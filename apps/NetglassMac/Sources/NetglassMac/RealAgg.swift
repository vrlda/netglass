import Foundation
import FlowModel
import Persistence

// MARK: - Real aggregations over live flows

/// One real application's aggregate from the live flow set.
public struct AppAgg: Identifiable, Equatable, Sendable {
    public let processPath: String
    public let pids: Set<Int32>
    public let activeConnections: Int
    public let bytesSent: UInt64
    public let bytesReceived: UInt64
    public let domains: Set<String>
    public let ips: Set<String>
    public let lastActive: Date
    public let destinations: [LiveDestination]

    public var id: String { processPath }

    public var name: String {
        processPath.split(separator: "/").last.map(String.init) ?? processPath
    }

    public var totalBytes: UInt64 { bytesSent + bytesReceived }
}

/// One real destination (endpoint or domain) of an app.
public struct LiveDestination: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let transport: TransportProtocol
    public let port: UInt16
    public let active: Bool
    public let evidence: String
    public let confidence: Double?
}

/// One real domain aggregate across apps.
public struct DomainAgg: Identifiable, Equatable, Sendable {
    public let name: String
    public let evidence: String
    public let confidence: Double?
    public let applications: Set<String>
    public let ipAddresses: Set<String>
    public let connections: Int
    public let bytesSent: UInt64
    public let bytesReceived: UInt64
    public let firstSeen: Date
    public let lastSeen: Date

    public var id: String { name }
}

/// Pure, deterministic aggregation from the live flow set.
public enum RealAgg {
    public static func apps(from flows: [LiveFlow]) -> [AppAgg] {
        var byPath: [String: [LiveFlow]] = [:]
        for flow in flows {
            byPath[flow.executablePath, default: []].append(flow)
        }
        return byPath.map { path, appFlows in
            let destinations = appFlows.map { flow -> LiveDestination in
                let evidence: String
                if let confidence = flow.remoteDomainConfidence {
                    evidence = confidence >= 0.5 ? "Verified by DNS" : "Reverse DNS estimate"
                } else {
                    evidence = "Unknown"
                }
                return LiveDestination(
                    id: "\(path)|\(flow.remote.address.text):\(flow.remote.port)",
                    name: flow.remoteDomain ?? flow.remote.address.text,
                    transport: flow.transport,
                    port: flow.remote.port,
                    active: flow.isActive,
                    evidence: evidence,
                    confidence: flow.remoteDomainConfidence)
            }
            return AppAgg(
                processPath: path,
                pids: Set(appFlows.map(\.pid)),
                activeConnections: appFlows.filter(\.isActive).count,
                bytesSent: appFlows.reduce(0) { $0 + $1.bytesSent },
                bytesReceived: appFlows.reduce(0) { $0 + $1.bytesReceived },
                domains: Set(appFlows.compactMap(\.remoteDomain)),
                ips: Set(appFlows.map { $0.remote.address.text }),
                lastActive: appFlows.map(\.startedAt).max() ?? Date.distantPast,
                destinations: destinations)
        }
        .sorted { $0.totalBytes > $1.totalBytes }
    }

    public static func domains(from flows: [LiveFlow]) -> [DomainAgg] {
        var byName: [String: [LiveFlow]] = [:]
        for flow in flows {
            let key = flow.remoteDomain ?? flow.remote.address.text
            byName[key, default: []].append(flow)
        }
        return byName.map { name, domainFlows in
            let confidence = domainFlows.compactMap(\.remoteDomainConfidence).max()
            let evidence: String
            if let confidence {
                evidence = confidence >= 0.5 ? "Verified by DNS" : "Reverse DNS estimate"
            } else {
                evidence = name.contains(".") ? "Unknown" : "Unknown"
            }
            return DomainAgg(
                name: name,
                evidence: evidence,
                confidence: confidence,
                applications: Set(domainFlows.map(\.processName)),
                ipAddresses: Set(domainFlows.map { $0.remote.address.text }),
                connections: domainFlows.count,
                bytesSent: domainFlows.reduce(0) { $0 + $1.bytesSent },
                bytesReceived: domainFlows.reduce(0) { $0 + $1.bytesReceived },
                firstSeen: domainFlows.map(\.startedAt).min() ?? Date.distantPast,
                lastSeen: domainFlows.map(\.startedAt).max() ?? Date.distantPast)
        }
        .sorted { $0.bytesReceived + $0.bytesSent > $1.bytesReceived + $1.bytesSent }
    }

    /// Unresolved destinations (no domain evidence) — real "new destinations".
    public static func unresolvedIPs(from flows: [LiveFlow]) -> [String] {
        Array(Set(flows.filter { $0.remoteDomain == nil }.map { $0.remote.address.text }))
            .sorted()
    }
}

/// Per-app current-rate tracker: deltas between successive snapshots over
/// real elapsed time. nettop refreshes its counters at ~1 Hz while ticks and
/// flow-publisher emissions run faster, so a rate is emitted ONLY when an
/// app's totals actually moved (measured from that app's last change). Frozen
/// totals keep the last rate; after `idleTimeout` of silence the rate decays
/// to zero. Rates start at zero until a second snapshot exists.
@MainActor
public final class AppRateTracker: ObservableObject {
    @Published public private(set) var rates: [String: (up: Double, down: Double)] = [:]

    private let minInterval: TimeInterval
    private let idleTimeout: TimeInterval
    private var lastTotals: [String: (sent: UInt64, received: UInt64)] = [:]
    private var lastDates: [String: Date] = [:]

    public init(minInterval: TimeInterval = 0.5, idleTimeout: TimeInterval = 2.0) {
        self.minInterval = minInterval
        self.idleTimeout = idleTimeout
    }

    public func update(apps: [AppAgg], now: Date = Date()) {
        var newRates = rates
        for app in apps {
            let totals: (sent: UInt64, received: UInt64) = (app.bytesSent, app.bytesReceived)
            guard let prev = lastTotals[app.processPath] else {
                lastTotals[app.processPath] = totals
                lastDates[app.processPath] = now
                continue
            }
            if prev.sent != totals.sent || prev.received != totals.received {
                let elapsed = now.timeIntervalSince(lastDates[app.processPath] ?? now)
                lastTotals[app.processPath] = totals
                lastDates[app.processPath] = now
                if elapsed >= minInterval {
                    let up = totals.sent >= prev.sent
                        ? Double(totals.sent - prev.sent) / elapsed : 0
                    let down = totals.received >= prev.received
                        ? Double(totals.received - prev.received) / elapsed : 0
                    newRates[app.processPath] = (up, down)
                }
            } else if now.timeIntervalSince(lastDates[app.processPath] ?? now) >= idleTimeout {
                newRates[app.processPath] = (0, 0)   // went quiet: decay to zero
            }
        }
        rates = newRates
    }

    /// Apps with live traffic, ranked by current rate (most traffic first).
    /// Drives the popover's recent-activity list: it reorders as rates change.
    public func activeApps(_ apps: [AppAgg]) -> [AppAgg] {
        func totalRate(_ app: AppAgg) -> Double {
            guard let rate = rates[app.processPath] else { return 0 }
            return rate.up + rate.down
        }
        return apps
            .filter { totalRate($0) > 0 }
            .sorted { totalRate($0) > totalRate($1) }
    }
}

// MARK: - Real chart data

/// A chart candle with stable identity. The bucket's first sample date stays
/// attached to it while the trailing partial bucket grows.
public struct TrafficChartSample: Identifiable, Equatable, Sendable {
    public let id: Date
    public let up: Double
    public let down: Double

    public init(id: Date, up: Double, down: Double) {
        self.id = id
        self.up = up
        self.down = down
    }

    public static let zero = TrafficChartSample(id: .distantPast, up: 0, down: 0)
}

/// Real traffic series for the traffic charts: the live 5-minute window comes
/// from in-memory per-second samples; longer ranges come from history buckets.
public enum TrafficHistory {
    /// seconds per bucket + bucket count for a time range.
    public static func bucketLayout(_ range: TimeRange) -> (seconds: Int, count: Int) {
        switch range {
        case .live, .fiveMinutes: (1, 300)      // unused; live samples
        case .hour: (60, 60)
        case .day: (600, 144)
        }
    }

    public static func liveSamples(_ history: [ThroughputSample]) -> [TrafficChartSample] {
        history.map {
            TrafficChartSample(id: $0.date, up: $0.bytesPerSecondUp,
                               down: $0.bytesPerSecondDown)
        }
    }

    /// Aggregates per-second history into fixed-width buckets (e.g. 5 s each),
    /// keeping the last `capacity` buckets. Buckets are aligned to WALL-CLOCK
    /// time, so trimming the history buffer (which drops the oldest sample
    /// every second once full) never shifts which samples a bucket sums —
    /// completed candles keep their value and identity forever. The trailing
    /// PARTIAL bucket is emitted too — that's the live bar that grows as
    /// traffic accumulates inside the current window. The y-scale is fixed,
    /// so growth stays smooth. The live chart uses 60 × 5 s = 5 min.
    public static func aggregate(_ history: [ThroughputSample],
                                 bucketSeconds: Int, capacity: Int) -> [TrafficChartSample] {
        guard !history.isEmpty else { return [] }
        let width = TimeInterval(max(1, bucketSeconds))
        var buckets: [TrafficChartSample] = []
        var bucketStart: Date?
        var accUp = 0.0
        var accDown = 0.0
        for sample in history {
            let start = alignedBucketStart(sample.date, width: width)
            if start != bucketStart {
                if let bucketStart {
                    buckets.append(TrafficChartSample(id: bucketStart,
                                                       up: accUp, down: accDown))
                }
                bucketStart = start
                accUp = 0
                accDown = 0
            }
            accUp += sample.bytesPerSecondUp
            accDown += sample.bytesPerSecondDown
        }
        if let bucketStart {
            buckets.append(TrafficChartSample(id: bucketStart,
                                               up: accUp, down: accDown)) // growing live bar
        }
        if buckets.count > capacity {
            buckets.removeFirst(buckets.count - capacity)
        }
        return buckets
    }

    /// The start of the wall-clock bucket containing `date` (e.g. 14:05:03 in
    /// 5 s buckets → 14:05:00). Stable across history trims and cadence drift.
    static func alignedBucketStart(_ date: Date, width: TimeInterval) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (t / width).rounded(.down) * width)
    }

    public static func bucketSamples(_ buckets: [TrafficBucket],
                                     secondsPerBucket: Int) -> [TrafficChartSample] {
        buckets.map {
            TrafficChartSample(id: $0.date,
                               up: Double($0.bytesSent) / Double(secondsPerBucket),
                               down: Double($0.bytesReceived) / Double(secondsPerBucket))
        }
    }
}
