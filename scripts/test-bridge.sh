#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -z "${PYLAB_KERNEL_PYTHON:-}" ]; then
  if [ -x .venv/bin/python ]; then
    export PYLAB_KERNEL_PYTHON="$PWD/.venv/bin/python"
  elif [ -x /opt/miniconda3/bin/python3.12 ]; then
    export PYLAB_KERNEL_PYTHON=/opt/miniconda3/bin/python3.12
  else
    export PYLAB_KERNEL_PYTHON="$(command -v python3)"
  fi
fi
output="$(mktemp -d "${TMPDIR:-/tmp}/pylab-bridge-checks.XXXXXX")"
trap 'rm -rf "$output"' EXIT
export IPYTHONDIR="$output/ipython"
export JUPYTER_CONFIG_DIR="$output/jupyter-config"
export JUPYTER_DATA_DIR="$output/jupyter-data"
export JUPYTER_RUNTIME_DIR="$output/jupyter-runtime"
export MPLCONFIGDIR="$output/matplotlib"
mkdir -p "$IPYTHONDIR" "$JUPYTER_CONFIG_DIR" "$JUPYTER_DATA_DIR" "$JUPYTER_RUNTIME_DIR" "$MPLCONFIGDIR"
export MPLBACKEND=Agg
export PYTHONDONTWRITEBYTECODE=1
for name in test_bridge test_interrupt test_shared_workspace test_multi_notebook_kernel; do
  "$PYLAB_KERNEL_PYTHON" "tests/$name.py"
done
