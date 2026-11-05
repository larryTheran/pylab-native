import Foundation

/// Bounds the transient console display while notebook outputs stay untouched.
struct ConsoleLog: Equatable, ExpressibleByStringLiteral {
    static let defaultByteLimit = 256 * 1024
    let byteLimit: Int
    private(set) var text = ""
    private(set) var wasTrimmed = false

    init(byteLimit: Int = Self.defaultByteLimit) {
        self.byteLimit = max(4, byteLimit)
    }
    init(stringLiteral value: String) {
        self.init()
        append(value)
    }
    var displayText: String {
        (wasTrimmed ? "[Earlier console output trimmed; showing the most recent output.]\n" : "") + text
    }
    mutating func append(_ value: String) {
        guard !value.isEmpty else { return }
        let incoming = Self.tail(value, byteLimit: byteLimit)
        let combined = text + incoming.text
        let result = Self.tail(combined, byteLimit: byteLimit)
        text = result.text
        wasTrimmed = wasTrimmed || incoming.trimmed || result.trimmed
    }
    static func += (log: inout Self, value: String) { log.append(value) }

    private static func tail(_ value: String, byteLimit: Int) -> (text: String, trimmed: Bool) {
        guard value.utf8.count > byteLimit else { return (value, false) }
        let bytes = value.utf8
        var start = bytes.index(bytes.endIndex, offsetBy: -byteLimit)
        // Avoid splitting a Unicode scalar at the truncation boundary.
        while start != bytes.endIndex, bytes[start] & 0xc0 == 0x80 { bytes.formIndex(after: &start) }
        return (String(decoding: bytes[start...], as: UTF8.self), true)
    }
}
