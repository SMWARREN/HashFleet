import SwiftUI

extension DashboardView {
    /// iPhone and iPad shortcut grid. Built as its own `View` type: when it was an inline
    /// `some View` property, the nested generic type of five modified buttons was resolved from
    /// its mangled name inside the dashboard's already deep body call, which overflowed the
    /// main-thread stack on launch in Debug phone builds once miners were saved
    /// (EXC_BAD_ACCESS in `swift_getTypeByMangledName`, 2026-11-07).
    var fleetToolsSection: some View {
        FleetToolsSection(
            compact: usesCompactHorizontalLayout,
            onRoute: { routeToDashboardPage($0) },
            onTour: { showingFeatureTour = true }
        )
    }
}

struct FleetToolsSection: View {
    let compact: Bool
    let onRoute: (DashboardPageDestination) -> Void
    let onTour: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    struct Tool: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let symbol: String
        let tint: FleetSidebarTileTint
        let destination: DashboardPageDestination
    }

    static let tools: [Tool] = [
        Tool(id: "network", title: "Network insights", subtitle: "Public network and pool data",
             symbol: "point.3.connected.trianglepath.dotted", tint: .blue, destination: .network),
        Tool(id: "energy", title: "Energy", subtitle: "Power and cost", symbol: "bolt.fill", tint: .yellow,
             destination: .energy),
        Tool(id: "achievements", title: "Achievements", subtitle: "Records and milestones",
             symbol: "trophy.fill", tint: .orange, destination: .achievements),
        Tool(id: "reports", title: "Reports", subtitle: "Share fleet status", symbol: "doc.text.fill", tint: .green,
             destination: .reports),
        Tool(id: "backup", title: "Backup", subtitle: "Export and restore", symbol: "arrow.triangle.2.circlepath",
             tint: .teal, destination: .backup)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Fleet tools")
                    .fleetFont(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("Network insights, reports, and backup are always within reach.")
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Self.tools) { tool in
                    FleetToolButton(tool: tool) { onRoute(tool.destination) }
                        .accessibilityIdentifier("dashboard.tools.\(tool.id)")
                }
            }
            Button(action: onTour) {
                Label("Show me around", systemImage: "sparkles")
                    .fleetFont(.subheadline, weight: .semibold)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("dashboard.tools.featureTour")
        }
        .fleetCard(padding: FleetSurfaceSpacing.cardInset, fill: FleetTheme.surface)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.fleetTools")
    }

    private var columns: [GridItem] {
        compact
            ? [GridItem(.flexible(), spacing: 10)]
            : [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 220 : 145), spacing: 10)]
    }
}

private struct FleetToolButton: View {
    let tool: FleetToolsSection.Tool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tool.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(tool.tint.color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.title)
                        .fleetFont(.subheadline, weight: .semibold)
                        .foregroundStyle(FleetTheme.ink)
                    Text(tool.subtitle)
                        .fleetFont(.caption2)
                        .foregroundStyle(FleetTheme.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .fleetFont(.caption, weight: .bold)
                    .foregroundStyle(FleetTheme.secondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.horizontal, 12)
            .background(FleetTheme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fleetPointerHover()
        .accessibilityLabel(tool.title)
        .accessibilityHint(tool.subtitle)
    }
}
