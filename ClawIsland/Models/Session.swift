import Foundation

enum SessionStatus: Sendable {
    case idle
    case running(toolName: String)
    case waitingApproval(PermissionRequestEvent)
    case compacting
    case completed
    case failed
}

@MainActor
final class Session: ObservableObject, Identifiable {
    let id: String                       // Claude session_id
    let transcriptPath: String?          // path to the transcript file

    @Published var status: SessionStatus = .idle
    @Published var currentTool: String?
    @Published var model: String?
    @Published var customTitle: String?   // set from UserPromptSubmit
    @Published var startTime: Date = Date()
    @Published var lastActivity: Date = Date()

    /// Pending approval continuation — ClawBridge task blocks on this
    var pendingApprovalContinuation: CheckedContinuation<HookResponse, Never>?

    init(id: String, transcriptPath: String?) {
        self.id = id
        self.transcriptPath = transcriptPath
    }

    /// Derive a human-readable title from the transcript path.
    /// The transcript lives at ~/.claude/projects/<encoded-cwd>/<session-id>.jsonl
    /// so the parent directory name encodes the working directory.
    var title: String {
        if let t = customTitle, !t.isEmpty { return t }
        guard let tp = transcriptPath else { return shortId }
        // Decode the encoded path segment — Claude replaces "/" with "-"
        let dirName = URL(fileURLWithPath: tp).deletingLastPathComponent().lastPathComponent
        // The encoded form is like "-Users-zhangjin-Documents-github-myproject"
        // Drop the leading dash and replace dashes at path boundaries
        if dirName.hasPrefix("-") {
            let stripped = String(dirName.dropFirst())
            // Heuristic: last path component is the project folder
            let parts = stripped.components(separatedBy: "-")
            if let last = parts.last, !last.isEmpty { return last }
        }
        return shortId
    }

    var shortId: String { String(id.prefix(8)) }

    var elapsedTime: String {
        let interval = Date().timeIntervalSince(startTime)
        let minutes = Int(interval / 60)
        let hours = minutes / 60
        if hours > 0 { return "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return "<1m"
    }
}
