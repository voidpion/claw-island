import SwiftUI

struct NotchContentView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var viewModel: NotchViewModel

    private var hasApprovalPending: Bool {
        sessionManager.sessions.contains {
            if case .waitingApproval = $0.status { return true }
            return false
        }
    }

    /// 底角半径：顶角已改为直角，此值只控制底部圆角大小。
    private var bodyRadius: CGFloat { viewModel.expanded ? 20 : 16 }

    /// 展开面板水平内边距，与 compactBar 的 edgePad 对齐。
    /// 顶角已改为直角 + clipShape 兜底，无需再根据 bodyRadius 留避让空间。
    private var expandedBodyInset: CGFloat { 14 }

    var body: some View {
        ZStack(alignment: .top) {
            NotchPill(expanded: viewModel.expanded)

            VStack(spacing: 0) {
                compactBar
                    .frame(maxWidth: .infinity)
                    .frame(height: viewModel.collapsedHeight + 6, alignment: .center)

                if viewModel.expanded {
                    // 渐隐分隔线：两端透明，中间白色细线
                    Rectangle()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear,              location: 0.0),
                                    .init(color: .white.opacity(0.10), location: 0.18),
                                    .init(color: .white.opacity(0.10), location: 0.82),
                                    .init(color: .clear,              location: 1.0),
                                ],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(height: 0.5)
                        .transition(.opacity)

                    expandedPanel
                        .transition(
                            .asymmetric(
                                insertion: .push(from: .top).combined(with: .opacity),
                                removal:   .opacity
                            )
                        )
                }
            }
            .clipShape(NotchPillShape(bottomRadius: bodyRadius))
        }
        // Auto-expand on approval — controller also does this, belt-and-suspenders
        .onChange(of: hasApprovalPending) { _, pending in
            if pending && !viewModel.expanded {
                withAnimation(.spring(response: 0.44, dampingFraction: 0.60)) {
                    viewModel.expanded = true
                }
            }
        }
        .animation(.spring(response: 0.44, dampingFraction: 0.60), value: viewModel.expanded)
    }

    // MARK: - Compact bar
    // Layout: [左翼: AgentIcon 居中] [notch gap] [右翼: dots 居中]
    // 两翼等宽，由 dots 自然宽度 + 内边距推算 sideWidth → 窗口 = sideWidth × 2 + notchWidth

    private var compactBar: some View {
        let edgePad: CGFloat = 14

        return HStack(spacing: 0) {
            // 左翼：AgentIcon 居中
            AgentIcon(hasApproval: hasApprovalPending,
                      hasSessions: !sessionManager.sessions.isEmpty,
                      expanded: viewModel.expanded)
                .frame(maxWidth: .infinity)

            // 硬件 notch 占位
            Color.clear.frame(width: viewModel.notchWidth > 0 ? viewModel.notchWidth : 0)

            // 右翼：dots 居中，量宽推算 sideWidth
            HStack(spacing: 4) {
                ForEach(sessionManager.sessions) { s in
                    StatusDot(session: s)
                }
            }
            .background(GeometryReader { geo in
                Color.clear.preference(
                    key: CollapsedWidthKey.self,
                    value: max(geo.size.width + edgePad * 2, 36 + edgePad * 2)
                )
            })
            .frame(maxWidth: .infinity)
        }
        .onPreferenceChange(CollapsedWidthKey.self) { sideWidth in
            if !viewModel.expanded {
                viewModel.collapsedContentWidth = sideWidth
            }
        }
    }

    // MARK: - Expanded panel

    private var expandedPanel: some View {
        let topPad: CGFloat = 10
        let botPad: CGFloat = 6   // 底角 br=16 视觉上已有空间感，少留一点
        let gearReserve: CGFloat = 24  // 为右下角齿轮按钮预留空间
        return VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 1) {
                    ForEach(sessionManager.sessions) { session in
                        SessionRowView(session: session)
                            .environmentObject(sessionManager)
                    }
                }
                .padding(.top, topPad)
                .padding(.bottom, botPad + gearReserve)
                .padding(.horizontal, expandedBodyInset)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ContentHeightKey.self,
                            value: geo.size.height
                                + topPad + botPad
                                + viewModel.collapsedHeight
                        )
                    }
                )
            }
            .frame(maxHeight: NotchWindowController.expandedMaxHeight
                   - viewModel.collapsedHeight)
        }
        .overlay(alignment: .bottomTrailing) {
            gearButton
                .padding(.trailing, expandedBodyInset - 2)
                .padding(.bottom, expandedBodyInset - 2)
        }
        .onPreferenceChange(ContentHeightKey.self) { h in
            viewModel.contentHeight = h
        }
    }

    // MARK: - Gear button

    private var gearButton: some View {
        Button {
            viewModel.onOpenSettings?()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(gearHovered ? 0.6 : 0.25))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            withAnimation(.easeOut(duration: 0.12)) {
                gearHovered = hovered
            }
        }
    }

    @State private var gearHovered = false
}

// MARK: - Preference keys

private struct CollapsedWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Pill background

private struct NotchPill: View {
    let expanded: Bool
    private var bottomRadius: CGFloat { expanded ? 20 : 12 }

    var body: some View {
        NotchPillShape(bottomRadius: bottomRadius)
            .fill(Color.black)
            .overlay(
                NotchPillShape(bottomRadius: bottomRadius)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
            )
    }
}

// MARK: - Notch pill shape
// Top edge = full width, top corners = square (flush with screen edge).
// Bottom corners: convex rounded corners, radius `br`.

private struct NotchPillShape: Shape & InsettableShape {
    var bottomRadius: CGFloat
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> NotchPillShape {
        var s = self; s.insetAmount += amount; return s
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let w = r.width, h = r.height
        let x = r.minX, y = r.minY
        let br = min(bottomRadius - insetAmount, min(w, h) / 2)

        var p = Path()

        // 顶边 — 直角，与屏幕边缘齐平
        p.move(to: CGPoint(x: x, y: y))
        p.addLine(to: CGPoint(x: x + w, y: y))

        // 右边 → 右下圆角
        p.addLine(to: CGPoint(x: x + w, y: y + h - br))
        p.addArc(center: CGPoint(x: x + w - br, y: y + h - br),
                 radius: br,
                 startAngle: .degrees(0), endAngle: .degrees(90),
                 clockwise: false)

        // 底边 → 左下圆角
        p.addLine(to: CGPoint(x: x + br, y: y + h))
        p.addArc(center: CGPoint(x: x + br, y: y + h - br),
                 radius: br,
                 startAngle: .degrees(90), endAngle: .degrees(180),
                 clockwise: false)

        // 左边回到起点
        p.addLine(to: CGPoint(x: x, y: y))

        p.closeSubpath()
        return p
    }
}

// MARK: - Agent icon

private struct AgentIcon: View {
    let hasApproval: Bool
    let hasSessions: Bool
    let expanded: Bool

    @State private var frame = 0
    @State private var patrolOffset: CGFloat = 0
    @State private var facingRight  = true
    @State private var availableWidth: CGFloat = 36

    // 巡逻最大偏移：图标边缘与容器边缘保持 edgePad(14pt) 对齐
    // maxPatrol = availableWidth/2 - mascotWidth/2 - edgePad = availableWidth/2 - 18 - 14
    private var maxPatrol: CGFloat {
        max(0, availableWidth / 2 - 32)
    }

    private var iconColor: Color {
        hasApproval
            ? Color.orange
            : (hasSessions ? Color.white.opacity(0.85) : Color.white.opacity(0.35))
    }

    var body: some View {
        // GeometryReader 填满父级宽度（外部 .frame(maxWidth:.infinity) 决定）
        GeometryReader { geo in
            MascotCanvas(frame: frame, color: iconColor)
                .frame(width: 36, height: 24)
                .scaleEffect(x: facingRight ? 1 : -1, y: 1)  // 面朝行进方向
                .frame(width: 36, height: 32)
                .position(x: geo.size.width / 2 + patrolOffset, y: 16)
                .onAppear { availableWidth = geo.size.width }
                .onChange(of: geo.size.width) { _, w in availableWidth = w }
        }
        .frame(height: 32)
        // 巡逻任务：expanded & !hasApproval 时来回走，否则回中心
        .task(id: "\(expanded)_\(hasApproval)") {
            guard expanded && !hasApproval else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
                    patrolOffset = 0
                }
                return
            }
            // 等 GeometryReader 上报实际宽度
            try? await Task.sleep(nanoseconds: 50_000_000)
            while !Task.isCancelled {
                guard maxPatrol > 2 else {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    continue
                }
                let target: CGFloat = facingRight ? maxPatrol : -maxPatrol
                let distance = abs(target - patrolOffset)
                let duration = max(0.3, Double(distance) / 22.0)  // 22pt/s 匀速步行
                withAnimation(.linear(duration: duration)) {
                    patrolOffset = target
                }
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                guard !Task.isCancelled else { break }
                try? await Task.sleep(nanoseconds: 240_000_000)   // 边缘停顿
                guard !Task.isCancelled else { break }
                facingRight.toggle()
            }
        }
        // 帧动画：展开时加快腿部步频
        .task(id: "\(hasSessions)_\(expanded)") {
            while !Task.isCancelled {
                let ns: UInt64 = !hasSessions ? 1_200_000_000
                    : (expanded ? 220_000_000 : 380_000_000)
                try? await Task.sleep(nanoseconds: ns)
                frame = (frame + 1) % 3
            }
        }
        .animation(.spring(response: 0.3), value: hasApproval)
    }
}

// MARK: - Mascot Canvas

private struct MascotCanvas: View {
    let frame: Int
    let color: Color

    private static let cols = 18
    private static let rows = 6

    // 3帧像素数据，18列 × 6行，UInt32 bitmask，bit17 = 最左列
    // 源自块字符：行0-1=头部，行2-3=身体，行4-5=腿（帧间交替）
    private static let frames: [[UInt32]] = [
        [0x7FF8, 0x6FD8, 0x1FFFE, 0x7FF8, 0x2850, 0],  // 帧0：双腿落地 ▘▘ ▝▝
        [0x7FF8, 0x6FD8, 0x1FFFE, 0x7FF8, 0x1890, 0],  // 帧1：交替 A   ▝▘ ▘▝
        [0x7FF8, 0x6FD8, 0x1FFFE, 0x7FF8, 0x2460, 0],  // 帧2：交替 B   ▘▝ ▝▘
    ]

    var body: some View {
        Canvas { context, size in
            guard frame < MascotCanvas.frames.count else { return }
            let rowData = MascotCanvas.frames[frame]
            let pw = size.width  / CGFloat(MascotCanvas.cols)
            let ph = size.height / CGFloat(MascotCanvas.rows)
            for (row, mask) in rowData.enumerated() {
                for col in 0..<MascotCanvas.cols {
                    guard (mask >> UInt32(17 - col)) & 1 == 1 else { continue }
                    let rect = CGRect(x: CGFloat(col) * pw, y: CGFloat(row) * ph,
                                     width: pw, height: ph)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
    }
}

// MARK: - Status dot

struct StatusDot: View {
    @ObservedObject var session: Session
    @State private var pulse = false

    private var dotColor: Color {
        switch session.status {
        case .idle:            return .white.opacity(0.28)
        case .running:         return Color(red: 0.35, green: 0.6, blue: 1.0)
        case .waitingApproval: return .orange
        case .notifying:       return Color(red: 0.7, green: 0.4, blue: 1.0)
        case .compacting:      return Color(red: 0.9, green: 0.8, blue: 0.2)
        case .completed:       return Color(red: 0.2, green: 0.9, blue: 0.5)
        case .failed:          return Color(red: 1.0, green: 0.35, blue: 0.35)
        }
    }

    private var isRunning: Bool {
        if case .running = session.status { return true }
        return false
    }

    var body: some View {
        ZStack {
            if isRunning {
                Circle()
                    .fill(dotColor.opacity(pulse ? 0.35 : 0))
                    .frame(width: 12, height: 12)
            }
            Circle().fill(dotColor).frame(width: 6, height: 6)
        }
        .frame(width: 12, height: 12)
        .task(id: isRunning) {
            if isRunning {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            } else {
                withAnimation { pulse = false }
            }
        }
        .animation(.spring(response: 0.28), value: dotColor.description)
    }
}
