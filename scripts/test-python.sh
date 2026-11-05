#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -n "${PYLAB_KERNEL_PYTHON:-}" ]; then
  python="$PYLAB_KERNEL_PYTHON"
elif [ -x .venv/bin/python ]; then
  python="$PWD/.venv/bin/python"
else
  python=python3
fi
output="$(mktemp -d "${TMPDIR:-/tmp}/pylab-python-checks.XXXXXX")"
trap 'rm -rf "$output"' EXIT
export MPLCONFIGDIR="$output/matplotlib"
mkdir -p "$MPLCONFIGDIR"
export MPLBACKEND=Agg
export PYTHONDONTWRITEBYTECODE=1
"$python" tests/test_display_protocol.py
"$python" tests/test_workspace_validation.py
"$python" tests/test_workspace_actions.py
"$python" tests/test_data_exchange.py
