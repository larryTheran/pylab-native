import Foundation

@main
struct PythonSyntaxChecks {
    static func main() {
        let source = """
        # comment with def and 'string'
        @dataclass(frozen=True)
        class Triangle:
            def area(self, x=2.5e-3):
                text = "# not a comment, π"
                block = '''first
        def this_is_not_code():
        # still string'''
                return max(x, 0x10)  # trailing
        """
        let text = source as NSString
        let tokens = PythonSyntax.tokens(in: source)
        func kind(_ needle: String, occurrence: Int = 0) -> PythonSyntaxKind? {
            var begin = 0
            for index in 0...occurrence {
                let range = text.range(of: needle, options: [], range: NSRange(location: begin, length: text.length - begin))
                guard range.location != NSNotFound else { return nil }
                begin = range.location + range.length
                if index == occurrence {
                    return tokens.first(where: { NSLocationInRange(range.location, $0.range) })?.kind
                }
            }
            return nil
        }
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            if !value() { fputs("FAIL: \(message)\n", stderr); exit(1) }
        }
        check(kind("# comment") == .comment, "comment coloring")
        check(kind("def", occurrence: 0) == .comment, "keyword inside comment")
        check(kind("@dataclass") == .decorator, "decorator coloring")
        check(kind("class Triangle") == .keyword, "class keyword")
        check(kind("Triangle") == .typeName, "class name")
        check(kind("area") == .function, "function definition")
        check(kind("2.5e-3") == .number, "scientific number")
        check(kind("# not a comment") == .string, "hash in string")
        check(kind("π") == .string, "unicode ranges")
        check(kind("this_is_not_code") == .string, "triple string across lines")
        check(kind("# still string") == .string, "comment in triple string")
        check(kind("return") == .keyword, "keyword after string")
        check(kind("max") == .builtin, "builtin")
        check(kind("0x10") == .number, "hex number")
        check(kind("# trailing") == .comment, "trailing comment")
        let unicode = "# 😀 before UTF-16\nvalue = 'á😀'\nprint(value)"
        let unicodeText = unicode as NSString
        let unicodeTokens = PythonSyntax.tokens(in: unicode)
        let printRange = unicodeText.range(of: "print")
        check(unicodeTokens.contains(where: { $0.kind == .builtin && $0.range.location == printRange.location }), "UTF-16 positions after emoji")
        let large = String(repeating: "def calculate(x):\n    return x * 2 # test\n", count: 2_000)
        let start = Date()
        let largeTokens = PythonSyntax.tokens(in: large)
        check(!largeTokens.isEmpty && Date().timeIntervalSince(start) < 5, "large-cell highlighting performance")
        print("PASS: Python syntax, strings, comments, definitions, numbers, UTF-16, and large cells")
    }
}
