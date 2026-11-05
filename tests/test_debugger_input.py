"""Exercise debugger stepping through real Jupyter input requests."""
import tempfile
import json, os, queue, subprocess, threading
from pathlib import Path
python = os.environ.get('PYLAB_KERNEL_PYTHON', '/opt/miniconda3/bin/python3.12')
bridge = Path(__file__).resolve().parents[1] / 'Resources' / 'kernel_bridge.py'
p = subprocess.Popen([python, '-u', str(bridge)], cwd=tempfile.gettempdir(), stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
q = queue.Queue()
def read():
    for line in p.stdout: q.put(json.loads(line))
threading.Thread(target=read, daemon=True).start()
def send(**obj): p.stdin.write(json.dumps(obj)+'\n'); p.stdin.flush()
def take(kind):
    observed = []
    while True:
        event = q.get(timeout=40); observed.append(event)
        if event['type'] in ('fatal', 'workspace_error'): raise AssertionError(event)
        if event['type'] == kind: return event, observed
try:
    take('ready')
    code = """import pdb as _pylab_debugger, linecache as _pylab_linecache
_pylab_debug_source = 'debug_value = 2\\ndebug_value += 3'
_pylab_debug_file = '<pylab-test-cell>'
_pylab_linecache.cache[_pylab_debug_file] = (len(_pylab_debug_source), None, _pylab_debug_source.splitlines(True), _pylab_debug_file)
_pylab_debug_session = _pylab_debugger.Pdb()
_pylab_debug_error = _pylab_debug_session.set_break(_pylab_debug_file, 2)
if _pylab_debug_error: print(_pylab_debug_error)
_pylab_debug_session.run(compile(_pylab_debug_source, _pylab_debug_file, 'exec'), globals(), globals())
"""
    send(type='execute', id='debug-test', source='cell', code=code)
    request, events = take('input_request')
    assert request.get('id') == 'debug-test', request
    send(type='input_reply', value='n')
    take('input_request')
    send(type='input_reply', value='c')
    take('finished')
    send(type='execute', id='verify', source='cell', code='print(debug_value)')
    _, events = take('finished')
    assert any('5' in e.get('text', '') for e in events), events
    print('PASS: debugger input, stepping, continue, and shared workspace')
finally:
    if p.poll() is None: send(type='stop'); p.wait(timeout=10)
