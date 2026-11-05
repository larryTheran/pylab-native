"""The activity pid must identify the actual IPython child and clean up on stop."""
import tempfile
import json, os, queue, subprocess, threading, time
from pathlib import Path
bridge = Path(__file__).resolve().parents[1] / 'Resources/kernel_bridge.py'
p = subprocess.Popen([os.environ.get('PYLAB_KERNEL_PYTHON', '/opt/miniconda3/bin/python3.12'), '-u', str(bridge)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1, cwd=tempfile.gettempdir())
q = queue.Queue()
threading.Thread(target=lambda: [q.put(json.loads(line)) for line in p.stdout], daemon=True).start()
pid = None
try:
    ready = q.get(timeout=40)
    assert ready['type'] == 'ready', ready
    pid = ready['kernel_pid']
    assert isinstance(pid, int) and pid > 0 and pid != p.pid, ready
    os.kill(pid, 0)
    p.stdin.write(json.dumps(dict(type='execute', id='activity', code='import time; time.sleep(2); print("activity ready")')) + '\n'); p.stdin.flush()
    events = []
    while True:
        event = q.get(timeout=20); events.append(event)
        if event.get('type') == 'finished' and event.get('id') == 'activity': break
    assert any(e.get('type') == 'stream' and 'activity ready' in e.get('text', '') for e in events)
    print('PASS: ready identifies live IPython pid; ordinary execution remains intact')
finally:
    if p.poll() is None:
        p.stdin.write('{"type":"stop"}\n'); p.stdin.flush(); p.wait(timeout=10)
if pid:
    for _ in range(50):
        try: os.kill(pid, 0)
        except ProcessLookupError: break
        time.sleep(.1)
    else: raise AssertionError('IPython process was not cleaned up')
