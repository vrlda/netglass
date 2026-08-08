import Foundation
import FlowSource

/// Captures read-only system state for operation snapshots: default route,
/// resolver configuration, and listening sockets. Subprocess output parsing
/// is pure; subprocess runs use the drain-queue pattern from ProcessNettopClient.
public enum SnapshotService {
    public static func capture() -> OperationSnapshot {
        let now = Date()
        return OperationSnapshot(
            date: now,
            defaultRouteInterface: run("/sbin/route", ["-n", "get", "default"]).flatMap(parseRouteInterface) ?? "",
            interfaces: InterfaceStore.interfaces(),
            resolvers: run("/usr/sbin/scutil", ["--dns"]).map(parseResolvers) ?? [],
            listeners: run("/usr/sbin/lsof", ["-i", "-n", "-P"]).map { LsofParser().parseListeners($0) } ?? [])
    }

    /// `interface: en0` from `route -n get default`.
    public static func parseRouteInterface(_ output: String) -> String? {
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            if parts.count == 2, parts[0] == "interface", !parts[1].isEmpty {
                return parts[1]
            }
        }
        return nil
    }

    /// Nameservers grouped per `resolver #N` section from `scutil --dns`.
    public static func parseResolvers(_ output: String) -> [ResolverConfig] {
        var resolvers: [ResolverConfig] = []
        var current: [String] = []
        for line in output.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("resolver #") || text.hasPrefix("DNS configuration") {
                if !current.isEmpty {
                    resolvers.append(ResolverConfig(nameservers: current))
                    current = []
                }
                continue
            }
            if text.hasPrefix("nameserver["), let colon = text.firstIndex(of: ":") {
                current.append(String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
            }
        }
        if !current.isEmpty {
            resolvers.append(ResolverConfig(nameservers: current))
        }
        return resolvers
    }

    private static func run(_ launchPath: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        nonisolated(unsafe) var captured = Data()
        let queue = DispatchQueue(label: "netglass.snapshot")
        let drain = DispatchGroup()
        drain.enter()
        queue.async {
            captured = output.fileHandleForReading.readDataToEndOfFile()
            drain.leave()
        }
        do {
            try process.run()
        } catch {
            output.fileHandleForWriting.closeFile()
            return nil
        }
        process.waitUntilExit()
        drain.wait()
        return String(data: captured, encoding: .utf8)
    }
}
