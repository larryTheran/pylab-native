"""Actual Jupyter regression for independent cell variable namespaces."""
import json
import os
from pathlib import Path
import queue
import subprocess
import tempfile
import threading

root=Path(__file__).resolve().parents[1]
python=os.environ.get('PYLAB_KERNEL_PYTHON','/opt/miniconda3/bin/python3.12')
env=os.environ.copy();env['PYLAB_VARIABLE_MODE']='independent'
p=subprocess.Popen([python,'-u',str(root/'Resources/kernel_bridge.py')],cwd=tempfile.gettempdir(),env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True,bufsize=1)
q=queue.Queue()
def read():
 for line in p.stdout:
  try:q.put(json.loads(line))
  except Exception:q.put({'type':'bad_json','text':line})
threading.Thread(target=read,daemon=True).start()
def send(**cmd):
 p.stdin.write(json.dumps(cmd)+'\n');p.stdin.flush()
def until(kind,ident=None,request_id=None):
 result=[]
 while True:
  e=q.get(timeout=45);result.append(e)
  assert e['type'] not in ('fatal','workspace_error','bad_json'),e
  if e['type']==kind and (ident is None or e.get('id')==ident) and (request_id is None or e.get('request_id')==request_id):return result
def run(scope,code,ident=None,source='cell'):
 ident=ident or scope
 send(type='execute',id=ident,code=code,source=source,scope_id=scope)
 return until('finished',ident)
def output(events):return ''.join(e.get('text','') for e in events if e['type'] in ('stream','result'))
def action(kind,scope,request,**kwargs):
 send(type=kind,scope_id=scope,request_id=request,**kwargs)
 return until({'statistics':'statistics_result','rename':'manage_result','delete':'manage_result','export_as':'export_result','plot':'plot_result'}[kind],request_id=request)[-1]
def workspace():
 send(type='workspace');return until('workspace')[-1]['rows']
try:
 until('ready')
 # Queue different scopes as Run All does; same-name globals and functions must
 # resolve their own module even after another scope is installed.
 send(type='execute',id='book1|A',source='cell',code='import numpy as np\nx = 10\nonly_a = 123\na = np.array([1,2,3])\ndef f(): return x\nclass C:\n    def value(self): return x\nx')
 send(type='execute',id='book1|B',source='cell',code='import numpy as np\nx = 20\na = np.array([7,8,9])\ndef f(): return x\nprint("B", f(), "only_a" in globals(), list(Out.values()))')
 ev=until('finished','book1|B');text=output(ev)
 assert 'B 20 False []' in text,text
 ev=run('book1|A','print("A", f(), C().value(), only_a, list(Out.values()))\nx = 11\nprint("changed", f())')
 assert 'A 10 10 123 [10]' in output(ev) and 'changed 11' in output(ev),ev
 ev=run('book1|B','print("B2", f(), "only_a" in globals(), any(("only_a"+" = 123") in s for s in In))')
 assert 'B2 20 False False' in output(ev),ev
 # A missing name raises in B rather than inheriting A, while later code runs.
 ev=run('book1|B','only_a')
 assert any(e['type']=='error' and 'NameError' in e['text'] for e in ev),ev
 ev=run('book1|B','print("still", x)')
 assert 'still 20' in output(ev)
 ev=run('book1|A','print("console",x); from_console=88',ident='console-A',source='console')
 assert 'console 11' in output(ev)
 ev=run('book1|B','print("from_console" in globals())')
 assert 'False' in output(ev)
 rows=workspace();duplicates=[r for r in rows if r[0]=='x']
 assert len(duplicates)==2 and {r[9] for r in duplicates}=={'book1|A','book1|B'},rows
 assert all(r[5]==r[9] for r in rows),rows
 # Every workspace action must target the chosen copy of the same-name value.
 send(type='table',scope_id='book1|A',name='a',offset=0)
 e=until('table')[-1];assert e['cells'][0][0]=='1' and e['scope_id']=='book1|A',e
 send(type='edit',scope_id='book1|A',name='a',row=0,column=0,literal='99')
 e=until('edit')[-1];assert e['scope_id']=='book1|A',e
 send(type='table',scope_id='book1|B',name='a',offset=0)
 e=until('table')[-1];assert e['cells'][0][0]=='7' and e['scope_id']=='book1|B',e
 send(type='paste',scope_id='book1|B',name='a',row=1,column=0,values=[['77']])
 until('edit')
 send(type='table',scope_id='book1|A',name='a',offset=0)
 e=until('table')[-1];assert [r[0] for r in e['cells']]==['99','2','3'],e
 stat=action('statistics','book1|B','stat',name='a')['result']
 assert stat['name']=='a' and stat['type']=='ndarray',stat
 with tempfile.TemporaryDirectory() as directory:
  path=Path(directory)/'a.npy'
  action('export_as','book1|B','export',name='a',path=str(path))
  import numpy as np
  assert np.load(path).tolist()==[7,77,9]
  imported=Path(directory)/'scoped_import.npy'
  np.save(imported,np.array([31,32]))
  run('book1|B', '_pylab_import_data(' + repr(str(imported)) + ')')
  imported_rows=[r for r in workspace() if r[0]=='scoped_import']
  assert len(imported_rows)==1 and imported_rows[0][9]=='book1|B',imported_rows
 plot=action('plot','book1|A','plot',name='a')['result']
 assert len(plot['png'])>50,plot.keys()
 e=action('rename','book1|A','rename',name='x',new_name='renamed_x')
 assert e['scope_id']=='book1|A',e
 action('delete','book1|A','delete',name='renamed_x')
 rows=workspace();assert [r[9] for r in rows if r[0]=='x']==['book1|B'],rows
 # Selected-code execution uses origin_id if scope_id is absent.
 send(type='execute',id='console-selection-A',source='cell',origin_id='book1|A',code='selected_value=555')
 until('finished','console-selection-A')
 ev=run('book1|A','print("selected", selected_value)')
 assert 'selected 555' in output(ev)
 # Native completion is scoped and imported code still uses native IPython.
 send(type='complete',request_id='comp-A',scope_id='book1|A',code='only_',cursor_pos=5)
 e=until('complete_result',request_id='comp-A')[-1];assert 'only_a' in e['matches'],e
 send(type='complete',request_id='comp-B',scope_id='book1|B',code='only_',cursor_pos=5)
 e=until('complete_result',request_id='comp-B')[-1];assert 'only_a' not in e['matches'],e
 ev=run('book1|A','%who\nprint("magic", only_a)')
 assert 'magic 123' in output(ev),ev
 # Errors carry scope context; malformed scopes must not switch a cell.
 send(type='table',scope_id='book1|B',name='only_a',offset=0)
 while True:
  e=q.get(timeout=45)
  if e['type']=='workspace_error':break
 assert e['scope_id']=='book1|B',e
 ev=run('book1|A','print("retained", only_a)')
 assert 'retained 123' in output(ev)
 # Native rich display, input requests and top-level async still execute in
 # the selected namespace, without a custom exec wrapper changing semantics.
 ev=run('book1|B','import matplotlib.pyplot as plt\nplt.plot([1,2]); plt.show()')
 assert any(e['type']=='image' and len(e['image'])>50 for e in ev),ev
 send(type='execute',id='input-B',source='console',scope_id='book1|B',code='answer=input("Scoped input? "); print("input",x,answer)')
 until('input_request','input-B')
 send(type='input_reply',value='hello')
 ev=until('finished','input-B');assert 'input 20 hello' in output(ev),ev
 ev=run('book1|B','import asyncio\nawait asyncio.sleep(0)\nprint("async",x)')
 assert 'async 20' in output(ev),ev
 # Reset clears only its cell. Restoring infrastructure permits later actions.
 ev=run('book1|C','temporary=7\n%reset -f\nprint("reset", "temporary" in globals())')
 assert 'reset False' in output(ev),ev
 run('book1|C','kept=9')
 rows=workspace();assert any(r[0]=='kept' and r[9]=='book1|C' for r in rows),rows
 assert any(r[0]=='only_a' and r[9]=='book1|A' for r in rows),rows
 send(type='execute',id='console-fallback',source='console',code='fallback_value=321')
 until('finished','console-fallback')
 rows=workspace();assert any(r[0]=='fallback_value' and r[9]=='internal:console' for r in rows),rows
 print('PASS: isolated globals/functions/history, Run All ordering, selected console, aggregate duplicate names, scoped tables/edits/paste/export/plot/statistics/rename/delete/completion and native magics/rich output/input/async/reset/import')
finally:
 if p.poll() is None:
  send(type='stop');p.wait(timeout=15)
