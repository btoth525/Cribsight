import SwiftUI
import UIKit

/// A single camera pane: the Metal video, gestures (fisheye PTZ), label,
/// connection/health badge, VU meter, cry flash, and quick controls.
struct CameraPaneView: View {
    @ObservedObject var pane: PaneViewModel
    var isFullscreen: Bool
    var controlsVisible: Bool
    /// When false (e.g. while arranging the layout), the pane's own PTZ gestures
    /// and quick controls are suppressed so drag-to-move/resize wins.
    var interactive: Bool = true
    /// Live vitals source for the Baby Mode HUD (the overlay observes it directly so
    /// polling refreshes only the pill, not the video). Nil hides the HUD.
    var vitalsService: VitalsService? = nil
    var onToggleFullscreen: () -> Void
    var onToast: (String) -> Void
    var onShowVitals: (() -> Void)? = nil
    /// Open the talk + lullaby controls (Owlet-bridge cameras only).
    var onBabyControls: (() -> Void)? = nil

    @State private var lastDrag: CGSize = .zero
    @State private var lastZoom: CGFloat = 1

    private var corner: CGFloat { isFullscreen ? 0 : Theme.paneCornerRadius }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                if interactive {
                    MetalDewarpView(renderer: pane.renderer)
                        .gesture(dragGesture(geo.size))
                        .simultaneousGesture(magnifyGesture())
                        .onTapGesture(count: 2) { onToggleFullscreen() }
                } else {
                    MetalDewarpView(renderer: pane.renderer)
                        .allowsHitTesting(false)
                }

                if !pane.connectionState.isLive {
                    offlineVeil
                }

                if pane.cryActive {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Theme.danger, lineWidth: 4)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                overlays(geo: geo)
                    .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: isFullscreen ? 0 : 1)
            )
        }
    }

    // MARK: Overlays

    @ViewBuilder
    private func overlays(geo: GeometryProxy) -> some View {
        VStack {
            // Top: label (left), and status + per-pane controls (right). Keeping the
            // controls up here means they never collide with the global control bar
            // that floats over the bottom-center on a side-by-side layout.
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    labelBadge
                    if pane.camera.babyMode, let vitalsService {
                        VitalsOverlay(service: vitalsService, camera: pane.camera) { onShowVitals?() }
                            .transition(.opacity)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    statusBadge
                    if controlsVisible {
                        quickControls(geo: geo)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            Spacer()
            HStack {
                VUMeter(level: min(1, pane.stats.audioLevel * 6))
                    .opacity(pane.isMuted ? 0.4 : 1)
                Spacer()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: controlsVisible)
    }

    private var labelBadge: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(pane.camera.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassPill()
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Text(pane.connectionState.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
            if pane.connectionState.isLive && pane.stats.fps > 0 {
                Text("· \(Int(pane.stats.fps)) fps")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassPill()
    }

    private func quickControls(geo: GeometryProxy) -> some View {
        // On a small tile show only the essentials so the row never overflows.
        let tiny = geo.size.width < 160
        let compact = geo.size.width < 240
        return HStack(spacing: 8) {
            if !tiny {
                GlassIconButton(systemName: pane.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                active: !pane.isMuted, size: 40,
                                label: pane.isMuted ? "Unmute" : "Mute") {
                    pane.toggleMute()
                }
            }
            if !tiny && pane.camera.isOwletBridge && onBabyControls != nil {
                GlassIconButton(systemName: "music.mic", size: 40, label: "Talk and lullabies") {
                    onBabyControls?()
                }
            }
            if !compact {
                GlassIconButton(systemName: "arrow.counterclockwise", size: 40, label: "Reset view") {
                    pane.resetView()
                }
            }
            if !compact {
                GlassIconButton(systemName: "camera.fill", size: 40, label: "Save snapshot") {
                    takeSnapshot(size: geo.size)
                }
            }
            GlassIconButton(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                            size: 40,
                            label: isFullscreen ? "Exit fullscreen" : "Fullscreen") {
                onToggleFullscreen()
            }
        }
    }

    private var offlineVeil: some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 12) {
                if case .failed(let message) = pane.connectionState {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Theme.warn)
                    Text(pane.connectionState.label)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                } else {
                    ProgressView()
                        .tint(Theme.accent)
                    Text(pane.connectionState.label)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var statusColor: Color {
        switch pane.connectionState {
        case .live: return Theme.live
        case .connecting, .reconnecting: return Theme.warn
        case .failed: return Theme.danger
        case .idle: return Theme.textTertiary
        }
    }

    // MARK: Actions

    private func takeSnapshot(size: CGSize) {
        let scale = UIScreen.main.scale
        let target = CGSize(width: max(640, size.width * scale), height: max(360, size.height * scale))
        guard let image = pane.snapshot(size: target) else {
            onToast("Snapshot unavailable")
            return
        }
        SnapshotService.save(image) { result in
            switch result {
            case .saved: Haptics.success(); onToast("Saved to Photos")
            case .denied: onToast("Allow Photos access to save")
            case .failed: onToast("Couldn't save snapshot")
            }
        }
    }

    // MARK: Gestures

    private func dragGesture(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let dx = Float((value.translation.width - lastDrag.width) / max(1, size.width))
                let dy = Float((value.translation.height - lastDrag.height) / max(1, size.height))
                lastDrag = value.translation
                pane.applyDrag(dx: dx, dy: dy)
            }
            .onEnded { _ in lastDrag = .zero; pane.endInteraction() }
    }

    private func magnifyGesture() -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let delta = value.magnification / max(0.01, lastZoom)
                lastZoom = value.magnification
                pane.applyZoom(Float(delta))
            }
            .onEnded { _ in lastZoom = 1; pane.endInteraction() }
    }
}
