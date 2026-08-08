import Foundation

/// One connection-open observation fed to the periodic-communication detector.
public struct BeaconObservation: Equatable, Sendable {
    public let process: String
    public let destination: String   // "ip:port"
    public let date: Date
    public let bytes: UInt64
    public init(process: String, destination: String, date: Date, bytes: UInt64) {
        self.process = process
        self.destination = destination
        self.date = date
        self.bytes = bytes
    }
}

/// Recurring outbound pattern for one (process, destination). Deliberately
/// called "periodic communication", never C2 — the user interprets it.
public struct PeriodicPattern: Identifiable, Equatable, Sendable, Codable {
    public let id: String            // process|destination
    public let process: String
    public let destination: String
    public let intervalSeconds: Double
    public let jitter: Double        // stddev / mean of the intervals
    public let averagePayloadBytes: Double
    public let occurrences: Int
}

/// Detects regular outbound intervals per (process, destination): at least
/// `minOccurrences` connections with jitter below `maxJitter`. Pure and
/// stateful (emits each pattern once).
public struct BeaconDetector {
    public let minOccurrences: Int
    public let maxJitter: Double

    private var history: [String: [BeaconObservation]] = [:]
    private var emitted: Set<String> = []

    public init(minOccurrences: Int = 4, maxJitter: Double = 0.35) {
        self.minOccurrences = minOccurrences
        self.maxJitter = maxJitter
    }

    public mutating func ingest(_ observations: [BeaconObservation]) -> [PeriodicPattern] {
        var patterns: [PeriodicPattern] = []
        for observation in observations {
            let key = "\(observation.process)|\(observation.destination)"
            history[key, default: []].append(observation)
        }
        for (key, entries) in history where !emitted.contains(key) {
            guard entries.count >= minOccurrences,
                  let pattern = pattern(for: key, entries: entries) else { continue }
            emitted.insert(key)
            patterns.append(pattern)
        }
        return patterns
    }

    func pattern(for key: String, entries: [BeaconObservation]) -> PeriodicPattern? {
        let sorted = entries.sorted { $0.date < $1.date }
        guard sorted.count >= minOccurrences else { return nil }
        var intervals: [Double] = []
        for i in 1..<sorted.count {
            intervals.append(sorted[i].date.timeIntervalSince(sorted[i - 1].date))
        }
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        guard mean > 0 else { return nil }
        let variance = intervals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(intervals.count)
        let jitter = variance.squareRoot() / mean
        guard jitter < maxJitter else { return nil }
        let parts = key.split(separator: "|", maxSplits: 1)
        let payload = Double(sorted.reduce(0) { $0 + $1.bytes }) / Double(sorted.count)
        return PeriodicPattern(id: key,
                               process: String(parts[0]),
                               destination: String(parts[1]),
                               intervalSeconds: mean,
                               jitter: jitter,
                               averagePayloadBytes: payload,
                               occurrences: sorted.count)
    }
}
