# Cribsight 👁️

A native **SwiftUI** multi-camera baby monitor for iPad/iPhone. As many live
camera panes as you want, arranged in **custom drag-to-resize layouts**, over
your **LAN only** (no cloud), with a real-time **Metal fisheye dewarp**, a modern
**Liquid Glass** UI, listen-in audio with **cry/sound alerts**, and rock-solid
auto-reconnect for an always-on nursery display.

- **Any number of cameras** — add them, then drag/resize/rearrange the panes
  into your own layout (side-by-side, stacked, one-bigger, grid, picture-in-pic).
- **Fisheye cameras** (ceiling-mounted) get a live dewarped panorama with
  interactive pan / tilt / zoom and snap-to-crib presets.

Video comes from your existing **Frigate → go2rtc** setup over **WebRTC**
(sub-second latency). Connect two ways:

- **Direct (go2rtc)** — straight to go2rtc's API port (1984), no login.
- **Frigate login** — through Frigate's authenticated port (8971) with your
  username/password; Cribsight logs in and lists your cameras for you.

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

## 1. Point it at Frigate (one stream per camera)

If your cameras already live in **Frigate**, you don't need to add any new feeds
or pull a second stream off the cameras. Frigate bundles **go2rtc**, which keeps
a *single* connection to each camera and fans it out to detection, recording, and
any live viewer — Cribsight included. So Cribsight just becomes one more consumer
of the restream; the cameras never see extra load.

**a) Make sure each camera is in Frigate's `go2rtc:` restream section.** This is
what gives it a reusable stream name (and is also how Frigate avoids hammering the
camera). In your Frigate `config.yml`:

```yaml
go2rtc:
  streams:
    owlet:
      - rtsp://user:pass@192.168.1.21:554/h264Preview_01_main
    reolink:
      - rtsp://user:pass@192.168.1.22:554/h264Preview_01_main
  webrtc:
    candidates:
      - 192.168.1.50:8555   # <-- your Frigate box's LAN IP, go2rtc WebRTC port

cameras:
  nursery:
    ffmpeg:
      inputs:
        - path: rtsp://127.0.0.1:8554/reolink   # detect/record off the restream,
          roles: [detect, record]                # not a 2nd pull from the camera
```

**b) Expose the go2rtc API port (1984).** Frigate doesn't publish it by default.
Add it to your Frigate container's ports so Cribsight can reach the WHEP endpoint:

```yaml
# docker-compose.yml (Frigate service)
ports:
  - "1984:1984"   # go2rtc API / WHEP  ← add this
  - "8555:8555/tcp"
  - "8555:8555/udp"
```

That's it on the server side. Cribsight talks to
`http://<frigate-ip>:1984/api/whep?src=<stream>` and reuses the existing restream.

> Standalone go2rtc (no Frigate) works exactly the same — just put your cameras
> under `streams:` and set `webrtc.candidates`.

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

On first launch the onboarding screen asks you to:

1. Pick a **connection mode**:
   - **Direct (go2rtc)** — enter host + port `1984`.
   - **Frigate login** — enter host + port `8971`, plus your Frigate
     **username/password** (stored in the iOS Keychain, never on disk).
2. Tap **Connect & find cameras** — Cribsight reaches your server (logging in if
   needed) and lists every stream it finds. Tap a chip to fill a camera's stream
   name (no typing).
3. Add as many **cameras** as you like, name them, and flag any **fisheye** ones.

Tap **Start Monitoring**. Panes should go **Live** in well under a second.

### Arranging your layout

Tap the **grid button** in the bottom control bar to enter layout mode, then:

- **Drag** a pane to move it, drag the **corner handle** to resize, tap **✕** to
  remove it. Edits snap to a grid and save automatically.
- Use the **presets** (side-by-side, stacked, one-bigger, grid, picture-in-pic)
  as a starting point, or **Add camera** to drop another pane in.
- Save multiple named layouts and switch between them in **Settings ▸ Layouts**.

Everything (cameras, layouts, fisheye calibration) is editable later from the
**gear ▸ Settings** sheet.

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

### Fisheye superpowers

A single ceiling fisheye can drive **multiple panes at once**, each its own
virtual camera. In layout mode, tap **Split fisheye** to instantly get two
side-by-side PTZ views (e.g. one per crib) from the one stream — decoded once, no
extra load. Add more panes of the same camera and aim each independently
(drag to pan/tilt, pinch to zoom). Each pane remembers its framing.

Projection modes (per pane, from the preset bar): **Panorama** (equirectangular
strip), **Zoom** (rectilinear virtual-PTZ), and **Planet** (a stereographic
"tiny planet" of the whole room). Edges are anti-aliased so the circular boundary
stays clean.

To tune the lens, open the camera in **Settings ▸ Cameras ▸ (your fisheye)** and
adjust:

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
