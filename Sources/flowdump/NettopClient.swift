import Foundation

public enum SamplingError: Error, Equatable {
    case terminated(Int32)
}

public protocol NettopClient: Sendable {
    func sample() throws -> String
}

public protocol LsofClient: Sendable {
    func sample() throws -> String
}

public struct ProcessNettopClient: NettopClient {
    public init() {}

    public func sample() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-n", "-L", "1", "-J", "bytes_in,bytes_out,interface,state,time"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SamplingError.terminated(process.terminationStatus)
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

public struct ProcessLsofClient: LsofClient {
    public init() {}

    public func sample() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-i", "-n", "-P"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SamplingError.terminated(process.terminationStatus)
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

public struct FileNettopClient: NettopClient {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func sample() throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}

public struct FileLsofClient: LsofClient {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func sample() throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
