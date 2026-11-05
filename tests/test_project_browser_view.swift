import SwiftUI
import AppKit

@main struct ProjectBrowserViewChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.appearance=NSAppearance(named:.darkAqua)
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("pylab-browser-view-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let child=folder.appendingPathComponent("Data",isDirectory:true)
        try FileManager.default.createDirectory(at:child,withIntermediateDirectories:false)
        let files=["Analysis.ipynb","model.py","measurements.csv"].map { folder.appendingPathComponent($0) }
        for url in files { try Data().write(to:url) }
        var actions:[String]=[]
        let view=ProjectBrowserView(folder:folder,items:([child]+files).map { ProjectItem(url:$0) },canGoBack:true,isNavigating:false,kernelState:"Ready",interpreter:"/opt/miniconda3/bin/python3.12",
            onBack:{ actions.append("back") },onParent:{ actions.append("parent") },onNavigateFolder:{ _ in actions.append("navigate") },onChooseFolder:{ actions.append("choose") },onCreateFolder:{ actions.append("create") },onOpen:{ _ in actions.append("open") },onRename:{ _ in actions.append("rename") },onDuplicate:{ _ in actions.append("duplicate") },onDropFiles:{ _ in actions.append("drop") },onRefresh:{ actions.append("refresh") })
        let host=NSHostingView(rootView:AnyView(view.frame(width:220,height:620)))
        host.sizingOptions = []
        host.frame = NSRect(x:0,y:0,width:220,height:620)
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:220,height:620),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
        window.contentView=host
        func all(_ view:NSView)->[NSView] { [view]+view.subviews.flatMap(all) }
        for width in [220.0,170.0,390.0] {
            host.rootView = AnyView(view.frame(width:width,height:620))
            window.setContentSize(NSSize(width:width,height:620))
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until:Date(timeIntervalSinceNow:0.4))
            host.layoutSubtreeIfNeeded()
            precondition(host.bounds.width == width)
            guard let list=all(host).compactMap({ $0 as? NSTableView }).first else { preconditionFailure("Missing native file list") }
            precondition(list.numberOfRows == 4,"Project files missing from native list")
            precondition(actions.isEmpty,"Rendering the browser must not open/import/run files")
            guard let rep=host.bitmapImageRepForCachingDisplay(in:host.bounds) else { preconditionFailure("No native browser snapshot") }
            host.cacheDisplay(in:host.bounds,to:rep)
            let png=rep.representation(using:.png,properties:[:])!
            try png.write(to:URL(fileURLWithPath:"/private/tmp/pylab-project-browser-\(Int(width)).png"))
            print("PASS: \(Int(width))-point project browser rendered four files without opening/importing them")
        }
    }
}
