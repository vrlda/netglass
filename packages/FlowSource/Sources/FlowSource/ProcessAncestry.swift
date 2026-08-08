import Foundation
import FlowModel

/// Walks the parent chain of a process (pid -> ppid -> ...) for the
/// connection inspector's "who spawned this" view. Root-first ordering.
/// Resolves parents itself (each identity's parentPID is read in the same
/// loop iteration as its own path, so the chain links are consistent) —
/// the sampler's hot `identity(for:)` path stays free of the extra syscall.
public enum ProcessAncestry {
    public static let maxDepth = 12

    public static func chain(for pid: Int32) -> [ProcessIdentity] {
        let resolver = ProcessResolver()
        var chain: [ProcessIdentity] = []
        var seen = Set<Int32>()
        var current: Int32 = pid
        while chain.count < maxDepth, current > 0, !seen.contains(current) {
            seen.insert(current)
            let path = resolver.executablePath(for: current)
            let parent = resolver.parentPID(for: current)
            chain.append(ProcessIdentity(
                pid: current, startTime: nil, executablePath: path ?? "",
                bundleIdentifier: path.flatMap { resolver.bundleIdentifier(forExecutable: $0) },
                parentPID: parent))
            guard let parent, parent != current else { break }
            current = parent
        }
        return chain.reversed()
    }
}
