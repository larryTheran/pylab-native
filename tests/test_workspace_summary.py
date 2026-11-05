"""Exercise workspace display summaries against a real, isolated IPython kernel."""
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
def receive(kind):
    while True:
        event = events.get(timeout=35)
        if event['type'] in ('fatal', 'workspace_error'):
            raise AssertionError(event)
        if event['type'] == kind:
            return event
try:
    receive('ready')
    send(type='execute', id='setup', code='''import numpy as np
import pandas as pd
scalar = 3.25
label = "example"
values = [90, 72, 36]
arr = np.arange(600000).reshape(600, 1000)
table = pd.DataFrame({"a": [1, 2], "b": [3, 4]})
series = pd.Series([2, 4, 6])
''')
    receive('finished')
    send(type='workspace')
    rows = {row[0]: row for row in receive('workspace')['rows']}
    assert rows['scalar'][1:5] == ['float', '1 × 1', '3.25', False], rows['scalar']
    assert rows['label'][1:5] == ['str', '7 chars', "'example'", False], rows['label']
    assert rows['values'][1:5] == ['list', '3 items', '[90, 72, 36]', False], rows['values']
    assert rows['arr'][1] == 'ndarray' and rows['arr'][2] == '600 × 1000', rows['arr']
    assert len(rows['arr'][3]) <= 160 and '...' in rows['arr'][3] and rows['arr'][4], rows['arr']
    assert rows['table'][1:5] == ['DataFrame', '2 × 2', '<table>', True], rows['table']
    assert rows['series'][1:5] == ['Series', '3 × 1', '[2, 4, 6]', True], rows['series']
    send(type='execute', id='check', code='print(int(arr[0, 0]), int(arr[-1, -1]), scalar, label, values)')
    output = ''
    while True:
        event = events.get(timeout=35)
        if event['type'] == 'stream': output += event['text']
        if event['type'] == 'finished': break
    assert '0 599999 3.25 example [90, 72, 36]' in output, output
    print('Workspace summaries show bounded, meaningful values and sizes without altering variables.')
finally:
    if process.poll() is None:
        send(type='stop')
        process.wait(timeout=10)
