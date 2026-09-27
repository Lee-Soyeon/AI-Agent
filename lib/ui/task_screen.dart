import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:provider/provider.dart';

import '../agent/agent_controller.dart';
import '../agent/agent_models.dart';
import '../core/settings_store.dart';
import 'app_theme.dart';
import 'browser_pip.dart';
import 'guide_screen.dart' show taskExamples;
import 'main_shell.dart';

/// 새 채팅을 열고 작업 화면으로 간다. [draft] 가 있으면 입력창에 미리 채운다.
void openNewChat(BuildContext context, {String? draft}) {
  context.read<AgentController>().newSession();
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskScreen(initialDraft: draft)));
}

/// 한 채팅(대화)의 작업 화면. 새 채팅이면 할 일을 입력받고, 진행 중이면 로그·승인 카드를 보여준다.
class TaskScreen extends StatefulWidget {
  const TaskScreen({super.key, this.initialDraft});

  final String? initialDraft;

  @override
  State<TaskScreen> createState() => _TaskScreenState();
}

class _TaskScreenState extends State<TaskScreen> {
  late final _followUp = TextEditingController(text: widget.initialDraft);
  final _scroll = ScrollController();
  int _lastLogCount = 0;
  bool _userScrolling = false; // 로그를 직접 넘기는 동안 미니 화면을 흐리게

  void _send(AgentController agent) {
    final t = _followUp.text.trim();
    if (t.isEmpty) return;
    if (agent.current.isEmpty) {
      final settings = context.read<SettingsStore>();
      if (!settings.isConfigured) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              settings.runOnServer ? '먼저 모델 탭에서 서버 주소와 토큰을 입력하세요.' : '먼저 모델 탭에서 LLM API 키를 입력하세요.',
            ),
            action: SnackBarAction(
              label: '모델 설정',
              onPressed: () {
                context.read<ShellTabs>().go(AppTab.model);
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
            ),
          ),
        );
        return;
      }
      agent.startTask(t);
    } else {
      agent.followUp(t);
    }
    _followUp.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    _followUp.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _autoScroll(int count) {
    if (count == _lastLogCount) return;
    _lastLogCount = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final agent = context.watch<AgentController>();
    _autoScroll(agent.logs.length);
    final session = agent.current;
    final fresh = session.isEmpty && !agent.isBusy;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(fresh ? '새 채팅' : session.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (!fresh)
              Text(statusLabel(agent.status), style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          if (agent.isBusy)
            TextButton.icon(
              onPressed: agent.cancel,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('중지'),
            ),
        ],
        bottom: agent.status == AgentStatus.running
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: Column(
        children: [
          Expanded(
            child: fresh
                ? _NewChatHint(onPick: (e) => _followUp.text = e)
                : Stack(
                    children: [
                      NotificationListener<UserScrollNotification>(
                        onNotification: (n) {
                          final scrolling = n.direction != ScrollDirection.idle;
                          if (scrolling != _userScrolling) {
                            setState(() => _userScrolling = scrolling);
                          }
                          return false;
                        },
                        child: ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          itemCount: agent.logs.length,
                          itemBuilder: (_, i) => _LogTile(entry: agent.logs[i]),
                        ),
                      ),
                      if (agent.lastScreenshot != null)
                        Positioned.fill(
                          child: BrowserPip(
                            screenshot: agent.lastScreenshot!,
                            live: agent.status == AgentStatus.running,
                            caption: latestAction(agent.logs),
                            dimmed: _userScrolling,
                            onOpen: () => Navigator.of(context).push(BrowserViewerPage.route()),
                          ),
                        ),
                    ],
                  ),
          ),
          if (agent.pendingApproval != null)
            _ApprovalCard(agent: agent, request: agent.pendingApproval!),
          if (agent.pendingQuestion != null)
            _QuestionCard(agent: agent, question: agent.pendingQuestion!),
          if (!agent.isBusy && !fresh && !agent.hasConversation)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '앱을 다시 시작해서 이 대화는 이어서 지시할 수 없어요.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        agent.newSession();
                        setState(() {});
                      },
                      child: const Text('새 채팅'),
                    ),
                  ],
                ),
              ),
            ),
          if (!agent.isBusy && (fresh || agent.hasConversation))
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _followUp,
                        autofocus: fresh && widget.initialDraft == null,
                        minLines: 1,
                        maxLines: fresh ? 6 : 4,
                        decoration: InputDecoration(
                          hintText: fresh ? '예) 쿠팡에서 휴지 30롤 담아줘' : '이어서 지시하기 (예: 두 번째 메일에 답장 써줘)',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      icon: Icon(fresh ? Icons.play_arrow : Icons.send),
                      tooltip: fresh ? '실행' : '보내기',
                      onPressed: () => _send(agent),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});

  final AgentLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, Color color) = switch (entry.kind) {
      LogKind.user => (Icons.person, scheme.primary),
      LogKind.thought => (Icons.psychology_alt, scheme.tertiary),
      LogKind.action => (Icons.touch_app, scheme.secondary),
      LogKind.observation => (Icons.visibility, scheme.outline),
      LogKind.approval => (Icons.verified_user, AppTokens.of(context).warningInk),
      LogKind.error => (Icons.error_outline, scheme.error),
      LogKind.result => (Icons.flag, scheme.primary),
    };

    final body = entry.kind == LogKind.result || entry.kind == LogKind.user
        ? Card(
            color: entry.kind == LogKind.result ? scheme.primaryContainer : scheme.surfaceContainer,
            margin: EdgeInsets.zero,
            child: Padding(padding: const EdgeInsets.all(12), child: SelectableText(entry.text)),
          )
        : Text(
            entry.text,
            style: TextStyle(
              color: entry.kind == LogKind.observation ? scheme.outline : null,
              fontSize: entry.kind == LogKind.observation ? 12 : 14,
            ),
          );

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: body),
        ],
      ),
    );

    if (entry.detail == null) return row;
    return InkWell(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          builder: (_, c) => SingleChildScrollView(
            controller: c,
            padding: const EdgeInsets.all(16),
            child: SelectableText(entry.detail!, style: const TextStyle(fontSize: 12)),
          ),
        ),
      ),
      child: row,
    );
  }
}

class _ApprovalCard extends StatefulWidget {
  const _ApprovalCard({required this.agent, required this.request});

  final AgentController agent;
  final ApprovalRequest request;

  @override
  State<_ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends State<_ApprovalCard> {
  final _feedback = TextEditingController();

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppTokens.r),
          border: Border.all(color: AppTokens.of(context).warningLine, width: 2),
          boxShadow: AppTokens.shadowLg,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(switch (r.kind) {
                    ApprovalKind.purchase => Icons.payments,
                    ApprovalKind.sendEmail => Icons.outgoing_mail,
                    ApprovalKind.sendMessage => Icons.send,
                    ApprovalKind.booking => Icons.event_available,
                    ApprovalKind.post => Icons.public,
                    ApprovalKind.submit => Icons.assignment_turned_in,
                    ApprovalKind.terminate => Icons.cancel,
                    ApprovalKind.other => Icons.warning_amber,
                  }, color: AppTokens.of(context).warningInk),
                  const SizedBox(width: 8),
                  Expanded(child: Text(r.title, style: Theme.of(context).textTheme.titleMedium)),
                  Chip(label: Text(r.kind.label)),
                ],
              ),
              const SizedBox(height: 8),
              SelectableText(r.summary),
              if (r.handoff) ...[
                const SizedBox(height: 8),
                Text(
                  '에이전트가 결제 직전까지 준비했습니다. "결제하러 가기"를 누르면 그 화면이 그대로 열리고, '
                  '결제하기·결제 비밀번호·카드 인증은 직접 하시면 됩니다. 완료되면 자동으로 돌아옵니다.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (r.details != null && r.details!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(AppTokens.rSm),
                  ),
                  child: SelectableText(r.details!),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _feedback,
                decoration: const InputDecoration(
                  hintText: '수정 요청 (선택) — 예: 수량을 2개로 / 더 공손하게',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          widget.agent.resolveApproval(false, feedback: _feedback.text),
                      child: Text(_feedback.text.trim().isEmpty ? '거절' : '수정 요청'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => widget.agent.resolveApproval(true),
                      child: Text(r.handoff ? '결제하러 가기' : '승인'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuestionCard extends StatefulWidget {
  const _QuestionCard({required this.agent, required this.question});

  final AgentController agent;
  final UserQuestion question;

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  final _answer = TextEditingController();

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    return SafeArea(
      top: false,
      child: Card(
        margin: const EdgeInsets.all(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(q.question, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final c in q.choices)
                    ActionChip(label: Text(c), onPressed: () => widget.agent.answerQuestion(c)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _answer,
                      decoration: const InputDecoration(hintText: '직접 입력', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: const Icon(Icons.send),
                    onPressed: () {
                      final t = _answer.text.trim();
                      if (t.isNotEmpty) widget.agent.answerQuestion(t);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewChatHint extends StatelessWidget {
  const _NewChatHint({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('무엇을 해드릴까요?', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          '할 일을 적으면 에이전트가 백그라운드에서 처리합니다. 결제·메일 전송은 승인 후에만 해요.',
          style: TextStyle(color: AppTokens.of(context).muted, fontSize: 13.5, height: 1.5),
        ),
        const SizedBox(height: 16),
        Text('예시', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        for (final e in taskExamples)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lightbulb_outline, size: 20),
            title: Text(e),
            onTap: () => onPick(e),
          ),
      ],
    );
  }
}

/// 진행 중인 작업 배너. 탭하면 작업 화면을 연다.
class ActiveTaskBanner extends StatelessWidget {
  const ActiveTaskBanner({super.key, required this.agent});

  final AgentController agent;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final needsYou = agent.pendingApproval != null || agent.pendingQuestion != null;
    return Card(
      color: needsYou ? t.warningBg : t.accentSoft,
      child: ListTile(
        iconColor: needsYou ? t.warningInk : t.accent,
        textColor: needsYou ? t.warningInk : t.accent,
        leading: agent.isBusy && !needsYou
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(needsYou ? Icons.notification_important : Icons.task_alt),
        title: Text(needsYou ? '승인/답변이 필요합니다' : statusLabel(agent.status)),
        subtitle: Text(agent.current.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        onTap: () =>
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TaskScreen())),
      ),
    );
  }
}

String statusLabel(AgentStatus s) => switch (s) {
  AgentStatus.idle => '대기 중',
  AgentStatus.running => '에이전트가 작업 중입니다',
  AgentStatus.waitingApproval => '승인을 기다리는 중',
  AgentStatus.waitingUser => '사용자 입력을 기다리는 중',
  AgentStatus.finished => '작업 완료',
  AgentStatus.failed => '작업 실패',
  AgentStatus.cancelled => '작업 취소됨',
};
