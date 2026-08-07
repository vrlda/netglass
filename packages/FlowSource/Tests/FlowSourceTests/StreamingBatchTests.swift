import Foundation
import Testing
@testable import FlowSource

@Suite struct StreamingBatchTests {
    private let header = StreamingNettopClient.header

    @Test func completesBatchesOnHeaderBoundaries() {
        let chunk = """
        \(header)
        row1,1,
        row2,2,
        \(header)
        row3,3,
        """
        let (completed, rest) = StreamingNettopClient.splitBatches(header, chunk, pending: "")
        #expect(completed.count == 1)
        #expect(completed[0].contains("row1,1,"))
        #expect(completed[0].contains("row2,2,"))
        // the second (still open) batch stays pending
        #expect(rest.contains("\(header)\nrow3,3,"))
    }

    @Test func handlesChunksSplitMidBatch() {
        // first chunk ends mid-batch; second chunk finishes it and opens a new one
        let first = "\(header)\nrow1,1,\nrow2,2,"
        let (c1, r1) = StreamingNettopClient.splitBatches(header, first, pending: "")
        #expect(c1.isEmpty)                       // batch not complete yet
        #expect(r1.contains("row2,2,"))           // partial line kept

        let second = "3,\n\(header)\nrow4,4,\n"
        let (c2, r2) = StreamingNettopClient.splitBatches(header, second, pending: r1)
        #expect(c2.count == 1)                    // batch completed by the new header
        #expect(c2[0].contains("row2,2,3,"))
        #expect(c2[0].contains("row1,1,"))
        #expect(r2.contains("row4,4,"))
    }

    @Test func neverPublishesTruncatedBatch() {
        let chunk = "\(header)\nrow1,1,\nrow2,2"
        let (completed, _) = StreamingNettopClient.splitBatches(header, chunk, pending: "")
        #expect(completed.isEmpty)
    }
}
