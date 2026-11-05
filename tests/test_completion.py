"""Completion requests reach the live kernel and preserve request correlation."""
import tempfile
import json, os, queue, subprocess, threading
from pathlib import Path
python = os.environ.get('PYLAB_KERNEL_PYTHON', '/opt/miniconda3/bin/python3.12')
bridge = Path(__file__).resolve().parents[1] / 'Resources' / 'kernel_bridge.py'
p = subprocess.Popen([python, '-u', str(bridge)], cwd=tempfile.gettempdir(), stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
q = queue.Queue()
def reader():
    for line in p.stdout: q.put(json.loads(line))
threading.Thread(target=reader, daemon=True).start()
def send(**cmd): p.stdin.write(json.dumps(cmd) + '\n'); p.stdin.flush()
def receive(kind):
    while True:
        event = q.get(timeout=40)
        if event['type'] in ('fatal', 'workspace_error'): raise AssertionError(event)
        if event['type'] == kind: return event
try:
    receive('ready')
    send(type='execute', id='test-cell', source='cell', code='pylab_example_variable = 42')
    receive('finished')
    text = 'pylab_example_var'
    send(type='complete', request_id='completion-test', code=text, cursor_pos=len(text))
    event = receive('complete_result')
    assert event['request_id'] == 'completion-test', event
    assert 'pylab_example_variable' in event['matches'], event
    assert event['cursor_start'] == 0 and event['cursor_end'] == len(text), event
    print('PASS: live kernel completion and request correlation')
finally:
    if p.poll() is None:
        send(type='stop'); p.wait(timeout=10)
