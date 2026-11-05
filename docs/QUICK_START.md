# Quick start

## 1. Requirements

- Apple Silicon Mac running macOS 26 or later.
- A scientific Python environment. Python 3.12 is the validated default; the app initially tries `/opt/miniconda3/bin/python3.12`.
- For source builds, Xcode with the macOS 26 SDK and command-line tools selected.

The app bundle does not include Python. Create a dedicated environment if you do not already have one:

```sh
python3.12 -m venv "$HOME/.venvs/pylab"
"$HOME/.venvs/pylab/bin/python" -m pip install jupyter_client ipykernel numpy pandas matplotlib
# Optional MAT and Excel support:
"$HOME/.venvs/pylab/bin/python" -m pip install scipy openpyxl
```

These are commands for you to run in the environment you choose; PyLab itself does not install packages.

## 2. Open PyLab and select Python

Download the [v0.7.3 development ZIP](https://github.com/larryTheran/pylab-native/releases/download/v0.7.3/PyLabNative-0.7.3-macos-arm64.zip), extract it, and open the app. Save notebooks in an older PyLab before quitting it and changing versions.

Choose **Python Kernel** in the toolbar to enter or browse for the desired executable. For the environment above, choose `$HOME/.venvs/pylab/bin/python` using its actual expanded home path. Enter a virtual environment path directly to preserve its symlink. Use **Check Environment** to inspect version, architecture and required/optional packages. Your interpreter selection is remembered. Wait for **Ready** before running code.

A launch-only override is also supported:

```sh
PYLAB_KERNEL_PYTHON="$HOME/.venvs/pylab/bin/python" \
  ./dist/PyLabNative.app/Contents/MacOS/PyLabNative
```

When using this override, launch the executable directly from Terminal. A Finder launch does not inherit Terminal's environment.

## 3. First notebook

1. Open a project folder using the folder control. Each project owns a kernel; changing folders updates its working directory after Python acknowledges the change.
2. Open `Examples/Welcome.ipynb` or create a notebook with the plus beside the notebook tabs.
3. Name a cell in its header. Type `import numpy as np` and `a = np.arange(12).reshape(3, 4)` in a code cell, then press **Shift–Return**.
4. Workspace lists `a`. Double-click it to inspect/edit its values; right-click it for supported save, plot and statistics actions.
5. Add another cell and run `a.sum()`. In Shared Variables mode it uses the same `a`.
6. Save the notebook as `.ipynb`. Each open notebook is saved separately; **Save All** covers changed notebooks in the active project.

## 4. Explore the examples

| Notebook | Purpose |
| --- | --- |
| `Welcome.ipynb` | Basic code, outputs and scientific Python |
| `Analysis Workbench.ipynb` | Arrays, tables, plotting and a named analysis workflow |
| `Variable Sharing Demo.ipynb` | Compare shared and independent cell namespaces |
| `Output Layout Demo.ipynb` | Adjust bounded code/output space with a large saved plot |
| `Live Plot Demo.ipynb` | Watch one figure refresh in place for about five seconds |

## 5. Run an FDTD experiment

Clone [fdtd-python](https://github.com/larryTheran/fdtd-python) separately and open that folder as a PyLab project. Import a `.py` experiment using Open, the browser, or a drop. A new unsaved notebook contains its source; importing does not execute or alter the original script.

New imports remember the script's original filename, making `__file__`, sibling imports, and a clean `sys.argv` available while the cell executes. The original location must still exist. For notebook code adapted from an older import, reimport once to attach that context.

The companion project's 3D runner enables its live preview automatically in a fresh IPython kernel. Run the existing experiment cell normally; its final data and figures are still saved. Full 3D runs can be large. Use the simulation's documented small smoke configuration and a separate output folder when experimenting; preview is not a physical convergence test.

## Keep your work

Save notebooks regularly. A notebook stores code and outputs, not kernel memory. Export variables you need to retain, or rerun the necessary cells after a restart. Changing interpreter or variable-sharing mode clears live variables after confirmation. Project/session restoration reopens saved notebook paths, not unsaved text.
