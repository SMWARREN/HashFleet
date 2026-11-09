import SwiftUI

/// An arc segment of the dial sweep, animatable so the fill follows the needle.
private struct DialArc: Shape {
    var to: Double
    let radiusFraction: CGFloat

    var animatableData: Double { get { to } set { to = newValue } }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard to > 0 else { return path }
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: MinerTuningDialGeometry.radius(in: rect.size) * radiusFraction,
                    startAngle: MinerTuningDialGeometry.angle(0), endAngle: MinerTuningDialGeometry.angle(to), clockwise: false)
        return path
    }
}

/// A tapered pointer that travels along the sweep, drawn as a path rather than a rotated image.
private struct DialNeedle: Shape {
    var fraction: Double
    let inner: CGFloat, outer: CGFloat, width: CGFloat

    var animatableData: Double { get { fraction } set { fraction = newValue } }

    func path(in rect: CGRect) -> Path {
        let radius = MinerTuningDialGeometry.radius(in: rect.size)
        let radians = MinerTuningDialGeometry.angle(fraction).radians
        let (dx, dy) = (cos(radians), sin(radians))
        let half = width * radius / 2
        func spot(_ distance: CGFloat, _ offset: CGFloat) -> CGPoint {
            CGPoint(x: rect.midX + dx * distance * radius - dy * offset, y: rect.midY + dy * distance * radius + dx * offset)
        }
        var path = Path()
        path.addLines([spot(inner, half), spot(outer, half * 0.3), spot(outer, -half * 0.3), spot(inner, -half)])
        path.closeSubpath()
        return path
    }
}

/// The touchable ring. The centre readout stays free so page scrolling still works there.
private struct DialRing: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(ellipseIn: rect)
        path.addEllipse(in: rect.insetBy(dx: rect.width / 4, dy: rect.height / 4))
        return path
    }
}

/// Static scale artwork: redline band, ticks, labels, firmware option notches and the miner's current value.
private struct DialScale: View {
    let range: ClosedRange<Double>
    let step: Double, referenceMaximum: Double?, configuredValue: Double?
    let referenceOptions: [Double]
    let formatValue: (Double) -> String

    var body: some View {
        Canvas { context, size in
            let radius = MinerTuningDialGeometry.radius(in: size)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let redline = referenceMaximum.map { MinerTuningDialGeometry.fraction($0, in: range) }
            if let redline, redline < 1 {
                var band = Path()
                band.addArc(center: center, radius: radius * 0.905, startAngle: MinerTuningDialGeometry.angle(redline), endAngle: MinerTuningDialGeometry.angle(1), clockwise: false)
                context.stroke(band, with: .color(.red.opacity(0.26)), lineWidth: radius * 0.1)
            }
            drawTicks(in: &context, center: center, radius: radius, redline: redline)
            for option in referenceOptions where range.contains(option) {
                let spot = MinerTuningDialGeometry.point(MinerTuningDialGeometry.fraction(option, in: range), center: center, radius: radius * 0.99)
                let dot = CGRect(x: spot.x, y: spot.y, width: 0, height: 0).insetBy(dx: -radius * 0.022, dy: -radius * 0.022)
                context.fill(Path(ellipseIn: dot), with: .color(FleetTheme.secondary.opacity(0.8)))
            }
            if let configuredValue {
                let fraction = MinerTuningDialGeometry.fraction(configuredValue, in: range)
                var marker = Path()
                marker.move(to: MinerTuningDialGeometry.point(fraction, center: center, radius: radius * 0.73))
                marker.addLine(to: MinerTuningDialGeometry.point(fraction, center: center, radius: radius * 0.87))
                context.stroke(marker, with: .color(FleetTheme.ink.opacity(0.75)),
                               style: StrokeStyle(lineWidth: max(2, radius * 0.022), lineCap: .round, dash: [3, 2]))
            }
        }
    }

    private func drawTicks(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat, redline: Double?) {
        let minor = MinerTuningDialGeometry.majorInterval(span: range.upperBound - range.lowerBound, step: step) / 5
        guard minor > 0 else { return }
        let lower = (range.lowerBound / minor).rounded(.up)
        let upper = (range.upperBound / minor).rounded(.down)
        // Int(_:) traps on non-finite or out-of-range values; reject before converting.
        guard lower.isFinite, upper.isFinite, abs(lower) < 1e9, abs(upper) < 1e9 else { return }
        let first = Int(lower)
        let last = Int(upper)
        guard last >= first, last - first <= 400 else { return }
        for index in first...last {
            let value = Double(index) * minor
            let fraction = MinerTuningDialGeometry.fraction(value, in: range)
            let isMajor = index % 5 == 0
            let isRed = redline.map { fraction > $0 + 0.000_1 } ?? false
            var tick = Path()
            tick.move(to: MinerTuningDialGeometry.point(fraction, center: center, radius: radius * (isMajor ? 0.855 : 0.885)))
            tick.addLine(to: MinerTuningDialGeometry.point(fraction, center: center, radius: radius * 0.95))
            context.stroke(tick, with: .color((isRed ? Color.red : FleetTheme.ink).opacity(isMajor ? 0.9 : 0.38)),
                           style: StrokeStyle(lineWidth: isMajor ? max(1.5, radius * 0.016) : 1, lineCap: .round))
            guard isMajor else { continue }
            let label = Text(formatValue(value))
                .font(.system(size: max(8, radius * 0.075), weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(isRed ? Color.red : FleetTheme.secondary)
            context.draw(label, at: MinerTuningDialGeometry.point(fraction, center: center, radius: radius * 0.68))
        }
    }
}

/// Tachometer-style tuning gauge. Its red zone means only "beyond the firmware's reported reference, a deliberate overclock", never a hardware-safe limit.
///
/// `formatValue` formats the bare number (e.g. `"585"`). The centre readout is a real `Text` whose label is
/// `"\(formatValue(setpoint)) \(unit)"`, e.g. `"585 MHz"`, tagged with `valueIdentifier` (or `"<prefix>.value"`).
struct MinerTuningDial: View {
    let title: String, unit: String
    @Binding var setpoint: Double
    let range: ClosedRange<Double>
    let liveValue: Double?, configuredValue: Double?, referenceMaximum: Double?
    let isBeyondReference: Bool
    let isRestricted: Bool
    let isEnabled: Bool
    let referenceOptions: [Double]
    let step: Double, coarseStep: Double
    let accessibilityPrefix: String, valueIdentifier: String?
    let formatValue: (Double) -> String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var readoutSize: CGFloat = 54
    @ScaledMetric(relativeTo: .headline) private var unitSize: CGFloat = 17
    @State private var dragFraction: Double?
    @State private var dragRange: ClosedRange<Double>?

    init(title: String, unit: String, setpoint: Binding<Double>, range: ClosedRange<Double>,
         liveValue: Double? = nil, configuredValue: Double? = nil, referenceMaximum: Double? = nil,
         isBeyondReference: Bool = false, isRestricted: Bool = false, isEnabled: Bool = true,
         referenceOptions: [Double] = [], step: Double = 1,
         coarseStep: Double = 10, accessibilityPrefix: String, valueIdentifier: String? = nil,
         formatValue: @escaping (Double) -> String = { MinerTuningDraft.numericText($0) }) {
        (self.title, self.unit, self._setpoint, self.range) = (title, unit, setpoint, range)
        (self.liveValue, self.configuredValue, self.referenceMaximum) = (liveValue, configuredValue, referenceMaximum)
        (self.isBeyondReference, self.referenceOptions) = (isBeyondReference, referenceOptions)
        self.isEnabled = isEnabled
        self.isRestricted = isRestricted
        (self.step, self.coarseStep, self.accessibilityPrefix) = (step, coarseStep, accessibilityPrefix)
        (self.valueIdentifier, self.formatValue) = (valueIdentifier, formatValue)
    }

    private var beyond: Bool { isRestricted || isBeyondReference || (referenceMaximum.map { setpoint > $0 } ?? false) }
    private var needleColor: Color { beyond ? .red : FleetTheme.accent }
    private var activeRange: ClosedRange<Double> { dragRange ?? range }
    private var fraction: Double { MinerTuningDialGeometry.fraction(setpoint, in: activeRange) }
    private var motion: Animation? { reduceMotion ? nil : .spring(duration: 0.42, bounce: 0.24) }

    var body: some View {
        VStack(spacing: 12) {
            header
            GeometryReader { proxy in
                let radius = MinerTuningDialGeometry.radius(in: proxy.size)
                ZStack {
                    gauge(radius: radius, center: CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2))
                    readout(radius: radius).allowsHitTesting(false)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 360)
            .frame(maxWidth: .infinity)
            stepButtons
        }
        .fleetCard(padding: 16, fill: beyond ? Color.red.opacity(0.06) : FleetTheme.surface,
                   border: beyond ? Color.red.opacity(0.45) : FleetTheme.ink.opacity(0.045))
        .sensoryFeedback(.impact(weight: .light, intensity: 0.55), trigger: setpoint)
        .sensoryFeedback(.impact(weight: .heavy), trigger: beyond) { old, new in !old && new }
        .disabled(!isEnabled)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(title).fleetFont(.headline).foregroundStyle(FleetTheme.ink)
                .accessibilityIdentifier(accessibilityPrefix == "tuningSession.master"
                    ? "tuningSession.frequencyControl" : "\(accessibilityPrefix).title")
            Spacer(minLength: 6)
            if isRestricted {
                Label("Device limit", systemImage: "lock.shield.fill")
                    .fleetFont(.caption, weight: .semibold).foregroundStyle(.red)
            } else if beyond {
                Label("Over reference", systemImage: "exclamationmark.triangle.fill").fleetFont(.caption, weight: .semibold).foregroundStyle(.red)
            } else if let referenceMaximum {
                Text("ref \(formatValue(referenceMaximum)) \(unit)").fleetFont(.caption, design: .monospaced).monospacedDigit().foregroundStyle(FleetTheme.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func gauge(radius: CGFloat, center: CGPoint) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [FleetTheme.raised, FleetTheme.surface], center: .center,
                                     startRadius: 0, endRadius: radius))
                .overlay(Circle().strokeBorder(FleetTheme.separator, lineWidth: 1))
            DialScale(range: activeRange, step: step, referenceMaximum: referenceMaximum, configuredValue: configuredValue,
                      referenceOptions: referenceOptions, formatValue: formatValue)
            DialArc(to: 1, radiusFraction: 0.8)
                .stroke(FleetTheme.separator, style: StrokeStyle(lineWidth: radius * 0.07, lineCap: .round))
            DialArc(to: max(fraction, 0.001), radiusFraction: 0.8)
                .stroke(fillGradient, style: StrokeStyle(lineWidth: radius * 0.07, lineCap: .round))
            if let liveValue {
                DialNeedle(fraction: MinerTuningDialGeometry.fraction(liveValue, in: activeRange), inner: 0.74, outer: 0.99, width: 0.03)
                    .fill(FleetTheme.positive)
                    .shadow(color: FleetTheme.positive.opacity(0.5), radius: 4)
            }
            DialNeedle(fraction: fraction, inner: 0.56, outer: 0.93, width: 0.07)
                .fill(needleColor)
                .shadow(color: needleColor.opacity(0.65), radius: 9)
        }
        .animation(motion, value: setpoint)
        .animation(motion, value: liveValue)
        .contentShape(DialRing(), eoFill: true)
        .highPriorityGesture(dragGesture(center: center))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) dial")
        .accessibilityValue(accessibilityValueText)
        .accessibilityHint("Swipe up or down to change by \(formatValue(step)) \(unit).")
        .accessibilityAdjustableAction { direction in
            if direction == .increment { nudge(by: step) } else if direction == .decrement { nudge(by: -step) }
        }
        .accessibilityIdentifier("\(accessibilityPrefix).dial")
    }

    private var fillGradient: AngularGradient {
        let redline = referenceMaximum.map { MinerTuningDialGeometry.fraction($0, in: activeRange) } ?? 1
        var stops = [Gradient.Stop(color: FleetTheme.accent.opacity(0.25), location: 0), Gradient.Stop(color: FleetTheme.accent, location: redline)]
        if redline < 1 { stops += [Gradient.Stop(color: .red, location: min(redline + 0.001, 1)), Gradient.Stop(color: .red, location: 1)] }
        return AngularGradient(gradient: Gradient(stops: stops), center: .center, startAngle: MinerTuningDialGeometry.angle(0), endAngle: MinerTuningDialGeometry.angle(1))
    }

    private func readout(radius: CGFloat) -> some View {
        let number = Text(isEnabled ? formatValue(setpoint) : "—")
            .font(.system(size: readoutSize, weight: .bold, design: .rounded).monospacedDigit())
        let unitText = Text(unit)
            .font(.system(size: unitSize, weight: .semibold, design: .rounded))
            .foregroundStyle(FleetTheme.secondary)
        return VStack(spacing: 4) {
            Text("SET").fleetFont(.caption2, weight: .bold).tracking(1.6).foregroundStyle(FleetTheme.secondary).accessibilityHidden(true)
            Text("\(number) \(unitText)")
                .foregroundStyle(beyond ? Color.red : FleetTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.35)
                .fleetNumericUpdate(setpoint, reduceMotion: reduceMotion)
                .accessibilityIdentifier(valueIdentifier ?? "\(accessibilityPrefix).value")
            if let deltaText {
                Text(deltaText).fleetFont(.caption, weight: .semibold, design: .monospaced).monospacedDigit().foregroundStyle(beyond ? Color.red : FleetTheme.accent)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .accessibilityIdentifier("\(accessibilityPrefix).delta")
            }
            if let liveValue {
                HStack(spacing: 4) {
                    Circle().frame(width: 6, height: 6).accessibilityHidden(true)
                    Text("Live \(formatValue(liveValue)) \(unit)").lineLimit(1).minimumScaleFactor(0.6)
                        .accessibilityIdentifier("\(accessibilityPrefix).live")
                }
                .fleetFont(.caption2, design: .monospaced).monospacedDigit()
                .foregroundStyle(FleetTheme.positive)
            }
        }
        .frame(width: radius * 1.05)
        .offset(y: radius * 0.06)
    }

    private var deltaText: String? {
        guard let configuredValue else { return nil }
        let delta = setpoint - configuredValue
        guard abs(delta) > 0.000_1 else { return "Matches miner" }
        return "\(delta > 0 ? "+" : "−")\(formatValue(abs(delta))) \(unit) vs miner"
    }

    private var accessibilityValueText: String {
        guard isEnabled else { return "Not reported. This dial is unavailable until a valid setpoint is loaded." }
        var parts = ["\(formatValue(setpoint)) \(unit)"]
        if let configuredValue { parts.append("miner currently at \(formatValue(configuredValue)) \(unit)") }
        if let liveValue { parts.append("measured \(formatValue(liveValue)) \(unit)") }
        if isRestricted { parts.append("above the device-specific voltage limit, applying is blocked") }
        if isBeyondReference { parts.append("beyond the firmware's reported reference, a deliberate overclock") }
        return parts.joined(separator: ", ")
    }

    private var stepButtons: some View {
        let isFrequency = coarseStep == 10 && step == 1
        let buttons = [(-coarseStep, isFrequency ? "minus10" : "minusCoarse"), (-step, isFrequency ? "minus1" : "minus"),
                       (step, isFrequency ? "plus1" : "plus"), (coarseStep, isFrequency ? "plus10" : "plusCoarse")]
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        stepButton(delta: buttons[0].0, identifier: buttons[0].1)
                        stepButton(delta: buttons[1].0, identifier: buttons[1].1)
                    }
                    GridRow {
                        stepButton(delta: buttons[2].0, identifier: buttons[2].1)
                        stepButton(delta: buttons[3].0, identifier: buttons[3].1)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(buttons, id: \.1) { delta, identifier in
                        stepButton(delta: delta, identifier: identifier)
                    }
                }
            }
        }
    }

    private func stepButton(delta: Double, identifier: String) -> some View {
        Button { nudge(by: delta) } label: {
            Text("\(delta < 0 ? "−" : "+")\(formatValue(abs(delta)))")
                .fleetFont(.subheadline, weight: .semibold, design: .monospaced)
                .lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(needleColor)
        .accessibilityLabel("\(delta < 0 ? "Decrease" : "Increase") \(title) by \(formatValue(abs(delta))) \(unit)")
        .accessibilityIdentifier("\(accessibilityPrefix).\(identifier)")
    }

    private func nudge(by delta: Double) {
        guard isEnabled else { return }
        // Steps are relative to the current value, not the range's lower edge. A miner at
        // 1143 mV must move to 1148 with +5 rather than unexpectedly snapping to 1150.
        setpoint = min(max(setpoint + delta, range.lowerBound), range.upperBound)
    }

    private func dragGesture(center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { drag in
                guard isEnabled else { return }
                // Capability reports can arrive mid-gesture. Freeze both mapping and scale
                // until release so a stationary finger never jumps to a new setpoint.
                if dragRange == nil { dragRange = range }
                let mapping = activeRange
                let next = MinerTuningDialGeometry.fraction(at: drag.location, center: center)
                // Ignore jumps across the open bottom gap so one drag cannot wrap from maximum to minimum.
                if let previous = dragFraction, abs(next - previous) > 0.5 { return }
                dragFraction = next
                let value = mapping.lowerBound + next * (mapping.upperBound - mapping.lowerBound)
                let snapped = MinerTuningDialGeometry.snapped(value, step: step, in: mapping)
                if snapped != setpoint { setpoint = snapped }
            }
            .onEnded { _ in
                dragFraction = nil
                dragRange = nil
            }
    }
}

/// Two tuning dials, side by side when at least 560 pt wide, stacked full width otherwise.
struct MinerTuningDialPair: View {
    let frequency: MinerTuningDial
    let voltage: MinerTuningDial

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) { frequency; voltage }
                .frame(minWidth: 560)
            VStack(spacing: 14) { frequency; voltage }
        }
    }
}

/// Compact "ECU readout" comparing staged values with what the miner currently runs.
/// The load bar is a rough orientation estimate only, not a safety limit.
struct MinerTuningDeltaStrip: View {
    let stagedFrequency: Double, configuredFrequency: Double?
    let stagedVoltage: Double, configuredVoltage: Double?
    let estimatedLoad: Double?
    let formatValue: (Double) -> String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(stagedFrequency: Double, configuredFrequency: Double?, stagedVoltage: Double,
         configuredVoltage: Double?, estimatedLoad: Double? = nil,
         formatValue: @escaping (Double) -> String = { MinerTuningDraft.numericText($0) }) {
        (self.stagedFrequency, self.configuredFrequency) = (stagedFrequency, configuredFrequency)
        (self.stagedVoltage, self.configuredVoltage) = (stagedVoltage, configuredVoltage)
        (self.estimatedLoad, self.formatValue) = (estimatedLoad, formatValue)
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        VStack(spacing: 10) {
            layout {
                cell(label: "FREQ", name: "Frequency", unit: "MHz", staged: stagedFrequency, configured: configuredFrequency)
                cell(label: "VCORE", name: "Core voltage", unit: "mV", staged: stagedVoltage, configured: configuredVoltage)
            }
            if let estimatedLoad, estimatedLoad.isFinite { loadBar(min(max(estimatedLoad, 0), 1)) }
        }
        .padding(12)
        .background(FleetTheme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(FleetTheme.separator, lineWidth: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tuningSession.deltaStrip")
    }

    private func cell(label: String, name: String, unit: String, staged: Double, configured: Double?) -> some View {
        let delta = configured.map { staged - $0 } ?? 0
        let changed = abs(delta) > 0.000_1
        let detail = configured.map {
            changed ? "\(delta > 0 ? "+" : "−")\(formatValue(abs(delta))) from \(formatValue($0))" : "Matches miner"
        } ?? "Miner value not reported"
        let tint = changed ? FleetTheme.accent : FleetTheme.secondary
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).fleetFont(.caption2, weight: .bold).tracking(1.2)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Image(systemName: changed ? (delta > 0 ? "arrow.up" : "arrow.down") : "equal").fleetFont(.caption2, weight: .bold)
            }
            .foregroundStyle(tint)
            Text("\(formatValue(staged)) \(unit)")
                .fleetFont(.title3, weight: .semibold, design: .monospaced)
                .foregroundStyle(FleetTheme.ink).lineLimit(1).minimumScaleFactor(0.6)
                .fleetNumericUpdate(staged, reduceMotion: reduceMotion)
            Text(detail).fleetFont(.caption2, design: .monospaced).monospacedDigit().foregroundStyle(tint)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(changed ? FleetTheme.accent.opacity(0.14) : FleetTheme.surface,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(changed ? FleetTheme.accent.opacity(0.6) : Color.clear, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) staged \(formatValue(staged)) \(unit), \(detail)")
    }

    private func loadBar(_ load: Double) -> some View {
        let percent = Int((load * 100).rounded())
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("EST. POWER LOAD").fleetFont(.caption2, weight: .bold).tracking(1.2)
                Spacer()
                Text("\(percent)% · rough").fleetFont(.caption2, design: .monospaced).monospacedDigit()
            }
            .foregroundStyle(FleetTheme.secondary)
            Capsule().fill(FleetTheme.separator).frame(height: 8)
                .overlay {
                    Capsule().fill(LinearGradient(colors: [FleetTheme.positive, FleetTheme.accent, .red], startPoint: .leading, endPoint: .trailing))
                        .mask(alignment: .leading) { Rectangle().scaleEffect(x: load, anchor: .leading) }
                }
                .animation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.15), value: load)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Estimated power load, rough, \(percent) percent")
    }
}

private struct MinerTuningGaugesPreviewHost: View {
    @State private var frequency = 525.0
    @State private var voltage = 1060.0

    var body: some View {
        let frequencyDial = MinerTuningDial(
            title: "Frequency", unit: "MHz", setpoint: $frequency, range: 325...725, liveValue: 521.4, configuredValue: 500,
            referenceMaximum: 575, referenceOptions: [400, 425, 450, 485, 500, 525, 550, 575],
            accessibilityPrefix: "tuningSession.master", valueIdentifier: "tuningSession.frequencyValue")
        let voltageDial = MinerTuningDial(
            title: "Core voltage", unit: "mV", setpoint: $voltage, range: 910...1210, liveValue: 1052, configuredValue: 1060,
            referenceMaximum: 1150, referenceOptions: [1000, 1060, 1100, 1150], step: 5, coarseStep: 25,
            accessibilityPrefix: "tuningSession.voltage", valueIdentifier: "tuningSession.voltageValue")
        ScrollView {
            VStack(spacing: 14) {
                MinerTuningDeltaStrip(stagedFrequency: frequency, configuredFrequency: 500, stagedVoltage: voltage,
                                      configuredVoltage: 1060, estimatedLoad: 0.62)
                MinerTuningDialPair(frequency: frequencyDial, voltage: voltageDial)
            }
            .padding()
        }
        .background(FleetTheme.canvas)
    }
}

#Preview("Tuning gauges") {
    MinerTuningGaugesPreviewHost().preferredColorScheme(.dark)
}
