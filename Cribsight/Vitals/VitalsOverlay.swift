import SwiftUI

/// Compact glass HUD of a sock's live vitals, shown under the camera label in
/// Baby Mode. The user picks which metrics appear (and their order) per camera;
/// tapping opens the history sheet.
struct VitalsOverlay: View {
    let vitals: Vitals
    /// The metrics to show, in order (from the camera's `hudFields`).
    var fields: [VitalsField] = VitalsField.defaultFields
    var onTap: () -> Void

    /// Wrap onto a new row after this many metrics so the pill never runs off a tile.
    private let perRow = 4

    private var rows: [[VitalsField]] {
        stride(from: 0, to: fields.count, by: perRow).map {
            Array(fields[$0..<min($0 + perRow, fields.count)])
        }
    }

    var body: some View {
        if fields.isEmpty {
            EmptyView()
        } else {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 10) {
                            ForEach(row) { stat($0) }
                        }
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .glassPill()
            }
            .buttonStyle(.plain)
        }
    }

    private func stat(_ field: VitalsField) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon(field))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(field.color(from: vitals))
            Text(field.value(from: vitals) ?? "—")
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
            if !field.unit.isEmpty {
                Text(field.unit).font(.caption2).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func icon(_ field: VitalsField) -> String {
        guard field == .battery, let b = vitals.battery else { return field.icon }
        if vitals.charging == true { return "battery.100.bolt" }
        switch b {
        case 0..<13: return "battery.0"
        case 13..<38: return "battery.25"
        case 38..<63: return "battery.50"
        case 63..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}

extension VitalsField {
    /// Display-only color cue (NOT a medical alert — the Owlet app/base do the real
    /// alerting). Green = nominal, amber = watch, red = out of the typical range.
    func color(from v: Vitals) -> Color {
        switch self {
        case .heartRate:
            guard let hr = v.heartRate else { return Theme.textTertiary }
            switch hr {
            case 80...180: return Theme.live
            case 60..<80, 181...210: return Theme.warn
            default: return Theme.danger
            }
        case .oxygen, .oxygenAvg:
            guard let o2 = (self == .oxygen ? v.oxygen : v.oxygenAvg) else { return Theme.textTertiary }
            switch o2 {
            case 95...100: return Theme.live
            case 90..<95: return Theme.warn
            default: return Theme.danger
            }
        case .battery:
            guard let b = v.battery else { return Theme.textTertiary }
            return b <= 15 ? Theme.danger : (b <= 30 ? Theme.warn : Theme.textSecondary)
        case .sleep:
            return v.sleepShort == nil ? Theme.textTertiary : Theme.accent
        default:
            return value(from: v) == nil ? Theme.textTertiary : Theme.textSecondary
        }
    }
}

/// A scrollable detail + history sheet for one sock: current values and simple
/// HR / SpO₂ sparklines over the rolling sample window.
struct VitalsHistoryView: View {
    @ObservedObject var service: VitalsService
    let dsn: String
    let title: String
    @Environment(\.dismiss) private var dismiss

    private var device: VitalsDevice? { service.device(dsn: dsn) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let v = device?.sensors {
                        currentGrid(v)
                    } else {
                        Text("Sock isn't reporting right now (it may be charging or off-foot).")
                            .font(.subheadline).foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center).padding(.top, 30)
                    }
                    chartCard("Heart rate", unit: "bpm", color: Theme.danger) { $0.heartRate.map(Double.init) }
                    chartCard("Oxygen", unit: "%", color: Theme.accent) { $0.oxygen.map(Double.init) }
                }
                .padding(20)
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
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    private func currentGrid(_ v: Vitals) -> some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: cols, spacing: 12) {
            metric("Heart rate", v.heartRate.map { "\($0) bpm" }, "heart.fill")
            metric("Oxygen", v.oxygen.map { "\($0)%" }, "lungs.fill")
            metric("Sleep", v.sleepLabel, "moon.zzz.fill")
            metric("Skin temp", v.skinTemp.map { String(format: "%.0f°F", $0) }, "thermometer.medium")
            metric("Battery", v.battery.map { "\($0)%" }, "battery.100")
            metric("Signal", v.signalStrength.map { "\($0) dBm" }, "antenna.radiowaves.left.and.right")
        }
    }

    private func metric(_ title: String, _ value: String?, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Theme.accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(Theme.textTertiary)
                Text(value ?? "—").font(.headline).foregroundStyle(Theme.textPrimary)
            }
            Spacer()
        }
        .padding(12)
        .glassCard(cornerRadius: 16)
    }

    private func chartCard(_ title: String, unit: String, color: Color,
                           _ pick: @escaping (Vitals) -> Double?) -> some View {
        let points: [Double] = service.history.compactMap { sample in
            sample.snapshot.device(dsn: dsn).flatMap { pick($0.sensors) }
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                if let last = points.last {
                    Text("\(Int(last)) \(unit)").font(.subheadline.monospacedDigit())
                        .foregroundStyle(color)
                }
            }
            Sparkline(values: points, color: color)
                .frame(height: 64)
            Text("Last \(points.count) samples").font(.caption2).foregroundStyle(Theme.textTertiary)
        }
        .padding(14)
        .glassCard()
    }
}

/// Minimal line chart for a series of values (no external dependency).
struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            if values.count < 2 {
                Text("Collecting…")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let lo = values.min() ?? 0
                let hi = values.max() ?? 1
                let span = max(hi - lo, 1)
                Path { p in
                    for (i, v) in values.enumerated() {
                        let x = geo.size.width * CGFloat(i) / CGFloat(values.count - 1)
                        let y = geo.size.height * (1 - CGFloat((v - lo) / span))
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
