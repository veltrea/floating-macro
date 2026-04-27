import Foundation

public protocol AppleScriptRunnerProtocol {
    func run(_ source: String) throws -> String?
}

public final class SystemAppleScriptRunner: AppleScriptRunnerProtocol {
    public static let shared = SystemAppleScriptRunner()

    public func run(_ source: String) throws -> String? {
        var errorDict: NSDictionary?
        let script = NSAppleScript(source: source)
        let result = script?.executeAndReturnError(&errorDict)

        if let error = errorDict {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            throw ActionError.appleScriptFailed(message: message)
        }

        return result?.stringValue
    }
}
