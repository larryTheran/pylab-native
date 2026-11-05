"""Imported source keeps script startup context without losing IPython semantics."""
import json
import os
from pathlib import Path
import queue
import subprocess
import tempfile
import threading
import time

PYTHON = os.environ.get('PYLAB_KERNEL_PYTHON', '/opt/miniconda3/bin/python3.12')
BRIDGE = Path(__file__).resolve().parents[1] / 'Resources' / 'kernel_bridge.py'

class Bridge:
    def __init__(self, mode, cwd):
        env = dict(os.environ, PYLAB_VARIABLE_MODE=mode)
        self.p = subprocess.Popen([PYTHON, '-u', str(BRIDGE)], cwd=cwd, env=env,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, bufsize=1)
        self.events = queue.Queue()
        self.sequence = 0
        def read():
            for line in self.p.stdout:
                try: self.events.put(json.loads(line))
                except ValueError: self.events.put({'type': 'bad_json', 'text': line})
        threading.Thread(target=read, daemon=True).start()
        self.until(lambda e: e['type'] == 'ready')
    def send(self, **value):
        self.p.stdin.write(json.dumps(value) + '\n'); self.p.stdin.flush()
    def until(self, predicate, timeout=35):
        seen = []
        deadline = time.monotonic() + timeout
        while True:
            e = self.events.get(timeout=max(0.1, deadline-time.monotonic()))
            if e['type'] in ('fatal', 'bad_json'): raise AssertionError(e)
            seen.append(e)
            if predicate(e): return seen
    def execute(self, code, scope='cell-A', script=None, allowed_error=False):
        self.sequence += 1
        ident = 'ctx-' + str(self.sequence)
        command = dict(type='execute', id=ident, code=code, source='cell', scope_id=scope)
        if script is not None: command['script_path'] = script
        self.send(**command)
        observed = self.until(lambda e: e['type']=='finished' and e.get('id')==ident)
        errors = [e for e in observed if e['type']=='error' and e.get('id')==ident]
        if not allowed_error: assert not errors, errors
        return observed
    def close(self):
        if self.p.poll() is None:
            try: self.send(type='stop'); self.p.wait(timeout=10)
            except Exception:
                self.p.terminate()
                try: self.p.wait(timeout=3)
                except subprocess.TimeoutExpired: self.p.kill(); self.p.wait(timeout=3)
        if self.p.stdin: self.p.stdin.close()
        if self.p.stdout: self.p.stdout.close()
        if self.p.stderr: self.p.stderr.close()

with tempfile.TemporaryDirectory(prefix='pylab-script-context-') as temporary:
    root = (Path(temporary) / "project with 'quote 🚀").resolve()
    scripts = root / 'scripts'
    scripts.mkdir(parents=True)
    a = str(scripts / 'source A.py')
    b = str(scripts / 'source B.py')
    (scripts / 'pylab_context_neighbor.py').write_text("from pathlib import Path\nORIGIN=str(Path(__file__).resolve())\n", encoding='utf-8')
    restore = """
import sys
assert __file__ == 'old-notebook-file.py', __file__
assert __name__ == 'notebook_name', __name__
assert __package__ == 'notebook_package', __package__
assert sys.argv is _ctx_before_argv and sys.argv == ['notebook', '--not-a-script-option'], sys.argv
assert all(frame["context"] is None for frame in get_ipython()._pylab_script_context.frames)
"""
    for mode in ('shared', 'independent'):
        bridge = Bridge(mode, temporary)
        try:
            baseline = bridge.execute("""
import sys
__file__='old-notebook-file.py'
__name__='notebook_name'
__package__='notebook_package'
sys.argv=['notebook','--not-a-script-option']
_ctx_before_argv=sys.argv
_ctx_before_path=sys.path
""")
            previous = [e['count'] for e in baseline if e['type']=='execute_input'][-1]
            source = """from __future__ import annotations
import argparse, sys
from pathlib import Path
from pylab_context_neighbor import ORIGIN
assert __file__ == %r, __file__
assert __name__ == '__main__', __name__
assert __package__ is None
assert sys.argv == [%r], sys.argv
parser=argparse.ArgumentParser()
parser.add_argument('--steps',type=int,default=3)
ctx_args=parser.parse_args()
assert ctx_args.steps == 3
ctx_value=4
def ctx_function(): return ctx_value
if __name__ == '__main__': ctx_main_ran=True
sys.path.insert(0, %r)
_ctx_nested_empty=get_ipython().run_cell('',store_history=False)
_ctx_nested=get_ipython().run_cell('ctx_nested_file=__file__',store_history=False)
assert __file__ == %r and ctx_nested_file == %r
print('SCRIPT_CONTEXT_OK')
""" % (a, a, str(root), a, a)
            output = bridge.execute(source, script=a)
            assert [e['count'] for e in output if e['type']=='execute_input'][-1] == previous+1
            assert any('SCRIPT_CONTEXT_OK' in e.get('text','') for e in output)
            bridge.execute(restore + "\nctx_value=5\nassert ctx_function()==5\nassert ctx_main_ran\nassert ORIGIN==%r\nassert %r in sys.path\nassert %r not in sys.path\n" % (str(scripts/'pylab_context_neighbor.py'), str(root), str(scripts)))
            for bad_code, expected in [
                ("ctx_error_file=__file__\nraise RuntimeError('expected-script-error')", 'RuntimeError'),
                ("if True print('bad syntax')", 'SyntaxError'),
                ("raise SystemExit(0)", 'SystemExit'),
            ]:
                events = bridge.execute(bad_code, script=a, allowed_error=True)
                assert any(expected in e.get('text','') for e in events if e['type']=='error'), events
                bridge.execute(restore)
            # A whitespace cell must not arm context for the next ordinary cell.
            bridge.execute('  \n', script=a)
            bridge.execute(restore)
            # Await and native magics execute as unwrapped IPython source.
            bridge.execute("import asyncio\nawait asyncio.sleep(0.01)\n%%time ctx_magic_value=9\nassert __file__==%r\n" % a, script=a)
            bridge.execute(restore + "\nassert ctx_magic_value==9\n")
            # Run All queues different origins without leaking context.
            bridge.send(type='execute',id='queued-A',source='cell',scope_id='cell-A',script_path=a,
                code='ctx_queued_a=__file__\nprint("QUEUED_A", __file__)')
            bridge.send(type='execute',id='queued-B',source='cell',scope_id='cell-B',script_path=b,
                code='ctx_queued_b=__file__\nprint("QUEUED_B", __file__)')
            events=bridge.until(lambda e:e['type']=='finished' and e.get('id')=='queued-B')
            assert not [e for e in events if e['type']=='error'], events
            assert any('QUEUED_A '+a in e.get('text','') for e in events)
            assert any('QUEUED_B '+b in e.get('text','') for e in events)
            bridge.execute(restore+'\nassert ctx_queued_a==%r\n'%a)
            if mode == 'independent':
                bridge.execute("assert '__file__' not in globals()\nassert __name__=='__main__'\nassert ctx_queued_b==%r\nassert 'ctx_queued_a' not in globals()\n"%b, scope='cell-B')
            # Input waits keep context until the original cell resumes.
            bridge.send(type='execute',id='input-script',source='cell',scope_id='cell-A',script_path=a,
                code="ctx_input_file=__file__\nctx_answer=input('Context prompt: ')\nassert ctx_answer=='yes'\nassert __file__==%r"%a)
            prompt=bridge.until(lambda e:e['type']=='input_request')[-1]
            assert prompt.get('id')=='input-script', prompt
            bridge.send(type='input_reply',value='yes')
            replied=bridge.until(lambda e:e['type']=='finished' and e.get('id')=='input-script')
            assert not [e for e in replied if e['type']=='error'], replied
            bridge.execute(restore)
            # Interrupted code must restore before the finished event.
            bridge.send(type='execute',id='interrupt-script',source='cell',scope_id='cell-A',script_path=a,
                code="import time\nprint('CTX_RUNNING',flush=True)\nwhile True: time.sleep(0.05)")
            bridge.until(lambda e:e['type']=='stream' and e.get('id')=='interrupt-script' and 'CTX_RUNNING' in e.get('text',''))
            bridge.send(type='interrupt')
            interrupted=bridge.until(lambda e:e['type']=='finished' and e.get('id')=='interrupt-script')
            assert any('KeyboardInterrupt' in e.get('text','') for e in interrupted), interrupted
            bridge.execute(restore)
            for invalid in ['relative.py', 42, '/tmp/a\x00.py']:
                events=bridge.execute('ctx_malformed_ran=True',script=invalid,allowed_error=True)
                assert any(e['type']=='error' for e in events)
            bridge.execute(restore+"\nassert 'ctx_malformed_ran' not in globals()\n")
            print('PASS:',mode,'script filename/main/argv, imports, globals, queued scopes, errors/interrupts, magics/await and clean restoration')
        finally: bridge.close()
