import Foundation

enum SessionStatus: Sendable {
    case idle
    case running(toolName: String)
    case waitingApproval(PermissionRequestEvent)
    case notifying(message: String)
    case compacting
    case completed
    case failed
}

@MainActor
final class Session: ObservableObject, Identifiable {
    let id: String
    let transcriptPath: String?

    @Published var status: SessionStatus = .idle
    @Published var currentTool: String?
    @Published var model: String?
    @Published var customTitle: String?
    @Published var lastUserPrompt: String?
    @Published var subagentCount: Int = 0
    @Published var startTime: Date = Date()
    @Published var lastActivity: Date = Date()
    @Published var cwd: String?

    var pendingApprovalContinuation: CheckedContinuation<HookResponse, Never>?

    init(id: String, transcriptPath: String?) {
        self.id = id
        self.transcriptPath = transcriptPath
    }

    var title: String {
        if let t = customTitle, !t.isEmpty { return t }
        if let cwd { return URL(fileURLWithPath: cwd).lastPathComponent }
        guard let tp = transcriptPath else { return shortId }
        let dirName = URL(fileURLWithPath: tp).deletingLastPathComponent().lastPathComponent
        if dirName.hasPrefix("-") {
            let parts = String(dirName.dropFirst()).components(separatedBy: "-")
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

    /// Priority for picking which session to feature in the collapsed bar.
    /// Higher = more urgent.
    var statusPriority: Int {
        switch status {
        case .waitingApproval: return 5
        case .notifying:       return 4
        case .running:         return 3
        case .failed:          return 3
        case .compacting:      return 2
        case .completed:       return 1
        case .idle:            return 0
        }
    }

    /// One-liner shown in the collapsed notch bar for the featured session.
    var compactMessage: String? {
        switch status {
        case .idle:            return nil
        case .running(let t): return t
        case .waitingApproval: return "Needs approval"
        case .notifying(let m):
            let s = m.trimmingCharacters(in: .whitespacesAndNewlines)
            return s.count > 28 ? String(s.prefix(28)) + "…" : s
        case .compacting:      return "Compacting…"
        case .completed:       return "Done · \(elapsedTime)"
        case .failed:          return "Failed"
        }
    }

    /// Human-readable subtitle derived from current status
    var subtitle: String? {
        switch status {
        case .idle:
            return subagentCount > 0 ? "↳ \(subagentCount) subagent\(subagentCount > 1 ? "s" : "")" : nil
        case .running(let tool):
            let base = tool
            return subagentCount > 0 ? "\(base)  ↳ \(subagentCount)" : base
        case .waitingApproval:
            return "Awaiting approval…"
        case .notifying(let msg):
            return msg
        case .compacting:
            return "Compacting context…"
        case .completed:
            return "Done · \(elapsedTime)"
        case .failed:
            return "Failed"
        }
    }
}
