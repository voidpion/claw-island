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
    @Published var lastError: String?
    var pid: pid_t?
    var tty: String?      // controlling terminal path, e.g. "/dev/ttys003"

    var pendingApprovalContinuation: CheckedContinuation<HookResponse, Never>?

    /// Timer to refresh elapsedTime display every minute.
    private nonisolated(unsafe) var elapsedTimer: Timer?

    init(id: String, transcriptPath: String?) {
        self.id = id
        self.transcriptPath = transcriptPath
        startElapsedTimer()
    }

    private func startElapsedTimer() {
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Trigger re-render by touching a published property
            objectWillChange.send()
        }
    }

    deinit {
        elapsedTimer?.invalidate()
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

    /// 根据 session ID hash 确定性地分配一只 buddy（0-7），同一 session 永远是同一只。
    var buddyIndex: Int {
        let hex = id.replacingOccurrences(of: "-", with: "").prefix(8)
        let hash = UInt32(hex, radix: 16) ?? 0
        return Int(hash % UInt32(BuddyPixels.count))
    }

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
            return m.trimmingCharacters(in: .whitespacesAndNewlines)
        case .compacting:      return "Compacting…"
        case .completed:       return "Done · \(elapsedTime)"
        case .failed:
            if let err = lastError { return "✗ \(err)" }
            return "Failed"
        }
    }

    /// Human-readable subtitle derived from current status
    var subtitle: String? {
        switch status {
        case .idle:
            if subagentCount > 0 { return "↳ \(subagentCount) subagent\(subagentCount > 1 ? "s" : "")" }
            if customTitle == nil && lastUserPrompt == nil { return "new session" }
            return nil
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
            if let err = lastError { return "✗ \(err)" }
            return "Failed"
        }
    }
}
