import HashFleetCore
import Foundation

/// Shared text for the read-only dashboard page and the standalone command.
enum CLISupportContent {
    static var lines: [String] {
        var lines = [DeveloperSupport.explanation, "", "PAYPAL"]
        if let url = DeveloperSupport.current.paypalURL {
            lines += ["Open this PayPal checkout yourself to choose an amount:", url.absoluteString]
        } else {
            lines.append("PayPal checkout is not configured in this build.")
        }
        lines += ["", "CRYPTO"]
        let destinations = DeveloperSupport.current.cryptoDestinations(
            storefrontCountryCode: nil, directDistribution: true
        )
        for destination in destinations {
            lines += [
                "\(destination.name) (\(destination.rawValue))",
                "Network: \(destination.network)",
                "Address:", destination.address, ""
            ]
        }
        lines += [DeveloperSupport.cryptoNotice, "", "Support destinations are real, including in demo mode.",
                  "This page does not open a browser or wallet, copy to the clipboard, or send a payment."]
        return lines
    }
}

@MainActor
final class CLISupportScreen {
    private var offset = 0
    private var maximumOffset = 0
    private(set) var closed = false
    private(set) var quit = false

    /// A transition discards buffered input instead of forwarding it to the dashboard.
    func handle(_ event: TerminalKey) -> Bool {
        switch event {
        case .escape, .byte(83), .byte(98):
            closed = true
            return true
        case .byte(3), .byte(4), .byte(113), .byte(81):
            quit = true
            return true
        case .up, .byte(107): offset = max(0, offset - 1)
        case .down, .byte(106): offset = min(maximumOffset, offset + 1)
        case .byte(103): offset = 0
        case .byte(71): offset = maximumOffset
        default: break
        }
        return false
    }

    func render(width: Int, height: Int, palette: DashboardPalette) -> String {
        var lines = [DashboardLine(" HASH FLEET / SUPPORT", style: palette.title)]
        guard width >= 24, height >= 8 else {
            let controls = width >= 20 ? " S/Esc back | q quit" : " Esc | q quit"
            lines += [DashboardLine(" Resize to 25x8."), DashboardLine(controls)]
            return frame(lines, width: width, height: height)
        }
        lines += [DashboardLine(" No payment is sent here.", style: palette.secondary),
                  DashboardLine(String(repeating: "─", count: width), style: palette.secondary)]
        let body = CLISupportContent.lines.flatMap { text -> [DashboardLine] in
            guard !text.isEmpty else { return [DashboardLine()] }
            let style = ["PAYPAL", "CRYPTO"].contains(text) ? palette.title : ""
            return TerminalText.wrapped(text, width: width - 2).map { DashboardLine(" " + $0, style: style) }
        }
        let available = height - 6
        maximumOffset = max(0, body.count - available)
        offset = min(offset, maximumOffset)
        lines += body.dropFirst(offset).prefix(available)
        while lines.count < height - 3 { lines.append(DashboardLine()) }
        lines.append(DashboardLine(" Lines \(offset + 1)-\(min(body.count, offset + available))/\(body.count)", style: palette.secondary))
        lines.append(DashboardLine(String(repeating: "─", count: width), style: palette.secondary))
        let controls = width >= 48 ? " jk/arrows scroll | S/b/Esc back | q quit"
            : width >= 30 ? " jk scroll | Esc back | q quit" : " jk | Esc back | q quit"
        lines.append(DashboardLine(controls, style: palette.secondary))
        return frame(lines, width: width, height: height)
    }

    private func frame(_ lines: [DashboardLine], width: Int, height: Int) -> String {
        "\u{1B}[H" + lines.prefix(height).map { $0.render(width: width) }.joined(separator: "\r\n") + "\u{1B}[J"
    }
}
