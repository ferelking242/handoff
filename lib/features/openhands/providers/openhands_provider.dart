import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/openhands_models.dart';
import '../services/openhands_api.dart';
import '../services/openhands_cache.dart';
import '../services/openhands_store.dart';

enum OpenHandsAuthStatus { loading, signedOut, signingIn, signedIn, error }

/// Owns the OpenHands session, the conversation list and the open timeline.
class OpenHandsProvider extends ChangeNotifier {
  OpenHandsProvider({
    OpenHandsStore? store,
    OpenHandsApi? api,
    OpenHandsCache? cache,
  })  : _store = store ?? OpenHandsStore(),
        _api = api ?? OpenHandsApi(),
        _cache = cache ?? OpenHandsCache();

  final OpenHandsStore _store;
  final OpenHandsApi _api;
  final OpenHandsCache _cache;

  OpenHandsAuthStatus _authStatus = OpenHandsAuthStatus.loading;
  OpenHandsAuthStatus get authStatus => _authStatus;

  OpenHandsUser? _user;
  OpenHandsUser? get user => _user;

  String? _error;
  String? get error => _error;

  String? _deviceNotice;
  String? get deviceNotice => _deviceNotice;

  String get baseUrl => _api.baseUrl;

  String get apiKeysUrl => '$baseUrl/settings/api-keys';

  List<OpenHandsConversation> _conversations = const [];
  List<OpenHandsConversation> get conversations => _conversations;

  bool _conversationsLoading = false;
  bool get conversationsLoading => _conversationsLoading;

  String? _conversationsError;
  String? get conversationsError => _conversationsError;

  String? _nextPageId;
  bool get hasMoreConversations => _nextPageId != null;

  OpenHandsConversation? _active;
  OpenHandsConversation? get active => _active;

  List<HandoffTimelineItem> _timeline = const [];
  List<HandoffTimelineItem> get timeline => _timeline;

  bool _timelineLoading = false;
  bool get timelineLoading => _timelineLoading;

  String? _timelineError;
  String? get timelineError => _timelineError;

  bool _sending = false;
  bool get sending => _sending;

  bool _creating = false;
  bool get creating => _creating;

  DeviceCode? _deviceCode;
  DeviceCode? get deviceCode => _deviceCode;

  bool _devicePolling = false;
  bool get devicePolling => _devicePolling;

  GuardConfig _guard = const GuardConfig();
  GuardConfig get guard => _guard;

  GuardStatus? _guardStatus;
  GuardStatus? get guardStatus => _guardStatus;

  bool _guardTesting = false;
  bool get guardTesting => _guardTesting;

  Timer? _deviceTimer;
  int _deviceGeneration = 0;
  Timer? _socketRetryTimer;
  WebSocketChannel? _socket;
  int _socketGeneration = 0;
  int _lastSeq = -1;
  bool _historyLoaded = false;
  final List<OpenHandsEvent> _events = [];
  final Map<String, _StreamingSlot> _streaming = {};
  final List<HandoffTimelineItem> _optimistic = [];

  List<OpenHandsFolder> _folders = const [];
  List<OpenHandsFolder> get folders => _folders;

  Set<String> _archivedIds = <String>{};
  Set<String> get archivedIds => _archivedIds;

  final Set<String> _collapsedFolders = <String>{};
  bool isFolderExpanded(String folderId) =>
      !_collapsedFolders.contains(folderId);

  bool get isSignedIn => _authStatus == OpenHandsAuthStatus.signedIn;

  bool get agentRunning => _streaming.isNotEmpty || (_active?.isRunning ?? false);

  List<OpenHandsConversation> get visibleConversations => _conversations
      .where((conversation) => !_archivedIds.contains(conversation.id))
      .toList(growable: false);

  List<OpenHandsConversation> get archivedConversations => _conversations
      .where((conversation) => _archivedIds.contains(conversation.id))
      .toList(growable: false);

  OpenHandsFolder? folderForConversation(String conversationId) {
    for (final folder in _folders) {
      if (folder.conversationIds.contains(conversationId)) return folder;
    }
    return null;
  }

  String? get activeModel => _active?.llmModel ?? _user?.llmModel;

  Future<void> initialize() async {
    final savedBaseUrl = await _store.readBaseUrl();
    _api.updateBaseUrl(savedBaseUrl);
    _guard = await _store.readGuardConfig();
    _folders = await _store.readFolders();
    _archivedIds = await _store.readArchivedIds();

    final token = await _store.readToken();
    if (token == null || token.isEmpty) {
      _authStatus = OpenHandsAuthStatus.signedOut;
      notifyListeners();
      return;
    }

    _api.token = token;
    try {
      _user = await _api.me();
      _authStatus = OpenHandsAuthStatus.signedIn;
      notifyListeners();
      unawaited(refreshConversations());
    } on OpenHandsApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        await _store.clearToken();
        _api.token = null;
        _authStatus = OpenHandsAuthStatus.signedOut;
      } else {
        _authStatus = OpenHandsAuthStatus.error;
        _error = error.message;
      }
      notifyListeners();
    } catch (error) {
      _authStatus = OpenHandsAuthStatus.error;
      _error = 'Could not reach OpenHands: $error';
      notifyListeners();
    }
  }

  Future<void> retry() async {
    _error = null;
    _authStatus = OpenHandsAuthStatus.loading;
    notifyListeners();
    await initialize();
  }

  // ---------------------------------------------------------------------
  // Sign-in
  // ---------------------------------------------------------------------

  Future<void> startDeviceSignIn() async {
    final generation = ++_deviceGeneration;
    _deviceTimer?.cancel();
    _error = null;
    _deviceNotice = null;
    _deviceCode = null;
    _devicePolling = true;
    _authStatus = OpenHandsAuthStatus.signingIn;
    notifyListeners();

    try {
      final code = await _api.startDeviceFlow();
      if (generation != _deviceGeneration) return;
      _deviceCode = code;
      notifyListeners();
      await _openExternal(code.verificationUriComplete);
      unawaited(_pollDeviceToken(code, generation));
    } catch (error) {
      if (generation != _deviceGeneration) return;
      _devicePolling = false;
      _authStatus = OpenHandsAuthStatus.signedOut;
      _error = _describeError(error);
      notifyListeners();
    }
  }

  Future<void> _pollDeviceToken(DeviceCode code, int generation) async {
    var interval = code.interval.clamp(1, 30);
    final deadline = DateTime.now().add(Duration(seconds: code.expiresIn));
    while (generation == _deviceGeneration &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(Duration(seconds: interval));
      if (generation != _deviceGeneration) return;
      try {
        final token = await _api.pollDeviceToken(code.deviceCode);
        if (generation != _deviceGeneration) return;
        await _completeSignIn(token);
        return;
      } on DeviceFlowPending {
        continue;
      } on DeviceFlowSlowDown catch (slowDown) {
        interval = (slowDown.interval ?? (interval + 5)).clamp(1, 30);
      } on TimeoutException {
        _deviceNotice = 'The network is slow. Still waiting for approval…';
        notifyListeners();
        continue;
      } on http.ClientException {
        _deviceNotice = 'Connection interrupted. Still waiting for approval…';
        notifyListeners();
        continue;
      } catch (error) {
        if (generation != _deviceGeneration) return;
        _devicePolling = false;
        _deviceCode = null;
        _deviceNotice = null;
        _authStatus = OpenHandsAuthStatus.signedOut;
        _error = _describeError(error);
        notifyListeners();
        return;
      }
    }
    if (generation != _deviceGeneration) return;
    _devicePolling = false;
    _deviceCode = null;
    _deviceNotice = null;
    _authStatus = OpenHandsAuthStatus.signedOut;
    _error = 'The sign-in code expired. Start again.';
    notifyListeners();
  }

  Future<void> cancelDeviceSignIn() async {
    _deviceGeneration++;
    _deviceTimer?.cancel();
    _devicePolling = false;
    _deviceCode = null;
    _deviceNotice = null;
    _authStatus = OpenHandsAuthStatus.signedOut;
    _error = null;
    notifyListeners();
  }

  Future<void> openVerificationPage() async {
    final code = _deviceCode;
    if (code == null) return;
    await _openExternal(code.verificationUriComplete);
  }

  Future<void> signInWithApiKey(String apiKey) async {
    final key = apiKey.trim();
    if (key.isEmpty) return;
    _error = null;
    _deviceNotice = null;
    _authStatus = OpenHandsAuthStatus.signingIn;
    notifyListeners();
    _api.token = key;
    try {
      _user = await _api.me();
      await _store.writeToken(key);
      _authStatus = OpenHandsAuthStatus.signedIn;
      notifyListeners();
      await refreshConversations();
    } catch (error) {
      _api.token = null;
      _authStatus = OpenHandsAuthStatus.signedOut;
      _error = _describeError(error);
      notifyListeners();
    }
  }

  Future<void> _completeSignIn(String token) async {
    _api.token = token;
    try {
      _user = await _api.me();
      await _store.writeToken(token);
      _devicePolling = false;
      _deviceCode = null;
      _deviceNotice = null;
      _authStatus = OpenHandsAuthStatus.signedIn;
      _error = null;
      notifyListeners();
      await refreshConversations();
    } catch (error) {
      _api.token = null;
      _devicePolling = false;
      _deviceCode = null;
      _deviceNotice = null;
      _authStatus = OpenHandsAuthStatus.signedOut;
      _error = 'Signed in, but the profile could not be loaded: $error';
      notifyListeners();
    }
  }

  String _describeError(Object error) {
    if (error is http.ClientException || error is TimeoutException) {
      return 'Could not reach OpenHands. Check your connection and try again.';
    }
    return error.toString();
  }

  bool _isAuthError(Object error) =>
      error is OpenHandsApiException &&
      (error.statusCode == 401 || error.statusCode == 403);

  Future<void> _expireSession() async {
    await signOut();
    _error = 'Your OpenHands session expired. Sign in again.';
    notifyListeners();
  }

  Future<void> signOut() async {
    _socketGeneration++;
    _cancelSocket();
    _deviceGeneration++;
    _deviceTimer?.cancel();
    await _store.clearToken();
    _api.token = null;
    _user = null;
    _conversations = const [];
    _nextPageId = null;
    _active = null;
    _timeline = const [];
    _events.clear();
    _streaming.clear();
    _optimistic.clear();
    _historyLoaded = false;
    _lastSeq = -1;
    _deviceNotice = null;
    _authStatus = OpenHandsAuthStatus.signedOut;
    _error = null;
    notifyListeners();
  }

  Future<void> setBaseUrl(String value) async {
    final normalized = OpenHandsApi.normalizeBaseUrl(value);
    if (normalized == _api.baseUrl) return;
    _api.updateBaseUrl(normalized);
    await _store.writeBaseUrl(normalized);
    if (_authStatus == OpenHandsAuthStatus.signedIn) {
      await signOut();
    } else {
      _error = null;
      notifyListeners();
    }
  }

  Future<void> _openExternal(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      // The user can still copy the code and open the URL manually.
    }
  }

  // ---------------------------------------------------------------------
  // Conversation list
  // ---------------------------------------------------------------------

  Future<void> refreshConversations() async {
    if (!isSignedIn) return;
    _conversationsLoading = true;
    _conversationsError = null;
    notifyListeners();
    try {
      final page = await _api.searchConversations(limit: 50);
      _conversations = page.items;
      _nextPageId = page.nextPageId;
    } catch (error) {
      if (_isAuthError(error)) {
        await _expireSession();
        return;
      }
      _conversationsError = _describeError(error);
    } finally {
      _conversationsLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreConversations() async {
    if (!isSignedIn || _conversationsLoading) return;
    final pageId = _nextPageId;
    if (pageId == null) return;
    _conversationsLoading = true;
    notifyListeners();
    try {
      final page = await _api.searchConversations(limit: 50, pageId: pageId);
      _conversations = [..._conversations, ...page.items];
      _nextPageId = page.nextPageId;
    } catch (error) {
      if (_isAuthError(error)) {
        await _expireSession();
        return;
      }
      _conversationsError = _describeError(error);
    } finally {
      _conversationsLoading = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------
  // Open conversation
  // ---------------------------------------------------------------------

  Future<void> openConversation(OpenHandsConversation conversation) async {
    final generation = ++_socketGeneration;
    _cancelSocket();
    _active = conversation;
    _events.clear();
    _streaming.clear();
    _optimistic.clear();
    _lastSeq = -1;
    _historyLoaded = false;
    _timeline = const [];
    _timelineError = null;
    _timelineLoading = true;
    notifyListeners();

    try {
      CachedConversationHistory cached;
      try {
        cached = await _cache.read(conversation.id);
      } catch (_) {
        cached = const CachedConversationHistory();
      }
      if (generation != _socketGeneration) return;
      if (!cached.isEmpty) {
        for (final event in cached.events) {
          _upsertEvent(event);
        }
        _sortEvents();
        _lastSeq = cached.lastSeq ?? -1;
        _historyLoaded = true;
        _rebuildTimeline();
        _timelineLoading = false;
        notifyListeners();
      }

      var fresh = await _api.getConversation(conversation.id);
      if (generation != _socketGeneration) return;
      if ((fresh.isPaused || !fresh.canStream) && fresh.canResume) {
        fresh = await _wakeSandbox(fresh, generation);
        if (generation != _socketGeneration) return;
      }
      _active = fresh;
      _replaceInList(fresh);
      _rebuildTimeline();

      if (!_historyLoaded) {
        await _loadAllEvents(fresh, generation);
        if (generation != _socketGeneration) return;
      }
      _connectSocket(fresh, generation);
    } catch (error) {
      if (generation != _socketGeneration) return;
      if (_isAuthError(error)) {
        await _expireSession();
        return;
      }
      _timelineError = _describeError(error);
    } finally {
      if (generation == _socketGeneration) {
        _timelineLoading = false;
        notifyListeners();
      }
    }
  }

  Future<OpenHandsConversation> _wakeSandbox(
    OpenHandsConversation conversation,
    int generation,
  ) async {
    final sandboxId = conversation.sandboxId;
    if (sandboxId == null || sandboxId.isEmpty) return conversation;
    try {
      await _api.resumeSandbox(sandboxId);
    } catch (_) {
      return conversation;
    }
    var latest = conversation;
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (generation != _socketGeneration) return latest;
      try {
        latest = await _api.getConversation(conversation.id);
      } catch (_) {
        continue;
      }
      if (latest.canStream && !latest.isPaused) return latest;
    }
    return latest;
  }

  /// Pulls the complete event log once, then stores it locally. Future opens
  /// read the cache and only ask the socket for events after `_lastSeq`.
  Future<void> _loadAllEvents(
    OpenHandsConversation conversation,
    int generation,
  ) async {
    try {
      final all = <OpenHandsEvent>[];
      final seenIds = <String>{};
      final seenPages = <String>{};
      String? pageId;
      while (true) {
        final page = await _api.searchEvents(
          conversation,
          limit: 100,
          pageId: pageId,
          sortOrder: 'TIMESTAMP',
        );
        if (generation != _socketGeneration) return;
        for (final event in page.items) {
          if (seenIds.add(event.id)) all.add(event);
        }
        final next = page.nextPageId;
        if (next == null || next.isEmpty || !seenPages.add(next)) break;
        pageId = next;
        if (all.length >= 20000) break;
      }
      if (generation != _socketGeneration) return;
      _events
        ..clear()
        ..addAll(all);
      _sortEvents();
      _historyLoaded = true;
      try {
        await _cache.writeSnapshot(conversation.id, _events);
      } catch (_) {
        // History is already in memory; the cache is an optimization.
      }
      _rebuildTimeline();
      notifyListeners();
    } catch (error) {
      if (generation != _socketGeneration) return;
      _timelineError = _describeError(error);
      notifyListeners();
    }
  }

  void _connectSocket(OpenHandsConversation conversation, int generation) {
    if (generation != _socketGeneration) return;
    if (!conversation.canStream) {
      _timelineError =
          'This conversation has no live sandbox. Wake it in OpenHands first.';
      notifyListeners();
      return;
    }

    _cancelSocket();
    try {
      final uri = _api.sessionSocketUri(conversation, afterSeq: _lastSeq);
      final socket = WebSocketChannel.connect(uri);
      _socket = socket;

      unawaited(
        socket.ready.then((_) {
          if (generation != _socketGeneration ||
              !identical(_socket, socket)) {
            return;
          }
          final key = conversation.sessionApiKey;
          if (key != null && key.isNotEmpty) {
            socket.sink.add(
              jsonEncode({'type': 'auth', 'session_api_key': key}),
            );
          }
        }).catchError((Object error) {
          _handleSocketClosed(conversation, generation, error, socket);
        }),
      );

      socket.stream.listen(
        (message) => _handleSocketFrame(message, conversation, generation),
        onError: (Object error) =>
            _handleSocketClosed(conversation, generation, error, socket),
        onDone: () =>
            _handleSocketClosed(conversation, generation, null, socket),
        cancelOnError: true,
      );
    } catch (error) {
      _handleSocketClosed(conversation, generation, error);
    }
  }

  void _handleSocketClosed(
    OpenHandsConversation conversation,
    int generation,
    Object? error, [
    WebSocketChannel? closedSocket,
  ]) {
    if (generation != _socketGeneration) return;
    // A replaced socket can close after its replacement is live.
    if (closedSocket != null && !identical(_socket, closedSocket)) return;
    _socket = null;
    if (error != null) {
      debugPrint('OpenHands socket closed: $error');
    }
    _socketRetryTimer?.cancel();
    _socketRetryTimer = Timer(const Duration(seconds: 2), () {
      if (generation == _socketGeneration && _active?.id == conversation.id) {
        _connectSocket(conversation, generation);
      }
    });
  }

  void _handleSocketFrame(
    dynamic message,
    OpenHandsConversation conversation,
    int generation,
  ) {
    if (generation != _socketGeneration) return;
    final Map<String, dynamic> frame;
    try {
      final decoded = jsonDecode(message.toString());
      if (decoded is! Map) return;
      frame = decoded.cast<String, dynamic>();
    } catch (_) {
      return;
    }

    switch (frame['type']) {
      case 'durable':
        final rawEvent = frame['event'];
        if (rawEvent is! Map) return;
        final event = OpenHandsEvent.fromJson(
          rawEvent.cast<String, dynamic>(),
        );
        final seq = frame['seq'];
        if (seq is num) {
          final value = seq.toInt();
          if (value > _lastSeq) _lastSeq = value;
          unawaited(_cache.append(conversation.id, value, event));
        }
        _upsertEvent(event);
        _sortEvents();
        _streaming.remove(event.id);
        _historyLoaded = true;
        _timelineError = null;
        _handleStateEvent(event);
        _removeOptimisticFor(event);
        _rebuildTimeline();
        notifyListeners();
      case 'transient':
        final rawEvent = frame['event'];
        if (rawEvent is Map) {
          _handleStateEvent(
            OpenHandsEvent.fromJson(rawEvent.cast<String, dynamic>()),
          );
          _rebuildTimeline();
          notifyListeners();
        }
      case 'item_started':
        final id = (frame['item_id'] ?? '').toString();
        if (id.isEmpty) return;
        _streaming[id] = _StreamingSlot(startedAt: DateTime.now());
        _rebuildTimeline();
        notifyListeners();
      case 'delta':
        final id = (frame['item_id'] ?? '').toString();
        final content = (frame['content'] ?? '').toString();
        if (id.isEmpty || content.isEmpty) return;
        if ((frame['kind'] ?? 'text').toString() == 'reasoning') return;
        final slot = _streaming.putIfAbsent(
          id,
          () => _StreamingSlot(startedAt: DateTime.now()),
        );
        slot.text += content;
        _rebuildTimeline();
        notifyListeners();
      case 'item_aborted':
        final id = (frame['item_id'] ?? '').toString();
        if (id.isEmpty) return;
        _streaming.remove(id);
        _rebuildTimeline();
        notifyListeners();
      case 'error':
        _timelineError = (frame['detail'] ?? frame['code'] ?? 'The event stream failed.').toString();
        notifyListeners();
      default:
        return;
    }
  }

  void _sortEvents() {
    final indexed = _events.indexed.toList(growable: false);
    indexed.sort((a, b) {
      final left = a.$2.timestamp;
      final right = b.$2.timestamp;
      if (left == null || right == null) return a.$1.compareTo(b.$1);
      final byTime = left.compareTo(right);
      return byTime == 0 ? a.$1.compareTo(b.$1) : byTime;
    });
    _events
      ..clear()
      ..addAll(indexed.map((entry) => entry.$2));
  }

  void _upsertEvent(OpenHandsEvent event) {
    final index = _events.indexWhere((item) => item.id == event.id);
    if (index == -1) {
      _events.add(event);
    } else {
      _events[index] = event;
    }
  }

  void _handleStateEvent(OpenHandsEvent event) {
    if (event.kind != 'ConversationStateUpdateEvent') return;
    final key = event.raw['key']?.toString();
    final value = event.raw['value']?.toString();
    if (key == null || value == null || value.isEmpty) return;
    if (key == 'execution_status') {
      _active = _active?.copyWith(executionStatus: value);
    } else if (key == 'sandbox_status') {
      _active = _active?.copyWith(sandboxStatus: value);
    }
    final current = _active;
    if (current != null) _replaceInList(current);
  }

  void _removeOptimisticFor(OpenHandsEvent event) {
    if (event.kind != 'MessageEvent') return;
    final message = event.raw['llm_message'] ?? event.raw['message'];
    final role = message is Map
        ? (message['role'] ?? event.source).toString()
        : event.source;
    if (role != 'user') return;
    final text = contentToText(message is Map ? message['content'] : message).trim();
    if (text.isEmpty) return;
    _optimistic.removeWhere((item) => item.text.trim() == text);
  }

  void _rebuildTimeline() {
    final mapped = _mapEvents(_events);
    for (final entry in _streaming.entries) {
      if (entry.value.text.trim().isEmpty) continue;
      mapped.add(
        HandoffTimelineItem(
          id: 'stream:${entry.key}',
          kind: HandoffItemKind.assistant,
          text: entry.value.text,
          running: true,
          at: entry.value.startedAt,
        ),
      );
    }
    mapped.addAll(_optimistic);
    _timeline = mapped;
  }

  void _cancelSocket() {
    _socketRetryTimer?.cancel();
    _socketRetryTimer = null;
    final socket = _socket;
    _socket = null;
    try {
      socket?.sink.close();
    } catch (_) {
      // The socket may already be gone.
    }
  }

  void closeConversation() {
    _socketGeneration++;
    _cancelSocket();
    _active = null;
    _events.clear();
    _streaming.clear();
    _optimistic.clear();
    _historyLoaded = false;
    _lastSeq = -1;
    _timeline = const [];
    _timelineError = null;
    _timelineLoading = false;
    notifyListeners();
  }

  Future<void> refreshTimeline() async {
    final current = _active;
    if (current == null) return;
    _timelineError = null;
    notifyListeners();
    final generation = _socketGeneration;
    if (!_historyLoaded && _events.isEmpty) {
      await _loadAllEvents(current, generation);
      if (generation != _socketGeneration) return;
    }
    _connectSocket(current, generation);
  }

  void _replaceInList(OpenHandsConversation conversation) {
    final index = _conversations.indexWhere(
      (item) => item.id == conversation.id,
    );
    if (index == -1) {
      _conversations = [conversation, ..._conversations];
    } else {
      final copy = [..._conversations];
      copy[index] = conversation;
      _conversations = copy;
    }
  }

  // ---------------------------------------------------------------------
  // Sending and conversation actions
  // ---------------------------------------------------------------------

  Future<bool> sendMessage(String text) async {
    final current = _active;
    final trimmed = text.trim();
    if (current == null || trimmed.isEmpty || _sending) return false;

    _sending = true;
    final optimistic = HandoffTimelineItem(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      kind: HandoffItemKind.user,
      text: trimmed,
      at: DateTime.now(),
    );
    _optimistic.add(optimistic);
    _rebuildTimeline();
    notifyListeners();

    try {
      final socket = _socket;
      var sent = false;
      if (socket != null) {
        try {
          await socket.ready.timeout(const Duration(seconds: 12));
          socket.sink.add(
            jsonEncode({
              'role': 'user',
              'content': [
                {'type': 'text', 'text': trimmed},
              ],
              'run': true,
            }),
          );
          sent = true;
        } catch (_) {
          // Fall back to the HTTP event endpoint below.
        }
      }
      if (!sent) {
        await _api.sendMessage(current, trimmed);
      }
      _active = _active?.copyWith(executionStatus: 'RUNNING');
      _sending = false;
      notifyListeners();
      return true;
    } catch (error) {
      _optimistic.removeWhere((item) => item.id == optimistic.id);
      _timelineError = _describeError(error);
      _sending = false;
      _rebuildTimeline();
      notifyListeners();
      return false;
    }
  }

  Future<void> stopAgent() async {
    final current = _active;
    if (current == null) return;
    try {
      await _api.interruptConversation(current);
      _active = _active?.copyWith(executionStatus: 'IDLE');
      _streaming.clear();
      _rebuildTimeline();
      notifyListeners();
    } catch (error) {
      _timelineError = _describeError(error);
      notifyListeners();
    }
  }

  Future<bool> pauseConversation(OpenHandsConversation conversation) async {
    final sandboxId = conversation.sandboxId;
    if (sandboxId == null || sandboxId.isEmpty) return false;
    try {
      await _api.pauseSandbox(sandboxId);
      _patchConversation(
        conversation.id,
        sandboxStatus: 'PAUSED',
        executionStatus: 'PAUSED',
      );
      notifyListeners();
      return true;
    } catch (error) {
      _conversationsError = _describeError(error);
      notifyListeners();
      return false;
    }
  }

  Future<bool> resumeConversation(OpenHandsConversation conversation) async {
    final sandboxId = conversation.sandboxId;
    if (sandboxId == null || sandboxId.isEmpty) return false;
    try {
      await _api.resumeSandbox(sandboxId);
      _patchConversation(conversation.id, sandboxStatus: 'STARTING');
      notifyListeners();
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(seconds: 2));
        try {
          final fresh = await _api.getConversation(conversation.id);
          _replaceInList(fresh);
          if (_active?.id == fresh.id) {
            _active = fresh;
            if (fresh.canStream) {
              _connectSocket(fresh, _socketGeneration);
            }
          }
          if (fresh.canStream && !fresh.isPaused) {
            notifyListeners();
            return true;
          }
        } catch (_) {
          // Keep polling until the sandbox answers.
        }
      }
      notifyListeners();
      return true;
    } catch (error) {
      _conversationsError = _describeError(error);
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteConversation(OpenHandsConversation conversation) async {
    try {
      await _api.deleteConversation(conversation.id);
    } catch (error) {
      if (!_isAuthError(error)) {
        _conversationsError = _describeError(error);
        notifyListeners();
        return false;
      }
      await _expireSession();
      return false;
    }

    _conversations = _conversations
        .where((item) => item.id != conversation.id)
        .toList(growable: false);
    _archivedIds = {..._archivedIds}..remove(conversation.id);
    await _store.writeArchivedIds(_archivedIds);
    await _cache.delete(conversation.id);
    await _removeFromFolders(conversation.id);
    if (_active?.id == conversation.id) {
      closeConversation();
    } else {
      notifyListeners();
    }
    return true;
  }

  Future<void> archiveConversation(OpenHandsConversation conversation) async {
    _archivedIds = {..._archivedIds, conversation.id};
    await _store.writeArchivedIds(_archivedIds);
    notifyListeners();
  }

  Future<void> unarchiveConversation(OpenHandsConversation conversation) async {
    _archivedIds = {..._archivedIds}..remove(conversation.id);
    await _store.writeArchivedIds(_archivedIds);
    notifyListeners();
  }

  Future<void> createFolder(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final folder = OpenHandsFolder(
      id: 'folder-${DateTime.now().microsecondsSinceEpoch}',
      name: trimmed,
    );
    _folders = [..._folders, folder];
    await _store.writeFolders(_folders);
    notifyListeners();
  }

  Future<void> renameFolder(String folderId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _folders = _folders
        .map(
          (folder) => folder.id == folderId
              ? folder.copyWith(name: trimmed)
              : folder,
        )
        .toList(growable: false);
    await _store.writeFolders(_folders);
    notifyListeners();
  }

  Future<void> deleteFolder(String folderId) async {
    _folders = _folders
        .where((folder) => folder.id != folderId)
        .toList(growable: false);
    await _store.writeFolders(_folders);
    notifyListeners();
  }

  Future<void> moveConversationToFolder(
    String conversationId,
    String? folderId,
  ) async {
    _folders = _folders.map((folder) {
      final ids = folder.conversationIds
          .where((id) => id != conversationId)
          .toList(growable: true);
      if (folder.id == folderId) ids.add(conversationId);
      return folder.copyWith(conversationIds: ids);
    }).toList(growable: false);
    await _store.writeFolders(_folders);
    notifyListeners();
  }

  void toggleFolder(String folderId) {
    if (_collapsedFolders.contains(folderId)) {
      _collapsedFolders.remove(folderId);
    } else {
      _collapsedFolders.add(folderId);
    }
    notifyListeners();
  }

  Future<void> _removeFromFolders(String conversationId) async {
    _folders = _folders
        .map(
          (folder) => folder.copyWith(
            conversationIds: folder.conversationIds
                .where((id) => id != conversationId)
                .toList(growable: false),
          ),
        )
        .toList(growable: false);
    await _store.writeFolders(_folders);
  }

  void _patchConversation(
    String conversationId, {
    String? sandboxStatus,
    String? executionStatus,
  }) {
    final index = _conversations.indexWhere(
      (item) => item.id == conversationId,
    );
    if (index == -1) return;
    final updated = _conversations[index].copyWith(
      sandboxStatus: sandboxStatus,
      executionStatus: executionStatus,
    );
    final copy = [..._conversations];
    copy[index] = updated;
    _conversations = copy;
    if (_active?.id == conversationId) _active = updated;
  }

  Future<OpenHandsConversation?> createConversation(
    String message, {
    String? repository,
    String? branch,
  }) async {
    if (_creating) return null;
    final trimmed = message.trim();
    if (trimmed.isEmpty) return null;
    _creating = true;
    _error = null;
    notifyListeners();
    try {
      final conversation = await _api.createConversation(
        message: trimmed,
        repository: repository,
        branch: branch,
      );
      _conversations = [
        conversation,
        ..._conversations.where((item) => item.id != conversation.id),
      ];
      _creating = false;
      notifyListeners();
      await openConversation(conversation);
      return conversation;
    } catch (error) {
      _creating = false;
      if (_isAuthError(error)) {
        await _expireSession();
        return null;
      }
      _error = _describeError(error);
      notifyListeners();
      return null;
    }
  }

  // ---------------------------------------------------------------------
  // Guard
  // ---------------------------------------------------------------------

  Future<void> saveGuardConfig(GuardConfig config) async {
    _guard = config.copyWith(
      url: _normalizeGuardUrl(config.url),
      key: config.key.trim(),
    );
    await _store.writeGuardConfig(_guard);
    notifyListeners();
  }

  Future<GuardStatus> testGuard() async {
    _guardTesting = true;
    _guardStatus = null;
    notifyListeners();

    final base = _normalizeGuardUrl(_guard.url);
    if (base.isEmpty) {
      final status = const GuardStatus(
        reachable: false,
        message: 'No Guard address configured.',
      );
      _guardStatus = status;
      _guardTesting = false;
      notifyListeners();
      return status;
    }

    final headers = <String, String>{
      if (_guard.key.isNotEmpty) 'Authorization': 'Bearer ${_guard.key}',
      if (_guard.key.isNotEmpty) 'X-Guard-Key': _guard.key,
      if (_guard.key.isNotEmpty) 'X-API-Key': _guard.key,
    };

    final candidates = <String>[
      '$base/health',
      '$base/healthz',
      '$base/api/health',
      '$base/api/status',
      '$base/status',
      base,
    ];

    GuardStatus? lastStatus;
    for (final candidate in candidates) {
      final watch = Stopwatch()..start();
      try {
        final response = await http
            .get(Uri.parse(candidate), headers: headers)
            .timeout(const Duration(seconds: 20));
        watch.stop();
        if (response.statusCode >= 200 && response.statusCode < 400) {
          final summary = await _guardStatusSummary(base, headers);
          if (summary == 'unauthorized') {
            final status = GuardStatus(
              reachable: false,
              message: 'Guard is online, but the key is wrong',
              latency: watch.elapsed,
              detail: _shorten(response.body),
            );
            _guardStatus = status;
            _guardTesting = false;
            notifyListeners();
            return status;
          }
          final status = GuardStatus(
            reachable: true,
            message: switch (summary) {
              'missing key' => 'Guard is online · add the Guard key',
              null => 'Guard is online',
              _ => 'Guard is online · $summary',
            },
            latency: watch.elapsed,
            detail: _shorten(response.body),
          );
          _guardStatus = status;
          _guardTesting = false;
          notifyListeners();
          return status;
        }
        lastStatus = GuardStatus(
          reachable: false,
          message: 'Guard answered with HTTP ${response.statusCode}',
          latency: watch.elapsed,
          detail: _shorten(response.body),
        );
      } catch (error) {
        watch.stop();
        lastStatus = GuardStatus(
          reachable: false,
          message: 'Could not reach the Guard',
          latency: watch.elapsed,
          detail: error.toString(),
        );
      }
    }

    final status =
        lastStatus ??
        const GuardStatus(reachable: false, message: 'Could not reach Guard');
    _guardStatus = status;
    _guardTesting = false;
    notifyListeners();
    return status;
  }

  Future<String?> _guardStatusSummary(
    String base,
    Map<String, String> headers,
  ) async {
    if (!headers.containsKey('Authorization')) return 'missing key';
    try {
      final response = await http
          .get(Uri.parse('$base/v1/status'), headers: headers)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 401 || response.statusCode == 403) {
        return 'unauthorized';
      }
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      if (data is! Map) return null;
      final watching = data['watching'];
      final active = data['active'];
      if (watching is num && active is num) {
        return 'watching $watching · active $active';
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  String _normalizeGuardUrl(String value) {
    var text = value.trim();
    if (text.isEmpty) return '';
    if (!text.startsWith('http://') && !text.startsWith('https://')) {
      text = 'https://$text';
    }
    while (text.endsWith('/')) {
      text = text.substring(0, text.length - 1);
    }
    return text;
  }

  String? _shorten(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.length <= 400 ? trimmed : '${trimmed.substring(0, 400)}…';
  }

  // ---------------------------------------------------------------------
  // Event mapping
  // ---------------------------------------------------------------------

  List<HandoffTimelineItem> _mapEvents(List<OpenHandsEvent> events) {
    final items = <HandoffTimelineItem>[];
    final actionIndex = <String, int>{};

    for (final event in events) {
      switch (event.kind) {
        case 'MessageEvent':
          final message = event.raw['llm_message'] ?? event.raw['message'];
          final role = message is Map
              ? (message['role'] ?? event.source).toString()
              : event.source;
          final text = contentToText(
            message is Map ? message['content'] : message,
          );
          if (role == 'system' || role == 'tool') continue;
          if (text.trim().isEmpty) continue;
          items.add(
            HandoffTimelineItem(
              id: event.id,
              kind: role == 'user'
                  ? HandoffItemKind.user
                  : HandoffItemKind.assistant,
              text: text.trim(),
              at: event.timestamp,
            ),
          );
        case 'ActionEvent':
          final rawAction = event.raw['action'];
          final action = rawAction is Map
              ? rawAction.cast<String, dynamic>()
              : <String, dynamic>{};
          final detail = describeAction(action);
          final tool = _eventToolName(event);
          if (tool.toLowerCase() == 'think') continue;
          final summary = (event.raw['summary'] ?? '').toString().trim();
          final item = HandoffTimelineItem(
            id: event.id,
            kind: HandoffItemKind.action,
            title: summary.isEmpty ? _toolLabel(tool) : summary,
            toolName: tool,
            arguments: action,
            text: detail,
            running: !_instantTool(tool),
            at: event.timestamp,
            actionId: event.id,
          );
          actionIndex[event.id] = items.length;
          if (event.toolCallId.isNotEmpty) {
            actionIndex[event.toolCallId] = items.length;
          }
          items.add(item);
        case 'ObservationEvent':
          final rawObservation = event.raw['observation'];
          final text = rawObservation is Map
              ? describeObservation(rawObservation.cast<String, dynamic>())
              : contentToText(rawObservation);
          final key = event.actionId.isNotEmpty
              ? event.actionId
              : event.toolCallId;
          int? index = actionIndex[key];
          index ??= _lastActionIndex(
            items,
            _eventToolName(event),
            requireEmptyResult: true,
          );
          if (index != null && index < items.length) {
            final item = items[index];
            item.running = false;
            item.finishedAt = event.timestamp;
            if (text.trim().isNotEmpty) {
              item.result = item.result.trim().isEmpty
                  ? text.trim()
                  : '${item.result}\n\n${text.trim()}';
            }
          } else if (text.trim().isNotEmpty) {
            items.add(
              HandoffTimelineItem(
                id: event.id,
                kind: HandoffItemKind.action,
                title: _toolLabel(_eventToolName(event)),
                toolName: _eventToolName(event),
                result: text.trim(),
                text: text.trim(),
                running: false,
                at: event.timestamp,
                finishedAt: event.timestamp,
              ),
            );
          }
        case 'AgentErrorEvent':
        case 'ErrorEvent':
        case 'ConversationErrorEvent':
          final detail =
              event.raw['error'] ??
              event.raw['detail'] ??
              event.raw['message'] ??
              'The agent hit an error.';
          items.add(
            HandoffTimelineItem(
              id: event.id,
              kind: HandoffItemKind.error,
              text: detail.toString(),
              at: event.timestamp,
            ),
          );
        case 'PauseEvent':
          items.add(
            HandoffTimelineItem(
              id: event.id,
              kind: HandoffItemKind.notice,
              text: 'Agent paused',
              at: event.timestamp,
            ),
          );
        case 'CondensationEvent':
          items.add(
            HandoffTimelineItem(
              id: event.id,
              kind: HandoffItemKind.notice,
              text: 'Context condensed',
              at: event.timestamp,
            ),
          );
        default:
          break;
      }
    }
    final busy = _active?.isRunning ?? false;
    for (final item in items) {
      if (item.kind == HandoffItemKind.action &&
          item.running &&
          (!busy || item.result.trim().isNotEmpty)) {
        item.running = false;
      }
    }
    return items;
  }

  int? _lastActionIndex(
    List<HandoffTimelineItem> items,
    String toolName, {
    required bool requireEmptyResult,
  }) {
    final name = toolName.toLowerCase();
    for (var i = items.length - 1; i >= 0; i--) {
      final item = items[i];
      if (item.kind != HandoffItemKind.action) continue;
      if (name.isNotEmpty && (item.toolName ?? '').toLowerCase() != name) {
        continue;
      }
      if (requireEmptyResult && item.result.trim().isNotEmpty) continue;
      return i;
    }
    return null;
  }

  bool _instantTool(String tool) {
    final name = tool.toLowerCase();
    return name == 'think' || name == 'finish' || name == 'task_tracker';
  }

  String _eventToolName(OpenHandsEvent event) {
    final named = event.toolName.trim();
    if (named.isNotEmpty) return named;
    final action = event.raw['action'];
    if (action is! Map) return '';
    final kind = (action['kind'] ?? '').toString().replaceAll('Action', '');
    if (kind.isEmpty) return '';
    return kind
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match[1]}_${match[2]}',
        )
        .toLowerCase();
  }

  String _toolLabel(String tool) {
    switch (tool.toLowerCase()) {
      case 'terminal':
        return 'Terminal';
      case 'file_editor':
        return 'File editor';
      case 'browse':
      case 'browser':
        return 'Browser';
      case 'task_tracker':
        return 'Task plan';
      case 'think':
        return 'Thinking';
      case 'finish':
        return 'Finished';
      case 'delegate':
        return 'Delegated task';
      default:
        if (tool.isEmpty) return 'Tool';
        final cleaned = tool.replaceAll('_', ' ');
        return cleaned[0].toUpperCase() + cleaned.substring(1);
    }
  }

  @override
  void dispose() {
    _socketGeneration++;
    _cancelSocket();
    _deviceTimer?.cancel();
    _api.close();
    super.dispose();
  }
}

class _StreamingSlot {
  _StreamingSlot({this.startedAt});

  final DateTime? startedAt;
  String text = '';
}
