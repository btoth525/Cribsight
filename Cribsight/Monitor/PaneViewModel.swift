import Foundation
import SwiftUI
import UIKit
import Combine

/// Drives a single layout slot: its own Metal renderer + fisheye framing, sharing
/// the underlying `CameraSource` (connection/audio/stats) with any other panes of
/// the same camera. So one ceiling fisheye can power several panes, each aimed at
/// a different crib.
final class PaneViewModel: ObservableObject, Identifiable {
    /// The layout slot id (a camera may back several slots).
    let id: UUID

    let source: CameraSource
    /// Owned here so it survives SwiftUI view rebuilds; reads the shared sink.
    let renderer: DewarpRenderer

    @Published var orientation: ViewOrientation
    @Published var mode: FisheyeProjectionMode

    /// Persist the per-slot framing (slot id, view) after the user reaims.
    var onAimChanged: ((UUID, SlotView) -> Void)?

    private var cancellable: AnyCancellable?

    // Forwarded source state (so the view only needs to observe the pane).
    var camera: CameraSettings { source.camera }
    var connectionState: PaneConnectionState { source.connectionState }
    var stats: PaneStats { source.stats }
    var isMuted: Bool { source.isMuted }
    var cryActive: Bool { source.cryActive }

    init(slotID: UUID, source: CameraSource, initialView: SlotView?) {
        self.id = slotID
        self.source = source
        self.renderer = DewarpRenderer(sink: source.sink)
        let cam = source.camera
        self.orientation = initialView?.orientation ?? cam.dewarp.defaultOrientation
        self.mode = initialView?.mode ?? cam.dewarp.mode
        updateUniforms()
        // Re-publish source changes (connection/stats/mute/cry) as our own.
        cancellable = source.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    // MARK: Audio

    func toggleMute() { source.toggleMute() }

    // MARK: Gestures / framing

    func applyDrag(dx: Float, dy: Float) {
        guard camera.isFisheye else { return }
        // Default planet feel: drag left/right spins the planet (pan), drag
        // up/down tilts into the room. Pan was inverted before, so its default is
        // flipped here. Per-camera invert flags flip either axis for odd mounts.
        let panDir: Float = camera.dewarp.invertPan ? 1 : -1
        let tiltDir: Float = camera.dewarp.invertTilt ? -1 : 1
        orientation.pan += panDir * dx
        orientation.tilt = min(max(orientation.tilt + tiltDir * dy, -1.45), 1.45)
        updateUniforms()
    }

    func applyZoom(_ scale: Float) {
        guard camera.isFisheye else { return }
        orientation.zoom = min(max(orientation.zoom * scale, 0.4), 4.0)
        updateUniforms()
    }

    func apply(preset: ViewPreset) {
        mode = preset.mode
        orientation = preset.orientation
        updateUniforms()
        persistAim()
        Haptics.selection()
    }

    func resetView() {
        orientation = camera.dewarp.defaultOrientation
        mode = camera.dewarp.mode
        updateUniforms()
        persistAim()
        Haptics.tap()
    }

    /// Called when a PTZ gesture ends, to save the new framing for this slot.
    func endInteraction() {
        guard camera.isFisheye else { return }
        persistAim()
    }

    func snapshot(size: CGSize) -> UIImage? {
        renderer.snapshot(size: size)
    }

    // MARK: Internal

    private func persistAim() {
        guard camera.isFisheye else { return }
        onAimChanged?(id, SlotView(mode: mode, orientation: orientation))
    }

    private func updateUniforms() {
        renderer.uniforms = DewarpUniformsData.make(isFisheye: camera.isFisheye,
                                                    params: camera.dewarp,
                                                    orientation: orientation,
                                                    mode: mode)
    }
}
