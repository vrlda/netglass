import Foundation
import FlowModel
import FlowSource
import Persistence

signal(SIGPIPE, SIG_IGN)   // EPIPE on stdout write surfaces as an error, not a kill

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.first == "--help" {
    print(usage())
    exit(0)
}

do {
    let config = try parseArguments(arguments)
    let db = try config.dbPath.map { try FlowDatabase(path: $0) }
    defer { db?.close() }
    try run(config: config,
            nettopClient: ProcessNettopClient(),
            lsofClient: ProcessLsofClient(),
            db: db) { event in
        let data = try FlowJSON.encoder.encode(event)
        let line = String(data: data, encoding: .utf8) ?? ""
        try FileHandle.standardOutput.write(contentsOf: Data((line + "\n").utf8))
    }
} catch ArgumentError.unknownFlag, ArgumentError.missingValue, ArgumentError.invalidValue {
    print(usage())
    exit(2)
} catch {
    let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError
    let isBrokenPipe = underlying?.domain == NSPOSIXErrorDomain && underlying?.code == Int(EPIPE)
    if isBrokenPipe { exit(0) }
    try? FileHandle.standardError.write(contentsOf: Data("error: \(error)\n".utf8))
    exit(1)
}
