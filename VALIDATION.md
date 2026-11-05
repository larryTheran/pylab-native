# Workspace and kernel selection validation

The arm64 app was compiled with Xcode's macOS SDK. The SwiftUI workspace was inspected with real NumPy, pandas, scalar, string and list variables; Name, Value, Size and Class were visible, and a DataFrame opened in the table editor. The kernel selector displayed `/opt/miniconda3/bin/python3.12` by default, rejected a nonexistent executable, and displayed a confirmation before switching kernels.

Real-IPython tests passed for notebook execution, inline PNG plots, workspace summary values and dimensions, NumPy array editing, deferred output clearing, interruption, and kernel-process cleanup. An isolated Swift test checked interpreter persistence and rejection of invalid paths. Summary previews are bounded; large arrays are not expanded in full.

This is an ad-hoc-signed development app for macOS 26 or later. It uses a separately installed Python environment. The current app warns before closing a window with unsaved notebooks; live kernels and variables are not restored.

# Named cells and tabs

The notebook-model round-trip check passed for named and unnamed cells, metadata, rich outputs, duplicate labels, selection, and deletion. The integrated native app and Xcode Swift package built successfully. A separate macOS test window displayed the named tab strip and a ready Miniconda kernel. Switching to All Cells and back to Cell Tabs retained the selected cell and its name. The original `.app` in `dist` is the older version; the updated build is provided separately as `PyLab-Named-Cells.app`.

# Shared workspace, exports, and plots

Real-IPython checks passed for variables shared between notebook cells and the console; ordered execution; grouping after assignments, in-place changes, exceptions and deletes; and collision-safe source IDs. Export checks passed for NPY, CSV, TXT and JSON, overwrite handling, and malformed or unsupported values. Plot checks passed for numeric scalars, arrays, lists, Series and DataFrames, including PNG rendering without changing pyplot's active figure. The same save, scalar plot and shared-workspace checks passed against the resources inside the packaged app.

In a separate native GUI preview, variables appeared under their named cells, renaming a cell updated the heading, and a right-click on an array offered Open Variable, Save As and Plot. A `.npy` saved through the app was loaded and its values verified. Grouping is best-effort for complex side effects and is not a complete provenance history.

# Project folder navigation

Verified in a separate native test window: selecting Documents updates Python's working directory, Back returns both the browser and kernel to the preceding folder, and the parent-folder control opens the parent. The arm64 app and Swift package compiled successfully. The current user's existing notebook was not closed or modified.

# Version 0.2 power tools

The integrated arm64 macOS app built successfully using Xcode. Focused Swift checks passed for search (cell identity, matching lines, Unicode, case, limits), command filtering/ranking, Python editing (indentation, comments, UTF-16 positions, selection dedenting), notebook collections, and notebook save/reopen metadata. A native editor harness verified Undo and selection mapping with folded code.

Real IPython regression checks passed for the new numeric summaries, validated rename/delete operations, ownership-preserving selected-code execution, aliases, nullable pandas columns, complex arrays, strided/empty arrays, bounded samples, and very large finite values. Existing shared-notebook, workspace action, completion, debugger, table-paste, and MAT exchange checks were also run.

In a separate native GUI test window, Command–F opened notebook search before using More; filtering and arrow-key navigation focused the matching cell and line. Command–Return executed only a selected assignment while a following deliberate exception was not executed; the new variable appeared under its source cell. The numeric inspector displayed the correct live name, count, min/max, mean, and standard deviation. Console plotting added a preview to Figures, whose image was inspected visually. Early GUI findings (stale inspector state, lazy menu shortcuts, and selection shortcut interception) were corrected before packaging. Save All opened the save dialog from the command palette; cancellation retained the unsaved notebook and its code. The notebook was then saved through the toolbar into the temporary test folder. After native menu registration was completed, Command–S persisted a further edit, verified by reading the saved notebook. Multi-notebook save iteration and failure paths have been reviewed in code, rather than exhaustively exercised in the GUI.

Distribution remains an ad-hoc-signed development build for Apple Silicon and macOS 26+, using an external scientific Python installation. Code-generated gallery images are snapshots; vector regeneration is available only for supported workspace plots. Numeric summaries of large datasets are explicitly bounded samples, not whole-dataset statistics.

# Version 0.3 responsive layout, outputs, magnetic tabs, and console docking

The full arm64 macOS26 app compiled with selected Xcode. Pane sizing checks cover all sidebar/workspace visibility combinations from 820 to 2400 points, preserving a 360-point notebook minimum. The console placement model passed 480 combinations covering window sizes, all three positions, visibility, bounds, nonoverlap and Workspace-hidden fallback. Below Workspace is the initial position; placement is persisted and shared between projects.

The native NSHostingView/NSTextView test resized the single-cell viewport from 1100×760 to 420×360, with the no-output editor changing from 1030×656 to 372×247 while retaining source and clipping. A 1200×4000 PNG and a 5,000-line log retained identical bounded output geometry; the large editor stayed over 400 points high. The default split gives code about 68% of usable cell content space. Layout tests passed fraction clamps, collapsed-space recovery and compact-window bounds. The selected editor, cursor and Undo survived changing layouts, including a seven-cell notebook with the last cell selected.

The final version restores native magnetic drag-and-drop for all three tab types, as requested. Private drag-session tests passed per-container/single-use-token validation, canceled-provider cleanup, malformed/foreign/stale/replayed drop rejection, hover-without-reorder, and preserved selection/identity. Pointer-following code and its tests were archived outside the product source. Tab selection-pill and cell selection-rim motion are scoped to their navigation/border elements and respect Reduce Motion; editor text does not animate while typing.

Console drag-state tests passed per-project/per-window token validation, non-mutating hover, canceled/foreign/malformed/replayed payload rejection, provider cleanup, persistence and reentrant-safe single commits. Static review confirmed docking changes stable sibling pane rectangles without changing notebook selection or calling kernel lifecycle functions. The optional full-Workbench identity harness encountered an SDK macro-plugin issue; the actual product build and targeted native notebook tests passed. An end-to-end console docking mouse test was not performed because the user was actively using the preview window; that window and its live code/kernel were left open.

Code-generated output snapshots have bounded aspect-fit previews and full-figure sheets. Their decoded PNG images are retained during resizing. Complete output JSON and text remain unchanged by collapse or resizing. Narrow figure and console headers use compact layouts. Reduce Motion disables spatial transitions and tab scaling; the system accessibility preference itself was not changed during tests.

Motion follows Apple's Human Interface Guidelines: https://developer.apple.com/design/human-interface-guidelines/motion . Native glass is confined to navigation and controls, and code cards keep standard materials.


# Version 0.4 appearance and native Liquid Glass

The integrated arm64 macOS app built successfully with selected Xcode. The appearance control uses SwiftUI's native interactive `glassEffect`, grouped in `GlassEffectContainer`, with stable `glassEffectID` values; project tabs also share a glass container. Native framework symbols were verified in the linked executable. The sun/moon control was inspected in offscreen Light and Dark previews. Its cap uses a convex native glass lens masked to the custom silhouette to avoid rendering artifacts. Labels and icons remain above the shared glass pass.

`tests/test_appearance_settings.swift` passed with an isolated UserDefaults suite and injected appearance callback. It covers first-launch System behavior, initial application, no-op selection, saved and restored Light/Dark preferences, invalid-value fallback, and toggling from either system appearance. It does not modify the user's stored preferences or macOS appearance.

`tests/test_native_appearance.swift` passed in a separate native process. Switching Aqua → Dark Aqua → Aqua → System refreshed an existing NSTextView and gutter while retaining the same editor instance, source, cursor, focus, saved state, and Undo history. A single Undo still restored the original text, confirming that appearance changes were not inserted as edits. Code review confirms the appearance action applies an app-only NSApplication override and does not invoke kernel controls or rebuild notebook identities.

Reduce Motion, Reduce Transparency, and increased-contrast branches are implemented in the control; the user's system accessibility settings were not changed during validation. The app remains a development build for Apple Silicon and macOS 26+, with an external scientific Python installation.


In the isolated `org.pylab.appearancecheck` GUI, Light appearance was observed across the interface. A cell assigned `theme_probe = 42` and printed `Theme check: 42`; Shift–Return executed it as In [1], and the workspace showed the value 42. Switching to Dark retained the ready kernel, execution count, source, output, and workspace value. Python syntax colors and line numbers remained visible. Right-clicking the switch displayed Use macOS Appearance, Light, and Dark. Selecting System was covered by the model/native tests; its selection was not confirmed in this GUI session.


# Version 0.5 reliability and data integrity

Read-only integration review covered the bounded console model and its use in the command console, acknowledged folder navigation, saving, and notebook closure. The console retains a Unicode-safe tail of at most 256 KiB plus its visible trim notice. Notebook output storage uses a separate path and is not trimmed by the console model.

`tests/test_console_log.swift` passed after compilation with Xcode, covering bounded appends, a huge single write, Unicode boundaries, the visible trim notice, and clear/reset behavior.

`tests/test_notebook_robustness.swift`, `test_notebook_names.swift`, and `test_notebook_collection.swift` passed. Checks cover transactional malformed-file handling; repaired unique cell IDs; failed writes and invalid JSON without changing the live notebook; external edits and deleted-original conflicts; symlink and hardlink alias recognition; preserving a symlink when saving its target; retained selection after deleting another cell; and transient-state cleanup. The collection test also passed same-file, symlink, and hardlink load deduplication while preserving an existing dirty store. A JSON writer crash with non-finite output was reproduced, then prevented by validating the snapshot before Foundation's writer.

`tests/test_kernel_failures.py` passed with a separate actual Jupyter kernel: malformed plot/chdir/completion/execution requests returned correlated errors; successful and rejected working-directory changes were acknowledged; and `os._exit(9)` caused child-death detection and prompt bridge exit even while stdin remained open. Existing `test_bridge.py`, `test_interrupt.py`, `test_completion.py`, and `test_debugger_input.py` passed, including deferred output clearing, interruption, input/debugger behavior, and child cleanup.

`tests/test_kernel_lifecycle.swift` passed with isolated native/fake-bridge fixtures. It verifies that an acknowledged folder survives restart, a rejected folder does not replace the previous restart directory, non-finite JSON is rejected without a crash or state change, and crashed/fatal kernels clear live workspace/table/input state while completing pending actions and executions exactly once. Disconnected execution also completes with an error. Framing fixtures verify fragmented input and both complete and unfinished oversized messages using a small test bound. Production uses a 128 MiB per-message diagnostic limit, separate from the console display's 256 KiB tail.

`tests/test_workspace_validation.py` passed nine isolated regressions: lossless quoting of string-array CSV fields; usable normalized import names and collision checks; normalized rename handling; all-or-nothing MAT name validation; rejection of mislabeled NPY/NPZ input; bounded list conversion; invalid cell coordinates without mutation; malformed paste without partial changes; and recovery from a stale table page. It extracts the same table helper definitions used by the bridge without starting a user's kernel.

Existing `test_workspace_actions.py`, `test_data_exchange.py`, and `test_mat_exchange.py` passed. Separate live-kernel runs of `test_table_paste.py`, `test_workspace_actions_bridge.py`, and `test_workspace_summary.py` passed, covering array/table alias identity, paste validation, correlated export/plot responses, file replacement protection, and bounded summaries. These checks used isolated temporary folders and Python sessions.

The release retains the native Apple Liquid Glass appearance control and the existing magnetic tab behavior. There is no claim of automatic crash recovery or recovery of unsaved notebook edits or live Python variables. Distribution remains a locally signed development app for Apple Silicon and macOS 26+, using an external scientific Python environment.


Final native editor regressions passed against the updated notebook model: `test_native_appearance.swift` preserved editor identity, source, cursor, focus, dirty state, and Undo across Light/Dark/System. `test_native_notebook_layout.swift` retained bounded code/output geometry for a 1200×4000 PNG and a 5,000-line log, and preserved editor identity, Undo, and the selected last cell across layouts. Tests used separate native processes.

The final kernel lifecycle check also passed offline folder selection without starting Python, rejection of missing folders and regular files, and restart in the selected offline folder. The running-kernel path still requires an acknowledged directory change.

In the isolated 0.5 native GUI check, Shift–Return ran a cell and displayed `Reliability check: 42` with the live workspace variable. Parent navigation changed the browser to `/Users`; a console command then reported `Working folder: /Users Shared value: 42`, confirming the browser/kernel directory and shared cell/console namespace. The user's existing PyLab sessions were not closed or edited.

The final integrated 0.5.0 arm64 app, including offline navigation, frame bounds, and restore deduplication, built successfully with Xcode. Its local code signature verified.


# Version 0.6 variable sharing modes

The first integrated arm64 app build passed with the new mode setting, scoped controller routing, project session persistence, workspace controls, and scoped plot metadata. `tests/test_project_session.swift` passed migration of older sessions to Shared Variables, mixed per-project mode round trips, and fallback for unknown future modes. Scoped native controller protocol checks and the existing native lifecycle regression passed; the protocol checks cover distinct same-name identities, scope routing, table reply matching, and mode startup/restart behavior.

Read-only integration review confirmed that full-cell execution, selected-code execution, debugging, completion, console commands, data import/export, and variable actions forward their intended namespace. Gallery selection uses the composite variable identity and matches tables by both variable name and scope. Mode changes require confirmation before clearing live variables; existing figures become snapshots to prevent regeneration from a different workspace with the same name.

`tests/test_workspace_modes.swift`, an isolated NSHostingView workspace harness, rendered two same-named `x` variables under Alpha and Beta at 390- and 260-point widths. The native table retained four distinct rows (two section headings and two values). The normal-width header displayed Independent; the 260-point header used the compact icon without overflow. Narrow table columns keep the existing horizontal scrolling behavior. Offscreen native snapshots were written to temporary files. The SDK emitted an NSTableView reentrant-delegate warning in this harness without a crash. The user's existing app windows and kernels were not touched.

Independent mode is namespace separation within one kernel process; shared imported modules, working directory, and process state are not isolated. No live merge of existing namespaces is performed when switching modes.


Final 0.6 backend validation: `tests/test_cell_namespaces.py` passed against actual Jupyter/IPython. Coverage includes same-name globals/functions/classes, queued execution, independent In/Out caches, selected and fallback console namespaces, aggregate duplicate variable names, scoped table edit/paste/export/plot/statistics/rename/delete/completion, selected-source ownership, native magics, PNG output, input, top-level await, reset, and import. Existing `test_shared_workspace.py`, `test_multi_notebook_kernel.py`, `test_bridge.py`, and `test_debugger_input.py` passed with shared mode unchanged.

`tests/test_variable_scopes_controller.swift` passed mode configuration/restart and no-op behavior, scope-aware protocol routing, unique scoped identities, stale table response rejection, console fallback, and shared-mode routing. The existing kernel lifecycle regression passed against the new controller. `tests/test_project_session.swift` passed legacy-session shared defaults, per-project mode restoration, and unknown-future-mode fallback.

The final integrated 0.6.0 arm64 build passed with the mode-aware console banner and final compact Workspace header. The local code signature verified. No active user PyLab session was closed or changed during validation.


# Version 0.6.1 notebook location

The integrated arm64 native app built successfully and its local code signature verified. Independent code review confirmed that Show in Finder targets the right-clicked notebook tab, is disabled for unsaved notebooks, and does not change selection, save files, or alter code. Existing saved files use NSWorkspace.activateFileViewerSelecting; missing files fall back to an available parent folder, with an error when that folder is unavailable. This small reversible action was verified by build and code review; Finder interaction was not automated.


# Version 0.6.2 cell context actions

The integrated native arm64 build passed and its local code signature verified. `tests/test_cell_actions.swift` passed copy semantics for code/Markdown/raw cells, preserved metadata and attachments, fresh unique IDs and copy names, insertion/selection, original-cell preservation, unexecuted copies without runtime state, save/reopen, missing-ID no-op, deletion selection, and last-cell fallback.

`tests/test_native_cell_actions.swift` passed with a separate native view harness: editor menus retain standard Copy/Paste and Run Selection; repeated menus contain one copy of each action; duplicating an inactive cell targets that cell and selects its adjacent copy; running-cell Delete is disabled and protected against direct action dispatch; completed-cell deletion preserves another selected cell and the duplicate. Independent review confirmed shared menu wiring on cell tabs and cards. No user application sessions were changed.


# Version 0.7 workflow, runtime visibility, and editor settings

The first integrated arm64 native build passed with the status bar, environment/activity surfaces, Project browser, script importer, and editor settings. Read-only integration review confirmed that the native settings sheet and Command–Comma use the shared editor model, while opening scripts creates unsaved notebook stores with no original `.py` save destination. The script-import regression passed the bounded UTF-8 import path.

`tests/test_editor_preferences.swift` passed persisted defaults/reset, finite font-size bounds, no-op updates, invalid-value fallback, and Light/Dark palette coverage. `tests/test_native_editor_preferences.swift` passed live updates to two existing native editors; source, focus, cursor, dirty state, and text Undo were retained. Hiding indentation guides kept Python comment actions enabled. Enlarged gutters fit line numbers, and folded code survived font/palette/gutter changes and reset. Existing `test_native_appearance.swift` and `test_native_cell_actions.swift` passed against the updated editor, preserving application appearance behavior and clicked-cell context actions. Tests used isolated defaults and separate native processes, without changing the user's open application.

The runtime readout measures the actual Python kernel process, with CPU expressed as 100% per busy core and memory as current resident usage. Environment checks inspect package metadata and only copy installation commands. No automatic package installation, Docker/GPU runtime configuration, or resource-limit enforcement is claimed. Browser drops and script import retain the established Shared/Independent scope routing.


Runtime validation reported passing `tests/test_runtime_environment.swift`, `tests/test_kernel_activity.swift`, and `tests/test_kernel_activity_bridge.py`: native process readings and per-core CPU calculations, bounded history and PID reset, timer cleanup, environment metadata and shell quoting, invalid/malformed/noisy probes, timeout/cancellation, stale-result rejection, and additive real-kernel activity metadata. Existing kernel lifecycle and backend regressions also passed. Project browser file-location decoding checks passed; browser visual validation is recorded separately by the release.

An isolated status-bar rendering harness used fixture process readings to exercise Ready, Busy, and failure states at 820- and 1450-point widths. All six layouts stayed 30 points high, with outstanding executions, elapsed time, environment, save state, CPU/memory, and editor controls present. The Busy snapshots were visually inspected and fit within the bar. This checks component layout with fixture data, rather than measuring or interacting with a user's running app.


Final 0.7 integration checks: the command-palette regression passed after adding Editor Settings, Import Python Script, and Kernel Activity. Script-import checks passed UTF-8/BOM preservation, original-file preservation, no execution, symlink import, and rejection of oversized, binary, remote, and special-file inputs. Special files are opened nonblocking and rejected by descriptor type before reading.

A native sidebar regression exposed a real parent-folder traversal loop for Foundation temporary/base URLs. Sampling located the loop in the folder menu; traversal now walks normalized absolute paths with cycle/root guards. Updated file/drop tests passed temporary/base-URL parent traversal, URL validation, Unicode, provider order, deduplication, atomic failure, count limits, timeout, and rejection of late callbacks. Up-navigation also stops at the root by normalized path.

`tests/test_project_browser_view.swift` passed native rendering at 170, 220, and 390 points. Each layout retained its four file rows, invoked no open/import callbacks during rendering, and produced an inspected snapshot. The narrow header was adjusted to keep its title on one line. The previously unconfirmed standalone sidebar result is superseded by these passing checks. Native status-bar rendering passed Ready/Busy/error cases at 820 and 1450 points; samples with large CPU/memory values and pending counts fit a 30-point bar.

The final integrated 0.7.0 arm64 app built successfully with Xcode after all sidebar, script-import, and status fixes. Its local code signature verified. Existing user PyLab sessions and notebooks were not closed or modified during this work.


# Version 0.7.1 imported-script compatibility

The current FDTD startup error was reproduced as a missing notebook `__file__`, followed by argparse rejecting IPython connection arguments. The open cell was corrected through the native editor by replacing only its project import path and changing its final runner call to `main(CONFIG, [])`; a fresh accessibility read confirmed the exact corrected source and unchanged CONFIG block. Original script files and existing simulation results were not edited. Configuration-only validation passed for the original 200×200×64 setup, and a separate four-step 12×12×8 NumPy smoke test produced finite fields and valid temporary outputs. No full 350-step run was performed by the agent.

`tests/test_script_execution_context.py` passed actual Jupyter execution in Shared and Independent modes: filename/main/package/argv, default argparse, sibling imports, shared globals, nested and empty run_cell calls, future imports, magics, top-level await, queued scopes, input, RuntimeError, SyntaxError, SystemExit, KeyboardInterrupt, restoration before finished, and rejection of invalid paths. Existing bridge execution/PNG/table-edit and full cell-namespace regressions passed. Swift metadata persistence/path validation and source-path reader checks passed.

`tests/test_imported_script_execution.swift` passed the actual Swift controller to Jupyter pipeline in both modes, including source metadata round trip, paths with Unicode/apostrophes, execution of edited notebook source, workspace values, restoration for the following ordinary cell, and preservation of original .py files. Tests used isolated preferences, caches, temporary files, and owned kernels.

The final 0.7.1 arm64 app built successfully, matched the reviewed sources, and verified its local code signature.


# Version 0.7.2 execution visibility

`tests/test_execution_activity.swift` passed against its own real Jupyter kernel. It checked two queued requests, actual start timestamps excluding queue delay, queue advancement, input wait/resume without resetting time, event callback ordering, error, interrupt, stop with a queued job, restart, kernel death, disconnected sends, and cell-origin aggregation. Existing kernel lifecycle/recovery checks passed with a temporary bridge fixture.

`tests/test_native_execution_indicators.swift` passed with native NSHostingView/NSTextView controls. Queued, running, waiting, and completed phases retained the same editor, source, cursor, focus, Undo history, and clean document state. Only running code used a spinner; Reduce Motion used a static indicator. Native screenshots were checked at 900- and 360-point widths. Runtime state cleared on cell removal, new notebook, and load.

`tests/test_native_execution_statusbar.swift` passed isolated native status-bar fixtures at 820 and 1450 points for queued, running, waiting-for-input, and ready states. Active execution exposed one native Stop control and clicking it invoked the interrupt callback; queued and idle states exposed none. Only running fixtures showed a spinner. The saved screenshots were visually checked for clear phase text, elapsed time, and unclipped controls.

The existing imported-script execution regression passed in Shared and Independent modes against real Jupyter kernels after adding execution tracking. It checked origin metadata, filenames/argv/sibling imports, edited notebook code, workspace values, and restoration for an ordinary cell. All checks used owned test processes and temporary state; the user's open PyLab session and simulation were not closed or interrupted.

The final 0.7.2 (11) arm64 product build passed with Xcode. Its source and resource files matched the final build input; the new app’s local code signature verified. Existing native cell-menu and editor-preference regressions also passed.


# Version 0.7.3 live plots

The user's open 0.7.2 app was inspected read-only. Its selected `38_waveguide_bend_3d` notebook had completed 4,200 steps on a 430×430×64 grid, with only a summary stream in the output; both project tabs and the kernel were idle. Its cell source and CONFIG were not edited. The current app was not restarted, and no full default waveguide simulation or existing-result write was performed during this change.

`tests/test_display_protocol.py` passed display-ID validation, MIME/metadata preservation, one PNG payload per frame, unsupported and empty display updates. `tests/test_live_display_events.swift` passed the real Swift-controller/Jupyter pipeline: four changing PNG frames before completion, stable display IDs, cross-cell PNG→text→SVG→empty changes, metadata, a late background update with no execution ID, ordinary plots, expression execution count, error and interruption. Existing bridge execution and interrupt regressions passed.

`tests/test_native_live_outputs.swift` passed twenty alternating live frames across two output slots and another notebook sharing the same frame object. Output counts stayed constant; the latest PNG saved and reopened without transient IDs. Native editor identity, text, cursor, focus, Undo and code height remained stable. An already-open figure changed its rendered pixels without resizing; inline layouts were checked at 1000 and 420 points. Text, unsupported MIME and invalid PNG updates removed stale inline images and marked retained figure snapshots. Clear, removal, load, new notebook and kernel detachment cleanup passed. Existing native execution-indicator and notebook-layout regressions passed, including huge-output bounds and retained selection/Undo across layout changes.

`tests/test_fdtd_live_pipeline.swift` passed an actual 14×16×12, six-step NumPy FDTD run through LiveFieldPreview, Jupyter, KernelController and NotebookStore. Four distinct PNG frames arrived before completion, replaced one notebook output and shared one gallery figure without growth. Observer-enabled arrays matched a baseline; final PNG, source and execution count survived save/reopen, and live mappings were empty after loading.

The FDTD project's focused preview tests passed numerical array equality with callbacks enabled/disabled, detached bounded read-only section arrays, stride/time throttling, malformed options/configuration, renderer/callback errors and interrupt cleanup, one reused figure/handle, and distinct PNG frames. A separate actual Jupyter smoke produced five changing frames with one display ID and no pyplot figure leakage. Selected Miniconda Python 3.12/Matplotlib 3.8 passed all forty-one existing 3D tests, all nineteen new preview tests, and the CLI/GIF integration case. An initial run in the project's separate venv encountered a Matplotlib font-discovery error in its CLI plot test; rerunning the entire existing suite in the user's selected environment passed without installing or changing packages.

The existing saved waveguide data was read to render a six-panel preview into a temporary PNG; its layout and physical axes were inspected against the supplied image. `--describe` confirmed the experiment's grid/steps remained unchanged; `--help` exposed live controls; a tiny CLI run with `--no-live --no-plots` wrote only its expected data/configuration/diagnostics into a temporary folder.

Read-only integration review confirmed per-project update routing before the execution-ID guard, fan-out to registered notebook slots, latest-frame gallery updates without appending, preserved execution counts/MIME metadata, and kernel-reset detachment preserving snapshots. A display that initially contains only text and later becomes a PNG through an update gets an inline preview and Open Figure, without automatically adding a gallery entry; the PNG-first FDTD preview is unaffected. The Live badge identifies an updatable linked display, not necessarily currently executing code. Refresh rate is capped and depends on computation/rendering speed; the preview is not a numerical convergence or physical-accuracy validation.

The final 0.7.3 (12) arm64 product built successfully with Xcode, matched the final source/resource inputs, and passed local code-signature verification. The new app was packaged separately without replacing or opening the user's current app.


# Public repository preparation

The publication checkout preserves byte-identical copies of all 45 production Swift source files and both Python resources from the validated 0.7.3 (12) implementation. The original development source/app folders were not edited. Personal development fallback paths were removed from copied tests; Python fixtures use the platform temporary directory, and the optional FDTD fixture accepts an argument, `PYLAB_FDTD_ROOT` or a sibling checkout and skips when unavailable. Test configuration and documentation use portable examples.

The public checkout built an arm64 app successfully with its own `scripts/build.sh`; local signature verification passed. `scripts/test-models.sh` passed six focused checks covering editing, folding, syntax, pane geometry, notebook code/output bounds and console Unicode/tail bounds. `scripts/test-python.sh` passed display protocol checks, nine workspace-validation tests, three workspace-action tests, and data exchange checks. `scripts/test-bridge.sh` passed four isolated real-Jupyter cases covering inline execution/images/table edits, deferred clear/interruption/cleanup, shared variables, and multiple notebook-scoped cells. These runs used the selected Python 3.12 environment and owned temporary state.

All five example notebooks parsed as notebook version 4. Shell scripts passed syntax checks. A staged text scan found no credential/key/token patterns or personal home-folder paths. Generated app bundles, caches, local environments and signing credentials are excluded by `.gitignore`. A labelled six-panel image is a read-only rendering of existing FDTD results; it is a layout illustration, not a screenshot of a new full simulation run.

GitHub Actions definitions were prepared for an arm64 macOS 26 build/model job and Ubuntu Python validation. Hosted-runner availability was verified against GitHub's official runner documentation; successful local checks do not themselves establish a successful remote CI run.
