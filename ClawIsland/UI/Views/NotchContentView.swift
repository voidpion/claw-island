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

    var body: some View {
        ZStack(alignment: .top) {
            NotchPill(expanded: viewModel.expanded)

            VStack(spacing: 0) {
                compactBar
                    .frame(height: viewModel.collapsedHeight)

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

    private var compactBar: some View {
        HStack(spacing: 6) {
            AgentIcon(hasApproval: hasApprovalPending,
                      hasSessions: !sessionManager.sessions.isEmpty)

            HStack(spacing: 4) {
                ForEach(sessionManager.sessions) { s in
                    StatusDot(session: s)
                }
            }

            if let msg = featuredCompactMessage {
                Text(msg)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: msg)
            }

            Spacer(minLength: 0)

            let count = sessionManager.sessions.count
            if count > 0 {
                Text(count == 1 ? "1 session" : "\(count) sessions")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
    }

    private var featuredCompactMessage: String? {
        sessionManager.sessions
            .max(by: { $0.statusPriority < $1.statusPriority })
            .flatMap { $0.compactMessage }
    }

    // MARK: - Expanded panel

    private var expandedPanel: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)
                .padding(.horizontal, 16)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 1) {
                    ForEach(sessionManager.sessions) { session in
                        SessionRowView(session: session)
                            .environmentObject(sessionManager)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
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

// MARK: - Pill background

private struct NotchPill: View {
    let expanded: Bool
    private var bottomRadius: CGFloat { expanded ? 20 : 12 }
    private let outerRadius: CGFloat = 10  // top outer (concave) corners

    var body: some View {
        GeometryReader { geo in
            NotchPillShape(bottomRadius: bottomRadius, outerTopRadius: outerRadius)
                .fill(LinearGradient(
                    colors: [Color(white: 0.11), Color(white: 0.04)],
                    startPoint: .top, endPoint: .bottom
                ))
                .overlay(
                    NotchPillShape(bottomRadius: bottomRadius, outerTopRadius: outerRadius)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                )
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Notch pill shape
// Top corners: outer/concave (arc center at corner point, curves outward into notch hardware).
// Bottom corners: inner/convex standard rounded corners.
// The outer top arcs extend above y=0 — the window clips them at the screen edge,
// creating a seamless "pulled down from notch" effect on notch Macs.

private struct NotchPillShape: Shape & InsettableShape {
    var bottomRadius: CGFloat
    var outerTopRadius: CGFloat
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> NotchPillShape {
        var s = self; s.insetAmount += amount; return s
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let w = r.width, h = r.height
        let x = r.minX, y = r.minY
        let br = min(bottomRadius - insetAmount, min(w, h) / 2)
        let or = max(outerTopRadius + insetAmount, 0)

        var p = Path()
        // Top edge (between the two outer corner tangent points)
        p.move(to: CGPoint(x: x + or, y: y))
        p.addLine(to: CGPoint(x: x + w - or, y: y))

        // Top-right outer corner: center at (x+w, y), arc from 180° to 90° clockwise on screen
        p.addArc(center: CGPoint(x: x + w, y: y),
                 radius: or,
                 startAngle: .degrees(180), endAngle: .degrees(90),
                 clockwise: true)

        // Right edge → bottom-right inner corner
        p.addLine(to: CGPoint(x: x + w, y: y + h - br))
        p.addArc(center: CGPoint(x: x + w - br, y: y + h - br),
                 radius: br,
                 startAngle: .degrees(0), endAngle: .degrees(90),
                 clockwise: false)

        // Bottom edge → bottom-left inner corner
        p.addLine(to: CGPoint(x: x + br, y: y + h))
        p.addArc(center: CGPoint(x: x + br, y: y + h - br),
                 radius: br,
                 startAngle: .degrees(90), endAngle: .degrees(180),
                 clockwise: false)

        // Left edge → top-left outer corner: center at (x, y), arc from 90° to 0° counter-clockwise on screen
        p.addLine(to: CGPoint(x: x, y: y + or))
        p.addArc(center: CGPoint(x: x, y: y),
                 radius: or,
                 startAngle: .degrees(90), endAngle: .degrees(0),
                 clockwise: false)

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
        case .running:         return Color(red: 0.2, green: 0.9, blue: 0.5)
        case .waitingApproval: return .orange
        case .notifying:       return Color(red: 0.7, green: 0.4, blue: 1.0)
        case .compacting:      return Color(red: 0.9, green: 0.8, blue: 0.2)
        case .completed:       return Color(red: 0.35, green: 0.6, blue: 1.0)
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
