import Foundation
import FlowModel
import Persistence

public struct CLIConfig: Sendable {
    public var duration: TimeInterval?
    public var interval: TimeInterval
    public var dbPath: String?
    public var processFilter: String?

    public init(duration: TimeInterval? = nil, interval: TimeInterval = 2.0,
                dbPath: String? = nil, processFilter: String? = nil) {
        self.duration = duration
        self.interval = interval
        self.dbPath = dbPath
        self.processFilter = processFilter
    }
}

public enum ArgumentError: Error, Equatable {
    case unknownFlag(String)
    case missingValue(String)
    case invalidValue(String, String)
}

public func parseArguments(_ args: [String]) throws -> CLIConfig {
    var config = CLIConfig()
    var index = 0
    while index < args.count {
        let flag = args[index]
        func value() throws -> String {
            guard index + 1 < args.count else { throw ArgumentError.missingValue(flag) }
            index += 1
            return args[index]
        }
        switch flag {
        case "--duration":
            guard let duration = TimeInterval(try value()) else {
                throw ArgumentError.invalidValue(flag, args[index])
            }
            config.duration = duration
        case "--interval":
            guard let interval = TimeInterval(try value()) else {
                throw ArgumentError.invalidValue(flag, args[index])
            }
            config.interval = interval
        case "--db":
            config.dbPath = try value()
        case "--process":
            config.processFilter = try value()
        default:
            throw ArgumentError.unknownFlag(flag)
        }
        index += 1
    }
    guard config.interval > 0 else { throw ArgumentError.invalidValue("--interval", String(config.interval)) }
    if let duration = config.duration, duration <= 0 {
        throw ArgumentError.invalidValue("--duration", String(duration))
    }
    return config
}

public func usage() -> String {
    """
    usage: flowdump [--duration <seconds>] [--interval <seconds>] \
    [--db <path>] [--process <name>]

    Polls nettop + lsof and emits normalized, process-aware flow events as JSONL
    on stdout.

      --duration  run for N seconds, then exit (default: run forever)
      --interval  seconds between samples (default: 2)
      --db        SQLite history path (optional)
      --process   only emit flows whose process name contains <name>
    """
}

public func run(config: CLIConfig,
                nettopClient: NettopClient,
                lsofClient: LsofClient,
                db: FlowDatabase?,
                identityForPID: (Int32) -> ProcessIdentity? = { ProcessResolver().identity(for: $0) },
                emit: (FlowEvent) throws -> Void) throws {
    let nettopParser = NettopParser()
    let lsofParser = LsofParser()
    let joiner = SocketJoiner()
    let tracker = FlowSessionTracker()
    let start = Date()

    while config.duration.map({ Date().timeIntervalSince(start) < $0 }) ?? true {
        let nettopText = try nettopClient.sample()
        let lsofText = try lsofClient.sample()
        let connections = nettopParser.parse(nettopText)
        let sockets = lsofParser.parse(lsofText)
        var rows = joiner.join(connections: connections, sockets: sockets)
        if let filter = config.processFilter {
            rows = rows.filter { $0.processName.localizedCaseInsensitiveContains(filter) }
        }
        let events = tracker.ingest(rows, identityForPID: identityForPID)
        for event in events {
            try emit(event)
        }
        if let db { try db.ingest(events) }
        Thread.sleep(forTimeInterval: config.interval)
    }
}
