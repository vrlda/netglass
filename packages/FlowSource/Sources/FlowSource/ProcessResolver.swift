import Foundation
import FlowModel

public protocol ProcessIdentityProviding: Sendable {
    func identity(for pid: Int32) -> ProcessIdentity?
}

public struct ProcessResolver: ProcessIdentityProviding {
    /// Info.plist reads are disk I/O: cache bundle ids by executable path so
    /// a per-tick resolver pass doesn't touch the filesystem repeatedly.
    private let bundleCache = BundleIDCache()

    public init() {}

    public func identity(for pid: Int32) -> ProcessIdentity? {
        guard pid > 0, let path = executablePath(for: pid) else { return nil }
        return ProcessIdentity(pid: pid, startTime: nil, executablePath: path,
                               bundleIdentifier: bundleIdentifier(forExecutable: path),
                               parentPID: parentPID(for: pid))
    }

    func parentPID(for pid: Int32) -> Int32? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size))
        guard result == size, info.pbi_ppid > 0 else { return nil }
        return Int32(info.pbi_ppid)
    }

    func executablePath(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)  // PROC_PIDPATHINFO_MAXSIZE
        let count = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard count > 0 else { return nil }
        return String(cString: buffer)
    }

    func bundleIdentifier(forExecutable path: String) -> String? {
        if let cached = bundleCache.value(for: path) {
            return cached
        }
        var result: String?
        var url = URL(fileURLWithPath: path)
        for _ in 0..<8 {  // walk up max 8 levels
            if url.lastPathComponent.hasSuffix(".app") {
                let plistURL = url.appendingPathComponent("Contents/Info.plist")
                if let data = try? Data(contentsOf: plistURL),
                   let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
                       as? [String: Any],
                   let identifier = plist["CFBundleIdentifier"] as? String {
                    result = identifier
                    break
                }
            }
            url = url.deletingLastPathComponent()
        }
        bundleCache.set(result, for: path)
        return result
    }
}

/// Locked cache: the resolver runs from the sampling task.
private final class BundleIDCache: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String?] = [:]

    func value(for path: String) -> String?? {
        lock.lock()
        defer { lock.unlock() }
        return values[path]   // nil = not cached; .some(nil) = cached miss
    }

    func set(_ identifier: String?, for path: String) {
        lock.lock()
        defer { lock.unlock() }
        values[path] = identifier
    }
}
