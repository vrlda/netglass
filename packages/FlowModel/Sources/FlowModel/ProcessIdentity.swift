import Foundation

public struct ProcessIdentity: Codable, Hashable, Sendable {
    public let pid: Int32
    public let startTime: Date?          // nil until M3 (sysctl-based)
    public let executablePath: String
    public let bundleIdentifier: String?
    public let parentPID: Int32?         // nil until M3

    public init(pid: Int32, startTime: Date?, executablePath: String,
                bundleIdentifier: String?, parentPID: Int32?) {
        self.pid = pid
        self.startTime = startTime
        self.executablePath = executablePath
        self.bundleIdentifier = bundleIdentifier
        self.parentPID = parentPID
    }
}
