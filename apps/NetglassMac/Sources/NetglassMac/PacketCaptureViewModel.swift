import Foundation

/// Scope of an explicit packet capture.
public enum CaptureScope: String, CaseIterable, Identifiable, Hashable, Sendable {
    case allTraffic = "All Traffic"
    case application = "Application"
    case process = "Process"
    case connection = "Connection"
    case domain = "Domain"
    case ipAddress = "IP Address"
    case port = "Port"
    case protocolName = "Protocol"
    case interface = "Interface"

    public var id: String { rawValue }
}

/// Lifecycle of a packet capture session.
public enum CaptureStatus: String, Hashable, Sendable {
    case recording, completed, failed, imported
}

/// A real packet capture session (tcpdump output, pcap format).
public struct CaptureSession: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let startedAt: Date
    public var duration: TimeInterval
    public let scope: CaptureScope
    public let scopeValue: String?
    public let interface: String
    public let fileURL: URL
    public var fileSize: Int64
    public var packetCount: Int
    public var status: CaptureStatus
    public let relatedApp: String?
    public let relatedDomain: String?
    public let relatedConnection: String?
}

/// Real packet capture: runs tcpdump elevated (one-time admin authorization)
/// into Application Support/Netglass/captures, tracks size/elapsed, stops via
/// a stop-file handshake. No packets are buffered in memory.
@MainActor
public final class PacketCaptureViewModel: ObservableObject {
    @Published public private(set) var sessions: [CaptureSession] = []
    @Published public private(set) var currentScope: CaptureScope = .allTraffic
    @Published public private(set) var scopeValue: String?
    @Published public var activeInterface: String
    /// Real packet rate derived from parsing the growing capture file.
    @Published public private(set) var packetsPerSecond: Double = 0
    /// Rolling per-second packet-rate history for the packets/s chart mode.
    @Published public private(set) var packetsHistory: [TrafficChartSample] = []

    private var activeSession: CaptureSession?
    private var ticker: Timer?
    private var captureProcess: Process?
    private var lastPacketCount: Int?
    private var lastPacketCountDate: Date?

    public init(interface: String? = nil) {
        self.activeInterface = interface ?? InterfaceStore.primary()
    }

    public var isRecording: Bool { activeSession != nil }

    public var elapsed: TimeInterval { activeSession?.duration ?? 0 }
    public var capturedBytes: Int64 { activeSession?.fileSize ?? 0 }

    /// tcpdump filter expression for a scope (pure, testable).
    public nonisolated static func filterExpression(scope: CaptureScope, value: String?) -> String {
        switch scope {
        case .allTraffic:
            return ""
        case .connection:
            guard let value else { return "" }
            let parts = value.split(separator: ":")
            if parts.count == 2, let port = UInt16(parts[1]) {
                return "host \(parts[0]) and port \(port)"
            }
            return "host \(value)"
        case .domain, .ipAddress:
            return value.map { "host \($0)" } ?? ""
        case .port:
            return value.map { "port \($0)" } ?? ""
        case .protocolName:
            guard let value else { return "" }
            switch value.lowercased() {
            case "tcp": return "tcp"
            case "udp": return "udp"
            case "icmp": return "icmp"
            default: return ""
            }
        case .application, .process, .interface:
            return ""
        }
    }

    public func start(scope: CaptureScope = .allTraffic, value: String? = nil,
                      interface: String? = nil,
                      rotationMB: Double? = nil, rotationFiles: Int? = nil) {
        guard !isRecording else { return }
        let iface = interface ?? activeInterface
        currentScope = scope
        scopeValue = value
        activeInterface = iface
        // capture settings → tcpdump ring rotation when enabled
        let defaults = UserDefaults.standard
        if rotationMB == nil {
            let configuredMB = defaults.double(forKey: "maxCaptureSize")
            let autoDelete = defaults.bool(forKey: "autoDeleteCaptures")
            if autoDelete, configuredMB > 0 {
                let files = max(2, Int((500.0 / configuredMB).rounded(.up)))
                self.rotationMB = configuredMB
                self.rotationFiles = files
            } else {
                self.rotationMB = nil
                self.rotationFiles = nil
            }
        } else {
            self.rotationMB = rotationMB
            self.rotationFiles = rotationFiles
        }
        packetsPerSecond = 0
        packetsHistory.removeAll()
        lastPacketCount = nil
        lastPacketCountDate = nil

        let dir = Self.captureDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileName = "capture-\(Int(Date().timeIntervalSince1970)).pcap"
        let fileURL = dir.appendingPathComponent(fileName)
        let filter = Self.filterExpression(scope: scope, value: value)
        let pidURL = dir.appendingPathComponent("\(fileName).pid")
        let stopURL = dir.appendingPathComponent("\(fileName).stop")
        try? FileManager.default.removeItem(at: stopURL)

        let session = CaptureSession(
            id: fileName, name: "\(scope.rawValue)\(value.map { " · \($0)" } ?? "") — \(Date().formatted(date: .abbreviated, time: .shortened))",
            startedAt: Date(), duration: 0, scope: scope, scopeValue: value,
            interface: iface, fileURL: fileURL, fileSize: 0, packetCount: 0,
            status: .recording,
            relatedApp: scope == .application ? value : nil,
            relatedDomain: scope == .domain ? value : nil,
            relatedConnection: scope == .connection ? value : nil)
        activeSession = session
        sessions.insert(session, at: 0)

        let script = Self.elevatedScript(fileURL: fileURL.path, interface: iface,
                                         filter: filter, pidFile: pidURL.path,
                                         stopFile: stopURL.path,
                                         rotationMB: rotationMB, rotationFiles: rotationFiles)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.terminationHandler = { [weak self] proc in
            MainActor.assumeIsolated {
                self?.onCaptureProcessExit(proc)
            }
        }
        captureProcess = process
        do {
            try process.run()
        } catch {
            failCurrent()
        }

        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    public func deleteSession(_ session: CaptureSession) {
        sessions.removeAll { $0.id == session.id }
    }

    public func stop() {
        guard let session = activeSession else { return }
        let stopURL = Self.captureDirectory()
            .appendingPathComponent("\(session.id).stop")
        try? Data().write(to: stopURL)
    }

    // MARK: - Internals

    private func tick() {
        guard let session = activeSession else { return }
        let now = Date()
        activeSession?.duration = now.timeIntervalSince(session.startedAt)
        let size = (try? FileManager.default.attributesOfItem(
            atPath: session.fileURL.path)[.size] as? Int64) ?? 0
        activeSession?.fileSize = size
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = activeSession!
        }
        // real packet rate from the growing capture file
        if let data = try? Data(contentsOf: session.fileURL),
           let packets = try? PcapParser.parse(data) {
            let count = packets.count
            if let lastPacketCount, let lastPacketCountDate {
                let dt = now.timeIntervalSince(lastPacketCountDate)
                if dt > 0.2 {
                    packetsPerSecond = Double(count - lastPacketCount) / dt
                }
            }
            self.lastPacketCount = count
            self.lastPacketCountDate = now
        }
        packetsHistory.append(TrafficChartSample(id: now, up: packetsPerSecond, down: 0))
        if packetsHistory.count > 300 {
            packetsHistory.removeFirst(packetsHistory.count - 300)
        }
    }

    private func onCaptureProcessExit(_ process: Process) {
        ticker?.invalidate()
        ticker = nil
        captureProcess = nil
        guard var session = activeSession else { return }
        activeSession = nil
        let size = (try? FileManager.default.attributesOfItem(
            atPath: session.fileURL.path)[.size] as? Int64) ?? 0
        session.fileSize = size
        session.duration = Date().timeIntervalSince(session.startedAt)
        session.packetCount = Self.packetCount(of: session.fileURL)
        session.status = (size > 0 || process.terminationStatus == 0) ? .completed : .failed
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        }
    }

    private func failCurrent() {
        ticker?.invalidate()
        ticker = nil
        captureProcess = nil
        guard var session = activeSession else { return }
        activeSession = nil
        session.status = .failed
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        }
    }

    private static func packetCount(of url: URL) -> Int {
        guard let data = try? Data(contentsOf: url),
              let packets = try? PcapParser.parse(data) else { return 0 }
        return packets.count
    }

    private static func captureDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Netglass").appendingPathComponent("captures")
    }

    private var rotationMB: Double?
    private var rotationFiles: Int?

    /// Shell wrapper: starts tcpdump in the background, writes its pid, waits
    /// for the stop file, then terminates it. Runs elevated via osascript so
    /// the user grants capture permission with one password prompt. Optional
    /// rotation (`-C`/`-W`) implements a bounded ring buffer.
    nonisolated static func elevatedScript(fileURL: String, interface: String, filter: String,
                               pidFile: String, stopFile: String,
                               rotationMB: Double? = nil, rotationFiles: Int? = nil) -> String {
        let escapedFile = fileURL.replacingOccurrences(of: "'", with: "'\\''")
        let escapedPid = pidFile.replacingOccurrences(of: "'", with: "'\\''")
        let escapedStop = stopFile.replacingOccurrences(of: "'", with: "'\\''")
        var rotation = ""
        if let rotationMB, let rotationFiles, rotationMB > 0, rotationFiles > 1 {
            rotation = " -C \(Int(rotationMB)) -W \(rotationFiles)"
        }
        let tcpdumpCmd = "/usr/sbin/tcpdump -i \(interface) -nn\(rotation) -w \(escapedFile) \(filter)"
        return """
        do shell script "'/bin/sh' -c '\
        rm -f \(escapedStop); \
        \(tcpdumpCmd) >/dev/null 2>&1 & \
        echo $! > \(escapedPid); \
        while [ ! -f \(escapedStop) ]; do sleep 0.25; done; \
        kill $(cat \(escapedPid)) 2>/dev/null; wait'"
        with administrator privileges
        """
    }
}
