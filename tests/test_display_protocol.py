"""Focused protocol validation without launching or altering a user's kernel."""
import ast
from pathlib import Path

source = Path(__file__).resolve().parents[1] / 'Resources' / 'kernel_bridge.py'
nodes = ast.parse(source.read_text(encoding='utf-8')).body
helpers = [node for node in nodes if isinstance(node, ast.FunctionDef) and node.name in ('display_fields', 'emit_display')]
received = []
namespace = {'emit': lambda **message: received.append(message)}
exec(compile(ast.Module(body=helpers, type_ignores=[]), str(source), 'exec'), namespace)
fields = namespace['display_fields']
emit = namespace['emit_display']
for value in ('', None, 5, [], {}, 'a' * 4097, '\ud800'):
    assert fields({'transient': {'display_id': value}}, True) == {'update': True}
assert fields({'transient': {'display_id': 'é' * 2048}}, True) == {'display_id': 'é' * 2048, 'update': True}
assert fields({'transient': {'display_id': 'é' * 2049}}, True) == {'update': True}
assert fields({'transient': None}, True) == {'update': True}
emit('cell', {'data': {'image/png': 'PNG', 'text/plain': 'Figure'}, 'metadata': {'image/png': {'width': 12}}, 'transient': {'display_id': 'live'}})
assert received[-1] == {'type': 'image', 'id': 'cell', 'image': 'PNG', 'data': {'text/plain': 'Figure'}, 'metadata': {'image/png': {'width': 12}}, 'display_id': 'live'}
assert 'image/png' not in received[-1]['data'], 'The large PNG must not be transmitted twice'
emit('other', {'data': {'image/svg+xml': '<svg/>'}, 'transient': {'display_id': 'live'}}, True)
assert received[-1] == {'type': 'display', 'id': 'other', 'display_id': 'live', 'update': True, 'data': {'image/svg+xml': '<svg/>'}}
emit(None, {'data': {}, 'transient': {'display_id': 'live'}}, True)
assert received[-1] == {'type': 'display', 'id': None, 'display_id': 'live', 'update': True}
emit('cell', {'data': {'text/plain': 'hello'}})
assert received[-1]['type'] == 'result' and received[-1]['text'] == 'hello'
count = len(received)
emit('cell', {'data': []})
assert len(received) == count
emit('cell', {'data': {'text/plain': '4'}}, count=7)
assert received[-1]['count'] == 7
print('PASS: display handle validation, MIME metadata, no duplicate PNG payload, empty/unsupported updates')
