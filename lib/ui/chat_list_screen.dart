import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../agent/agent_controller.dart';
import '../agent/agent_models.dart';
import '../agent/chat_session.dart';
import 'main_shell.dart';
import 'task_screen.dart';

/// 채팅 탭: 대화(작업) 목록. 새 채팅을 열거나 지난 대화를 열어 이어서 지시한다.
class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  void _open(BuildContext context, ChatSession s) {
    final agent = context.read<AgentController>();
    if (agent.isBusy && s.id != agent.current.id) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('진행 중인 작업이 끝나거나 중지한 뒤에 열 수 있어요.')));
      return;
    }
    agent.openSession(s.id);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TaskScreen()));
  }

  Future<bool> _confirmDelete(BuildContext context, ChatSession s) async {
    final agent = context.read<AgentController>();
    if (agent.isBusy && s.id == agent.current.id) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('진행 중인 작업은 먼저 중지해 주세요.')));
      return false;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('채팅 삭제'),
        content: Text('"${s.title}" 대화를 이 기기에서 삭제할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('삭제')),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final agent = context.watch<AgentController>();
    final theme = Theme.of(context);
    final sessions = agent.chats;

    return Scaffold(
      appBar: AppBar(
        title: const Text('채팅'),
        actions: [
          IconButton(
            tooltip: '새 채팅',
            icon: const Icon(Icons.edit_square),
            onPressed: agent.isBusy ? null : () => openNewChat(context),
          ),
        ],
      ),
      body: ListView(
        padding: tabListPadding(context),
        children: [
          if (agent.isBusy) ActiveTaskBanner(agent: agent),
          Card(
            color: theme.colorScheme.primaryContainer,
            child: ListTile(
              leading: const Icon(Icons.add_comment_outlined),
              title: const Text('새 채팅'),
              subtitle: Text(agent.isBusy ? '진행 중인 작업이 끝나면 시작할 수 있어요' : '무엇을 해드릴까요?'),
              enabled: !agent.isBusy,
              onTap: () => openNewChat(context),
            ),
          ),
          const SizedBox(height: 16),
          Text('지난 채팅', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                '아직 대화가 없어요.\n새 채팅에서 에이전트에게 할 일을 맡겨 보세요.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final s in sessions)
            Dismissible(
              key: ValueKey(s.id),
              direction: DismissDirection.endToStart,
              confirmDismiss: (_) => _confirmDelete(context, s),
              onDismissed: (_) => agent.deleteSession(s.id),
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                color: theme.colorScheme.errorContainer,
                child: Icon(Icons.delete_outline, color: theme.colorScheme.onErrorContainer),
              ),
              child: _SessionTile(
                session: s,
                current: s.id == agent.current.id,
                needsYou:
                    s.id == agent.current.id &&
                    (agent.pendingApproval != null || agent.pendingQuestion != null),
                onTap: () => _open(context, s),
              ),
            ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.current,
    required this.needsYou,
    required this.onTap,
  });

  final ChatSession session;
  final bool current;
  final bool needsYou;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = session;
    final busy =
        s.status == AgentStatus.running ||
        s.status == AgentStatus.waitingApproval ||
        s.status == AgentStatus.waitingUser;

    final Widget leading = needsYou
        ? Icon(Icons.notification_important, color: scheme.error)
        : busy && current
        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
        : Icon(switch (s.status) {
            AgentStatus.finished => Icons.task_alt,
            AgentStatus.failed => Icons.error_outline,
            AgentStatus.cancelled => Icons.stop_circle_outlined,
            _ => s.remoteTaskId != null ? Icons.cloud_outlined : Icons.chat_bubble_outline,
          }, color: s.status == AgentStatus.failed ? scheme.error : scheme.onSurfaceVariant);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: SizedBox(width: 32, child: Center(child: leading)),
      title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (busy && current) statusLabel(s.status),
          if (!(busy && current) && s.preview.isNotEmpty) s.preview.replaceAll('\n', ' '),
        ].join(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        _when(s.updatedAt),
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
      onTap: onTap,
    );
  }

  static String _when(DateTime t) {
    final now = DateTime.now();
    final d = now.difference(t);
    if (d.inMinutes < 1) return '방금';
    if (d.inHours < 1) return '${d.inMinutes}분 전';
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    if (t.year == now.year) return '${t.month}월 ${t.day}일';
    return '${t.year}. ${t.month}. ${t.day}.';
  }
}
