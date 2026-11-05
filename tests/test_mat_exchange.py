"""MAT exchange does not overwrite workspace names and preserves supported arrays."""
import contextlib
import io
import runpy
import tempfile
from pathlib import Path
import numpy as np
from scipy.io import loadmat, savemat

class IPython:
    def __init__(self): self.user_ns = {}
shell = IPython()
path = Path(__file__).resolve().parents[1] / 'Resources' / 'workspace_actions.py'
helpers = runpy.run_path(str(path), init_globals={'get_ipython': lambda: shell})
with tempfile.TemporaryDirectory() as folder:
    target = Path(folder) / 'input.mat'
    savemat(target, {'matrix': np.array([[1., 2.], [3., 4.]])})
    with contextlib.redirect_stdout(io.StringIO()): helpers['_pylab_import_mat'](str(target))
    assert np.array_equal(shell.user_ns['matrix'], [[1, 2], [3, 4]])
    try:
        helpers['_pylab_import_mat'](str(target))
        raise AssertionError('Expected a conflict')
    except ValueError as exc:
        assert 'already exist' in str(exc)
    shell.user_ns['unsupported'] = object()
    output = Path(folder) / 'out.mat'
    with contextlib.redirect_stdout(io.StringIO()) as printed: helpers['_pylab_export_mat'](str(output))
    assert np.array_equal(loadmat(output)['matrix'], shell.user_ns['matrix'])
    assert 'Skipped unsupported variables' in printed.getvalue()
    original = output.read_bytes()
    shell.user_ns['matrix'] = np.array([[99]])
    try:
        helpers['_pylab_export_mat'](str(output))
        raise AssertionError('Expected existing-file protection')
    except FileExistsError:
        assert output.read_bytes() == original
    with contextlib.redirect_stdout(io.StringIO()): helpers['_pylab_export_mat'](str(output), True)
    assert loadmat(output)['matrix'].tolist() == [[99]]
    assert not list(Path(folder).glob('.pylab-mat-*'))
print('PASS: MAT round trip, conflict protection, unsupported variable reporting')
