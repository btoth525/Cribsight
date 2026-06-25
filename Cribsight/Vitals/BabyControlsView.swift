import SwiftUI
import UniformTypeIdentifiers

/// Baby Mode controls for an Owlet-bridge camera: hold-to-talk (two-way audio)
/// and a lullaby library you can play, add, and delete — all routed through the
/// bridge's REST API.
struct BabyControlsView: View {
    let control: OwletControl
    /// Bridge camera name (the Owlet-bridge camera's `streamName`).
    let camera: String
    let title: String

    @StateObject private var recorder = TalkRecorder()
    @State private var sounds: [OwletControl.Sound] = []
    @State private var loadingSounds = true
    @State private var sending = false
    @State private var showImporter = false
    @State private var status: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                talkSection
                lullabySection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let status {
                    Text(status)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .glassPill()
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: status)
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.audio, .mp3, .wav, .mpeg4Audio],
                          allowsMultipleSelection: false) { handleImport($0) }
            .onAppear(perform: loadSounds)
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    // MARK: Talk

    private var talkSection: some View {
        Section {
            talkButton
        } header: {
            Text("Talk to the room")
        } footer: {
            Text("Press and hold to speak through the camera, release to send. Your voice plays on the camera's speaker.")
        }
    }

    private var talkButton: some View {
        let recording = recorder.isRecording
        return HStack {
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: recording ? "mic.fill" : "mic")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(recording ? Theme.danger : Theme.accent)
                    .scaleEffect(recording ? 1.12 : 1)
                Text(sending ? "Sending…" : (recording ? "Release to send" : "Hold to talk"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(recording ? Theme.danger.opacity(0.18) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(recording ? Theme.danger : Theme.hairline, lineWidth: recording ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !recorder.isRecording && !sending { recorder.start() } }
                    .onEnded { _ in sendTalk() }
            )
            .animation(.easeInOut(duration: 0.2), value: recording)
            Spacer()
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    private func sendTalk() {
        guard let clip = recorder.stop() else { flash("Nothing recorded"); return }
        sending = true
        control.talk(camera: camera, audio: clip.data, filename: clip.filename, mime: clip.mime) { ok in
            sending = false
            flash(ok ? "Sent to camera" : "Couldn't reach the bridge")
        }
    }

    // MARK: Lullabies

    private var lullabySection: some View {
        Section {
            if loadingSounds {
                HStack { ProgressView().tint(Theme.accent); Text("Loading…").foregroundStyle(Theme.textSecondary) }
            } else if sounds.isEmpty {
                Text("No lullabies yet. Add a sound to play it on the camera.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(sounds) { sound in
                    Button { play(sound) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "play.circle.fill")
                                .font(.title3).foregroundStyle(Theme.accent)
                            Text(sound.displayName).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.caption).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteSounds)
            }
            Button { showImporter = true } label: {
                Label("Add lullaby", systemImage: "plus.circle.fill")
            }
        } header: {
            HStack {
                Text("Lullabies")
                Spacer()
                Button { loadSounds() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
            }
        } footer: {
            Text("Tap a lullaby to play it on the camera speaker. Swipe left to delete. Add your own audio files (mp3, m4a, wav).")
        }
    }

    private func play(_ sound: OwletControl.Sound) {
        Haptics.tap()
        flash("Playing \(sound.displayName)…")
        control.play(camera: camera, file: sound.name) { ok in
            if !ok { flash("Couldn't play \(sound.displayName)") }
        }
    }

    private func deleteSounds(_ offsets: IndexSet) {
        let targets = offsets.map { sounds[$0] }
        for sound in targets {
            control.deleteSound(sound.name) { ok in
                if ok { sounds.removeAll { $0.id == sound.id } }
                flash(ok ? "Removed \(sound.displayName)" : "Couldn't remove \(sound.displayName)")
            }
        }
    }

    private func loadSounds() {
        loadingSounds = true
        control.listSounds { list in
            sounds = list
            loadingSounds = false
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            flash("Couldn't read that file"); return
        }
        flash("Uploading \(url.lastPathComponent)…")
        control.uploadSound(filename: url.lastPathComponent,
                            data: data,
                            mime: Self.mimeType(for: url.pathExtension)) { ok in
            flash(ok ? "Added \(url.lastPathComponent)" : "Upload failed")
            if ok { loadSounds() }
        }
    }

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "m4a", "aac": return "audio/m4a"
        case "ogg": return "audio/ogg"
        case "caf": return "audio/x-caf"
        default: return "application/octet-stream"
        }
    }

    /// Set a transient status message that auto-clears.
    private func flash(_ message: String) {
        status = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if status == message { status = nil }
        }
    }
}
