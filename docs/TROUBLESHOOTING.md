# Troubleshooting

| Symptom | Check / action |
| --- | --- |
| Python not found | Select an existing executable through Python Kernel. `/opt/miniconda3/bin/python3.12` is an initial default, not a bundled runtime. |
| Missing package / kernel cannot start | Use Check Environment for the selected interpreter. Install required packages into that same environment, then restart. A terminal `pip` may target a different Python. |
| Wrong working directory | Use the project folder control. Folder changes are acknowledged by Python; failure keeps the previous folder. Imported script context does not silently change the working directory. |
| `__file__` or argparse errors in an old imported cell | Reimport the original `.py`/`.pyw` once. New imports save their origin and supply a clean script context. Scripts needing arguments still require explicit runner values. |
| Variables unavailable in another cell | Check Shared/Independent mode and execution order. Independent cells need their own imports/definitions; switching to Shared restarts and does not automatically merge existing namespaces. |
| Code appears queued | Another request is running in the same project kernel. The queue timer starts when execution actually begins. |
| Waiting for input | Enter the answer or debugger command in the console. Password input is not echoed. Stop can interrupt the current execution. |
| Plot appears only after code finishes | Code must publish intermediate frames. Use an IPython display handle and `update()`, or the companion FDTD 3D live runner. Merely writing `fields.png` at the end provides no intermediate state. |
| New FDTD live preview does not appear | Use a fresh kernel after updating the companion solver; Python may retain imported old modules. Run the cell again. A completed run cannot become live retroactively. |
| Live preview is slow | Rendering costs time. Lower `--live-fps`, increase `--live-stride`, or use `--no-live`. The displayed time is simulated physical time, not a promise of real-time computation. |
| Plot consumes code space | Use Cell Tabs, drag the code/output separator, collapse Output, or open the figure separately. Output size is bounded independently of PNG dimensions. |
| Large output disconnects kernel | Each incoming JSON message is limited to 128 MiB. Reduce one response's size; the app does not save a truncated partial message. |
| Console text disappeared | The console retains the latest 256 KiB with a trim notice. Saved notebook output is separate. |
| Save conflict | Another app changed/moved/deleted the file. Save As preserves current edits instead of silently overwriting it. |
| No variables after restart | Kernel memory is session-only. Rerun source or import previously exported data. |
| Build lacks macOS 26 APIs | Select Xcode with the macOS 26 SDK; check `DEVELOPER_DIR`, SDK version and Swift compiler. Remove an unrelated inherited SDKROOT; the build script resolves the selected SDK. |
| Downloaded development app is not notarized | Check its release signing statement and checksum. A local ad-hoc signature is not an Apple notarization ticket. Developers can build from reviewed source; official notarization is a maintainer distribution step. |

Report the app version/build, macOS/Xcode/Python versions, package versions and minimal reproducing code in an issue. Remove private paths, data, notebook outputs, passwords and tokens before posting. The app does not require a GitHub password to run.
