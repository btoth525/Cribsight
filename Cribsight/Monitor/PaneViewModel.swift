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
        // Non-fisheye panes use identity (1×, centered) — their pan/tilt/zoom are
        // digital-PTZ view offsets, not a fisheye aim.
        self.orientation = initialView?.orientation
            ?? (cam.isFisheye ? cam.dewarp.defaultOrientation : .identity)
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

    /// `dx`/`dy` are raw drag deltas normalized to the pane size (fractions).
    func applyDrag(dx: Float, dy: Float) {
        if camera.isFisheye {
            // Drag left/right pans level around the room (azimuth), up/down tilts
            // between straight-down and the walls. Per-camera invert flags flip either
            // axis for odd mounts. tilt is an elevation angle (0…~89° off nadir).
            let panDir: Float = camera.dewarp.invertPan ? 1 : -1
            let tiltDir: Float = camera.dewarp.invertTilt ? -1 : 1
            orientation.pan += panDir * dx * 2.6
            orientation.tilt = min(max(orientation.tilt + tiltDir * dy * 2.0, 0.02), 1.56)
        } else {
            // Digital pan while zoomed in: the content follows the finger, so the
            // view window moves opposite the drag, scaled by the zoom.
            let z = max(orientation.zoom, 1)
            guard z > 1.001 else { return }
            orientation.pan -= dx / z
            orientation.tilt -= dy / z
            clampDigitalOffsets()
        }
        updateUniforms()
    }

    func applyZoom(_ scale: Float) {
        if camera.isFisheye {
            orientation.zoom = min(max(orientation.zoom * scale, 0.4), 4.0)
        } else {
            orientation.zoom = min(max(orientation.zoom * scale, 1.0), 5.0)
            clampDigitalOffsets()
        }
        updateUniforms()
    }

    /// Keep the digital-PTZ window inside the frame (offsets shrink as zoom does).
    private func clampDigitalOffsets() {
        let limit = (1 - 1 / max(orientation.zoom, 1)) / 2
        orientation.pan = min(max(orientation.pan, -limit), limit)
        orientation.tilt = min(max(orientation.tilt, -limit), limit)
    }

    func apply(preset: ViewPreset) {
        mode = preset.mode
        orientation = preset.orientation
        updateUniforms()
        persistAim()
        Haptics.selection()
    }

    func resetView() {
        orientation = camera.isFisheye ? camera.dewarp.defaultOrientation : .identity
        mode = camera.dewarp.mode
        updateUniforms()
        persistAim()
        Haptics.tap()
    }

    /// Called when a PTZ gesture ends, to save the new framing for this slot.
    func endInteraction() {
        persistAim()
    }

    func snapshot(size: CGSize) -> UIImage? {
        renderer.snapshot(size: size)
    }

    /// Re-push uniforms after the camera's settings changed (fisheye calibration,
    /// flips, FOV). Keeps the user's current aim; only the lens params refresh.
    func refreshCameraParams() {
        updateUniforms()
    }

    // MARK: Internal

    private func persistAim() {
        onAimChanged?(id, SlotView(mode: mode, orientation: orientation))
    }

    private func updateUniforms() {
        renderer.uniforms = DewarpUniformsData.make(isFisheye: camera.isFisheye,
                                                    params: camera.dewarp,
                                                    orientation: orientation,
                                                    mode: mode)
    }
}
