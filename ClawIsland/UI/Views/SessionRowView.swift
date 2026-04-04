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
        ZStack {
            // Pulsing halo for active states
            if isActive {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(statusColor.opacity(pulse ? 0.22 : 0))
                    .frame(width: 34, height: 34)
            }

            // Background
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .frame(width: 28, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(statusColor.opacity(0.6), lineWidth: 1.5)
                )

            // Icon
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(statusColor)
                .symbolEffect(.variableColor.iterative.dimInactiveLayers,
                              isActive: isActive)
        }
        .frame(width: 34, height: 34)
        .onAppear {
            guard isActive else { return }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            } else {
                withAnimation { pulse = false }
            }
        }
        .animation(.spring(response: 0.3), value: session.status.discriminator)
    }

    private var iconName: String {
        switch session.status {
        case .idle:            return "waveform"
        case .running:         return "bolt.fill"
        case .waitingApproval: return "exclamationmark.shield.fill"
        case .notifying:       return "bell.fill"
        case .compacting:      return "arrow.triangle.2.circlepath"
        case .completed:       return "checkmark"
        case .failed:          return "xmark"
        }
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
