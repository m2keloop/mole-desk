import AppKit

// One native drawing surface for the six groups, independent of the number of file rows.
final class Distribution: NSView {
    var groups: [(key: String, bytes: Double)] = [] { didSet { updateTips(); needsDisplay = true } }
    var choose: ((String) -> Void)?
    private let colors: [NSColor] = [
        NSColor(calibratedRed: 0.39, green: 0.79, blue: 0.72, alpha: 1),
        NSColor(calibratedRed: 0.47, green: 0.68, blue: 0.84, alpha: 1),
        NSColor(calibratedRed: 0.56, green: 0.61, blue: 0.78, alpha: 1),
        NSColor(calibratedRed: 0.84, green: 0.69, blue: 0.51, alpha: 1),
        NSColor(calibratedRed: 0.76, green: 0.55, blue: 0.56, alpha: 1),
        NSColor(calibratedRed: 0.68, green: 0.57, blue: 0.75, alpha: 1)
    ]

    private var segments: [(key: String, rect: NSRect)] {
        let sum = groups.reduce(0) { $0 + $1.bytes }
        guard sum > 0 else { return [] }
        var x: CGFloat = 0
        return groups.map { group in
            let width = bounds.width * group.bytes / sum
            defer { x += width }
            return (group.key, NSRect(x: x,y: 0,width: max(width-1,0),height: bounds.height))
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).addClip()
        NSColor.quaternaryLabelColor.setFill(); bounds.fill()
        for (i, segment) in segments.enumerated() { colors[i % colors.count].setFill(); segment.rect.fill() }
    }
    private func updateTips() {
        toolTip = groups.map { (categoryNames[$0.key] ?? $0.key) + " · 约 " + displaySize($0.bytes) }.joined(separator: "\n")
    }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let s = segments.first(where: { $0.rect.contains(p) }) { choose?(s.key) }
    }
}
func displaySize(_ bytes: Double) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .decimal)
}
