import Foundation

@main struct VariableScopeControllerChecks {
    @MainActor static func main() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("pylab-scope-controller-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let executable = temp.appendingPathComponent("fake-python")
        let script = """
        #!/opt/miniconda3/bin/python3.12
        import json, os, sys
        def emit(**message): print(json.dumps(message), flush=True)
        mode=os.environ.get('PYLAB_VARIABLE_MODE')
        emit(type='trace',text=json.dumps({'boot_mode':mode}))
        emit(type='ready')
        for line in sys.stdin:
            cmd=json.loads(line); kind=cmd['type']; scope=cmd.get('scope_id')
            if kind=='stop': break
            emit(type='trace',text=json.dumps(cmd))
            if kind=='workspace':
                rows=[['array','ndarray','2','[1, 2]',True,'cell-A','npy','NumPy',True,'cell-A'], ['array','ndarray','2','[3, 4]',True,'cell-B','npy','NumPy',True,'cell-B']]
                if mode=='shared': rows=[rows[0][:9]]
                emit(type='workspace',rows=rows)
            elif kind=='execute': emit(type='finished',id=cmd['id'])
            elif kind=='complete': emit(type='complete_result',request_id=cmd['request_id'],matches=['array'],cursor_start=0,cursor_end=1)
            elif kind=='table':
                emit(type='table',name=cmd['name'],scope_id=('cell-A' if cmd['offset']==99 else scope),requested_offset=cmd['offset'],offset=0,columns=['0'],indices=['0'],cells=[['3']],total=1,width=1)
            elif kind in ('edit','paste'): emit(type='edit',name=cmd['name'],scope_id=scope)
            elif kind=='export_as': emit(type='export_result',request_id=cmd['request_id'],scope_id=scope)
            elif kind=='plot': emit(type='plot_result',request_id=cmd['request_id'],scope_id=scope,result={'png':'YQ=='})
            elif kind=='statistics': emit(type='statistics_result',request_id=cmd['request_id'],scope_id=scope,result={'name':cmd['name'],'type':'ndarray','shape':'2','fields':[],'columns':[],'notes':[]})
            elif kind in ('rename','delete'): emit(type='manage_result',request_id=cmd['request_id'],scope_id=scope,result={'name':cmd['name']})
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions:0o700], ofItemAtPath: executable.path)
        let suite = "org.pylab.tests.scopes." + UUID().uuidString
        let preferences = UserDefaults(suiteName:suite)!
        defer { preferences.removePersistentDomain(forName:suite) }
        let kernel = KernelController(python:executable.path,preferences:preferences,variableMode:.independent)
        defer { kernel.stop() }
        var traces:[[String:Any]]=[]
        kernel.onEvent = { event in
            if event.type == "trace", let text=event.text, let data=text.data(using:.utf8), let value=try? JSONSerialization.jsonObject(with:data) as? [String:Any] { traces.append(value) }
        }
        func wait(_ condition: () -> Bool, _ reason:String) {
            let end=Date(timeIntervalSinceNow:8)
            while !condition() && Date()<end { RunLoop.main.run(until:Date(timeIntervalSinceNow:0.01)) }
            precondition(condition(),reason+" state:"+kernel.state)
        }
        func seen(_ kind:String, _ scope:String?)->Bool {
            traces.contains { $0["type"] as? String == kind && $0["scope_id"] as? String == scope }
        }
        precondition(kernel.variableMode == .independent && kernel.state == "Disconnected")
        kernel.setVariableMode(.shared)
        precondition(kernel.variableMode == .shared && kernel.state == "Disconnected", "Mode configuration started an idle kernel")
        kernel.setVariableMode(.independent)
        kernel.start(cwd:temp)
        wait({kernel.workspace.count==2},"Scoped workspace did not load")
        precondition(Set(kernel.workspace.map(\.id)).count == 2, "Same-name variables collide")
        precondition(kernel.workspace.map(\.scopeID) == ["cell-A","cell-B"])
        precondition(WorkspaceVariable.identity(name:"x",scopeID:"a:bc") != WorkspaceVariable.identity(name:"bc:x",scopeID:"a"))
        precondition(WorkspaceVariable.identity(name:"scope:1:a:x",scopeID:nil) != WorkspaceVariable.identity(name:"x",scopeID:"a"))
        kernel.loadTable(name:"array",offset:99,scopeID:"cell-B")
        wait({seen("table","cell-B")},"Table request was not scoped")
        RunLoop.main.run(until:Date(timeIntervalSinceNow:0.1))
        precondition(kernel.table == nil,"A stale table from another scope was accepted")
        kernel.loadTable(name:"array",scopeID:"cell-B")
        wait({kernel.table?.scopeID == "cell-B"},"Scoped table did not load")
        kernel.execute(code:"x=1",id:"cell-A",scopeID:"cell-A")
        var completed=false, exported=false, plotted=false, inspected=false, renamed=false, deleted=false
        kernel.complete(code:"a",cursorUTF16:1,scopeID:"cell-A") { matches,_ in precondition(matches==["array"]); completed=true }
        kernel.editTable(name:"array",row:0,column:0,literal:"7",scopeID:"cell-B")
        kernel.pasteTable(name:"array",row:0,column:0,values:[["8"]],scopeID:"cell-B")
        kernel.exportVariable(name:"array",path:temp.appendingPathComponent("array.npy").path,scopeID:"cell-B") { error in precondition(error==nil); exported=true }
        kernel.plotVariable(name:"array",scopeID:"cell-B") { data,error in precondition(data != nil && error == nil); plotted=true }
        kernel.inspectVariable(name:"array",scopeID:"cell-B") { stats,error in precondition(stats != nil && error == nil); inspected=true }
        kernel.renameVariable(name:"array",to:"other",scopeID:"cell-B") { error in precondition(error == nil); renamed=true }
        kernel.deleteVariable(name:"other",scopeID:"cell-B") { error in precondition(error == nil); deleted=true }
        wait({completed && exported && plotted && inspected && renamed && deleted},"Scoped callback did not complete")
        for kind in ["edit","paste","export_as","plot","statistics","rename","delete"] { precondition(seen(kind,"cell-B"),kind+" lost cell scope") }
        precondition(seen("complete","cell-A") && seen("execute","cell-A"))
        kernel.complete(code:"a",cursorUTF16:1) { _,_ in }
        wait({seen("complete","internal:console")},"Default independent request did not use console scope")
        let boots=traces.filter{$0["boot_mode"] != nil}.count
        kernel.setVariableMode(.independent)
        RunLoop.main.run(until:Date(timeIntervalSinceNow:0.1))
        precondition(traces.filter{$0["boot_mode"] != nil}.count==boots,"Selecting active mode restarted kernel")
        kernel.setVariableMode(.shared,cwd:temp)
        precondition(kernel.workspace.isEmpty && kernel.table == nil)
        wait({kernel.workspace.count==1 && traces.contains{$0["boot_mode"] as? String == "shared"}},"Changed mode did not restart with shared environment")
        kernel.execute(code:"x=2",id:"shared",scopeID:"ignored-in-shared")
        wait({traces.contains{$0["id"] as? String == "shared"}},"Shared request did not run")
        precondition(traces.first{$0["id"] as? String == "shared"}?["scope_id"] == nil,"Shared mode forwarded an independent scope")
        kernel.stop()
        print("PASS: scope mode configuration/restart, duplicate variable identity, stale-table rejection, and every scoped action/completion/execute protocol route")
    }
}
