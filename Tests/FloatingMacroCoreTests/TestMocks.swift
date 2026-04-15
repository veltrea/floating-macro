import Foundation
import CoreGraphics
@testable import FloatingMacroCore

// MARK: - Mock EventSynthesizer

/// Records every `postKeyEvent` call. Use `errorToThrow` to simulate
/// Accessibility denial.
final class MockEventSynthesizer: EventSynthesizerProtocol {
    struct Call: Equatable {
        let keyCode: UInt16
        let flags: CGEventFlags
    }

    private(set) var calls: [Call] = []
    var errorToThrow: Error?

    func postKeyEvent(keyCode: UInt16, flags: CGEventFlags) throws {
        if let error = errorToThrow { throw error }
        calls.append(Call(keyCode: keyCode, flags: flags))
    }
}

// MARK: - Mock Clipboard

/// Records every save / restore / setString call and lets tests peek at the
/// last stored string. Snapshots are distinguished by a monotonically
/// increasing token so save/restore ordering can be asserted.
final class MockClipboard: ClipboardProtocol {
    private(set) var savedCount = 0
    private(set) var restoredSnapshots: [ClipboardSnapshot] = []
    private(set) var setStrings: [String] = []
    /// Each Operation is either .save / .set / .restore so tests can assert
    /// the exact sequence (e.g. "save -> set -> restore" for TextActionExecutor).
    enum Op: Equatable {
        case save
        case setString(String)
        case restore
    }
    private(set) var ops: [Op] = []

    func save() -> ClipboardSnapshot {
        savedCount += 1
        ops.append(.save)
        // We use the length of .items as a "token" (here: empty).
        return ClipboardSnapshot(items: [])
    }

    func restore(_ snapshot: ClipboardSnapshot) {
        restoredSnapshots.append(snapshot)
        ops.append(.restore)
    }

    func setString(_ s: String) {
        setStrings.append(s)
        ops.append(.setString(s))
    }
}

// MARK: - Mock AppleScript Runner

final class MockAppleScriptRunner: AppleScriptRunnerProtocol {
    private(set) var scripts: [String] = []
    var resultToReturn: String?
    var errorToThrow: Error?

    func run(_ source: String) throws -> String? {
        if let error = errorToThrow { throw error }
        scripts.append(source)
        return resultToReturn
    }
}

// MARK: - Mock Workspace Launcher

final class MockWorkspaceLauncher: WorkspaceLauncherProtocol {
    private(set) var openedURLs: [URL] = []
    private(set) var openedBundleIDs: [String] = []
    /// Override per-method errors; if set, that method throws.
    var openURLError: Error?
    var openAppError: Error?

    func open(url: URL) throws {
        if let error = openURLError { throw error }
        openedURLs.append(url)
    }

    func openApplication(bundleIdentifier: String) throws {
        if let error = openAppError { throw error }
        openedBundleIDs.append(bundleIdentifier)
    }
}

// MARK: - Executor DI Scope

/// Helper that swaps out every Executor's DI singletons to a provided set of
/// mocks, and restores the originals when deallocated. Tests should hold one
/// instance for the duration of the test case.
///
/// Usage:
/// ```
/// let mocks = TestMocks()
/// defer { mocks.restore() }
/// // call executors; inspect mocks.synth / mocks.clipboard / ...
/// ```
final class TestMocks {
    let synth      = MockEventSynthesizer()
    let clipboard  = MockClipboard()
    let launcher   = MockWorkspaceLauncher()
    let script     = MockAppleScriptRunner()

    private let originalKeySynth:    EventSynthesizerProtocol
    private let originalTextSynth:   EventSynthesizerProtocol
    private let originalTextClip:    ClipboardProtocol
    private let originalLaunchLauncher: WorkspaceLauncherProtocol
    private let originalLaunchScript:   AppleScriptRunnerProtocol
    private let originalTermSynth:   EventSynthesizerProtocol
    private let originalTermClip:    ClipboardProtocol
    private let originalTermLauncher: WorkspaceLauncherProtocol
    private let originalTermScript:   AppleScriptRunnerProtocol

    init() {
        originalKeySynth        = KeyActionExecutor.synthesizer
        originalTextSynth       = TextActionExecutor.synthesizer
        originalTextClip        = TextActionExecutor.clipboard
        originalLaunchLauncher  = LaunchActionExecutor.launcher
        originalLaunchScript    = LaunchActionExecutor.scriptRunner
        originalTermSynth       = TerminalActionExecutor.synthesizer
        originalTermClip        = TerminalActionExecutor.clipboard
        originalTermLauncher    = TerminalActionExecutor.launcher
        originalTermScript      = TerminalActionExecutor.scriptRunner

        KeyActionExecutor.synthesizer       = synth
        TextActionExecutor.synthesizer      = synth
        TextActionExecutor.clipboard        = clipboard
        LaunchActionExecutor.launcher       = launcher
        LaunchActionExecutor.scriptRunner   = script
        TerminalActionExecutor.synthesizer  = synth
        TerminalActionExecutor.clipboard    = clipboard
        TerminalActionExecutor.launcher     = launcher
        TerminalActionExecutor.scriptRunner = script
    }

    func restore() {
        KeyActionExecutor.synthesizer       = originalKeySynth
        TextActionExecutor.synthesizer      = originalTextSynth
        TextActionExecutor.clipboard        = originalTextClip
        LaunchActionExecutor.launcher       = originalLaunchLauncher
        LaunchActionExecutor.scriptRunner   = originalLaunchScript
        TerminalActionExecutor.synthesizer  = originalTermSynth
        TerminalActionExecutor.clipboard    = originalTermClip
        TerminalActionExecutor.launcher     = originalTermLauncher
        TerminalActionExecutor.scriptRunner = originalTermScript
    }
}
