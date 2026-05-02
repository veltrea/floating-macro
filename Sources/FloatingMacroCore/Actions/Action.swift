import Foundation

public enum Action: Codable, Equatable {
    case key(combo: String)
    case text(content: String, pasteDelayMs: Int, restoreClipboard: Bool)
    case launch(target: String)
    case terminal(app: String, command: String, newWindow: Bool, execute: Bool, profile: String?)
    case delay(ms: Int)
    case macro(actions: [Action], stopOnError: Bool)

    private enum CodingKeys: String, CodingKey {
        case type
        case combo
        case content
        case pasteDelayMs
        case restoreClipboard
        case target
        case app
        case command
        case newWindow
        case execute
        case profile
        case ms
        case actions
        case stopOnError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "key":
            let combo = try container.decode(String.self, forKey: .combo)
            self = .key(combo: combo)

        case "text":
            let content = try container.decode(String.self, forKey: .content)
            let pasteDelayMs = try container.decodeIfPresent(Int.self, forKey: .pasteDelayMs) ?? 120
            let restoreClipboard = try container.decodeIfPresent(Bool.self, forKey: .restoreClipboard) ?? true
            self = .text(content: content, pasteDelayMs: pasteDelayMs, restoreClipboard: restoreClipboard)

        case "launch":
            let target = try container.decode(String.self, forKey: .target)
            self = .launch(target: target)

        case "terminal":
            let app = try container.decodeIfPresent(String.self, forKey: .app) ?? "Terminal"
            let command = try container.decode(String.self, forKey: .command)
            let newWindow = try container.decodeIfPresent(Bool.self, forKey: .newWindow) ?? true
            let execute = try container.decodeIfPresent(Bool.self, forKey: .execute) ?? true
            let profile = try container.decodeIfPresent(String.self, forKey: .profile)
            self = .terminal(app: app, command: command, newWindow: newWindow, execute: execute, profile: profile)

        case "delay":
            let ms = try container.decode(Int.self, forKey: .ms)
            self = .delay(ms: ms)

        case "macro":
            let actions = try container.decode([Action].self, forKey: .actions)
            // Reject nested macros
            for action in actions {
                if case .macro = action {
                    throw DecodingError.dataCorruptedError(
                        forKey: .actions,
                        in: container,
                        debugDescription: "Nested macro is not allowed"
                    )
                }
            }
            let stopOnError = try container.decodeIfPresent(Bool.self, forKey: .stopOnError) ?? true
            self = .macro(actions: actions, stopOnError: stopOnError)

        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown action type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .key(let combo):
            try container.encode("key", forKey: .type)
            try container.encode(combo, forKey: .combo)

        case .text(let content, let pasteDelayMs, let restoreClipboard):
            try container.encode("text", forKey: .type)
            try container.encode(content, forKey: .content)
            try container.encode(pasteDelayMs, forKey: .pasteDelayMs)
            try container.encode(restoreClipboard, forKey: .restoreClipboard)

        case .launch(let target):
            try container.encode("launch", forKey: .type)
            try container.encode(target, forKey: .target)

        case .terminal(let app, let command, let newWindow, let execute, let profile):
            try container.encode("terminal", forKey: .type)
            try container.encode(app, forKey: .app)
            try container.encode(command, forKey: .command)
            try container.encode(newWindow, forKey: .newWindow)
            try container.encode(execute, forKey: .execute)
            try container.encodeIfPresent(profile, forKey: .profile)

        case .delay(let ms):
            try container.encode("delay", forKey: .type)
            try container.encode(ms, forKey: .ms)

        case .macro(let actions, let stopOnError):
            try container.encode("macro", forKey: .type)
            try container.encode(actions, forKey: .actions)
            try container.encode(stopOnError, forKey: .stopOnError)
        }
    }
}
