import Foundation

/// The executor of the `.delay` action.
///
/// Converting `UInt64(ms)` to a negative value will cause an immediate runtime crash (trap), so it must always be checked here.
/// Clamp and then sleep. Set an upper limit, for a huge value due to typos in the number of presses.
/// Prevent accidents where macros remain stopped for hours.
public enum DelayActionExecutor {
    /// Delay step allowed range in milliseconds (1 ms ~ 1 hour).
    /// Validation also refers to this value during decoding.
    public static let allowedMs = 1...3_600_000

    public static func execute(ms: Int) async throws {
        let clamped = min(max(ms, 0), allowedMs.upperBound)
        try await Task.sleep(nanoseconds: UInt64(clamped) * 1_000_000)
    }
}
