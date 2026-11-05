import Foundation

struct PythonFoldRegion: Equatable {
    let header: Int
    let body: NSRange
}

/// Finds indentation-based suites without treating comments or string contents as code.
enum PythonFolding {
    static func regions(in text: String) -> [PythonFoldRegion] {
        let source = text as NSString
        guard source.length > 0 else { return [] }
        struct Line { let start: Int; let end: Int; let indentation: Int; let content: String; let contentStart: Int }
        var lines: [Line] = []
        var pos = 0
        while pos < source.length {
            let line = source.lineRange(for: NSRange(location: pos, length: 0))
            let raw = source.substring(with: line) as NSString
            var p = 0, indentation = 0
            while p < raw.length {
                let c = raw.character(at: p)
                if c == 32 { indentation += 1 } else if c == 9 { indentation += 4 - indentation % 4 } else { break }
                p += 1
            }
            let content = raw.substring(from: p).trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append(Line(start: line.location, end: NSMaxRange(line), indentation: indentation, content: content, contentStart: line.location + p))
            pos = NSMaxRange(line)
        }
        let ignored = PythonSyntax.tokens(in: text).filter { $0.kind == .string || $0.kind == .comment }.map(\.range)
        func ignoredAt(_ pos: Int) -> Bool { ignored.contains { NSLocationInRange(pos, $0) } }
        let prefixes = ["def ", "class ", "if ", "elif ", "else:", "for ", "while ", "try:", "except", "finally:", "with ", "match ", "case ", "async def ", "async for ", "async with "]
        var result: [PythonFoldRegion] = []
        for index in lines.indices {
            let line = lines[index]
            guard prefixes.contains(where: { line.content.hasPrefix($0) }), !ignoredAt(line.contentStart) else { continue }
            let raw = source.substring(with: NSRange(location: line.start, length: line.end - line.start)) as NSString
            var colon: Int? = nil
            if raw.length > 0 {
                for i in 0..<raw.length where raw.character(at: i) == 58 && !ignoredAt(line.start + i) { colon = i }
            }
            guard let colon else { continue }
            // Only a single-line suite header is folded; inline statements are not hidden.
            let after = raw.substring(from: colon + 1).trimmingCharacters(in: .whitespacesAndNewlines)
            guard after.isEmpty || after.hasPrefix("#") else { continue }
            var end = line.end, hasBody = false
            for child in lines.dropFirst(index + 1) {
                if child.content.isEmpty || child.content.hasPrefix("#") { end = child.end; continue }
                if child.indentation <= line.indentation { break }
                hasBody = true; end = child.end
            }
            if hasBody && end > line.end { result.append(PythonFoldRegion(header: line.start, body: NSRange(location: line.end, length: end - line.end))) }
        }
        return result
    }
}
