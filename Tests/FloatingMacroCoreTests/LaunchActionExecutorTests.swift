import XCTest
@testable import FloatingMacroCore

final class LaunchActionExecutorTests: XCTestCase {

    private var mocks: TestMocks!

    override func setUp() {
        super.setUp()
        mocks = TestMocks()
    }

    override func tearDown() {
        mocks.restore()
        mocks = nil
        super.tearDown()
    }

    // MARK: - shell: prefix (real /bin/sh execution)

    func testShellPrefixRunsCommand() throws {
        // Create a temp file and verify the shell command creates it.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("fmtest-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: tmp) }

        try LaunchActionExecutor.execute(target: "shell:touch '\(tmp.path)'")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.path))
    }

    func testShellPrefixNonZeroExitThrows() {
        XCTAssertThrowsError(try LaunchActionExecutor.execute(target: "shell:exit 42")) { error in
            guard case ActionError.shellCommandFailed(let code, _) = error else {
                return XCTFail("Expected shellCommandFailed, got \(error)")
            }
            XCTAssertEqual(code, 42)
        }
    }

    func testShellPrefixCapturesStderr() {
        XCTAssertThrowsError(try LaunchActionExecutor.execute(
            target: "shell:echo 'boom' 1>&2; exit 3"
        )) { error in
            guard case ActionError.shellCommandFailed(let code, let stderr) = error else {
                return XCTFail("Expected shellCommandFailed, got \(error)")
            }
            XCTAssertEqual(code, 3)
            XCTAssertTrue(stderr.contains("boom"))
        }
    }

    // MARK: - URL schemes

    func testHttpsURLDispatchesOpenURL() throws {
        try LaunchActionExecutor.execute(target: "https://example.com/path?q=1")
        XCTAssertEqual(mocks.launcher.openedURLs.count, 1)
        XCTAssertEqual(mocks.launcher.openedURLs[0].absoluteString, "https://example.com/path?q=1")
        XCTAssertEqual(mocks.launcher.openedBundleIDs.count, 0)
    }

    func testCustomSchemeDispatchesOpenURL() throws {
        try LaunchActionExecutor.execute(target: "vscode:///tmp/foo")
        XCTAssertEqual(mocks.launcher.openedURLs.count, 1)
        XCTAssertEqual(mocks.launcher.openedURLs[0].scheme, "vscode")
    }

    func testLauncherOpenURLErrorPropagates() {
        mocks.launcher.openURLError = ActionError.urlSchemeUnhandled("whatever://")
        XCTAssertThrowsError(try LaunchActionExecutor.execute(target: "whatever://thing")) { error in
            XCTAssertEqual(error as? ActionError, .urlSchemeUnhandled("whatever://"))
        }
    }

    // MARK: - Bundle identifier branch

    func testBundleIdentifierDispatchesOpenApplication() throws {
        try LaunchActionExecutor.execute(target: "com.tinyspeck.slackmacgap")
        XCTAssertEqual(mocks.launcher.openedBundleIDs, ["com.tinyspeck.slackmacgap"])
        XCTAssertEqual(mocks.launcher.openedURLs, [])
    }

    func testBundleIdNotFoundThrows() {
        mocks.launcher.openAppError = ActionError.launchTargetNotFound("com.fake.app")
        XCTAssertThrowsError(try LaunchActionExecutor.execute(target: "com.fake.app")) { error in
            XCTAssertEqual(error as? ActionError, .launchTargetNotFound("com.fake.app"))
        }
    }

    // MARK: - File path branch

    func testExistingAbsolutePathOpens() throws {
        // /tmp is guaranteed to exist on macOS.
        try LaunchActionExecutor.execute(target: "/tmp")
        XCTAssertEqual(mocks.launcher.openedURLs.count, 1)
        XCTAssertEqual(mocks.launcher.openedURLs[0].path, "/tmp")
    }

    func testNonExistingAbsolutePathThrowsNotFound() {
        XCTAssertThrowsError(try LaunchActionExecutor.execute(
            target: "/definitely/does/not/exist-\(UUID().uuidString)"
        )) { error in
            guard case ActionError.launchTargetNotFound = error else {
                return XCTFail("Expected launchTargetNotFound, got \(error)")
            }
        }
    }

    func testTildeExpansion() throws {
        // Create a file in $HOME/.tmp-fmtest so ~ resolution works.
        let home = FileManager.default.homeDirectoryForCurrentUser
        let file = home.appendingPathComponent(".fmtest-\(UUID().uuidString)")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let tilde = "~/\(file.lastPathComponent)"
        try LaunchActionExecutor.execute(target: tilde)
        XCTAssertEqual(mocks.launcher.openedURLs.count, 1)
        XCTAssertEqual(mocks.launcher.openedURLs[0].path, file.path)
    }

    // MARK: - Malformed targets

    func testRelativePathWithoutSlashThrowsNotFound() {
        XCTAssertThrowsError(try LaunchActionExecutor.execute(target: "not-a-valid-target")) { error in
            guard case ActionError.launchTargetNotFound = error else {
                return XCTFail("Expected launchTargetNotFound, got \(error)")
            }
        }
    }
}
