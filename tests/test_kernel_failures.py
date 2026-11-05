"""Correlated protocol errors, acknowledged folders and unexpected-kernel cleanup."""
import json
import os
from pathlib import Path
import queue
import subprocess
import tempfile
import threading
import time

python = os.environ.get('PYLAB_KERNEL_PYTHON', '/opt/miniconda3/bin/python3.12')
bridge = Path(__file__).resolve().parents[1] / 'Resources' / 'kernel_bridge.py'
process = subprocess.Popen([python, '-u', str(bridge)], cwd=tempfile.gettempdir(),
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
events = queue.Queue()
def reader():
    for line in process.stdout:
        events.put(json.loads(line))
threading.Thread(target=reader, daemon=True).start()
def send(**command):
    process.stdin.write(json.dumps(command) + '\n')
    process.stdin.flush()
def receive(kind, ident=None, timeout=40):
    deadline=time.monotonic() + timeout
    while True:
        event=events.get(timeout=max(0.01, deadline-time.monotonic()))
        if event['type'] == kind and (ident is None or event.get('request_id') == ident or event.get('id') == ident):
            return event
        if event['type'] == 'fatal': raise AssertionError(event)
try:
    receive('ready')
    send(type='plot', request_id='bad-plot')
    assert receive('action_error', 'bad-plot')['action'] == 'plot'
    send(type='chdir', request_id='bad-directory')
    assert receive('action_error', 'bad-directory')['action'] == 'chdir'
    send(type='complete', request_id='bad-completion', code='abc', cursor_pos='not-an-integer')
    assert receive('complete_result', 'bad-completion')['matches'] == []
    send(type='execute', id='bad-code', code=['invalid', 'source'])
    assert 'source text' in receive('error', 'bad-code')['text']
    receive('finished', 'bad-code')
    with tempfile.TemporaryDirectory(prefix='pylab-directory-test-') as directory:
        send(type='chdir', path=directory, request_id='valid-directory')
        assert Path(receive('directory_result', 'valid-directory')['path']).resolve() == Path(directory).resolve()
        send(type='chdir', path=directory + '/missing', request_id='missing-directory')
        assert receive('action_error', 'missing-directory')['action'] == 'chdir'
        send(type='execute', id='directory-check', code='import os\nprint("Working folder:", os.getcwd())')
        assert directory in receive('stream', 'directory-check')['text']
        receive('finished', 'directory-check')
        # Killing the IPython child must wake the bridge even with stdin still open.
        started=time.monotonic()
        send(type='execute', id='child-exit', code='import os\nos._exit(9)')
        failure=receive('fatal', timeout=8)
        assert 'stopped unexpectedly' in failure['text'], failure
        process.wait(timeout=8)
        assert time.monotonic()-started < 8
    print('PASS: malformed requests return correlated errors, folders acknowledge success/failure, unexpected child death stops bridge promptly')
finally:
    if process.poll() is None:
        send(type='stop')
        process.wait(timeout=10)
