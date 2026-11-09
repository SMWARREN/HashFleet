#if canImport(UIKit)
import UIKit
#else
import AppKit
import CoreText
#endif

/// Native, paginated PDF output. The semantic preview and both exports share one frozen DTO.
@MainActor
enum FleetReportPDF {
    static func render(_ report: FleetReportSnapshot) -> Data {
#if canImport(UIKit)
        renderUIKit(report)
#else
        renderAppKit(report)
#endif
    }

#if canImport(UIKit)
    private static func renderUIKit(_ report: FleetReportSnapshot) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "Hash Fleet snapshot report",
            kCGPDFContextCreator as String: "Hash Fleet"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)
        return renderer.pdfData { context in
            var y: CGFloat = 0
            var page = 0
            let width: CGFloat = 532
            let bottom: CGFloat = 738

            func attributes(size: CGFloat, bold: Bool = false) -> [NSAttributedString.Key: Any] {
                [
                    .font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size),
                    .foregroundColor: UIColor.black
                ]
            }

            func height(_ text: String, size: CGFloat, bold: Bool = false) -> CGFloat {
                ceil((text as NSString).boundingRect(
                    with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes(size: size, bold: bold), context: nil
                ).height) + 6
            }

            func beginPage() {
                context.beginPage()
                page += 1
                y = 40
                ("HASH FLEET  /  SNAPSHOT" as NSString).draw(
                    at: CGPoint(x: 40, y: y), withAttributes: attributes(size: 11, bold: true)
                )
                y += 30
                let footer = "Captured \(FleetReportSnapshot.timestamp(report.capturedAt))  |  Page \(page)"
                (footer as NSString).draw(at: CGPoint(x: 40, y: 758), withAttributes: attributes(size: 9))
            }

            func paragraph(_ text: String, size: CGFloat = 11, bold: Bool = false) {
                let h = height(text, size: size, bold: bold)
                if y + h > bottom { beginPage() }
                (text as NSString).draw(
                    in: CGRect(x: 40, y: y, width: width, height: h),
                    withAttributes: attributes(size: size, bold: bold)
                )
                y += h
            }

            beginPage()
            paragraph("Fleet snapshot report", size: 23, bold: true)
            paragraph(report.isDemo ? "DEMO / SIMULATED READINGS" : "Miner-reported readings", bold: true)
            paragraph("Captured: \(FleetReportSnapshot.timestamp(report.capturedAt))")
            paragraph(FleetReportSnapshot.scopeNote)
            paragraph(FleetReportSnapshot.privacyNote, size: 10)
            paragraph(FleetReportSnapshot.freshnessNote, size: 10)
            y += 8
            paragraph("\(report.miners.count) miners · \(report.onlineCount) online at last response · \(report.offlineCount) offline at last check · \(report.unconfirmedCount) unconfirmed")
            paragraph("\(report.currentCount) fresh online · \(report.nonFreshCount) readings not fresh")
            paragraph("Hashrate subtotal: \(FleetReportSnapshot.formattedHashrate(report.hashrate.value)) (\(report.hashrate.coverage))", bold: true)
            let powerSubtotal = report.power.value.flatMap(FleetReportSnapshot.usable)
                .map { "\(FleetReportSnapshot.number($0)) W" } ?? "Not reported"
            paragraph("Power subtotal: \(powerSubtotal) (\(report.power.coverage))", bold: true)
            paragraph("Not reported means missing, invalid or no longer current, never an assumed zero. Per-miner values below may be last-known readings.", size: 10)
            y += 10

            if report.miners.isEmpty {
                paragraph("No miners in this fleet. Add a miner and capture a new report when readings are available.")
            }
            func metricText(_ value: Double?, unit: String) -> String {
                guard let usable = FleetReportSnapshot.usable(value) else { return "Not reported" }
                return "\(FleetReportSnapshot.number(usable)) \(unit)"
            }

            for miner in report.miners {
                let lines = [
                    "\(miner.connection.rawValue) · \(miner.freshness.rawValue)",
                    "Observed: \(FleetReportSnapshot.timestamp(miner.observedAt))",
                    miner.isCurrent ? "Included in fresh-online subtotals where reported." : "Last-known / unconfirmed readings. Excluded from subtotals.",
                    "Hashrate: \(FleetReportSnapshot.formattedHashrate(miner.hashrateGHs)) · Power: \(metricText(miner.powerWatts, unit: "W"))",
                    "Chip temperature: \(metricText(miner.temperatureCelsius, unit: "°C")) · Fan: \(metricText(miner.fanRPM, unit: "RPM"))",
                    "Uptime: \(metricText(miner.uptimeSeconds, unit: "seconds"))"
                ]
                let blockHeight = height(miner.label, size: 13, bold: true)
                    + lines.reduce(CGFloat(0)) { $0 + height($1, size: 10) } + 14
                if y + blockHeight > bottom { beginPage() }
                paragraph(miner.label, size: 13, bold: true)
                for line in lines { paragraph(line, size: 10) }
                y += 14
            }
        }
    }
#else
    private static func renderAppKit(_ report: FleetReportSnapshot) -> Data {
        let output = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }
        let body = NSMutableString()
        func add(_ text: String = "") { body.append(text + "\n") }
        add("Fleet snapshot report")
        add(report.isDemo ? "DEMO / SIMULATED READINGS" : "Miner-reported readings")
        add("Captured: \(FleetReportSnapshot.timestamp(report.capturedAt))")
        add(FleetReportSnapshot.scopeNote); add(FleetReportSnapshot.privacyNote); add(FleetReportSnapshot.freshnessNote)
        add("\(report.miners.count) miners · \(report.onlineCount) online at last response · \(report.offlineCount) offline at last check · \(report.unconfirmedCount) unconfirmed")
        add("\(report.currentCount) fresh online · \(report.nonFreshCount) readings not fresh")
        add("Hashrate subtotal: \(FleetReportSnapshot.formattedHashrate(report.hashrate.value)) (\(report.hashrate.coverage))")
        let power = report.power.value.flatMap(FleetReportSnapshot.usable).map { "\(FleetReportSnapshot.number($0)) W" } ?? "Not reported"
        add("Power subtotal: \(power) (\(report.power.coverage))")
        add("Not reported means missing, invalid or no longer current, never an assumed zero.")
        if report.miners.isEmpty { add("No miners in this fleet. Add a miner and capture a new report when readings are available.") }
        for miner in report.miners {
            func metric(_ value: Double?, _ unit: String) -> String {
                guard let value = FleetReportSnapshot.usable(value) else { return "Not reported" }
                return "\(FleetReportSnapshot.number(value)) \(unit)"
            }
            add(); add(miner.label); add("\(miner.connection.rawValue) · \(miner.freshness.rawValue)")
            add("Observed: \(FleetReportSnapshot.timestamp(miner.observedAt))")
            add(miner.isCurrent ? "Included in fresh-online subtotals where reported." : "Last-known / unconfirmed readings. Excluded from subtotals.")
            add("Hashrate: \(FleetReportSnapshot.formattedHashrate(miner.hashrateGHs)) · Power: \(metric(miner.powerWatts, "W"))")
            add("Chip temperature: \(metric(miner.temperatureCelsius, "°C")) · Fan: \(metric(miner.fanRPM, "RPM"))")
            add("Uptime: \(metric(miner.uptimeSeconds, "seconds"))")
        }
        let font = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
        let attributed = NSAttributedString(string: body as String, attributes: [.font: font, .foregroundColor: NSColor.black])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var location = 0
        var page = 0
        while location < attributed.length {
            page += 1
            context.beginPDFPage(nil)
            context.textMatrix = .identity
            let header = NSAttributedString(string: "HASH FLEET  /  SNAPSHOT", attributes: [.font: CTFontCreateWithName("Helvetica-Bold" as CFString, 11, nil), .foregroundColor: NSColor.black])
            let headerLine = CTLineCreateWithAttributedString(header)
            context.textPosition = CGPoint(x: 40, y: 752)
            CTLineDraw(headerLine, context)
            let path = CGMutablePath(); path.addRect(CGRect(x: 40, y: 48, width: 532, height: 680))
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            CTFrameDraw(frame, context)
            let footer = NSAttributedString(
                string: "Captured \(FleetReportSnapshot.timestamp(report.capturedAt))  |  Page \(page)",
                attributes: [.font: CTFontCreateWithName("Helvetica" as CFString, 9, nil), .foregroundColor: NSColor.black]
            )
            context.textPosition = CGPoint(x: 40, y: 28)
            CTLineDraw(CTLineCreateWithAttributedString(footer), context)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { break }
            location += visible.length
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }
#endif
}
