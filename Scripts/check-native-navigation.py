#!/usr/bin/env python3
"""Check native navigation's production integration, without launching an app.

Pixel/hosting checks live in check-native-chrome.swift. These checks cover the
call-site seams that a generic rounded control or copied title fixture cannot.
They are not a replacement for actual-window visual approval.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]


def check_dashboard(root: Path) -> list[str]:
    errors: list[str] = []
    wide = (root / "App/Features/Dashboard/DashboardView+WideLayout.swift").read_text()
    sidebar = wide.split("struct FleetSidebarView: View {", 1)[1].split(
        "private var minerSectionHeading:", 1
    )[0]
    if ".fleetMacSidebarSurface(fill: FleetTheme.sidebarSurface)" not in sidebar:
        errors.append("The actual Fleet sidebar must clip its whole list/footer with the rounded native surface")

    dashboard = (root / "App/Features/Dashboard/DashboardView.swift").read_text()
    toolbar = dashboard.split("private var dashboardToolbar:", 1)[1].split(
        "private var settingsToolbarIcon:", 1
    )[0]
    if re.search(r"\.fleetDesignedMenu\(\)\s*\.fleetToolbarMenu\(\)", toolbar):
        errors.append("The real settings Menu must not override its toolbar style with an inner plain style")
    if "FleetHeaderTitle()" not in toolbar:
        errors.append("The iPad dashboard must use the same actual header title view as the Mac")
    if "FleetMacToolbarBrand()" not in toolbar or "placement: .principal" not in toolbar:
        errors.append("The Mac dashboard must keep its standalone brand in the principal title/search slot")
    return errors


def check_branding(root: Path) -> list[str]:
    errors: list[str] = []
    branding = (root / "App/Design/FleetDesktopBranding.swift").read_text()
    if not re.search(r"ToolbarItem\(placement: \.principal\)\s*\{\s*FleetMacToolbarBrand\(\)", branding):
        errors.append("Native page branding must use the principal title slot, not an inline logo/title group")
    if "FleetHeaderArtwork()" not in branding:
        errors.append("Native artwork must remain separate from the centered title")
    if "includesPrincipalBrand" not in branding:
        errors.append("Dashboard search must own one principal item, not compete with a second brand item")

    title_path = root / "App/Design/FleetHeaderTitle.swift"
    if not title_path.exists():
        errors.append("Missing shared original iPad header-title view")
        return errors
    title = title_path.read_text()
    errors.extend(
        f"Shared wordmark lost its original iPad title contract: {token}"
        for token in ['Text("Hash Fleet")', ".fleetFont(.headline)", ".lineLimit(1)",
                      ".dynamicTypeSize(...DynamicTypeSize.xxxLarge)"]
        if token not in title
    )
    if "design: .rounded" in title or ".font(.system(size:" in title:
        errors.append("Do not substitute a new typeface or Mac-only point size for the original iPad wordmark")
    return errors


def check_miner_detail(root: Path) -> list[str]:
    errors: list[str] = []
    detail = (root / "App/Features/Miner/MinerDetailView.swift").read_text()
    actions = (root / "App/Features/Miner/MinerDetailView+QuickActions.swift").read_text()
    if "NavigationLink(value: endpoint)" not in actions:
        errors.append("Measured miner action cards must navigate by value, not build review destinations inside their labels")
    if ".navigationDestination(for: MinerEndpoint.self)" not in detail:
        errors.append("The miner workspace must register its endpoint review destination outside the measured action grid")
    return errors


def check(root: Path = ROOT) -> list[str]:
    return check_dashboard(root) + check_branding(root) + check_miner_detail(root)


if __name__ == "__main__":
    errors = check()
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        raise SystemExit(1)
    print("Native navigation integration guard passed. Live window/menu acceptance remains separate.")
