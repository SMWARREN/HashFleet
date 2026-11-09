import Foundation
import Darwin

/// Owns terminal state for one dashboard session. All exits pass through restore().
final class TerminalSession {
    static var isInteractive: Bool {
        isatty(STDIN_FILENO) == 1 && hasTerminalOutput
    }

    static var hasTerminalOutput: Bool {
        isatty(STDOUT_FILENO) == 1 && ProcessInfo.processInfo.environment["TERM"] != "dumb"
    }

    private var original = termios()
    private var restored = false

    init() throws {
        guard tcgetattr(STDIN_FILENO, &original) == 0 else {
            throw POSIXError(.ENOTTY)
        }
        var raw = original
        cfmakeraw(&raw)
        // Keep output processing; only input needs character-at-a-time delivery.
        raw.c_oflag = original.c_oflag
        guard tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0 else { throw POSIXError(.ENOTTY) }
        setlocale(LC_CTYPE, "")
        write("\u{1B}[?1049h\u{1B}[?25l\u{1B}[?2004h\u{1B}[2J\u{1B}[H")
    }

    var size: (columns: Int, rows: Int) { Self.outputSize }

    static var outputSize: (columns: Int, rows: Int) {
        var size = winsize()
        guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0 else { return (100, 30) }
        return (size.ws_col == 0 ? 100 : Int(size.ws_col), size.ws_row == 0 ? 30 : Int(size.ws_row))
    }

    /// nil means the terminal input closed; an empty array means no key is ready.
    func input() -> [UInt8]? {
        // stdin and stdout can share one open file description in embedded terminals.
        // Setting O_NONBLOCK on stdin would then also break full-frame stdout writes.
        var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        let ready = poll(&descriptor, 1, 0)
        if ready == 0 || (ready < 0 && errno == EINTR) { return [] }
        guard ready > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: 128)
        let count = Darwin.read(STDIN_FILENO, &bytes, bytes.count)
        if count > 0 { return Array(bytes.prefix(count)) }
        if count == 0 { return nil }
        return errno == EAGAIN || errno == EINTR ? [] : nil
    }

    func write(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }

    func restore() {
        guard !restored else { return }
        restored = true
        write("\u{1B}[?2004l\u{1B}[0m\u{1B}[?25h\u{1B}[?1049l")
        tcsetattr(STDIN_FILENO, TCSANOW, &original)
    }

    deinit { restore() }
}

enum TerminalText {
    static func wrapped(_ text: String, width: Int) -> [String] {
        let columns = max(1, width)
        var lines: [String] = [], line = "", used = 0
        for character in safe(text) {
            let cells = Self.width(character)
            if used + cells > columns, !line.isEmpty { lines.append(line); line = ""; used = 0 }
            line.append(character); used += cells
        }
        if !line.isEmpty { lines.append(line) }
        return lines
    }

    /// Firmware strings are data, never terminal commands or extra display rows.
    static func safe(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.prefix(2_048).map { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator: return " "
            default: return scalar
            }
        }))
    }

    static func width(_ character: Character) -> Int {
        character.unicodeScalars.map { max(0, Int(wcwidth(Int32($0.value)))) }.max() ?? 0
    }

    static func fit(_ text: String, _ columns: Int, right: Bool = false) -> String {
        guard columns > 0 else { return "" }
        let text = safe(text)
        let length = text.reduce(0) { $0 + width($1) }
        if length <= columns {
            let padding = String(repeating: " ", count: columns - length)
            return right ? padding + text : text + padding
        }
        var result = ""
        var used = 0
        for character in text {
            let next = width(character)
            guard used + next <= columns - 1 else { break }
            result.append(character)
            used += next
        }
        return result + "…" + String(repeating: " ", count: max(0, columns - used - 1))
    }
}
