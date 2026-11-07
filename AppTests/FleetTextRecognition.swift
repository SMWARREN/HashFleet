import Foundation
import Vision
import ImageIO
import Testing

/// Independent, uncorrected observations of the same pixels. The character-oriented and
/// language-oriented recognizers have different failure modes for technical copy.
/// Neither receives expected text, custom words, corrected spelling or substituted units.
struct FleetRecognizedText: Sendable {
    let accurate: String
    let characters: String
    let lineAccurate: String
    let words: [FleetOCRLine]
    let wrappedAccurate: [String]
    let wrappedCharacters: [String]

    func contains(_ text: String, allowingLineWraps: Bool = false) -> Bool {
        if accurate.contains(text) || characters.contains(text) || lineAccurate.contains(text) { return true }
        return allowingLineWraps && (wrappedAccurate + wrappedCharacters).contains { $0.contains(text) }
    }

    func containsMetric(value: String, unit: String) -> Bool {
        words.filter { $0.text == value }.contains { number in
            words.filter { $0.text == unit }.contains { symbol in
                let height = min(number.bounds.height, symbol.bounds.height)
                let overlap = min(number.bounds.maxY, symbol.bounds.maxY) - max(number.bounds.minY, symbol.bounds.minY)
                let gap = symbol.bounds.minX - number.bounds.maxX
                return overlap > height * 0.6 && gap > height * 0.12
                    && gap < max(number.bounds.height, symbol.bounds.height)
            }
        }
    }
}

struct FleetOCRLine: Sendable {
    let text: String
    let bounds: CGRect
}

/// Geometry, not spelling, determines reading order and continuation. Keep columns apart
/// when testing an unbroken token wrapped onto the immediately following visual line.
enum FleetTextRecognition {
    static func readingOrder(_ lines: [FleetOCRLine]) -> [[FleetOCRLine]] {
        var rows: [[FleetOCRLine]] = []
        for line in lines.sorted(by: { $0.bounds.minY < $1.bounds.minY }) {
            if let index = rows.indices.last(where: { index in
                rows[index].contains { other in
                    let overlap = min(line.bounds.maxY, other.bounds.maxY) - max(line.bounds.minY, other.bounds.minY)
                    let smaller = min(line.bounds.height, other.bounds.height)
                    return overlap > smaller * 0.6
                        && abs(line.bounds.maxY - other.bounds.maxY) < max(line.bounds.height, other.bounds.height) * 0.3
                }
            }) {
                rows[index].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { $0.sorted { $0.bounds.minX < $1.bounds.minX } }
    }

    static func paragraphText(_ lines: [FleetOCRLine]) -> String {
        lines.map(\.text).joined(separator: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func text(_ lines: [FleetOCRLine]) -> String {
        paragraphText(readingOrder(lines).flatMap { $0 })
    }

    static func wrappedTokens(_ lines: [FleetOCRLine]) -> [String] {
        let rows = readingOrder(lines)
        return zip(rows, rows.dropFirst()).compactMap { first, second in
            guard first.count == 1, second.count == 1,
                  let previous = first.first, let next = second.first,
                  abs(previous.bounds.minX - next.bounds.minX) < min(previous.bounds.height, next.bounds.height),
                  next.bounds.minY - previous.bounds.maxY < max(previous.bounds.height, next.bounds.height),
                  next.bounds.minY >= previous.bounds.maxY else { return nil }
            // No internal whitespace is removed. Only the physical line break is joined.
            return previous.text + next.text
        }
    }

    static func recognize(_ data: Data) throws -> FleetRecognizedText {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var words: [FleetOCRLine] = []
        let accurate = try observations(in: image, level: .accurate, words: &words)
        let characters = try observations(in: image, level: .fast, words: &words)
        let refined = try refine(accurate + characters, in: image, words: &words)
        // Preserve Vision's paragraph order for ordinary copy. Sorting all observations
        // by rows can insert a centered icon between the two lines of a single label.
        // Geometry is used only for metrics and explicitly requested token continuations.
        return FleetRecognizedText(accurate: paragraphText(accurate), characters: paragraphText(characters),
                                  lineAccurate: text(refined), words: words,
                                  wrappedAccurate: wrappedTokens(accurate), wrappedCharacters: wrappedTokens(characters))
    }

    private static func wordBounds(
        _ candidate: VNRecognizedText, width: Int, height: Int, origin: CGPoint
    ) -> [FleetOCRLine] {
        let text = candidate.string
        var remaining = text.startIndex..<text.endIndex
        return text.split(whereSeparator: \.isWhitespace).compactMap { word in
            guard let range = text.range(of: word, range: remaining) else { return nil }
            remaining = range.upperBound..<text.endIndex
            guard let observation = try? candidate.boundingBox(for: range) else { return nil }
            let box = observation.boundingBox
            return FleetOCRLine(text: String(word), bounds: CGRect(
                x: origin.x + box.minX * Double(width), y: origin.y + (1 - box.maxY) * Double(height),
                width: box.width * Double(width), height: box.height * Double(height)))
        }
    }

    /// A second observation of a tight pixel crop can disambiguate a short technical
    /// label. Mixed alphabets are a recognition ambiguity, not permission to replace
    /// characters. Both passes remain uncorrected and receive no expected copy.
    static func needsLineRefinement(_ text: String) -> Bool {
        guard text.count <= 40 else { return false }
        if text.contains(where: \.isNumber) { return true }
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        return letters.contains { $0.isASCII } && letters.contains { !$0.isASCII }
    }

    private static func refine(
        _ lines: [FleetOCRLine], in image: CGImage, words: inout [FleetOCRLine]
    ) throws -> [FleetOCRLine] {
        var refined: [FleetOCRLine] = []
        for line in lines where needsLineRefinement(line.text) {
            let crop = line.bounds.insetBy(dx: -12, dy: -8).integral
                .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard let pixels = image.cropping(to: crop) else { continue }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = false
            request.minimumTextHeight = 0
            try VNImageRequestHandler(cgImage: pixels, orientation: .up).perform([request])
            for observation in request.results ?? [] {
                guard let candidate = observation.topCandidates(1).first else { continue }
                refined.append(FleetOCRLine(text: candidate.string, bounds: line.bounds))
                words += wordBounds(candidate, width: pixels.width, height: pixels.height, origin: crop.origin)
            }
        }
        return refined
    }

    private static func observations(
        in image: CGImage, level: VNRequestTextRecognitionLevel, words: inout [FleetOCRLine]
    ) throws -> [FleetOCRLine] {
        var lines: [FleetOCRLine] = []
        for strip in recognitionStrips(width: image.width, height: image.height) {
            try Task.checkCancellation()
            let tile = try #require(image.cropping(to: strip.crop))
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = level
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = false
            request.minimumTextHeight = Float(2) / Float(tile.height)
            try VNImageRequestHandler(cgImage: tile, orientation: .up).perform([request])
            for observation in request.results ?? [] {
                let box = observation.boundingBox
                let bounds = CGRect(x: strip.crop.minX + box.minX * Double(tile.width),
                                    y: strip.crop.minY + (1 - box.maxY) * Double(tile.height),
                                    width: box.width * Double(tile.width), height: box.height * Double(tile.height))
                guard bounds.midX >= Double(strip.coreX.lowerBound), bounds.midX < Double(strip.coreX.upperBound),
                      bounds.midY >= Double(strip.core.lowerBound), bounds.midY < Double(strip.core.upperBound),
                      let candidate = observation.topCandidates(1).first else { continue }
                lines.append(FleetOCRLine(text: candidate.string, bounds: bounds))
                words += wordBounds(candidate, width: tile.width, height: tile.height, origin: strip.crop.origin)
            }
        }
        return lines
    }
}
