import AppKit

/// Manages notification sounds for agent events
final class SoundManager {
    static let shared = SoundManager()

    private init() {}

    enum SoundType {
        case permission
        case question
        case taskComplete
        case notification

        /// Map to built-in macOS system sounds
        var systemSoundName: NSSound.Name {
            switch self {
            case .permission: return NSSound.Name("Funk")
            case .question: return NSSound.Name("Submarine")
            case .taskComplete: return NSSound.Name("Glass")
            case .notification: return NSSound.Name("Pop")
            }
        }
    }

    func play(_ type: SoundType) {
        DispatchQueue.main.async {
            NSSound(named: type.systemSoundName)?.play()
        }
    }
}
