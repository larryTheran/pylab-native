"""Kernel-side, explicit workspace export and plotting actions.

This file is executed inside the existing IPython namespace by kernel_bridge.py.
The public helpers return JSON strings so they can be used as user_expressions.
"""
import base64 as _pylab_base64
import io as _pylab_io
import json as _pylab_json
import os as _pylab_os
import tempfile as _pylab_tempfile
import keyword as _pylab_keyword
import unicodedata as _pylab_unicodedata
import csv as _pylab_csv
from pathlib import Path as _PyLabPath
import numpy as _pylab_np
import pandas as _pylab_pd


def _pylab_variable(name):
    ns = get_ipython().user_ns
    if not isinstance(name, str) or name not in ns or name.startswith('_'):
        raise ValueError('The selected variable is no longer available in the workspace.')
    return ns[name]


def _pylab_manage_variable(name, action, new_name=None):
    if name in ('In', 'Out', 'get_ipython', 'exit', 'quit', 'open'):
        raise ValueError('This name is reserved by IPython.')
    value = _pylab_variable(name)
    ns = get_ipython().user_ns
    if action == 'rename':
        if isinstance(new_name, str):
            new_name = _pylab_unicodedata.normalize('NFKC', new_name)
        if (not isinstance(new_name, str) or not new_name.isidentifier()
                or _pylab_keyword.iskeyword(new_name) or new_name.startswith('_')):
            raise ValueError('Enter a public Python identifier, such as measured_voltage.')
        if new_name == name:
            return _pylab_json.dumps({'name': name, 'new_name': name, 'identity': id(value)})
        if new_name in ns:
            raise ValueError('A variable or reserved name already exists with that name.')
        ns[new_name] = value
        del ns[name]
        return _pylab_json.dumps({'name': name, 'new_name': new_name, 'identity': id(value)})
    if action == 'delete':
        del ns[name]
        return _pylab_json.dumps({'name': name})
    raise ValueError('Unsupported workspace operation.')


def _pylab_statistics(name):
    """Bound inspection work independently of the size of the live dataset."""
    value = _pylab_variable(name)
    fields, notes, columns = [], [], []
    def field(label, value):
        fields.append({'label': label, 'value': str(value)})
    limit = 100000
    memory = None
    shape = str(getattr(value, 'shape', ''))
    if isinstance(value, _pylab_np.ndarray):
        memory = int(value.nbytes)
        field('Elements', value.size)
        field('Dtype', value.dtype)
        if value.dtype.kind in 'biufc':
            sample = value.flat[:limit]
            columns.append(('', sample))
            if value.size > limit:
                notes.append('Statistics use the first 100,000 elements in row-major order; counts below describe this sample.')
    elif isinstance(value, (_pylab_pd.DataFrame, _pylab_pd.Series)):
        frame = value.to_frame() if isinstance(value, _pylab_pd.Series) else value
        memory = int(frame.memory_usage(index=True, deep=False).sum())
        field('Rows', len(frame))
        field('Columns', frame.shape[1])
        positions = [i for i, dtype in enumerate(frame.dtypes)
                     if _pylab_pd.api.types.is_numeric_dtype(dtype)]
        row_limit = max(1, limit // max(1, min(32, len(positions))))
        for i in positions[:32]:
            series = frame.iloc[:row_limit, i]
            dtype = complex if _pylab_pd.api.types.is_complex_dtype(series.dtype) else float
            sample = series.to_numpy(dtype=dtype, na_value=_pylab_np.nan)
            columns.append((str(frame.columns[i]) + ' [column ' + str(i) + ']', sample))
        if len(frame) > row_limit or len(positions) > 32:
            notes.append('Statistics use the first ' + str(row_limit) + ' rows of up to 32 numeric columns; counts describe each sample.')
        notes.append('Memory excludes the deep size of referenced Python objects.')
    elif isinstance(value, (int, float, complex, bool, _pylab_np.number)):
        sample = _pylab_np.asarray([value])
        if sample.dtype.kind in 'biufc':
            columns.append(('', sample))
    if memory is not None:
        field('Memory (bytes)', memory)
    if not columns:
        notes.append('Numeric statistics are available for numeric NumPy arrays, pandas columns, and numeric scalars.')
    summaries = []
    for label, sample in columns:
        finite_mask = _pylab_np.isfinite(sample)
        finite = sample[finite_mask]
        result = [{'label': 'Count', 'value': str(sample.size)},
                  {'label': 'Missing (NaN)', 'value': str(int(_pylab_np.isnan(sample).sum()))},
                  {'label': 'Finite', 'value': str(finite.size)},
                  {'label': 'Infinite', 'value': str(int(_pylab_np.isinf(sample).sum()))}]
        complex_values = sample.dtype.kind == 'c'
        if complex_values:
            # Magnitudes give real, ordered statistics without silently discarding imaginary parts.
            finite = _pylab_np.abs(finite.astype(_pylab_np.clongdouble))
        else:
            finite = finite.astype(_pylab_np.longdouble)
        if finite.size:
            prefix = 'Magnitude ' if complex_values else ''
            with _pylab_np.errstate(over='ignore', invalid='ignore'):
                scale = _pylab_np.abs(finite).max()
                normalized = finite / scale if scale else finite
                metrics = [('Min', finite.min()), ('Max', finite.max()),
                           ('Mean', normalized.mean() * scale if scale else 0),
                           ('Std (population)', normalized.std() * scale if scale else 0)]
            result.extend({'label': prefix + metric, 'value': str(number)} for metric, number in metrics)
        summaries.append({'title': label or name, 'fields': result})
    return _pylab_json.dumps({'name': name, 'type': type(value).__name__, 'shape': shape,
                             'fields': fields, 'columns': summaries, 'notes': notes})


def _pylab_json_convert(value):
    if isinstance(value, _pylab_np.generic):
        value = value.item()
    if value is None or isinstance(value, (str, bool, int, float)):
        return value
    if isinstance(value, (list, tuple)):
        return [_pylab_json_convert(item) for item in value]
    if isinstance(value, dict):
        if not all(isinstance(k, str) for k in value):
            raise ValueError('JSON export requires dictionary keys to be strings.')
        return {k: _pylab_json_convert(v) for k, v in value.items()}
    raise ValueError('JSON export supports only strings, numbers, booleans, null, lists and dictionaries.')


def _pylab_format(value):
    if isinstance(value, _pylab_np.ndarray):
        # NPY object arrays require pickle and cannot be saved safely here.
        return None if value.dtype.hasobject else ('npy', 'NumPy array')
    if isinstance(value, (_pylab_pd.DataFrame, _pylab_pd.Series)):
        return ('csv', 'CSV table')
    if isinstance(value, str):
        return ('txt', 'Text')
    if isinstance(value, (_pylab_np.generic, int, float, bool, list, tuple, dict)) or value is None:
        return ('json', 'JSON')
    return None


def _pylab_numeric_columns(frame):
    return [(index, column) for index, (column, dtype) in enumerate(zip(frame.columns, frame.dtypes))
            if _pylab_pd.api.types.is_numeric_dtype(dtype)
            and not _pylab_pd.api.types.is_complex_dtype(dtype)]


def _pylab_plot_candidate(value):
    if isinstance(value, (_pylab_np.generic, int, float, bool)):
        try:
            return _pylab_np.asarray(value).dtype.kind in 'biuf' and bool(_pylab_np.isfinite(value))
        except (TypeError, ValueError):
            return False
    if isinstance(value, _pylab_pd.DataFrame):
        return bool(_pylab_numeric_columns(value))
    if isinstance(value, _pylab_pd.Series):
        return (_pylab_pd.api.types.is_numeric_dtype(value.dtype)
                and not _pylab_pd.api.types.is_complex_dtype(value.dtype))
    if isinstance(value, _pylab_np.ndarray):
        return (value.ndim in (1, 2) and value.dtype.kind in 'biuf' and value.size > 0)
    if isinstance(value, (list, tuple)):
        if not value:
            return False
        try:
            # Avoid converting a potentially enormous list just to populate the workspace menu.
            sample_values = []
            for row in value[:8]:
                if isinstance(row, _pylab_np.ndarray):
                    if row.ndim > 1:
                        return False
                    row = row[:33] if row.ndim else row
                elif isinstance(row, (list, tuple)):
                    row = row[:33]
                    if any(isinstance(item, (list, tuple, _pylab_np.ndarray)) for item in row):
                        return False
                sample_values.append(row)
            sample = _pylab_np.asarray(sample_values)
            return sample.ndim in (1, 2) and sample.dtype.kind in 'biuf'
        except (TypeError, ValueError):
            return False
    return False


def _pylab_actions_info(name):
    value = _pylab_variable(name)
    format_info = _pylab_format(value)
    can_plot = bool(_pylab_plot_candidate(value))
    return _pylab_json.dumps({
        'export': {'extension': format_info[0], 'label': format_info[1]} if format_info else None,
        'plot': can_plot,
        'plot_reason': '' if can_plot else 'Plotting requires a numeric one- or two-dimensional variable.',
    })


def _pylab_export(name, path, replace_existing=False):
    value = _pylab_variable(name)
    format_info = _pylab_format(value)
    if not format_info:
        raise ValueError('This variable type cannot be saved in a supported format.')
    extension, _label = format_info
    target = _PyLabPath(path).expanduser()
    if not target.is_absolute():
        raise ValueError('Choose an absolute file path.')
    if target.suffix.lower() != '.' + extension:
        raise ValueError('This variable must be saved as a .' + extension + ' file.')
    if not target.parent.is_dir():
        raise ValueError('The selected folder does not exist.')

    # Serialize values requiring validation before creating or replacing a file.
    text = None
    if extension == 'json':
        try:
            text = _pylab_json.dumps(_pylab_json_convert(value), ensure_ascii=False,
                                    allow_nan=False, indent=2) + '\n'
        except (TypeError, ValueError, RecursionError) as exc:
            raise ValueError('This value cannot be saved as JSON: ' + str(exc)) from exc
    elif extension == 'txt':
        text = value

    def write_file(handle):
        if extension == 'npy':
            _pylab_np.save(handle, value, allow_pickle=False)
        elif extension == 'csv':
            # Include the pandas index so rows remain identifiable on import.
            value.to_csv(handle, index=True)
        else:
            handle.write(text)

    binary = extension == 'npy'
    mode = 'wb' if binary else 'w'
    options = {} if binary else {'encoding': 'utf-8', 'newline': ''}
    if not replace_existing:
        # Exclusive creation ensures another process cannot race the save dialog.
        try:
            handle = open(target, 'xb' if binary else 'x', **options)
        except FileExistsError as exc:
            raise FileExistsError('That file already exists. Choose another name or confirm replacement.') from exc
        created = _pylab_os.fstat(handle.fileno())
        try:
            with handle:
                write_file(handle)
        except BaseException:
            try:
                if _pylab_os.path.samestat(created, _pylab_os.stat(target)):
                    _pylab_os.unlink(target)
            except OSError:
                pass
            raise
    else:
        # The caller may set this only after the native save panel confirms replacement.
        # Write to a sibling first so a serialization error cannot truncate existing data.
        fd, temporary = _pylab_tempfile.mkstemp(prefix='.pylab-export-', dir=str(target.parent))
        try:
            with _pylab_os.fdopen(fd, mode, **options) as handle:
                write_file(handle)
            _pylab_os.replace(temporary, target)
        finally:
            if _pylab_os.path.exists(temporary):
                _pylab_os.unlink(temporary)
    return _pylab_json.dumps({'path': str(target), 'format': extension})


def _pylab_plot(name, column=None, options=None):
    value = _pylab_variable(name)
    if column is not None:
        if not isinstance(column, int) or column < 0:
            raise ValueError('Invalid column selection.')
        if isinstance(value, _pylab_pd.DataFrame):
            if column >= value.shape[1]: raise ValueError('The selected column is no longer available.')
            value = value.iloc[:, column]
        elif isinstance(value, _pylab_pd.Series):
            if column != 0: raise ValueError('Invalid column selection.')
        else:
            array = _pylab_np.asarray(value)
            if array.ndim == 1 and column == 0: value = array
            elif array.ndim == 2 and column < array.shape[1]: value = array[:, column]
            else: raise ValueError('The selected column is no longer available.')
    if not _pylab_plot_candidate(value):
        raise ValueError('Plotting requires a numeric one- or two-dimensional variable.')
    if isinstance(value, _pylab_pd.DataFrame):
        columns = _pylab_numeric_columns(value)
        if len(columns) > 32:
            raise ValueError('The table has more than 32 numeric columns. Plot a selection instead.')
        if len(value) > 20000:
            raise ValueError('The variable has more than 20,000 rows. Plot a selection instead.')
        series = [(str(col), value.iloc[:, index].to_numpy(dtype=float, na_value=_pylab_np.nan)) for index, col in columns]
    elif isinstance(value, _pylab_pd.Series):
        if len(value) > 20000:
            raise ValueError('The variable has more than 20,000 rows. Plot a selection instead.')
        series = [(str(value.name or name), value.to_numpy(dtype=float, na_value=_pylab_np.nan))]
    else:
        if isinstance(value, (list, tuple)):
            if len(value) > 20000:
                raise ValueError('Plotting supports at most 20,000 rows and 32 columns. Plot a selection instead.')
            for row in value:
                if isinstance(row, _pylab_np.ndarray):
                    if row.ndim > 1 or (row.ndim == 1 and len(row) > 32):
                        raise ValueError('Plotting supports at most 20,000 rows and 32 columns. Plot a selection instead.')
                elif isinstance(row, (list, tuple)) and len(row) > 32:
                    raise ValueError('Plotting supports at most 20,000 rows and 32 columns. Plot a selection instead.')
        try:
            array = _pylab_np.asarray(value)
        except (TypeError, ValueError) as exc:
            raise ValueError('The variable must be a rectangular numeric array.') from exc
        if array.ndim == 0:
            array = array.reshape(1)
        if array.ndim not in (1, 2) or array.dtype.kind not in 'biuf' or array.size == 0:
            raise ValueError('The variable must be a nonempty one- or two-dimensional real numeric array.')
        rows = array.shape[0]
        columns = 1 if array.ndim == 1 else array.shape[1]
        if rows > 20000 or columns > 32:
            raise ValueError('Plotting supports at most 20,000 rows and 32 columns. Plot a selection instead.')
        series = [(name if columns == 1 else str(i), array if array.ndim == 1 else array[:, i])
                  for i in range(columns)]

    options = options if isinstance(options, dict) else {}
    title = str(options.get('title', name))[:256]
    xlabel = str(options.get('xlabel', 'Index'))[:256]
    ylabel = str(options.get('ylabel', ''))[:256]
    output_format = options.get('format', 'png')
    if output_format not in ('png', 'svg', 'pdf'):
        raise ValueError('Unsupported figure format.')
    # A standalone Figure does not alter pyplot's current figures, backend, or style.
    from matplotlib.figure import Figure
    from matplotlib.backends.backend_agg import FigureCanvasAgg
    fig = Figure(figsize=(8, 4.8), tight_layout=True)
    canvas = FigureCanvasAgg(fig)
    axes = fig.subplots()
    for label, data in series:
        axes.plot(data, label=label, marker='o' if len(data) == 1 else None)
    cursor = options.get('cursor', '')
    if cursor not in ('', None):
        try: cursor = int(cursor)
        except (TypeError, ValueError) as exc: raise ValueError('Data index must be a whole number.') from exc
        if cursor < 0 or any(cursor >= len(data) for _, data in series):
            raise ValueError('Data index is outside the plotted data.')
        axes.axvline(cursor, color='#777777', linestyle=':', linewidth=0.9)
        for label, data in series:
            point = float(data[cursor])
            if _pylab_np.isfinite(point):
                axes.scatter([cursor], [point], s=25, zorder=5)
                axes.annotate(f'{label}: ({cursor}, {point:.6g})', (cursor, point),
                              xytext=(6, 6), textcoords='offset points', fontsize=8)
    axes.set_title(title)
    axes.set_xlabel(xlabel)
    axes.set_ylabel(ylabel)
    for axis, setter in (('x', axes.set_xlim), ('y', axes.set_ylim)):
        lower, upper = options.get(axis + 'min', ''), options.get(axis + 'max', '')
        try:
            lower = None if lower in ('', None) else float(lower)
            upper = None if upper in ('', None) else float(upper)
        except (TypeError, ValueError) as exc:
            raise ValueError('Axis limits must be finite numbers.') from exc
        if any(value is not None and not _pylab_np.isfinite(value) for value in (lower, upper)):
            raise ValueError('Axis limits must be finite numbers.')
        if lower is not None and upper is not None and lower >= upper:
            raise ValueError('The minimum axis limit must be smaller than the maximum.')
        if lower is not None or upper is not None: setter(left=lower, right=upper) if axis == 'x' else setter(bottom=lower, top=upper)
    axes.grid(alpha=0.25)
    if options.get('legend', len(series) > 1):
        axes.legend()
    buffer = _pylab_io.BytesIO()
    if output_format == 'png': canvas.print_png(buffer)
    elif output_format == 'svg':
        from matplotlib.backends.backend_svg import FigureCanvasSVG
        FigureCanvasSVG(fig).print_svg(buffer)
    else:
        from matplotlib.backends.backend_pdf import FigureCanvasPdf
        FigureCanvasPdf(fig).print_pdf(buffer)
    return _pylab_json.dumps({output_format: _pylab_base64.b64encode(buffer.getvalue()).decode('ascii'), 'title': title})


def _pylab_import_mat(path):
    """Import public MATLAB variables without overwriting existing Python names."""
    from scipy.io import loadmat
    try:
        values = loadmat(path)
    except NotImplementedError as exc:
        raise ValueError('MATLAB v7.3 files need an HDF5 reader; save as v7 or earlier for this import.') from exc
    # Python normalizes identifiers before evaluating source. Normalize before
    # checking collisions, so every imported value can be reached by its name.
    normalized = {}
    invalid = []
    for key, value in values.items():
        if key.startswith('_'):
            continue
        name = _pylab_unicodedata.normalize('NFKC', key)
        if not name.isidentifier() or _pylab_keyword.iskeyword(name) or name.startswith('_'):
            invalid.append(key)
        elif name in normalized:
            raise ValueError('MAT file contains names that refer to the same Python identifier: ' + name)
        else:
            normalized[name] = value
    if invalid:
        raise ValueError('MAT file contains names that are not Python identifiers: ' + ', '.join(invalid))
    values = normalized
    namespace = get_ipython().user_ns
    conflicts = sorted(set(values).intersection(namespace))
    if conflicts:
        raise ValueError('Import stopped; these variables already exist: ' + ', '.join(conflicts))
    namespace.update(values)
    print('Imported MAT variables: ' + (', '.join(sorted(values)) or '(none)'))


def _pylab_export_mat(path, replace_existing=False):
    """Write supported variables atomically, replacing only when explicitly authorized."""
    from scipy.io import savemat
    import types
    namespace = get_ipython().user_ns
    values, skipped = {}, []
    for name, value in list(namespace.items()):
        if name.startswith('_') or name in ('In', 'Out', 'get_ipython', 'exit', 'quit', 'open'):
            continue
        if isinstance(value, (types.ModuleType, types.FunctionType, type)):
            continue
        if isinstance(value, (_pylab_np.ndarray, _pylab_np.generic, int, float, complex, bool, str)):
            if isinstance(value, _pylab_np.ndarray) and value.dtype.hasobject:
                skipped.append(name)
            else:
                values[name] = value
        else:
            skipped.append(name)
    if not values:
        raise ValueError('There are no supported numeric, string, or NumPy variables to export.')
    target = _PyLabPath(path).expanduser()
    if target.suffix.lower() != '.mat':
        raise ValueError('Choose a .mat file name.')
    fd, temporary = _pylab_tempfile.mkstemp(prefix='.pylab-mat-', suffix='.mat', dir=str(target.parent))
    _pylab_os.close(fd)
    try:
        savemat(temporary, values, appendmat=False)
        if replace_existing:
            _pylab_os.replace(temporary, target)
        else:
            # Link publishes the completed file exclusively, including if a file
            # appeared after the save dialog was dismissed.
            try:
                _pylab_os.link(temporary, target)
            except FileExistsError as exc:
                raise FileExistsError('That file already exists. Choose another name or confirm replacement.') from exc
    finally:
        if _pylab_os.path.exists(temporary):
            _pylab_os.unlink(temporary)
    print('Exported MAT variables: ' + ', '.join(sorted(values)))
    if skipped:
        print('Skipped unsupported variables: ' + ', '.join(sorted(skipped)))


def _pylab_import_data(path):
    """Import a supported data file under a safe, non-conflicting Python name."""
    target = _PyLabPath(path).expanduser()
    suffix = target.suffix.lower()
    if suffix == '.mat':
        return _pylab_import_mat(str(target))
    # Match the normalization performed by Python's parser. Regex \w also
    # accepts characters such as superscripts that cannot appear in identifiers.
    stem = _pylab_unicodedata.normalize('NFKC', target.stem)
    name = ''.join(char if ('a' + char).isidentifier() else '_' for char in stem).strip('_') or 'data'
    if not name.isidentifier(): name = 'data_' + name
    if _pylab_keyword.iskeyword(name): name += '_data'
    namespace = get_ipython().user_ns
    if name in namespace:
        raise ValueError('Import stopped; variable already exists: ' + name)
    if suffix == '.npy':
        value = _pylab_np.load(target, allow_pickle=False)
        if not isinstance(value, _pylab_np.ndarray):
            # np.load also accepts NPZ archives regardless of the extension.
            # Do not retain an open archive or publish an unusable variable.
            value.close()
            raise ValueError('Choose a single NumPy array saved as NPY, rather than an NPZ archive.')
    elif suffix == '.csv':
        value = _pylab_pd.read_csv(target)
    elif suffix in ('.xlsx', '.xls'):
        try: value = _pylab_pd.read_excel(target)
        except ImportError as exc: raise ValueError('Excel import requires the appropriate pandas Excel engine, such as openpyxl.') from exc
    else:
        raise ValueError('Choose a MAT, NPY, CSV, or Excel file.')
    namespace[name] = value
    print('Imported ' + str(target) + ' as ' + name)


def _pylab_export_as(name, path, replace_existing=False):
    """Export a variable by extension without truncating a failed destination."""
    value = _pylab_variable(name)
    target = _PyLabPath(path).expanduser()
    if not target.is_absolute() or not target.parent.is_dir():
        raise ValueError('Choose an absolute path in an existing folder.')
    suffix = target.suffix.lower()
    default = _pylab_format(value)
    if default and suffix == '.' + default[0]:
        return _pylab_export(name, path, replace_existing)
    if suffix not in ('.mat', '.csv', '.xlsx'):
        raise ValueError('This format is not supported for the selected variable.')
    if suffix == '.mat':
        if not isinstance(value, (_pylab_np.ndarray, _pylab_np.generic, int, float, complex, bool, str)) or (isinstance(value, _pylab_np.ndarray) and value.dtype.hasobject):
            raise ValueError('MAT export supports numeric values, strings, and non-object NumPy arrays.')
    elif suffix == '.csv':
        if not isinstance(value, (_pylab_np.ndarray, _pylab_pd.DataFrame, _pylab_pd.Series)):
            raise ValueError('CSV export supports arrays and tables.')
        if isinstance(value, _pylab_np.ndarray) and (value.ndim not in (1, 2) or value.dtype.hasobject):
            raise ValueError('CSV export supports one- and two-dimensional non-object arrays.')
    elif suffix == '.xlsx':
        if not isinstance(value, (_pylab_np.ndarray, _pylab_pd.DataFrame, _pylab_pd.Series)):
            raise ValueError('Excel export supports arrays and tables.')
        if isinstance(value, _pylab_np.ndarray) and (value.ndim not in (1, 2) or value.dtype.hasobject):
            raise ValueError('Excel export supports one- and two-dimensional non-object arrays.')
    fd, temporary = _pylab_tempfile.mkstemp(prefix='.pylab-export-', suffix=suffix, dir=str(target.parent))
    _pylab_os.close(fd)
    try:
        if suffix == '.mat':
            from scipy.io import savemat
            savemat(temporary, {name: value}, appendmat=False)
        elif suffix == '.csv':
            if isinstance(value, (_pylab_pd.DataFrame, _pylab_pd.Series)): value.to_csv(temporary, index=True)
            else:
                # savetxt does not quote delimiters or embedded newlines in
                # string arrays; use a real CSV writer to retain each value.
                rows = value.reshape(-1, 1) if value.ndim == 1 else value
                with open(temporary, 'w', encoding='utf-8', newline='') as handle:
                    _pylab_csv.writer(handle).writerows(rows)
        else:
            try:
                frame = value if isinstance(value, (_pylab_pd.DataFrame, _pylab_pd.Series)) else _pylab_pd.DataFrame(value)
                frame.to_excel(temporary, index=isinstance(value, (_pylab_pd.DataFrame, _pylab_pd.Series)))
            except ImportError as exc: raise ValueError('Excel export requires an Excel engine, such as openpyxl or xlsxwriter.') from exc
        if replace_existing:
            _pylab_os.replace(temporary, target)
        else:
            try: _pylab_os.link(temporary, target)
            except FileExistsError as exc: raise FileExistsError('That file already exists. Choose another name or confirm replacement.') from exc
    finally:
        if _pylab_os.path.exists(temporary): _pylab_os.unlink(temporary)
    return _pylab_json.dumps({'path': str(target), 'format': suffix[1:]})
