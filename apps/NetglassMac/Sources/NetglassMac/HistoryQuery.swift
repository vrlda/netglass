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
}
