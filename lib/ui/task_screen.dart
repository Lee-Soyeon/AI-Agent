import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:provider/provider.dart';

import '../agent/agent_controller.dart';
import '../agent/agent_models.dart';
import 'app_theme.dart';
import 'browser_pip.dart';
import 'home_screen.dart' show statusLabel;

class TaskScreen extends StatefulWidget {
  const TaskScreen({super.key});

  @override
  State<TaskScreen> createState() => _TaskScreenState();
}

class _TaskScreenState extends State<TaskScreen> {
  final _followUp = TextEditingController();
  final _scroll = ScrollController();
  int _lastLogCount = 0;
  bool _userScrolling = false; // 로그를 직접 넘기는 동안 미니 화면을 흐리게

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

    return Scaffold(
      appBar: AppBar(
        title: Text(statusLabel(agent.status)),
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
            child: Stack(
              children: [
                NotificationListener<UserScrollNotification>(
                  onNotification: (n) {
                    final scrolling = n.direction != ScrollDirection.idle;
                    if (scrolling != _userScrolling) setState(() => _userScrolling = scrolling);
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
          if (!agent.isBusy && agent.hasConversation)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _followUp,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: '이어서 지시하기 (예: 두 번째 메일에 답장 써줘)',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      icon: const Icon(Icons.send),
                      onPressed: () {
                        final t = _followUp.text.trim();
                        if (t.isEmpty) return;
                        _followUp.clear();
                        agent.followUp(t);
                      },
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
                  Icon(
                    r.kind == ApprovalKind.purchase
                        ? Icons.payments
                        : r.kind == ApprovalKind.sendEmail
                        ? Icons.outgoing_mail
                        : Icons.warning_amber,
                    color: AppTokens.of(context).warningInk,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(r.title, style: Theme.of(context).textTheme.titleMedium)),
                  Chip(label: Text(r.kind.label)),
                ],
              ),
              const SizedBox(height: 8),
              SelectableText(r.summary),
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
                      child: const Text('승인'),
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
                      decoration: const InputDecoration(
                        hintText: '직접 입력',
                        isDense: true,
                      ),
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
