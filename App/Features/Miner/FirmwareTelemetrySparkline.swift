import SwiftUI

/// Observed samples only. A single observation is a dot, never an invented flat history.
struct FirmwareTelemetrySparkline: View {
    let values: [Double]
    let nominal: Double?

    private var validValues: [Double] { values.filter { $0.isFinite && $0 >= 0 } }

    var body: some View {
        GeometryReader { _ in
            if validValues.isEmpty {
                Text("Collecting observed samples")
                    .fleetFont(.caption2)
                    .foregroundStyle(FleetTheme.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                Canvas { context, size in
                    draw(in: &context, size: size)
                }
                .accessibilityHidden(true)
            }
        }
        .background(FleetTheme.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(FleetTheme.separator.opacity(0.55), lineWidth: 0.75)
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let reference = nominal.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let scaleValues = validValues + (reference.map { [$0] } ?? [])
        // Normalize before subtracting/padding, so even very large finite firmware values
        // cannot overflow the plotting range. The displayed measurements are never changed.
        let scale = max(scaleValues.max() ?? 1, 1)
        let low = (scaleValues.min() ?? 0) / scale
        let high = (scaleValues.max() ?? 0) / scale
        let padding = max((high - low) * 0.12, 0.02)
        let lower = low - padding
        let span = high - low + 2 * padding
        let plot = CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6)
        guard plot.width > 0, plot.height > 0 else { return }
        func y(_ value: Double) -> CGFloat {
            plot.maxY - plot.height * CGFloat((value / scale - lower) / span)
        }

        for fraction: CGFloat in [0.25, 0.5, 0.75] {
            let row = plot.minY + plot.height * fraction
            var grid = Path()
            grid.move(to: CGPoint(x: plot.minX, y: row))
            grid.addLine(to: CGPoint(x: plot.maxX, y: row))
            context.stroke(grid, with: .color(FleetTheme.separator.opacity(0.4)), lineWidth: 0.5)
        }
        if let reference {
            var rule = Path()
            rule.move(to: CGPoint(x: plot.minX, y: y(reference)))
            rule.addLine(to: CGPoint(x: plot.maxX, y: y(reference)))
            context.stroke(rule, with: .color(FleetTheme.secondary.opacity(0.75)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }

        var line = Path()
        var previousWasValid = false
        var points: [CGPoint] = []
        for (index, value) in values.enumerated() {
            guard value.isFinite && value >= 0 else {
                previousWasValid = false
                continue
            }
            let x = values.count == 1 ? plot.midX
                : plot.minX + plot.width * CGFloat(index) / CGFloat(values.count - 1)
            let point = CGPoint(x: x, y: y(value))
            if previousWasValid { line.addLine(to: point) } else { line.move(to: point) }
            points.append(point)
            previousWasValid = true
        }
        context.stroke(line, with: .color(FleetTheme.accent),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        for (index, point) in points.enumerated() {
            let radius: CGFloat = index == points.count - 1 ? 3 : 1.5
            let dot = CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius)
            context.fill(Path(ellipseIn: dot), with: .color(FleetTheme.accent))
        }
    }
}
