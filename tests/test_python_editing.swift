import Foundation
@main struct PythonEditingTest {
    static func main() {
        func perform(_ command: PythonEditing.Command, _ text: String, _ selection: NSRange? = nil) -> (String, NSRange) {
            let range = selection ?? NSRange(location: (text as NSString).length, length: 0)
            guard let edit = PythonEditing.edit(command, in: text, selection: range) else { return (text, range) }
            return ((text as NSString).replacingCharacters(in: edit.range, with: edit.text), edit.selection)
        }
        precondition(perform(.newline, "def example():").0 == "def example():\n    ")
        precondition(perform(.newline, "    if ready: # start").0 == "    if ready: # start\n        ")
        precondition(perform(.newline, "\tfor x in values:").0 == "\tfor x in values:\n\t\t")
        precondition(perform(.newline, "    result = {'key':").0 == "    result = {'key':\n    ")
        precondition(perform(.newline, "    message = 'if ready:'").0 == "    message = 'if ready:'\n    ")
        precondition(perform(.newline, "message = \"\"\"\nif ready:").0 == "message = \"\"\"\nif ready:\n")
        precondition(perform(.newline, "if label == '😀':").0 == "if label == '😀':\n    ")
        let source = "    value = 1\n    print(value)\nnext_value = 2\n"
        let selected = NSRange(location: 0, length: ("    value = 1\n    print(value)\n" as NSString).length)
        let commented = perform(.toggleComment, source, selected)
        precondition(commented.0 == "    # value = 1\n    # print(value)\nnext_value = 2\n")
        precondition(perform(.toggleComment, commented.0, commented.1).0 == source)
        let unicode = "    print('😀')\n"
        let result = perform(.toggleComment, unicode, NSRange(location: 10, length: 0))
        precondition(result.0 == "    # print('😀')\n" && result.1.location == 12)
        let indented = perform(.indent, source, selected)
        precondition(indented.0 == "        value = 1\n        print(value)\nnext_value = 2\n")
        precondition(perform(.outdent, indented.0, indented.1).0 == source)
        precondition(perform(.indent, "x").0 == "x   ")
        precondition(perform(.outdent, "  x").0 == "x")
        precondition(PythonEditing.executableSelection("    a = 2\n    if a:\n        print(a)\n") == "a = 2\nif a:\n    print(a)\n")
        precondition(PythonEditing.executableSelection("print(1)\n    print(2)") == "print(1)\n    print(2)")
        print("PASS: Python suite indentation, strings/comments, comment round trips, Unicode positions, block indent/outdent and selection dedenting")
    }
}
