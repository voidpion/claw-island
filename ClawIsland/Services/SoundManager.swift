import AppKit

@MainActor
final class SoundManager {
    enum Event {
        case sessionStart
        case sessionEnd
        case stop
        case permissionRequest
        case approve
        case deny
        case notification
        case stopFailure
        case postToolUseFailure
        case userPromptSubmit
        case preToolUse
        case postToolUse
        case preCompact
        case postCompact
    }

    func play(_ event: Event) {
        let name: String? = switch event {
        case .sessionStart:       "Pop"
        case .sessionEnd:         "Purr"
        case .stop:               "Tink"
        case .permissionRequest:  "Ping"
        case .approve:            "Glass"
        case .deny:               "Basso"
        case .notification:       "Blow"
        case .stopFailure:        "Sosumi"
        case .postToolUseFailure: "Funk"
        case .userPromptSubmit,
             .preToolUse,
             .postToolUse,
             .preCompact,
             .postCompact:        nil
        }
        guard let name else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}
