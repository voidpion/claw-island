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
    // Layout: [左翼: AgentIcon 固定左 | dots 居中] [notch gap] [右翼: session count 居中]
    // 量 dots 自然宽度 → 推算最小 sideWidth → 窗口 = sideWidth × 2 + notchWidth

    private var compactBar: some View {
        let edgePad: CGFloat = 14
        // 左翼最小宽度 = edgePad(14) + icon(18) + 两侧 minSpacer(6+6) + dotsWidth
        let leftWingFixed: CGFloat = edgePad + 18 + 12  // 不含 dots，dots 单独量

        return HStack(spacing: 0) {
            // 左翼：AgentIcon 固定左，dots 在剩余空间居中
            HStack(spacing: 0) {
                AgentIcon(hasApproval: hasApprovalPending,
                          hasSessions: !sessionManager.sessions.isEmpty)
                    .padding(.leading, edgePad)
                Spacer(minLength: 6)
                HStack(spacing: 4) {
                    ForEach(sessionManager.sessions) { s in
                        StatusDot(session: s)
                    }
                }
                // 量 dots 宽度，推算 sideWidth 上报给 controller
                .background(GeometryReader { geo in
                    Color.clear.preference(
                        key: CollapsedWidthKey.self,
                        value: max(leftWingFixed + geo.size.width, 90)
                    )
                })
                Spacer(minLength: 6)
            }
            .frame(maxWidth: .infinity)

            // 硬件 notch 占位 — 无内容
            Color.clear.frame(width: viewModel.notchWidth > 0 ? viewModel.notchWidth : 0)

            // 右翼："N sessions" 水平居中
            let count = sessionManager.sessions.count
            (Text("\(count) ")
                .foregroundStyle(.white.opacity(0.55))
            + Text("session\(count == 1 ? "" : "s")")
                .foregroundStyle(.white.opacity(0.25)))
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .onPreferenceChange(CollapsedWidthKey.self) { minSide in
            if !viewModel.expanded {
                viewModel.collapsedContentWidth = minSide
            }
        }
    }

    // MARK: - Expanded panel

    private var expandedPanel: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)
                .padding(.horizontal, expandedBodyInset)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 1) {
                    ForEach(sessionManager.sessions) { session in
                        SessionRowView(session: session)
                            .environmentObject(sessionManager)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, expandedBodyInset)
                // Measure natural content height and report to controller
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ContentHeightKey.self,
                            value: geo.size.height
                                + 20                                           // vertical padding
                                + viewModel.collapsedHeight                    // compact bar
                        )
                    }
                )
            }
            .frame(maxHeight: NotchWindowController.expandedMaxHeight
                   - viewModel.collapsedHeight)
        }
        .onPreferenceChange(ContentHeightKey.self) { h in
            viewModel.contentHeight = h
        }
    }
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
        GeometryReader { geo in
            NotchPillShape(bottomRadius: bottomRadius)
                .fill(LinearGradient(
                    colors: [Color(white: 0.11), Color(white: 0.04)],
                    startPoint: .top, endPoint: .bottom
                ))
                .overlay(
                    NotchPillShape(bottomRadius: bottomRadius)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                )
                .frame(width: geo.size.width, height: geo.size.height)
        }
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
    @State private var pulse = false

    var body: some View {
        ZStack {
            if hasApproval {
                Circle()
                    .fill(Color.orange.opacity(pulse ? 0.28 : 0))
                    .frame(width: 18, height: 18)
            }
            Image(systemName: hasApproval ? "exclamationmark.shield.fill" : "waveform")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hasApproval ? Color.orange : Color.white.opacity(0.55))
                .symbolEffect(.variableColor.iterative.dimInactiveLayers,
                              isActive: hasSessions && !hasApproval)
        }
        .frame(width: 18, height: 18)
        .task(id: hasApproval) {
            if hasApproval {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            } else {
                withAnimation { pulse = false }
            }
        }
        .animation(.spring(response: 0.3), value: hasApproval)
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
