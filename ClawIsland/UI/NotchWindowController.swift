import AppKit
import SwiftUI
import Combine

// Shared state: AppKit controller writes, SwiftUI view reads.
@MainActor
final class NotchViewModel: ObservableObject {
    @Published var expanded = false
    @Published var contentHeight: CGFloat = 0   // measured by SwiftUI, 0 = unknown yet
    @Published var collapsedHeight: CGFloat = 32 // real notch height; updated from safeAreaInsets
    @Published var notchWidth: CGFloat = 0       // hardware notch width; 0 on non-notch screens
    @Published var collapsedContentWidth: CGFloat = 220  // measured by SwiftUI, auto-sized
}

@MainActor
final class NotchWindowController: NSWindowController {
    private let sessionManager: SessionManager
    let viewModel = NotchViewModel()

    private var cancellables = Set<AnyCancellable>()
    private var collapseTask: Task<Void, Never>?
    private var mouseMonitor: Any?

    // Cached notch screen — never changes at runtime (only on display config change)
    private var notchScreen: NSScreen?

    // The frame we INTEND the window to occupy (used for hover hit-test,
    // so we compare against target rather than the mid-animation frame)
    private var targetFrame: CGRect = .zero

    // Notch geometry
    static let collapsedWidth: CGFloat    = 220
    static let collapsedHeight: CGFloat   = 32
    static let expandedWidth: CGFloat     = 520
    static let expandedMaxHeight: CGFloat = 480
    static let expandedMinHeight: CGFloat = 100   // shown while content is still measuring
    static let topBleed: CGFloat         = 6      // extra height above screen edge for seamless top

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
        let window = NotchWindow()
        super.init(window: window)

        notchScreen = Self.findNotchScreen()
        updateNotchGeometry()
        setupContentView()
        positionOnNotch(animated: false)

        // Force-expand for permission requests and notifications
        sessionManager.onAutoExpand = { [weak self] in
            guard let self else { return }
            // If this is an approval request, bring window to front so buttons are interactive.
            let hasApproval = sessionManager.sessions.contains {
                if case .waitingApproval = $0.status { return true }
                return false
            }
            if hasApproval {
                NSApp.activate(ignoringOtherApps: true)
                self.window?.makeKeyAndOrderFront(nil)
            }
            guard !viewModel.expanded else { return }
            withAnimation(.spring(response: 0.44, dampingFraction: 0.60)) {
                viewModel.expanded = true
            }
        }

        sessionManager.onAutoCollapse = { [weak self] in
            guard let self, viewModel.expanded else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                viewModel.expanded = false
            }
        }

        sessionManager.start()
        startMouseMonitor()

        // 有审批请求时自动收起展开面板
        sessionManager.$sessions
            .receive(on: RunLoop.main)
            .sink { [weak self] sessions in
                if sessions.isEmpty { self?.viewModel.expanded = false }
            }
            .store(in: &cancellables)

        // 常驻显示：启动后立即展示岛
        showPersistent()

        // Reposition when expand state changes, or content height is measured while expanded
        viewModel.$expanded
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.positionOnNotch(animated: true) }
            .store(in: &cancellables)

        viewModel.$contentHeight
            .receive(on: RunLoop.main)
            .filter { [weak self] _ in self?.viewModel.expanded == true }
            .removeDuplicates()
            .sink { [weak self] _ in self?.positionOnNotch(animated: true) }
            .store(in: &cancellables)

        // collapsedContentWidth = 最小 sideWidth（由 dots 宽度推算），session 数量变化时更新窗口
        viewModel.$collapsedContentWidth
            .receive(on: RunLoop.main)
            .filter { [weak self] _ in self?.viewModel.expanded == false }
            .removeDuplicates()
            .sink { [weak self] _ in self?.positionOnNotch(animated: true) }
            .store(in: &cancellables)

        // Re-cache screen when display configuration changes
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.notchScreen = Self.findNotchScreen()
                self?.updateNotchGeometry()
                self?.positionOnNotch(animated: false)
            }
            .store(in: &cancellables)
    }

    private func updateNotchGeometry() {
        let screen = notchScreen ?? NSScreen.main
        // Height from safeAreaInsets
        let inset = screen?.safeAreaInsets.top ?? 0
        viewModel.collapsedHeight = inset > 0 ? inset : Self.collapsedHeight
        // Width: screen width minus the two auxiliary strips flanking the notch
        if let screen,
           let left  = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            viewModel.notchWidth = max(screen.frame.width - left.width - right.width, 0)
        } else {
            viewModel.notchWidth = 0
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func debugLog(_ msg: String) {
        let line = "\(Date()) [NWC] \(msg)\n"
        if let data = line.data(using: .utf8) {
            let url = URL(fileURLWithPath: "/tmp/claw-island.log")
            if let fh = try? FileHandle(forWritingTo: url) {
                fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    deinit {
        // mouseMonitor removal done via NotificationCenter / lifecycle — safe to skip in deinit
    }

    // MARK: - Hover via global mouse monitor

    private func startMouseMonitor() {
        // Global monitor fires even when the app is not frontmost (.accessory policy)
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .mouseEntered, .mouseExited]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluateHover()
            }
        }
    }

    private func evaluateHover() {
        let mouse = NSEvent.mouseLocation
        // Compare against the TARGET frame, not the current (potentially mid-animation) frame
        let hovering = targetFrame.contains(mouse)

        let hasApproval = sessionManager.sessions.contains {
            if case .waitingApproval = $0.status { return true }
            return false
        }

        if hovering {
            collapseTask?.cancel()
            collapseTask = nil
            if !viewModel.expanded {
                withAnimation(.spring(response: 0.44, dampingFraction: 0.60)) {
                    viewModel.expanded = true
                }
            }
        } else if viewModel.expanded && !hasApproval {
            guard collapseTask == nil else { return }
            collapseTask = Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    viewModel.expanded = false
                }
                collapseTask = nil
            }
        }
    }

    // MARK: - Content

    private func setupContentView() {
        let root = NotchContentView()
            .environmentObject(sessionManager)
            .environmentObject(viewModel)
        let hv = NotchHostingView(rootView: root)
        hv.sizingOptions = []
        window?.contentView = hv
    }

    // MARK: - Visibility

    /// 岛常驻显示，启动时调用一次即可。
    private func showPersistent() {
        guard let window else { return }
        guard !window.isVisible || window.alphaValue == 0 else { return }
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            window.animator().alphaValue = 1
        }
    }

    // MARK: - Frame

    private func positionOnNotch(animated: Bool) {
        let screen = notchScreen ?? NSScreen.main
        guard let screen else { return }
        let sf = screen.frame
        let expanded = viewModel.expanded

        // collapsedContentWidth = 最小 sideWidth；窗口 = sideWidth × 2 + notch
        let collapsedW: CGFloat = {
            let side = viewModel.collapsedContentWidth > 0 ? viewModel.collapsedContentWidth : 90
            let notch = viewModel.notchWidth > 0 ? viewModel.notchWidth : 0
            return side * 2 + notch
        }()
        let w = expanded ? Self.expandedWidth : collapsedW
        let measured = viewModel.contentHeight
        let h: CGFloat = expanded
            ? min(max(measured > 0 ? measured : Self.expandedMinHeight, Self.expandedMinHeight),
                  Self.expandedMaxHeight)
            : viewModel.collapsedHeight

        let bleed = Self.topBleed
        let x = sf.minX + (sf.width - w) / 2
        let y = sf.maxY - h - bleed
        let newFrame = CGRect(x: x, y: y, width: w, height: h + bleed)
        targetFrame = CGRect(x: x, y: sf.maxY - h, width: w, height: h) // hover uses visible frame

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = expanded ? 0.52 : 0.32
                ctx.timingFunction = expanded
                    ? CAMediaTimingFunction(controlPoints: 0.20, 1.40, 0.36, 1.0)
                    : CAMediaTimingFunction(controlPoints: 0.40, 0.00, 0.20, 1.0)
                ctx.allowsImplicitAnimation = true
                window?.animator().setFrame(newFrame, display: true)
            }
        } else {
            window?.setFrame(newFrame, display: false)
        }
    }

    // MARK: - Screen detection

    private static func findNotchScreen() -> NSScreen? {
        // Prefer built-in display with hardware notch (safeAreaInsets.top > 0)
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
            ?? NSScreen.screens.first { $0.localizedName.lowercased().contains("built-in") }
            ?? NSScreen.main
    }
}

// MARK: - NotchWindow

final class NotchWindow: NSWindow {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        hasShadow = false
        ignoresMouseEvents = false
        alphaValue = 0
    }
}

// MARK: - NotchHostingView

final class NotchHostingView: NSHostingView<AnyView> {
    init<V: View>(rootView: V) {
        super.init(rootView: AnyView(rootView))
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
    required init(rootView: AnyView) { super.init(rootView: rootView) }

    // Non-activating panel windows don't forward clicks to subviews unless
    // acceptsFirstMouse returns true — without this, all buttons are dead.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
