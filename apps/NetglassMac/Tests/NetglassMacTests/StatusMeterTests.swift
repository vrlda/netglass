import AppKit
import Testing
@testable import NetglassMac

@Suite struct StatusMeterTests {
    private func pixels(of image: NSImage) -> NSBitmapImageRep {
        NSBitmapImageRep(data: image.tiffRepresentation!)!
    }

    private func counts(_ rep: NSBitmapImageRep, in xRange: Range<Int>,
                        match: (NSColor) -> Bool) -> Int {
        var count = 0
        for y in 0..<rep.pixelsHigh {
            for x in xRange {
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                if match(c) { count += 1 }
            }
        }
        return count
    }

    /// Pixels matching a color once both are expressed in the bitmap's
    /// color space, so component comparisons survive color-space conversion.
    private func pixels(_ rep: NSBitmapImageRep, matching color: NSColor,
                        tolerance: CGFloat = 0.03) -> Int {
        guard let target = color.usingColorSpace(rep.colorSpace) else { return 0 }
        return counts(rep, in: 0..<rep.pixelsWide) {
            abs($0.redComponent - target.redComponent) <= tolerance
                && abs($0.greenComponent - target.greenComponent) <= tolerance
                && abs($0.blueComponent - target.blueComponent) <= tolerance
        }
    }

    @Test func rendersBlueDownBarPurpleUpBarWithText() {
        let image = StatusMeter.image(down: 50_000_000, up: 8_000_000, height: 22)
        #expect(image.size.width > 60)
        let rep = pixels(of: image)

        // blue pixels must exist (down bar segments + arrow)
        let blue = counts(rep, in: 0..<rep.pixelsWide) { $0.blueComponent > 0.55 && $0.redComponent < 0.45 }
        #expect(blue > 40)
        // purple pixels must exist (up bar segments + arrow)
        let purple = counts(rep, in: 0..<rep.pixelsWide) { $0.redComponent > 0.5 && $0.blueComponent > 0.6 && $0.greenComponent < 0.5 }
        #expect(purple > 10)
        // dark text pixels must exist (speed labels)
        let dark = counts(rep, in: 0..<rep.pixelsWide) {
            $0.redComponent * 0.299 + $0.greenComponent * 0.587 + $0.blueComponent * 0.114 < 0.4
        }
        #expect(dark > 100)
    }

    @Test func fillIsSegmentedNotSolid() {
        // A full bar must show gaps: the blue pixel run length is bounded by
        // segment width, far less than a solid 26pt fill would produce.
        let rep = pixels(of: StatusMeter.image(down: 100_000_000, up: 0, height: 22))
        var longestRun = 0
        for y in 0..<rep.pixelsHigh {
            var run = 0
            for x in 0..<rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                let isBlue = c.blueComponent > 0.55 && c.redComponent < 0.45
                run = isBlue ? run + 1 : 0
                longestRun = max(longestRun, run)
            }
        }
        // 1.5pt segment at 1x backing scale ≈ 2px + antialiasing; a solid
        // bar would run ~26px.
        #expect(longestRun <= 6)
    }

    @Test func barFillGrowsWithRate() {
        // Near-idle: fill is only the 3pt nub. High rate: nearly full bar.
        let low = pixels(of: StatusMeter.image(down: 0, up: 0, height: 20))
        let high = pixels(of: StatusMeter.image(down: 100_000_000, up: 0, height: 20))
        let blueLow = pixels(low, matching: .systemBlue)
        let blueHigh = pixels(high, matching: .systemBlue)
        #expect(blueHigh > blueLow * 3)
    }

    @Test func statusMeterTextWidthIsDeterministic() {
        #expect(StatusMeter.textWidth("AB") == StatusMeter.textWidth("CD"))
        #expect(StatusMeter.textWidth("ABCD") == StatusMeter.textWidth("AB") * 2)
    }

    @Test func textRightAlignedInFixedSlots() {
        // Values with different string lengths must land at the same right
        // edge so the item width never jitters.
        let a = StatusMeter.image(down: 999_499, up: 0, height: 20)   // "↓999K"
        let b = StatusMeter.image(down: 1_234_567, up: 0, height: 20) // "↓1.2M"
        let repA = pixels(of: a)
        let repB = pixels(of: b)
        func rightmostTextPixel(_ rep: NSBitmapImageRep) -> Int? {
            var rightmost: Int?
            for x in 0..<rep.pixelsWide {
                for y in 0..<rep.pixelsHigh {
                    guard let c = rep.colorAt(x: x, y: y) else { continue }
                    let brightness = c.redComponent * 0.299 + c.greenComponent * 0.587 + c.blueComponent * 0.114
                    if brightness < 0.4 {
                        rightmost = x
                        break
                    }
                }
            }
            return rightmost
        }
        let rightmostA = try! #require(rightmostTextPixel(repA))
        let rightmostB = try! #require(rightmostTextPixel(repB))
        #expect(abs(rightmostA - rightmostB) <= 1)
    }
}
