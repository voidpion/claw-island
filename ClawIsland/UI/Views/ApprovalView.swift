import SwiftUI

struct ApprovalView: View {
    let event: PermissionRequestEvent
    let session: Session
    @EnvironmentObject var sessionManager: SessionManager
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ── Header ──────────────────────────────────────────────
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.orange)
                Text("Permission Request")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange.opacity(0.9))
                Spacer()
                // Tool name pill on the right
                Text(event.toolName)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }

            // ── Input preview ────────────────────────────────────────
            if !inputSummary.isEmpty {
                Text(inputSummary)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                    )
            }

            // ── Buttons ──────────────────────────────────────────────
            HStack(spacing: 6) {
                ApprovalButton(label: "Deny", color: Color(red: 1.0, green: 0.35, blue: 0.35)) {
                    sessionManager.deny(session: session)
                }
                ApprovalButton(label: "Allow", color: Color(red: 0.15, green: 0.8, blue: 0.45)) {
                    sessionManager.approve(session: session)
                }
                if let suggestions = event.permissionSuggestions, !suggestions.isEmpty {
                    ApprovalButton(label: "Always Allow", color: Color(red: 0.25, green: 0.6, blue: 0.95)) {
                        sessionManager.approve(session: session, updatedPermissions: suggestions)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.2), lineWidth: 0.5)
                )
        )
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.96, anchor: .top)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }

    private var inputSummary: String {
        let raw = event.toolInput.description
        // Strip outer braces for cleaner display
        if raw.hasPrefix("{") && raw.hasSuffix("}") {
            return String(raw.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return String(raw.prefix(240))
    }
}

// MARK: - Approval button

private struct ApprovalButton: View {
    let label: String
    let color: Color
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(color.opacity(pressed ? 0.5 : 0.75))
                )
                .scaleEffect(pressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .pressEvents(onPress: { pressed = true }, onRelease: { pressed = false })
        .animation(.easeOut(duration: 0.1), value: pressed)
    }
}

// MARK: - Press event helper

private extension View {
    func pressEvents(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onPress() }
                .onEnded   { _ in onRelease() }
        )
    }
}
