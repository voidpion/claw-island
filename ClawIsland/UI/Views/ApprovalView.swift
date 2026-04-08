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
            if !formattedInput.isEmpty {
                Text(formattedInput)
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

    /// Format tool input based on tool type for cleaner display.
    private var formattedInput: String {
        let input = event.toolInput
        let cwd = session.cwd

        switch event.toolName {
        case "Bash":
            var parts: [String] = []
            if let desc = input["description"]?.description { parts.append(desc) }
            if let cmd  = input["command"]?.description     { parts.append(String(cmd.prefix(300))) }
            if !parts.isEmpty { return parts.joined(separator: "\n") }
        case "Read":
            // Show file path only
            if let path = input["file_path"]?.description {
                return stripCwd(path, cwd: cwd)
            }
        case "Write":
            // Show file path + first few lines of content
            if let path = input["file_path"]?.description {
                let clean = stripCwd(path, cwd: cwd)
                if let content = input["content"]?.description {
                    let preview = String(content.prefix(120))
                    return "\(clean)\n\(preview)"
                }
                return clean
            }
        case "Edit":
            // Show file path + old → new
            if let path = input["file_path"]?.description {
                let clean = stripCwd(path, cwd: cwd)
                var parts = [clean]
                if let old = input["old_string"]?.description {
                    parts.append("- \(String(old.prefix(80)))")
                }
                if let new = input["new_string"]?.description {
                    parts.append("+ \(String(new.prefix(80)))")
                }
                return parts.joined(separator: "\n")
            }
        case "Grep":
            if let pattern = input["pattern"]?.description {
                var result = "pattern: \(pattern)"
                if let glob = input["glob"]?.description {
                    result += "  glob: \(glob)"
                }
                return result
            }
        case "Glob":
            if let pattern = input["pattern"]?.description {
                return "pattern: \(pattern)"
            }
        case "Agent":
            if let desc = input["description"]?.description {
                return desc
            }
        case "WebFetch", "WebSearch":
            if let url = input["url"]?.description { return url }
            if let q = input["query"]?.description { return q }
        default:
            break
        }

        // Fallback: raw description, trimmed
        let raw = input.description
        if raw.hasPrefix("{") && raw.hasSuffix("}") {
            return String(raw.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return String(raw.prefix(240))
    }

    /// Strip cwd prefix from file paths for cleaner display.
    private func stripCwd(_ path: String, cwd: String?) -> String {
        guard let cwd, path.hasPrefix(cwd + "/") else { return path }
        return String(path.dropFirst(cwd.count + 1))
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
