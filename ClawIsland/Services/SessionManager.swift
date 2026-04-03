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
        Task {
            try? await socketServer.start { [weak self] event in
                guard let self else { return nil }
                return await self.handle(event: event)
            }
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
        s.status      = .running(toolName: e.toolName)
        s.currentTool = e.toolName
        s.lastActivity = Date()
    }

    private func handlePostToolUse(_ e: PostToolUseEvent) {
        let s = findOrCreate(id: e.sessionId, transcriptPath: e.transcriptPath)
        // Keep the tool name visible for 1.5s so the user can read it, then go idle
        s.lastActivity = Date()
        Task {
            try? await Task.sleep(for: .milliseconds(1500))
            // Only clear if still showing this tool (not replaced by a new PreToolUse)
            if case .running(let tool) = s.status, tool == e.toolName {
                s.status      = .idle
                s.currentTool = nil
            }
        }
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
        // Only set once — first prompt establishes the session title; later prompts don't override.
        if !trimmed.isEmpty && s.customTitle == nil {
            s.customTitle = String(trimmed.prefix(40))
        }
        s.status = .idle
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
        // Remove from list after 10s
        Task {
            try? await Task.sleep(for: .seconds(10))
            sessions.removeAll { $0.id == e.sessionId }
        }
    }

    private func handleSessionEnd(_ e: SessionEndEvent) {
        // SessionEnd often follows Stop; avoid double-remove
        guard let s = sessions.first(where: { $0.id == e.sessionId }) else { return }
        if case .completed = s.status { return }  // already handled by Stop
        s.status = .completed
        Task {
            try? await Task.sleep(for: .seconds(10))
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
        session.pendingApprovalContinuation?.resume(
            returning: HookResponse(decision: .allow, reason: nil)
        )
        session.pendingApprovalContinuation = nil
        session.status = .idle
    }

    func deny(session: Session, reason: String? = nil) {
        session.pendingApprovalContinuation?.resume(
            returning: HookResponse(decision: .deny, reason: reason)
        )
        session.pendingApprovalContinuation = nil
        session.status = .idle
    }

    /// Silently allow — dismisses the approval UI without surfacing a decision to the model.
    func ignore(session: Session) {
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
        return s
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
