import Foundation
import ImageIO
import CoreServices  // for kUTTypePNG (legacy) — actually we use string literal "public.png"

// QlmanageSpike: When calling qlmanage through a Process, the "pipe deadlock" anti-pattern occurs.
// Minimal spike for verification. Compares behavior across three patterns.
//
// Background
// If you set `process.standardOutput = Pipe()` and then call `waitUntilExit()`, the process will wait until it exits before returning.
// Child process exceeded output in pipe buffer (64KB), causing write to fail.
// Blocked, parent continues to wait for exit, causing deadlock.
// qlmanage generates warnings during thumbnail creation, so it matches this.
//
//   refs:
//   - https://cocoadev.github.io/NSTaskWaitUntilExit/
//   - https://forums.swift.org/t/the-problem-with-a-frozen-process-in-swift-process-class/39579

let calculator = "/System/Applications/Calculator.app"

enum SpikePattern: String, CaseIterable {
    case nullDevice           = "1-null-device"          // Redirect to /dev/null
    case readabilityHandler   = "2-readability-handler"  // Continuously sucking in readabilityHandler
    case backgroundReadToEnd  = "3-background-read-to-end" // Read to end in separate thread
    case anti                 = "0-anti-pattern"         // Reproduction: wait without using pipe
}

func runSpike(pattern: SpikePattern, timeoutSeconds: TimeInterval = 30) {
    let outDir = URL(fileURLWithPath: "/tmp/qlmanage-spike-out-\(pattern.rawValue)")
    try? FileManager.default.removeItem(at: outDir)
    try! FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
    p.arguments = ["-t", "-s", "256", "-o", outDir.path, calculator]

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()

    switch pattern {
    case .anti:
        p.standardOutput = stdoutPipe
        p.standardError = stderrPipe
        // Do not intentionally set handlers to ensure deadlocks are confirmed.

    case .nullDevice:
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice

    case .readabilityHandler:
        p.standardOutput = stdoutPipe
        p.standardError = stderrPipe
        var stdoutBytes = Data()
        var stderrBytes = Data()
        let lock = NSLock()
        stdoutPipe.fileHandleForReading.readabilityHandler = { fh in
            let chunk = fh.availableData
            if chunk.isEmpty { return }
            lock.lock(); stdoutBytes.append(chunk); lock.unlock()
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { fh in
            let chunk = fh.availableData
            if chunk.isEmpty { return }
            lock.lock(); stderrBytes.append(chunk); lock.unlock()
        }
        // Collected to display later, weak ref-like things are omitted as they are a spike.

    case .backgroundReadToEnd:
        p.standardOutput = stdoutPipe
        p.standardError = stderrPipe
        DispatchQueue.global().async {
            _ = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }
        DispatchQueue.global().async {
            _ = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }
    }

    let start = Date()
    do {
        try p.run()
    } catch {
        print("[\(pattern.rawValue)] FAILED to run: \(error)")
        return
    }

    // wait with timeout
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async {
        p.waitUntilExit()
        group.leave()
    }
    let waitResult = group.wait(timeout: .now() + timeoutSeconds)

    let elapsed = Date().timeIntervalSince(start)

    if waitResult == .timedOut {
        print("[\(pattern.rawValue)] HUNG after \(String(format: "%.2f", elapsed))s. Terminating.")
        p.terminate()
        // If not killed by SIGTERM, then SIGKILL
        Thread.sleep(forTimeInterval: 1)
        if p.isRunning {
            kill(p.processIdentifier, SIGKILL)
        }
        return
    }

    let files = (try? FileManager.default.contentsOfDirectory(at: outDir, includingPropertiesForKeys: nil)) ?? []
    let pngs = files.filter { $0.pathExtension.lowercased() == "png" }
    print("[\(pattern.rawValue)] OK exit=\(p.terminationStatus) elapsed=\(String(format: "%.2f", elapsed))s pngs=\(pngs.map(\.lastPathComponent))")
}

// MARK: - ImageIO Direct Reading (Alternative Route Not Dependent on qlmanage)

func runImageIOSpike(appPath: String, size: Int = 256) {
    let appURL = URL(fileURLWithPath: appPath)
    let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")

    // Read CFBundleIconFile from Info.plist
    var iconFile: String? = nil
    if let data = try? Data(contentsOf: infoPlistURL),
       let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
        iconFile = plist["CFBundleIconFile"] as? String
    }

    // If there is no extension, add .icns. If still missing, search for AppIcon.icns and icon.icns in order.
    let candidates: [String] = {
        var list: [String] = []
        if let f = iconFile {
            list.append(f.hasSuffix(".icns") ? f : f + ".icns")
        }
        list.append("AppIcon.icns")
        list.append("icon.icns")
        return list
    }()

    let resources = appURL.appendingPathComponent("Contents/Resources")
    var icnsURL: URL? = nil
    for name in candidates {
        let url = resources.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) {
            icnsURL = url
            break
        }
    }

    guard let icns = icnsURL else {
        print("[imageio] \(appURL.lastPathComponent): no icns found")
        return
    }

    let start = Date()

    // Open .icns with CGImageSource
    guard let source = CGImageSourceCreateWithURL(icns as CFURL, nil) else {
        print("[imageio] \(appURL.lastPathComponent): CGImageSourceCreateWithURL failed")
        return
    }
    let count = CGImageSourceGetCount(source)
    guard count > 0 else {
        print("[imageio] \(appURL.lastPathComponent): icns has 0 representations")
        return
    }

    // Choose the representation closest to the target size.
    var bestIndex = 0
    var bestDelta = Int.max
    for i in 0..<count {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any] else { continue }
        let w = (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let delta = abs(w - size)
        if delta < bestDelta { bestDelta = delta; bestIndex = i }
    }

    guard let cgImage = CGImageSourceCreateImageAtIndex(source, bestIndex, nil) else {
        print("[imageio] \(appURL.lastPathComponent): CGImageSourceCreateImageAtIndex failed at \(bestIndex)")
        return
    }

    // Write PNG
    let outData = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(outData, "public.png" as CFString, 1, nil) else {
        print("[imageio] \(appURL.lastPathComponent): CGImageDestinationCreateWithData failed")
        return
    }
    CGImageDestinationAddImage(dest, cgImage, nil)
    guard CGImageDestinationFinalize(dest) else {
        print("[imageio] \(appURL.lastPathComponent): finalize failed")
        return
    }

    let elapsed = Date().timeIntervalSince(start)
    let outPath = "/tmp/qlmanage-spike-imageio-\(appURL.deletingPathExtension().lastPathComponent).png"
    try? (outData as Data).write(to: URL(fileURLWithPath: outPath))

    print("[imageio] \(appURL.lastPathComponent): OK \(cgImage.width)x\(cgImage.height) \(outData.length)B elapsed=\(String(format: "%.3f", elapsed))s → \(outPath)")
}

// Specify the execution pattern as an argument; if not specified, run all of them (anti runs last).
let args = CommandLine.arguments.dropFirst()
let patterns: [SpikePattern]
if args.isEmpty {
    patterns = [.nullDevice, .backgroundReadToEnd, .readabilityHandler, .anti]
} else {
    patterns = args.compactMap { SpikePattern(rawValue: $0) }
}

if args.first == "imageio" {
    // ImageIO Route: Comparing behavior across several apps
    let apps = [
        "/System/Applications/Calculator.app",
        "/Applications/Slack.app",
        "/Applications/Visual Studio Code.app",
    ]
    for app in apps where FileManager.default.fileExists(atPath: app) {
        runImageIOSpike(appPath: app)
    }
} else {
    print("Running \(patterns.count) qlmanage pattern(s) against \(calculator)")
    print("Each pattern has a 30s timeout. Anti-pattern is expected to hang.")
    print("---")
    for pat in patterns {
        runSpike(pattern: pat)
    }
}
print("---")
print("done.")
