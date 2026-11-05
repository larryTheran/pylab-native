"""Regression checks for lossless CSV, usable Python names and safe table coordinates."""
import ast
import contextlib
import csv
import io
import json
from pathlib import Path
import tempfile
import types
import unittest
from unittest.mock import patch

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]

class WorkspaceValidationTest(unittest.TestCase):
    def setUp(self):
        self.ns = {}
        shell = types.SimpleNamespace(user_ns=self.ns, run_line_magic=lambda *args: None)
        self.actions = {'get_ipython': lambda: shell}
        exec(compile((ROOT / 'Resources/workspace_actions.py').read_text(), 'workspace_actions.py', 'exec'), self.actions)
        tree = ast.parse((ROOT / 'Resources/kernel_bridge.py').read_text())
        helpers = next(ast.literal_eval(node.value) for node in tree.body if isinstance(node, ast.Assign)
                       and any(isinstance(target, ast.Name) and target.id == 'HELPERS' for target in node.targets))
        exec(compile(helpers, 'kernel_table_helpers', 'exec'), self.actions)

    def test_string_array_csv_quotes_fields_and_roundtrips(self):
        values = np.array([['one,two', 'line1\nline2'], ['"quoted"', 'π']])
        self.ns['labels'] = values
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / 'labels.csv'
            self.actions['_pylab_export_as']('labels', str(target))
            with target.open(newline='', encoding='utf-8') as handle:
                self.assertEqual(list(csv.reader(handle)), values.tolist())
            before = target.read_bytes()
            with self.assertRaises(FileExistsError):
                self.actions['_pylab_export_as']('labels', str(target))
            self.assertEqual(target.read_bytes(), before)
            self.assertFalse(list(target.parent.glob('.pylab-export-*')))

    def test_imported_names_match_python_parser_and_collisions(self):
        with tempfile.TemporaryDirectory() as folder:
            for stem, expected in [('a²', 'a2'), ('Kelvin', 'Kelvin'), ('for', 'for_data'), ('123', 'data_123')]:
                path = Path(folder) / (stem + '.npy')
                np.save(path, np.array([5]))
                with contextlib.redirect_stdout(io.StringIO()):
                    self.actions['_pylab_import_data'](str(path))
                self.assertTrue(expected.isidentifier())
                self.assertEqual(eval(expected, {}, self.ns).tolist(), [5])
            conflict = Path(folder) / 'Ｋelvin.npy'
            np.save(conflict, np.array([99]))
            before = self.ns.copy()
            with self.assertRaisesRegex(ValueError, 'already exists'):
                self.actions['_pylab_import_data'](str(conflict))
            self.assertEqual(self.ns.keys(), before.keys())
            self.assertIs(self.ns['Kelvin'], before['Kelvin'])

    def test_disguised_numpy_archive_is_rejected_without_importing(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'archive.npy'
            with path.open('wb') as handle:
                np.savez(handle, measurements=np.arange(3))
            with self.assertRaisesRegex(ValueError, 'NPZ archive'):
                self.actions['_pylab_import_data'](str(path))
            self.assertEqual(self.ns, {})

    def test_rename_canonicalizes_and_detects_collisions(self):
        self.ns.update({'source': 1, 'Kelvin': 2})
        with self.assertRaisesRegex(ValueError, 'already exists'):
            self.actions['_pylab_manage_variable']('source', 'rename', 'Kelvin')
        self.assertEqual(self.ns, {'source': 1, 'Kelvin': 2})
        result = json.loads(self.actions['_pylab_manage_variable']('source', 'rename', 'ｇain'))
        self.assertEqual(result['new_name'], 'gain')
        self.assertEqual(self.ns, {'gain': 1, 'Kelvin': 2})

    def test_mat_import_validates_all_normalized_names_before_commit(self):
        self.ns['original'] = 10
        for values in [{'valid': np.array([1]), 'bad name': np.array([2])},
                       {'Kelvin': np.array([1]), 'Kelvin': np.array([2])}]:
            with patch('scipy.io.loadmat', return_value=values):
                with self.assertRaises(ValueError):
                    self.actions['_pylab_import_mat']('/unused.mat')
            self.assertEqual(self.ns, {'original': 10})
        with patch('scipy.io.loadmat', return_value={'Kelvin': np.array([3])}):
            with contextlib.redirect_stdout(io.StringIO()):
                self.actions['_pylab_import_mat']('/unused.mat')
        self.assertEqual(eval('Kelvin', {}, self.ns).tolist(), [3])

    def test_plot_lists_are_bounded_before_full_conversion(self):
        class UnconvertibleList(list):
            def __array__(self, *args, **kwargs):
                raise AssertionError('Unbounded list converted before validation')
        self.ns['too_long'] = UnconvertibleList([1] * 20001)
        self.ns['too_wide'] = UnconvertibleList([[1] * 33])
        for name in ('too_long', 'too_wide'):
            with self.assertRaisesRegex(ValueError, 'at most 20,000'):
                self.actions['_pylab_plot'](name)

    def test_invalid_edit_coordinates_never_mutate(self):
        for original in (np.array([1, 2]), pd.Series([1, 2]), pd.DataFrame({'x': [1, 2]}), np.array([[1, 2]])):
            for row, column in [(-1, 0), (0, -1), (0, 9), (9, 0), (True, 0), (0, 0.5)]:
                value = original.copy()
                before = value.copy()
                with self.assertRaises(ValueError):
                    self.actions['_pylab_set_literal'](value, row, column, '8')
                if isinstance(value, np.ndarray): np.testing.assert_array_equal(value, before)
                elif isinstance(value, pd.Series): pd.testing.assert_series_equal(value, before)
                else: pd.testing.assert_frame_equal(value, before)
        for value in (np.array(1), np.ones((1, 1, 1)), np.array([object()], dtype=object)):
            with self.assertRaises(ValueError): self.actions['_pylab_set_literal'](value, 0, 0, '8')

    def test_bad_paste_inputs_have_no_partial_changes(self):
        original = np.array([[1, 2], [3, 4]])
        self.ns['array'] = original
        for values in ([1], [None], ['bad'], [[]], [['5', '6'], ['oops']], [['5']]):
            row = -1 if values == [['5']] else 0
            with self.assertRaises(ValueError): self.actions['_pylab_paste']('array', row, 0, values)
            np.testing.assert_array_equal(original, [[1, 2], [3, 4]])

    def test_stale_table_page_clamps_and_negative_offset_rejected(self):
        for value in (np.arange(8), pd.Series(range(8)), pd.DataFrame({'x': range(8)})):
            self.ns['array'] = value
            table = json.loads(self.actions['_pylab_table']('array', 100))
            self.assertEqual(table['offset'], 0)
            self.assertEqual(len(table['cells']), 8)
            with self.assertRaises(ValueError): self.actions['_pylab_table']('array', -1)

if __name__ == '__main__':
    unittest.main()
