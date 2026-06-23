import Foundation
import CoreGraphics

/// A per-slot fisheye framing override. The same fisheye camera can sit in
/// several slots, each aimed differently — one ceiling cam becomes many panes.
struct SlotView: Codable, Equatable {
    var mode: FisheyeProjectionMode
    var orientation: ViewOrientation
}

/// One camera placed in a layout, positioned by a normalized rect (0…1 on both
/// axes) so layouts are resolution-independent and drag-to-resize is just math.
struct LayoutSlot: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var cameraID: UUID
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    /// Optional fisheye framing override for this slot.
    var view: SlotView? = nil

    var frame: CGRect {
        get { CGRect(x: x, y: y, width: width, height: height) }
        set {
            x = newValue.origin.x; y = newValue.origin.y
            width = newValue.size.width; height = newValue.size.height
        }
    }

    /// Clamp to the canvas and enforce a minimum size.
    mutating func normalize(minSize: Double = 0.12) {
        width = min(max(width, minSize), 1)
        height = min(max(height, minSize), 1)
        x = min(max(x, 0), 1 - width)
        y = min(max(y, 0), 1 - height)
    }
}

/// A saved arrangement of camera panes.
struct PaneLayout: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var slots: [LayoutSlot]

    // MARK: Generators

    /// Balanced grid (cols = ceil(sqrt(n))). The sensible default for any count.
    static func auto(cameraIDs: [UUID], name: String = "Grid") -> PaneLayout {
        let n = max(cameraIDs.count, 1)
        let cols = Int(ceil(Double(n).squareRoot()))
        let rows = Int(ceil(Double(n) / Double(cols)))
        let cw = 1.0 / Double(cols)
        let rh = 1.0 / Double(rows)
        var slots: [LayoutSlot] = []
        for (i, cam) in cameraIDs.enumerated() {
            let r = i / cols, c = i % cols
            slots.append(LayoutSlot(cameraID: cam,
                                    x: Double(c) * cw, y: Double(r) * rh,
                                    width: cw, height: rh))
        }
        return PaneLayout(name: name, slots: slots)
    }

    /// Side-by-side columns.
    static func columns(cameraIDs: [UUID], name: String = "Side by side") -> PaneLayout {
        let n = max(cameraIDs.count, 1)
        let cw = 1.0 / Double(n)
        let slots = cameraIDs.enumerated().map { i, cam in
            LayoutSlot(cameraID: cam, x: Double(i) * cw, y: 0, width: cw, height: 1)
        }
        return PaneLayout(name: name, slots: slots)
    }

    /// Stacked rows (top/bottom).
    static func rows(cameraIDs: [UUID], name: String = "Stacked") -> PaneLayout {
        let n = max(cameraIDs.count, 1)
        let rh = 1.0 / Double(n)
        let slots = cameraIDs.enumerated().map { i, cam in
            LayoutSlot(cameraID: cam, x: 0, y: Double(i) * rh, width: 1, height: rh)
        }
        return PaneLayout(name: name, slots: slots)
    }

    /// One big pane on the left (2/3), the rest stacked down the right column.
    static func spotlight(cameraIDs: [UUID], name: String = "One bigger") -> PaneLayout {
        guard cameraIDs.count > 1 else { return columns(cameraIDs: cameraIDs, name: name) }
        let big = cameraIDs[0]
        let rest = Array(cameraIDs.dropFirst())
        var slots = [LayoutSlot(cameraID: big, x: 0, y: 0, width: 2.0/3.0, height: 1)]
        let rh = 1.0 / Double(rest.count)
        for (i, cam) in rest.enumerated() {
            slots.append(LayoutSlot(cameraID: cam, x: 2.0/3.0, y: Double(i) * rh,
                                    width: 1.0/3.0, height: rh))
        }
        return PaneLayout(name: name, slots: slots)
    }

    /// Picture-in-picture: first fills, second floats bottom-right.
    static func pip(cameraIDs: [UUID], name: String = "Picture-in-picture") -> PaneLayout {
        guard cameraIDs.count > 1 else { return columns(cameraIDs: cameraIDs, name: name) }
        return PaneLayout(name: name, slots: [
            LayoutSlot(cameraID: cameraIDs[0], x: 0, y: 0, width: 1, height: 1),
            LayoutSlot(cameraID: cameraIDs[1], x: 0.66, y: 0.66, width: 0.32, height: 0.32)
        ])
    }
}
