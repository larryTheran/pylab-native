"""Check data imports, alternate exports, and no-overwrite behavior."""
import contextlib, io, runpy, tempfile, types
from pathlib import Path
import numpy as np
import pandas as pd
from scipy.io import loadmat
shell = types.SimpleNamespace(user_ns={'array': np.array([[1, 2], [3, 4]])})
actions = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'Resources' / 'workspace_actions.py'), init_globals={'get_ipython': lambda: shell})
with tempfile.TemporaryDirectory() as folder:
    folder = Path(folder)
    csv = folder / 'array.csv'; mat = folder / 'array.mat'
    actions['_pylab_export_as']('array', str(csv)); actions['_pylab_export_as']('array', str(mat))
    assert np.array_equal(np.loadtxt(csv, delimiter=','), shell.user_ns['array'])
    assert np.array_equal(loadmat(mat)['array'], shell.user_ns['array'])
    try: actions['_pylab_export_as']('array', str(csv))
    except FileExistsError: pass
    else: raise AssertionError('Expected existing-file protection')
    source = folder / 'my-data.npy'; np.save(source, np.array([5, 6]))
    with contextlib.redirect_stdout(io.StringIO()): actions['_pylab_import_data'](str(source))
    assert shell.user_ns['my_data'].tolist() == [5, 6]
    try: actions['_pylab_import_data'](str(source))
    except ValueError as exc: assert 'already exists' in str(exc)
    else: raise AssertionError('Expected workspace collision protection')
    csv2 = folder / 'table.csv'; csv2.write_text('x,y\n1,2\n')
    with contextlib.redirect_stdout(io.StringIO()): actions['_pylab_import_data'](str(csv2))
    assert isinstance(shell.user_ns['table'], pd.DataFrame)
print('PASS: MAT/CSV/NPY exchange and no-overwrite protection')
