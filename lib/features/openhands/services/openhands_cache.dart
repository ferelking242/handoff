import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/openhands_models.dart';

class CachedConversationHistory {
  const CachedConversationHistory({this.events = const [], this.lastSeq});

  final List<OpenHandsEvent> events;
  final int? lastSeq;

  bool get isEmpty => events.isEmpty;
}

/// Append-only local history for OpenHands conversations.
///
/// Each conversation gets a JSONL file. REST snapshots have no sequence number;
/// durable WebSocket frames do, and the highest one becomes the resume cursor
/// for the next connection.
class OpenHandsCache {
  OpenHandsCache({Directory? root}) : _rootOverride = root;

  final Directory? _rootOverride;
  Directory? _root;
  final Set<String> _knownIds = <String>{};

  Future<Directory> _directory() async {
    final root = _rootOverride ?? _root;
    if (root != null) {
      await root.create(recursive: true);
      return root;
    }
    Directory base;
    try {
      base = await getApplicationSupportDirectory();
    } catch (_) {
      base = Directory.systemTemp;
    }
    final directory = Directory(p.join(base.path, 'openhands_history'));
    await directory.create(recursive: true);
    _root = directory;
    return directory;
  }

  String _fileName(String conversationId) {
    final safe = conversationId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return '$safe.jsonl';
  }

  Future<File> _file(String conversationId) async {
    final directory = await _directory();
    return File(p.join(directory.path, _fileName(conversationId)));
  }

  Future<CachedConversationHistory> read(String conversationId) async {
    _knownIds.clear();
    final file = await _file(conversationId);
    if (!await file.exists()) return const CachedConversationHistory();

    final byId = <String, OpenHandsEvent>{};
    int? lastSeq;
    final lines = await file.readAsLines();
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is! Map) continue;
        final eventJson = decoded['event'];
        if (eventJson is! Map) continue;
        final event = OpenHandsEvent.fromJson(
          eventJson.cast<String, dynamic>(),
        );
        if (event.id.isEmpty) continue;
        byId[event.id] = event;
        final seq = decoded['seq'];
        if (seq is num) {
          final value = seq.toInt();
          if (lastSeq == null || value > lastSeq) lastSeq = value;
        }
      } catch (_) {
        // A truncated final line is harmless; the next append repairs it.
      }
    }
    _knownIds
      ..clear()
      ..addAll(byId.keys);
    return CachedConversationHistory(
      events: byId.values.toList(growable: false),
      lastSeq: lastSeq,
    );
  }

  Future<void> writeSnapshot(
    String conversationId,
    List<OpenHandsEvent> events,
  ) async {
    final file = await _file(conversationId);
    final buffer = StringBuffer();
    _knownIds
      ..clear()
      ..addAll(events.map((event) => event.id));
    for (final event in events) {
      buffer.writeln(jsonEncode({'event': event.raw}));
    }
    await file.writeAsString(buffer.toString(), flush: true);
  }

  Future<void> append(
    String conversationId,
    int seq,
    OpenHandsEvent event,
  ) async {
    if (!_knownIds.add(event.id)) return;
    final file = await _file(conversationId);
    await file.writeAsString(
      '${jsonEncode({'seq': seq, 'event': event.raw})}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  Future<void> delete(String conversationId) async {
    _knownIds.clear();
    final file = await _file(conversationId);
    if (await file.exists()) await file.delete();
  }
}
