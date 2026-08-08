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
    private static let drainQueue = DispatchQueue(label: "netglass.nettop-drain")

    public init() {}

    public func sample() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-n", "-L", "1", "-J", "bytes_in,bytes_out,interface,state,time"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.standardError

        // happens-before via drain group wait(): the queue block completes before
        // wait() returns, so cross-thread access below needs no synchronization.
        nonisolated(unsafe) var captured = Data()
        let queue = Self.drainQueue
        let drain = DispatchGroup()
        drain.enter()
        queue.async {
            captured = output.fileHandleForReading.readDataToEndOfFile()
            drain.leave()
        }
        do {
            try process.run()
        } catch {
            output.fileHandleForWriting.closeFile()   // unblock the drain if run failed
            throw error
        }
        process.waitUntilExit()
        drain.wait()
        guard process.terminationStatus == 0 else {
            throw SamplingError.terminated(process.terminationStatus)
        }
        return String(data: captured, encoding: .utf8) ?? ""
    }
}

/// Long-lived nettop: ONE subprocess streams batches at `interval` seconds;
/// `sample()` returns the latest COMPLETE batch. Eliminates the per-tick
/// subprocess spawn (the dominant idle CPU cost) and the per-tick queue
/// churn. Self-starts on the first sample; no wiring changes needed.
/// Note: nettop clamps its sample cadence to 1 Hz on modern macOS, and
/// requesting 0.25 s makes it burn CPU internally — the default is 1 s.
public final class StreamingNettopClient: NettopClient, @unchecked Sendable {
    public static let header = "time,,interface,state,bytes_in,bytes_out,"

    private let lock = NSLock()
    private var latestBatch = ""
    private var pending = ""
    private var process: Process?
    private var started = false
    private var interval: Double

    public init(interval: Double = 1.0) {
        self.interval = interval
    }

    public func sample() throws -> String {
        startIfNeeded()
        lock.lock()
        defer { lock.unlock() }
        return latestBatch
    }

    public func stop() {
        lock.lock()
        started = false
        let process = self.process
        self.process = nil
        lock.unlock()
        process?.terminate()
    }

    /// Changes the sampling cadence. The running nettop is terminated and
    /// restarted lazily with the new `-L` on the next sample.
    public func setInterval(_ newInterval: Double) {
        lock.lock()
        interval = newInterval
        started = false
        let process = self.process
        self.process = nil
        lock.unlock()
        process?.terminate()
    }

    deinit { stop() }

    private func startIfNeeded() {
        lock.lock()
        guard !started else { lock.unlock(); return }
        started = true
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-n", "-L", String(interval),
                             "-J", "bytes_in,bytes_out,interface,state,time"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            started = false
            lock.unlock()
            return
        }
        self.process = process
        let handle = output.fileHandleForReading
        lock.unlock()
        handle.readabilityHandler = { [weak self] fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty, let self else {
                fileHandle.readabilityHandler = nil
                return
            }
            self.consume(String(data: data, encoding: .utf8) ?? "")
        }
    }

    private func consume(_ chunk: String) {
        let (completed, rest) = Self.splitBatches(Self.header, chunk, pending: pending)
        lock.lock()
        pending = rest
        if let last = completed.last {
            latestBatch = last
        }
        lock.unlock()
    }

    /// Pure batch splitting: emits COMPLETE batches (header line followed by
    /// its rows) — a batch is published only when the NEXT header arrives,
    /// so a chunk split mid-batch never yields a truncated table. The rest
    /// keeps the open batch's header so it can complete later.
    static func splitBatches(_ header: String, _ chunk: String,
                             pending: String) -> (completed: [String], rest: String) {
        let text = pending + chunk
        var completed: [String] = []
        var batchStart: String.Index?
        var cursor = text.startIndex
        while cursor < text.endIndex {
            guard let newline = text[cursor...].firstIndex(of: "\n") else { break }
            let line = text[cursor..<newline]
            if line.hasPrefix(header) {
                if let start = batchStart {
                    completed.append(String(text[start..<cursor]))
                }
                batchStart = cursor
            }
            cursor = text.index(after: newline)
        }
        let rest = batchStart.map { text[$0...] } ?? text[cursor...]
        return (completed, String(rest))
    }
}

public struct ProcessLsofClient: LsofClient {
    private static let drainQueue = DispatchQueue(label: "netglass.lsof-drain")

    public init() {}

    public func sample() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-i", "-n", "-P"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.standardError

        // happens-before via drain group wait(): the queue block completes before
        // wait() returns, so cross-thread access below needs no synchronization.
        nonisolated(unsafe) var captured = Data()
        let queue = Self.drainQueue
        let drain = DispatchGroup()
        drain.enter()
        queue.async {
            captured = output.fileHandleForReading.readDataToEndOfFile()
            drain.leave()
        }
        do {
            try process.run()
        } catch {
            output.fileHandleForWriting.closeFile()   // unblock the drain if run failed
            throw error
        }
        process.waitUntilExit()
        drain.wait()
        guard process.terminationStatus == 0 else {
            throw SamplingError.terminated(process.terminationStatus)
        }
        return String(data: captured, encoding: .utf8) ?? ""
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
