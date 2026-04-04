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

    /// The shape's body is inset by `br` on each side from the window edge.
    /// Content must use at least this much horizontal padding to stay inside the body.
    private var bodyRadius: CGFloat { viewModel.expanded ? 20 : 12 }

    /// Horizontal inset for expanded body content (rows, dividers).
    /// Must be > bodyRadius so rows stay clearly inside the shape body with breathing room.
    private var expandedBodyInset: CGFloat { bodyRadius + 6 }

    var body: some View {
        ZStack(alignment: .top) {
            NotchPill(expanded: viewModel.expanded)

            VStack(spacing: 0) {
                compactBar
                    .frame(height: viewModel.collapsedHeight + 6, alignment: .center)
                    .clipped()

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
    // Layout: [left: icon + dots] [center gap = notch] [right: message + count]

    private var compactBar: some View {
        let edgePad: CGFloat = viewModel.expanded ? 24 : 14
        return HStack(spacing: 0) {
            // Left wing — shrink to content
            HStack(spacing: 6) {
                AgentIcon(hasApproval: hasApprovalPending,
                          hasSessions: !sessionManager.sessions.isEmpty)
                HStack(spacing: 4) {
                    ForEach(sessionManager.sessions) { s in
                        StatusDot(session: s)
                    }
                }
            }
            .padding(.leading, edgePad)

            // Center gap — the hardware notch lives here, no content
            if viewModel.notchWidth > 0 {
                Spacer(minLength: 0).frame(width: viewModel.notchWidth)
            }

            Spacer(minLength: 4)

            // Right wing — shrink to content
            let count = sessionManager.sessions.count
            (Text("\(count) ")
                .foregroundStyle(.white.opacity(0.55))
            + Text("session\(count == 1 ? "" : "s")")
                .foregroundStyle(.white.opacity(0.25)))
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .padding(.trailing, edgePad)
        }
        // Measure collapsed content width and report to controller
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: CollapsedWidthKey.self,
                    value: geo.size.width
                )
            }
        )
        .onPreferenceChange(CollapsedWidthKey.self) { w in
            viewModel.collapsedContentWidth = w
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

// MARK: - Preference key

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct CollapsedWidthKey: PreferenceKey {
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
// Top edge = full width (widest).
// Top corners: concave quadratic bezier — same radius `br` as bottom corners.
// Bottom corners: standard inner rounded corners (convex, radius `br`).
// Top and bottom use identical `br` so the curves are visual mirrors.

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

        // Start at top-left corner
        p.move(to: CGPoint(x: x, y: y))

        // Top edge — full width
        p.addLine(to: CGPoint(x: x + w, y: y))

        // Top-right concave: (x+w, y) → (x+w-br, y+br), control (x+w-br, y)
        p.addQuadCurve(
            to:      CGPoint(x: x + w - br, y: y + br),
            control: CGPoint(x: x + w - br, y: y)
        )

        // Right body edge → bottom-right inner corner
        p.addLine(to: CGPoint(x: x + w - br, y: y + h - br))
        p.addArc(center: CGPoint(x: x + w - 2 * br, y: y + h - br),
                 radius: br,
                 startAngle: .degrees(0), endAngle: .degrees(90),
                 clockwise: false)

        // Bottom edge → bottom-left inner corner
        p.addLine(to: CGPoint(x: x + 2 * br, y: y + h))
        p.addArc(center: CGPoint(x: x + 2 * br, y: y + h - br),
                 radius: br,
                 startAngle: .degrees(90), endAngle: .degrees(180),
                 clockwise: false)

        // Left body edge up to the concave curve start
        p.addLine(to: CGPoint(x: x + br, y: y + br))

        // Top-left concave: (x+br, y+br) → (x, y), control (x+br, y)
        p.addQuadCurve(
            to:      CGPoint(x: x, y: y),
            control: CGPoint(x: x + br, y: y)
        )

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
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                            pulse = true
                        }
                    }
                    .onDisappear { pulse = false }
            }
            Image(systemName: hasApproval ? "exclamationmark.shield.fill" : "waveform")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hasApproval ? Color.orange : Color.white.opacity(0.55))
                .symbolEffect(.variableColor.iterative.dimInactiveLayers,
                              isActive: hasSessions && !hasApproval)
        }
        .frame(width: 18, height: 18)
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
        .onAppear {
            guard isRunning else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onChange(of: isRunning) { _, running in
            if running {
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
