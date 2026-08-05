import Foundation
import FlowModel

public protocol ProcessIdentityProviding: Sendable {
    func identity(for pid: Int32) -> ProcessIdentity?
}

public struct ProcessResolver: ProcessIdentityProviding {
    public init() {}

    public func identity(for pid: Int32) -> ProcessIdentity? {
        guard pid > 0, let path = executablePath(for: pid) else { return nil }
        return ProcessIdentity(pid: pid, startTime: nil, executablePath: path,
                               bundleIdentifier: bundleIdentifier(forExecutable: path),
                               parentPID: nil)
    }

    func executablePath(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)  // PROC_PIDPATHINFO_MAXSIZE
        let count = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard count > 0 else { return nil }
        return String(cString: buffer)
    }

    func bundleIdentifier(forExecutable path: String) -> String? {
        var url = URL(fileURLWithPath: path)
        for _ in 0..<8 {  // walk up max 8 levels
            if url.lastPathComponent.hasSuffix(".app") {
                let plistURL = url.appendingPathComponent("Contents/Info.plist")
                if let data = try? Data(contentsOf: plistURL),
                   let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
                       as? [String: Any],
                   let identifier = plist["CFBundleIdentifier"] as? String {
                    return identifier
                }
            }
            url = url.deletingLastPathComponent()
        }
        return nil
    }
}
