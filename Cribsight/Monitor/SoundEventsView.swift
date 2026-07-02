import SwiftUI

/// Sheet listing recent cry/sound alerts (newest first) so a parent can see at a
/// glance what happened overnight. Session-scoped — clears with the app.
struct SoundEventsView: View {
    @ObservedObject var vm: MonitorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if vm.soundEvents.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(vm.soundEvents) { event in
                            row(event)
                                .listRowBackground(Theme.canvasElevated)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Sound history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !vm.soundEvents.isEmpty {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Clear") { vm.clearSoundEvents() }
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    private func row(_ event: MonitorViewModel.SoundEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.badge.fill")
                .foregroundStyle(Theme.accentWarm)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.cameraName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(event.date, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Text(event.date, style: .relative)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            Text("No sounds detected")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("When Cribsight hears sustained crying or noise, it shows up here with the camera and time.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}
