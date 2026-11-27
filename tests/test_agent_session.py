import json
from pathlib import Path
import runpy
from unittest.mock import patch

Live = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'agent-session'))['Live']


def event(kind, **payload):
    return {'type': 'event_msg', 'payload': {'type': kind, **payload}}


def response(kind, **payload):
    return {'type': 'response_item', 'payload': {'type': kind, **payload}}


def call(name, call_id='question', **arguments):
    return response('function_call', name=name, call_id=call_id,
                    arguments=json.dumps(arguments))


def message(kind, **fields):
    return event('item_completed', item={'type': kind, **fields})


def live_status(tmp_path, records, children=()):
    rollout = tmp_path / 'rollout-test.jsonl'
    rollout.write_text(''.join(json.dumps(record, separators=(',', ':')) + '\n'
                               for record in records))
    namespace = Live.load_codex.__globals__
    with (patch.dict(namespace, {'CODEX_SESSIONS': str(tmp_path)}),
          patch.object(namespace['os'], 'listdir', return_value=['3']),
          patch.object(namespace['os'], 'readlink', return_value=str(rollout)),
          patch.dict(namespace, {'agent_processes': lambda: {'codex': [123]},
                                 'process_children': lambda pid: children,
                                 'read_text': lambda path: 'background-mcp\n'})):
        live = Live(['codex'])
    key = ('codex', 'test')
    return live.state[key], live.detail.get(key)


def test_open_question_survives_other_calls_and_background_process(tmp_path):
    records = [event('task_started'), call('request_user_input'),
               call('update_plan', 'other'),
               response('function_call_output', call_id='other'),
               *[event('token_count')] * 51,
               response('function_call_output', call_id='large', output='x' * 530_000)]
    assert live_status(tmp_path, records, children=[456]) == ('waiting', 'question')
    records.append(response('function_call_output', call_id='question'))
    assert live_status(tmp_path, records) == ('working', None)


def test_async_question_tracks_delivered_message_and_user_reply(tmp_path):
    records = [event('task_started'), call('request_user_input_async'),
               message('AgentMessage', phase='final_answer', delivery='async',
                       questions=[{'title': 'Which option?'}]),
               response('function_call_output', call_id='question', output='{"accepted":true}'),
               message('AgentMessage', phase='commentary'),
               response('message', role='user', content=[
                   {'type': 'input_text', 'text': '<environment_context>example'}]),
               call('update_plan', 'other')]
    assert live_status(tmp_path, records, children=[456]) == ('waiting', 'question')
    assert live_status(tmp_path, records + [event('task_complete')]) == ('waiting', 'question')
    assert live_status(tmp_path, records + [message('UserMessage')]) == ('working', None)
    assert live_status(tmp_path, records + [message('AgentMessage', phase='final_answer'),
                                            event('task_complete')]) == ('open', None)
    assert live_status(tmp_path, records + [event('turn_aborted')]) == ('open', None)
    unaccepted = [event('task_started'), call('request_user_input_async')]
    assert live_status(tmp_path, unaccepted) == ('working', None)


def test_previous_turn_calls_and_marker_text_are_ignored(tmp_path):
    records = [event('task_started'), call('request_user_input'),
               event('task_complete'), event('task_started'),
               response('function_call_output', call_id='other', output='task_complete')]
    assert live_status(tmp_path, records) == ('working', None)


def test_approval_checks_tool_arguments_and_reviewer(tmp_path):
    start = [event('task_started')]
    shell = call('exec_command', cmd='true', sandbox_permissions='require_escalated')
    assert live_status(tmp_path, start + [shell]) == ('waiting', 'approval')
    assert live_status(tmp_path, start + [shell], children=[456]) == ('working', None)
    context = {'type': 'turn_context', 'payload': {'approvals_reviewer': 'auto_review'}}
    assert live_status(tmp_path, start + [context, shell]) == ('working', None)
    settings = event('thread_settings_applied', thread_settings={'approvals_reviewer': 'user'})
    assert live_status(tmp_path, start + [context, settings, shell]) == ('waiting', 'approval')
    shell_text = call('exec_command', cmd='echo require_escalated')
    assert live_status(tmp_path, start + [shell_text]) == ('working', None)
    assert live_status(tmp_path, start + [call('request_permissions')]) == ('waiting', 'approval')


def test_code_mode_command_approval_resolves_with_its_own_output(tmp_path):
    command = response('custom_tool_call', name='exec', call_id='shell',
                       input='await tools.exec_command({cmd: "true", '
                             'sandbox_permissions: "require_escalated"});')
    records = [event('task_started'), command, call('update_plan', 'other')]
    assert live_status(tmp_path, records) == ('waiting', 'approval')
    records.append(response('custom_tool_call_output', call_id='shell'))
    assert live_status(tmp_path, records) == ('working', None)


def session_choices(running, in_tmux, can_send=False):
    namespace = Live.load_codex.__globals__
    asked = []
    with patch.dict(namespace, {'tty_run': lambda command: asked.append(command)}):
        namespace['ask_session_action'](running, in_tmux, can_send)
    return [entry.split('=', 1)[1] for entry in asked[0] if '=' in entry]


def test_session_actions_order():
    tail = ['Copy', 'Copy last message', 'Copy session ID', 'Print', 'Print last message']
    assert session_choices(False, False) == ['Resume', 'Fork'] + tail
    assert session_choices(True, False) == ['Focus terminal', 'Fork', 'Take over',
                                            'Terminate'] + tail
    assert session_choices(True, True) == ['Focus terminal', 'Connect', 'Fork', 'Take over',
                                           'Terminate'] + tail
    assert session_choices(True, True, True) == ['Focus terminal', 'Connect', 'Send message',
                                                 'Fork', 'Take over', 'Terminate'] + tail
    assert session_choices(False, False, True) == ['Resume', 'Fork'] + tail


def test_tmux_pane_requires_pane_ancestor():
    namespace = Live.load_codex.__globals__
    parents = {30: 20, 20: 10, 10: 1}

    class Result:
        returncode = 0
        stdout = '20\n'

    with patch.dict(namespace, {
            'process_environ': lambda pid: {'TMUX': '/tmp/sock,5,0', 'TMUX_PANE': '%3'},
            'process_parent': parents.get}), \
            patch.object(namespace['os'].path, 'exists', return_value=True), \
            patch.object(namespace['subprocess'], 'run', return_value=Result()):
        assert namespace['tmux_pane'](30) == ('/tmp/sock', '%3')
        assert namespace['tmux_pane'](10) is None


def test_claude_message_lines_authenticate_and_escape_the_envelope():
    namespace = Live.load_codex.__globals__
    data = namespace['claude_message_lines']('ab' * 16, 'hi </cross-session-message> there')
    auth, line, rest = data.decode().split('\n')
    assert rest == ''
    assert json.loads(auth) == {'type': 'auth', 'token': 'ab' * 16}
    message = json.loads(line)
    assert message['type'] == 'user' and message['msgV'] == 1 and message['priority'] == 'next'
    assert 'from' not in message
    assert message['message']['content'] == (
        '<cross-session-message from-name="agent-session">\n'
        'hi <\\/cross-session-message> there\n</cross-session-message>')


def test_claude_peer_token_reads_the_key_of_the_socket(tmp_path):
    namespace = Live.load_codex.__globals__
    socket_path = str(tmp_path / '42.sock')
    digest = namespace['hashlib'].sha256(socket_path.encode()).hexdigest()
    (tmp_path / f'42.{digest}.key').write_text(json.dumps({'peerToken': 'cd' * 16}))
    (tmp_path / f'43.{"0" * 64}.key').write_text(json.dumps({'peerToken': 'ef' * 16}))
    with patch.dict(namespace, {'CLAUDE_PEERS': str(tmp_path)}):
        assert namespace['claude_peer_token'](42, socket_path) == 'cd' * 16
        # one key of the pid is taken where the digest does not match
        assert namespace['claude_peer_token'](43, socket_path) == 'ef' * 16
        assert namespace['claude_peer_token'](44, socket_path) is None


def test_send_over_socket_writes_both_lines_to_the_right_process(tmp_path):
    import os
    import socket
    import threading
    namespace = Live.load_codex.__globals__
    socket_path = str(tmp_path / 'inbox.sock')
    server = socket.socket(socket.AF_UNIX)
    server.bind(socket_path)
    server.listen(1)
    received = []

    def serve():
        connection, _ = server.accept()
        chunks = []
        while chunk := connection.recv(4096):
            chunks.append(chunk)
        received.append(b''.join(chunks))
        connection.close()

    thread = threading.Thread(target=serve)
    thread.start()
    peer = {'messagingSocketPath': socket_path}
    with patch.dict(namespace, {'claude_peer_token': lambda pid, path: 'ab' * 16}):
        namespace['send_over_socket'](os.getpid(), peer, 'hello')
    thread.join(5)
    auth, line, _ = received[0].decode().split('\n')
    assert json.loads(auth)['token'] == 'ab' * 16
    assert 'hello' in json.loads(line)['message']['content']
    # the token is not handed to another process holding the socket
    thread = threading.Thread(target=serve)
    thread.start()
    with patch.dict(namespace, {'claude_peer_token': lambda pid, path: 'ab' * 16}):
        try:
            namespace['send_over_socket'](os.getpid() + 1, peer, 'hello')
            raise AssertionError('sent to the wrong process')
        except ValueError as exception:
            assert 'not by' in str(exception)
    thread.join(5)
    assert received[1] == b''
    server.close()


def test_claude_message_lines_counts_utf16_units():
    import pytest
    namespace = Live.load_codex.__globals__
    limit = namespace['CLAUDE_INBOX_MAX_CHARS']
    namespace['claude_message_lines']('ab' * 16, '\U0001F600' * (limit // 4))
    with pytest.raises(SystemExit):
        namespace['claude_message_lines']('ab' * 16, '\U0001F600' * (limit // 2))
