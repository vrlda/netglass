import Foundation
import Testing
@testable import FlowModel
@testable import FlowSource
@testable import NetglassMac

@Suite struct OperationSessionTests {
    @Test func sessionAddsEventsAndWarnings() {
        var session = OperationSession.make(name: "Op 1", expectedTunnel: "utun4",
                                            scope: OperationScope(), snapshotIn: OperationSnapshot(date: Date()))
        let event = OperationEvent.connection(
            opened: true, date: Date(), process: "nmap", executablePath: "/usr/local/bin/nmap",
            remote: NetworkEndpoint(address: IPAddress(text: "10.20.30.1")!, port: 443),
            interface: "utun4", transport: .tcp, bytes: 100)
        session.events.append(event)
        session.warnings.append(LeakWarning(
            rule: .interfaceMismatch, severity: .critical,
            title: "Traffic bypassing tunnel", details: ["x"]))
        #expect(session.events.count == 1)
        #expect(session.warnings.count == 1)
        #expect(session.name == "Op 1")
    }

    @Test func cleanupReportDiffsListenersAndResolvers() {
        let snapshotIn = OperationSnapshot(
            date: Date(),
            resolvers: [ResolverConfig(nameservers: ["192.168.1.1"])],
            listeners: [LsofListener(pid: 1, processName: "sshd", transport: .tcp,
                                     address: "127.0.0.1", port: 22)])
        let snapshotOut = OperationSnapshot(
            date: Date().addingTimeInterval(60),
            resolvers: [ResolverConfig(nameservers: ["10.20.0.1"])],
            listeners: [LsofListener(pid: 1, processName: "sshd", transport: .tcp,
                                     address: "127.0.0.1", port: 22),
                        LsofListener(pid: 2, processName: "python3", transport: .tcp,
                                     address: "0.0.0.0", port: 8000)])
        let report = CleanupReport(snapshotIn: snapshotIn, snapshotOut: snapshotOut,
                                   liveFlows: [], endedAt: snapshotOut.date)
        #expect(report.listenersStillOpen == ["python3:0.0.0.0:8000"])
        #expect(report.resolverChanged)
    }
}
