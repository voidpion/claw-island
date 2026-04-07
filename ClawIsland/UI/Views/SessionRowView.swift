import SwiftUI

struct SessionRowView: View {
    @ObservedObject var session: Session
    @EnvironmentObject var sessionManager: SessionManager
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainRow
                .padding(.vertical, 8)
                .padding(.horizontal, 10)

            // Inline approval panel — inside the same card
            if case .waitingApproval(let event) = session.status {
                Divider().overlay(Color.white.opacity(0.06)).padding(.horizontal, 10)
                ApprovalView(event: event, session: session)
                    .transition(
                        .asymmetric(
                            insertion: .push(from: .top).combined(with: .opacity),
                            removal:   .opacity
                        )
                    )
            }
        }
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovered = $0 }
        .onTapGesture { sessionManager.focusWindow(for: session) }
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
        HStack(alignment: .top, spacing: 10) {
            SessionAvatar(session: session)

            VStack(alignment: .leading, spacing: 2) {
                // Title line
                Text(session.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)

                // Last user prompt
                if let prompt = session.lastUserPrompt {
                    Text("You: \(prompt)")
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }

                // Status line
                if let sub = session.subtitle {
                    Text(sub)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(statusColor.opacity(0.75))
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeOut(duration: 0.2), value: session.subtitle)

            Spacer(minLength: 4)

            // Right badges: model + time
            VStack(alignment: .trailing, spacing: 4) {
                if let model = session.model {
                    Text(model)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
                Text(session.elapsedTime)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.28))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Capsule())
            }
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .idle:            return .white.opacity(0.3)
        case .running:         return Color(red: 0.35, green: 0.6, blue: 1.0)
        case .waitingApproval: return .orange
        case .notifying:       return Color(red: 0.7, green: 0.4, blue: 1.0)
        case .compacting:      return Color(red: 0.9, green: 0.8, blue: 0.2)
        case .completed:       return Color(red: 0.2, green: 0.9, blue: 0.5)
        case .failed:          return Color(red: 1.0, green: 0.35, blue: 0.35)
        }
    }

    private var isWaiting: Bool {
        if case .waitingApproval = session.status { return true }
        return false
    }
}

// MARK: - Session Avatar

private struct SessionAvatar: View {
    @ObservedObject var session: Session
    @State private var pulse = false
    @State private var frame = 0

    private var statusColor: Color {
        switch session.status {
        case .idle:            return .white.opacity(0.2)
        case .running:         return Color(red: 0.35, green: 0.6, blue: 1.0)
        case .waitingApproval: return .orange
        case .notifying:       return Color(red: 0.7, green: 0.4, blue: 1.0)
        case .compacting:      return Color(red: 0.9, green: 0.8, blue: 0.2)
        case .completed:       return Color(red: 0.2, green: 0.9, blue: 0.5)
        case .failed:          return Color(red: 1.0, green: 0.35, blue: 0.35)
        }
    }

    private var isActive: Bool {
        if case .running = session.status { return true }
        if case .waitingApproval = session.status { return true }
        return false
    }

    var body: some View {
        let lines = BuddyArt.frames[session.buddyIndex][frame]

        ZStack {
            // 仅 active 状态保留一个模糊光晕，无矩形框
            if isActive {
                Circle()
                    .fill(statusColor.opacity(pulse ? 0.18 : 0))
                    .blur(radius: 5)
                    .frame(width: 32, height: 32)
            }

            // ASCII buddy — 4 行 monospaced
            Text(lines.joined(separator: "\n"))
                .font(.system(size: 7, design: .monospaced))
                .foregroundStyle(statusColor.opacity(0.9))
                .fixedSize()
                .animation(.easeInOut(duration: 0.12), value: frame)
        }
        .frame(width: 38, height: 42)
        .task(id: isActive) {
            if isActive {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            } else {
                withAnimation { pulse = false }
            }
        }
        .task {
            while !Task.isCancelled {
                let interval: UInt64 = isActive ? 600_000_000 : 1_400_000_000
                try? await Task.sleep(nanoseconds: interval)
                frame = (frame + 1) % 3
            }
        }
        .animation(.spring(response: 0.3), value: session.status.discriminator)
    }

}

// MARK: - Discriminator for animation keying

extension SessionStatus {
    var discriminator: Int {
        switch self {
        case .idle:            return 0
        case .running:         return 1
        case .waitingApproval: return 2
        case .notifying:       return 3
        case .compacting:      return 4
        case .completed:       return 5
        case .failed:          return 6
        }
    }
}
