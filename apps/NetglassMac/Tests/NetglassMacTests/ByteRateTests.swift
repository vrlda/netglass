import Testing
@testable import NetglassMac

@Suite struct ByteRateTests {
    @Test func bytes() {
        #expect(ByteRate.string(0) == "0B")
        #expect(ByteRate.string(42) == "42B")
        #expect(ByteRate.string(999) == "999B")
    }

    @Test func kilobytes() {
        #expect(ByteRate.string(1_000) == "1.0K")
        #expect(ByteRate.string(5_000) == "5.0K")
        #expect(ByteRate.string(88_000) == "88.0K")
        #expect(ByteRate.string(120_000) == "120K")
        #expect(ByteRate.string(999_499) == "999K")
        #expect(ByteRate.string(999_949) == "1.0M")
    }

    @Test func megabytes() {
        #expect(ByteRate.string(1_234_567) == "1.2M")
        #expect(ByteRate.string(9_999_999) == "10.0M")
        #expect(ByteRate.string(45_000_000) == "45M")
        #expect(ByteRate.string(999_499_000) == "999M")
        #expect(ByteRate.string(999_949_000) == "1.0G")
    }

    @Test func gigabytes() {
        #expect(ByteRate.string(1_500_000_000) == "1.5G")
        #expect(ByteRate.string(9_900_000_000) == "9.9G")
        #expect(ByteRate.string(15_000_000_000) == "15G")
    }

    @Test func logScaleBars() {
        #expect(StatusMeter.heightFactor(0) == 0)
        #expect(StatusMeter.heightFactor(-5) == 0)
        #expect(StatusMeter.heightFactor(100_000_000) == 1)
        #expect(StatusMeter.heightFactor(1_000_000_000) == 1)
    }

    @Test func relativeScaleAnchors() {
        // any nonzero traffic shows at least one line
        #expect(StatusMeter.heightFactor(1) > 0)
        #expect(StatusMeter.heightFactor(1) >= 0.03)
        #expect(StatusMeter.heightFactor(500) >= 0.03)
        // ~500K → 2-3 lines (factor 0.33-0.58)
        let f500k = StatusMeter.heightFactor(500_000)
        #expect(f500k > 0.33 && f500k < 0.58)
        // ~1M → 4 lines (factor ~0.63)
        let f1m = StatusMeter.heightFactor(1_000_000)
        #expect(f1m > 0.55 && f1m < 0.72)
        // ~5M → 5 lines (factor ~0.87)
        let f5m = StatusMeter.heightFactor(5_000_000)
        #expect(f5m > 0.8 && f5m < 0.95)
        // 10M+ → full
        #expect(StatusMeter.heightFactor(10_000_000) == 1)
        #expect(StatusMeter.heightFactor(50_000_000) == 1)
        // monotonic
        #expect(StatusMeter.heightFactor(300_000) < StatusMeter.heightFactor(2_000_000))
        #expect(StatusMeter.heightFactor(2_000_000) < StatusMeter.heightFactor(7_000_000))
    }
}
