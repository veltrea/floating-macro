import Foundation

public enum MacroRunner {
    private static let category = "MacroRunner"

    public static func run(actions: [Action], stopOnError: Bool = true) async throws {
        let log = LoggerContext.shared
        log.info(category, "Starting macro", [
            "count": String(actions.count),
            "stopOnError": String(stopOnError),
        ])

        for action in actions {
            if case .macro = action {
                log.error(category, "Rejected nested macro")
                throw ActionError.nestedMacroNotAllowed
            }
        }

        var successCount = 0
        var failureCount = 0

        for (idx, action) in actions.enumerated() {
            do {
                log.debug(category, "Executing action", [
                    "index": String(idx),
                    "type": action.typeName,
                ])
                switch action {
                case .key(let combo):
                    let kc = try KeyCombo.parse(combo)
                    try KeyActionExecutor.execute(kc)

                case .text(let content, let pasteDelayMs, let restoreClipboard):
                    try TextActionExecutor.execute(
                        content: content,
                        pasteDelayMs: pasteDelayMs,
                        restoreClipboard: restoreClipboard
                    )

                case .launch(let target):
                    try LaunchActionExecutor.execute(target: target)

                case .terminal(let app, let command, let newWindow, let execute, let profile):
                    try TerminalActionExecutor.execute(
                        app: app, command: command, newWindow: newWindow,
                        execute: execute, profile: profile
                    )

                case .delay(let ms):
                    try await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)

                case .macro:
                    throw ActionError.nestedMacroNotAllowed
                }
                successCount += 1
            } catch {
                failureCount += 1
                log.warn(category, "Action failed", [
                    "index": String(idx),
                    "type": action.typeName,
                    "error": String(describing: error),
                ])
                if stopOnError {
                    log.error(category, "Macro aborted", [
                        "completed": String(successCount),
                        "remaining": String(actions.count - idx - 1),
                    ])
                    throw error
                }
            }
        }

        log.info(category, "Completed macro", [
            "success": String(successCount),
            "failed": String(failureCount),
        ])
    }
}

// MARK: - Internal helpers

extension Action {
    /// Short lowercase identifier used in log metadata.
    var typeName: String {
        switch self {
        case .key:      return "key"
        case .text:     return "text"
        case .launch:   return "launch"
        case .terminal: return "terminal"
        case .delay:    return "delay"
        case .macro:    return "macro"
        }
    }
}
