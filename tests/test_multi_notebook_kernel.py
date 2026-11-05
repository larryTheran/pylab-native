"""Notebook-scoped cell IDs and the console must share one live IPython namespace."""
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
    process.stdin.write(json.dumps(command) + '\n')
    process.stdin.flush()
def read_until(kind, wanted_id=None):
    observed = []
    while True:
        event = events.get(timeout=45)
        if event['type'] in ('fatal', 'workspace_error'):
            raise AssertionError(event)
        observed.append(event)
        if event['type'] == kind and (wanted_id is None or event.get('id') == wanted_id):
            return observed
try:
    read_until('ready')
    # Queue the cells together, as Run All does.
    send(type='execute', id='11111111-1111-1111-1111-111111111111|cell-A', source='cell', code='import numpy as np\nx = np.array([1, 2, 3])\nscale = 10')
    send(type='execute', id='22222222-2222-2222-2222-222222222222|cell-B', source='cell', code='y = x * scale\nx[0] = 99\nprint("22222222-2222-2222-2222-222222222222|cell-B", y.tolist())')
    send(type='execute', id='console-1', source='console', code='print("console", x.tolist(), y.tolist())')
    observed = read_until('finished', 'console-1')
    output = ''.join(event.get('text', '') for event in observed if event['type'] == 'stream')
    assert '22222222-2222-2222-2222-222222222222|cell-B [10, 20, 30]' in output, output
    assert 'console [99, 2, 3] [10, 20, 30]' in output, output
    send(type='workspace')
    rows = {row[0]: row for row in read_until('workspace')[-1]['rows']}
    assert rows['x'][5] == '22222222-2222-2222-2222-222222222222|cell-B' and rows['y'][5] == '22222222-2222-2222-2222-222222222222|cell-B', rows
    assert rows['scale'][5] == '11111111-1111-1111-1111-111111111111|cell-A', rows['scale']
    print('PASS: separate notebook-scoped cells and console share variables and run in order')
finally:
    if process.poll() is None:
        send(type='stop')
        process.wait(timeout=10)
