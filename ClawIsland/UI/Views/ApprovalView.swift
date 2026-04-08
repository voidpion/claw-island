import SwiftUI

struct ApprovalView: View {
    let event: PermissionRequestEvent
    let session: Session
    @EnvironmentObject var sessionManager: SessionManager
    @State private var appeared = false

    var body: some View {
        Group {
            if event.toolName == "AskUserQuestion" {
                AskUserQuestionView(event: event, session: session)
            } else {
                permissionView
            }
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.96, anchor: .top)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }

    // ── 普通 Permission Request ──────────────────────────────────

    private var permissionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.orange)
                Text("Permission Request")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange.opacity(0.9))
                Spacer()
                Text(event.toolName)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }

            // Input preview
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

            // Buttons
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

// MARK: - AskUserQuestion View

private struct AskUserQuestionView: View {
    let event: PermissionRequestEvent
    let session: Session
    @EnvironmentObject var sessionManager: SessionManager

    // 解析后的题目
    private struct QData: Identifiable {
        let id: Int
        let question: String
        let header: String
        let multiSelect: Bool
        let options: [(label: String, description: String)]
    }

    // 单选：[题目index → 选项index]；多选：[题目index → Set<选项index>]
    @State private var single: [Int: Int] = [:]
    @State private var multi:  [Int: Set<Int>] = [:]

    private var questions: [QData] {
        guard case .array(let qs) = event.toolInput["questions"] else { return [] }
        return qs.enumerated().compactMap { i, q in
            guard let question = q["question"]?.description,
                  let header   = q["header"]?.description else { return nil }
            let ms: Bool
            if case .bool(let b) = q["multiSelect"] { ms = b } else { ms = false }
            var opts: [(String, String)] = []
            if case .array(let arr) = q["options"] {
                opts = arr.compactMap { o in
                    guard let label = o["label"]?.description else { return nil }
                    return (label, o["description"]?.description ?? "")
                }
            }
            return QData(id: i, question: question, header: header, multiSelect: ms, options: opts)
        }
    }

    private var canSubmit: Bool {
        questions.allSatisfy { q in
            q.multiSelect ? !(multi[q.id]?.isEmpty ?? true) : single[q.id] != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 5) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.4, green: 0.6, blue: 1.0))
                Text("Claude 需要你回答")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 0.4, green: 0.6, blue: 1.0).opacity(0.9))
                Spacer()
                Text("AskUserQuestion")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
            }

            // 每道题
            ForEach(questions) { q in
                VStack(alignment: .leading, spacing: 5) {
                    // 题目标题
                    HStack(spacing: 5) {
                        Text(q.header)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.07))
                            .clipShape(Capsule())
                        Text(q.question)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(2)
                    }
                    // 选项列表
                    VStack(spacing: 3) {
                        ForEach(Array(q.options.enumerated()), id: \.offset) { j, opt in
                            let selected = q.multiSelect
                                ? (multi[q.id]?.contains(j) ?? false)
                                : (single[q.id] == j)
                            OptionRow(label: opt.label, description: opt.description, selected: selected) {
                                if q.multiSelect {
                                    var s = multi[q.id] ?? []
                                    if s.contains(j) { s.remove(j) } else { s.insert(j) }
                                    multi[q.id] = s
                                } else {
                                    single[q.id] = j
                                }
                            }
                        }
                    }
                }
            }

            // 提交按钮
            ApprovalButton(
                label: "提交",
                color: canSubmit
                    ? Color(red: 0.25, green: 0.6, blue: 0.95)
                    : Color.white.opacity(0.15)
            ) {
                guard canSubmit else { return }
                var answers: [String: String] = [:]
                for q in questions {
                    if q.multiSelect {
                        let picked = (multi[q.id] ?? []).sorted().map { q.options[$0].label }
                        answers[q.header] = picked.joined(separator: ", ")
                    } else if let idx = single[q.id] {
                        answers[q.header] = q.options[idx].label
                    }
                }
                sessionManager.approve(session: session, answers: answers)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.15, green: 0.25, blue: 0.5).opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(red: 0.4, green: 0.6, blue: 1.0).opacity(0.2), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Option row

private struct OptionRow: View {
    let label: String
    let description: String
    let selected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                // 选中指示器
                ZStack {
                    Circle()
                        .strokeBorder(selected
                            ? Color(red: 0.25, green: 0.6, blue: 0.95)
                            : Color.white.opacity(0.2),
                            lineWidth: 1)
                        .frame(width: 12, height: 12)
                    if selected {
                        Circle()
                            .fill(Color(red: 0.25, green: 0.6, blue: 0.95))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 11, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? .white : .white.opacity(0.7))
                        .lineLimit(2)
                    if !description.isEmpty {
                        Text(description)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.white.opacity(0.35))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected
                        ? Color(red: 0.25, green: 0.6, blue: 0.95).opacity(0.12)
                        : (hovered ? Color.white.opacity(0.04) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(selected
                        ? Color(red: 0.25, green: 0.6, blue: 0.95).opacity(0.3)
                        : Color.clear,
                        lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: selected)
        .animation(.easeOut(duration: 0.1), value: hovered)
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
