import AppKit
import SwiftUI

/// AppKit hex viewer: offset / hex / ASCII columns with drag selection and
/// synchronized field highlighting. Precise byte selection, no SwiftUI layer.
final class HexViewer: NSView {
    var bytes: [UInt8] = [] {
        didSet { needsDisplay = true }
    }
    /// Byte range to highlight (protocol field sync); nil clears.
    var highlightRange: Range<Int>? {
        didSet { needsDisplay = true }
    }
    /// Callback with the currently selected byte range.
    var onSelection: ((Range<Int>?) -> Void)?

    private(set) var selection: Range<Int>?
    private var dragAnchor: Int?

    private let offsetWidth: CGFloat = 52
    private let hexWidth: CGFloat = 16
    private let asciiWidth: CGFloat = 10
    private let rowHeight: CGFloat = 15
    private let topPadding: CGFloat = 4
    private var bytesPerRow = 16

    private let monoFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private let monoBold = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let usable = bounds.width - offsetWidth
        bytesPerRow = max(8, Int(usable / (hexWidth + asciiWidth)) / 16 * 16)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        guard !bytes.isEmpty else { return }
        let rows = (bytes.count + bytesPerRow - 1) / bytesPerRow

        for row in 0..<rows {
            let y = topPadding + CGFloat(row) * rowHeight
            let offset = row * bytesPerRow
            let count = min(bytesPerRow, bytes.count - offset)

            // offset column
            NSString(format: "%08x", offset).draw(
                at: NSPoint(x: 6, y: y), withAttributes: [
                    .font: monoFont, .foregroundColor: NSColor.secondaryLabelColor])

            // hex + ascii
            for i in 0..<count {
                let byteIndex = offset + i
                let hexX = offsetWidth + CGFloat(i) * hexWidth
                let asciiX = offsetWidth + CGFloat(bytesPerRow) * hexWidth + 6 + CGFloat(i) * asciiWidth
                let isHighlighted = highlightRange?.contains(byteIndex) == true
                let isSelected = selection?.contains(byteIndex) == true
                let color: NSColor = isHighlighted
                    ? .systemBlue : isSelected ? .selectedTextColor : .labelColor

                if isSelected {
                    NSColor.selectedContentBackgroundColor.setFill()
                    NSRect(x: hexX - 2, y: y, width: hexWidth - 4, height: rowHeight - 1).fill()
                }
                NSString(format: "%02x", bytes[byteIndex]).draw(
                    at: NSPoint(x: hexX, y: y), withAttributes: [
                        .font: isHighlighted ? monoBold : monoFont,
                        .foregroundColor: color])

                let ascii = bytes[byteIndex]
                let char = (32...126).contains(Int(ascii)) ? String(UnicodeScalar(ascii)) : "."
                (char as NSString).draw(at: NSPoint(x: asciiX, y: y), withAttributes: [
                    .font: monoFont,
                    .foregroundColor: isHighlighted ? NSColor.systemBlue : .labelColor])
            }

            // selection background for ascii column
            if selection != nil {
                for i in 0..<count {
                    let byteIndex = offset + i
                    if selection?.contains(byteIndex) == true {
                        let asciiX = offsetWidth + CGFloat(bytesPerRow) * hexWidth + 6 + CGFloat(i) * asciiWidth
                        NSColor.selectedContentBackgroundColor.setFill()
                        NSRect(x: asciiX - 2, y: y, width: asciiWidth - 3, height: rowHeight - 1).fill()
                        let ascii = bytes[byteIndex]
                        let char = (32...126).contains(Int(ascii)) ? String(UnicodeScalar(ascii)) : "."
                        (char as NSString).draw(at: NSPoint(x: asciiX, y: y), withAttributes: [
                            .font: monoFont, .foregroundColor: NSColor.selectedTextColor])
                    }
                }
            }
        }

        // separator
        NSColor.separatorColor.setFill()
        NSRect(x: offsetWidth + CGFloat(bytesPerRow) * hexWidth + 2, y: 0,
               width: 1, height: bounds.height).fill()
    }

    private func byteIndex(at point: NSPoint) -> Int? {
        guard point.y >= topPadding else { return nil }
        let row = Int((point.y - topPadding) / rowHeight)
        let col: Int
        if point.x < offsetWidth {
            col = 0
        } else if point.x < offsetWidth + CGFloat(bytesPerRow) * hexWidth {
            col = Int((point.x - offsetWidth) / hexWidth)
        } else {
            col = Int((point.x - (offsetWidth + CGFloat(bytesPerRow) * hexWidth + 6)) / asciiWidth)
        }
        guard row >= 0, col >= 0, col < bytesPerRow else { return nil }
        let index = row * bytesPerRow + col
        return index < bytes.count ? index : nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragAnchor = byteIndex(at: point)
        selection = dragAnchor.map { $0..<($0 + 1) }
        onSelection?(selection)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let anchor = dragAnchor, let current = byteIndex(at: point) else { return }
        selection = min(anchor, current)..<(max(anchor, current) + 1)
        onSelection?(selection)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragAnchor = nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let selection else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 123: // left
            if selection.lowerBound > 0 {
                let start = selection.lowerBound - 1
                self.selection = start..<start
                onSelection?(self.selection)
                needsDisplay = true
            }
        case 124: // right
            if selection.upperBound < bytes.count {
                let start = selection.upperBound
                self.selection = start..<(start + 1)
                onSelection?(self.selection)
                needsDisplay = true
            }
        case 8: // delete
            let data = Data(selection.map { bytes[$0] })
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(data, forType: NSPasteboard.PasteboardType("public.data"))
        default:
            super.keyDown(with: event)
        }
    }
}

/// NSViewRepresentable wrapper.
struct HexViewerView: NSViewRepresentable {
    let bytes: [UInt8]
    var highlight: Range<Int>?

    func makeNSView(context: Context) -> HexViewer {
        let view = HexViewer()
        view.bytes = bytes
        view.highlightRange = highlight
        return view
    }

    func updateNSView(_ view: HexViewer, context: Context) {
        view.bytes = bytes
        view.highlightRange = highlight
    }
}
