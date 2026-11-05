import Foundation

/// Small, source-only edits shared by the native editor and its focused tests.
/// Every range uses UTF-16 so emoji and non-ASCII identifiers retain their cursor positions.
enum PythonEditing {
    enum Command { case newline, indent, outdent, toggleComment }
    struct Edit {
        let range: NSRange
        let text: String
        let selection: NSRange
    }

    static func edit(_ command: Command, in text: String, selection: NSRange) -> Edit? {
        let source = text as NSString
        guard selection.location != NSNotFound, selection.location >= 0,
              selection.length >= 0, NSMaxRange(selection) <= source.length else { return nil }
        if case .newline = command {
            let line = source.lineRange(for: NSRange(location: selection.location, length: 0))
            let prefix = source.substring(with: NSRange(location: line.location, length: selection.location - line.location))
            let indentation = String(prefix.prefix { $0 == " " || $0 == "\t" })
            // Only real suite headers gain indentation. A colon inside a comment,
            // dictionary, slice, or string does not start a new suite.
            let beforeCursor = source.substring(to: selection.location)
            let masked = NSMutableString(string: beforeCursor)
            for token in PythonSyntax.tokens(in: beforeCursor).reversed() where token.kind == .string || token.kind == .comment {
                let original = (beforeCursor as NSString).substring(with: token.range)
                // Replace with one space per UTF-16 code unit, retaining line endings.
                let units = original.utf16.map { $0 == 10 || $0 == 13 ? $0 : UInt16(32) }
                masked.replaceCharacters(in: token.range, with: String(decoding: units, as: UTF16.self))
            }
            let current = masked.substring(from: line.location).trimmingCharacters(in: .whitespacesAndNewlines)
            let suite = current.hasSuffix(":") && current.range(of: "^(?:(?:async[ \\t]+)?(?:def|for|with)|class|if|elif|else|while|try|except|finally|match|case)\\b", options: .regularExpression) != nil
            let unit = indentation.contains("\t") ? "\t" : "    "
            let replacement = "\n" + indentation + (suite ? unit : "")
            return Edit(range: selection, text: replacement, selection: NSRange(location: selection.location + (replacement as NSString).length, length: 0))
        }
        if case .indent = command, selection.length == 0 {
            let line = source.lineRange(for: selection)
            let prefix = source.substring(with: NSRange(location: line.location, length: selection.location - line.location))
            let leading = String(prefix.prefix { $0 == " " || $0 == "\t" })
            let replacement: String
            if leading.contains("\t"), leading.count == prefix.count { replacement = "\t" }
            else {
                let column = prefix.reduce(0) { count, character in character == "\t" ? count + 4 - count % 4 : count + 1 }
                replacement = String(repeating: " ", count: 4 - column % 4)
            }
            return Edit(range: selection, text: replacement, selection: NSRange(location: selection.location + (replacement as NSString).length, length: 0))
        }
        let start = source.lineRange(for: NSRange(location: selection.location, length: 0)).location
        let last = selection.length == 0 ? selection.location : NSMaxRange(selection) - 1
        let end = NSMaxRange(source.lineRange(for: NSRange(location: last, length: 0)))
        let block = NSRange(location: start, length: end - start)
        let original = source.substring(with: block) as NSString
        var lines: [(start: Int, indent: Int, content: String)] = []
        var position = 0
        while position < original.length {
            let range = original.lineRange(for: NSRange(location: position, length: 0))
            let value = original.substring(with: range)
            let leading = String(value.prefix { $0 == " " || $0 == "\t" })
            lines.append((range.location, (leading as NSString).length, value))
            position = NSMaxRange(range)
        }
        if lines.isEmpty { lines.append((0, 0, "")) }
        let nonempty = lines.filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let uncomment = !nonempty.isEmpty && nonempty.allSatisfy { ($0.content as NSString).substring(from: $0.indent).hasPrefix("#") }
        var changes: [(start: Int, count: Int, value: String)] = []
        for line in lines {
            let value = line.content as NSString
            switch command {
            case .toggleComment:
                guard !line.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                if uncomment {
                    let after = value.substring(from: line.indent)
                    changes.append((line.start + line.indent, after.hasPrefix("# ") ? 2 : 1, ""))
                } else { changes.append((line.start + line.indent, 0, "# ")) }
            case .indent:
                changes.append((line.start, 0, line.content.hasPrefix("\t") ? "\t" : "    "))
            case .outdent:
                if line.content.hasPrefix("\t") { changes.append((line.start, 1, "")) }
                else {
                    let amount = min(4, line.content.prefix { $0 == " " }.count)
                    if amount > 0 { changes.append((line.start, amount, "")) }
                }
            case .newline: break
            }
        }
        guard !changes.isEmpty else { return nil }
        let result = NSMutableString(string: original)
        for change in changes.reversed() { result.replaceCharacters(in: NSRange(location: change.start, length: change.count), with: change.value) }
        func transformed(_ absolute: Int) -> Int {
            let local = absolute - start
            var delta = 0
            for change in changes {
                if local < change.start { break }
                let newCount = (change.value as NSString).length
                if local <= change.start + change.count { return start + change.start + delta + newCount }
                delta += newCount - change.count
            }
            return absolute + delta
        }
        let a = transformed(selection.location), b = transformed(NSMaxRange(selection))
        return Edit(range: block, text: result as String, selection: NSRange(location: a, length: max(0, b - a)))
    }

    /// Allow highlighted statements from an indented suite to run at the kernel prompt.
    /// The same common leading whitespace is removed from every nonblank line.
    static func executableSelection(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let indents = lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { String($0.prefix { $0 == " " || $0 == "\t" }) }
        guard var common = indents.first else { return text }
        for indent in indents.dropFirst() {
            while !indent.hasPrefix(common), !common.isEmpty { common.removeLast() }
        }
        guard !common.isEmpty else { return text }
        return lines.map { $0.hasPrefix(common) ? String($0.dropFirst(common.count)) : $0 }.joined(separator: "\n")
    }
}
