import SwiftUI

struct SessionRowView: View {
    @ObservedObject var session: Session
    @EnvironmentObject var sessionManager: SessionManager
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainRow
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
                .background(rowBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onHover { hovered = $0 }

            // Inline approval panel slides in below the row
            if case .waitingApproval(let event) = session.status {
                ApprovalView(event: event, session: session)
                    .padding(.top, 3)
                    .transition(
                        .asymmetric(
                            insertion: .push(from: .top).combined(with: .opacity),
                            removal:   .opacity
                        )
                    )
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.76), value: isWaiting)
    }

    // MARK: - Row background

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(hovered ? Color.white.opacity(0.07) : Color.white.opacity(0.03))
            .animation(.easeOut(duration: 0.15), value: hovered)
    }

    // MARK: - Main row content

    private var mainRow: some View {
        HStack(spacing: 8) {
            StatusDot(session: session)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.title)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)

                if let sub = session.subtitle {
                    Text(sub)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeOut(duration: 0.2), value: session.subtitle)

            Spacer(minLength: 4)

            // Elapsed time badge
            Text(session.elapsedTime)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
        }
    }

    private var isWaiting: Bool {
        if case .waitingApproval = session.status { return true }
        return false
    }
}
