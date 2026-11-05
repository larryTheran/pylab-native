# User guide

## Layout and projects

The left pane browses the project folder; Back and Up navigate folders. The center contains notebook and named cell tabs. Workspace and the command console occupy the right side by default. Drag pane dividers to resize them; drag the console header to choose Below Workspace, Below Notebook or Across Bottom. Hide a pane from View when more code space is needed.

Use the plus in Projects to open a separate folder/kernel, or the plus beside notebook tabs for another notebook in the current project. All notebooks in one project share that project's kernel. Different projects retain separate kernels while you switch tabs. Drag project, notebook or cell tabs to reorder them; magnetic targets highlight before a drop, and hovering does not commit a reorder. Reduce Motion keeps navigation motion restrained.

Right-click a saved notebook tab for **Show in Finder**. Right-click a cell tab, card or editor for **Duplicate Cell** and **Delete Cell**. A duplicate has a new ID, name and unexecuted source copy; it does not inherit outputs or variables. Running/queued cells cannot be deleted. Removing the last cell leaves a blank cell.

## Editing and execution

| Action | Shortcut / control |
| --- | --- |
| Run full cell | Shift–Return or Run in its header |
| Run highlighted statements | Command–Return; full selected cell if no selection |
| Notebook search | Command–F |
| Command palette | Command–Shift–P |
| Kernel completions | Control–Space |
| Indent/outdent | Tab / Shift–Tab |
| Toggle line comment | Command–/ |
| Editor settings | Command–Comma |
| Save current notebook | Command–S |

More/command palette also provide Run Cell and Advance, Run All Above, Run Selected and Below, Run All Cells, Save All, Clear Outputs and Debug Selected Cell. A running header shows `In [*]`, a spinner, elapsed time, amber rim and Stop; queued code has a clock and no running timer. An input/debugger prompt shows Waiting for input and opens the console. Notebook/project badges remain visible when you switch away. Stop interrupts that project's current kernel execution; it does not cancel a separately selected queued request or restart Python.

VS Code, Nord and Solarized syntax palettes adapt to appearance; choose 11–22 pt type, guides and the line-number/folding gutter in Editor settings. Fold arrows support single-line Python block headers, including functions and classes. Folding affects presentation only: saving and running use the full source. Editing folded code expands it before applying the edit. This is lightweight Python editing, not a semantic language server.

For debugging ordinary Python, click the gutter beside a line to set a temporary breakpoint, then choose Debug Selected Cell. Use Step, Next, Continue and Stop in the console, or PDB commands such as `p variable`. Breakpoints clear after editing. Debugging IPython magic commands is not supported.

## Workspace and variable sharing

**Shared Variables** is the default: cells and notebooks in a project use one namespace, so variables are available to later cells and console commands. Workspace groups each name under the latest detected assigning/changing cell. Attribution is best-effort for dynamic code, hidden function side effects and aliases; it is not a full provenance record.

**Independent Cells** gives each cell a persistent namespace within the same Python process. Same-named variables do not overwrite one another. Imports and definitions needed by a cell must be run there. The console/completions follow the selected cell; the Workspace groups values by their owning namespace. Renaming/reordering a cell preserves its namespace identity. Switching modes confirms a restart and clears variables instead of ambiguously merging names.

Double-click a supported NumPy array, pandas Series or DataFrame to open its paged editor (up to 100 rows/page and 30 displayed columns). Editing uses Python scalar literals and commits on Return. Right-click a destination for Paste Table Starting Here; enter tab-separated literals. Clear sorting/filtering before positional paste. Right-click a header to plot a column.

Variable actions include supported rename/delete, statistics, Save As and Plot. Statistics sample large data within displayed limits. Default exports include NPY for non-object arrays, indexed CSV for pandas, TXT for strings and JSON for supported ordinary values. CSV/XLSX/MAT alternatives depend on type and installed packages. Object arrays and unsupported custom objects are rejected rather than pickled. MAT supports SciPy formats up to v7; HDF5/v7.3 is not supported. Imports refuse existing-name collisions.

Deleting a cell or notebook does not erase its Python variables; restart or explicitly remove them. Deleted/unattributed values appear under the corresponding fallback group.

## Figures and code space

Cell Tabs allocates about 68% of usable cell content to code initially. A bounded output area prevents an image or long log from taking over the editor. Drag the code/output separator, use its menu presets or collapse outputs; complete saved output is retained. All Cells also bounds output height.

Choose Open Figure or double-click a preview for fit/zoom/export, or use Figures to revisit up to 50 recent project previews. A code-generated figure is a PNG with image-PDF export. Supported workspace plots can be regenerated from current data with title/axis/limit/legend controls and vector PDF/SVG export. Exporting a live figure saves the latest received frame.

A Jupyter `display_id` links an output to future updates. PyLab replaces matching output slots, including across notebooks in the project, and refreshes an open figure at stable size/zoom. Live means the display handle remains linked, independent of whether code is currently running. Restart detaches the link and preserves a snapshot. Saving stores the latest output, not a frame history or live link. Unsupported MIME is retained in the notebook without executing HTML/JavaScript.

## Python, appearance and recovery

Choose Python Kernel to select an executable or check installed package metadata. A running project's CPU/resident-memory readout can be opened for recent activity history. CPU is measured per core (100% per fully used core); it is not a resource reservation or limit.

Use the glass sun/moon switch for Light/Dark, or right-click for System. Preferences apply to this app and retain editor state. macOS Reduce Motion, Reduce Transparency and contrast settings are respected by the corresponding controls.

Restart clears live variables but keeps notebook source and outputs. Save conflicts from outside edits are reported; use Save As to retain your edits. A kernel failure clears pending/live runtime state and exposes recovery controls. The console retains a Unicode-safe 256 KiB tail; notebook output is separate. A single incoming kernel message above 128 MiB stops the connection with a diagnostic rather than saving a partial response.
