import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/models/chat_input_data.dart';
import '../../../core/models/chat_message.dart';
import '../../../icons/broken_icons.dart';
import '../../../theme/app_font_weights.dart';
import '../../chat/widgets/chat_message_widget.dart';
import '../../home/widgets/chat_input_bar.dart';
import '../models/openhands_models.dart';
import '../providers/openhands_provider.dart';
import '../widgets/handoff_logo.dart';
import 'guard_page.dart';
import 'settings_page.dart';

/// The chat surface for one OpenHands conversation.
class OpenHandsConversationView extends StatefulWidget {
  const OpenHandsConversationView({super.key});

  @override
  State<OpenHandsConversationView> createState() =>
      _OpenHandsConversationViewState();
}

class _OpenHandsConversationViewState extends State<OpenHandsConversationView> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _composer = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  int _lastItemCount = 0;
  bool _atBottom = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _composer.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final atBottom = position.pixels >= position.maxScrollExtent - 80;
    if (atBottom != _atBottom) {
      setState(() => _atBottom = atBottom);
    }
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_scrollController.hasClients) return;
    final target = _scrollController.position.maxScrollExtent;
    if (animate) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  Future<ChatInputSubmissionResult> _send(ChatInputData data) async {
    final text = data.text.trim();
    if (text.isEmpty) return ChatInputSubmissionResult.rejected;
    final provider = context.read<OpenHandsProvider>();
    final sent = await provider.sendMessage(text);
    if (sent) _scrollToBottom();
    return sent
        ? ChatInputSubmissionResult.sent
        : ChatInputSubmissionResult.rejected;
  }

  void _openModelSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const OpenHandsSettingsPage()));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OpenHandsProvider>();
    final timeline = provider.timeline;
    final scheme = Theme.of(context).colorScheme;

    if (timeline.length != _lastItemCount) {
      final grew = timeline.length > _lastItemCount;
      _lastItemCount = timeline.length;
      if (grew && _atBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    }

    if (provider.timelineLoading && timeline.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (timeline.isEmpty && provider.timelineError != null) {
      return _ConversationError(
        message: provider.timelineError!,
        onRetry: provider.refreshTimeline,
      );
    }

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              timeline.isEmpty
                  ? _EmptyConversation(provider: provider)
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(top: 8, bottom: 8),
                      itemCount: timeline.length,
                      itemBuilder: (context, index) {
                        final item = timeline[index];
                        return _TimelineRow(
                          item: item,
                          conversationId: provider.active?.id ?? 'handoff',
                        );
                      },
                    ),
              Positioned(
                right: 16,
                bottom: 12,
                child: AnimatedOpacity(
                  opacity: _atBottom ? 0 : 1,
                  duration: const Duration(milliseconds: 180),
                  child: AnimatedScale(
                    scale: _atBottom ? 0.85 : 1,
                    duration: const Duration(milliseconds: 180),
                    child: IgnorePointer(
                      ignoring: _atBottom,
                      child: Material(
                        color: scheme.surfaceContainerHighest,
                        elevation: 3,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _scrollToBottom(),
                          child: Padding(
                            padding: const EdgeInsets.all(9),
                            child: Icon(
                              Broken.arrow_down_2,
                              size: 20,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (provider.agentRunning)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Agent is working…',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(),
        if (provider.timelineError != null && timeline.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              provider.timelineError!,
              style: TextStyle(fontSize: 12, color: scheme.error),
            ),
          ),
        ChatInputBar(
          controller: _composer,
          focusNode: _composerFocus,
          loading: provider.agentRunning || provider.sending,
          onSend: _send,
          onStop: () => provider.stopAgent(),
          onSelectModel: _openModelSettings,
          chatModelId: provider.active?.llmModel,
          modelIcon: const HandoffLogo(size: 22, radius: 7),
          showMoreButton: false,
          showToolsButton: false,
          showMiniMapButton: false,
          showWorkspaceButton: false,
          showQuickPhraseButton: false,
          showOcrButton: false,
          sendButtonTooltip: 'Send',
        ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.item, required this.conversationId});

  final HandoffTimelineItem item;
  final String conversationId;

  ChatMessage _message() {
    switch (item.kind) {
      case HandoffItemKind.user:
        return ChatMessage(
          id: item.id,
          role: 'user',
          content: item.text,
          conversationId: conversationId,
          timestamp: item.at,
        );
      case HandoffItemKind.assistant:
        return ChatMessage(
          id: item.id,
          role: 'assistant',
          content: item.text,
          conversationId: conversationId,
          timestamp: item.at,
          isStreaming: item.running,
        );
      case HandoffItemKind.action:
        return ChatMessage(
          id: item.id,
          role: 'assistant',
          content: item.text,
          conversationId: conversationId,
          timestamp: item.at,
        );
      case HandoffItemKind.error:
      case HandoffItemKind.notice:
        return ChatMessage(
          id: item.id,
          role: 'assistant',
          content: item.text,
          conversationId: conversationId,
          timestamp: item.at,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (item.kind == HandoffItemKind.error) return _ErrorRow(item: item);
    if (item.kind == HandoffItemKind.notice) return _NoticeRow(item: item);
    if (item.kind == HandoffItemKind.action) return _ToolRow(item: item);
    return ChatMessageWidget(
      key: ValueKey('${item.kind.name}-${item.id}'),
      message: _message(),
      showTokenStats: false,
      showModelIcon: false,
      useAssistantAvatar: false,
      useAssistantName: true,
      assistantName: 'OpenHands',
      hideStreamingIndicator: !item.running,
      enableStreamingTextMotion: true,
      showThinkingCards: false,
      showToolCards: true,
      collapseThinkingSteps: true,
      onGuard: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const OpenHandsGuardPage()),
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({required this.item});

  final HandoffTimelineItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final command = _command();
    final result = item.result.trim();
    final hasError = result.toLowerCase().contains('traceback') ||
        result.toLowerCase().startsWith('error') ||
        result.toLowerCase().contains('\nerror:');
    final statusColor = item.running
        ? scheme.primary
        : hasError
            ? const Color(0xFFEF4444)
            : const Color(0xFF22C55E);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 6 * (1 - value)),
          child: child,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Material(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _showToolDetail(context, item),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_icon(), size: 15, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          item.title ?? item.toolName ?? 'Tool',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: AppFontWeights.semibold,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      if (item.running)
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: statusColor,
                          ),
                        )
                      else
                        Icon(
                          hasError ? Broken.close_circle : Broken.tick_circle,
                          size: 14,
                          color: statusColor,
                        ),
                      if (item.duration != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          _duration(item.duration!),
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(width: 2),
                      Icon(
                        Broken.arrow_right_2,
                        size: 14,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ],
                  ),
                  if (command.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surface.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        command,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                          height: 1.35,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                  if (result.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      result,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        height: 1.35,
                        color: hasError
                            ? scheme.error
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _command() {
    final args = item.arguments;
    final command = (args['command'] ?? '').toString().trim();
    final path = (args['path'] ?? '').toString().trim();
    final url = (args['url'] ?? '').toString().trim();
    if (command.isNotEmpty) {
      if (path.isNotEmpty && !command.contains(path)) return '$command  $path';
      return command;
    }
    if (path.isNotEmpty) return path;
    if (url.isNotEmpty) return url;
    final text = item.text.trim();
    if (text.isEmpty) return '';
    return text.split('\n').first;
  }

  IconData _icon() {
    switch ((item.toolName ?? '').toLowerCase()) {
      case 'terminal':
        return Broken.command_square;
      case 'file_editor':
        return Broken.document_code;
      case 'browse':
      case 'browser':
        return Broken.global;
      case 'finish':
        return Broken.tick_circle;
      default:
        return Broken.code;
    }
  }

  String _duration(Duration duration) {
    if (duration.inMilliseconds < 1000) {
      return '${duration.inMilliseconds}ms';
    }
    if (duration.inSeconds < 60) return '${duration.inSeconds}s';
    return '${duration.inMinutes}m';
  }
}

void _showToolDetail(BuildContext context, HandoffTimelineItem item) {
  final scheme = Theme.of(context).colorScheme;
  final command = item.arguments['command']?.toString() ?? item.text.trim();
  final output = item.result.trim();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.82,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.title ?? item.toolName ?? 'Tool',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: AppFontWeights.semibold,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  icon: const Icon(Broken.close_circle, size: 22),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  if (command.isNotEmpty) ...[
                    _DetailLabel(label: 'Command'),
                    const SizedBox(height: 6),
                    _DetailBlock(text: command),
                    const SizedBox(height: 14),
                  ],
                  _DetailLabel(label: 'Output'),
                  const SizedBox(height: 6),
                  if (output.isEmpty)
                    Text(
                      item.running ? 'Waiting for output…' : 'No output',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  else
                    _DetailBlock(text: output, selectable: true),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DetailLabel extends StatelessWidget {
  const _DetailLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        letterSpacing: 1.1,
        fontWeight: AppFontWeights.semibold,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({required this.text, this.selectable = false});

  final String text;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12,
      height: 1.45,
      color: scheme.onSurface,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: selectable
          ? SelectableText(text, style: style)
          : Text(text, style: style),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.item});

  final HandoffTimelineItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Broken.warning_2, size: 18, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              item.text,
              style: TextStyle(fontSize: 13, color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeRow extends StatelessWidget {
  const _NoticeRow({required this.item});

  final HandoffTimelineItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          item.text,
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation({required this.provider});

  final OpenHandsProvider provider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final suggestions = [
      'What are you working on?',
      'Summarize this conversation',
      'List the files in the workspace',
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const SizedBox(height: 40),
          const HandoffLogo(size: 64, radius: 20),
          const SizedBox(height: 18),
          Text(
            provider.active?.displayTitle ?? 'New conversation',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: AppFontWeights.semibold,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Send the first message to wake the agent.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          ...suggestions.map(
            (text) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ActionChip(
                label: Text(text),
                onPressed: () => provider.sendMessage(text),
                avatar: const Icon(Broken.flash, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationError extends StatelessWidget {
  const _ConversationError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Broken.warning_2, size: 36, color: scheme.error),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

String formatRelative(DateTime? time) {
  if (time == null) return '';
  final now = DateTime.now();
  final diff = now.difference(time);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return DateFormat.MMMd().format(time);
}
