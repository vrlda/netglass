import Foundation
import Testing
@testable import NetglassMac

@Suite struct BeaconDetectorTests {
    @Test func regularSequenceDetected() {
        var detector = BeaconDetector()
        let t0 = Date(timeIntervalSince1970: 1_752_800_000)
        let observations = (0..<4).map { i in
            BeaconObservation(process: "helper", destination: "198.51.100.24:443",
                              date: t0.addingTimeInterval(TimeInterval(i) * 60), bytes: 1_800)
        }
        let patterns = detector.ingest(observations)
        #expect(patterns.count == 1)
        let pattern = try! #require(patterns.first)
        #expect(pattern.process == "helper")
        #expect(abs(pattern.intervalSeconds - 60) < 1)
        #expect(pattern.jitter < 0.01)
        #expect(pattern.averagePayloadBytes == 1_800)
        #expect(pattern.occurrences == 4)
    }

    @Test func irregularSequenceNotDetected() {
        var detector = BeaconDetector()
        let t0 = Date(timeIntervalSince1970: 1_752_800_000)
        let intervals: [TimeInterval] = [10, 300, 5]
        var date = t0
        let observations = intervals.map { step in
            let observation = BeaconObservation(process: "helper", destination: "1.2.3.4:443",
                                                date: date, bytes: 100)
            date = date.addingTimeInterval(step)
            return observation
        }
        #expect(detector.ingest(observations).isEmpty)
    }

    @Test func tooFewOccurrencesNotDetected() {
        var detector = BeaconDetector()
        let t0 = Date(timeIntervalSince1970: 1_752_800_000)
        let observations = (0..<3).map { i in
            BeaconObservation(process: "helper", destination: "1.2.3.4:443",
                              date: t0.addingTimeInterval(TimeInterval(i) * 60), bytes: 100)
        }
        #expect(detector.ingest(observations).isEmpty)
    }

    @Test func dedupesAfterEmit() {
        var detector = BeaconDetector()
        let t0 = Date(timeIntervalSince1970: 1_752_800_000)
        let observations = (0..<4).map { i in
            BeaconObservation(process: "helper", destination: "198.51.100.24:443",
                              date: t0.addingTimeInterval(TimeInterval(i) * 60), bytes: 100)
        }
        _ = detector.ingest(observations)
        #expect(detector.ingest(observations).isEmpty)
    }

    @Test func maxJitterConfigurationHonored() {
        let t0 = Date(timeIntervalSince1970: 1_752_800_000)
        let observations = [0, 60, 120, 186].map { i in
            BeaconObservation(process: "helper", destination: "198.51.100.24:443",
                              date: t0.addingTimeInterval(TimeInterval(i)), bytes: 100)
        }
        var strict = BeaconDetector(maxJitter: 0.01)   // jitter ~0.07 exceeds
        #expect(strict.ingest(observations).isEmpty)
        var defaultDetector = BeaconDetector()         // 0.07 < 0.35: default still emits
        #expect(defaultDetector.ingest(observations).count == 1)
    }
}
