import Foundation
import FlowModel
import Persistence

/// History search: matches against executable path, bundle id, IP text,
/// and remote port. Pure helper — unit-testable without UI.
public enum HistoryQuery {
    public static func search(database: FlowDatabase, text: String, limit: Int = 500)
        throws -> [StoredFlow] {
        let query = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return try database.flows(limit: limit) }

        var results: [StoredFlow] = []
        if let port = UInt16(query) {
            results += try database.flows(remotePort: port, limit: limit)
        }
        if let address = IPAddress(text: query) {
            results += try database.flows(remoteAddress: address, limit: limit)
        }
        if results.isEmpty {
            // fall back to process path substring: fetch and filter (M2 keeps
            // this O(n) since history tables are small; M3 adds SQL LIKE index)
            results = try database.flows(limit: limit).filter {
                $0.processPath.lowercased().contains(query)
                    || ($0.bundleIdentifier?.lowercased().contains(query) ?? false)
            }
        }
        // dedupe by flowID, newest first
        var seen = Set<UUID>()
        return results.filter { seen.insert($0.flowID).inserted }
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// Groups flows by executable path. Groups are sorted by total bytes
    /// (down+up) descending; flows within a group newest first.
    public static func grouped(database: FlowDatabase, text: String, limit: Int = 500)
        throws -> [HistoryGroup] {
        let flows = try search(database: database, text: text, limit: limit)
        var buckets: [String: [StoredFlow]] = [:]
        for flow in flows {
            buckets[flow.processPath, default: []].append(flow)
        }
        return buckets.map { HistoryGroup(kind: .app(processPath: $0.key), flows: $0.value) }
            .sorted { $0.totalBytes > $1.totalBytes }
    }

    /// Groups flows by their domain evidence (unresolved flows fall back to
    /// the app path). Sorted by total bytes descending, newest first inside.
    public static func groupedByDomain(database: FlowDatabase, text: String, limit: Int = 500)
        throws -> [HistoryGroup] {
        let flows = try search(database: database, text: text, limit: limit)
        var buckets: [String: [StoredFlow]] = [:]
        for flow in flows {
            let key = flow.domain.isEmpty ? flow.processPath : flow.domain
            buckets[key, default: []].append(flow)
        }
        return buckets.map { HistoryGroup(kind: .domain(name: $0.key), flows: $0.value) }
            .sorted { $0.totalBytes > $1.totalBytes }
    }
}

/// One group of the history: an app's or a domain's share of flows.
public struct HistoryGroup: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case app(processPath: String)
        case domain(name: String)
    }

    public let kind: Kind
    public let flows: [StoredFlow]

    public init(kind: Kind, flows: [StoredFlow]) {
        self.kind = kind
        self.flows = flows.sorted { $0.startedAt > $1.startedAt }
    }

    public var title: String {
        switch kind {
        case .app(let processPath):
            processPath.split(separator: "/").last.map(String.init) ?? processPath
        case .domain(let name):
            // unresolved flows fall back to their app path as the group key
            name.contains("/")
                ? (name.split(separator: "/").last.map(String.init) ?? name)
                : name
        }
    }

    public var processPath: String? {
        if case .app(let processPath) = kind { return processPath }
        return nil
    }

    public var totalBytesReceived: UInt64 {
        flows.reduce(0) { $0 + $1.bytesReceived }
    }

    public var totalBytesSent: UInt64 {
        flows.reduce(0) { $0 + $1.bytesSent }
    }

    public var totalBytes: UInt64 { totalBytesReceived + totalBytesSent }
}
