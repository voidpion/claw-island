import Foundation
import UserNotifications

@MainActor
final class SessionManager: ObservableObject {
    @Published var sessions: [Session] = []

    /// Controller sets this to be notified when a session needs the panel auto-expanded
    var onAutoExpand: (() -> Void)?

    private let socketServer = SocketServer()

    func start() {
        requestNotificationPermission()
        try? socketServer.start { [weak self] event in
            guard let self else { return nil }
            return await self.handle(event: event)
        }
    }

    // MARK: - Event routing

    private func handle(event: HookEvent) async -> HookResponse? {
        switch event {
        case .sessionStart(let e):      handleSessionStart(e)
        case .permissionRequest(let e): return await handlePermissionRequest(e)
        case .preToolUse(let e):        handlePreToolUse(e)
        case .postToolUse(let e):       handlePostToolUse(e)
        case .notification(let e):      handleNotification(e)
        case .stop(let e):              handleStop(e)
        case .sessionEnd(let e):        handleSessionEnd(e)
        case .userPromptSubmit(let e):  handleUserPromptSubmit(e)
        case .preCompact(let e):        handlePreCompact(e)
        case .subagentStart(let e):     handleSubagentStart(e)
        case .subagentStop(let e):      handleSubagentStop(e)
        case .unknown:                  break
        }
        return nil
    }

    // MARK: - Handlers

    private func handleSessionStart(_ e: SessionStartEvent) {
        debugLog("handleSessionStart id=\(e.sessionId) sessions.count=\(sessions.count)")
        let s = findOrCreate(id: e.sessionId, transcriptPath: e.transcriptPath)
        s.status = .idle
        s.currentTool = nil
        s.lastActivity = Date()
        if let model = e.model { s.model = model }
        // compact / resume: session continues — preserve title and start time.
        // startup / clear / unknown: fresh session, fully reset.
        let isContinuation = e.source == "compact" || e.source == "resume"
        if isContinuation {
            s.subagentCount = 0
        } else {
            s.startTime = Date()
            s.customTitle = nil
            s.subagentCount = 0
        }
    }

    private func handlePermissionRequest(_ e: PermissionRequestEvent) async -> HookResponse {
        let s = findOrCreate(id: e.sessionId, transcriptPath: e.transcriptPath)
        s.status = .waitingApproval(e)
        s.lastActivity = Date()
        onAutoExpand?()
        return await withCheckedContinuation { continuation in
            s.pendingApprovalContinuation = continuation
        }
    }

    private func handlePreToolUse(_ e: PreToolUseEvent) {
        let s = findOrCreate(id: e.sessionId, transcriptPath: e.transcriptPath)
        let desc = Self.toolDescription(name: e.toolName, input: e.toolInput)
        s.status      = .running(toolName: desc)
        s.currentTool = e.toolName
        s.lastActivity = Date()
    }

    /// Build a single-line tool description: "ToolName: key_param"
    private static func toolDescription(name: String, input: JSONValue) -> String {
        let key: String? = {
            switch name {
            case "Bash":   return input["command"]?.description
            case "Read":   return input["file_path"]?.description
            case "Write":  return input["file_path"]?.description
            case "Edit":   return input["file_path"]?.description
            case "Grep":   return input["pattern"]?.description
            case "Glob":   return input["pattern"]?.description
            case "Agent":  return input["description"]?.description
            case "WebFetch", "WebSearch": return input["query"]?.description ?? input["url"]?.description
            default:       return nil
            }
        }()
        if let key {
            let truncated = String(key.prefix(80))
            return "\(name): \(truncated)"
        }
        return name
    }

    private func handlePostToolUse(_ e: PostToolUseEvent) {
        let s = findOrCreate(id: e.sessionId, transcriptPath: e.transcriptPath)
        // Stay in running state — next pre_tool_use will update the tool name,
        // or stop will transition to completed. No idle flash mid-conversation.
        s.lastActivity = Date()
    }

    private func handleNotification(_ e: NotificationEvent) {
        let s = findOrCreate(id: e.sessionId, transcriptPath: e.transcriptPath)
        let msg = e.message.trimmingCharacters(in: .whitespacesAndNewlines)
        s.status = .notifying(message: String(msg.prefix(60)))
        s.lastActivity = Date()
        onAutoExpand?()
        sendSystemNotification(title: e.title ?? s.title, body: msg, id: e.sessionId + "-notif")
    }

    private func handleUserPromptSubmit(_ e: UserPromptSubmitEvent) {
        let s = findOrCreate(id: e.sessionId, transcriptPath: e.transcriptPath)
        let trimmed = e.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            // Only set once — first prompt establishes the session title; later prompts don't override.
            if s.customTitle == nil {
                s.customTitle = String(trimmed.prefix(40))
            }
            s.lastUserPrompt = String(trimmed.prefix(60))
        }
        // Show as running("thinking") — Claude has received the message and is about to work.
        // pre_tool_use will replace this with the actual tool name shortly.
        s.status = .running(toolName: "thinking")
        s.currentTool = nil
        s.lastActivity = Date()
    }

    private func handlePreCompact(_ e: PreCompactEvent) {
        let s = findOrCreate(id: e.sessionId, transcriptPath: e.transcriptPath)
        s.status = .compacting
        s.lastActivity = Date()
    }

    private func handleStop(_ e: StopEvent) {
        let s = findOrCreate(id: e.sessionId, transcriptPath: e.transcriptPath)
        s.status      = .completed
        s.currentTool = nil
        s.lastActivity = Date()
        sendSystemNotification(
            title: "Task Completed",
            body: "\(s.title) · \(s.elapsedTime)",
            id: s.id + "-stop"
        )
        // Do NOT remove here — Stop fires after every response, not just at session end.
        // SessionEnd handles removal when the user actually exits claude.
    }

    private func handleSessionEnd(_ e: SessionEndEvent) {
        // User exited claude — remove after a brief delay so "Done" is readable.
        Task {
            try? await Task.sleep(for: .seconds(5))
            sessions.removeAll { $0.id == e.sessionId }
        }
    }

    private func handleSubagentStart(_ e: SubagentStartEvent) {
        let s = findOrCreate(id: e.sessionId, transcriptPath: e.transcriptPath)
        s.subagentCount += 1
        s.lastActivity = Date()
    }

    private func handleSubagentStop(_ e: SubagentStopEvent) {
        guard let s = sessions.first(where: { $0.id == e.sessionId }) else { return }
        s.subagentCount = max(0, s.subagentCount - 1)
        s.lastActivity = Date()
    }

    // MARK: - Approval (called from UI)

    func approve(session: Session) {
        NSLog("[ClawIsland] approve called — continuation present: %d", session.pendingApprovalContinuation != nil ? 1 : 0)
        session.pendingApprovalContinuation?.resume(
            returning: HookResponse(decision: .allow, reason: nil)
        )
        session.pendingApprovalContinuation = nil
        session.status = .idle
    }

    func deny(session: Session, reason: String? = nil) {
        NSLog("[ClawIsland] deny called — continuation present: %d", session.pendingApprovalContinuation != nil ? 1 : 0)
        session.pendingApprovalContinuation?.resume(
            returning: HookResponse(decision: .deny, reason: reason)
        )
        session.pendingApprovalContinuation = nil
        session.status = .idle
    }

    /// Silently allow — dismisses the approval UI without surfacing a decision to the model.
    func ignore(session: Session) {
        NSLog("[ClawIsland] ignore called — continuation present: %d", session.pendingApprovalContinuation != nil ? 1 : 0)
        session.pendingApprovalContinuation?.resume(
            returning: HookResponse(decision: .allow, reason: nil)
        )
        session.pendingApprovalContinuation = nil
        session.status = .idle
    }

    // MARK: - Helpers

    private func findOrCreate(id: String, transcriptPath: String?) -> Session {
        if let existing = sessions.first(where: { $0.id == id }) { return existing }
        let s = Session(id: id, transcriptPath: transcriptPath)
        sessions.append(s)
        debugLog("findOrCreate: created new session, total=\(sessions.count)")
        return s
    }

    private func debugLog(_ msg: String) {
        let line = "\(Date()) [SM] \(msg)\n"
        if let data = line.data(using: .utf8) {
            let url = URL(fileURLWithPath: "/tmp/claw-island.log")
            if let fh = try? FileHandle(forWritingTo: url) {
                fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendSystemNotification(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: nil)
        )
    }
}
