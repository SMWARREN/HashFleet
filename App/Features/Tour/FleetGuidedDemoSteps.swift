import Foundation

/// Every lesson refers to a control or reading rendered by a production screen, not a mock screenshot.
struct FleetGuidedDemoStep: Identifiable, Sendable {
    enum Screen: String, Sendable { case fleet, miner, coins, settings, preferences, energy, report, pdf, notifications }
    let id: String
    let screen: Screen
    let target: String
    let title: String
    let instruction: String
    let tapTitle: String?

    static let all: [Self] = [
        .init(id: "overview", screen: .fleet, target: "guide.hero", title: "Meet your fleet",
            instruction: "These are sample miners. The highlighted card adds up their hashrate and power, "
                + "so it's the quickest place to check your fleet's health. Tap Next when you're ready.",
            tapTitle: nil),
        .init(id: "history", screen: .fleet, target: "guide.history", title: "View hashrate over time",
            instruction: "Swipe left or right on the history chart to see daily, weekly, monthly, "
                + "or yearly hashrate trends. Each time period helps you spot different patterns.",
            tapTitle: nil),
        .init(id: "openMiner", screen: .fleet, target: "guide.miner", title: "Open a miner",
            instruction: "Tap the highlighted miner card to see its own readings. "
                + "The hand points to the same kind of card you'd tap in your real fleet.",
            tapTitle: "Open the sample miner"),
        .init(id: "cooling", screen: .miner, target: "guide.cooling", title: "Check temperature and cooling",
            instruction: "Here you can see the sample miner's chip temperature and fan speed and RPM. "
                + "This is the place to check cooling before you change any settings.",
            tapTitle: nil),
        .init(id: "openCoins", screen: .fleet, target: "guide.coinSelection", title: "Choose what the dashboard shows",
            instruction: "Back on Fleet, tap Coins to show. "
                + "This only changes what's on screen, not which coins a miner actually mines.",
            tapTitle: "Open Coins to show"),
        .init(id: "chooseDGB", screen: .coins, target: "guide.coin.DGB", title: "Try a display choice",
            instruction: "We've set this practice fleet to Custom. Tap the highlighted DGB switch to add DigiByte "
                + "to its dashboard. Nothing changes outside this demo.",
            tapTitle: "Turn on DigiByte in the demo"),
        .init(id: "coinResult", screen: .fleet, target: "guide.chain.DGB",
            title: "See your choice take effect",
            instruction: "DGB now shows up once on the dashboard. These numbers come from public sample data, "
                + "and picking a coin here never changes which pool a miner uses.",
            tapTitle: nil),
        .init(id: "openPreferences", screen: .settings, target: "guide.preferencesEntry",
            title: "Find display settings",
            instruction: "In Settings, tap Preferences to find appearance and sorting controls. "
                + "This is where you switch between light and dark mode.",
            tapTitle: "Open Preferences"),
        .init(id: "appearance", screen: .preferences, target: "guide.appearance", title: "Choose your appearance",
            instruction: "The highlighted Appearance control lets you pick Light, Dark, or System mode. "
                + "Your choice applies across the whole app and is saved for next launch.",
            tapTitle: nil),
        .init(id: "openEnergy", screen: .settings, target: "guide.energyEntry",
            title: "Find your fleet tools",
            instruction: "Back in Settings, tap Electricity estimates to see the running-cost tool.",
            tapTitle: "Open Electricity estimates"),
        .init(id: "energy", screen: .energy, target: "guide.dailyCost", title: "Understand the estimate",
            instruction: "This sample uses 0.15 USD per kWh. The highlighted daily cost assumes power use "
                + "stays where it is right now. It's an estimate, not an actual bill.",
            tapTitle: nil),
        .init(id: "openReports", screen: .settings, target: "guide.reportEntry", title: "Find snapshot reports",
            instruction: "Back in Settings, tap Fleet reports. Reports are built from readings already in the app, "
                + "so they never contact your miners.",
            tapTitle: "Open Fleet reports"),
        .init(id: "previewReport", screen: .report, target: "guide.previewPDF", title: "Preview before you share",
            instruction: "Tap Preview PDF and we'll render a real PDF from this sample fleet. "
                + "The tour never opens a share sheet or sends a file anywhere.",
            tapTitle: "Preview the sample fleet PDF"),
        .init(id: "pdf", screen: .pdf, target: "guide.pdf", title: "Here's the actual report",
            instruction: "This PDF only contains anonymous sample readings. In your real fleet, sharing a PDF "
                + "or CSV is always a separate step that you choose.",
            tapTitle: nil),
        .init(id: "openAlerts", screen: .settings, target: "guide.notificationsEntry",
            title: "Set up alerts from Settings",
            instruction: "Expand Notifications and banners here in App settings to find block-found and best-share alerts. The demo won't ask for "
                + "permission, send alerts, or change any of your real choices.",
            tapTitle: "Expand Notifications and banners"),
        .init(id: "alerts", screen: .notifications, target: "guide.notificationTest",
            title: "Know where to test delivery",
            instruction: "These are the real inline notification controls in App settings, and the highlighted test button is there for you "
                + "once the tour is over. System permission and background timing can affect delivery.",
            tapTitle: nil),
        .init(id: "complete", screen: .fleet, target: "guide.hero",
            title: "Ready for your own fleet",
            instruction: "You've practiced viewing history trends, changing appearance, opening a miner, "
                + "picking coins, checking costs, previewing a report, and finding alerts. Tap Done and you'll "
                + "land right back on the fleet you left.",
            tapTitle: nil)
    ]
}
