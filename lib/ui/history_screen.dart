import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../agent/agent_controller.dart';
import '../agent/agent_models.dart';
import '../agent/chat_session.dart';
import 'task_screen.dart';

/// 지난 대화를 열어 진행 화면으로 간다. 다른 대화가 진행 중이면 읽기 전용으로 열린다.
void openChat(BuildContext context, ChatSession s) {
  unawaited(context.read<AgentController>().openSession(s.id));
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskScreen(sessionId: s.id)));
}

/// 대화 삭제 (확인 후). 지웠으면 true.
Future<bool> confirmDeleteChat(BuildContext context, ChatSession s) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('대화 삭제'),
      content: Text('"${s.title}" 대화를 삭제할까요?\n삭제하면 다시 열 수 없습니다.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  final deleted = await context.read<AgentController>().deleteSession(s.id);
  if (!deleted && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('진행 중인 대화는 삭제할 수 없어요. 먼저 중지하세요.')));
  }
  return deleted;
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<ChatSessionStore>().sessions;
    context.watch<AgentController>(); // 진행 중 표시 갱신

    return Scaffold(
      appBar: AppBar(title: const Text('대화 기록')),
      body: sessions.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '아직 대화가 없어요.\n작업을 실행하면 여기에 남아서 언제든 다시 열어 이어갈 수 있어요.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: sessions.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
              itemBuilder: (context, i) {
                final s = sessions[i];
                return Dismissible(
                  key: ValueKey(s.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Theme.of(context).colorScheme.errorContainer,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: const Icon(Icons.delete_outline),
                  ),
                  confirmDismiss: (_) => confirmDeleteChat(context, s),
                  child: ChatSessionTile(session: s),
                );
              },
            ),
    );
  }
}

class ChatSessionTile extends StatelessWidget {
  const ChatSessionTile({super.key, required this.session});

  final ChatSession session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final scheme = Theme.of(context).colorScheme;
    final isOpen = context.select<AgentController, bool>((a) => a.current?.id == s.id);
    final (IconData icon, Color color) = switch (s.status) {
      AgentStatus.running => (Icons.autorenew, scheme.primary),
      AgentStatus.waitingApproval ||
      AgentStatus.waitingUser => (Icons.notification_important, Colors.orange),
      AgentStatus.finished => (Icons.task_alt, Colors.green),
      AgentStatus.failed => (Icons.error_outline, scheme.error),
      AgentStatus.cancelled => (Icons.stop_circle_outlined, scheme.outline),
      AgentStatus.idle => (Icons.chat_bubble_outline, scheme.outline),
    };
    final preview = s.preview;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        foregroundColor: color,
        child: Icon(icon),
      ),
      title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (s.isRemote) '서버',
          formatWhen(s.updatedAt),
          if (preview.isNotEmpty) preview,
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: isOpen ? Icon(Icons.visibility, size: 18, color: scheme.primary) : null,
      onTap: () => openChat(context, s),
      onLongPress: () => confirmDeleteChat(context, s),
    );
  }
}

/// 목록용 짧은 시간 표시: 방금 / 5분 전 / 3시간 전 / 어제 / 9월 24일 / 2025.9.24
String formatWhen(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final d = n.difference(t);
  if (d.inMinutes < 1) return '방금';
  if (d.inHours < 1) return '${d.inMinutes}분 전';
  final today = DateTime(n.year, n.month, n.day);
  if (!t.isBefore(today)) return '${d.inHours}시간 전';
  if (!t.isBefore(today.subtract(const Duration(days: 1)))) return '어제';
  if (t.year == n.year) return '${t.month}월 ${t.day}일';
  return '${t.year}.${t.month}.${t.day}';
}
