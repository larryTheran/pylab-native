# Development release history

This is the detailed pre-publication development record. Older artifact names and setup paragraphs are historical; use the current [README](../README.md) and [Quick start](QUICK_START.md) for version 0.7.3. Personal development folder examples have been normalized.

A new Apple Silicon macOS desktop application built with SwiftUI and AppKit. It uses native macOS 26 Liquid Glass controls and materials, a native notebook editor, and an IPython kernel running in a separate Python process. It is a separate app from the previous Qt version.

## New in 0.7.3: live plots during execution

PyLab now replaces an existing Jupyter display in place when Python updates its `display_id`. Inline previews, **Open Figure**, and **Figures** show the current PNG while the code continues running. Updates keep the editor's allocated space, the open figure's size and zoom, and the figure's identity. One updating plot occupies one output and one gallery entry. **Stop** interrupts the running code; the latest received frame remains available. The Live badge identifies a connected display handle, including handles that can be updated again by a later cell; it is separate from the Running indicator.

Save/reopen retains the latest frame as ordinary notebook output. Live display links are temporary and detach on kernel restart or interpreter changes, so old saved figures cannot be retargeted by a new kernel. Text or unsupported rich updates replace the inline MIME bundle; a gallery's last supported PNG is explicitly labelled Snapshot. SVG/HTML data are preserved without executing HTML. General Python loops can use `from IPython.display import display`, `handle = display(fig, display_id=True)`, and `handle.update(fig)`. See **Examples/Live Plot Demo.ipynb** for a short animation.

### This FDTD waveguide simulation

The local FDTD project at `/path/to/fdtd-python` now has a bounded live-preview callback in its 3D solver and a persistent six-panel Matplotlib renderer. The top row shows evolving XY/XZ/YZ Ez/Z0 sections; the bottom row shows the material sections. Step count, percentage, physical time and the sampled energy proxy accompany the plot. The three section arrays are copied only for published frames; no additional 3D field history is retained. The color scale uses the peak across the displayed sections over the run; final saved plots retain their existing scaling.

In a fresh PyLab kernel, the existing `38_waveguide_bend_3d` cell's `main(CONFIG)` automatically enables preview. **Save your notebook, quit the older app, open PyLab-Live-Plots.app, reopen your notebook if needed, and run the cell again.** A previously completed run does not become live retroactively. The new app uses the updated local FDTD modules when its kernel imports them. No CONFIG changes or source edits inside the open cell are required. The simulation's normal final PNG, data, diagnostics and optional GIF generation continue afterward.

The default cap is four intermediate previews per second, with a step stride of one; actual refresh depends on solver and rendering speed. Preview adds rendering overhead without changing the numerical update equations. Set `main(CONFIG, ["--live-fps", "2"])` for less overhead, add `"--live-stride", "5"` to limit eligible steps, or use `main(CONFIG, ["--no-live"])` to disable it. Maximum accepted FPS is ten. Terminal runs retain their existing default behavior; explicit `--live` requires a Jupyter/IPython kernel. `--no-plots` disables automatic live preview unless `--live` is explicit. Supply `--output` to choose another result folder when retaining a previous run for comparison.

This uses standard [Jupyter display updates](https://jupyter-client.readthedocs.io/en/stable/messaging.html#update-display-data) and [IPython display handles](https://ipython.readthedocs.io/en/stable/api/generated/IPython.display.html#IPython.display.DisplayHandle). The local FDTD implementation and tests are documented in that project's `docs/THREE_D.md`.

## New in 0.7.2: visible execution status

Running code now shows an amber activity spinner, elapsed time, **In [*]**, and a **Stop** button in its cell header. A subtle amber cell rim and activity icons on the cell, notebook, and project tabs keep execution visible when you select another cell or project. The console header and bottom status bar show the current project's activity as well.

Requests waiting their turn show **Queued** with a clock; their timer starts when Python begins execution. `input()` and debugger prompts show **Waiting for input** with a keyboard icon; enter the answer or debugger command in the console. Highlighted-code execution is attributed to its source cell. **Stop** interrupts the currently running code in that project's kernel. The controls return to idle when the kernel confirms completion, interruption, or failure. The last full-cell runtime remains visible afterward.

These indicators are temporary session state and are not saved in notebook files. They preserve the editor's text, selection, Undo history, and layout. With macOS Reduce Motion enabled, a static hourglass replaces the spinner.

## New in 0.7.1: imported-script execution context

Newly imported Python script cells remember their original filename in `pylab_script_path` metadata. While the cell runs, Python receives that `__file__`, `__name__ = "__main__"`, and `sys.argv = [original_filename]`, with the script directory available for sibling imports. This supports script startup code and avoids passing IPython's connection flags to `argparse`. The raw notebook code stays unchanged, so future imports, magics, normal tracebacks, and top-level await retain IPython behavior. Notebook variables remain in the current shared or independent namespace.

The temporary context restores after success, errors, input, and interruption. The working directory is unchanged; deliberate `sys.path` changes made by the script remain. Save/load and cell duplication retain origin metadata. Scripts imported in 0.7 or earlier have no recorded origin: reimport them once to enable automatic context, or keep a notebook-compatible startup path and explicit runner arguments. Reimport a moved script to update its original location.

Context applies during the cell's execution. Functions called later from ordinary cells that depend on global `__file__` should capture the needed location during definition or live in a normal imported module. Scripts requiring additional command-line arguments still need explicit values in their notebook code.

## New in 0.7: clearer workflow and editor controls

The public [PyLab site](https://www.getpylab.com/) highlights runtime status, resource visibility, file drop areas, and themes. This release adapts those workflow patterns to the existing native macOS design.

- **Persistent project status.** The bottom bar shows the selected Python environment, kernel state, outstanding executions and elapsed time, and notebook save state. Click the environment to choose Python or check its packages. A stopped or failed kernel exposes Restart; normal restart confirmation still protects live variables.
- **Python Activity.** Click the activity readout or choose **More → Kernel Activity** for recent CPU history and current resident memory of this project's IPython process. Samples arrive about every two seconds without queuing work behind running code. One fully used CPU core is 100%, so multithreaded code can exceed 100%. Readings are actual process usage, not whole-Mac totals, GPU controls, resource reservations, or CPU/RAM limits. Unavailable readings are identified explicitly.
- **Environment checks.** In **Python Kernel**, choose **Check Environment** to inspect Python version, architecture, and installed required/optional package versions. The check runs separately, can be canceled, and does not install packages or import large optional frameworks. If required packages are missing, **Copy Install Command** copies a command for the selected executable; it is not run automatically.
- **Faster file navigation.** The Project browser has a file filter, refresh, a folder menu with ancestor navigation and Copy Folder Path, plus Finder actions on files and folders. Drop local notebooks or Python scripts into the browser to open/import them; drop a folder on its own to navigate, or supported data files separately to import into the active workspace. Files are not copied or moved by a drop. In Independent Cells mode, data import targets the selected cell.
- **Import Python scripts.** Open `.py`/`.pyw` files through Open, the browser, a drop, or **More → Import Python Script**. Each becomes a new unsaved notebook containing one named, unexecuted cell. Saving uses `.ipynb`, leaving the original script untouched. Imports accept UTF-8 text up to 4 MiB and reject binary or oversized files; they do not execute the script.
- **Editor Appearance — Command–Comma.** Use the bottom-bar Editor control, **More → Editor Settings**, the app settings menu, or the command palette. Choose VS Code, Nord, or Solarized syntax colors, an 11–22 pt font, indentation guides, and the line-number/folding gutter. Settings are remembered and apply immediately to existing editors; code, selection, Undo, and folded functions remain intact. Colors adapt to Light/Dark appearance. VS Code colors and 13 pt remain the defaults.

The default `/opt/miniconda3/bin/python3.12`, native Apple Liquid Glass, project/notebook tabs, magnetic cell tabs, Shared/Independent variable modes, and cell context actions remain available. This release uses the selected local Python environment; it does not add Docker runtimes or automatic GPU configuration.

## New in 0.6.2: cell context actions

Right-click a cell tab, cell card, or code editor for **Duplicate Cell** and **Delete Cell**. Duplicate inserts a selected copy immediately after the clicked cell, with a new ID and unique copy name. Source, type, metadata, and Markdown attachments are retained; the new cell starts unexecuted, with no copied outputs, execution timing, breakpoints, or live variables. In Independent Cells mode, its fresh ID gives it a new namespace when run. Native code-editor menus retain normal text actions.

Delete targets the clicked cell and is disabled while it is running or queued. Removing the final cell leaves a blank cell so the notebook stays editable. Deleting a cell keeps the existing kernel variables until they are deleted or Python is restarted.

## New in 0.6.1: Show in Finder

Right-click any notebook tab and choose **Show in Finder** to open its containing folder with that notebook selected. Unsaved notebooks must be saved first. If a saved file has moved or been deleted, PyLab opens its original folder when available. The action uses the tab you right-clicked and keeps the current notebook selection and code intact.

## New in 0.6: shared or independent cell variables

Use the **Shared / Independent** menu beside the Workspace title to choose how the current project's variables behave. **Shared Variables** is the default: all notebook cells and the console use the same workspace, so a variable created in one cell is available to the others. **Independent Cells** gives each cell its own persistent Python namespace. Two cells can each define `x` without replacing each other's value; a name defined only in another cell is unavailable. Imports and definitions should be run in each cell that needs them.

In Independent Cells mode, the console and code completion follow the selected cell. The console header shows that cell's name. Workspace displays all cell namespaces, grouped under their notebook/cell names; same-named values remain separate when opened, edited, inspected, renamed, deleted, plotted, or exported. Data import and workspace MAT export use the selected cell's namespace. Renaming or reordering a cell retains its namespace for the current kernel session.

Changing modes asks before restarting Python and clearing live variables. Notebook code and saved outputs remain; rerun cells to populate the selected mode. To share calculations, choose Shared Variables and rerun the contributing cells in order. Existing independent namespaces are not automatically merged, avoiding ambiguous values when names conflict. Existing figure previews remain as snapshots after a mode change. The mode is remembered for each open project across app relaunches, and older saved sessions default to Shared Variables.

Independent cell namespaces use the same Python process and kernel. Imported module objects, the working directory, filesystem access, and other process state are shared; this option separates variable names rather than providing process or security isolation. Modes and live namespace contents are not written into `.ipynb` files, and live values still need export or rerunning after a restart.

## New in 0.5: reliability and data integrity

Notebook loading now validates editable fields before changing the open document, repairs invalid or duplicate cell IDs, and retains unknown metadata and rich outputs. Saving builds and validates a snapshot, then writes atomically; a failed save keeps the current source, path, and unsaved state. If a previously opened file changed or became unavailable outside PyLab, saving stops with an explanation. Use **Save As** to preserve your edits in another file, or close and reopen the notebook to load its latest version. Symlink aliases of an open notebook are recognized within a project so they cannot be opened or overwritten as separate tabs. Save and close actions commit the active name field before checking changes.

With a running kernel, folder navigation waits for Python to accept the new working directory before updating the browser and Back history. A pending change is visible in the sidebar. Failed changes leave the browser and history intact, and the acknowledged working directory is retained for kernel restarts and interpreter changes. When Python is stopped or unavailable, valid folders can still be browsed and the chosen folder is retained for the next launch. Kernel launch, connection, and unexpected-exit failures are surfaced, and unfinished operations are released so the interface can recover through Restart Kernel.

The transient console keeps its most recent **256 KiB** of UTF-8 text and displays a note when older text is trimmed. Clearing the console resets that note. Full notebook outputs are unaffected by this console display limit. Separately, a single incoming kernel message is limited to **128 MiB**, including fragmented messages, to keep a runaway or malformed response from growing the communication buffer indefinitely. Exceeding that limit stops the connection with an explicit diagnostic. Restart the kernel and reduce the size of individual outputs before rerunning the code; this guard does not truncate and save a partial notebook output.

Workspace data actions validate table coordinates, shapes, paste contents, and stale pages before editing. CSV exports quote commas, quotes, and embedded newlines correctly. Imported and renamed Python identifiers are normalized consistently with Python, with conflicts checked before changing the workspace. Mislabeled NumPy archives are rejected without importing an open archive object. Plot previews sample nested lists within bounds, and oversized list plots are rejected before a full array conversion.

Save notebooks regularly and export live values you need to retain. Session restoration reopens saved notebooks; it does not restore unsaved edits or a previous kernel's memory.

## New in 0.4: native glass appearance switch

The sun/moon switch at the right of the **Projects** bar changes the entire app between Light and Dark. Its raised glass cap slides between the two positions; the label shows the current appearance. The choice is remembered when PyLab reopens. Right-click the switch, or choose **View → Appearance** or **More → Appearance**, for **Use macOS Appearance**, Light, and Dark. The initial setting follows macOS; an explicit choice affects PyLab only.

Native title bars, sheets, file panels, notebook syntax colors, line numbers, and insertion cursors follow the same setting. Switching appearance retains the editor, its text, selection, and Undo history. Reduce Motion removes the cap's travel animation, Reduce Transparency uses an opaque control, and increased contrast strengthens its rim.

The control uses Apple's SwiftUI **`glassEffect`**, **`GlassEffectContainer`**, and **`glassEffectID`** APIs, including interactive native glass. The cap silhouette and highlights are custom SwiftUI shapes; Apple's framework renders the glass material. Project tabs are also grouped in a native glass container. See [Apple's Liquid Glass guidance](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views).

## New in 0.3: responsive editing, magnetic tabs, and console docking

Cells fill the notebook pane with adaptive margins. Cell Tabs expands the selected editor into the available space. All Cells keeps short cells compact, and narrow windows use compact headers. The selected editor, cursor, and Undo history survive switching cell layouts; the selected cell remains visible. The window can shrink to 820 × 540 points, with side-pane widths adapting around the notebook.

### Keep code visible with plots

Cell Tabs reserves about **68% of its usable content space for code** by default. Images and long logs use a bounded output pane with its own scrollbar, so their natural size cannot squeeze the editor. Drag the separator above Output to change the split, or right-click it for More Space for Code, Default Split, and More Space for Output. Hide collapses outputs; Show restores them. All Cells also caps the output area at a sensible height. These choices affect presentation, leaving complete notebook outputs unchanged.

Plots fit inside the output preview without cropping. Choose Open Figure or double-click the image to inspect the complete snapshot with zoom and PNG export. Decoded images are retained during live resizing instead of being decoded on every drag update.

### Magnetic tab management

Project, notebook, and cell tabs use native drag-and-drop with magnetic target feedback. A valid destination gets a subtle glass lift and highlighted rim; releasing settles the reordered tabs with a short spring. Hovering never changes document order, and canceled or unrelated drops leave it intact. Selection pills glide between tabs, while Reduce Motion keeps them static. The native magnetic behavior is retained; pointer-following tab movement has been removed. Cell cards can still be moved by their header handles in All Cells mode.

### Place the console

The command console starts **below Workspace**, keeping the notebook tall. Drag the terminal label or grip in the console header to reveal three glass docking targets: Below Workspace, Below Notebook, and Across Bottom. The highlighted target previews the destination; release to dock. The console's placement menu offers the same choices without dragging. The position is remembered and shared between project tabs, while each project keeps its own console, history, and live kernel. When Workspace is hidden, a console assigned below it temporarily appears below the notebook.

Divider tracking stays attached to the pointer. Deliberate expansion, placement, and reorder changes use short settled transitions. Reduce Motion disables spatial transitions and tab scaling while retaining subtle highlight fades. Navigation controls use native glass; code content keeps a readable standard material.

Try `Examples/Analysis Workbench.ipynb` for an analysis workflow, or `Examples/Output Layout Demo.ipynb` to inspect the code/output split with a saved large plot.

## New in 0.2: analysis power tools

- **Command palette — Command–Shift–P.** Search commands instead of navigating menus. Exact command titles rank first; use Up/Down and Return to choose. Commands affect the active project.
- **Find in Notebooks — Command–F.** Search code and named cells in the current notebook or all open notebooks in the project. Match Case is optional. Results show notebook, cell, and line; Return or Go to Cell opens and focuses the matching line, including folded code. The list is limited to 200 results; narrow your query to find more.
- **Run highlighted Python — Command–Return.** Highlight statements to execute only that selection in the shared project kernel. Output appears in the console, and new variables retain the source cell's workspace group. Common leading indentation is removed. Without a selection, the full cell runs. Shift–Return and the Run Cell button always run the full cell. Right-click Run Selection is also available.
- **Faster editing.** Return preserves Python indentation and indents supported block headers; Tab/Shift–Tab indent/outdent, and Command–/ toggles comments. These edits use native Undo. Automatic block indentation handles single-line headers; multiline signatures may need manual indentation.
- **Inspect Statistics.** Right-click a workspace variable for type, dimensions, memory, count, missing/infinite counts, min/max, mean, and population standard deviation where supported. Numeric NumPy arrays, pandas numeric columns, and numeric scalars are supported; complex arrays report magnitude statistics. Large arrays use the first 100,000 elements; tables use up to 32 numeric columns with at most 100,000 values total. Sample limits are displayed explicitly. Memory estimates exclude deep Python object storage.
- **Rename or delete live variables.** Right-click a workspace name. Renaming validates the new Python name, refuses conflicts, retains aliases and cell attribution, and leaves notebook text unchanged. Update your code references yourself. Delete asks for confirmation and removes only that name; rerun code to recreate it.
- **Run Selected and Below, Save All Notebooks, Clear Notebook Outputs.** Available in More and the command palette. Save All saves changed notebooks in the active project and stops if a save is canceled or fails. Clear Outputs keeps code and live variables and is blocked while that notebook's cells are running.
- **Unified figure gallery.** PNG figures emitted by notebook cells and the console join workspace plots under Figures. Keep up to 50 recent previews per project; notebook inline outputs remain saved separately. Code-generated figures are snapshots, with PNG and image-PDF export. Workspace plots retain their existing label/limit controls and vector export from current workspace data. Gallery previews are session-only.

Try `Examples/Analysis Workbench.ipynb` for a small signal-analysis workflow using shared arrays, pandas tables, functions, and plotting.

## Open and use

Open the supplied `PyLab-Script-Context.app` beside this source project on macOS 26 or later, or build `dist/PyLabNative.app` below. It automatically starts `/opt/miniconda3/bin/python3.12`, the scientific Python installation already on this Mac. Wait until the sidebar says **Ready**. The kernel environment must include `jupyter_client`, `ipykernel`, `numpy`, `pandas`, and `matplotlib`. Use the **Python Kernel** toolbar button or **More → Choose Python Kernel…** to enter or browse for a different Python executable; your selection is remembered. The default is `/opt/miniconda3/bin/python3.12`. Enter a virtual-environment path directly to preserve symlinks. Switching kernels stops running code and clears live variables after confirmation, while notebook cells and outputs remain. For a launch-only override, set `PYLAB_KERNEL_PYTHON` before launching from Terminal.

Open the previous `.ipynb` notebook using the **Open** toolbar button. The project sidebar's folder button chooses the working folder; selecting a folder changes the kernel working directory as well. The back arrow returns to the previous folder, and the up arrow opens its parent. Notebook cells and console commands use one live kernel. In Shared Variables mode, a variable created in one cell is immediately available to other cells and the console, regardless of its workspace group. Independent Cells mode keeps names separate and directs the console to the selected cell. Variables are live memory and do not survive a kernel restart unless exported or recreated by rerunning cells. Python code cells use VS Code-inspired syntax colors that adapt to light and dark mode. Shift–Enter runs a cell. Edit the name field in a cell header to name it; names are saved in each cell’s notebook metadata. Choose **All Cells** to expand the notebook or **Cell Tabs** to show one named cell at a time. The tab strip scrolls horizontally, and its plus button adds a new named cell. Drag a tab to reorder cells, or drag the handle in a cell header in All Cells view. The order is saved in the notebook. Use the cell’s plus and trash buttons to add or remove cells; the toolbar and More menu provide run, save, interrupt and restart controls. The live workspace uses a compact MATLAB-style table with Name, Value, Size, and Class columns, grouped by the cell that last created, assigned, or visibly changed each variable. Console variables appear separately. Filter or sort the rows, and double-click a supported array or table to open the paged editor. Right-click a variable to choose **Save As…** or **Plot** when supported. Edits use Python scalar literals and commit on Return.

The app supports notebook version 4 and preserves metadata and pre-existing rich outputs. Run `Examples/Welcome.ipynb` to try the interface. Unsaved notebook changes are checked when closing a notebook, project, window, or the app. Save your notebooks before switching app versions; live variables still need export or rerunning code.

Workspace exports are chosen by type: NumPy arrays use `.npy` without pickle, pandas DataFrames and Series use `.csv` including the index, strings use `.txt`, and JSON-compatible scalars, lists, and dictionaries use `.json`. Some values (such as object arrays, unsupported custom objects, non-finite numbers, or nested values that cannot be represented as JSON) cannot be exported in these formats. The save dialog lets you choose the destination and confirms replacement of existing files. Plotting accepts real numeric scalars, one- or two-dimensional arrays and lists, Series, and the numeric columns of DataFrames. It opens a separate figure preview, with an option to save a PNG; plots are limited to 20,000 rows and 32 columns.

In Shared Variables mode, cell attribution is best-effort: the app tracks object changes, explicit assignments, and common in-place operations. A mutation hidden inside a function, dynamic code, magic command, or an alias may not be detected. A variable's section represents its latest detected assignment or mutation, not a complete history. Renaming a cell updates its group heading; values from deleted cells remain under **Other / deleted cell**. Workspace values that cannot be attributed appear under **Other / untracked**. In Independent Cells mode, workspace groups identify the owning cell namespace instead of the latest shared assignment.

The supplied `PyLab-Variable-Modes.zip` contains the app, Quick Start instructions, and example notebooks.

## Build with Xcode

Install the Xcode command-line tools and select Xcode, then run:

```sh
cd /path/to/PyLabNative
./scripts/build.sh
open dist/PyLabNative.app
```

You can also open `Package.swift` in Xcode to edit and build the Swift sources. The script creates an arm64 app bundle and copies the Python bridge into its resources. If Xcode is installed but not selected, prefix the build with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

For kernel tests, use the same scientific Python environment:

```sh
/opt/miniconda3/bin/python3.12 tests/test_bridge.py
/opt/miniconda3/bin/python3.12 tests/test_interrupt.py
/opt/miniconda3/bin/python3.12 tests/test_shared_workspace.py
/opt/miniconda3/bin/python3.12 tests/test_workspace_origins.py
/opt/miniconda3/bin/python3.12 tests/test_workspace_actions.py
/opt/miniconda3/bin/python3.12 tests/test_workspace_actions_bridge.py
```

## Design and scope

The desktop interface and controls are native SwiftUI and AppKit, including Apple's `glassEffect`, `GlassEffectContainer`, `glassEffectID`, glass button styles, and system materials. A small Python JSON-lines bridge uses Jupyter's client protocol to launch and communicate with a separate IPython kernel. No Qt or browser shell is used for the interface. The built app requires an external scientific Python installation; bundling a relocatable Python runtime, Developer ID signing, and notarization are future distribution work.

The console accepts one-line commands and provides session command history. Editor completions use Control–Space. Figures display inline in notebook cells and are retained in the session figure gallery, including console-generated plots. HTML/JavaScript widgets and full JupyterLab extensions are not rendered. The workspace editor displays up to 100 rows per page and the first 30 columns of supported one- or two-dimensional NumPy arrays and pandas tables. Output from unsupported rich formats is preserved when opening and saving existing notebooks. Restart clears live variables. Running notebook code has the normal file and network access of your user account.

### Working with multiple projects

Use the **+** button in the Projects bar to open another folder in a new project tab. Each tab keeps its own notebook, folder, console, and running Python kernel, including its own live variables. Switch tabs to return to a project without interrupting its kernel. Save each notebook separately. Closing a project stops its kernel; PyLab warns before closing a project with unsaved notebook changes, live variables, or running code. Saved project and notebook tabs are restored when the app reopens.

### Notebook and project tabs

Use the plus beside the notebook tabs to create another notebook in the current project. Opening a notebook from the project browser or toolbar adds a tab; opening one that is already open selects it. Save each notebook separately. All notebooks in one project use its Python kernel; different projects have separate kernels. Shared Variables uses one namespace for all cells, while Independent Cells keeps each cell’s names separate. Workspace groups show the owning cell in independent mode or the latest detected assignment in shared mode. Drag project or notebook tabs to reorder them, or right-click a tab and use the Move commands. Closing an unsaved notebook asks for confirmation. Saved project and notebook tab arrangements are restored after quitting.

### Python editor

Python cells show syntax colors, line numbers, indentation guides, and fold arrows beside supported function, class, and control-flow headers. Click an arrow to collapse or expand a block. Folding changes only the view: running and saving use the complete code. Editing while blocks are folded expands them before applying the edit; clicking inside a folded placeholder expands it without deleting the hidden code. Initial folding supports single-line Python block headers.

### MATLAB-style workflow

- The More menu provides **Run Cell and Advance**, **Run All Above**, **Run All Cells**, **Debug Selected Cell**, MAT import/export, and **Reset Layout**. Cell headers show when a cell is running and how long its last run took.
- Click the line-number side of a Python gutter to toggle a breakpoint. Start **Debug Selected Cell**, then use Step, Next, Continue, or Stop in the console. While paused, use Python debugger commands such as `p variable` to inspect values. The workspace table refreshes after execution resumes. Breakpoints are temporary and are cleared when a cell is edited. Debugging executes Python code, not IPython magic commands.
- Press Control–Space in a Python cell for completions from the current kernel. Expand folded code before requesting completion.
- The command console has command history; use the history button or the up/down arrow keys. History is kept during the project session.
- Project tabs, saved notebook paths, selected saved notebook, and pane sizes are restored at launch. Save every notebook before quitting; unsaved text, kernels, and live variables are not restored.
- The variable editor supports multiple variable tabs, filtering and sorting the current page, and copying displayed values. To paste a tab-separated block, right-click the destination cell and choose Paste Table Starting Here; use Python scalar literals, including quotes for strings. The entire block is validated before updating the live variable. Clear any filter or sort before pasting. Right-click a column header to plot that column. Editing remains positional even while sorted or filtered.
- Workspace figures can be revisited through More > Figures. Figure previews support fit, zoom, scrolling, editable titles, axis labels and limits, legend controls, an exact zero-based data-index marker, PNG export, and vector PDF/SVG export. Figures remain available while the project is open. Vector export regenerates from the current workspace data using the last applied figure settings.
- More > Import Data supports MAT, NPY, CSV, and Excel files. Import refuses to overwrite existing workspace names. MAT import requires SciPy and accepts v7 and earlier files supported by `scipy.io.loadmat`; v7.3/HDF5 files are not supported. Excel requires a pandas Excel engine such as openpyxl, which must be installed in the selected Python environment. Workspace export to MAT supports numeric scalars, strings, and non-object NumPy arrays and reports skipped values. Right-click an array or table to export it in a supported individual format.
- The project browser offers New Folder, Rename, and Duplicate. Close any notebook inside an item before renaming it.

Try `Examples/Variable Sharing Demo.ipynb` to compare the modes: run Alpha and Beta, then select each cell and enter `print(x)` in the console. Independent mode keeps 10 and 20 separate; shared mode uses the latest assigned value.

Script context uses IPython’s documented [pre/post cell events](https://ipython.readthedocs.io/en/stable/config/callbacks.html), preserving normal notebook execution.
