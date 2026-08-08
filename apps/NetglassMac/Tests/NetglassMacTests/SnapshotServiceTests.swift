import Foundation
import Testing
@testable import FlowSource
@testable import NetglassMac

@Suite struct SnapshotServiceTests {
    @Test func parsesDefaultRoute() {
        let output = """
           route to: default
        destination: default
           mask: default
        gateway: 192.168.1.1
          interface: en0
        """
        #expect(SnapshotService.parseRouteInterface(output) == "en0")
        #expect(SnapshotService.parseRouteInterface("garbage") == nil)
    }

    @Test func parsesScutilDNS() {
        let output = """
        DNS configuration

        resolver #1
          search domain[0] : example.com
          nameserver[0] : 192.168.1.1
          nameserver[1] : 8.8.8.8

        DNS configuration (for scoped queries)

        resolver #1
          nameserver[0] : 10.20.0.1
          if_index : 15 (utun4)
        """
        let resolvers = SnapshotService.parseResolvers(output)
        #expect(resolvers.count == 2)
        #expect(resolvers[0].nameservers == ["192.168.1.1", "8.8.8.8"])
        #expect(resolvers[1].nameservers == ["10.20.0.1"])
    }
}
