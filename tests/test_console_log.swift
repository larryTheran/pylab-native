import Foundation
@main struct ConsoleLogChecks {
    static func main() {
        var log = ConsoleLog(byteLimit: 32)
        log += "First line\n"
        log += "Second line\n"
        precondition(log.displayText == "First line\nSecond line\n" && !log.wasTrimmed)
        log += String(repeating: "x", count: 100) + "\nlatest\n"
        precondition(log.text.utf8.count <= 32 && log.text.hasSuffix("\nlatest\n") && log.wasTrimmed)
        precondition(log.displayText.contains("Earlier console output trimmed"))
        log += "🚀 café e\u{301}\n"
        precondition(log.text.utf8.count <= 32 && !log.text.contains("�") && log.text.hasSuffix("🚀 café e\u{301}\n"))
        var small = ConsoleLog(byteLimit: 5)
        small += "😀😀"
        precondition(small.text == "😀" && small.wasTrimmed)
        var reset: ConsoleLog = ""
        precondition(!reset.wasTrimmed && reset.displayText.isEmpty)
        reset += "hello"
        precondition(reset.displayText == "hello")
        print("PASS: bounded console tail, huge writes, Unicode boundaries and clear state")
    }
}
