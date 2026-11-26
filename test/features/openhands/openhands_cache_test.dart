import 'dart:io';

import 'package:Kelivo/features/openhands/models/openhands_models.dart';
import 'package:Kelivo/features/openhands/services/openhands_cache.dart';
import 'package:flutter_test/flutter_test.dart';

OpenHandsEvent _event(String id) => OpenHandsEvent.fromJson({
      'id': id,
      'kind': 'MessageEvent',
      'source': 'agent',
    });

void main() {
  late Directory root;
  late OpenHandsCache cache;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('handoff-cache-test');
    cache = OpenHandsCache(root: root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('snapshot and durable events round-trip without duplicates', () async {
    await cache.writeSnapshot('conversation', [_event('one'), _event('two')]);
    await cache.append('conversation', 4, _event('three'));
    await cache.append('conversation', 5, _event('three'));

    final history = await cache.read('conversation');
    expect(history.events.map((event) => event.id), ['one', 'two', 'three']);
    expect(history.lastSeq, 4);
    expect(
      File('${root.path}/conversation.jsonl').readAsLinesSync().length,
      3,
    );
  });
}
