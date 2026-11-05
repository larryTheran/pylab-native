"""Exercise per-cell ownership and queued executions against a real IPython kernel."""
import tempfile
import json
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
        event = events.get(timeout=35)
        if event['type'] in ('fatal', 'workspace_error'):
            raise AssertionError(event)
        if event['type'] == kind:
            return event

def workspace():
    send(type='workspace')
    return {row[0]: row for row in receive('workspace')['rows']}

try:
    receive('ready')
    # Submit without waiting, as Run All does: each snapshot must be ordered.
    send(type='execute', id='cell-A', code='import numpy as np\na = np.arange(4)\nscalar = 1\nsame = 5')
    send(type='execute', id='cell-B', code='scalar = 2\nfoo = 7\nsame = 5')
    send(type='execute', id='console-123', source='console', code='a[0] = 9\nbar = 3\nprint(scalar)')
    send(type='execute', id='cell-C', code='partial = 17\nraise RuntimeError("expected")')
    rows = workspace()
    assert rows['a'][5] == 'internal:console', rows['a']
    assert rows['scalar'][5] == 'cell-B', rows['scalar']
    assert rows['same'][5] == 'cell-B', rows['same'] # interned value, explicit assignment
    assert rows['foo'][5] == 'cell-B', rows['foo']
    assert rows['bar'][5] == 'internal:console', rows['bar']
    assert rows['partial'][5] == 'cell-C', rows['partial'] # partial failure still tracked
    assert rows['a'][6:9] == ['npy', 'NumPy array', True], rows['a']
    assert rows['scalar'][6:9] == ['json', 'JSON', True], rows['scalar']
    send(type='execute', id='cell-D', code='print(scalar, a)')
    rows = workspace()
    assert rows['scalar'][5] == 'cell-B' and rows['a'][5] == 'internal:console', rows
    send(type='execute', id='cell-E', code='del a\nfoo = 8')
    rows = workspace()
    assert 'a' not in rows and rows['foo'][5] == 'cell-E', rows
    send(type='execute', id='console-valid-cell-id', source='cell', code='a = np.array([1,2])')
    rows = workspace()
    assert rows['a'][5] == 'console-valid-cell-id', rows['a']
    send(type='execute', id='table-origin', code='import pandas as pd\ndf = pd.DataFrame({"x": [2, 1]})')
    send(type='execute', id='table-copy', code='df2 = df.sort_values("x")')
    rows = workspace()
    assert rows['df'][5] == 'table-origin' and rows['df2'][5] == 'table-copy', rows
    send(type='execute', id='table-mutated', code='df.sort_values("x", inplace=True)')
    rows = workspace()
    assert rows['df'][5] == 'table-mutated', rows['df']
    print('PASS: queued cell/console ownership, mutation, partial failures, reading, deletion, recreation, and pandas in-place detection')
finally:
    if process.poll() is None:
        send(type='stop'); process.wait(timeout=10)
