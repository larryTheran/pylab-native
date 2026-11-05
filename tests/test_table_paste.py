"""Batch table paste validates before updating and preserves array aliases."""
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
def send(**cmd): p.stdin.write(json.dumps(cmd)+'\n'); p.stdin.flush()
def receive(kind):
    while True:
        event=q.get(timeout=40)
        if event['type']=='fatal': raise AssertionError(event)
        if event['type']==kind: return event
try:
    receive('ready')
    send(type='execute', id='setup', source='cell', code='import numpy as np\na = np.zeros((2,2), dtype=int)\nalias = a')
    receive('finished')
    send(type='paste', name='a', row=0, column=0, values=[['1','2'],['3','4']])
    receive('edit')
    send(type='execute', id='verify', source='cell', code='print(alias.tolist())')
    chunks=[]
    while True:
        event=q.get(timeout=40)
        if event['type']=='stream' and event.get('id')=='verify': chunks.append(event['text'])
        if event['type']=='finished' and event.get('id')=='verify': break
    assert '[[1, 2], [3, 4]]' in ''.join(chunks), chunks
    send(type='paste', name='a', row=0, column=0, values=[['8','invalid']])
    receive('workspace_error')
    send(type='table', name='a', offset=0)
    table=receive('table')
    assert table['cells'][0] == ['1','2'], table
    send(type='execute', id='setup-df', source='cell', code="import pandas as pd\ndf = pd.DataFrame({'a': [1, 2, 3], 'b': ['old', 'keep', 'end']})\ndf_alias = df")
    receive('finished')
    send(type='paste', name='df', row=0, column=0, values=[['8', "'new'"], ['9']])
    receive('edit')
    send(type='execute', id='verify-df', source='cell', code="print(df_alias.to_dict('list'))")
    chunks=[]
    while True:
        event=q.get(timeout=40)
        if event['type']=='stream' and event.get('id')=='verify-df': chunks.append(event['text'])
        if event['type']=='finished' and event.get('id')=='verify-df': break
    assert "'a': [8, 9, 3]" in ''.join(chunks) and "'b': ['new', 'keep', 'end']" in ''.join(chunks), chunks
    print('PASS: multi-cell paste, validation, ragged rows, and shared array/table identity')
finally:
    if p.poll() is None: send(type='stop'); p.wait(timeout=10)
