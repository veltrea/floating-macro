import Foundation
import FloatingMacroCore

/// HTTP routes for fm-test-target. Kept dependency-free of AppKit so the
/// dispatch logic is trivial to reason about. All UI access goes through
/// the closures supplied by `TestTargetDelegate`, which marshal to
/// MainActor internally.
struct TestTargetHandlers {
    let getText:     () -> String
    let clearText:   () -> Void
    let focus:       () -> Void
    let getEvents:   () -> [RecordedKeyEvent]
    let clearEvents: () -> Void
    let quit:        () -> Void

    func dispatch(_ req: HTTPRequest) -> HTTPResponse {
        switch (req.method, req.path) {
        case (.GET,  "/health"):  return .json(["ok": true])
        case (.GET,  "/text"):    return handleGetText()
        case (.POST, "/clear"):   return handleClear()
        case (.POST, "/focus"):   return handleFocus()
        case (.GET,  "/events"):  return handleGetEvents()
        case (.POST, "/events/clear"): return handleClearEvents()
        case (.POST, "/quit"):    return handleQuit()
        default:
            return HTTPResponse.notFound(req.path)
        }
    }

    private func handleGetText() -> HTTPResponse {
        let s = getText()
        // Return both the raw string and its UTF-8 byte length so tests can
        // disambiguate "smart-quote rewrite" failures from "nothing pasted".
        return HTTPResponse.json([
            "text": s,
            "length": s.count,
            "utf8Bytes": Array(s.utf8).count,
        ])
    }

    private func handleClear() -> HTTPResponse {
        clearText()
        return HTTPResponse.json(["ok": true])
    }

    private func handleFocus() -> HTTPResponse {
        focus()
        return HTTPResponse.json(["ok": true])
    }

    private func handleGetEvents() -> HTTPResponse {
        let evs = getEvents()
        let arr: [[String: Any]] = evs.map { e in
            [
                "timestampMs":                  e.timestampMs,
                "keyCode":                      e.keyCode,
                "characters":                   e.characters,
                "charactersIgnoringModifiers":  e.charactersIgnoringModifiers,
                "modifierFlags":                e.modifierFlags,
                "isARepeat":                    e.isARepeat,
            ]
        }
        return HTTPResponse.json(["events": arr, "count": arr.count])
    }

    private func handleClearEvents() -> HTTPResponse {
        clearEvents()
        return HTTPResponse.json(["ok": true])
    }

    private func handleQuit() -> HTTPResponse {
        // Schedule shortly after responding so the HTTP reply makes it
        // back to the client before the process tears down.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            quit()
        }
        return HTTPResponse.json(["ok": true])
    }
}
