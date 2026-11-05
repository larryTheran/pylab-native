"""Exercise bounded statistics and safe live-name operations through IPython."""
import tempfile
import json
import math
import os
from pathlib import Path
import queue
import subprocess
import threading

python = os.environ.get('PYLAB_KERNEL_PYTHON', '/opt/miniconda3/bin/python3.12')
bridge = Path(__file__).resolve().parents[1] / 'Resources' / 'kernel_bridge.py'
process = subprocess.Popen([python, '-u', str(bridge)], cwd=tempfile.gettempdir(),
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
events = queue.Queue()
def read_events():
    for line in process.stdout:
        events.put(json.loads(line))
threading.Thread(target=read_events, daemon=True).start()
def send(**command):
    process.stdin.write(json.dumps(command) + '\n'); process.stdin.flush()
def receive(kind):
    while True:
        event = events.get(timeout=45)
        if event['type'] in ('fatal', 'workspace_error'):
            raise AssertionError(event)
        if event['type'] == kind:
            return event
def statistics(name, request_id):
    send(type='statistics', name=name, request_id=request_id)
    event = receive('statistics_result')
    assert event['request_id'] == request_id, event
    return event['result']
def numeric_fields(result, column=0):
    return {x['label']: x['value'] for x in result['columns'][column]['fields']}
def workspace():
    send(type='workspace')
    return {row[0]: row for row in receive('workspace')['rows']}

try:
    receive('ready')
    send(type='execute', id='cell-origin', code='''import numpy as np
import pandas as pd
values = np.array([1., 3., np.nan, np.inf, -np.inf])
alias = values
complex_values = np.array([3+4j, 0j])
huge = np.arange(2000000)
frame = pd.DataFrame({'x': pd.Series([1, None, 5], dtype='Int64'), 'label': ['a', None, 'c']})
label = 'hello'
empty = np.array([])
extreme = np.array([1e308, 1e308])
opposite = np.array([-1e308, 1e308])
noncontiguous = np.arange(400000).reshape(1000, 400).T
''')
    receive('finished')
    before = workspace()
    assert before['values'][5] == 'cell-origin', before['values']
    summary = statistics('values', 'stats-array')
    fields = numeric_fields(summary)
    assert fields['Count'] == '5' and fields['Missing (NaN)'] == '1'
    assert fields['Finite'] == '2' and fields['Infinite'] == '2'
    assert float(fields['Mean']) == 2 and float(fields['Std (population)']) == 1, fields
    assert float(numeric_fields(statistics('complex_values', 'stats-complex'))['Magnitude Mean']) == 2.5
    huge = statistics('huge', 'stats-bounded')
    assert numeric_fields(huge)['Count'] == '100000' and any('first 100,000' in n for n in huge['notes']), huge
    assert math.isclose(float(numeric_fields(huge)['Mean']), 49999.5, rel_tol=1e-14)
    assert numeric_fields(statistics('noncontiguous', 'stats-strided'))['Count'] == '100000'
    frame = statistics('frame', 'stats-frame')
    assert len(frame['columns']) == 1 and numeric_fields(frame)['Missing (NaN)'] == '1', frame
    assert float(numeric_fields(frame)['Mean']) == 3
    assert numeric_fields(statistics('empty', 'stats-empty'))['Finite'] == '0'
    assert float(numeric_fields(statistics('extreme', 'stats-extreme'))['Mean']) == 1e308
    assert float(numeric_fields(statistics('opposite', 'stats-opposite'))['Std (population)']) == 1e308
    assert not statistics('label', 'stats-label')['columns']
    # Validation never changes the namespace, including malicious-looking names.
    for i, bad in enumerate(['for', '_hidden', 'other name', 'frame', "x; values[:] = 0"]):
        send(type='rename', name='values', new_name=bad, request_id='bad-' + str(i))
        error = receive('action_error')
        assert error['action'] == 'rename' and error['request_id'] == 'bad-' + str(i), error
        assert 'values' in workspace()
    send(type='rename', name='values', new_name='measurements', request_id='rename-ok')
    assert receive('manage_result')['request_id'] == 'rename-ok'
    rows = workspace()
    assert 'values' not in rows and rows['measurements'][5] == 'cell-origin', rows
    # A selection has a fresh output ID while retaining its original cell ownership.
    send(type='execute', id='console-selection-1', source='cell', origin_id='cell-origin',
         code='selected_value = measurements[0]\nassert alias is measurements')
    receive('finished')
    assert workspace()['selected_value'][5] == 'cell-origin'
    assert workspace()['measurements'][5] == 'cell-origin'
    send(type='delete', name='measurements', request_id='delete-ok')
    assert receive('manage_result')['request_id'] == 'delete-ok'
    rows = workspace()
    assert 'measurements' not in rows and 'alias' in rows, rows
    send(type='statistics', name='measurements', request_id='gone')
    error = receive('action_error')
    assert error['request_id'] == 'gone' and error['action'] == 'statistics', error
    send(type='delete', name='measurements', request_id='gone-delete')
    assert receive('action_error')['request_id'] == 'gone-delete'
    print('PASS: bounded numeric statistics, nullable/complex/empty/strided data, validated rename/delete, aliases and cell ownership')
finally:
    if process.poll() is None:
        send(type='stop'); process.wait(timeout=10)
