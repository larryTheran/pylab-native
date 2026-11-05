import Foundation
@main struct FoldingTest {
 static func main() {
    let source = """
    def first():
        value = "if x:"
        if value:
            print(value)
        return value

    class Second:
        def method(self):
            return 2

    message = \"\"\"\nif fake:\n    not_a_block\n\"\"\"
    """
    let folds = PythonFolding.regions(in: source)
    let ns = source as NSString
    let headers = folds.map { ns.substring(with: ns.lineRange(for: NSRange(location: $0.header, length: 0))).trimmingCharacters(in: .whitespacesAndNewlines) }
    precondition(headers == ["def first():", "if value:", "class Second:", "def method(self):"], "Unexpected headers: \(headers)")
    precondition(ns.substring(with: folds[0].body).contains("return value"))
    precondition(!ns.substring(with: folds[0].body).contains("class Second"))
    let inline = "if True: print('hi')\ndef empty():\n    pass\n"
    precondition(PythonFolding.regions(in: inline).count == 1)
    print("PASS: nested suites, indentation boundaries, strings, and inline statements")
 }
}
