import SwiftUI

/// Native animated illustrations that replace the flat Energy, Network, Report and Block art.
/// Each one draws with Canvas on a `TimelineView` so it stays sharp at any size and costs no asset
/// bytes. With Reduce Motion the same drawing renders once at a representative, fully-drawn frame.
/// Every illustration is decorative and hidden from VoiceOver; the surrounding copy carries meaning.
private let illustrationAmber = Color(red: 245 / 255, green: 172 / 255, blue: 38 / 255)

/// Shared driver: provides elapsed seconds, or a fixed time under Reduce Motion.
private struct IllustrationClock<Content: View>: View {
    var stillTime: Double
    @ViewBuilder var content: (Double) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        if reduceMotion {
            content(stillTime)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                content(context.date.timeIntervalSince(start))
            }
        }
    }
}

/// Lightning bolt that charges up inside a rotating dashed ring, with sparks orbiting.
struct FleetEnergyIllustration: View {
    var size: CGFloat = 96

    var body: some View {
        IllustrationClock(stillTime: 0.9) { t in
            Canvas { ctx, canvas in
                let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
                let r = min(canvas.width, canvas.height) * 0.42
                var ring = Path()
                ring.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                ctx.stroke(ring, with: .color(illustrationAmber.opacity(0.28)),
                           style: StrokeStyle(lineWidth: max(1.5, r * 0.035), dash: [r * 0.09, r * 0.07],
                                              dashPhase: CGFloat(t * 18)))
                let pulse = 0.5 - 0.5 * cos(t * 2 * .pi / 1.6)
                let glowR = r * (0.55 + 0.18 * pulse)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - glowR, y: c.y - glowR, width: glowR * 2, height: glowR * 2)),
                         with: .radialGradient(Gradient(colors: [illustrationAmber.opacity(0.35 * pulse + 0.1), .clear]),
                                               center: c, startRadius: 0, endRadius: glowR))
                let s = r / 180
                var bolt = Path()
                let pts: [(CGFloat, CGFloat)] = [(282, 104), (175, 274), (246, 274), (230, 408), (338, 224), (266, 224)]
                for (i, p) in pts.enumerated() {
                    let pt = CGPoint(x: c.x + (p.0 - 256) * s, y: c.y + (p.1 - 256) * s)
                    if i == 0 { bolt.move(to: pt) } else { bolt.addLine(to: pt) }
                }
                bolt.closeSubpath()
                var boltCtx = ctx
                boltCtx.addFilter(.shadow(color: illustrationAmber.opacity(0.4 + 0.5 * pulse), radius: 6 + 8 * pulse))
                boltCtx.fill(bolt, with: .color(illustrationAmber))
                for i in 0..<3 {
                    let a = t * 1.4 + Double(i) * 2 * .pi / 3
                    let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                    let d = max(3, r * 0.07)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)),
                             with: .color(illustrationAmber.opacity(0.9)))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Miner nodes on a local network with data packets travelling between them.
struct FleetNetworkIllustration: View {
    var width: CGFloat = 220

    private static let nodes: [CGPoint] = [
        CGPoint(x: 150, y: 350), CGPoint(x: 340, y: 190), CGPoint(x: 535, y: 310),
        CGPoint(x: 730, y: 130), CGPoint(x: 900, y: 250)
    ]
    private static let hub = CGPoint(x: 450, y: 400)
    private static let links: [(Int, Int)] = [(0, 1), (1, 2), (2, 3), (3, 4)]

    var body: some View {
        IllustrationClock(stillTime: 0.7) { t in
            Canvas { ctx, canvas in
                let sx = canvas.width / 1024, sy = canvas.height / 512
                func map(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * sx, y: p.y * sy) }
                var edges: [(CGPoint, CGPoint)] = Self.links.map { (map(Self.nodes[$0.0]), map(Self.nodes[$0.1])) }
                edges += Self.nodes.map { (map($0), map(Self.hub)) }
                for (a, b) in edges {
                    var p = Path(); p.move(to: a); p.addLine(to: b)
                    ctx.stroke(p, with: .color(illustrationAmber.opacity(0.28)), lineWidth: 1.2)
                }
                for (i, edge) in edges.enumerated() {
                    let phase = (t * 0.55 + Double(i) * 0.23).truncatingRemainder(dividingBy: 1)
                    let pt = CGPoint(x: edge.0.x + (edge.1.x - edge.0.x) * phase,
                                     y: edge.0.y + (edge.1.y - edge.0.y) * phase)
                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4)),
                             with: .color(illustrationAmber.opacity(sin(phase * .pi))))
                }
                for (i, node) in Self.nodes.enumerated() {
                    let p = map(node)
                    let ping = (t * 0.6 + Double(i) * 0.2).truncatingRemainder(dividingBy: 1)
                    let pr = 10 + 22 * ping
                    ctx.stroke(Path(ellipseIn: CGRect(x: p.x - pr, y: p.y - pr, width: pr * 2, height: pr * 2)),
                               with: .color(illustrationAmber.opacity(0.5 * (1 - ping))), lineWidth: 1.5)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18)),
                             with: .color(illustrationAmber.opacity(0.45)))
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)),
                             with: .color(illustrationAmber))
                }
            }
        }
        .frame(width: width, height: width / 2)
        .accessibilityHidden(true)
    }
}

/// Report card whose hashrate line draws itself, then the end point pulses.
struct FleetReportIllustration: View {
    var width: CGFloat = 200

    var body: some View {
        IllustrationClock(stillTime: 3.0) { t in
            Canvas { ctx, canvas in
                let sx = canvas.width / 640, sy = canvas.height / 420
                let card = CGRect(x: 76 * sx, y: 55 * sy, width: 420 * sx, height: 270 * sy)
                ctx.fill(Path(roundedRect: card.offsetBy(dx: 28 * sx, dy: 30 * sy), cornerRadius: 26 * sx),
                         with: .color(.gray.opacity(0.35)))
                ctx.fill(Path(roundedRect: card, cornerRadius: 26 * sx), with: .color(.black))
                ctx.stroke(Path(roundedRect: card, cornerRadius: 26 * sx),
                           with: .color(illustrationAmber.opacity(0.7)), lineWidth: 1.5)
                let grow = min(1, t / 0.6)
                ctx.fill(Path(roundedRect: CGRect(x: 124 * sx, y: 108 * sy, width: 170 * sx * grow, height: 12 * sy),
                              cornerRadius: 6 * sy), with: .color(illustrationAmber))
                ctx.fill(Path(roundedRect: CGRect(x: 124 * sx, y: 136 * sy, width: 110 * sx * grow, height: 9 * sy),
                              cornerRadius: 4.5 * sy), with: .color(.gray))
                let side = CGRect(x: 515 * sx, y: 115 * sy, width: 52 * sx, height: 220 * sy)
                ctx.fill(Path(roundedRect: side, cornerRadius: 16 * sx), with: .color(Color(white: 0.1)))
                let level = 0.55 + 0.4 * (0.5 - 0.5 * cos(t * 2 * .pi / 2.4))
                let fillH = 120 * sy * level
                ctx.fill(Path(roundedRect: CGRect(x: 530 * sx, y: 265 * sy - fillH, width: 22 * sx, height: fillH),
                              cornerRadius: 11 * sx), with: .color(illustrationAmber.opacity(0.8)))
                let cycle = t.truncatingRemainder(dividingBy: 5)
                let progress = min(1, max(0, (cycle - 0.3) / 1.6))
                var chart = Path()
                chart.move(to: CGPoint(x: 124 * sx, y: 253 * sy))
                chart.addCurve(to: CGPoint(x: 250 * sx, y: 170 * sy),
                               control1: CGPoint(x: 170 * sx, y: 200 * sy), control2: CGPoint(x: 215 * sx, y: 215 * sy))
                chart.addCurve(to: CGPoint(x: 330 * sx, y: 150 * sy),
                               control1: CGPoint(x: 285 * sx, y: 125 * sy), control2: CGPoint(x: 300 * sx, y: 190 * sy))
                chart.addCurve(to: CGPoint(x: 404 * sx, y: 107 * sy),
                               control1: CGPoint(x: 360 * sx, y: 110 * sy), control2: CGPoint(x: 390 * sx, y: 140 * sy))
                ctx.stroke(chart.trimmedPath(from: 0, to: progress),
                           with: .linearGradient(Gradient(colors: [illustrationAmber.opacity(0.3), illustrationAmber]),
                                                 startPoint: CGPoint(x: 124 * sx, y: 0), endPoint: CGPoint(x: 404 * sx, y: 0)),
                           style: StrokeStyle(lineWidth: 12 * sy, lineCap: .round, lineJoin: .round))
                if progress >= 1 {
                    let pulse = 0.5 - 0.5 * cos((cycle - 1.9) * 2 * .pi / 1.2)
                    let end = CGPoint(x: 404 * sx, y: 107 * sy)
                    let pr = (10 + 10 * pulse) * sx
                    ctx.fill(Path(ellipseIn: CGRect(x: end.x - pr, y: end.y - pr, width: pr * 2, height: pr * 2)),
                             with: .color(illustrationAmber.opacity(0.35 * (1 - pulse))))
                    ctx.fill(Path(ellipseIn: CGRect(x: end.x - 10 * sx, y: end.y - 10 * sx, width: 20 * sx, height: 20 * sx)),
                             with: .color(illustrationAmber))
                }
            }
        }
        .frame(width: width, height: width * 420 / 640)
        .accessibilityHidden(true)
    }
}
