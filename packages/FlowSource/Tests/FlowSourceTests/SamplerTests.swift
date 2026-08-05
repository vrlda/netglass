import Foundation
import Testing
@testable import FlowModel
@testable import FlowSource

@Suite struct SamplerTests {
    @Test func sampleProducesJoinedEvents() throws {
        let base = try FixtureLocator.repoRoot()
        let sampler = Sampler(
            nettopClient: FileNettopClient(url: base.appendingPathComponent("Fixtures/nettop/synthetic.txt")),
            lsofClient: FileLsofClient(url: base.appendingPathComponent("Fixtures/lsof/synthetic.txt")),
            resolver: StubResolver())
        let events = try sampler.sample()
        #expect(events.contains { event in
            if case .flowOpened(let opened) = event {
                return opened.pid == 9217
                    && opened.remote.address.text == "149.154.167.51"
                    && opened.process?.executablePath == "/Applications/Telegram.app/Contents/MacOS/Telegram"
            }
            return false
        })
    }

    @Test func sampleIsIdempotentOnSameFixtures() throws {
        let base = try FixtureLocator.repoRoot()
        let sampler = Sampler(
            nettopClient: FileNettopClient(url: base.appendingPathComponent("Fixtures/nettop/synthetic.txt")),
            lsofClient: FileLsofClient(url: base.appendingPathComponent("Fixtures/lsof/synthetic.txt")),
            resolver: StubResolver())
        let first = try sampler.sample()
        let second = try sampler.sample()
        // same fixtures → same flowIDs for still-present flows; second sample has no new opens
        let secondOpened = second.compactMap { event -> UUID? in
            if case .flowOpened(let opened) = event { return opened.flowID }
            return nil
        }
        #expect(secondOpened.isEmpty)
        #expect(first.count > 0)
    }

    private struct StubResolver: ProcessIdentityProviding {
        func identity(for pid: Int32) -> ProcessIdentity? {
            ProcessIdentity(pid: pid, startTime: nil,
                            executablePath: "/Applications/Telegram.app/Contents/MacOS/Telegram",
                            bundleIdentifier: "org.telegram.desktop", parentPID: nil)
        }
    }
}
