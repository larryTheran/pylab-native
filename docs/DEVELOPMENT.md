# Development and validation

## Toolchain

Use an Apple Silicon Mac with macOS 26+, Xcode containing the macOS 26 SDK, and Swift 6.2+ tools. Sources currently use Swift 5 language mode. If several Xcode installations exist, select one explicitly:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun --sdk macosx --show-sdk-version
xcrun swiftc --version
./scripts/build.sh
```

The build script resolves its own SDK and produces `dist/PyLabNative.app`; it does not install Python. `Package.swift` can be opened in Xcode for source development. Distributing the app uses the bundle script, which includes `Info.plist` and bridge resources.

## Python test environment

```sh
python3.12 -m venv .venv
.venv/bin/python -m pip install -r requirements-test.txt
export PYLAB_KERNEL_PYTHON="$PWD/.venv/bin/python"
export MPLBACKEND=Agg
```

Use an isolated environment and temporary kernel/cache configuration for tests. Never point a regression at a user's running app or existing simulation output directory. Tests start owned kernels and small temporary fixtures; they are not full physical validation of a scientific model.

## Focused entry points

```sh
# No GUI/kernel needed: MIME protocol and data-operation validation.
./scripts/test-python.sh
# macOS model checks for editing, geometry and console bounds.
./scripts/test-models.sh
# Native NSTextView/output checks in a separate test process.
./scripts/test-native.sh
# Real-Jupyter execution/interrupt/sharing checks.
./scripts/test-bridge.sh
```

`test-python.sh` chooses `PYLAB_KERNEL_PYTHON`, then the checkout venv, then `python3`. `test-bridge.sh` exports the same selected interpreter to the subprocess tests. The standalone Swift tests use the controller's `PYLAB_KERNEL_PYTHON` override; default real-kernel fixtures otherwise try `/opt/miniconda3/bin/python3.12`.

Not every test is run by the focused scripts. `tests/` also covers notebook save conflicts and identity, tables, imports, namespace modes, console docking, private drag sessions, appearance, kernel failure/framing, script context, and live plotting. Many Swift files are standalone `@main` programs with source dependencies rather than XCTest targets. Build them with their model dependencies and one test main; compiling every test main together is invalid.

For a real Swift-to-Jupyter live-output check:

```sh
xcrun swiftc -swift-version 5 -target arm64-apple-macosx26.0 -parse-as-library \
  Sources/Kernel.swift Sources/KernelActivity.swift \
  Sources/KernelExecutionActivity.swift Sources/VariableSharingMode.swift \
  tests/test_live_display_events.swift -o /tmp/pylab-live-events
/tmp/pylab-live-events
```

The optional `test_fdtd_live_pipeline.swift` additionally needs the native notebook model dependencies. Clone [fdtd-python](https://github.com/larryTheran/fdtd-python) as a sibling checkout, set `PYLAB_FDTD_ROOT`, or pass that folder to the compiled executable. When none is available the fixture prints SKIP. It runs only a 14×16×12, six-step NumPy case and compares observer-enabled results against a baseline.

## CI

The Python workflow runs protocol, data and real-kernel tests on Ubuntu with Python 3.12. The native workflow builds the Apple Silicon app on `macos-26`, runs model checks, verifies the app signature and uploads a zipped build. Run native rendering checks locally for visual review.

Runner availability was checked against GitHub's [hosted runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) and [runner-image list](https://github.com/actions/runner-images). A future runner/SDK change should be assessed rather than treating `macos-latest` as a fixed toolchain. CI configuration is prepared here; the historical [validation record](../VALIDATION.md) describes local development checks, not a claim that GitHub CI has already run.

## Review before changes

Preserve stable editor/cell/project identity. Do not use `.id` to force an editor refresh. Keep native glass on navigation/controls and bounded outputs around code. Separate UI state from notebook JSON. Validate file paths, export shapes, scope IDs and stale table pages. Any kernel reset must detach pending operations and live display handles while preserving source/output snapshots. Scientific preview changes should compare numerical arrays with callbacks on/off and avoid retaining full-volume histories.
