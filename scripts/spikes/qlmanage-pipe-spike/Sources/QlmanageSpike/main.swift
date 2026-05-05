import Foundation
import ImageIO
import CoreServices  // for kUTTypePNG (legacy) — actually we use string literal "public.png"

// QlmanageSpike: qlmanage を Process 経由で呼ぶときの「pipe deadlock」アンチパターン
// 検証用の最小 spike。3 つのパターンで挙動を比較する。
//
// 背景:
//   `process.standardOutput = Pipe()` を設定したまま `waitUntilExit()` を呼ぶと、
//   子プロセスが pipe バッファ (64KB) を超える出力をしたところで write が
//   ブロックされ、親が exit を待ち続けてデッドロックする。
//   qlmanage は thumbnail 生成中に warning 等を吐くため、これに該当する。
//
//   refs:
//   - https://cocoadev.github.io/NSTaskWaitUntilExit/
//   - https://forums.swift.org/t/the-problem-with-a-frozen-process-in-swift-process-class/39579

let calculator = "/System/Applications/Calculator.app"

enum SpikePattern: String, CaseIterable {
    case nullDevice           = "1-null-device"          // /dev/null に捨てる
    case readabilityHandler   = "2-readability-handler"  // readabilityHandler で吸い続ける
    case backgroundReadToEnd  = "3-background-read-to-end" // 別 thread で readToEndOfFile
    case anti                 = "0-anti-pattern"         // 再現用: pipe を吸わずに wait
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
        // 意図的にハンドラを設定しない → デッドロックすることを確認

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
        // collected を後で表示できるように weak ref 的なものは spike なので省略

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

    // タイムアウト付き wait
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
        // SIGTERM で死ななければ SIGKILL
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

// MARK: - ImageIO 直読み (qlmanage に依存しない代替路線)

func runImageIOSpike(appPath: String, size: Int = 256) {
    let appURL = URL(fileURLWithPath: appPath)
    let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")

    // Info.plist から CFBundleIconFile を読む
    var iconFile: String? = nil
    if let data = try? Data(contentsOf: infoPlistURL),
       let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
        iconFile = plist["CFBundleIconFile"] as? String
    }

    // 拡張子が無ければ .icns を補完。それでも無ければ AppIcon.icns / icon.icns を順に探索
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

    // CGImageSource で .icns を開く
    guard let source = CGImageSourceCreateWithURL(icns as CFURL, nil) else {
        print("[imageio] \(appURL.lastPathComponent): CGImageSourceCreateWithURL failed")
        return
    }
    let count = CGImageSourceGetCount(source)
    guard count > 0 else {
        print("[imageio] \(appURL.lastPathComponent): icns has 0 representations")
        return
    }

    // 目的サイズに最も近い representation を選ぶ
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

    // PNG として書き出し
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

// 実行する pattern を引数で指定。なければ全部走らせる（anti は最後）。
let args = CommandLine.arguments.dropFirst()
let patterns: [SpikePattern]
if args.isEmpty {
    patterns = [.nullDevice, .backgroundReadToEnd, .readabilityHandler, .anti]
} else {
    patterns = args.compactMap { SpikePattern(rawValue: $0) }
}

if args.first == "imageio" {
    // ImageIO 路線: いくつかのアプリで挙動を比較
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
