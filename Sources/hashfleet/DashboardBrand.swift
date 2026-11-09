import Foundation
import Darwin

/// Render the original logo as colored cells, using two image pixels per ▀ glyph.
/// Monochrome terminals receive an ASCII conversion of the same image.
enum DashboardBrand {
    struct HeaderContent {
        let mode: String
        let state: String
        let paused: Bool
    }

    static func header(width: Int, height: Int, content: HeaderContent,
                       palette: DashboardPalette, logoHint: String? = "l  view logo") -> [DashboardLine] {
        let (mode, state, paused) = (content.mode, content.state, content.paused)
        let gold = palette.gold
        let secondary = palette.secondary
        let status = paused ? palette.warning : secondary
        if width >= 64 && height >= 28 {
            let pixels = height >= 36 && width >= 80 ? DashboardLogo.large
                : height >= 31 && width >= 72 ? DashboardLogo.medium : DashboardLogo.small
            return artwork(pixels, palette: palette).enumerated().map { index, art in
                let right: DashboardLine.Run
                switch index {
                case 1: right = ("HASH FLEET", palette.title)
                case 3: right = ("Your hash. Your hardware.", secondary)
                case 5: right = (mode, gold)
                case 7: right = (state, status)
                case 9: right = (logoHint ?? "", secondary)
                default: right = ("", "")
                }
                return DashboardLine(runs: [(" ", "")] + art.runs + [("    ", ""), right])
            }
        }
        return [
            DashboardLine(runs: [(" HASH FLEET", palette.title), ("  /  \(mode)", gold)]),
            DashboardLine(runs: [(" \(state)", status)])
        ]
    }

    static func statusHeader(width: Int, state: String, palette: DashboardPalette) -> [DashboardLine] {
        // A snapshot scrolls normally, so shallow panes can still show the real artwork.
        let heading = header(width: width, height: 28,
                             content: HeaderContent(mode: "STATUS", state: state, paused: false),
                             palette: palette, logoHint: nil)
        guard width < 64, width >= 22 else { return heading }
        return artwork(DashboardLogo.small, palette: palette) + heading
    }

    static func preview(width: Int, height: Int, palette: DashboardPalette) -> [DashboardLine] {
        var lines = [DashboardLine(" HASH FLEET / LOGO", style: palette.title)]
        if height >= 16 && width >= 24 {
            let pixels = height >= 24 && width >= 36 ? DashboardLogo.large
                : height >= 19 && width >= 28 ? DashboardLogo.medium : DashboardLogo.small
            let inset = String(repeating: " ", count: max(0, (width - pixels[0].count) / 2))
            lines += artwork(pixels, palette: palette).map { DashboardLine(runs: [(inset, "")] + $0.runs) }
        } else {
            lines.append(DashboardLine(" Enlarge the terminal to view the artwork."))
        }
        while lines.count < height - 2 { lines.append(DashboardLine()) }
        lines.append(DashboardLine(" Your hash. Your hardware.", style: palette.secondary))
        let controls = width >= 42 ? " l return to fleet · S support · q quit"
            : width >= 30 ? " l back · S support · q quit" : " l back · S · q quit"
        lines.append(DashboardLine(controls, style: palette.secondary))
        return lines
    }

    private static func artwork(_ pixels: [[Int]], palette: DashboardPalette) -> [DashboardLine] {
        let ramp = Array(" .:-=+*#%@")
        return stride(from: 0, to: pixels.count, by: 2).map { y in
            var runs: [DashboardLine.Run] = []
            for x in pixels[y].indices {
                let topIndex = pixels[y][x], bottomIndex = pixels[y + 1][x]
                let top = topIndex < 0 ? nil : DashboardLogo.colors[topIndex]
                let bottom = bottomIndex < 0 ? nil : DashboardLogo.colors[bottomIndex]
                let text: String
                let style: String
                if palette.hasColor {
                    switch (top, bottom) {
                    case let (top?, bottom?):
                        text = "▀"
                        style = palette.pixelStyle(top: top, bottom: bottom)
                    case let (top?, nil):
                        text = "▀"
                        style = palette.pixelStyle(top: top, bottom: nil)
                    case let (nil, bottom?):
                        text = "▄"
                        style = palette.pixelStyle(top: bottom, bottom: nil)
                    case (nil, nil):
                        text = " "
                        style = ""
                    }
                } else {
                    func luminance(_ rgb: UInt32) -> Double {
                        0.2126 * Double((rgb >> 16) & 255) + 0.7152 * Double((rgb >> 8) & 255) + 0.0722 * Double(rgb & 255)
                    }
                    let light = (luminance(top ?? 0) + luminance(bottom ?? 0)) / 510
                    text = String(ramp[min(9, Int(pow(light, 0.65) * 9))])
                    style = ""
                }
                if runs.last?.style == style { runs[runs.count - 1].text += text } else { runs.append((text, style)) }
            }
            // Never extend the last pixel's background across the rest of the terminal row.
            runs.append((" ", ""))
            return DashboardLine(runs: runs)
        }
    }

    /// Normal scrollback output lets the full artwork be seen even in a shallow split pane.
    static func printLogo() {
        setlocale(LC_CTYPE, "")
        let terminal = TerminalSession.hasTerminalOutput
        let width = terminal ? max(1, TerminalSession.outputSize.columns - 1) : 100
        let palette = DashboardPalette(environment: terminal ? ProcessInfo.processInfo.environment : ["NO_COLOR": "1"])
        print(DashboardLine("HASH FLEET", style: palette.title).render(width: width, fillRow: false))
        guard width >= 21 else {
            print(DashboardLine("Enlarge the terminal.", style: palette.secondary).render(width: width, fillRow: false))
            return
        }
        let pixels = width >= 33 ? DashboardLogo.large : width >= 25 ? DashboardLogo.medium : DashboardLogo.small
        let rows = artwork(pixels, palette: palette)
        for row in rows { print(row.render(width: width, fillRow: false)) }
    }
}

struct DashboardPalette {
    private enum ColorDepth { case none, basic, indexed, rgb }
    private let depth: ColorDepth
    var hasColor: Bool { depth != .none }
    let title: String
    let gold: String
    let secondary: String
    let good: String
    let warning: String
    let offline: String
    let selection: String
    let value: String
    let chart: String

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard environment["NO_COLOR"] == nil else {
            depth = .none
            title = ""; gold = ""; secondary = ""; good = ""
            warning = ""; offline = ""; selection = ""
            value = ""; chart = ""
            return
        }
        let term = environment["TERM", default: ""]
        let trueColor = ["truecolor", "24bit"].contains(environment["COLORTERM", default: ""].lowercased())
            || term.contains("direct")
        let extended = term.contains("256color")
        depth = trueColor ? .rgb : extended ? .indexed : .basic
        func foreground(_ rgb: String, _ indexed: Int, _ basic: Int) -> String {
            "\u{1B}[\(trueColor ? "38;2;" + rgb : extended ? "38;5;\(indexed)" : "\(basic)")m"
        }
        // #F5AC26 matches the current native app accent. Status hues are semantic.
        gold = foreground("245;172;38", 214, 33)
        title = "\u{1B}[1m" + gold
        secondary = "\u{1B}[2m"
        good = foreground("87;190;133", 78, 32)
        warning = foreground("242;193;102", 221, 33)
        offline = foreground("242;119;119", 210, 31)
        value = "\u{1B}[1m"
        chart = foreground("122;182;236", 111, 36)
        selection = trueColor ? "\u{1B}[1;38;2;255;207;117;48;2;46;37;23m"
            : extended ? "\u{1B}[1;38;5;222;48;5;235m" : "\u{1B}[1;33;40m"
    }

    func pixelStyle(top: UInt32, bottom: UInt32?) -> String {
        func component(_ rgb: UInt32, background: Bool) -> String {
            let r = Int((rgb >> 16) & 255), g = Int((rgb >> 8) & 255), b = Int(rgb & 255)
            switch depth {
            case .none: return ""
            case .rgb: return "\(background ? 48 : 38);2;\(r);\(g);\(b)"
            case .indexed:
                let levels = [0, 95, 135, 175, 215, 255]
                func nearest(_ value: Int) -> Int { levels.indices.min { abs(levels[$0] - value) < abs(levels[$1] - value) }! }
                let ri = nearest(r), gi = nearest(g), bi = nearest(b)
                let gray = min(23, max(0, (r + g + b) / 30 - 1))
                let grayValue = 8 + gray * 10
                func distance(_ a: Int, _ c: Int, _ d: Int) -> Int {
                    (r - a) * (r - a) + (g - c) * (g - c) + (b - d) * (b - d)
                }
                let index = distance(grayValue, grayValue, grayValue) < distance(levels[ri], levels[gi], levels[bi])
                    ? 232 + gray : 16 + 36 * ri + 6 * gi + bi
                return "\(background ? 48 : 38);5;\(index)"
            case .basic:
                // A portable 16-color approximation; exact hues belong to the terminal theme.
                let colors: [(Int, Int, Int)] = [(0, 0, 0), (128, 0, 0), (0, 128, 0), (128, 128, 0),
                    (0, 0, 128), (128, 0, 128), (0, 128, 128), (192, 192, 192), (128, 128, 128),
                    (255, 0, 0), (0, 255, 0), (255, 255, 0), (0, 0, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255)]
                func distance(_ index: Int) -> Int {
                    let (a, c, d) = colors[index]
                    return (r - a) * (r - a) + (g - c) * (g - c) + (b - d) * (b - d)
                }
                let index = colors.indices.min { distance($0) < distance($1) }!
                return "\((index < 8 ? 30 : 90) + index % 8 + (background ? 10 : 0))"
            }
        }
        let background = bottom.map { component($0, background: true) } ?? "49"
        return "\u{1B}[\(component(top, background: false));\(background)m"
    }
}

/// Keep trusted ANSI styling separate from firmware text, including inside mixed-color rows.
struct DashboardLine {
    typealias Run = (text: String, style: String)
    var runs: [Run]

    init(_ text: String = "", style: String = "") { runs = [(text, style)] }
    init(runs: [Run]) { self.runs = runs }

    func render(width: Int, fillRow: Bool = true) -> String {
        var output = ""
        var remaining = width
        var lastStyle = ""
        for run in runs where remaining > 0 {
            let safe = TerminalText.safe(run.text)
            let length = safe.reduce(0) { $0 + TerminalText.width($1) }
            let columns = min(remaining, length)
            output += run.style + TerminalText.fit(safe, columns)
                + (fillRow || !run.style.isEmpty ? "\u{1B}[0m" : "")
            remaining -= columns
            lastStyle = run.style
        }
        return fillRow ? output + lastStyle + String(repeating: " ", count: remaining) + "\u{1B}[0m\u{1B}[K" : output
    }
}
