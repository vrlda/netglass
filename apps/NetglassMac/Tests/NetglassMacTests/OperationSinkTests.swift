import Foundation
import Testing
@testable import FlowModel
@testable import FlowSource
@testable import NetglassMac

@Suite struct OperationSinkTests {
    @MainActor
    @Test func sinkReceivesOpenedEvents() async throws {
        let base = try FixtureLocator.repoRoot()
        let model = LiveConnectionsModel(sampler: Sampler(
            nettopClient: FileNettopClient(url: base.appendingPathComponent("Fixtures/nettop/synthetic.txt")),
            lsofClient: FileLsofClient(url: base.appendingPathComponent("Fixtures/lsof/synthetic.txt")),
            resolver: TestResolver()),
            domainResolver: DomainResolver(lookup: NoopResolver()))
        var received: [OperationEvent] = []
        model.operationSink = { received.append(contentsOf: $0) }
        await model.runOnce()
        let opened = received.filter { event in
            guard case .connection(true, _, _, _, _, _, _, _) = event else { return false }
            return true
        }
        #expect(!opened.isEmpty)
        // the fixture's Telegram row carries interface en0
        let telegram = received.first { event in
            guard case .connection(true, _, let process, _, _, let interface, _, _) = event else { return false }
            return process == "Telegram" && interface == "en0"
        }
        #expect(telegram != nil)
    }

    struct TestResolver: ProcessIdentityProviding {
        func identity(for pid: Int32) -> ProcessIdentity? {
            ProcessIdentity(pid: pid, startTime: nil,
                            executablePath: "/Applications/Telegram.app/Contents/MacOS/Telegram",
                            bundleIdentifier: "org.telegram.desktop", parentPID: nil)
        }
    }

    struct NoopResolver: ReverseDNSResolving {
        func hostname(for ip: String) -> String? { nil }
        func ipAddresses(for hostname: String) -> [String] { [] }
    }
}
