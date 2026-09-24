import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../browser/agent_browser.dart';
import '../browser/session_store.dart';
import '../browser/sites.dart';
import '../core/settings_store.dart';
import '../google/gmail_api.dart';
import '../google/google_auth.dart';
import '../google/writing_style.dart';
import '../remote/agent_server_client.dart';
import '../services/service_catalog.dart';
import '../ui/browser_screen.dart';
import '../ui/payment_screen.dart';
import '../ui/remote_browser_screen.dart';
import 'agent_models.dart';
import 'agent_runner.dart';
import 'prompts.dart';

/// UI 와 에이전트 실행기를 잇는 상태 객체.
class AgentController extends ChangeNotifier with WidgetsBindingObserver implements AgentHooks {
  AgentController({
    required this.settings,
    required this.sessions,
    required this.google,
    required this.writingStyle,
    required this.navigatorKey,
    this.catalog,
  }) {
    WidgetsBinding.instance.addObserver(this);
  }

  final SettingsStore settings;
  final SiteSessionStore sessions;
  final GoogleAuthService google;
  final WritingStyleStore writingStyle;
  final ServiceCatalog? catalog;
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

  bool get hasConversation => _runner != null || _remoteTaskId != null;

  // ---- 서버 모드 (server/) ----
  AgentServerClient? _server;
  String? _remoteTaskId;
  int _remoteLogCount = 0;
  int _remoteShotVersion = 0;
  Timer? _poll;
  bool _polling = false;
  bool _helpOpen = false;
  bool _paymentOpen = false;
  final ValueNotifier<bool> _paymentClosed = ValueNotifier(false);
  String? _lastPollError;

  bool get isRemote => _remoteTaskId != null;

  /// 새 작업을 시작한다(이전 대화는 버린다).
  Future<void> startTask(String task) async {
    if (isBusy) return;
    logs.clear();
    lastResult = null;
    lastScreenshot = null;
    if (settings.runOnServer) return _startRemote(task);
    _stopRemote();
    _runner = AgentRunner(
      llm: settings.createProvider(),
      browser: _browser,
      hooks: this,
      maxSteps: settings.maxSteps,
      gmail: google.isSignedIn ? GmailApi(authHeaders: google.authHeaders) : null,
      gmailAddress: google.email,
      catalog: catalog,
      systemPrompt: buildSystemPrompt(
        loginState: {for (final s in allSites) s: sessions.isLoggedIn(s)},
        gmailAccount: google.email,
        styleGuide: writingStyle.profile?.guide,
        serviceIndex: catalog?.promptIndex(),
      ),
    );
    await _run(task);
  }

  /// 보낸 메일함을 분석해 말투를 학습한다 (현재 선택된 LLM 사용).
  Future<void> learnWritingStyle() async {
    if (!google.isSignedIn || !settings.isLocalLlmConfigured) return;
    await writingStyle.learn(
      llm: settings.createProvider(),
      gmail: GmailApi(authHeaders: google.authHeaders),
    );
  }

  /// 같은 대화를 이어서 지시한다 (예: "두 번째 메일에 답장 써줘").
  Future<void> followUp(String message) async {
    if (isBusy) return;
    lastResult = null;
    if (isRemote) {
      await _remoteCall(() => _server!.followUp(_remoteTaskId!, message));
      status = AgentStatus.running;
      _startPolling();
      return;
    }
    if (_runner == null) return;
    await _run(message);
  }

  Future<void> _run(String message) async {
    final r = await _runner!.run(message);
    if (r != null) lastResult = r;
    notifyListeners();
  }

  void cancel() {
    if (isRemote) {
      _remoteCall(() => _server!.cancel(_remoteTaskId!));
      pendingApproval = null;
      pendingQuestion = null;
      notifyListeners();
      return;
    }
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
    if (isRemote && (pendingApproval?.handoff ?? false)) {
      pendingApproval = null;
      notifyListeners();
      if (approved) {
        _openRemotePayment();
      } else {
        _remoteCall(() => _server!.payment(_remoteTaskId!, approved: false, feedback: feedback));
      }
      return;
    }
    if (isRemote) {
      pendingApproval = null;
      notifyListeners();
      _remoteCall(() => _server!.approve(_remoteTaskId!, approved, feedback: feedback));
      return;
    }
    final a = pendingApproval;
    if (a == null || a.completer.isCompleted) return;
    pendingApproval = null;
    a.completer.complete(ApprovalDecision(approved: approved, feedback: feedback));
    notifyListeners();
  }

  void answerQuestion(String answer) {
    if (isRemote) {
      pendingQuestion = null;
      notifyListeners();
      _remoteCall(() => _server!.answer(_remoteTaskId!, answer));
      return;
    }
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
  Future<PaymentOutcome> requestPaymentHandoff(ApprovalRequest request) async {
    final decision = await requestApproval(request);
    if (!decision.approved) return PaymentOutcome(approved: false, feedback: decision.feedback);
    final nav = navigatorKey.currentState;
    final url = await _browser.currentUrl();
    if (nav == null) return PaymentOutcome(approved: true, url: url);
    helpReason = request.title;
    notifyListeners();
    // 에이전트의 브라우저를 그대로 화면에 붙인다 → 주문서·결제수단 선택이 유지된다.
    final headless = _browser.takeOverForDisplay();
    final out = await nav.push<PaymentOutcome>(
      MaterialPageRoute(
        builder: (_) => PaymentScreen(request: request, headless: headless, fallbackUrl: url),
      ),
    );
    helpReason = null;
    notifyListeners();
    return out ?? PaymentOutcome(approved: true, url: url);
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

  // ---- 서버 모드 구현 ----

  Future<void> _startRemote(String prompt) async {
    final client = settings.serverClient;
    if (client == null) return;
    _server = client;
    status = AgentStatus.running;
    logs.add(AgentLogEntry(LogKind.user, prompt));
    notifyListeners();
    try {
      final t = await client.createTask(prompt);
      _adopt(t, keepLogs: false);
    } catch (e) {
      logs.add(AgentLogEntry(LogKind.error, '서버에 작업을 보내지 못했습니다: $e'));
      status = AgentStatus.failed;
      notifyListeners();
    }
  }

  /// 앱을 켜거나 다시 열었을 때, 서버에서 진행 중인 작업이 있으면 이어서 보여준다.
  Future<void> attachToServer() async {
    if (!settings.runOnServer) return;
    final client = settings.serverClient;
    if (client == null) return;
    try {
      final t = await client.current();
      if (t == null) return;
      _server = client;
      if (t.id == _remoteTaskId) {
        _startPolling();
      } else if (_runner == null || !isBusy) {
        logs.clear();
        lastResult = null;
        lastScreenshot = null;
        _adopt(t, keepLogs: false);
      }
    } catch (_) {
      // 서버에 닿지 않으면 조용히 넘어간다 (설정 화면의 연결 테스트로 확인)
    }
  }

  void _adopt(RemoteTask t, {required bool keepLogs}) {
    _runner = null;
    _remoteTaskId = t.id;
    _remoteLogCount = 0;
    _remoteShotVersion = 0;
    if (!keepLogs) logs.clear();
    _startPolling();
    _refreshRemote();
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 1500), (_) => _refreshRemote());
  }

  void _stopRemote() {
    _poll?.cancel();
    _poll = null;
    _remoteTaskId = null;
  }

  Future<void> _refreshRemote() async {
    final client = _server;
    final id = _remoteTaskId;
    if (client == null || id == null || _polling) return;
    _polling = true;
    try {
      final t = await client.task(id, since: _remoteLogCount);
      _lastPollError = null;
      for (final l in t.logs) {
        final kind = LogKind.values.asNameMap()[l['kind']] ?? LogKind.observation;
        logs.add(AgentLogEntry(kind, '${l['text'] ?? ''}', detail: l['detail'] as String?));
      }
      _remoteLogCount = t.logCount;
      status = switch (t.status) {
        'waiting_approval' => AgentStatus.waitingApproval,
        'waiting_user' => AgentStatus.waitingUser,
        'finished' => AgentStatus.finished,
        'failed' => AgentStatus.failed,
        'cancelled' => AgentStatus.cancelled,
        _ => AgentStatus.running,
      };
      if (t.result != null) lastResult = t.result;
      _applyPending(t.pending);
      if (t.screenshotVersion != _remoteShotVersion) {
        _remoteShotVersion = t.screenshotVersion;
        lastScreenshot = await client.screenshot(id) ?? lastScreenshot;
      }
      if (!isBusy) _poll?.cancel(); // 끝난 작업은 더 묻지 않는다 (후속 지시 때 다시 시작)
    } catch (e) {
      final msg = '서버 연결 문제: $e';
      if (msg != _lastPollError) logs.add(AgentLogEntry(LogKind.error, msg));
      _lastPollError = msg;
    } finally {
      _polling = false;
      notifyListeners();
    }
  }

  void _applyPending(Map<String, dynamic>? p) {
    final type = p?['type'];
    if (type == 'approval' || (type == 'payment' && !_paymentOpen)) {
      final title = '${p!['title'] ?? '승인 요청'}';
      if (pendingApproval?.title != title || pendingApproval?.summary != p['summary']) {
        pendingApproval = ApprovalRequest(
          kind: type == 'payment' ? ApprovalKind.purchase : ApprovalKind.parse(p['kind']),
          title: title,
          summary: '${p['summary'] ?? ''}',
          details: p['details'] as String?,
          handoff: type == 'payment',
        );
      }
    } else {
      pendingApproval = null;
    }
    // 서버가 결제 완료 페이지를 감지해 스스로 넘어갔다면 열려 있는 결제 화면을 닫는다.
    if (type != 'payment' && _paymentOpen) _paymentClosed.value = true;
    if (type == 'question') {
      final q = '${p!['question'] ?? ''}';
      if (pendingQuestion?.question != q) {
        pendingQuestion = UserQuestion(
          q,
          choices: [for (final c in (p['choices'] as List? ?? const [])) '$c'],
        );
      }
    } else {
      pendingQuestion = null;
    }
    if (type == 'help' && !_helpOpen) _openRemoteHelp('${p!['reason'] ?? '직접 처리해 주세요.'}');
  }

  /// 서버 브라우저 화면을 폰에 띄워 사용자가 직접 처리하게 한 뒤 작업을 이어간다.
  Future<void> _openRemoteHelp(String reason) async {
    final nav = navigatorKey.currentState;
    final client = _server;
    final id = _remoteTaskId;
    if (nav == null || client == null || id == null) return;
    _helpOpen = true;
    helpReason = reason;
    notifyListeners();
    await nav.push<void>(
      MaterialPageRoute(
        builder: (_) => RemoteBrowserScreen(client: client, title: '도움이 필요해요', message: reason),
      ),
    );
    helpReason = null;
    _helpOpen = false;
    await _remoteCall(() => client.helpDone(id));
  }

  /// 서버 모드 결제: 서버 브라우저의 결제 직전 화면을 실시간으로 띄워 사용자가 직접 결제한다.
  Future<void> _openRemotePayment() async {
    final nav = navigatorKey.currentState;
    final client = _server;
    final id = _remoteTaskId;
    if (nav == null || client == null || id == null) return;
    _paymentOpen = true;
    _paymentClosed.value = false;
    final completed = await nav.push<bool>(
      MaterialPageRoute(
        builder: (_) => RemoteBrowserScreen(
          client: client,
          title: '결제',
          message: '결제하기를 누르고 결제 비밀번호·카드 인증을 마치세요. 완료되면 자동으로 닫힙니다.',
          paymentMode: true,
          closeSignal: _paymentClosed,
        ),
      ),
    );
    _paymentOpen = false;
    if (_paymentClosed.value) return; // 서버가 완료를 감지해 이미 넘어감
    await _remoteCall(() => client.payment(id, approved: true, completed: completed ?? false));
  }

  Future<void> _remoteCall(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      logs.add(AgentLogEntry(LogKind.error, '서버 요청 실패: $e'));
      notifyListeners();
    }
    _startPolling();
    await _refreshRemote();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      attachToServer();
    } else if (state == AppLifecycleState.paused) {
      _poll?.cancel(); // 앱이 백그라운드면 폴링을 멈춘다 (작업은 서버에서 계속된다)
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _browser.dispose();
    super.dispose();
  }
}
