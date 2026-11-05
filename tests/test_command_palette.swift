import Foundation

@main
struct CommandPaletteTests {
    static func main() {
        let all = PaletteCommand.matching("")
        precondition(all.count == Set(all.map(\.id)).count, "Commands must have unique action IDs")
        precondition(PaletteCommand.matching("  ").map(\.id) == all.map(\.id))
        precondition(PaletteCommand.matching("python conda").map(\.action) == [.kernelSettings])
        precondition(PaletteCommand.matching("ALL ABOVE").map(\.action) == [.runAbove])
        precondition(PaletteCommand.matching("mat save").map(\.action) == [.exportMat])
        precondition(PaletteCommand.matching("zzzz-no-command").isEmpty)
        precondition(PaletteCommand.matching("search code").contains { $0.action == .findCells })
        precondition(PaletteCommand.matching("run all cells").first?.action == .runAll,
                     "An exact title must outrank matching help text")
        precondition(PaletteCommand.matching("  RUN   all cells  ").first?.action == .runAll)
        precondition(PaletteCommand.matching("save all").first?.action == .saveAll)
        precondition(PaletteCommand.matching("restart kernel").first?.action == .restart)
        let ranked = [
            PaletteCommand(action: .runAbove, title: "First fallback", detail: "run example", icon: ""),
            PaletteCommand(action: .runBelow, title: "Second fallback", detail: "run example", icon: ""),
            PaletteCommand(action: .runCell, title: "Select Run Example", detail: "", icon: ""),
            PaletteCommand(action: .runAdvance, title: "Run Example and Advance", detail: "", icon: ""),
            PaletteCommand(action: .runAll, title: "Run Example", detail: "", icon: ""),
        ]
        precondition(PaletteCommand.matching("run example", commands: ranked).map(\.action)
                     == [.runAll, .runAdvance, .runCell, .runAbove, .runBelow],
                     "Rank exact titles, prefixes, phrases, then stable help-text matches")
        print("Command palette filtering and ranking checks passed")
    }
}
