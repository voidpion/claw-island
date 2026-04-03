import Foundation
import UserNotifications

@MainActor
final class SessionManager: ObservableObject {
    @Published var sessions: [Session] = []

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
        case .sessionStart(let e):
            handleSessionStart(e)
        case .permissionRequest(let e):
            return await handlePermissionRequest(e)
        case .preToolUse(let e):
            handlePreToolUse(e)
        case .postToolUse(let e):
            handlePostToolUse(e)
        case .notification(let e):
            handleNotification(e)
        case .stop(let e):
            handleStop(e)
        case .sessionEnd(let e):
            handleSessionEnd(e)
        case .userPromptSubmit(let e):
            handleUserPromptSubmit(e)
        case .preCompact(let e):
            handlePreCompact(e)
        case .subagentStart, .subagentStop, .unknown:
            // Update last activity timestamp
            if let session = sessions.first(where: { $0.id == event.sessionId }) {
                session.lastActivity = Date()
            }
        }
        return nil
    }

    // MARK: - Specific handlers

    private func handleSessionStart(_ e: SessionStartEvent) {
        let session = findOrCreate(id: e.sessionId, transcriptPath: e.transcriptPath)
        session.status = .idle
        session.startTime = Date()
        session.lastActivity = Date()
        session.model = e.model
    }

    private func handlePermissionRequest(_ e: PermissionRequestEvent) async -> HookResponse {
        let session = findOrCreate(id: e.sessionId, transcriptPath: e.transcriptPath)
        session.status = .waitingApproval(e)
        session.lastActivity = Date()

        // Suspend this async task until the user taps Allow or Deny in the UI
        return await withCheckedContinuation { continuation in
            session.pendingApprovalContinuation = continuation
        }
    }

    private func handlePreToolUse(_ e: PreToolUseEvent) {
        let session = findOrCreate(id: e.sessionId, transcriptPath: e.transcriptPath)
        session.status = .running(toolName: e.toolName)
        session.currentTool = e.toolName
        session.lastActivity = Date()
    }

    private func handlePostToolUse(_ e: PostToolUseEvent) {
        let session = findOrCreate(id: e.sessionId, transcriptPath: e.transcriptPath)
        session.status = .idle
        session.currentTool = nil
        session.lastActivity = Date()
    }

    private func handleNotification(_ e: NotificationEvent) {
        let session = findOrCreate(id: e.sessionId, transcriptPath: e.transcriptPath)
        session.lastActivity = Date()
        // Could surface the message in the UI; for now, ignore
    }

    private func handleUserPromptSubmit(_ e: UserPromptSubmitEvent) {
        let session = findOrCreate(id: e.sessionId, transcriptPath: e.transcriptPath)
        // Use the first ~40 chars of the prompt as the session title
        let trimmed = e.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = String(trimmed.prefix(40))
        if !title.isEmpty { session.customTitle = title }
        session.lastActivity = Date()
    }

    private func handlePreCompact(_ e: PreCompactEvent) {
        let session = findOrCreate(id: e.sessionId, transcriptPath: e.transcriptPath)
        session.status = .compacting
        session.lastActivity = Date()
    }

    private func handleStop(_ e: StopEvent) {
        let session = findOrCreate(id: e.sessionId, transcriptPath: e.transcriptPath)
        session.status = .completed
        session.currentTool = nil
        session.lastActivity = Date()
        sendCompletionNotification(for: session)
    }

    private func handleSessionEnd(_ e: SessionEndEvent) {
        guard let session = sessions.first(where: { $0.id == e.sessionId }) else { return }
        session.status = .completed
        // Remove after a short delay so user can see the completed state
        Task {
            try? await Task.sleep(for: .seconds(10))
            sessions.removeAll { $0.id == e.sessionId }
        }
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

    // MARK: - Helpers

    private func findOrCreate(id: String, transcriptPath: String?) -> Session {
        if let existing = sessions.first(where: { $0.id == id }) {
            return existing
        }
        let session = Session(id: id, transcriptPath: transcriptPath)
        sessions.append(session)
        return session
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendCompletionNotification(for session: Session) {
        let content = UNMutableNotificationContent()
        content.title = "Task Completed"
        content.body = "\(session.title) — \(session.elapsedTime)"
        content.sound = .default
        let request = UNNotificationRequest(identifier: session.id + "-stop", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
