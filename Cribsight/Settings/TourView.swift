import SwiftUI

/// A short, glassy paged walkthrough shown once after onboarding (and replayable
/// from Settings ▸ How to use). Teaches the Frigate connect flow, layouts, the
/// fisheye gestures, listen-in/cry alerts, and night/kiosk.
struct TourView: View {
    var onDone: () -> Void

    @State private var page = 0
    private let pages = TourPage.all

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            RadialGradient(colors: [Theme.accent.opacity(0.22), .clear],
                           center: .top, startRadius: 20, endRadius: 560)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip") { Haptics.tap(); onDone() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                }
                .padding(.horizontal, 16).padding(.top, 14)

                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { i in
                        pageView(pages[i]).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Button {
                    if page < pages.count - 1 {
                        withAnimation { page += 1 }
                        Haptics.tap()
                    } else {
                        Haptics.success()
                        onDone()
                    }
                } label: {
                    Text(page < pages.count - 1 ? "Next" : "Got it — let's go")
                        .frame(maxWidth: .infinity)
                }
                .glassButton(prominent: true)
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    private func pageView(_ p: TourPage) -> some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Theme.brandGradient)
                    .frame(width: 116, height: 116)
                    .shadow(color: Theme.accent.opacity(0.4), radius: 20, y: 8)
                Image(systemName: p.icon)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(p.title)
                .font(.title.bold())
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(p.body)
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 16)
    }
}

/// One page of the tour.
struct TourPage: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let body: String

    static let all: [TourPage] = [
        TourPage(icon: "eye.fill",
                 title: "Welcome to Cribsight",
                 body: "A private, multi-camera nursery monitor that lives only on your network — no cloud, no accounts. Here's the 30-second tour."),
        TourPage(icon: "lock.shield.fill",
                 title: "Connect to Frigate",
                 body: "Enter your Frigate address and login, then tap “Connect & find cameras.” Cribsight signs in and lists your cameras — tap to add the ones you want. One camera or ten, it's up to you."),
        TourPage(icon: "square.grid.2x2.fill",
                 title: "Arrange your view",
                 body: "Tap the grid button to arrange panes: drag to move, pull a corner to resize, tap ✕ to remove. Use a preset — Single (one camera full-screen), Side-by-side, Stacked, One-bigger, Grid, or Picture-in-picture."),
        TourPage(icon: "globe.americas.fill",
                 title: "Fisheye superpowers",
                 body: "Flag a ceiling camera as Fisheye and it's live-dewarped for you. Pinch to zoom in and drag to look around the room. Tap “Split fisheye” to turn that one camera into several independent close-ups — one per crib."),
        TourPage(icon: "waveform",
                 title: "Listen in & cry alerts",
                 body: "Tap a pane's speaker to listen; the little bars show the sound level. Cribsight flashes and buzzes when it hears sustained crying — fine-tune the sensitivity per camera in Settings."),
        TourPage(icon: "moon.stars.fill",
                 title: "Night mode & kiosk",
                 body: "Night Mode gently dims and warms the screen on a schedule. The lock button hides every control for a clean, full-bleed wall display — perfect for an always-on nursery iPad.")
    ]
}
