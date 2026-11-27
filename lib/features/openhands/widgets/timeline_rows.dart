import 'package:flutter/material.dart';

import '../../../icons/broken_icons.dart';
import '../../../shared/widgets/thinking_sheen.dart';
import '../../../theme/app_font_weights.dart';
import '../models/openhands_models.dart';

class OpenHandsThinkingRow extends StatefulWidget {
  const OpenHandsThinkingRow({super.key, required this.item});

  final HandoffTimelineItem item;

  @override
  State<OpenHandsThinkingRow> createState() => _OpenHandsThinkingRowState();
}

class _OpenHandsThinkingRowState extends State<OpenHandsThinkingRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = widget.item;
    final text = item.text.trim();
    final duration = item.duration;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 5 * (1 - value)),
          child: child,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Material(
          color: scheme.primaryContainer.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: text.isEmpty
                ? null
                : () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Broken.lamp_on, size: 15, color: scheme.primary),
                      const SizedBox(width: 7),
                      Expanded(
                        child: item.running
                            ? ThinkingSheen(
                                child: Text(
                                  'Thinking…',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: AppFontWeights.semibold,
                                    color: scheme.primary,
                                  ),
                                ),
                              )
                            : Text(
                                'Thinking',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: AppFontWeights.semibold,
                                  color: scheme.primary,
                                ),
                              ),
                      ),
                      if (duration != null) ...[
                        Text(
                          _formatDuration(duration),
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      AnimatedRotation(
                        turns: _expanded ? 0 : -0.25,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          Broken.arrow_down_1,
                          size: 14,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topLeft,
                    child: _expanded && text.isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: SelectableText(
                              text,
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.45,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OpenHandsToolRow extends StatefulWidget {
  const OpenHandsToolRow({super.key, required this.item});

  final HandoffTimelineItem item;

  @override
  State<OpenHandsToolRow> createState() => _OpenHandsToolRowState();
}

class _OpenHandsToolRowState extends State<OpenHandsToolRow> {
  bool _expanded = false;

  HandoffTimelineItem get item => widget.item;

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
    final hasBody = command.isNotEmpty || result.isNotEmpty || item.running;

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
            onTap: hasBody
                ? () => setState(() => _expanded = !_expanded)
                : null,
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
                          _formatDuration(item.duration!),
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: _expanded ? 0 : -0.25,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          Broken.arrow_down_1,
                          size: 14,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topLeft,
                    child: _expanded
                        ? Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (command.isNotEmpty) ...[
                                  const _DetailLabel(label: 'Command'),
                                  const SizedBox(height: 5),
                                  _DetailBlock(text: command, selectable: true),
                                ],
                                if (result.isNotEmpty) ...[
                                  if (command.isNotEmpty)
                                    const SizedBox(height: 10),
                                  const _DetailLabel(label: 'Output'),
                                  const SizedBox(height: 5),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxHeight: 320,
                                    ),
                                    child: SingleChildScrollView(
                                      child: _DetailBlock(
                                        text: result,
                                        selectable: true,
                                      ),
                                    ),
                                  ),
                                ],
                                if (item.running && result.isEmpty) ...[
                                  if (command.isNotEmpty)
                                    const SizedBox(height: 10),
                                  Text(
                                    'Waiting for output…',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
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
}

class OpenHandsQueuedPromptsTray extends StatelessWidget {
  const OpenHandsQueuedPromptsTray({
    super.key,
    required this.prompts,
    required this.paused,
    required this.canSendNow,
    required this.onEdit,
    required this.onRemove,
    required this.onMove,
    required this.onSendNow,
    required this.onPause,
    required this.onClear,
  });

  final List<QueuedPrompt> prompts;
  final bool paused;
  final bool canSendNow;
  final ValueChanged<QueuedPrompt> onEdit;
  final ValueChanged<String> onRemove;
  final void Function(String id, int offset) onMove;
  final ValueChanged<String> onSendNow;
  final VoidCallback onPause;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (prompts.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Broken.clock, size: 14, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                paused ? 'Queued · paused' : 'Queued · ${prompts.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: AppFontWeights.semibold,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onPause,
                icon: Icon(
                  paused ? Broken.arrow_up_2 : Broken.pause,
                  size: 15,
                ),
                label: Text(paused ? 'Resume' : 'Pause'),
              ),
              IconButton(
                tooltip: 'Clear queue',
                onPressed: onClear,
                icon: const Icon(Broken.trash, size: 16),
              ),
            ],
          ),
          for (final prompt in prompts)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _QueuedPromptCard(
                prompt: prompt,
                canSendNow: canSendNow,
                onEdit: () => onEdit(prompt),
                onRemove: () => onRemove(prompt.id),
                onMoveUp: () => onMove(prompt.id, -1),
                onMoveDown: () => onMove(prompt.id, 1),
                onSendNow: () => onSendNow(prompt.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _QueuedPromptCard extends StatelessWidget {
  const _QueuedPromptCard({
    required this.prompt,
    required this.canSendNow,
    required this.onEdit,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onSendNow,
  });

  final QueuedPrompt prompt;
  final bool canSendNow;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onSendNow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              prompt.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurface),
            ),
          ),
          if (canSendNow)
            IconButton(
              tooltip: 'Send now',
              onPressed: onSendNow,
              icon: const Icon(Broken.arrow_up_2, size: 16),
            ),
          IconButton(
            tooltip: 'Edit',
            onPressed: onEdit,
            icon: const Icon(Broken.message_edit, size: 16),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Broken.more_2, size: 17),
            onSelected: (value) {
              switch (value) {
                case 'up':
                  onMoveUp();
                case 'down':
                  onMoveDown();
                case 'send':
                  onSendNow();
                case 'remove':
                  onRemove();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'up', child: Text('Move up')),
              PopupMenuItem(value: 'down', child: Text('Move down')),
              PopupMenuItem(value: 'send', child: Text('Send now')),
              PopupMenuItem(value: 'remove', child: Text('Remove')),
            ],
          ),
        ],
      ),
    );
  }
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
        color: scheme.surface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(10),
      ),
      child: selectable
          ? SelectableText(text, style: style)
          : Text(text, style: style),
    );
  }
}

String _formatDuration(Duration duration) {
  if (duration.inMilliseconds < 1000) {
    return '${duration.inMilliseconds}ms';
  }
  if (duration.inSeconds < 60) return '${duration.inSeconds}s';
  return '${duration.inMinutes}m';
}
