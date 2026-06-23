<div align="center">

<img src="docs/icon.png" alt="Cribsight" width="172">

# Cribsight

**A native, LAN-only multi-camera baby monitor for iPad & iPhone.**

Sub-second **WebRTC** video · real-time **Metal** fisheye dewarp · **Liquid Glass** UI · listen-in audio with **cry alerts**. No cloud. No accounts. No subscription.

<br>

![Platform](https://img.shields.io/badge/iOS-18%2B-0A84FF?logo=apple&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-Swift%205-F05138?logo=swift&logoColor=white)
![Rendering](https://img.shields.io/badge/Render-Metal-1B998B?logo=apple&logoColor=white)
![Transport](https://img.shields.io/badge/Video-WebRTC-FF5A5F?logo=webrtc&logoColor=white)
![Source](https://img.shields.io/badge/Cameras-Frigate%20%2F%20go2rtc-7C5CFC)
![Network](https://img.shields.io/badge/LAN--only-no%20cloud-30D158)

</div>

---

> Point it at the **Frigate** box you already run, pick the cameras you want, and
> drag them into whatever layout fits your nursery. The cameras never see extra
> load — Cribsight rides Frigate's single restream — and the whole thing lives on
> your local network, so the only thing watching your baby is **you**.

## ✨ Highlights

| | |
|---|---|
| 🎥 **Any number of cameras** | Add as many as you want and arrange them in **custom drag-to-resize layouts** — side-by-side, stacked, one-bigger, grid, picture-in-picture. Save and switch between named layouts. |
| 🌀 **Real-time fisheye dewarp** | A ceiling fisheye is unwrapped on the GPU into **Panorama**, **Zoom** (virtual PTZ), or a stereographic **tiny-planet**. One stream can drive **multiple independent PTZ panes** — decoded once. |
| ⚡ **Sub-second latency** | Direct **WebRTC** from go2rtc — no HLS buffering, no relay, no round-trip to a server farm. |
| 🔊 **Listen-in + cry alerts** | Per-pane audio with a live VU meter; a red flash, haptic, and toast when sustained noise crosses a per-camera sensitivity threshold. |
| 🔐 **Frigate login** | Connect through Frigate's authenticated port with your username/password — credentials live in the **iOS Keychain**, and Cribsight lists your cameras for you. |
| 🪟 **Liquid Glass UI** | Native `.glassEffect` on iOS 26 with a clean material fallback on iOS 18–25. Dark-first nursery theme + a **Night Mode** that dims and warms the screen. |
| 🛡️ **Always-on** | Per-pane exponential-backoff reconnect, a frame **watchdog** that recovers silent stalls, keep-awake, and a **kiosk lock** for wall displays. |
| 📸 **Snapshots** | Grab a still to Photos in a tap. |

---

## Requirements

- **Xcode 26** (Liquid Glass SDK) on macOS.
- iPad/iPhone on **iOS 18+** (Liquid Glass renders natively on iOS 26; falls back to a translucent material on 18–25).
- A **paid Apple Developer account** for TestFlight (a free personal team works for installing on your own device).
- **Frigate** (or standalone **go2rtc**) reachable on your LAN, with your cameras exposed as restreams.

---

## 1 · Point it at Frigate

Your cameras already live in **Frigate**, which bundles **go2rtc** and keeps a
*single* connection to each camera — fanning it out to detection, recording, and
any live viewer. Cribsight just becomes one more consumer of that restream, so
**the cameras never see extra load.**

**a) Put each camera in Frigate's `go2rtc:` restream section** (this is what gives
it a reusable stream name and what lets detect/record run off the restream
instead of hitting the camera twice):

```yaml
go2rtc:
  streams:
    nursery:
      - rtsp://user:pass@192.168.1.21:554/h264Preview_01_main
    playroom:
      - rtsp://user:pass@192.168.1.22:554/h264Preview_01_main
  webrtc:
    candidates:
      - 192.168.1.50:8555      # ← your Frigate box's LAN IP + go2rtc WebRTC port

cameras:
  nursery:
    ffmpeg:
      inputs:
        - path: rtsp://127.0.0.1:8554/nursery   # detect/record off the restream,
          roles: [detect, record]               # not a 2nd pull from the camera
```

**b) Make the WebRTC media path reachable.** WebRTC carries video over port
**8555 (TCP + UDP)** — make sure that's open on the LAN and that
`webrtc.candidates` lists your Frigate box's IP. This is the single most common
"stuck on Connecting…" cause.

**c) Pick how Cribsight connects** — two modes, choose in onboarding:

| Mode | Port | Auth | Expose extra ports? |
|---|---|---|---|
| **Frigate login** *(recommended)* | `8971` | Your Frigate user/pass | No — `8971` already serves the UI |
| **Direct (go2rtc)** | `1984` | None (LAN-trusted) | Add `- "1984:1984"` to the Frigate container |

> Standalone go2rtc (no Frigate) works the same — put cameras under `streams:`,
> set `webrtc.candidates`, and use **Direct** mode against port `1984`.

---

## 2 · Open in Xcode

```bash
open Cribsight.xcodeproj
```

1. Let Xcode resolve the Swift Package (`stasel/WebRTC`) — *File ▸ Packages ▸ Resolve Package Versions* if it doesn't start on its own.
2. **Cribsight** target ▸ **Signing & Capabilities** → set your **Team** and a unique **Bundle Identifier** (e.g. `com.yourname.cribsight`).
3. If you have GPU shaders prompting it, install the **Metal Toolchain** (Settings ▸ Components, or `xcodebuild -downloadComponent MetalToolchain`).
4. Pick your iPad and **⌘R**.

> Regenerate the project anytime with `brew install xcodegen && xcodegen generate`.

---

## 3 · First run

1. Pick a **connection mode** and enter the host:
   - **Frigate login** → host + port `8971` + your Frigate **username/password** (saved to the Keychain).
   - **Direct (go2rtc)** → host + port `1984`.
2. Tap **Connect & find cameras** — Cribsight reaches your server (logging in if needed) and lists every stream. Tap a chip to assign one to a pane — no typing, no typos.
3. Add your **cameras**, name them, and flag any **fisheye** ones.
4. **Start Monitoring** — panes go **Live** in well under a second.

### Arranging your layout

Tap the **grid button** in the control bar to enter layout mode:

- **Drag** to move a pane, drag the **corner handle** to resize, tap **✕** to remove. Edits snap to a grid and save automatically.
- Start from a **preset** (side-by-side · stacked · one-bigger · grid · picture-in-picture) or **Add camera** to drop in another pane.
- For a ceiling fisheye, tap **Split fisheye** to instantly get two independent PTZ views (e.g. one per crib) from the one stream.
- Keep multiple named layouts and switch in **Settings ▸ Layouts**.

---

## Fisheye superpowers

A single ceiling fisheye can drive **multiple panes at once**, each its own
virtual camera, decoded **once**. Aim each pane independently — drag to pan/tilt,
pinch to zoom — and it remembers its framing.

Projection modes (per pane, from the preset bar):

- **Panorama** — equirectangular strip across the room.
- **Zoom** — rectilinear virtual-PTZ for crib close-ups.
- **Planet** — a stereographic "tiny planet" of the whole room.

Tune the lens in **Settings ▸ Cameras ▸ (your fisheye)**:

- **Center X/Y** + **Radius** so the circular image fills the dewarp.
- **Lens FOV°** to match your lens (Reolink fisheye ≈ 180–200°).
- **Pano top/bottom°** to frame the cribs.
- **Flip** if the image is mirrored.

Changes apply when you close Settings.

---

## Ship to TestFlight

1. Run destination → **Any iOS Device (arm64)**, then **Product ▸ Archive**.
2. Organizer → **Distribute App ▸ App Store Connect ▸ Upload**. Uncheck *"Upload your app's symbols"* to skip the harmless WebRTC dSYM warning (it's a precompiled framework with no dSYM).
3. Add the build to **TestFlight** and install on the nursery iPad.

The project ships a `PrivacyInfo.xcprivacy` (declares only `UserDefaults`; no
tracking, no data collected) and sets `ITSAppUsesNonExemptEncryption = NO`, so
there's no export-compliance prompt and no privacy-manifest warning.

### Kiosk mode

For a locked-down wall display, use iOS **Guided Access** (Settings ▸
Accessibility ▸ Guided Access) and triple-click the side button. The in-app
**lock** button also hides every control for a clean, full-bleed view.

---

## Architecture

```
Frigate :8971 (auth) ──login──► JWT ──► iOS Keychain
   │ go2rtc restream — ONE pull per physical camera
   ▼
WebRTC  (WHEP or WebSocket signaling · media over :8555)
   ▼
CameraSource ── decoded once per camera ───────────────┐
   │                                                    │  fisheye → N virtual PTZ panes
   ├─ video ─► FrameSink (CVPixelBuffer) ─► DewarpRenderer (Metal) ─► MTKView  (per pane)
   │                                              ▲ pan/tilt/zoom ◄─ gestures
   └─ audio ─► AVAudioSession(.playback) ─► VU meter + CryDetector
```

| Area | Files |
|---|---|
| App / shell | `App/CribsightApp.swift`, `App/RootView.swift` |
| Monitor UI | `Monitor/MonitorView.swift`, `CameraPaneView.swift`, `ControlBar.swift`, `LayoutEditorBar.swift`, `PresetPicker.swift`, `AlertOverlay.swift` |
| Layout engine | `Monitor/LayoutCanvas.swift`, `Settings/Layout.swift` |
| View models / sources | `Monitor/MonitorViewModel.swift`, `PaneViewModel.swift`, `CameraSource.swift` |
| Connection / WebRTC | `WebRTC/WebRTCClient.swift`, `Signaling.swift`, `WHEPSignaling.swift`, `WebSocketSignaling.swift`, `FrigateClient.swift`, `ReconnectController.swift`, `StatsMonitor.swift`, `RTCFactory.swift` |
| Rendering | `Rendering/Shaders.metal`, `DewarpRenderer.swift`, `FrameSink.swift`, `MetalDewarpView.swift`, `DewarpUniforms.swift` |
| Audio / capture | `Audio/AudioController.swift`, `CryDetector.swift`, `Capture/SnapshotService.swift` |
| Settings / config | `Settings/AppConfig.swift`, `CameraConfig.swift`, `ConnectionSettings.swift`, `Keychain.swift`, `SettingsView.swift`, `CameraSettingsView.swift`, `OnboardingView.swift`, `StreamDiscovery.swift`, `StreamChips.swift` |
| Design | `Design/Theme.swift`, `GlassSurface.swift`, `GlassControls.swift`, `NightModeOverlay.swift`, `Haptics.swift` |

Dependency: [`stasel/WebRTC`](https://github.com/stasel/WebRTC) via Swift Package Manager.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Panes stuck on **"Connecting…"** | The `webrtc.candidates` / port **8555** step. Confirm the iPad and Frigate are on the same subnet and the candidate IP is right. |
| **"Live" but no video** | Stream name must match go2rtc exactly — use the discovered chips instead of typing. |
| **Login fails** (Frigate mode) | Check the port is `8971` (not the UI's `5000`) and the user/pass are right. On a self-signed cert, leave HTTPS off and use plain HTTP on the LAN. |
| **HTTP blocked** | The app allows local-network cleartext via `NSAllowsLocalNetworking` — LAN addresses only, by design. |
| **Package won't resolve** | File ▸ Packages ▸ Reset Package Caches, then Resolve. |
| **Fisheye looks wrong** | Tune Center / Radius / Lens FOV in Settings ▸ Cameras. |

---

<div align="center">

**Built for the one screen in the house that should never go dark.** 👁️

*LAN-only · no cloud · no accounts*

</div>
