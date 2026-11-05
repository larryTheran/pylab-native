#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
output="$(mktemp -d "${TMPDIR:-/tmp}/pylab-native-checks.XXXXXX")"
trap 'rm -rf "$output"' EXIT
sources=(
  Sources/Notebook.swift Sources/NotebookTabs.swift Sources/NotebookLayout.swift
  Sources/NotebookCellActions.swift Sources/CellContextMenu.swift Sources/CellReordering.swift
  Sources/CellOutputPane.swift Sources/VariablePlot.swift Sources/PaneResizeHandle.swift
  Sources/LiquidMotion.swift Sources/PythonSyntax.swift Sources/PythonFolding.swift
  Sources/PythonEditing.swift Sources/EditorPreferences.swift
  Sources/KernelExecutionActivity.swift Sources/ExecutionIndicator.swift Sources/NotebookLiveOutputs.swift
)
for name in test_native_execution_indicators test_native_live_outputs test_native_notebook_layout; do
  xcrun swiftc -swift-version 5 -target arm64-apple-macosx26.0 -parse-as-library     "${sources[@]}" "tests/$name.swift" -o "$output/$name"
  "$output/$name"
done
