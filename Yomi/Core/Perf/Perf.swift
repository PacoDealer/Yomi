import os

/// Signpost intervals for the S129 performance baseline (RESEARCH §23.2). They show up in Instruments'
/// Points of Interest track, so "tap title → chapters visible" and friends read as numbers, before and after.
enum Perf {
    static let signposter = OSSignposter(subsystem: "pacodealer.Yomi", category: .pointsOfInterest)

    /// Starts a named interval; call `end()` on the result (usually in a `defer`).
    static func begin(_ name: StaticString) -> Interval {
        Interval(name: name, state: signposter.beginInterval(name, id: signposter.makeSignpostID()))
    }

    struct Interval {
        let name: StaticString
        let state: OSSignpostIntervalState
        func end() { Perf.signposter.endInterval(name, state) }
    }
}
