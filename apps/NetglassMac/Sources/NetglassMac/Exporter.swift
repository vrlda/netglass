import Foundation
import FlowModel
import Persistence

public enum Exporter {
    public static func exportJSON(_ flows: [StoredFlow], to url: URL) throws {
        let data = try FlowJSON.encoder.encode(flows)
        try data.write(to: url, options: .atomic)
    }

    public static func exportCSV(_ flows: [StoredFlow], to url: URL) throws {
        var lines = ["flow_id,process_path,bundle_identifier,transport,local_address,local_port,remote_address,remote_port,started_at,ended_at,bytes_sent,bytes_received"]
        for flow in flows {
            let fields = [
                flow.flowID.uuidString,
                csvEscape(flow.processPath),
                csvEscape(flow.bundleIdentifier ?? ""),
                flow.transport.rawValue,
                flow.localAddress.text,
                String(flow.localPort),
                flow.remoteAddress.text,
                String(flow.remotePort),
                iso8601(flow.startedAt),
                flow.endedAt.map(iso8601) ?? "",
                String(flow.bytesSent),
                String(flow.bytesReceived),
            ]
            lines.append(fields.joined(separator: ","))
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func csvEscape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func iso8601(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}
