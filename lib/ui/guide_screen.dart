import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../agent/agent_controller.dart';
import '../browser/session_store.dart';
import '../browser/sites.dart';
import '../core/settings_store.dart';
import '../google/google_auth.dart';
import '../openai/chatgpt_auth.dart';
import 'main_shell.dart';
import 'task_screen.dart';

const taskExamples = [
  '쿠팡에서 삼다수 2L 12개 로켓배송 제일 싼 걸 장바구니에 담고, 결제 전에 나한테 승인 받아줘',
  '쿠팡 장바구니에 뭐가 들어있는지 알려줘',
  'Gmail 에서 안 읽은 메일 5개 요약해줘',
  'Gmail 에서 가장 최근 메일에 "확인했습니다, 감사합니다" 라고 답장 써서 승인 받고 보내줘',
  '안 읽은 메일 중 답장이 필요한 것에 평소 내 말투로 답장 초안 써줘',
];

/// 홈 탭: 앱 사용법 안내. 각 단계의 준비 상태를 보여주고 해당 탭으로 보내 준다.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final sessions = context.watch<SiteSessionStore>();
    final google = context.watch<GoogleAuthService>();
    final agent = context.watch<AgentController>();
    context.watch<ChatGptAuth>(); // ChatGPT 로그인 상태가 바뀌면 준비 상태를 갱신
    final tabs = context.read<ShellTabs>();
    final theme = Theme.of(context);

    final loggedIn = settings.runOnServer || google.isSignedIn || allSites.any(sessions.isLoggedIn);

    return Scaffold(
      appBar: AppBar(title: const Text('AI Agent')),
      body: ListView(
        padding: tabListPadding(context),
        children: [
          if (agent.isBusy) ActiveTaskBanner(agent: agent),
          Text('로그인만 하세요.\n나머지는 에이전트가 합니다.', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'OpenAI · Claude · Gemini 중 원하는 모델이 웹사이트와 Gmail 을 대신 조작합니다. '
            '결제와 메일 전송은 반드시 내 승인을 받은 뒤에만 합니다.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          Text('시작하기', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _StepCard(
            step: 1,
            done: settings.isConfigured,
            title: '모델 설정',
            body: settings.isConfigured
                ? (settings.runOnServer
                      ? '서버에서 실행 · ${settings.serverUrl}'
                      : '${settings.vendor.label} · ${settings.model(settings.vendor)}')
                : '모델 탭에서 사용할 LLM 을 고르고 API 키(또는 ChatGPT 로그인)를 입력하세요.',
            tab: AppTab.model,
          ),
          _StepCard(
            step: 2,
            done: loggedIn,
            title: '서비스 로그인',
            body: settings.runOnServer
                ? '로그인 탭에서 서버 브라우저를 열어 쓸 서비스에 한 번만 로그인하세요.'
                : '로그인 탭에서 쿠팡에 로그인하거나 Google 계정을 연결하세요. 로그인은 직접, 나머지는 에이전트가 합니다.',
            tab: AppTab.accounts,
          ),
          _StepCard(
            step: 3,
            done: agent.chats.isNotEmpty,
            title: '채팅으로 작업 맡기기',
            body: '채팅 탭에서 새 채팅을 열고 할 일을 적으세요. 끝난 뒤에도 같은 채팅에서 이어서 지시할 수 있어요.',
            tab: AppTab.chat,
          ),
          const _StepCard(
            step: 4,
            done: null,
            title: '승인하기',
            body: '결제·메일 전송 전에는 승인 카드가 뜹니다. 승인, 거절, 또는 "수량을 2개로" 같은 수정 요청을 할 수 있어요.',
          ),
          const SizedBox(height: 24),
          Text('이렇게 말해 보세요', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          for (final e in taskExamples)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lightbulb_outline, size: 20),
              title: Text(e),
              trailing: const Icon(Icons.north_east, size: 18),
              onTap: () {
                if (agent.isBusy) {
                  tabs.go(AppTab.chat);
                  return;
                }
                openNewChat(context, draft: e);
              },
            ),
          const SizedBox(height: 24),
          Text('알아두면 좋아요', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const _Tip(
            icon: Icons.phone_iphone,
            title: '실행 위치: 이 폰 / 서버',
            body: '이 폰에서 실행하면 앱을 내렸을 때 멈출 수 있어요. 서버에서 실행하면 앱을 꺼도 계속되고, 어떤 웹 서비스든 다룰 수 있어요.',
          ),
          const _Tip(
            icon: Icons.front_hand_outlined,
            title: '도움 요청',
            body: '캡차·인증번호·결제 비밀번호처럼 사람이 해야 하는 일은 브라우저 화면을 띄워 직접 처리하도록 요청해요.',
          ),
          const _Tip(
            icon: Icons.draw_outlined,
            title: '내 말투로 답장',
            body: 'Google 계정을 연결한 뒤 로그인 탭에서 "내 메일 말투"를 학습시키면 내가 쓴 것처럼 답장해요.',
          ),
          const _Tip(
            icon: Icons.lock_outline,
            title: '개인정보',
            body: 'API 키는 기기 보안 저장소에만 저장되고, 사이트 비밀번호는 앱이 저장하지 않아요. 채팅 기록은 이 기기에만 남아요.',
          ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.done,
    required this.title,
    required this.body,
    this.tab,
  });

  final int step;

  /// null 이면 완료 여부를 표시하지 않는다.
  final bool? done;
  final String title;
  final String body;
  final AppTab? tab;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: done == true ? scheme.primary : scheme.surfaceContainerHighest,
          foregroundColor: done == true ? scheme.onPrimary : scheme.onSurfaceVariant,
          child: done == true ? const Icon(Icons.check, size: 20) : Text('$step'),
        ),
        title: Text(title),
        subtitle: Text(body),
        trailing: tab == null ? null : const Icon(Icons.chevron_right),
        onTap: tab == null ? null : () => context.read<ShellTabs>().go(tab!),
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
