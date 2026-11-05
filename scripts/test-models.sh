#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
output="$(mktemp -d "${TMPDIR:-/tmp}/pylab-model-checks.XXXXXX")"
trap 'rm -rf "$output"' EXIT
run_check() {
  local name="$1"
  shift
  xcrun swiftc -swift-version 5 -target arm64-apple-macosx26.0 -parse-as-library     "$@" "tests/$name.swift" -o "$output/$name"
  "$output/$name"
}
run_check test_python_editing Sources/PythonEditing.swift Sources/PythonSyntax.swift
run_check test_python_folding Sources/PythonFolding.swift Sources/PythonSyntax.swift
run_check test_python_syntax Sources/PythonSyntax.swift
run_check test_workbench_layout Sources/WorkbenchLayout.swift
run_check test_notebook_layout Sources/NotebookLayout.swift
run_check test_console_log Sources/ConsoleLog.swift
