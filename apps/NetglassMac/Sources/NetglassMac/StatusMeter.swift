import AppKit

/// AppKit-rendered menu-bar indicator: two thin horizontal bars stacked
/// vertically (down = blue, up = purple), filled with line segments
/// (Little-Snitch style), each with its speed number on the same row.
/// Drawn directly into an NSImage so the menu bar shows exactly this.
enum StatusMeter {
    static let marginX: CGFloat = 4
    static let barWidth: CGFloat = 26
    /// 7pt bars keep the 15pt stack comfortably inside an 18pt status-item
    /// image (thickness 22 - 4), so the top row is never clipped.
    static let barHeight: CGFloat = 7
    static let barGap: CGFloat = 1
    static let arrowSlotWidth: CGFloat = 9
    static let textSlotWidth: CGFloat = 26
    static let segmentWidth: CGFloat = 3
    static let segmentStep: CGFloat = 4.5

    static var font: NSFont {
        NSFont.systemFont(ofSize: 8, weight: .medium)
    }
    private static let glyphWidth: CGFloat = 4.8

    /// Fixed-width labels avoid asking CoreText to measure a custom image while
    /// AppKit is taking a status-item snapshot.
    static func textWidth(_ text: String) -> CGFloat {
        CGFloat(text.utf16.count) * glyphWidth
    }

    static func image(down: Double, up: Double, height: CGFloat) -> NSImage {
        let width = marginX * 2 + barWidth + arrowSlotWidth + textSlotWidth
        return NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            // Bars drive the layout: two chunky bars nearly touching, with the
            // speed text vertically centered on each bar's row.
            let stack = barHeight * 2 + barGap
            let padding = max(1, (height - stack) / 2)
            let midY1 = padding + barHeight / 2
            let midY2 = midY1 + barHeight + barGap
            drawRow(x: marginX, midY: midY1, roundTop: false,
                    factor: heightFactor(down), color: .systemBlue, pointsDown: true,
                    text: ByteRate.string(down))
            drawRow(x: marginX, midY: midY2, roundTop: true,
                    factor: heightFactor(up), color: .systemPurple, pointsDown: false,
                    text: ByteRate.string(up))
            return true
        }
    }

    private static func drawRow(x: CGFloat, midY: CGFloat, roundTop: Bool,
                                factor: CGFloat, color: NSColor,
                                pointsDown: Bool, text: String) {
        let barRect = NSRect(x: x, y: midY - barHeight / 2, width: barWidth, height: barHeight)
        // ghost slots: one background in the exact shape of a line at every
        // line position, so a vanished line leaves its spot behind
        let fillWidth = 3 + factor * (barWidth - 3)
        var slotX = x + 0.5
        while slotX - x <= barWidth - segmentWidth {
            let slot = NSRect(x: slotX, y: barRect.minY, width: segmentWidth, height: barHeight)
            NSColor.labelColor.withAlphaComponent(0.3).setFill()
            segmentPath(rect: slot, roundTop: roundTop).fill()
            slotX += segmentStep
        }
        // colored lines on top of their slots
        color.setFill()
        var segmentX = x + 0.5
        while segmentX - x <= fillWidth - segmentWidth {
            segmentPath(rect: NSRect(x: segmentX, y: barRect.minY,
                                     width: segmentWidth, height: barHeight),
                        roundTop: roundTop).fill()
            segmentX += segmentStep
        }
        // Draw arrow as a path; text measurement in NSImage reps can crash
        // during AppKit status-item snapshotting on some macOS releases.
        drawArrow(x: x + barWidth + 1, midY: midY, pointsDown: pointsDown, color: color)

        // Speed number, right-aligned in a fixed slot so the item never jitters.
        let number = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: NSColor.labelColor])
        // Baseline from font metrics minus a 2pt nudge: digit ink is
        // baseline-heavy, so centering by metrics alone sits the number
        // ~2pt above its bar. 8pt text keeps the ink inside an 18-20pt
        // image with the 7pt bar stack.
        let baseline = midY - (font.ascender + font.descender) / 2 - 2
        number.draw(at: NSPoint(x: x + barWidth + arrowSlotWidth + textSlotWidth - textWidth(text),
                                y: baseline))
    }

    private static func drawArrow(x: CGFloat, midY: CGFloat, pointsDown: Bool, color: NSColor) {
        let path = NSBezierPath()
        path.lineWidth = 1.2
        let tipY = midY + (pointsDown ? -3 : 3)
        let tailY = midY + (pointsDown ? 3 : -3)
        let headY = tipY + (pointsDown ? 2 : -2)
        path.move(to: NSPoint(x: x + 4.5, y: tailY))
        path.line(to: NSPoint(x: x + 4.5, y: tipY))
        path.move(to: NSPoint(x: x + 2.5, y: headY))
        path.line(to: NSPoint(x: x + 4.5, y: tipY))
        path.line(to: NSPoint(x: x + 6.5, y: headY))
        color.setStroke()
        path.stroke()
    }

    /// A line segment: rounded on one end (toward the bar's outer edge),
    /// squared on the other — top bar rounds up, bottom bar rounds down.
    private static func segmentPath(rect: NSRect, roundTop: Bool) -> NSBezierPath {
        let radius = min(1.5, rect.width / 2)
        let x = rect.minX, y = rect.minY
        let w = rect.width, h = rect.height
        let path = NSBezierPath()
        if roundTop {
            path.move(to: NSPoint(x: x, y: y))
            path.line(to: NSPoint(x: x + w, y: y))
            path.line(to: NSPoint(x: x + w, y: y + h - radius))
            path.appendArc(from: NSPoint(x: x + w, y: y + h),
                           to: NSPoint(x: x + w - radius, y: y + h), radius: radius)
            path.line(to: NSPoint(x: x + radius, y: y + h))
            path.appendArc(from: NSPoint(x: x, y: y + h),
                           to: NSPoint(x: x, y: y + h - radius), radius: radius)
            path.close()
        } else {
            path.move(to: NSPoint(x: x, y: y + h))
            path.line(to: NSPoint(x: x + w, y: y + h))
            path.line(to: NSPoint(x: x + w, y: y + radius))
            path.appendArc(from: NSPoint(x: x + w, y: y),
                           to: NSPoint(x: x + w - radius, y: y), radius: radius)
            path.line(to: NSPoint(x: x + radius, y: y))
            path.appendArc(from: NSPoint(x: x, y: y),
                           to: NSPoint(x: x, y: y + radius), radius: radius)
            path.close()
        }
        return path
    }

    /// Relative log-style fill: a power law over the 0..10 MB/s range so low
    /// traffic still shows a few lines while the top is capped. Anchors:
    /// 0 → 0 lines, any nonzero → ≥1 line, ~500K → 3, ~1M → 4, ~3-5M → 5,
    /// 10M+ → 6.
    static func heightFactor(_ bytesPerSecond: Double) -> CGFloat {
        guard bytesPerSecond > 0 else { return 0 }
        let full = 10_000_000.0
        let power = pow(min(bytesPerSecond, full) / full, 0.2)
        return CGFloat(max(0.03, power))   // 0.03 ≈ one line's worth of fill
    }
}

/// Compact byte-rate formatting for the menu bar: 0B, 900B, 4.5K, 120K,
/// 3.2M, 45M, 1.1G. One decimal below 100K / 10M / 10G, whole units above.
public enum ByteRate {
    public static func string(_ bytesPerSecond: Double) -> String {
        let locale = Locale(identifier: "en_US_POSIX")
        guard bytesPerSecond >= 1_000 else { return "\(Int(bytesPerSecond))B" }
        if bytesPerSecond < 1_000_000 {
            let k = bytesPerSecond / 1_000
            guard k < 999.5 else { return string(1_000_000) }
            return k < 100
                ? String(format: "%.1fK", locale: locale, k)
                : "\(Int(k.rounded()))K"
        }
        if bytesPerSecond < 1_000_000_000 {
            let m = bytesPerSecond / 1_000_000
            guard m < 999.5 else { return string(1_000_000_000) }
            return m < 10
                ? String(format: "%.1fM", locale: locale, m)
                : "\(Int(m.rounded()))M"
        }
        let g = bytesPerSecond / 1_000_000_000
        return g < 10
            ? String(format: "%.1fG", locale: locale, g)
            : "\(Int(g.rounded()))G"
    }
}
