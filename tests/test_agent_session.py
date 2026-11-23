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


def session_choices(running, in_tmux):
    namespace = Live.load_codex.__globals__
    asked = []
    with patch.dict(namespace, {'tty_run': lambda command: asked.append(command)}):
        namespace['ask_session_action'](running, in_tmux)
    return [entry.split('=', 1)[1] for entry in asked[0] if '=' in entry]


def test_session_actions_order():
    tail = ['Copy', 'Copy last message', 'Copy session ID', 'Print', 'Print last message']
    assert session_choices(False, False) == ['Resume', 'Fork'] + tail
    assert session_choices(True, False) == ['Focus terminal', 'Fork', 'Take over',
                                            'Terminate'] + tail
    assert session_choices(True, True) == ['Focus terminal', 'Connect', 'Fork', 'Take over',
                                           'Terminate'] + tail


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
