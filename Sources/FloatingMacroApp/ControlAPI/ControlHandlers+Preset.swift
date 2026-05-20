import Foundation
import FloatingMacroCore

// MARK: - Preset CRUD

extension ControlHandlers {

    // MARK: - Preset CRUD

    @MainActor
    func handlePresetCurrent() -> HTTPResponse {
        guard let preset = presetManager.currentPreset else {
            return HTTPResponse.json(["preset": NSNull()])
        }
        if let data = try? JSONEncoder().encode(preset),
           let obj = try? JSONSerialization.jsonObject(with: data) {
            return HTTPResponse.json(["preset": obj])
        }
        return HTTPResponse.internalError("failed to encode preset")
    }

    /// 指定名のプリセットを読み取る (read-only)。Phase 5 で Web Panel が
    /// パネルごとの URL から preset を選んで開くために使う。
    @MainActor
    func handlePresetGet(_ req: HTTPRequest) -> HTTPResponse {
        guard let name = req.query["name"], !name.isEmpty else {
            return HTTPResponse.badRequest("missing 'name' query parameter")
        }
        guard let preset = presetManager.preset(named: name) else {
            return HTTPResponse.json(["preset": NSNull(), "error": "not found"], status: 404)
        }
        if let data = try? JSONEncoder().encode(preset),
           let obj = try? JSONSerialization.jsonObject(with: data) {
            return HTTPResponse.json(["preset": obj])
        }
        return HTTPResponse.internalError("failed to encode preset")
    }

    @MainActor
    func handlePresetCreate(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary() else {
            return HTTPResponse.badRequest("body must be a JSON object")
        }
        // All keys are optional. Missing `name` → auto-number; missing
        // `displayName` → fall back to the resolved name. `memo` lets AI
        // agents seed the usage note at creation time without an extra call.
        let name = (dict["name"] as? String) ?? presetManager.nextPresetName()
        let displayName = (dict["displayName"] as? String) ?? name
        let memo = dict["memo"] as? String
        let ok = presetManager.createPreset(name: name, displayName: displayName, memo: memo)
        return HTTPResponse.json(["ok": ok, "name": name, "displayName": displayName])
    }

    @MainActor
    func handlePresetRename(_ req: HTTPRequest) -> HTTPResponse {
        // Despite the legacy name "rename", this endpoint now updates any
        // preset-level metadata: `displayName` and/or `memo`. Both are
        // optional so callers can update one without touching the other.
        // Pass `memo: ""` (empty string) to clear the memo; omit the key
        // entirely to leave the existing memo intact.
        guard let dict = req.jsonDictionary(),
              let name = dict["name"] as? String else {
            return HTTPResponse.badRequest("body must contain {name}")
        }
        let display = dict["displayName"] as? String
        let memoProvided = dict.keys.contains("memo")
        let memo = dict["memo"] as? String

        if display == nil && !memoProvided {
            return HTTPResponse.badRequest("body must contain at least one of {displayName, memo}")
        }

        var renameOk = true
        if let display = display, !display.isEmpty {
            renameOk = presetManager.renamePreset(name: name, displayName: display)
        }
        var memoOk = true
        if memoProvided {
            memoOk = presetManager.updatePresetMemo(name: name, memo: memo)
        }
        return HTTPResponse.json(["ok": renameOk && memoOk])
    }

    @MainActor
    func handlePresetExport(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let name = dict["name"] as? String else {
            return HTTPResponse.badRequest("body must contain {name: String}")
        }
        guard let data = presetManager.exportPresetData(name: name),
              let preset = try? JSONSerialization.jsonObject(with: data) else {
            return HTTPResponse.badRequest("preset not found: \(name)")
        }
        return HTTPResponse.json(["ok": true, "name": name, "preset": preset])
    }

    @MainActor
    func handlePresetExportBundle() -> HTTPResponse {
        guard let data = presetManager.exportAllPresetsData(),
              let bundle = try? JSONSerialization.jsonObject(with: data) else {
            return HTTPResponse.json(["ok": false, "error": "failed to encode bundle"])
        }
        return HTTPResponse.json(["ok": true, "bundle": bundle])
    }

    /// Accepts either:
    ///  - `{ "preset": {...} }` — single preset payload
    ///  - `{ "bundle": { "version": 1, "presets": [...] } }` — multiple
    /// Imported presets are saved with fresh internal ids via
    /// `nextPresetName()`, so existing files are never overwritten.
    @MainActor
    func handlePresetImport(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary() else {
            return HTTPResponse.badRequest("body must be a JSON object")
        }
        // Re-serialize the inner payload so we can reuse the existing
        // file-based importer, which auto-detects single vs bundle.
        let payload: Any
        if let p = dict["preset"] {
            payload = p
        } else if let b = dict["bundle"] {
            payload = b
        } else {
            return HTTPResponse.badRequest("body must contain {preset: {...}} or {bundle: {...}}")
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            return HTTPResponse.badRequest("payload is not valid JSON")
        }
        // Write to a temp file so importPresets(from:) can decode it.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("fm-import-\(UUID().uuidString).json")
        do { try data.write(to: tmp) } catch {
            return HTTPResponse.badRequest("failed to stage payload: \(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(at: tmp) }
        let before = Set(presetManager.presetEntries.map { $0.name })
        let imported = presetManager.importPresets(from: tmp)
        let after = presetManager.presetEntries.map { $0.name }
        let names = after.filter { !before.contains($0) }
        return HTTPResponse.json(["ok": imported > 0, "imported": imported, "names": names])
    }

    @MainActor
    func handlePresetInstallSeeds(_ req: HTTPRequest) -> HTTPResponse {
        let force = (req.jsonDictionary()?["force"] as? Bool) ?? false
        guard let result = presetManager.reinstallSeedPresets(force: force) else {
            return HTTPResponse.json(["ok": false, "error": "install failed"])
        }
        return HTTPResponse.json([
            "ok":        true,
            "installed": result.installed,
            "skipped":   result.skipped,
            "force":     force,
        ])
    }

    @MainActor
    func handlePresetDelete(_ req: HTTPRequest) -> HTTPResponse {
        guard let dict = req.jsonDictionary(),
              let name = dict["name"] as? String else {
            return HTTPResponse.badRequest("body must contain {name: String}")
        }
        let ok = presetManager.deletePreset(name: name)
        return HTTPResponse.json(["ok": ok])
    }

}
