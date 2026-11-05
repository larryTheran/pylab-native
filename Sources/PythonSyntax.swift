import Foundation

/// Lightweight, linear Python lexer. Ranges use UTF-16, as required by AppKit.
/// This is intentionally syntax coloring rather than a Python parser.
enum PythonSyntaxKind: Equatable {
    case keyword, constant, string, comment, number, builtin, function, typeName, decorator
}

struct PythonSyntaxToken: Equatable {
    let range: NSRange
    let kind: PythonSyntaxKind
}

enum PythonSyntax {
    private static let keywords: Set<String> = [
        "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del",
        "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in",
        "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while",
        "with", "yield", "match", "case"
    ]
    private static let constants: Set<String> = ["True", "False", "None", "NotImplemented", "Ellipsis", "__name__", "__file__"]
    private static let builtins: Set<String> = [
        "abs", "all", "any", "bin", "bool", "breakpoint", "bytearray", "bytes", "callable", "chr",
        "classmethod", "compile", "complex", "delattr", "dict", "dir", "divmod", "enumerate", "eval",
        "exec", "filter", "float", "format", "frozenset", "getattr", "globals", "hasattr", "hash",
        "help", "hex", "id", "input", "int", "isinstance", "issubclass", "iter", "len", "list",
        "locals", "map", "max", "memoryview", "min", "next", "object", "oct", "open", "ord",
        "pow", "print", "property", "range", "repr", "reversed", "round", "set", "setattr", "slice",
        "sorted", "staticmethod", "str", "sum", "super", "tuple", "type", "vars", "zip",
        "Exception", "ValueError", "TypeError", "RuntimeError", "KeyError", "IndexError", "ImportError"
    ]
    private static let prefixes: Set<String> = ["r", "u", "b", "f", "br", "rb", "fr", "rf"]

    private static func isDigit(_ c: unichar) -> Bool { c >= 48 && c <= 57 }
    private static func isLetter(_ c: unichar) -> Bool {
        (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c >= 128
    }
    private static func isWord(_ c: unichar) -> Bool { isLetter(c) || isDigit(c) }
    private static func isSpace(_ c: unichar) -> Bool { c == 32 || c == 9 || c == 12 }

    static func tokens(in text: String) -> [PythonSyntaxToken] {
        let s = text as NSString
        let count = s.length
        guard count > 0 else { return [] }
        var tokens: [PythonSyntaxToken] = []
        var i = 0
        var atLineStart = true
        var definition: PythonSyntaxKind?
        func add(_ start: Int, _ end: Int, _ kind: PythonSyntaxKind) {
            if end > start { tokens.append(PythonSyntaxToken(range: NSRange(location: start, length: end - start), kind: kind)) }
        }
        func quotedEnd(_ start: Int) -> Int {
            let quote = s.character(at: start)
            let triple = start + 2 < count && s.character(at: start + 1) == quote && s.character(at: start + 2) == quote
            var p = start + (triple ? 3 : 1)
            while p < count {
                let c = s.character(at: p)
                if c == 92 { p = min(count, p + 2); continue }
                if c == quote {
                    if !triple { return p + 1 }
                    if p + 2 < count && s.character(at: p + 1) == quote && s.character(at: p + 2) == quote { return p + 3 }
                }
                if !triple && (c == 10 || c == 13) { return p }
                p += 1
            }
            return count
        }
        while i < count {
            let c = s.character(at: i)
            if c == 10 || c == 13 { atLineStart = true; definition = nil; i += 1; continue }
            if isSpace(c) { i += 1; continue }
            if c == 35 { // # comment, unless consumed inside a string
                let start = i
                while i < count && s.character(at: i) != 10 && s.character(at: i) != 13 { i += 1 }
                add(start, i, .comment); atLineStart = false; continue
            }
            if c == 34 || c == 39 {
                let end = quotedEnd(i); add(i, end, .string); i = max(end, i + 1); atLineStart = false; definition = nil; continue
            }
            if c == 64 && atLineStart && i + 1 < count && isLetter(s.character(at: i + 1)) {
                let start = i; i += 1
                while i < count && (isWord(s.character(at: i)) || s.character(at: i) == 46) { i += 1 }
                add(start, i, .decorator); atLineStart = false; continue
            }
            if isLetter(c) {
                let start = i; i += 1
                while i < count && isWord(s.character(at: i)) { i += 1 }
                let word = s.substring(with: NSRange(location: start, length: i - start))
                if i < count && (s.character(at: i) == 34 || s.character(at: i) == 39) && prefixes.contains(word.lowercased()) {
                    let end = quotedEnd(i); add(start, end, .string); i = end; atLineStart = false; definition = nil; continue
                }
                if let expected = definition {
                    add(start, i, expected); definition = nil
                } else if keywords.contains(word) {
                    add(start, i, .keyword)
                    if word == "def" { definition = .function }
                    else if word == "class" { definition = .typeName }
                } else if constants.contains(word) { add(start, i, .constant) }
                else if builtins.contains(word) { add(start, i, .builtin) }
                else {
                    var next = i
                    while next < count && isSpace(s.character(at: next)) { next += 1 }
                    if next < count && s.character(at: next) == 40 { add(start, i, .function) }
                }
                atLineStart = false; continue
            }
            if isDigit(c) || (c == 46 && i + 1 < count && isDigit(s.character(at: i + 1))) {
                let start = i
                let isHex = c == 48 && i + 1 < count && (s.character(at: i + 1) == 120 || s.character(at: i + 1) == 88)
                i += 1
                while i < count {
                    let d = s.character(at: i)
                    if isDigit(d) || d == 95 || d == 46 || d == 106 || d == 74 || d == 101 || d == 69 ||
                        (isHex && ((d >= 65 && d <= 70) || (d >= 97 && d <= 102) || d == 120 || d == 88)) ||
                        (i == start + 1 && (d == 98 || d == 66 || d == 111 || d == 79)) { i += 1; continue }
                    if (d == 43 || d == 45) && i > start && (s.character(at: i-1) == 101 || s.character(at: i-1) == 69) { i += 1; continue }
                    break
                }
                add(start, i, .number); atLineStart = false; definition = nil; continue
            }
            atLineStart = false; definition = nil; i += 1
        }
        return tokens
    }
}
