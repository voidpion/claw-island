import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 240),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Claw Island"
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .windowBackgroundColor
        super.init(window: panel)

        let rootView = SettingsContentView()
            .environmentObject(AppSettings.shared)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hostingView

        guard let contentView = panel.contentView else { return }
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func toggleSettings() {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            centerOnNotchScreen()
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func centerOnNotchScreen() {
        guard let screen = AppSettings.shared.resolveScreen() ?? NSScreen.main,
              let window else { return }
        let wx = screen.frame.midX - window.frame.width / 2
        let wy = screen.frame.midY - window.frame.height / 2
        window.setFrameOrigin(NSPoint(x: wx, y: wy))
    }
}
