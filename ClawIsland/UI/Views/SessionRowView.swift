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

            // Inline approval panel — 只有 activeApprovalId 匹配时才展开
            if case .waitingApproval(let event) = session.status,
               sessionManager.activeApprovalId == session.id {
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

            // Right badges: queued approval indicator + model + time
            VStack(alignment: .trailing, spacing: 4) {
                // 排队等待角标：waiting 但不是当前 active
                if isQueuedApproval {
                    HStack(spacing: 3) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 8))
                        Text("待审批")
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.orange.opacity(0.3), lineWidth: 0.5))
                }
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

    // waiting 且是当前 active — 用于 animation keying
    private var isWaiting: Bool {
        if case .waitingApproval = session.status {
            return sessionManager.activeApprovalId == session.id
        }
        return false
    }

    // waiting 但排在队列里（非 active）
    private var isQueuedApproval: Bool {
        if case .waitingApproval = session.status {
            return sessionManager.activeApprovalId != session.id
        }
        return false
    }
}

// MARK: - Session Avatar

private struct SessionAvatar: View {
    @ObservedObject var session: Session
    @State private var pulse = false
    @State private var frame = 0

    private var charIndex: Int { session.buddyIndex }

    private var statusColor: Color {
        switch session.status {
        case .idle:            return .white.opacity(0.35)
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
            // 光晕 — 像素图形状的模糊副本，active 时呼吸
            BuddyCanvas(charIndex: charIndex, frame: frame, color: statusColor)
                .frame(width: 24, height: 24)
                .blur(radius: pulse ? 10 : 5)
                .opacity(pulse ? 1.0 : (isActive ? 0.6 : 0.3))
                .scaleEffect(pulse ? 1.3 : 1.0)

            // 精灵本体
            BuddyCanvas(charIndex: charIndex, frame: frame, color: statusColor)
                .frame(width: 24, height: 24)
        }
        .frame(width: 32, height: 32)
        .task(id: isActive) {
            if isActive {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.4)) { pulse = false }
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: isActive ? 500_000_000 : 1_200_000_000)
                frame = (frame + 1) % 3
            }
        }
        .animation(.spring(response: 0.3), value: session.status.discriminator)
    }
}

// MARK: - Pixel sprite canvas

private struct BuddyCanvas: View {
    let charIndex: Int
    let frame: Int
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard charIndex < BuddyPixels.frames.count,
                  frame < BuddyPixels.frames[charIndex].count else { return }
            let frameData = BuddyPixels.frames[charIndex][frame]
            let pw = size.width  / CGFloat(BuddyPixels.cols)
            let ph = size.height / CGFloat(BuddyPixels.rows)
            for (row, mask) in frameData.enumerated() {
                for col in 0..<BuddyPixels.cols {
                    guard (mask >> UInt8(7 - col)) & 1 == 1 else { continue }
                    let rect = CGRect(x: CGFloat(col) * pw, y: CGFloat(row) * ph,
                                     width: pw, height: ph)
                    context.fill(Path(rect), with: .color(color))
                }
            }
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
