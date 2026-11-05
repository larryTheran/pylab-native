"""Exercise save/plot through the actual asynchronous Jupyter bridge."""
import base64
import json
import os
from pathlib import Path
import queue
import subprocess
import tempfile
import threading

python = os.environ.get('PYLAB_KERNEL_PYTHON', '/opt/miniconda3/bin/python3.12')
bridge = Path(__file__).resolve().parents[1] / 'Resources' / 'kernel_bridge.py'
process = subprocess.Popen([python, '-u', str(bridge)], cwd=tempfile.gettempdir(),
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
events = queue.Queue()
def read_events():
    for line in process.stdout: events.put(json.loads(line))
threading.Thread(target=read_events, daemon=True).start()
def send(**command):
    process.stdin.write(json.dumps(command) + '\n'); process.stdin.flush()
def receive(kind):
    while True:
        event = events.get(timeout=45)
        if event['type'] in ('fatal', 'workspace_error'): raise AssertionError(event)
        if event['type'] == kind: return event

try:
    receive('ready')
    send(type='execute', id='cell-A', code='import numpy as np\na = np.arange(8).reshape(4, 2)\ntext = "hello"\nscalar = 12.5')
    receive('finished')
    with tempfile.TemporaryDirectory(prefix='pylab-export-test-') as tmp:
        path = str(Path(tmp) / 'a.npy')
        send(type='export', name='a', path=path, request_id='save1')
        result = receive('export_result')
        assert result['request_id'] == 'save1' and result['result']['path'] == path, result
        import numpy as np
        assert np.load(path, allow_pickle=False).tolist() == [[0, 1], [2, 3], [4, 5], [6, 7]]
        before = Path(path).read_bytes()
        send(type='export', name='a', path=path, request_id='save2')
        error = receive('action_error')
        assert error['request_id'] == 'save2' and Path(path).read_bytes() == before, error
        mat_path = str(Path(tmp) / 'a.mat')
        send(type='export_as', name='a', path=mat_path, request_id='save-mat')
        mat_result = receive('export_result')
        assert mat_result['request_id'] == 'save-mat' and Path(mat_path).is_file(), mat_result
        send(type='export_as', name='a', path=mat_path, request_id='save-mat-conflict')
        mat_error = receive('action_error')
        assert mat_error['request_id'] == 'save-mat-conflict' and mat_error['action'] == 'export_as', mat_error
        send(type='plot', name='a', column=1, options={'format': 'svg', 'cursor': '2'}, request_id='svg-figure')
        vector = receive('plot_result')
        assert vector['request_id'] == 'svg-figure' and b'<svg' in base64.b64decode(vector['result']['svg']), vector
        send(type='plot', name='a', request_id='figure1')
        figure = receive('plot_result')
        assert figure['request_id'] == 'figure1'
        assert base64.b64decode(figure['result']['png']).startswith(b'\x89PNG\r\n\x1a\n')
        send(type='plot', name='scalar', request_id='scalar-figure')
        scalar_figure = receive('plot_result')
        assert scalar_figure['request_id'] == 'scalar-figure'
        assert base64.b64decode(scalar_figure['result']['png']).startswith(b'\x89PNG\r\n\x1a\n')
        send(type='plot', name='text', request_id='figure2')
        error = receive('action_error')
        assert error['request_id'] == 'figure2' and error['action'] == 'plot', error
    print('PASS: correlated save, safe existing file, PNG plotting, and errors')
finally:
    if process.poll() is None:
        send(type='stop'); process.wait(timeout=10)
