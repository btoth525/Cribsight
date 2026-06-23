# Cribsight 👁️

A native **SwiftUI** split-screen baby monitor for iPad/iPhone. Two live camera
panes side-by-side over your **LAN only** (no cloud), with a real-time **Metal
fisheye dewarp**, a modern **Liquid Glass** UI, listen-in audio with **cry/sound
alerts**, and rock-solid auto-reconnect for an always-on nursery display.

- **Pane A — "Owlet"**: normal passthrough view.
- **Pane B — "Reolink fisheye"** (ceiling-mounted): live dewarped panorama with
  interactive pan / tilt / zoom and snap-to-crib presets.

Video comes from your existing **Frigate → go2rtc** setup over **WebRTC/WHEP**
(sub-second latency).

---

## Requirements

- **Xcode 26** (for the Liquid Glass SDK) on macOS.
- An iPad/iPhone running **iOS 18+** (Liquid Glass renders natively on iOS 26;
  on iOS 18–25 it gracefully falls back to a translucent material).
- A **paid Apple Developer account** to ship to TestFlight (a free personal team
  works for installing directly on your own device).
- **go2rtc** (standalone or via Frigate) reachable on your LAN, with both cameras
  exposed as streams.

---

## 1. Prepare go2rtc (one-time, on the server)

WebRTC needs a reachable ICE candidate on your LAN. In your go2rtc config add
your server's LAN IP with the WebRTC port (default **8555**):

```yaml
webrtc:
  candidates:
    - 192.168.1.50:8555   # <-- your go2rtc server's LAN IP
```

Make sure each camera has a stream name, e.g.:

```yaml
streams:
  owlet: ...
  reolink: ...
```

The go2rtc API is on port **1984** by default. Cribsight talks to
`http://<server>:1984/api/whep?src=<stream>`.

## 2. Open & sign in Xcode

```bash
open Cribsight.xcodeproj
```

(If anything looks off, you can regenerate the project with
`brew install xcodegen && xcodegen generate`.)

Then:

1. Let Xcode resolve the Swift Package (`stasel/WebRTC`). If it doesn't start
   automatically: **File ▸ Packages ▸ Resolve Package Versions**.
2. Select the **Cribsight** target ▸ **Signing & Capabilities**:
   - Set your **Team**.
   - Change the **Bundle Identifier** to something unique under your team
     (e.g. `com.yourname.cribsight`).
3. Pick your iPad as the run destination and **⌘R**.

## 3. First run

On first launch the onboarding screen asks for:

- **Server IP / host** and **port** (1984)
- **Camera A** display name + go2rtc **stream name** (e.g. `owlet`)
- **Camera B** display name + go2rtc **stream name** (e.g. `reolink`)

Tap **Start Monitoring**. Both panes should go **Live** in well under a second.
You can change any of this later from the **gear ▸ Settings** sheet.

---

## Features

- **Dual live panes**, adaptive split (side-by-side in landscape, stacked in
  portrait). Tap the expand button to **fullscreen** a camera; **swap** panes.
- **Interactive fisheye**: drag to pan/tilt, pinch to zoom, reset button, and a
  glass **preset picker** (Panorama / Crib A / Crib B / Wide).
- **Listen-in audio** per pane with a mute toggle and an always-on **VU meter**.
- **Cry / sound alerts**: a red flash, haptic, and toast when sustained noise
  crosses a per-camera sensitivity threshold.
- **Liquid Glass** controls, dark-first nursery theme, and a **Night Mode** that
  dims + warms the screen (manual or scheduled).
- **Snapshot** to Photos. **Kiosk lock** (hides controls; long-press to unlock).
- **Never disconnects**: per-pane exponential-backoff reconnect plus a frame
  **watchdog** that recovers silent stalls, keep-awake, and clean
  background/foreground handling.

### Tuning the fisheye

Open **Settings ▸ Fisheye Calibration** and adjust:

- **Center X/Y** and **Radius** so the circular image fills the dewarp.
- **Lens FOV°** to match your lens (Reolink fisheye ≈ 180–200°).
- **Pano top/bottom°** to frame the cribs in panorama mode.
- **Flip** if the image is mirrored.

Changes apply when you close Settings. (If go2rtc only gives you the raw circular
fisheye — which is normal — this is where you dial in the un-warp.)

---

## Ship to TestFlight

1. Set the run destination to **Any iOS Device (arm64)**.
2. **Product ▸ Archive**.
3. In the Organizer: **Distribute App ▸ App Store Connect ▸ Upload**.
4. In App Store Connect, add the build to **TestFlight** and install it on the
   nursery iPad via the TestFlight app.

`Info.plist` already sets `ITSAppUsesNonExemptEncryption = NO`, so you won't be
prompted about export compliance.

### Kiosk mode

For a locked-down wall display, use iOS **Guided Access**
(Settings ▸ Accessibility ▸ Guided Access), then triple-click the side button in
the app. The in-app **lock** button also hides all controls for a clean,
full-bleed view.

---

## Architecture

```
go2rtc (LAN) --WHEP/WebRTC--> WebRTCClient (per pane)
   audio ─→ AVAudioSession(.playback) + getStats audioLevel → VU + CryDetector
   video ─→ FrameSink (CVPixelBuffer) ─→ DewarpRenderer (Metal) ─→ MTKView
                                              ↑ pan/tilt/zoom uniforms ← gestures
```

| Area | Files |
|---|---|
| App / shell | `App/CribsightApp.swift`, `App/RootView.swift` |
| Monitor UI | `Monitor/MonitorView.swift`, `CameraPaneView.swift`, `ControlBar.swift`, `PresetPicker.swift`, `AlertOverlay.swift` |
| View models | `Monitor/MonitorViewModel.swift`, `PaneViewModel.swift` |
| WebRTC | `WebRTC/WebRTCClient.swift`, `WHEPSignaling.swift`, `ReconnectController.swift`, `StatsMonitor.swift`, `RTCFactory.swift` |
| Rendering | `Rendering/Shaders.metal`, `DewarpRenderer.swift`, `FrameSink.swift`, `MetalDewarpView.swift`, `DewarpUniforms.swift` |
| Audio / capture | `Audio/AudioController.swift`, `CryDetector.swift`, `Capture/SnapshotService.swift` |
| Settings | `Settings/AppConfig.swift`, `CameraConfig.swift`, `SettingsView.swift`, `OnboardingView.swift` |
| Design | `Design/Theme.swift`, `GlassSurface.swift`, `GlassControls.swift`, `NightModeOverlay.swift`, `Haptics.swift` |

Dependency: [`stasel/WebRTC`](https://github.com/stasel/WebRTC) via Swift Package
Manager (declared in the project and in `project.yml`).

---

## Troubleshooting

- **Panes stay "Connecting…"** — almost always the go2rtc `webrtc.candidates`
  step above. Confirm the iPad and server are on the same subnet and the IP/port
  are right.
- **No video but "Live"** — check the stream name matches go2rtc exactly.
- **HTTP blocked** — the app allows local-network cleartext via
  `NSAllowsLocalNetworking`; this only works for LAN addresses (as intended).
- **Package won't resolve** — File ▸ Packages ▸ Reset Package Caches, then
  Resolve.
- **Fisheye looks wrong** — tune Center/Radius/Lens FOV in Settings.

> Built in a headless CI environment, so the project ships as source +
> a ready-to-open `.xcodeproj`. The final compile, signing, and TestFlight upload
> happen on your Mac. The Liquid Glass calls are guarded by availability with a
> material fallback, so the project builds on the full iOS 18+ range.
