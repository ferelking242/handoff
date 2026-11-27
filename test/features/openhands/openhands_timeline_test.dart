import 'package:Kelivo/features/openhands/models/openhands_models.dart';
import 'package:Kelivo/features/openhands/providers/openhands_provider.dart';
import 'package:flutter_test/flutter_test.dart';

OpenHandsEvent _event(Map<String, dynamic> json) =>
    OpenHandsEvent.fromJson(json);

void main() {
  group('timeline mapping', () {
    late OpenHandsProvider provider;

    setUp(() {
      provider = OpenHandsProvider();
    });

    tearDown(() {
      provider.dispose();
    });

    test('think actions become thinking rows and skip their observation', () {
      final items = provider.debugMapEvents([
        _event({
          'id': 'think-1',
          'kind': 'ActionEvent',
          'source': 'agent',
          'tool_call_id': 'call-think',
          'action': {
            'kind': 'ThinkAction',
            'thought': 'I should inspect the repository first.',
          },
        }),
        _event({
          'id': 'obs-think',
          'kind': 'ObservationEvent',
          'source': 'environment',
          'action_id': 'think-1',
          'tool_call_id': 'call-think',
          'observation': {'content': [{'type': 'text', 'text': 'ok'}]},
        }),
      ]);

      expect(items, hasLength(1));
      expect(items.single.kind, HandoffItemKind.thinking);
      expect(items.single.text, contains('inspect the repository'));
    });

    test('action reasoning and observations stay attached to the tool row', () {
      final items = provider.debugMapEvents([
        _event({
          'id': 'action-1',
          'kind': 'ActionEvent',
          'source': 'agent',
          'tool_call_id': 'call-1',
          'reasoning_content': 'I will list the workspace.',
          'tool_name': 'terminal',
          'action': {'kind': 'ExecuteBashAction', 'command': 'ls -la'},
        }),
        _event({
          'id': 'obs-1',
          'kind': 'ObservationEvent',
          'source': 'environment',
          'action_id': 'action-1',
          'tool_call_id': 'call-1',
          'observation': {
            'content': [
              {'type': 'text', 'text': 'README.md\nlib'},
            ],
          },
        }),
      ]);

      expect(items.map((item) => item.kind), [
        HandoffItemKind.thinking,
        HandoffItemKind.action,
      ]);
      expect(items.first.text, 'I will list the workspace.');
      expect(items.last.running, isFalse);
      expect(items.last.result, contains('README.md'));
    });

    test('finish actions render the final answer outside the tool list', () {
      final items = provider.debugMapEvents([
        _event({
          'id': 'finish-1',
          'kind': 'ActionEvent',
          'source': 'agent',
          'tool_call_id': 'call-finish',
          'reasoning_content': 'The task is complete.',
          'action': {
            'kind': 'FinishAction',
            'message': 'Everything is done.',
          },
        }),
        _event({
          'id': 'obs-finish',
          'kind': 'ObservationEvent',
          'source': 'environment',
          'action_id': 'finish-1',
          'tool_call_id': 'call-finish',
          'observation': {'content': [{'type': 'text', 'text': 'finished'}]},
        }),
      ]);

      expect(items.map((item) => item.kind), [
        HandoffItemKind.thinking,
        HandoffItemKind.assistant,
      ]);
      expect(items.last.text, 'Everything is done.');
    });

    test('inline think blocks are peeled out of assistant messages', () {
      const open = '\u003cthink\u003e';
      const close = '\u003c/think\u003e';
      final items = provider.debugMapEvents([
        _event({
          'id': 'message-1',
          'kind': 'MessageEvent',
          'source': 'agent',
          'llm_message': {
            'role': 'assistant',
            'content': [
              {
                'type': 'text',
                'text': '${open}hidden reasoning${close}Visible answer',
              },
            ],
          },
        }),
      ]);

      expect(items.map((item) => item.kind), [
        HandoffItemKind.thinking,
        HandoffItemKind.assistant,
      ]);
      expect(items.first.text, 'hidden reasoning');
      expect(items.last.text, 'Visible answer');
    });
  });

  group('queued prompts', () {
    test('queue can be edited, reordered and cleared', () async {
      final provider = OpenHandsProvider();
      addTearDown(provider.dispose);
      provider.debugSetActive(
        const OpenHandsConversation(
          id: 'conversation-1',
          title: 'Test',
          executionStatus: 'RUNNING',
        ),
      );

      expect(
        await provider.submitMessage('first'),
        OpenHandsSendOutcome.queued,
      );
      expect(
        await provider.submitMessage('second'),
        OpenHandsSendOutcome.queued,
      );
      expect(
        await provider.submitMessage('third'),
        OpenHandsSendOutcome.queued,
      );

      expect(provider.queuedPrompts.map((prompt) => prompt.text), [
        'first',
        'second',
        'third',
      ]);

      final second = provider.queuedPrompts[1];
      provider.updateQueuedPrompt(second.id, 'second edited');
      expect(provider.queuedPrompts[1].text, 'second edited');

      provider.moveQueuedPrompt(second.id, -1);
      expect(provider.queuedPrompts.first.text, 'second edited');

      provider.removeQueuedPrompt(second.id);
      expect(provider.queuedPrompts.map((prompt) => prompt.text), [
        'first',
        'third',
      ]);

      provider.clearQueuedPrompts();
      expect(provider.queuedPrompts, isEmpty);
    });
  });

  test('splitInlineThink ignores an unclosed block', () {
    const open = '\u003cthink\u003e';
    final split = splitInlineThink('${open}still streaming');
    expect(split.reasoning, isEmpty);
    expect(split.content, contains('still streaming'));
  });
}
