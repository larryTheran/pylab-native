"""Small JSON-lines bridge between the native UI and an IPython kernel."""
import ast
import json
import os
import sys
import threading
import queue
import signal
from pathlib import Path
try:
    from jupyter_client import KernelManager
    from jupyter_client.kernelspec import KernelSpec
except ImportError as exc:
    print(json.dumps({'type': 'fatal', 'text': 'Jupyter could not load in %s: %s. Install jupyter_client and ipykernel in this Python environment.' % (sys.executable, exc)}), flush=True)
    sys.exit(1)

out_lock = threading.Lock()
map_lock = threading.Lock()
requests = {}
cells = {}
origins = {}
previous_snapshot = {}
active = True
independent_cells = os.environ.get('PYLAB_VARIABLE_MODE', 'shared') == 'independent'
bridge_failures = queue.Queue()

ACTION_REQUESTS = frozenset(('export', 'export_as', 'plot', 'statistics', 'rename', 'delete', 'chdir'))

def scoped_fields(command):
    return {'scope_id': command.get('scope_id', 'internal:console')} if independent_cells else {}

def request_error(command, exc):
    message = str(exc) or type(exc).__name__
    kind = command.get('type') if isinstance(command, dict) else None
    if kind in ACTION_REQUESTS and isinstance(command.get('request_id'), str):
        emit(type='action_error', request_id=command['request_id'], action=kind, text=message)
    elif kind == 'complete' and isinstance(command.get('request_id'), str):
        emit(type='complete_result', request_id=command['request_id'], matches=[], cursor_start=0, cursor_end=0)
    elif kind == 'execute' and isinstance(command.get('id'), str):
        emit(type='error', id=command['id'], text=message)
        emit(type='finished', id=command['id'])
    else:
        emit(type='workspace_error', text=message, **(scoped_fields(command) if isinstance(command, dict) else {}))

# Names explicitly assigned and common in-place mutations supplement object-identity
# snapshots. Python allows arbitrary side effects; provenance is necessarily best-effort.
MUTATING_METHODS = frozenset(('append', 'extend', 'insert', 'remove', 'pop', 'clear',
    'sort', 'reverse', 'update', 'add', 'discard', 'difference_update',
    'intersection_update', 'symmetric_difference_update', 'fill', 'resize',
    'put', 'itemset', 'setdefault', 'set_index', 'drop', 'dropna', 'fillna',
    'replace', 'rename', 'sort_values', 'sort_index', 'reset_index', 'insert'))
# pandas returns a new object for these operations unless inplace=True.
PANDAS_OPTIONAL_INPLACE = frozenset(('set_index', 'drop', 'dropna', 'fillna',
    'replace', 'rename', 'sort_values', 'sort_index', 'reset_index'))

def assigned_names(code):
    try:
        tree = ast.parse(code)
    except (SyntaxError, ValueError, TypeError):
        return set()
    class Visitor(ast.NodeVisitor):
        def __init__(self): self.names = set()
        def root_name(self, node):
            while isinstance(node, (ast.Subscript, ast.Attribute)):
                node = node.value
            return node.id if isinstance(node, ast.Name) else None
        def visit_Name(self, node):
            if isinstance(node.ctx, (ast.Store, ast.Del)):
                self.names.add(node.id)
        def visit_Subscript(self, node):
            if isinstance(node.ctx, (ast.Store, ast.Del)):
                name = self.root_name(node)
                if name: self.names.add(name)
            self.generic_visit(node)
        def visit_Attribute(self, node):
            if isinstance(node.ctx, (ast.Store, ast.Del)):
                name = self.root_name(node)
                if name: self.names.add(name)
            self.generic_visit(node)
        def visit_Call(self, node):
            if isinstance(node.func, ast.Attribute) and node.func.attr in MUTATING_METHODS:
                method = node.func.attr
                explicit_inplace = any(keyword.arg == 'inplace' and
                    isinstance(keyword.value, ast.Constant) and keyword.value.value is True
                    for keyword in node.keywords)
                if method not in PANDAS_OPTIONAL_INPLACE or explicit_inplace:
                    name = self.root_name(node.func.value)
                    if name: self.names.add(name)
            self.generic_visit(node)
        def visit_FunctionDef(self, node): self.names.add(node.name)
        visit_AsyncFunctionDef = visit_FunctionDef
        def visit_ClassDef(self, node): self.names.add(node.name)
        def visit_Lambda(self, node): pass
    visitor = Visitor()
    visitor.visit(tree)
    return visitor.names


def emit(**message):
    with out_lock:
        print(json.dumps(message, ensure_ascii=False), flush=True)

HELPERS = '''
import json as _json
import ast as _ast
import types as _types
import numpy as _np
import pandas as _pd
def _pylab_snapshot():
    return _json.dumps({n:id(v) for n,v in list(get_ipython().user_ns.items())
        if not n.startswith('_') and n not in ('In','Out','get_ipython','exit','quit','open')
        and not isinstance(v,(_types.ModuleType,_types.FunctionType,type))})
def _pylab_chdir(path):
    import os as _os
    _os.chdir(path)
    return _json.dumps(_os.getcwd())
def _pylab_summary():
    # Keep workspace previews small even when scientific objects are very large.
    import reprlib as _reprlib
    formatter = _reprlib.Repr()
    formatter.maxstring = 120
    formatter.maxother = 140
    formatter.maxlist = formatter.maxtuple = formatter.maxset = 5
    formatter.maxdict = 4
    rows=[]
    for n,v in list(get_ipython().user_ns.items()):
        if n.startswith('_') or n in ('In','Out','get_ipython','exit','quit','open') or isinstance(v,(_types.ModuleType,_types.FunctionType,type)):
            continue
        try:
            array = isinstance(v, _np.ndarray)
            frame = isinstance(v, _pd.DataFrame)
            series = isinstance(v, _pd.Series)
            editable = (array and v.ndim in (1,2) and v.dtype.kind in 'biufcUS') or frame or series
            if array:
                size = ' × '.join(str(d) for d in v.shape) if v.ndim else '1 × 1'
                preview = _np.array2string(v, threshold=6, edgeitems=1, max_line_width=100, separator=', ').replace('\\n',' ')
            elif frame:
                size = ' × '.join(str(d) for d in v.shape)
                preview = '<table>'
            elif series:
                size = str(len(v)) + ' × 1'
                preview = formatter.repr(v.iloc[:5].tolist())
                if len(v) > 5: preview += ' …'
            elif isinstance(v, str):
                size = str(len(v)) + ' chars'
                preview = formatter.repr(v)
            elif isinstance(v, (list,tuple,dict,set,frozenset)):
                size = str(len(v)) + ' items'
                preview = formatter.repr(v)
            else:
                size = '1 × 1' if isinstance(v, (_np.generic,int,float,complex,bool)) else ''
                preview = formatter.repr(v.item() if isinstance(v, _np.generic) else v)
            capabilities = _json.loads(_pylab_actions_info(n))
            export = capabilities.get('export') or {}
            rows.append([n,type(v).__name__,size,preview[:160],bool(editable),
                         export.get('extension'),export.get('label'),bool(capabilities.get('plot'))])
        except Exception:
            rows.append([n,type(v).__name__,'','<unavailable>',False,None,None,False])
    return _json.dumps(rows)
def _pylab_table(name, offset):
    requested_offset=offset
    if isinstance(offset, bool) or not isinstance(offset, int) or offset < 0:
        raise ValueError('The page offset must be a nonnegative whole number.')
    v=get_ipython().user_ns[name]
    if isinstance(v,_np.ndarray):
        if v.ndim not in (1,2) or v.dtype.kind not in 'biufcUS': raise ValueError('Unsupported array')
        a=v.reshape(-1,1) if v.ndim==1 else v
        total,width=a.shape
        offset=min(offset, max(0, ((total-1)//100)*100))
        part=a[offset:offset+100,:30]
        columns=[str(i) for i in range(part.shape[1])]; indices=[str(i) for i in range(offset,offset+len(part))]
        cells=[[repr(x.item()) for x in row] for row in part]
    elif isinstance(v,(_pd.DataFrame,_pd.Series)):
        a=v.to_frame() if isinstance(v,_pd.Series) else v
        total,width=a.shape
        offset=min(offset, max(0, ((total-1)//100)*100))
        part=a.iloc[offset:offset+100,:30]
        columns=[str(x) for x in part.columns]; indices=[str(x) for x in part.index]
        cells=[[repr(x.item() if isinstance(x,_np.generic) else x) for x in row] for row in part.itertuples(index=False,name=None)]
    else: raise ValueError('Variable is not a supported table')
    return _json.dumps(dict(columns=columns,indices=indices,cells=cells,total=total,width=width,offset=offset,name=name,requested_offset=requested_offset))
def _pylab_set_literal(v, row, column, literal):
    if (isinstance(row, bool) or isinstance(column, bool)
            or not isinstance(row, int) or not isinstance(column, int)):
        raise ValueError('Cell coordinates must be whole numbers.')
    if isinstance(v,_np.ndarray):
        if v.ndim not in (1,2) or v.dtype.kind not in 'biufcUS':
            raise ValueError('Variable is not a supported editable array.')
        rows,cols=v.shape[0],1 if v.ndim==1 else v.shape[1]
    elif isinstance(v,_pd.Series): rows,cols=len(v),1
    elif isinstance(v,_pd.DataFrame): rows,cols=v.shape
    else: raise ValueError('Variable is not editable.')
    if row<0 or column<0 or row>=rows or column>=cols:
        raise ValueError('The selected cell is no longer in this variable.')
    new=_ast.literal_eval(literal)
    if not isinstance(new,(str,int,float,complex,bool,type(None))): raise ValueError('Enter a scalar Python literal')
    if isinstance(v,_np.ndarray):
        cast=_np.asarray(new,dtype=v.dtype).item()
        if cast!=new: raise ValueError('Value cannot be represented exactly in this dtype')
        if v.ndim==1: v[row]=new
        else: v[row,column]=new
    elif isinstance(v,_pd.Series): v.iloc[row]=new
    elif isinstance(v,_pd.DataFrame): v.iat[row,column]=new
    else: raise ValueError('Variable is not editable')
def _pylab_edit(name,row,column,literal):
    _pylab_set_literal(get_ipython().user_ns[name],row,column,literal)
    return _json.dumps(True)
def _pylab_paste(name,row,column,values):
    v=get_ipython().user_ns[name]
    if not isinstance(values,list) or not values or len(values)>1000:
        raise ValueError('Paste must contain between 1 and 10,000 cells.')
    if not all(isinstance(r,list) and r for r in values): raise ValueError('Clipboard rows must contain values.')
    if sum(len(r) for r in values)>10000:
        raise ValueError('Paste must contain between 1 and 10,000 cells.')
    if not isinstance(v,(_np.ndarray,_pd.DataFrame,_pd.Series)): raise ValueError('Variable is not editable.')
    if isinstance(v,_np.ndarray) and (v.ndim not in (1,2) or v.dtype.kind not in 'biufcUS'):
        raise ValueError('Variable is not a supported editable array.')
    if (isinstance(row, bool) or isinstance(column, bool)
            or not isinstance(row, int) or not isinstance(column, int)):
        raise ValueError('Cell coordinates must be whole numbers.')
    rows=len(v); cols=1 if isinstance(v,_pd.Series) or (isinstance(v,_np.ndarray) and v.ndim==1) else v.shape[1]
    if row<0 or column<0 or row+len(values)>rows or any(column+len(r)>cols for r in values):
        raise ValueError('The pasted values do not fit in this variable.')
    # Copy only the affected rectangle, not the entire scientific dataset.
    # Validation happens on the copy before any value in the live object changes.
    height=len(values); width=max(len(cells) for cells in values)
    if isinstance(v,_np.ndarray):
        clone=v[row:row+height].copy() if v.ndim==1 else v[row:row+height,column:column+width].copy()
    elif isinstance(v,_pd.Series): clone=v.iloc[row:row+height].copy(deep=True)
    else: clone=v.iloc[row:row+height,column:column+width].copy(deep=True)
    for r, cells in enumerate(values):
        for c, literal in enumerate(cells): _pylab_set_literal(clone,r,c,literal)
    # Write only pasted cells to the original object so aliases and unpasted
    # values remain unchanged, including when clipboard rows have different widths.
    for r, cells in enumerate(values):
        for c, _ in enumerate(cells):
            if isinstance(v,_np.ndarray):
                if v.ndim==1: v[row+r] = clone[r]
                else: v[row+r,column+c] = clone[r,c]
            elif isinstance(v,_pd.Series): v.iloc[row+r] = clone.iloc[r]
            else: v.iat[row+r,column+c] = clone.iat[r,c]
    return _json.dumps(True)
get_ipython().run_line_magic('matplotlib','inline')
'''


# IPython exposes user_module (globals) and user_ns (locals) for embedding.
# Both move together, preserving native execution, magics and display semantics.
# This is namespace isolation, not process/security isolation: modules, files,
# the working directory, execution counter and interpreter remain shared.
SCOPE_HELPERS = r"""
import sys as _pylab_sys
import types as _pylab_types
class _PyLabScopeState:
    def __init__(self, shell):
        self.shell = shell
        self.active = None
        self.scopes = {}
        self.base = self.capture()
        self.helpers = {n:v for n,v in shell.user_ns.items()
                        if n.startswith('_pylab_') and callable(v)}
    def capture(self):
        shell = self.shell
        history = shell.history_manager
        return dict(module=shell.user_module, ns=shell.user_ns,
                    hidden=shell.user_ns_hidden,
                    history=(history.input_hist_parsed, history.input_hist_raw,
                             history.output_hist, history.output_hist_reprs,
                             history._i, history._ii, history._iii, history._i00),
                    display=(shell.displayhook._, shell.displayhook.__, shell.displayhook.___))
    def activate(self, key):
        shell = self.shell
        if self.active is None: self.base = self.capture()
        else: self.scopes[self.active] = self.capture()
        if key is None:
            state = self.base
        else:
            if key not in self.scopes:
                module, ns = shell.prepare_user_module(_pylab_types.ModuleType('__main__'))
                self.scopes[key] = dict(module=module, ns=ns, hidden={},
                    history=([''], [''], {}, {}, '', '', '', ''), display=('', '', ''))
            state = self.scopes[key]
        shell.user_module = state['module']
        shell.user_ns = state['ns']
        shell.user_ns_hidden = state['hidden']
        history = shell.history_manager
        (history.input_hist_parsed, history.input_hist_raw, history.output_hist,
         history.output_hist_reprs, history._i, history._ii, history._iii, history._i00) = state['history']
        shell.displayhook._, shell.displayhook.__, shell.displayhook.___ = state['display']
        # Prompt counts are project-wide, but a scope's In/Out and _, _i caches
        # never inherit values or source from another cell.
        for inputs in (history.input_hist_parsed, history.input_hist_raw):
            if len(inputs) < shell.execution_count:
                inputs.extend([''] * (shell.execution_count - len(inputs)))
        shell.init_user_ns()
        shell.user_ns.update(self.helpers)
        shell.user_ns_hidden.update(self.helpers)
        shell.ns_table['user_global'] = shell.user_global_ns
        shell.ns_table['user_local'] = shell.user_ns
        shell.set_completer_frame()
        _pylab_sys.modules['__main__'] = shell.user_module
        self.active = key
    def evaluate(self, key, expression):
        previous = self.active
        try:
            self.activate(key)
            return eval(expression, self.shell.user_global_ns, self.shell.user_ns)
        finally:
            self.activate(previous)
    def summary(self):
        previous = self.active
        rows = []
        try:
            for key in list(self.scopes):
                if key == 'internal:system': continue
                self.activate(key)
                for row in _json.loads(_pylab_summary()):
                    rows.append(row[:5] + [key] + row[5:] + [key])
        finally:
            self.activate(previous)
        return _json.dumps(rows)
get_ipython()._pylab_scope_state = _PyLabScopeState(get_ipython())
"""

# Imported files keep their script startup context without wrapping/indenting
# the source. IPython hooks therefore retain magics, future imports and await,
# and restore before the normal idle/finished event is emitted.
SCRIPT_CONTEXT_HELPERS = r"""
class _PyLabScriptContext:
    def __init__(self, shell):
        self.shell = shell
        self.sys = __import__('sys')
        self.os = __import__('os')
        self.missing = object()
        self.pending = None
        self.frames = []
        self.directory_type = type('_PyLabScriptDirectory', (str,), {})
    def prepare(self, path):
        self.pending = path
    def before(self, info):
        path = self.pending
        self.pending = None
        frame = dict(info=info, context=None)
        self.frames.append(frame)
        if path is None:
            return
        targets = []
        for namespace in (self.shell.user_ns, self.shell.user_global_ns):
            if not any(item[0] is namespace for item in targets):
                previous = {key:namespace.get(key, self.missing) for key in ('__file__', '__name__', '__package__')}
                targets.append((namespace, previous))
        argv = self.sys.argv
        previous_argv = list(argv) if isinstance(argv, list) else None
        directory = self.os.path.dirname(self.os.path.realpath(path))
        token = None
        if directory not in self.sys.path:
            token = self.directory_type(directory)
            self.sys.path.insert(0, token)
        frame['context'] = (targets, argv, previous_argv, token, self.sys.path)
        for namespace, _ in targets:
            namespace['__file__'] = path
            namespace['__name__'] = '__main__'
            namespace['__package__'] = None
        self.sys.argv = [path]
    def after(self, result):
        info = getattr(result, 'info', None)
        index = None
        if info is not None:
            for candidate in range(len(self.frames)-1, -1, -1):
                if self.frames[candidate]['info'] is info:
                    index = candidate
                    break
        elif self.frames:
            index = len(self.frames)-1
        if index is None:
            return
        frame = self.frames.pop(index)
        context = frame['context']
        if context is None:
            return
        targets, argv, previous_argv, token, injected_into = context
        for namespace, previous in targets:
            for key, value in previous.items():
                if value is self.missing:
                    namespace.pop(key, None)
                else:
                    namespace[key] = value
        if previous_argv is not None:
            argv[:] = previous_argv
        self.sys.argv = argv
        if token is not None:
            # Remove the exact injected entry, retaining intentional path edits
            # made by the script (such as this FDTD project's root insertion).
            # Also clean an old list retained through an alias if a script
            # deliberately assigned a replacement sys.path object.
            seen = set()
            for path in (injected_into, self.sys.path):
                if id(path) in seen:
                    continue
                seen.add(id(path))
                if isinstance(path, list):
                    path[:] = [value for value in path if value is not token]
                elif isinstance(path, tuple) and path is self.sys.path:
                    self.sys.path = tuple(value for value in path if value is not token)
_pylab_script_context = _PyLabScriptContext(get_ipython())
get_ipython()._pylab_script_context = _pylab_script_context
get_ipython().events.register('pre_run_cell', _pylab_script_context.before)
get_ipython().events.register('post_run_cell', _pylab_script_context.after)
"""

def command_scope(command, source=None, ident=None):
    scope = command.get('scope_id')
    if scope is not None and (not isinstance(scope, str) or not scope or len(scope) > 4096):
        raise ValueError('A variable scope must be a nonempty cell identifier.')
    if scope is not None: return scope
    if source == 'cell':
        origin = command.get('origin_id')
        return origin if isinstance(origin, str) and origin else ident
    return 'internal:system' if source == 'internal' else 'internal:console'

def scope_state_expression():
    return "__import__('IPython').get_ipython()._pylab_scope_state"

def activate_scope(scope):
    # This silent request is queued on the same shell channel immediately before
    # its user execution/completion, so Run All cannot race namespace selection.
    return kc.execute(scope_state_expression() + '.activate(%r)' % scope,
                      silent=True, store_history=False, allow_stdin=False)

def scoped_expression(scope, expression):
    return scope_state_expression() + '.evaluate(%r, %r)' % (scope, expression)

km = KernelManager(kernel_name='python3', autorestart=False)
km._kernel_spec = KernelSpec(argv=[sys.executable, '-m', 'ipykernel_launcher', '-f', '{connection_file}'], display_name='Python', language='python')
try:
    km.start_kernel(cwd=os.getcwd())
    kc = km.client()
    kc.start_channels()
    kc.wait_for_ready(timeout=30)
    action_source = Path(__file__).with_name('workspace_actions.py').read_text(encoding='utf-8')
    bootstrap = kc.execute(action_source + '\n' + HELPERS + (SCOPE_HELPERS if independent_cells else '') + SCRIPT_CONTEXT_HELPERS, silent=True, store_history=False, allow_stdin=False)
    while True:
        reply = kc.get_shell_msg(timeout=30)
        if reply.get('parent_header', {}).get('msg_id') == bootstrap:
            if reply['content']['status'] != 'ok':
                raise RuntimeError(reply['content'].get('evalue', 'Kernel initialization failed'))
            break
    kernel_pid = getattr(getattr(km, 'provisioner', None), 'pid', None)
    emit(type='ready', text=sys.executable, kernel_pid=kernel_pid if isinstance(kernel_pid, int) and kernel_pid > 0 else None)
except Exception as exc:
    emit(type='fatal', text=str(exc))
    if km.has_kernel:
        km.shutdown_kernel(now=True)
    sys.exit(1)

def display_fields(content, update=False):
    """Jupyter display handles are transient, session-scoped identities.

    Retain update intent even for an invalid handle so a client never appends a
    malformed update as a new output. The UI ignores updates it cannot match.
    """
    transient = content.get('transient', {})
    display_id = transient.get('display_id') if isinstance(transient, dict) else None
    fields = {'update': True} if update else {}
    if isinstance(display_id, str) and display_id:
        try:
            if len(display_id.encode('utf-8')) <= 4096:
                fields['display_id'] = display_id
        except UnicodeError:
            pass
    return fields


def emit_display(ident, content, update=False, count=None):
    data = content.get('data', {})
    if not isinstance(data, dict):
        return
    fields = display_fields(content, update)
    if isinstance(count, int) and not isinstance(count, bool) and count >= 0:
        fields['count'] = count
    metadata = content.get('metadata', {})
    if isinstance(metadata, dict) and metadata:
        fields['metadata'] = metadata
    # Preserve the MIME bundle for notebook round trips without transmitting
    # the large PNG twice. KernelEvent reconstructs it from the legacy field.
    other_data = {key: value for key, value in data.items() if key != 'image/png'}
    if other_data:
        fields['data'] = other_data
    if 'image/png' in data:
        emit(type='image', id=ident, image=data['image/png'], **fields)
    elif 'text/plain' in data:
        emit(type='result', id=ident, text=data['text/plain'], **fields)
    else:
        # An update can remove a PNG in favor of SVG/HTML or an empty bundle.
        # Emit it so a client replaces its old frame rather than displaying it.
        emit(type='display', id=ident, **fields)


def iopub():
    while active:
        try:
            msg = kc.get_iopub_msg(timeout=0.25)
        except queue.Empty:
            continue
        except Exception as exc:
            if active: bridge_failures.put(str(exc))
            return
        parent = msg.get('parent_header', {}).get('msg_id', '')
        with map_lock:
            ident = cells.get(parent)
        kind, content = msg['msg_type'], msg['content']
        if kind == 'status':
            if ident and content.get('execution_state') == 'idle':
                emit(type='finished', id=ident)
                with map_lock: cells.pop(parent, None)
            elif ident:
                emit(type='status', id=ident, text=content.get('execution_state'))
            continue
        # A display handle may be updated by a background task after its
        # originating execution has completed. A matching UI handle is enough
        # to route that update; initial outputs still require an active request.
        if not ident:
            if kind == 'update_display_data' and 'display_id' in display_fields(content, True):
                emit_display(None, content, update=True)
            continue
        if kind == 'execute_input':
            emit(type='execute_input', id=ident, count=content.get('execution_count'))
        elif kind == 'stream':
            emit(type='stream', id=ident, text=content.get('text',''))
        elif kind == 'error':
            emit(type='error', id=ident, text='\n'.join(content.get('traceback',[])))
        elif kind in ('display_data','execute_result','update_display_data'):
            emit_display(ident, content, update=(kind == 'update_display_data'),
                         count=content.get('execution_count') if kind == 'execute_result' else None)
        elif kind == 'clear_output':
            emit(type='clear_output', id=ident, wait=bool(content.get('wait', False)))

def stdin_requests():
    while active:
        try: msg = kc.get_stdin_msg(timeout=0.25)
        except queue.Empty: continue
        except Exception as exc:
            if active: bridge_failures.put(str(exc))
            return
        if msg.get('msg_type') != 'input_request': continue
        parent = msg.get('parent_header', {}).get('msg_id', '')
        with map_lock: ident = cells.get(parent)
        content = msg.get('content', {})
        emit(type='input_request', id=ident, prompt=content.get('prompt', ''), password=bool(content.get('password')))

def shell():
    while active:
        try: msg=kc.get_shell_msg(timeout=0.25)
        except queue.Empty: continue
        except Exception as exc:
            if active: bridge_failures.put(str(exc))
            return
        parent=msg.get('parent_header',{}).get('msg_id','')
        with map_lock: item=requests.pop(parent,None)
        if not item: continue
        if item['type'] == 'complete':
            content = msg['content']
            emit(type='complete_result', request_id=item['request_id'], matches=content.get('matches', []),
                 cursor_start=content.get('cursor_start', 0), cursor_end=content.get('cursor_end', 0))
            continue
        response=msg['content'].get('user_expressions',{}).get('value',{})
        if response.get('status') != 'ok':
            error = response.get('evalue','Kernel request failed')
            if item['type'] in ACTION_REQUESTS:
                emit(type='action_error', request_id=item['request_id'], action=item['type'], text=error)
            elif item['type'] != 'snapshot':
                emit(type='workspace_error', text=error, **scoped_fields(item))
            continue
        try:
            result=json.loads(ast.literal_eval(response['data']['text/plain']))
            if item['type']=='snapshot':
                with map_lock:
                    for name in list(origins):
                        if name not in result: origins.pop(name, None)
                    owner = item['owner']
                    if owner is not None:
                        for name, identity in result.items():
                            if previous_snapshot.get(name) != identity or name in item['assigned']:
                                origins[name] = owner
                    previous_snapshot.clear()
                    previous_snapshot.update(result)
            elif item['type']=='workspace':
                with map_lock:
                    rows = result if independent_cells else [row[:5] + [origins.get(row[0])] + row[5:] for row in result]
                emit(type='workspace',rows=rows)
            elif item['type']=='table': emit(type='table', **result, **scoped_fields(item))
            elif item['type']=='chdir': emit(type='directory_result', request_id=item['request_id'], path=result)
            elif item['type'] in ('edit','paste'):
                emit(type='edit', name=item['name'], **scoped_fields(item))
            elif item['type'] in ('rename','delete'):
                with map_lock:
                    old = item['name']
                    owner = origins.pop(old, None)
                    previous_snapshot.pop(old, None)
                    if item['type'] == 'rename':
                        new = result['new_name']
                        if owner is not None: origins[new] = owner
                        previous_snapshot[new] = result['identity']
                emit(type='manage_result', request_id=item['request_id'], action=item['type'], result=result, **scoped_fields(item))
            elif item['type']=='statistics':
                emit(type='statistics_result', request_id=item['request_id'], result=result)
            elif item['type'] in ('export','export_as','plot'):
                emit(type=('export_result' if item['type']=='export_as' else item['type'] + '_result'), request_id=item['request_id'], result=result)
        except Exception as exc:
            if item['type'] in ACTION_REQUESTS:
                emit(type='action_error', request_id=item['request_id'], action=item['type'], text=str(exc))
            else: emit(type='workspace_error', text=str(exc), **scoped_fields(item))

def terminate(signum, frame):
    raise SystemExit(0)

signal.signal(signal.SIGTERM, terminate)
threading.Thread(target=iopub, daemon=True).start()
threading.Thread(target=shell, daemon=True).start()
threading.Thread(target=stdin_requests, daemon=True).start()

# Reading stdin in a daemon lets the supervisor detect a dead kernel while the
# desktop has no further commands to send. A blocked readline previously left
# failed executions and every pending workspace action waiting indefinitely.
commands = queue.Queue()
def read_commands():
    try:
        for line in sys.stdin:
            commands.put(line)
    finally:
        commands.put(None)
threading.Thread(target=read_commands, daemon=True).start()
try:
    while True:
        if not bridge_failures.empty():
            emit(type='fatal', text='Kernel communication failed: ' + bridge_failures.get())
            break
        if not km.is_alive():
            emit(type='fatal', text='The Python kernel stopped unexpectedly. Restart it to continue.')
            break
        try:
            line = commands.get(timeout=0.25)
        except queue.Empty:
            continue
        if line is None: break
        cmd = None
        try:
            cmd=json.loads(line)
            if not isinstance(cmd, dict): raise ValueError('A kernel command must be a JSON object.')
            kind=cmd.get('type')
            if kind=='stop': break
            if kind=='interrupt':
                km.interrupt_kernel(); continue
            if kind=='input_reply':
                kc.input(str(cmd.get('value', ''))); continue
            if kind=='execute':
                if not isinstance(cmd.get('id'), str) or not cmd['id'] or not isinstance(cmd.get('code'), str):
                    raise ValueError('Execution requires a cell identifier and Python source text.')
                script_path = cmd.get('script_path')
                if script_path is not None:
                    if (not isinstance(script_path, str) or not os.path.isabs(script_path)
                            or '\0' in script_path or len(script_path.encode('utf-8')) > 65536):
                        raise ValueError('Imported script context requires an absolute local script path.')
                    script_path = os.path.normpath(script_path)
                ident = str(cmd['id'])
                source = cmd.get('source') or ('internal' if ident.startswith('internal-') else 'console' if ident.startswith('console-') else 'cell')
                origin = cmd.get('origin_id')
                owner = None if source == 'internal' else ('internal:console' if source == 'console' else (origin if isinstance(origin, str) and origin else ident))
                scope = command_scope(cmd, source=source, ident=ident) if independent_cells else None
                with map_lock:
                    if independent_cells: activate_scope(scope)
                    if script_path is not None and cmd['code'].strip():
                        context = "__import__('IPython').get_ipython()._pylab_script_context"
                        kc.execute(context + '.prepare(%r)' % script_path,
                                   silent=True, store_history=False, allow_stdin=False)
                    msg=kc.execute(cmd.get('code',''),allow_stdin=True,stop_on_error=False)
                    cells[msg]=ident
                    if not independent_cells:
                        # Shared attribution is snapshotted in queue order.
                        snapshot = kc.execute('',silent=True,store_history=False,allow_stdin=False,
                                              user_expressions={'value':'_pylab_snapshot()'})
                        requests[snapshot] = {'type':'snapshot', 'owner':owner,
                                              'assigned':assigned_names(cmd.get('code',''))}
                continue
            if kind == 'complete':
                scope = command_scope(cmd) if independent_cells else None
                with map_lock:
                    if independent_cells: activate_scope(scope)
                    msg = kc.complete(cmd.get('code', ''), cursor_pos=int(cmd.get('cursor_pos', 0)))
                    requests[msg] = cmd
                continue
            if kind=='chdir': expression='_pylab_chdir(%r)' % cmd['path']
            elif kind=='workspace': expression=(scope_state_expression() + '.summary()') if independent_cells else '_pylab_summary()'
            elif kind=='table': expression='_pylab_table(%r, %d)' % (cmd['name'], int(cmd.get('offset',0)))
            elif kind=='edit': expression='_pylab_edit(%r, %d, %d, %r)' % (cmd['name'], int(cmd['row']), int(cmd['column']), cmd['literal'])
            elif kind=='paste': expression='_pylab_paste(%r, %d, %d, %r)' % (cmd['name'], int(cmd['row']), int(cmd['column']), cmd['values'])
            elif kind=='export': expression='_pylab_export(%r, %r, %r)' % (cmd['name'],cmd['path'],bool(cmd.get('replace_existing',False)))
            elif kind=='export_as': expression='_pylab_export_as(%r, %r, %r)' % (cmd['name'],cmd['path'],bool(cmd.get('replace_existing',False)))
            elif kind=='plot': expression='_pylab_plot(%r, %r, %r)' % (cmd['name'], cmd.get('column'), cmd.get('options'))
            elif kind=='statistics': expression='_pylab_statistics(%r)' % cmd['name']
            elif kind in ('rename','delete'): expression='_pylab_manage_variable(%r, %r, %r)' % (cmd['name'], kind, cmd.get('new_name'))
            else: continue
            if independent_cells and kind not in ('workspace', 'chdir'):
                cmd['scope_id'] = command_scope(cmd)
                expression = scoped_expression(cmd['scope_id'], expression)
            with map_lock:
                msg=kc.execute('',silent=True,store_history=False,allow_stdin=False,user_expressions={'value':expression})
                requests[msg]=cmd
        except Exception as exc: request_error(cmd, exc)
finally:
    active=False
    kc.stop_channels()
    if km.has_kernel:
        km.shutdown_kernel(now=True)
