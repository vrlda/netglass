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
/// real elapsed time. Rates start at zero until a second snapshot exists.
/// Snapshots closer than `minInterval` are IGNORED (not even a baseline
/// refresh): the flows publisher fires several times per sampling tick, and
/// refreshing the baseline on each would push the next real measurement past
/// `minInterval` forever at the default 0.25 s cadence.
@MainActor
public final class AppRateTracker: ObservableObject {
    @Published public private(set) var rates: [String: (up: Double, down: Double)] = [:]

    private let minInterval: TimeInterval
    private var lastTotals: [String: (sent: UInt64, received: UInt64)] = [:]
    private var lastDate: Date?

    public init(minInterval: TimeInterval = 0.5) {
        self.minInterval = minInterval
    }

    public func update(apps: [AppAgg], now: Date = Date()) {
        var totals: [String: (sent: UInt64, received: UInt64)] = [:]
        for app in apps {
            totals[app.processPath] = (app.bytesSent, app.bytesReceived)
        }
        guard let lastDate, !lastTotals.isEmpty else {
            lastTotals = totals
            self.lastDate = now
            return
        }
        let elapsed = now.timeIntervalSince(lastDate)
        guard elapsed >= minInterval else { return }   // sub-interval noise
        var newRates: [String: (up: Double, down: Double)] = [:]
        for app in apps {
            guard let last = lastTotals[app.processPath] else { continue }
            let up = app.bytesSent >= last.sent
                ? Double(app.bytesSent - last.sent) / elapsed : 0
            let down = app.bytesReceived >= last.received
                ? Double(app.bytesReceived - last.received) / elapsed : 0
            newRates[app.processPath] = (up, down)
        }
        rates = newRates
        lastTotals = totals
        self.lastDate = now
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
    /// keeping the last `capacity` buckets. The trailing PARTIAL bucket is
    /// emitted too — that's the live bar that grows as traffic accumulates
    /// inside the current window. The y-scale is a held peak (no re-fit
    /// jumps), so growth stays smooth. The live chart uses 60 × 5 s = 5 min.
    public static func aggregate(_ history: [ThroughputSample],
                                 bucketSeconds: Int, capacity: Int) -> [TrafficChartSample] {
        guard !history.isEmpty else { return [] }
        var buckets: [TrafficChartSample] = []
        var accUp = 0.0
        var accDown = 0.0
        var count = 0
        var bucketStart: Date?
        for sample in history {
            if count == 0 { bucketStart = sample.date }
            accUp += sample.bytesPerSecondUp
            accDown += sample.bytesPerSecondDown
            count += 1
            if count == bucketSeconds {
                buckets.append(TrafficChartSample(id: bucketStart ?? sample.date,
                                                   up: accUp, down: accDown))
                accUp = 0
                accDown = 0
                count = 0
                bucketStart = nil
            }
        }
        if count > 0, let bucketStart {
            buckets.append(TrafficChartSample(id: bucketStart,
                                               up: accUp, down: accDown)) // growing live bar
        }
        if buckets.count > capacity {
            buckets.removeFirst(buckets.count - capacity)
        }
        return buckets
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
