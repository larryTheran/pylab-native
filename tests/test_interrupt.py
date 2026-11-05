import tempfile
import json,subprocess,threading,queue,os,time,psutil
from pathlib import Path
p=subprocess.Popen([os.environ.get('PYLAB_KERNEL_PYTHON', '/opt/miniconda3/bin/python3.12'),'-u',str(Path(__file__).resolve().parents[1] / 'Resources' / 'kernel_bridge.py')],cwd=tempfile.gettempdir(),env=os.environ.copy(),stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True,bufsize=1)
q=queue.Queue(); threading.Thread(target=lambda:[q.put(json.loads(x)) for x in p.stdout],daemon=True).start()
def send(**o): p.stdin.write(json.dumps(o)+'\n'); p.stdin.flush()
def take(t):
 while True:
  e=q.get(timeout=30)
  if e['type']=='fatal': raise AssertionError(e)
  if e['type']==t:return e
try:
 take('ready'); children=psutil.Process(p.pid).children(); assert children
 send(type='execute',id='clear',code='from IPython.display import clear_output\nprint("old")\nclear_output(wait=True)\nprint("new")')
 e=take('clear_output'); assert e['wait'] is True
 take('finished')
 send(type='execute',id='interrupt',code='import time\ntime.sleep(60)')
 take('execute_input'); send(type='interrupt')
 assert 'KeyboardInterrupt' in take('error')['text']
 take('finished')
 p.terminate(); p.wait(timeout=10)
 deadline=time.monotonic()+5
 while time.monotonic()<deadline and any(c.is_running() and c.status()!=psutil.STATUS_ZOMBIE for c in children):time.sleep(.1)
 assert not any(c.is_running() and c.status()!=psutil.STATUS_ZOMBIE for c in children)
 print('Deferred clear, interrupt, and SIGTERM cleanup passed')
finally:
 if p.poll() is None:p.kill()
