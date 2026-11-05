import tempfile
import json, subprocess, os, queue, threading
from pathlib import Path
p=subprocess.Popen([os.environ.get('PYLAB_KERNEL_PYTHON', '/opt/miniconda3/bin/python3.12'),'-u',str(Path(__file__).resolve().parents[1] / 'Resources' / 'kernel_bridge.py')],cwd=tempfile.gettempdir(),env=os.environ.copy(),stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True,bufsize=1)
q=queue.Queue()
threading.Thread(target=lambda:[q.put(json.loads(line)) for line in p.stdout],daemon=True).start()
def send(**obj): p.stdin.write(json.dumps(obj)+'\n'); p.stdin.flush()
def expect(kind):
 while True:
  event=q.get(timeout=35)
  if event['type'] in ('fatal','workspace_error'): raise AssertionError(event)
  if event['type']==kind: return event
try:
 print(expect('ready'))
 send(type='execute',id='one',code='import numpy as np\na=np.arange(6).reshape(2,3)\nprint("hello")\nimport matplotlib.pyplot as plt\nplt.plot([1,2]); plt.show()')
 outputs=[]
 while True:
  event=q.get(timeout=35); outputs.append(event)
  if event['type']=='finished': break
 assert any(e['type']=='stream' and 'hello' in e['text'] for e in outputs), outputs
 assert any(e['type']=='image' and len(e['image'])>50 for e in outputs)
 send(type='workspace'); e=expect('workspace'); assert any(x[0]=='a' for x in e['rows'])
 send(type='table',name='a',offset=0); e=expect('table'); assert e['cells'][1][2]=='5'
 send(type='edit',name='a',row=1,column=2,literal='19'); expect('edit')
 send(type='table',name='a',offset=0); e=expect('table'); assert e['cells'][1][2]=='19'
 print('Bridge execution, inline image, workspace, and array edits passed')
finally:
 send(type='stop'); p.wait(timeout=10)
