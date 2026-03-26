import Foundation

/// Serializes MapKit Directions calls so the app stays under Apple's ~50 requests / 60s quota.
actor DirectionsRateLimiter {
    static let shared = DirectionsRateLimiter()

    /// Minimum spacing between any two `MKDirections.calculate` calls in this process.
    private let minIntervalSeconds: Double = 1.2
    private var lastRequestEnd: CFAbsoluteTime = 0

    func acquireSlot() async throws {
        try Task.checkCancellation()
        let now = CFAbsoluteTimeGetCurrent()
        let wait = lastRequestEnd + minIntervalSeconds - now
        if wait > 0 {
            try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            try Task.checkCancellation()
        }
    }

    func markRequestCompleted() {
        lastRequestEnd = CFAbsoluteTimeGetCurrent()
    }
}
