import Foundation

enum TerminalKey {
    case byte(UInt8), up, down, left, right, escape, paste([UInt8])
}

/// Decodes split escape sequences and keeps pasted text separate from command keys.
struct TerminalInput {
    private var bytes: [UInt8] = []
    private var escapeStarted: Date?

    mutating func append(_ value: [UInt8]) {
        // Interrupts must work even if a terminal never finishes an escape or paste sequence.
        if let interrupt = value.first(where: { $0 == 3 || $0 == 4 }) {
            clear(); bytes = [interrupt]
        } else { bytes += value }
    }
    mutating func clear() { bytes.removeAll(); escapeStarted = nil }

    mutating func next() -> TerminalKey? {
        while !bytes.isEmpty {
            guard bytes[0] == 27 else { return .byte(bytes.removeFirst()) }
            if bytes.count == 1 {
                if let started = escapeStarted, Date().timeIntervalSince(started) >= 0.15 {
                    clear(); return .escape
                }
                if escapeStarted == nil { escapeStarted = Date() }
                return nil
            }
            escapeStarted = nil
            guard bytes[1] == 91 || bytes[1] == 79 else { bytes.removeFirst(); return .escape }
            guard let final = bytes.indices.dropFirst(2).first(where: { (64...126).contains(bytes[$0]) }) else {
                if bytes.count > 32 { clear() }
                return nil
            }
            let sequence = Array(bytes[0...final])
            if sequence == [27, 91, 50, 48, 48, 126] {
                let end = Data([27, 91, 50, 48, 49, 126])
                guard let range = Data(bytes).range(of: end) else { return nil }
                let pasted = Array(bytes[(final + 1)..<range.lowerBound].prefix(1024))
                bytes.removeFirst(range.upperBound)
                return .paste(pasted)
            }
            bytes.removeFirst(final + 1)
            switch sequence.last {
            case 65: return .up
            case 66: return .down
            case 67: return .right
            case 68: return .left
            default: continue
            }
        }
        return nil
    }
}
