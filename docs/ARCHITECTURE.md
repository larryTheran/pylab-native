# Architecture

## Native interface and project ownership

`ProjectTabsHost` retains one stable `Workbench` for each project ID. Switching a tab changes visibility/hit-testing rather than rebuilding its kernel or editor. A project owns a `KernelController`, `NotebookCollection`, console/history, workspace, figure gallery and pending execution state. Layout preferences are shared across project tabs.

SwiftUI composes panes, glass navigation, sheets and menus. AppKit supplies native text editing, file panels, workspace/Finder actions and process-related integration. `NativeCellEditor` uses an `NSTextView` and custom gutter; syntax, folding and editor preferences update the same native editor so selection and Undo can survive layout/theme changes.

## Kernel boundary

```text
SwiftUI / AppKit
      │ project commands, source, scope IDs
KernelController (Swift, Foundation Process + pipes)
      │ JSON lines
Resources/kernel_bridge.py (external selected Python)
      │ Jupyter shell / IOPub / stdin / control channels
IPython kernel process
      │ NumPy, pandas, Matplotlib, project modules
Workspace actions and notebook execution
```

Each project launches a bridge with the selected executable. The bridge starts its own IPython child using that executable, not an unrelated installed kernelspec. Stdin/stdout carry JSON-line messages; IOPub carries streams, errors, execution status and rich output. Controller state is published on the UI side. Request IDs correlate work without depending on the selected tab.

`KernelExecutionActivity` tracks queued/running/waiting phases, queued time and actual execution start. It clears on completion, interrupt resolution, stop or communication failure. Workspace requests, plotting and table edits have separate callbacks. The CPU/memory UI uses the actual IPython child PID; it does not queue measurements behind running notebook code.

## Namespaces and script context

Shared mode uses the project kernel's normal namespace. Independent mode activates a cell scope before its execution or completion request on the same shell channel; variable operations carry that scope. These namespaces share a process, modules, working directory and filesystem access.

Imported `.py`/`.pyw` cells retain their original filename in `pylab_script_path` notebook metadata. IPython pre/post-cell events temporarily apply `__file__`, `__name__ = '__main__'`, clean argv and the script's import location, then restore context. Raw source remains raw IPython input, preserving future imports, magics, top-level await and tracebacks. This context does not supply arbitrary CLI arguments and applies during the cell run, not to every future function call.

## Notebook storage

`NotebookStore` holds cell IDs, names, source, original JSON and rich output. Unknown metadata remains available on round-trip. Cell names use notebook metadata, while execution timers, breakpoints, live display registries and namespaces are transient. Saving validates JSON, checks the original file fingerprint, writes atomically and preserves symlink targets. `NotebookCollection` deduplicates open files by identity, including aliases.

The console's 256 KiB display tail is separate from notebook output storage. The communication buffer has a 128 MiB per-message guard, including fragmented input. The app does not promise arbitrary-size output or persistent kernel memory.

## Live display updates

The bridge preserves validated transient display IDs, update flags, full MIME bundles and metadata. Large PNG strings are transported once. `Workbench.receive` processes display updates before requiring an execution ID, allowing another cell or a later background update to refresh an existing handle.

`NotebookStore` maps a display ID to transient output slots; an update replaces data/metadata in those slots without appending. A `LiveFigure` observable object owns one latest PNG and decoded image shared by inline/open views. Gallery identity, zoom and initial size remain stable. Unknown update IDs do not create outputs. Text/unsupported updates remove stale inline images and mark retained image views as snapshots. Kernel restart detaches mappings; save/reopen keeps ordinary latest-frame output.

## Main source areas

| Files | Responsibility |
| --- | --- |
| `App.swift`, `ProjectTabs.swift`, `PyLabCommands.swift` | Project workbench, integration and commands |
| `Notebook*.swift`, `Cell*.swift` | Document/model, cells, layout, outputs and context actions |
| `PythonSyntax/Folding/Editing.swift`, `Editor*.swift` | Native editor behavior and appearance |
| `Kernel*.swift`, `EnvironmentInspection.swift` | Python process, requests, execution status and environment metadata |
| `Workspace.swift`, `VariablePlot.swift` | Inspection/edit/export/plot UI and figure gallery |
| `ProjectBrowser*.swift`, `ProjectSession.swift` | Files, safe drops, navigation and session persistence |
| `ConsoleDocking.swift`, `Workbench*.swift`, `PaneResizeHandle.swift` | Pane/dock geometry and status |
| `AppearanceToggle.swift`, `AppAppearance.swift`, `LiquidMotion.swift` | Native glass appearance and scoped motion |
| `Resources/*.py` | Jupyter bridge and validated workspace operations |

This separation keeps the solver or scientific project outside the UI repository. The companion FDTD project publishes bounded field planes through ordinary IPython display updates; PyLab does not own its numerical update equations.
