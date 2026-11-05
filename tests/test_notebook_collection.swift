import Foundation
@main struct TestCollection {
 static func main() throws {
   let group = NotebookCollection()
   let first = group.selectedID
   group.selected.store.cells[0].source = "first"
   group.selected.store.markDirty()
   group.add()
   let second = group.selectedID
   precondition(first != second && group.tabs.count == 2 && group.isDirty)
   precondition(group.selected.store.cells[0].source.isEmpty)
   group.move(second, to: first)
   precondition(group.tabs.map(\.id) == [second, first] && group.selectedID == second)
   group.selectedID = first
   precondition(group.selected.store.cells[0].source == "first")
   group.remove(second)
   precondition(group.tabs.count == 1 && group.selectedID == first && group.isDirty)
   let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pylab-collection-\(UUID().uuidString)")
   try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
   defer { try? FileManager.default.removeItem(at: folder) }
   let file = folder.appendingPathComponent("shared.ipynb")
   let loaded = NotebookStore(); loaded.cells[0].source = "saved = 1"
   try loaded.save(to: file)
   group.addLoaded(loaded)
   let openedID = group.selectedID
   loaded.cells[0].source = "unsaved = 42"; loaded.markDirty()
   let alias = folder.appendingPathComponent("alias.ipynb")
   try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: file)
   let hardlink = folder.appendingPathComponent("hardlink.ipynb")
   try FileManager.default.linkItem(at: file, to: hardlink)
   for path in [file, alias, hardlink] {
     group.selectedID = first
     let restored = NotebookStore(); try restored.load(from: path)
     group.addLoaded(restored)
     precondition(group.tabs.count == 2 && group.selectedID == openedID)
     precondition(group.selected.store === loaded && loaded.isDirty && loaded.cells[0].source == "unsaved = 42", "duplicate restore replaced unsaved notebook")
   }
   let different = NotebookStore()
   try different.save(to: folder.appendingPathComponent("different.ipynb"))
   group.addLoaded(different)
   precondition(group.tabs.count == 3 && group.selected.store === different)
   print("PASS: independent contents, selection/order/dirty tracking, duplicate/alias restore deduplication and unsaved-store preservation")
 }
}
