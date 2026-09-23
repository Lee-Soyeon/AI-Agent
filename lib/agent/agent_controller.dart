import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../browser/agent_browser.dart';
import '../browser/session_store.dart';
import '../browser/sites.dart';
import '../core/settings_store.dart';
import '../google/gmail_api.dart';
import '../google/google_auth.dart';
import '../ui/browser_screen.dart';
import 'agent_models.dart';
import 'agent_runner.dart';
import 'prompts.dart';

/// UI 와 에이전트 실행기를 잇는 상태 객체.
class AgentController extends ChangeNotifier implements AgentHooks {
  AgentController({
    required this.settings,
    required this.sessions,
    required this.google,
    required this.navigatorKey,
  });

  final SettingsStore settings;
  final SiteSessionStore sessions;
  final GoogleAuthService google;
  final GlobalKey<NavigatorState> navigatorKey;

  final AgentBrowser _browser = AgentBrowser();
  AgentRunner? _runner;

  AgentStatus status = AgentStatus.idle;
  final List<AgentLogEntry> logs = [];
  Uint8List? lastScreenshot;
  String? lastResult;
  ApprovalRequest? pendingApproval;
  UserQuestion? pendingQuestion;
  String? helpReason;

  bool get isBusy =>
      status == AgentStatus.running ||
      status == AgentStatus.waitingApproval ||
      status == AgentStatus.waitingUser;

  bool get hasConversation => _runner != null;

  /// 새 작업을 시작한다(이전 대화는 버린다).
  Future<void> startTask(String task) async {
    if (isBusy) return;
    logs.clear();
    lastResult = null;
    lastScreenshot = null;
    _runner = AgentRunner(
      llm: settings.createProvider(),
      browser: _browser,
      hooks: this,
      maxSteps: settings.maxSteps,
      gmail: google.isSignedIn ? GmailApi(authHeaders: google.authHeaders) : null,
      gmailAddress: google.email,
      systemPrompt: buildSystemPrompt(
        loginState: {for (final s in allSites) s: sessions.isLoggedIn(s)},
        gmailAccount: google.email,
      ),
    );
    await _run(task);
  }

  /// 같은 대화를 이어서 지시한다 (예: "두 번째 메일에 답장 써줘").
  Future<void> followUp(String message) async {
    if (isBusy || _runner == null) return;
    lastResult = null;
    await _run(message);
  }

  Future<void> _run(String message) async {
    final r = await _runner!.run(message);
    if (r != null) lastResult = r;
    notifyListeners();
  }

  void cancel() {
    _runner?.cancel();
    final a = pendingApproval;
    if (a != null && !a.completer.isCompleted) {
      a.completer.complete(const ApprovalDecision(approved: false, feedback: '사용자가 작업을 취소함'));
    }
    final q = pendingQuestion;
    if (q != null && !q.completer.isCompleted) q.completer.complete('(사용자가 작업을 취소함)');
    pendingApproval = null;
    pendingQuestion = null;
    notifyListeners();
  }

  void resolveApproval(bool approved, {String? feedback}) {
    final a = pendingApproval;
    if (a == null || a.completer.isCompleted) return;
    pendingApproval = null;
    a.completer.complete(ApprovalDecision(approved: approved, feedback: feedback));
    notifyListeners();
  }

  void answerQuestion(String answer) {
    final q = pendingQuestion;
    if (q == null || q.completer.isCompleted) return;
    pendingQuestion = null;
    q.completer.complete(answer);
    notifyListeners();
  }

  // ---- AgentHooks ----

  @override
  void onLog(AgentLogEntry entry) {
    logs.add(entry);
    notifyListeners();
  }

  @override
  void onStatus(AgentStatus s) {
    status = s;
    notifyListeners();
  }

  @override
  void onScreenshot(List<int> jpeg) {
    lastScreenshot = Uint8List.fromList(jpeg);
    notifyListeners();
  }

  @override
  Future<ApprovalDecision> requestApproval(ApprovalRequest request) {
    pendingApproval = request;
    notifyListeners();
    return request.completer.future;
  }

  @override
  Future<String> askUser(UserQuestion question) {
    pendingQuestion = question;
    notifyListeners();
    return question.completer.future;
  }

  @override
  Future<String?> requestUserHelp(String reason, String? url) async {
    helpReason = reason;
    notifyListeners();
    final nav = navigatorKey.currentState;
    String? finalUrl;
    if (nav != null) {
      finalUrl = await nav.push<String>(
        MaterialPageRoute(
          builder: (_) =>
              BrowserScreen(title: '도움이 필요해요', initialUrl: url ?? 'about:blank', message: reason),
        ),
      );
    }
    helpReason = null;
    // 사용자가 도움 화면에서 로그인을 마쳤다면 로그인 상태로 기록한다.
    if (finalUrl != null) {
      for (final s in allSites) {
        if (s.isLoggedInUrl(finalUrl)) await sessions.markLoggedIn(s);
      }
    }
    notifyListeners();
    return finalUrl;
  }

  @override
  void dispose() {
    _browser.dispose();
    super.dispose();
  }
}
