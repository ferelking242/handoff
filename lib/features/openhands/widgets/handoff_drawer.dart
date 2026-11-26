import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../icons/broken_icons.dart';
import '../../../theme/app_font_weights.dart';
import '../models/openhands_models.dart';
import '../providers/openhands_provider.dart';
import 'handoff_logo.dart';

/// Left navigation: account, conversations, Guard and settings.
class HandoffDrawer extends StatelessWidget {
  const HandoffDrawer({
    super.key,
    required this.provider,
    required this.onSelectConversation,
    required this.onNewConversation,
    required this.onOpenSettings,
    required this.onOpenGuard,
    required this.onOpenAccount,
  });

  final OpenHandsProvider provider;
  final ValueChanged<OpenHandsConversation> onSelectConversation;
  final VoidCallback onNewConversation;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenGuard;
  final VoidCallback onOpenAccount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Drawer(
      width: MediaQuery.sizeOf(context).width * 0.86,
      backgroundColor: scheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 8),
              child: Row(
                children: [
                  const HandoffLogo(size: 34, radius: 10),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Handoff',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: AppFontWeights.heavy,
                            letterSpacing: -0.4,
                            color: scheme.onSurface,
                          ),
                        ),
                        Text(
                          'OpenHands client',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: provider.conversationsLoading
                        ? null
                        : provider.refreshConversations,
                    icon: const Icon(Broken.refresh, size: 19),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: FilledButton.icon(
                onPressed: provider.creating ? null : onNewConversation,
                icon: provider.creating
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimary,
                        ),
                      )
                    : const Icon(Broken.add, size: 18),
                label: Text(provider.creating ? 'Starting…' : 'New conversation'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
              child: Row(
                children: [
                  Text(
                    'CONVERSATIONS',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.2,
                      fontWeight: AppFontWeights.semibold,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (provider.visibleConversations.isNotEmpty)
                    Text(
                      '${provider.visibleConversations.length}',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  IconButton(
                    tooltip: 'New folder',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _showFolderNameDialog(context, provider),
                    icon: Icon(
                      Broken.folder_add,
                      size: 17,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _ConversationList(provider: provider, onSelect: onSelectConversation)),
            _DrawerFooter(
              provider: provider,
              onOpenAccount: onOpenAccount,
              onOpenGuard: onOpenGuard,
              onOpenSettings: onOpenSettings,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationList extends StatelessWidget {
  const _ConversationList({required this.provider, required this.onSelect});

  final OpenHandsProvider provider;
  final ValueChanged<OpenHandsConversation> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = provider.visibleConversations;
    final archived = provider.archivedConversations;
    final byId = {
      for (final conversation in visible) conversation.id: conversation,
    };
    final ungrouped = visible
        .where(
          (conversation) =>
              provider.folderForConversation(conversation.id) == null,
        )
        .toList(growable: false);

    if (visible.isEmpty && archived.isEmpty && provider.folders.isEmpty) {
      if (provider.conversationsLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (provider.conversationsError != null) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Broken.warning_2, size: 28, color: scheme.error),
              const SizedBox(height: 8),
              Text(
                provider.conversationsError!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: provider.refreshConversations,
                child: const Text('Retry'),
              ),
            ],
          ),
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Broken.message,
                size: 30,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 10),
              Text(
                'No conversations yet',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: AppFontWeights.medium,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final children = <Widget>[];
    for (final conversation in ungrouped) {
      children.add(
        _ConversationTile(
          conversation: conversation,
          selected: provider.active?.id == conversation.id,
          onTap: () => onSelect(conversation),
        ),
      );
    }

    for (final folder in provider.folders) {
      final conversations = folder.conversationIds
          .map((id) => byId[id])
          .whereType<OpenHandsConversation>()
          .toList(growable: false);
      final expanded = provider.isFolderExpanded(folder.id);
      children.add(
        _FolderHeader(
          folder: folder,
          count: conversations.length,
          expanded: expanded,
          onToggle: () => provider.toggleFolder(folder.id),
          onRename: () =>
              _showFolderNameDialog(context, provider, folder: folder),
          onDelete: () => _confirmDeleteFolder(context, provider, folder),
        ),
      );
      if (expanded) {
        for (final conversation in conversations) {
          children.add(
            _ConversationTile(
              conversation: conversation,
              selected: provider.active?.id == conversation.id,
              indent: 14,
              onTap: () => onSelect(conversation),
            ),
          );
        }
        if (conversations.isEmpty) {
          children.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 2, 16, 8),
              child: Text(
                'Empty folder',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ),
          );
        }
      }
    }

    if (archived.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 16, 4),
          child: Row(
            children: [
              Icon(Broken.archive, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                'ARCHIVED',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: AppFontWeights.semibold,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                '${archived.length}',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
      for (final conversation in archived) {
        children.add(
          _ConversationTile(
            conversation: conversation,
            selected: provider.active?.id == conversation.id,
            indent: 10,
            onTap: () => onSelect(conversation),
          ),
        );
      }
    }

    if (provider.hasMoreConversations) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: TextButton(
              onPressed: provider.conversationsLoading
                  ? null
                  : provider.loadMoreConversations,
              child: Text(
                provider.conversationsLoading ? 'Loading…' : 'Load more',
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: provider.refreshConversations,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        children: children,
      ),
    );
  }
}

class _FolderHeader extends StatelessWidget {
  const _FolderHeader({
    required this.folder,
    required this.count,
    required this.expanded,
    required this.onToggle,
    required this.onRename,
    required this.onDelete,
  });

  final OpenHandsFolder folder;
  final int count;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
            child: Row(
              children: [
                Icon(
                  expanded ? Broken.arrow_down_2 : Broken.arrow_right_2,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Icon(Broken.folder, size: 16, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: AppFontWeights.semibold,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                Text(
                  '$count',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
                PopupMenuButton<String>(
                  icon: Icon(
                    Broken.more_2,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  tooltip: 'Folder options',
                  onSelected: (value) {
                    if (value == 'rename') onRename();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename folder')),
                    PopupMenuItem(value: 'delete', child: Text('Delete folder')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _ConversationAction { pause, resume, archive, unarchive, move, delete }

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.selected,
    required this.onTap,
    this.indent = 0,
  });

  final OpenHandsConversation conversation;
  final bool selected;
  final VoidCallback onTap;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = conversation.subtitle;
    final provider = context.read<OpenHandsProvider>();
    final archived = provider.archivedIds.contains(conversation.id);

    return Padding(
      padding: EdgeInsets.only(left: indent, bottom: 2),
      child: Dismissible(
        key: ValueKey('conversation-${conversation.id}'),
        direction: DismissDirection.horizontal,
        background: const _SwipeBackground(
          alignment: Alignment.centerLeft,
          color: Color(0xFFDC2626),
          icon: Broken.trash,
          label: 'Delete',
        ),
        secondaryBackground: const _SwipeBackground(
          alignment: Alignment.centerRight,
          color: Color(0xFFD97706),
          icon: Broken.archive,
          label: 'Archive',
        ),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            final confirmed = await _confirmDeleteConversation(
              context,
              conversation,
            );
            if (!confirmed) return false;
            return provider.deleteConversation(conversation);
          }
          await provider.archiveConversation(conversation);
          return true;
        },
        child: Material(
          color: selected
              ? scheme.primary.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: _StatusDot(conversation: conversation),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                conversation.displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: selected
                                      ? AppFontWeights.semibold
                                      : AppFontWeights.medium,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _relative(conversation.updatedAt),
                              style: TextStyle(
                                fontSize: 10,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            PopupMenuButton<_ConversationAction>(
                              icon: Icon(
                                Broken.more_2,
                                size: 18,
                                color: scheme.onSurfaceVariant,
                              ),
                              tooltip: 'Conversation options',
                              padding: EdgeInsets.zero,
                              onSelected: (action) async {
                                switch (action) {
                                  case _ConversationAction.pause:
                                    await provider.pauseConversation(
                                      conversation,
                                    );
                                  case _ConversationAction.resume:
                                    await provider.resumeConversation(
                                      conversation,
                                    );
                                  case _ConversationAction.archive:
                                    await provider.archiveConversation(
                                      conversation,
                                    );
                                  case _ConversationAction.unarchive:
                                    await provider.unarchiveConversation(
                                      conversation,
                                    );
                                  case _ConversationAction.move:
                                    await _showMoveDialog(
                                      context,
                                      provider,
                                      conversation,
                                    );
                                  case _ConversationAction.delete:
                                    final confirmed =
                                        await _confirmDeleteConversation(
                                          context,
                                          conversation,
                                        );
                                    if (confirmed) {
                                      await provider.deleteConversation(
                                        conversation,
                                      );
                                    }
                                }
                              },
                              itemBuilder: (context) => [
                                if (conversation.isRunning)
                                  const PopupMenuItem(
                                    value: _ConversationAction.pause,
                                    child: Text('Pause'),
                                  )
                                else if (conversation.canResume)
                                  const PopupMenuItem(
                                    value: _ConversationAction.resume,
                                    child: Text('Resume'),
                                  ),
                                const PopupMenuItem(
                                  value: _ConversationAction.move,
                                  child: Text('Move to folder'),
                                ),
                                if (archived)
                                  const PopupMenuItem(
                                    value: _ConversationAction.unarchive,
                                    child: Text('Unarchive'),
                                  )
                                else
                                  const PopupMenuItem(
                                    value: _ConversationAction.archive,
                                    child: Text('Archive'),
                                  ),
                                const PopupMenuItem(
                                  value: _ConversationAction.delete,
                                  child: Text('Delete'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _relative(DateTime? time) {
    if (time == null) return '';
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return DateFormat.MMMd().format(time);
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.conversation});

  final OpenHandsConversation conversation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _statusColor(scheme);
    return Tooltip(
      message: _statusLabel(),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: conversation.isRunning || conversation.isStarting
              ? [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 6)]
              : null,
        ),
      ),
    );
  }

  Color _statusColor(ColorScheme scheme) {
    if (conversation.hasError) return const Color(0xFFEF4444);
    if (conversation.isRunning) return const Color(0xFF22C55E);
    if (conversation.isStarting || conversation.isPaused) {
      return const Color(0xFFF59E0B);
    }
    if (conversation.isFinished) return const Color(0xFF22C55E);
    return scheme.onSurfaceVariant.withValues(alpha: 0.45);
  }

  String _statusLabel() {
    if (conversation.hasError) return 'Error';
    if (conversation.isRunning) return 'Running';
    if (conversation.isStarting) return 'Starting';
    if (conversation.isPaused) return 'Paused';
    if (conversation.isFinished) return 'Finished';
    return 'Idle';
  }
}

Future<void> _showFolderNameDialog(
  BuildContext context,
  OpenHandsProvider provider, {
  OpenHandsFolder? folder,
}) async {
  final controller = TextEditingController(text: folder?.name ?? '');
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(folder == null ? 'New folder' : 'Rename folder'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Folder name'),
        onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  final name = result?.trim() ?? '';
  if (name.isEmpty) return;
  if (folder == null) {
    await provider.createFolder(name);
  } else {
    await provider.renameFolder(folder.id, name);
  }
}

Future<void> _confirmDeleteFolder(
  BuildContext context,
  OpenHandsProvider provider,
  OpenHandsFolder folder,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Delete “${folder.name}”?'),
      content: const Text('The conversations inside stay in your list.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed == true) await provider.deleteFolder(folder.id);
}

Future<void> _showMoveDialog(
  BuildContext context,
  OpenHandsProvider provider,
  OpenHandsConversation conversation,
) async {
  final current = provider.folderForConversation(conversation.id)?.id;
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('Move to folder'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.of(dialogContext).pop(''),
          child: const Text('No folder'),
        ),
        for (final folder in provider.folders)
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(folder.id),
            child: Row(
              children: [
                Icon(
                  current == folder.id ? Broken.folder_open : Broken.folder,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(folder.name)),
              ],
            ),
          ),
        if (provider.folders.isEmpty)
          const SimpleDialogOption(
            onPressed: null,
            child: Text('Create a folder first'),
          ),
      ],
    ),
  );
  if (result == null) return;
  await provider.moveConversationToFolder(
    conversation.id,
    result.isEmpty ? null : result,
  );
}

Future<bool> _confirmDeleteConversation(
  BuildContext context,
  OpenHandsConversation conversation,
) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete conversation?'),
          content: Text(
            '“${conversation.displayTitle}” is removed from OpenHands and this device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;
}

class _DrawerFooter extends StatelessWidget {
  const _DrawerFooter({
    required this.provider,
    required this.onOpenAccount,
    required this.onOpenGuard,
    required this.onOpenSettings,
  });

  final OpenHandsProvider provider;
  final VoidCallback onOpenAccount;
  final VoidCallback onOpenGuard;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = provider.user;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onOpenAccount,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: scheme.primary.withValues(alpha: 0.16),
                      child: Text(
                        user?.initial ?? 'O',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: AppFontWeights.semibold,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        user?.displayName ?? 'Account',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: AppFontWeights.medium,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'OpenHands Guard',
            onPressed: onOpenGuard,
            icon: Icon(
              Broken.shield_tick,
              size: 21,
              color: provider.guard.isConfigured
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: onOpenSettings,
            icon: Icon(
              Broken.setting_2,
              size: 21,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
