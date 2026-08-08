import Foundation
import FlowModel

/// Walks the parent chain of a process (pid -> ppid -> ...) for the
/// connection inspector's "who spawned this" view. Root-first ordering.
public enum ProcessAncestry {
    public static let maxDepth = 12

    public static func chain(for pid: Int32) -> [ProcessIdentity] {
        let resolver = ProcessResolver()
        var chain: [ProcessIdentity] = []
        var seen = Set<Int32>()
        var current: Int32 = pid
        while chain.count < maxDepth, current > 0, !seen.contains(current) {
            seen.insert(current)
            chain.append(resolver.identity(for: current) ?? ProcessIdentity(
                pid: current, startTime: nil, executablePath: "",
                bundleIdentifier: nil, parentPID: nil))
            guard let parent = resolver.parentPID(for: current), parent != current else { break }
            current = parent
        }
        return chain.reversed()
    }
}
