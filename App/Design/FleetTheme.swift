import SwiftUI
import HashFleetCore

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import Foundation

/// Content clearance belongs inside a rounded fill, not outside its hit region.
/// Shared by Mac and iOS so compact labels do not crowd their curved edges.
enum FleetSurfaceSpacing {
    static let pill = EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
    static let selection = EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
    static let cardInset: CGFloat = 16
    static let highlightOutset: CGFloat = 12
}

/// Shared visual language for the native HashFleet screens.
enum FleetTheme {
    // White and black bases are the user's explicit preference. Gold and graphite
    // retain the single-miner logo samples, with neutral secondary text and surfaces.
    // Recipes and contrast checks: docs/research/neutral-palette-2026.
    // Artwork is unchanged. Sage is a functional status companion, not a logo sample.
    static let canvas = adaptive(light: 0xFFFFFF, dark: 0x02090C)
    static let surface = adaptive(light: 0xF5F5F5, dark: 0x10191D)
    // A distinct third layer separates individual miners from fleet-level panels.
    static let raised = adaptive(light: 0xE5E5E5, dark: 0x182126)
    static let ink = adaptive(light: 0x21201E, dark: 0xF4F6F7)
    static let secondary = adaptive(light: 0x595959, dark: 0xBFC6CC)
    static let accent = adaptive(light: 0x8A5000, dark: 0xF5AC26)
    static let charcoal = adaptive(light: 0x111111, dark: 0x111111)
    // Slightly lighter sampled blade graphite, still inside the established logo palette.
    static let soloSurface = adaptive(light: 0x21201E, dark: 0x21201E)
    static let panelInk = adaptive(light: 0xFFFFFF, dark: 0xF4F6F7)
    static let panelSecondary = adaptive(light: 0xBDBDBD, dark: 0xBFC6CC)
    static let panelPositive = adaptive(light: 0x2AAE68, dark: 0x25A354)
    static let panelAccent = adaptive(light: 0xE9931E, dark: 0xF5AC26)
    // The chart follows the approved opposite-surface theme: charcoal in light mode and
    // a light neutral in dark mode. Its text and accent swap with the surface so the chart
    // remains readable without introducing a yellow card background.
    static let hashrateSurface = adaptive(light: 0x111111, dark: 0xF5F5F5)
    static let hashrateInk = adaptive(light: 0xFFFFFF, dark: 0x111111)
    static let hashrateSecondary = adaptive(light: 0xBDBDBD, dark: 0x595959)
    static let hashrateAccent = adaptive(light: 0xE9931E, dark: 0x8A5000)
    static let hashrateSkeleton = adaptive(light: 0x262626, dark: 0xE0E0E0)
    static let marqueeSurface = canvas
    static let marqueeInk = ink
    static let marqueeSecondary = secondary
    static let comparisonBorder = adaptive(light: 0xE9931E, dark: 0xFFB72E)
    static let positive = adaptive(light: 0x356447, dark: 0x25A354)
    static let warning = adaptive(light: 0x864705, dark: 0xF5AC26)
    static let separator = adaptive(light: 0xCCCCCC, dark: 0x27343A)
    /// Shared sidebar layers sampled from the existing iPad workspace.
    static let sidebarSurface = adaptive(light: 0xF5F5F5, dark: 0x162228)
    static let sidebarSelection = adaptive(light: 0xE5E5E5, dark: 0x2A363C)
    static let controlBorder = adaptive(light: 0x897869, dark: 0x566F7C)
    static let chartThird = adaptive(light: 0x245E97, dark: 0x7AB6EC)
    static let chartFourth = adaptive(light: 0x897869, dark: 0xC6CED6)
    static let buttonInk = adaptive(light: 0xFFFFFF, dark: 0x10120F)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
#if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
#else
        let name = NSColor.Name(
            "app.hashfleet.FleetTheme.\(String(light, radix: 16)).\(String(dark, radix: 16))"
        )
        return Color(nsColor: NSColor(name: name) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let value = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
#endif
    }

    static func mono(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
}

/// The approved single-miner mark. Keep the image opaque and unmodified so it reads
/// consistently in the toolbar, About screen, and onboarding card.
struct FleetBrandMark: View {
    var size: CGFloat = 72

    var body: some View {
        Image("HashFleetBrand")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .accessibilityHidden(true)
    }
}

private struct FleetCardModifier: ViewModifier {
    let padding: CGFloat
    let fill: Color
    let border: Color
    let borderWidth: CGFloat
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(border, lineWidth: borderWidth)
            }
    }
}

extension View {
    /// Apply before a capsule background so every edge has real content clearance.
    func fleetPillPadding() -> some View {
        padding(FleetSurfaceSpacing.pill)
    }

    /// A menu whose label already draws its own hit area and visual treatment.
    /// Keep native form buttons at their normal style rather than flattening the whole app.
    @ViewBuilder
    func fleetDesignedMenu() -> some View {
        #if os(macOS)
        self.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        #else
        self
        #endif
    }

    func fleetCard(padding: CGFloat = 20, fill: Color = FleetTheme.surface,
                   border: Color = FleetTheme.ink.opacity(0.045), borderWidth: CGFloat = 1,
                   cornerRadius: CGFloat = 24) -> some View {
        modifier(FleetCardModifier(
            padding: padding,
            fill: fill,
            border: border,
            borderWidth: borderWidth,
            cornerRadius: cornerRadius
        ))
    }

    /// Numeric content changes in place instead of replacing the whole label. The value is kept as
    /// a string so formatted units such as `TH/s`, `W` and share counts retain their existing layout.
    /// SwiftUI's numeric transition handles the digits while the surrounding label stays anchored.
    /// Native Mac publishes live telemetry every second to dozens of labels at once. Each rolling
    /// numeric transition is a blurred, CPU-rasterized animation, which measured about 57% versus
    /// 20% idle CPU on a live miner page (2026-11-06). Mac labels therefore update in place.
    func fleetNumericUpdate<Value: Equatable>(_ value: Value, reduceMotion requested: Bool) -> some View {
        fleetNumericUpdate(value, reduceMotion: requested, isHeadline: false)
    }

    /// Headline numbers (fleet and miner hashrate) keep rolling digits on every platform.
    func fleetHeadlineNumericUpdate<Value: Equatable>(_ value: Value, reduceMotion requested: Bool) -> some View {
        fleetNumericUpdate(value, reduceMotion: requested, isHeadline: true)
    }

    private func fleetNumericUpdate<Value: Equatable>(
        _ value: Value, reduceMotion requested: Bool, isHeadline: Bool
    ) -> some View {
        let reduceMotion = requested || FleetNumericMotionPolicy.updatesInPlace(isHeadline: isHeadline)
        return contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: value)
            .transaction { transaction in
                if reduceMotion { transaction.animation = nil }
            }
    }

    /// Numeric content changes in place using the ambient `accessibilityReduceMotion` environment setting.
    func fleetNumericUpdate<Value: Equatable>(_ value: Value) -> some View {
        modifier(FleetNumericUpdateModifier(value: value, isHeadline: false))
    }

    /// Headline variant using the ambient Reduce Motion setting.
    func fleetHeadlineNumericUpdate<Value: Equatable>(_ value: Value) -> some View {
        modifier(FleetNumericUpdateModifier(value: value, isHeadline: true))
    }
}

/// Where live numeric labels skip the rolling digit animation. Rolling digits are a blurred,
/// CPU-rasterized transition. iOS rolls every label. Native Mac shows many more live labels at
/// once, so it rolls only the headline hashrate numbers and updates secondary labels in place.
/// The system Reduce Motion setting turns all of them off.
enum FleetNumericMotionPolicy {
    static func updatesInPlace(isNativeMac: Bool, isHeadline: Bool = false) -> Bool {
        isNativeMac && !isHeadline
    }

    static func updatesInPlace(isHeadline: Bool) -> Bool {
        #if os(macOS)
        updatesInPlace(isNativeMac: true, isHeadline: isHeadline)
        #else
        updatesInPlace(isNativeMac: false, isHeadline: isHeadline)
        #endif
    }

    static var updatesInPlace: Bool { updatesInPlace(isHeadline: false) }
}

private struct FleetNumericUpdateModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let isHeadline: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let reduceMotion = reduceMotion || FleetNumericMotionPolicy.updatesInPlace(isHeadline: isHeadline)
        return content
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: value)
            .transaction { transaction in
                if reduceMotion { transaction.animation = nil }
            }
    }
}

struct FleetSectionLabel: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .fleetFont(.title3, weight: .semibold)
                .foregroundStyle(FleetTheme.ink)
            if let subtitle {
                Text(subtitle)
                    .fleetFont(.subheadline)
                    .foregroundStyle(FleetTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct FleetStatusBadge: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(title)
                .fleetFont(.caption, weight: .semibold)
        }
        .foregroundStyle(color)
        .fleetPillPadding()
        .background(color.opacity(0.09), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct MinerUptimeLabel: View {
    let reportedSeconds: Int?
    let observedAt: Date?
    let identifier: String
    var color: Color = FleetTheme.secondary

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(Self.humanReadable(seconds: currentSeconds(at: context.date)))
                .fleetFont(.caption2, design: .monospaced)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityIdentifier(identifier)
        }
    }

    private func currentSeconds(at date: Date) -> Int? {
        guard let reportedSeconds, reportedSeconds >= 0 else { return nil }
        let elapsed = observedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0
        return reportedSeconds + Int(elapsed)
    }

    private static func humanReadable(seconds: Int?) -> String {
        guard let seconds, seconds >= 0 else { return "Uptime not reported" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60

        if days > 0 { return "Uptime \(days)d \(hours)h \(minutes)m \(remainder)s" }
        if hours > 0 { return "Uptime \(hours)h \(minutes)m \(remainder)s" }
        if minutes > 0 { return "Uptime \(minutes)m \(remainder)s" }
        return "Uptime \(remainder)s"
    }
}

/// The five known SHA-256 mining coins are bundled into the app's asset catalog.
/// CoinGecko still supplies live ticker and market data, but icon rendering never
/// needs a network request or device-side cache.
enum FleetCoinIconAsset {
    static func name(for coin: MiningPoolCoin) -> String {
        switch coin {
        case .btc: "CoinBitcoin"
        case .bch: "CoinBitcoinCash"
        case .bc2: "CoinBitcoinII"
        case .bch2: "CoinBitcoinCashII"
        case .xec: "CoinECash"
        case .dgb: "CoinDigiByte"
        }
    }
}

/// Uses a checked-in asset for supported coins and keeps the native ticker mark
/// for unknown or unavailable coin identities.
struct CoinGeckoIcon: View {
    let coin: MiningPoolCoin?
    let fallbackTicker: String
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let coin {
                Image(FleetCoinIconAsset.name(for: coin))
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.08)
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        ZStack {
            Circle().fill(fallbackColor)
            Text(fallbackTicker == "BTC" ? "₿" : fallbackTicker)
                .font(.system(size: fallbackTicker == "BTC" ? size * 0.54 : size * 0.30,
                              weight: .bold, design: .rounded))
                .minimumScaleFactor(0.55)
                .foregroundStyle(fallbackTicker == "BTC" || fallbackTicker == "BCH"
                    ? Color.black : FleetTheme.buttonInk)
        }
    }

    private var fallbackColor: Color {
        switch fallbackTicker {
        case "BTC": return Color(red: 0.95, green: 0.48, blue: 0.10)
        case "BCH": return Color(red: 0.18, green: 0.62, blue: 0.36)
        default: return FleetTheme.accent
        }
    }
}

/// Converts a reported web or stratum endpoint into a safe browser destination.
///
/// Stratum is not a web protocol, so stratum endpoints open at the host's HTTPS origin instead of
/// forwarding a mining port or path. Userinfo, query strings and fragments are always discarded.
/// This keeps a tap useful without ever handing a wallet, worker name or password to Safari.
enum FleetBrowserURL {
    private static let acceptedSchemes = Set(["http", "https", "stratum", "stratum+tcp", "stratum+ssl", "tcp", "ssl"])

    static func destination(for raw: String, defaultScheme: String = "https") -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "Not reported" else { return nil }

        let hasExplicitScheme = trimmed.range(of: "^[A-Za-z][A-Za-z0-9+.-]*://", options: .regularExpression) != nil
        let fallbackScheme = defaultScheme.lowercased()
        guard ["http", "https"].contains(fallbackScheme) else { return nil }
        let candidate = hasExplicitScheme ? trimmed : "\(fallbackScheme)://\(trimmed)"
        guard var components = URLComponents(string: candidate),
              let sourceScheme = components.scheme?.lowercased(),
              acceptedSchemes.contains(sourceScheme),
              let host = components.host, !host.isEmpty else {
            return nil
        }

        let isWebEndpoint = sourceScheme == "http" || sourceScheme == "https"
        components.scheme = isWebEndpoint ? sourceScheme : "https"
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil

        // A stratum port is a mining service port, not normally a browser service. Opening the
        // origin avoids a misleading blank page while retaining an explicit HTTP(S) port for real
        // web endpoints such as a local miner dashboard.
        if !isWebEndpoint {
            components.port = nil
            components.path = ""
        }

        guard let destination = components.url, destination.host != nil else { return nil }
        return destination
    }
}

/// A small shared link presentation for reported endpoints. Invalid or intentionally omitted
/// values remain plain text rather than becoming a dead or unsafe control.
struct BrowserLink: View {
    let label: String
    let rawValue: String
    let identifier: String?
    let font: Font
    let defaultScheme: String
    let alignment: Alignment

    init(
        label: String,
        rawValue: String,
        identifier: String? = nil,
        font: Font = .caption,
        defaultScheme: String = "https",
        alignment: Alignment = .leading
    ) {
        self.label = label
        self.rawValue = rawValue
        self.identifier = identifier
        self.font = font
        self.defaultScheme = defaultScheme
        self.alignment = alignment
    }

    var body: some View {
        if let destination = FleetBrowserURL.destination(for: rawValue, defaultScheme: defaultScheme) {
            Link(destination: destination) {
                labelView
            }
            .accessibilityHint("Opens this site in your browser")
            .accessibilityIdentifier(identifier ?? "")
        } else {
            labelView
                .textSelection(.enabled)
                .accessibilityIdentifier(identifier ?? "")
        }
    }

    private var labelView: some View {
        HStack(spacing: 5) {
            Text(label)
                .lineLimit(1)
                .truncationMode(.middle)
            if FleetBrowserURL.destination(for: rawValue, defaultScheme: defaultScheme) != nil {
                Image(systemName: "arrow.up.right")
                    .fleetFont(.caption2, weight: .semibold)
                    .accessibilityHidden(true)
            }
        }
        .font(font)
        .foregroundStyle(FleetTheme.accent)
        .frame(maxWidth: .infinity, alignment: alignment)
        .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
        .contentShape(Rectangle())
        .accessibilityLabel(label)
    }
}
