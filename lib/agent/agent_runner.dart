import 'dart:async';

import '../browser/agent_browser.dart';
import '../google/gmail_api.dart';
import '../google/writing_style.dart';
import '../llm/llm_types.dart';
import 'agent_models.dart';
import 'agent_tools.dart';
import 'safety.dart';

class _Outcome {
  const _Outcome(this.content, {this.finishSummary});
  final String content;
  final String? finishSummary;
}

/// LLM ↔ 브라우저 도구 호출 루프.
class AgentRunner {
  AgentRunner({
    required this.llm,
    required this.browser,
    required this.hooks,
    required this.systemPrompt,
    this.maxSteps = 60,
    this.gmail,
    this.gmailAddress,
    SafetyPolicy? safety,
  }) : safety = safety ?? SafetyPolicy();

  final LlmProvider llm;
  final BrowserDriver browser;
  final AgentHooks hooks;
  final String systemPrompt;
  final int maxSteps;
  final SafetyPolicy safety;

  /// Google 계정이 연결되지 않았으면 null.
  final GmailApi? gmail;
  final String? gmailAddress;

  /// 이번 대화에서 말투 예시를 확인했는지. 확인 전에는 gmail_send 를 막는다.
  bool _styleChecked = false;

  final List<ChatMessage> messages = [];
  bool _cancelled = false;

  static const snapshotHeader = '=== 페이지 스냅샷 ===';

  /// 오래된 페이지 스냅샷은 토큰을 많이 쓰므로 최근 [keepSnapshots] 개만 남긴다.
  static const keepSnapshots = 2;

  void cancel() => _cancelled = true;

  /// [userMessage] 를 대화에 추가하고 작업이 끝날 때까지 실행한다. 같은 runner 로 이어서 지시할 수 있다.
  Future<String?> run(String userMessage) async {
    _cancelled = false;
    messages.add(ChatMessage.user(userMessage));
    hooks.onLog(AgentLogEntry(LogKind.user, userMessage));
    hooks.onStatus(AgentStatus.running);

    for (var step = 0; step < maxSteps; step++) {
      if (_cancelled) return _stopCancelled();
      compactHistory(messages);

      final LlmResponse res;
      try {
        res = await _completeWithRetry();
      } catch (e) {
        hooks.onLog(AgentLogEntry(LogKind.error, 'LLM 호출 실패: $e'));
        hooks.onStatus(AgentStatus.failed);
        return null;
      }
      if (_cancelled) return _stopCancelled();
      messages.add(res.toMessage());

      final thought = res.text?.trim() ?? '';
      if (res.toolCalls.isEmpty) {
        final answer = thought.isEmpty ? '(응답 없음)' : thought;
        hooks.onLog(AgentLogEntry(LogKind.result, answer));
        hooks.onStatus(AgentStatus.finished);
        return answer;
      }
      if (thought.isNotEmpty) hooks.onLog(AgentLogEntry(LogKind.thought, thought));

      String? finishSummary;
      for (final call in res.toolCalls) {
        // 모든 tool call 에는 반드시 결과를 붙여야 다음 요청이 유효하다.
        final _Outcome out;
        if (_cancelled) {
          out = const _Outcome('사용자가 작업을 취소했습니다.');
        } else {
          out = await _execute(call);
        }
        messages.add(
          ChatMessage.toolResult(toolCallId: call.id, toolName: call.name, content: out.content),
        );
        finishSummary ??= out.finishSummary;
      }
      if (finishSummary != null) {
        hooks.onLog(AgentLogEntry(LogKind.result, finishSummary));
        hooks.onStatus(AgentStatus.finished);
        return finishSummary;
      }
    }
    hooks.onLog(AgentLogEntry(LogKind.error, '최대 단계($maxSteps)에 도달해 멈췄습니다. 이어서 지시할 수 있습니다.'));
    hooks.onStatus(AgentStatus.failed);
    return null;
  }

  String? _stopCancelled() {
    safety.revoke();
    hooks.onLog(AgentLogEntry(LogKind.error, '작업이 취소되었습니다.'));
    hooks.onStatus(AgentStatus.cancelled);
    return null;
  }

  Future<LlmResponse> _completeWithRetry() async {
    var delay = const Duration(seconds: 2);
    for (var attempt = 0; ; attempt++) {
      try {
        return await llm.complete(
          system: systemPrompt,
          messages: messages,
          tools: AgentTools.specs,
        );
      } on LlmException catch (e) {
        final retryable = e.statusCode == 429 || (e.statusCode ?? 0) >= 500;
        if (!retryable || attempt >= 3) rethrow;
      } on TimeoutException {
        if (attempt >= 3) rethrow;
      }
      await Future<void>.delayed(delay);
      delay *= 2;
    }
  }

  /// 최근 [keepSnapshots] 개를 제외한 페이지 스냅샷을 URL 한 줄로 줄인다.
  static void compactHistory(List<ChatMessage> messages) {
    var seen = 0;
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      final text = m.text;
      if (m.role != ChatRole.tool || text == null) continue;
      final idx = text.indexOf(snapshotHeader);
      if (idx < 0) continue;
      seen++;
      if (seen <= keepSnapshots) continue;
      final urlLine = RegExp(r'URL: (.*)').firstMatch(text.substring(idx))?.group(1) ?? '';
      messages[i] = m.withText('${text.substring(0, idx)}[이전 페이지 스냅샷 생략됨 — $urlLine]');
    }
  }

  Future<_Outcome> _execute(ToolCall call) async {
    final a = call.arguments;
    hooks.onLog(AgentLogEntry(LogKind.action, _describeCall(call)));
    try {
      switch (call.name) {
        case AgentTools.openUrl:
          await browser.navigate('${a['url'] ?? ''}');
          return await _observe('페이지를 열었습니다.');

        case AgentTools.readPage:
          return await _observe('현재 페이지입니다.');

        case AgentTools.click:
          final id = asInt(a['element_id']);
          if (id == null) return _error('element_id 가 필요합니다.');
          final d = await browser.describe(id);
          if (d['ok'] != true) return _error('id $id 요소를 찾을 수 없습니다. read_page 로 최신 id 를 확인하세요.');
          final label = '${d['label'] ?? ''}';
          if (safety.isSensitive(label)) {
            if (!safety.consumeGrant()) {
              hooks.onLog(AgentLogEntry(LogKind.approval, '승인 없이 "$label" 클릭 시도 → 차단'));
              return _error(
                '차단됨: "$label" 은(는) 결제/전송 등 되돌릴 수 없는 동작입니다. '
                '먼저 request_approval 로 전체 내용을 보여주고 사용자 승인을 받으세요.',
              );
            }
            hooks.onLog(AgentLogEntry(LogKind.approval, '승인된 동작 실행: "$label"'));
          }
          final r = await browser.click(id);
          if (r['ok'] != true) return _error('${r['error'] ?? '클릭 실패'}');
          return await _observe('"$label" 을(를) 클릭했습니다.');

        case AgentTools.typeText:
          final id = asInt(a['element_id']);
          if (id == null) return _error('element_id 가 필요합니다.');
          final text = '${a['text'] ?? ''}';
          final submit = a['submit'] == true;
          final d = await browser.describe(id);
          if (d['ok'] != true) return _error('id $id 요소를 찾을 수 없습니다. read_page 로 최신 id 를 확인하세요.');
          if (d['type'] == 'password') {
            return _error('비밀번호 입력창에는 입력할 수 없습니다. request_user_help 로 사용자에게 로그인을 요청하세요.');
          }
          if (submit &&
              safety.isSensitive('${d['formSubmitLabels'] ?? ''}') &&
              !safety.consumeGrant()) {
            return _error('차단됨: 이 입력창에서 Enter 를 누르면 전송/결제될 수 있습니다. submit 없이 입력하거나 먼저 승인을 받으세요.');
          }
          final r = await browser.typeText(id, text, submit: submit);
          if (r['ok'] != true) {
            return _error(
              r['error'] == 'password'
                  ? '비밀번호 입력창에는 입력할 수 없습니다. request_user_help 를 사용하세요.'
                  : '${r['error'] ?? '입력 실패'}',
            );
          }
          return await _observe('입력했습니다${submit ? ' (Enter)' : ''}.');

        case AgentTools.scroll:
          await browser.scroll('${a['direction'] ?? 'down'}');
          return await _observe('스크롤했습니다.');

        case AgentTools.goBack:
          await browser.goBack();
          return await _observe('뒤로 갔습니다.');

        case AgentTools.requestApproval:
          final req = ApprovalRequest(
            kind: ApprovalKind.parse(a['kind']),
            title: '${a['title'] ?? '승인 요청'}',
            summary: '${a['summary'] ?? ''}',
            details: a['details']?.toString(),
          );
          hooks.onStatus(AgentStatus.waitingApproval);
          final decision = await hooks.requestApproval(req);
          hooks.onStatus(AgentStatus.running);
          if (decision.approved) {
            safety.grant(req.kind.name, req.summary);
            hooks.onLog(AgentLogEntry(LogKind.approval, '✅ 사용자가 승인했습니다: ${req.title}'));
            return const _Outcome(
              '승인됨. 이제 해당 버튼(결제하기/보내기 등)을 10분 안에 한 번 누를 수 있습니다. '
              '승인받은 내용과 다르게 진행하지 마세요.',
            );
          }
          safety.revoke();
          final fb = decision.feedback?.trim() ?? '';
          hooks.onLog(AgentLogEntry(LogKind.approval, '❌ 사용자가 거절했습니다${fb.isEmpty ? '' : ': $fb'}'));
          return _Outcome(
            fb.isEmpty
                ? '거절됨. 해당 동작을 하지 말고, 지금까지의 상황을 finish 로 보고하세요.'
                : '거절됨. 사용자 의견: "$fb". 의견을 반영해 수정한 뒤 다시 request_approval 하세요.',
          );

        case AgentTools.askUser:
          final q = UserQuestion(
            '${a['question'] ?? ''}',
            choices: [for (final c in (a['choices'] as List? ?? const [])) '$c'],
          );
          hooks.onStatus(AgentStatus.waitingUser);
          final answer = await hooks.askUser(q);
          hooks.onStatus(AgentStatus.running);
          hooks.onLog(AgentLogEntry(LogKind.user, answer));
          return _Outcome('사용자 답변: $answer');

        case AgentTools.requestUserHelp:
          final reason = '${a['reason'] ?? '직접 처리해 주세요.'}';
          final before = await browser.currentUrl();
          hooks.onStatus(AgentStatus.waitingUser);
          final after = await hooks.requestUserHelp(reason, before);
          hooks.onStatus(AgentStatus.running);
          final target = (after != null && after.startsWith('http')) ? after : before;
          if (target != null && target.startsWith('http')) await browser.navigate(target);
          return await _observe('사용자가 직접 처리를 마쳤습니다. 페이지를 다시 확인하세요.');

        case AgentTools.gmailSearch:
          final api = gmail;
          if (api == null) return _gmailNotConnected();
          final q = '${a['query'] ?? ''}';
          final found = await api.search(q, maxResults: asInt(a['max_results']) ?? 10);
          hooks.onLog(
            AgentLogEntry(
              LogKind.observation,
              '메일 ${found.length}통 찾음',
              detail: found.map((m) => m.toPrompt()).join('\n'),
            ),
          );
          return _Outcome(
            found.isEmpty
                ? '검색 결과가 없습니다. (검색어: $q)'
                : '검색 결과 ${found.length}통:\n${found.map((m) => m.toPrompt()).join('\n')}',
          );

        case AgentTools.gmailRead:
          final api = gmail;
          if (api == null) return _gmailNotConnected();
          final msg = await api.read('${a['message_id'] ?? ''}');
          final text = msg.toPrompt();
          hooks.onLog(
            AgentLogEntry(LogKind.observation, '메일 읽음: ${msg.header('subject')}', detail: text),
          );
          return _Outcome(text);

        case AgentTools.gmailStyleExamples:
          final api = gmail;
          if (api == null) return _gmailNotConnected();
          final recipient = '${a['recipient'] ?? ''}'.trim();
          final extra = '${a['query'] ?? ''}'.trim();
          var samples = await fetchSentSamples(
            api,
            max: 3,
            query: [if (recipient.isNotEmpty) 'to:$recipient', extra].join(' '),
          );
          var note = recipient.isEmpty ? '최근 보낸 메일' : '$recipient 에게 보냈던 메일';
          if (samples.isEmpty && recipient.isNotEmpty) {
            samples = await fetchSentSamples(api, max: 3, query: extra);
            note = '$recipient 에게 보낸 메일이 없어 최근 보낸 메일로 대신함';
          }
          _styleChecked = true;
          final body = samples.isEmpty
              ? '보낸 메일 예시가 없습니다. 시스템 프롬프트의 말투 가이드(있다면)를 따르세요.'
              : [for (var i = 0; i < samples.length; i++) samples[i].toPrompt(i)].join('\n\n');
          hooks.onLog(
            AgentLogEntry(LogKind.observation, '말투 예시 ${samples.length}통 ($note)', detail: body),
          );
          return _Outcome(
            '## 사용자가 실제로 보낸 메일 — $note\n'
            '인사말·호칭·어미·문단 구성·맺음말·서명을 이 예시와 똑같이 따라 쓰세요.\n\n$body',
          );

        case AgentTools.gmailSend:
          final api = gmail;
          if (api == null) return _gmailNotConnected();
          if (!_styleChecked) {
            _styleChecked = true; // 한 번만 막고, 다음 호출부터는 통과시킨다.
            return _error(
              '먼저 gmail_style_examples 로 사용자가 이 받는 사람에게 보냈던 메일을 확인하고, '
              '그 말투와 형식에 맞춰 본문을 다시 쓴 뒤 gmail_send 를 호출하세요.',
            );
          }
          final email = OutgoingEmail(
            to: _stringList(a['to']),
            cc: _stringList(a['cc']),
            subject: '${a['subject'] ?? ''}',
            body: '${a['body'] ?? ''}',
            replyToMessageId: (a['reply_to_message_id'] as String?)?.trim().isEmpty ?? true
                ? null
                : (a['reply_to_message_id'] as String).trim(),
          );
          final invalid = [...email.to, ...email.cc].where((e) => !_emailRe.hasMatch(e)).toList();
          if (email.to.isEmpty) return _error('받는 사람(to)이 없습니다.');
          if (invalid.isNotEmpty) return _error('올바르지 않은 이메일 주소: ${invalid.join(', ')}');

          // 승인 카드에 보여준 내용 그대로만 전송한다.
          final req = ApprovalRequest(
            kind: ApprovalKind.sendEmail,
            title: email.replyToMessageId == null ? '메일 전송 승인' : '답장 전송 승인',
            summary: [
              if (gmailAddress != null) '보내는 사람: $gmailAddress',
              '받는 사람: ${email.to.join(', ')}',
              if (email.cc.isNotEmpty) '참조: ${email.cc.join(', ')}',
              '제목: ${email.subject}',
            ].join('\n'),
            details: email.body,
          );
          hooks.onStatus(AgentStatus.waitingApproval);
          final decision = await hooks.requestApproval(req);
          hooks.onStatus(AgentStatus.running);
          if (!decision.approved) {
            final fb = decision.feedback?.trim() ?? '';
            hooks.onLog(AgentLogEntry(LogKind.approval, '❌ 메일 전송 거절${fb.isEmpty ? '' : ': $fb'}'));
            return _Outcome(
              fb.isEmpty
                  ? '거절됨. 메일을 보내지 않았습니다. 보내지 말고 finish 로 보고하세요.'
                  : '거절됨. 사용자 의견: "$fb". 의견을 반영해 수정한 뒤 gmail_send 를 다시 호출하세요.',
            );
          }
          final sentId = await api.send(email, fromAddress: gmailAddress);
          hooks.onLog(AgentLogEntry(LogKind.approval, '✅ 메일을 보냈습니다: ${email.subject}'));
          return _Outcome('전송 완료 (id: $sentId)');

        case AgentTools.finish:
          final s = '${a['summary'] ?? '완료했습니다.'}';
          return _Outcome('보고 완료', finishSummary: s);

        default:
          return _error('알 수 없는 도구: ${call.name}');
      }
    } on BrowserException catch (e) {
      return _error(e.message);
    } on GmailException catch (e) {
      return _error(e.message);
    } catch (e) {
      return _error('도구 실행 중 오류: $e');
    }
  }

  Future<_Outcome> _observe(String prefix) async {
    final snap = await browser.snapshot();
    final shot = await browser.screenshot();
    if (shot != null) hooks.onScreenshot(shot);
    final body = snap.toPrompt();
    hooks.onLog(
      AgentLogEntry(LogKind.observation, snap.title.isEmpty ? snap.url : snap.title, detail: body),
    );
    return _Outcome('$prefix\n\n$snapshotHeader\n$body');
  }

  static final _emailRe = RegExp(r'^[^@\s<>,;"]+@[^@\s<>,;"]+\.[^@\s<>,;"]+$');

  static List<String> _stringList(Object? v) => switch (v) {
    List() => [for (final e in v) '$e'.trim()].where((e) => e.isNotEmpty).toList(),
    String() => v.split(RegExp(r'[,;]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
    _ => const [],
  };

  _Outcome _gmailNotConnected() => _error(
    'Gmail(Google 계정)이 연결되어 있지 않습니다. '
    '사용자에게 홈 화면에서 "Google 계정 연결"을 눌러 달라고 finish 로 안내하세요.',
  );

  _Outcome _error(String msg) {
    hooks.onLog(AgentLogEntry(LogKind.error, msg));
    return _Outcome('오류: $msg');
  }

  static String _describeCall(ToolCall c) {
    final a = c.arguments;
    return switch (c.name) {
      AgentTools.openUrl => '🌐 열기: ${a['url']}',
      AgentTools.readPage => '👀 페이지 읽기',
      AgentTools.click => '👆 클릭 #${a['element_id']}',
      AgentTools.typeText =>
        '⌨️ 입력 #${a['element_id']}: "${a['text']}"${a['submit'] == true ? ' ⏎' : ''}',
      AgentTools.scroll => '↕️ 스크롤 ${a['direction']}',
      AgentTools.goBack => '⬅️ 뒤로',
      AgentTools.requestApproval => '🙋 승인 요청: ${a['title']}',
      AgentTools.askUser => '❓ 질문: ${a['question']}',
      AgentTools.requestUserHelp => '🧑 사용자 도움 요청: ${a['reason']}',
      AgentTools.finish => '🏁 완료',
      AgentTools.gmailSearch => '📬 메일 검색: ${a['query']}',
      AgentTools.gmailRead => '📖 메일 읽기',
      AgentTools.gmailSend => '✉️ 메일 전송 준비: ${a['subject']}',
      AgentTools.gmailStyleExamples => '🖋️ 내 말투 확인: ${a['recipient'] ?? '최근 메일'}',
      _ => '${c.name} $a',
    };
  }
}
