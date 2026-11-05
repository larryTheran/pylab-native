"""Regression checks for safe export and independent variable plotting."""
import json
import os
from pathlib import Path
import tempfile
import types
import unittest

import numpy as np
import pandas as pd


class WorkspaceActionsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pylab-actions-')
        self.root = Path(self.temp.name)
        self.ns = {
            'array': np.arange(6).reshape(2, 3),
            'frame': pd.DataFrame({'x': [1.0, 2.5], 'label': ['a', 'b']}, index=['one', 'two']),
            'series': pd.Series([1, 2, 3], name='gain'),
            'text': 'hello π',
            'number': np.int64(7),
            'list': [1, 2, 3],
            'nested': {'a': [1, True, None]},
            'object_array': np.array([object()], dtype=object),
            'unsupported': object(),
            'nan': float('nan'),
            'huge': np.ones((20001, 2)),
        }
        scope = {'get_ipython': lambda: types.SimpleNamespace(user_ns=self.ns)}
        source = (Path(__file__).resolve().parents[1] / 'Resources' / 'workspace_actions.py').read_text()
        exec(compile(source, 'workspace_actions.py', 'exec'), scope)
        self.actions = scope

    def tearDown(self):
        self.temp.cleanup()

    def info(self, name):
        return json.loads(self.actions['_pylab_actions_info'](name))

    def save(self, name, filename, replace=False):
        return json.loads(self.actions['_pylab_export'](name, str(self.root / filename), replace))

    def test_correct_formats_and_roundtrips(self):
        for name, ext in [('array', 'npy'), ('frame', 'csv'), ('series', 'csv'),
                          ('text', 'txt'), ('number', 'json'), ('list', 'json'), ('nested', 'json')]:
            self.assertEqual(self.info(name)['export']['extension'], ext)
            self.assertEqual(self.save(name, name + '.' + ext)['format'], ext)
        np.testing.assert_array_equal(np.load(self.root / 'array.npy', allow_pickle=False), self.ns['array'])
        pd.testing.assert_frame_equal(pd.read_csv(self.root / 'frame.csv', index_col=0), self.ns['frame'])
        self.assertEqual((self.root / 'text.txt').read_text(), 'hello π')
        self.assertEqual(json.loads((self.root / 'number.json').read_text()), 7)
        self.assertEqual(json.loads((self.root / 'nested.json').read_text()), self.ns['nested'])
        self.assertIsNone(self.info('unsupported')['export'])
        self.assertIsNone(self.info('object_array')['export'])

    def test_overwrites_require_consent_and_bad_values_never_truncate(self):
        target = self.root / 'number.json'
        target.write_text('original')
        with self.assertRaises(FileExistsError):
            self.save('number', 'number.json')
        self.assertEqual(target.read_text(), 'original')
        with self.assertRaises(ValueError):
            self.save('nan', 'number.json', replace=True)
        self.assertEqual(target.read_text(), 'original')
        self.save('number', 'number.json', replace=True)
        self.assertEqual(json.loads(target.read_text()), 7)
        with self.assertRaises(ValueError):
            self.save('number', 'number.csv', replace=True)
        self.assertFalse((self.root / 'number.csv').exists())
        with self.assertRaises(ValueError):
            self.save('object_array', 'object_array.npy')
        self.assertFalse((self.root / 'object_array.npy').exists())

    def test_plot_png_and_validation(self):
        import base64
        import matplotlib.pyplot as plt
        before = plt.get_fignums()
        for name in ('array', 'frame', 'series', 'list', 'number'):
            self.assertTrue(self.info(name)['plot'])
            data = json.loads(self.actions['_pylab_plot'](name))
            self.assertEqual(data['title'], name)
            self.assertTrue(base64.b64decode(data['png']).startswith(b'\x89PNG\r\n\x1a\n'))
        for kind, signature in [('svg', b'<svg'), ('pdf', b'%PDF')]:
            data = json.loads(self.actions['_pylab_plot']('array', 1, {'format': kind, 'title': 'Gain', 'xlabel': 'Frequency', 'legend': True}))
            payload = base64.b64decode(data[kind])
            self.assertIn(signature, payload)
            self.assertEqual(data['title'], 'Gain')
        with self.assertRaises(ValueError): self.actions['_pylab_plot']('frame', 1)
        with self.assertRaises(ValueError): self.actions['_pylab_plot']('array', 1, {'xmin': '5', 'xmax': '2'})
        self.assertTrue(json.loads(self.actions['_pylab_plot']('array', 1, {'ymin': '0', 'ymax': '10', 'cursor': '1'}))['png'])
        with self.assertRaises(ValueError): self.actions['_pylab_plot']('array', 1, {'cursor': '100'})
        self.assertEqual(plt.get_fignums(), before)
        self.assertFalse(self.info('text')['plot'])
        self.assertFalse(self.info('nan')['plot'])
        with self.assertRaises(ValueError):
            self.actions['_pylab_plot']('huge')
        self.ns['ragged'] = [[1], [2, 3]]
        self.assertFalse(self.info('ragged')['plot'])
        self.ns['duplicates'] = pd.DataFrame([[1, 2], [3, 4]], columns=['x', 'x'])
        self.assertTrue(json.loads(self.actions['_pylab_plot']('duplicates'))['png'])


if __name__ == '__main__':
    unittest.main()
