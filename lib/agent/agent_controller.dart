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
import '../ui/browser_screen.dart';
import '../ui/remote_browser_screen.dart';
import 'agent_models.dart';
import 'agent_runner.dart';
import 'chat_session.dart';
import 'prompts.dart';

/// UI 와 에이전트 실행기를 잇는 상태 객체.
class AgentController extends ChangeNotifier with WidgetsBindingObserver implements AgentHooks {
  AgentController({
    required this.settings,
    required this.sessions,
    required this.google,
    required this.writingStyle,
    required this.navigatorKey,
    ChatSessionStore? history,
  }) : history = history ?? ChatSessionStore.memory() {
    WidgetsBinding.instance.addObserver(this);
  }

  final SettingsStore settings;
  final SiteSessionStore sessions;
  final GoogleAuthService google;
  final WritingStyleStore writingStyle;
  final GlobalKey<NavigatorState> navigatorKey;

  /// 지난 대화 목록. 끝난 대화도 남겨 두었다가 다시 열어 이어서 지시할 수 있다.
  final ChatSessionStore history;

  final AgentBrowser _browser = AgentBrowser();
  AgentRunner? _runner;

  /// 지금 화면에 열려 있는 대화. 에이전트는 이 대화에서만 실행된다.
  ChatSession? current;

  AgentStatus status = AgentStatus.idle;
  Uint8List? lastScreenshot;
  String? lastResult;
  ApprovalRequest? pendingApproval;
  UserQuestion? pendingQuestion;
  String? helpReason;

  bool get isBusy =>
      status == AgentStatus.running ||
      status == AgentStatus.waitingApproval ||
      status == AgentStatus.waitingUser;

  List<AgentLogEntry> get logs => current?.logs ?? const [];

  /// 이어서 지시할 수 있는지. 서버 대화는 서버에 기록이 남아 있어야 한다.
  bool get hasConversation {
    final s = current;
    if (s == null) return false;
    return !s.isRemote || _remoteTaskId != null;
  }

  // ---- 서버 모드 (server/) ----
  AgentServerClient? _server;
  String? _remoteTaskId;
  int _remoteShotVersion = 0;
  Timer? _poll;
  bool _polling = false;
  bool _helpOpen = false;
  String? _lastPollError;

  bool get isRemote => _remoteTaskId != null;

  /// 새 대화로 작업을 시작한다. 이전 대화는 목록에 남는다.
  Future<void> startTask(String task) async {
    if (isBusy) return;
    _stopRemote();
    _runner = null;
    final s = ChatSession.create(task, vendor: settings.runOnServer ? null : settings.vendor.name);
    _select(s);
    history.add(s);
    if (settings.runOnServer) return _startRemote(task);
    _runner = _newRunner(s);
    await _run(task);
  }

  AgentRunner _newRunner(ChatSession s) {
    // 다른 LLM 공급자로 이어가면, 이전 공급자 형식의 원본 응답은 보낼 수 없으므로 버린다.
    if (s.vendor != settings.vendor.name) {
      for (var i = 0; i < s.messages.length; i++) {
        s.messages[i] = s.messages[i].withoutProviderRaw();
      }
      s.vendor = settings.vendor.name;
    }
    return AgentRunner(
      llm: settings.createProvider(),
      browser: _browser,
      hooks: this,
      maxSteps: settings.maxSteps,
      gmail: google.isSignedIn ? GmailApi(authHeaders: google.authHeaders) : null,
      gmailAddress: google.email,
      history: s.messages,
      systemPrompt: buildSystemPrompt(
        loginState: {for (final s in allSites) s: sessions.isLoggedIn(s)},
        gmailAccount: google.email,
        styleGuide: writingStyle.profile?.guide,
      ),
    );
  }

  /// 지난 대화를 연다. 다른 대화에서 작업이 진행 중이면 열지 못하고 false 를 돌려준다.
  Future<bool> openSession(String id) async {
    final s = history.byId(id);
    if (s == null) return false;
    if (current?.id == id) return true;
    if (isBusy) return false;
    _stopRemote();
    _runner = null;
    _select(s);
    notifyListeners();
    lastScreenshot = await history.loadScreenshot(s);
    if (current != s) return true; // 읽는 사이에 다른 대화로 바뀜
    final client = settings.serverClient;
    if (s.isRemote && client != null) {
      // 앱에 받아 둔 로그 다음부터 서버에서 이어 받는다 (그 사이 서버에서 진행된 내용 포함).
      _server = client;
      _remoteTaskId = s.remoteTaskId;
      _remoteShotVersion = 0;
      _startPolling();
      await _refreshRemote();
    }
    notifyListeners();
    return true;
  }

  /// 열린 대화를 닫고 새 대화를 준비한다 (목록에는 남는다).
  void closeSession() {
    if (isBusy) return;
    _stopRemote();
    _runner = null;
    _select(null);
    notifyListeners();
  }

  /// 대화를 목록에서 지운다. 진행 중인 대화는 지울 수 없다.
  Future<bool> deleteSession(String id) async {
    final s = history.byId(id);
    if (s == null) return true;
    if (current?.id == id) {
      if (isBusy) return false;
      closeSession();
    }
    final taskId = s.remoteTaskId;
    final client = settings.serverClient;
    if (taskId != null && client != null) {
      unawaited(client.deleteTask(taskId).catchError((_) {})); // 서버 기록도 지운다 (실패해도 무시)
    }
    await history.delete(id);
    notifyListeners();
    return true;
  }

  void _select(ChatSession? s) {
    current = s;
    status = s?.status ?? AgentStatus.idle;
    lastResult = s?.lastResult;
    lastScreenshot = s?.screenshot;
    pendingApproval = null;
    pendingQuestion = null;
    _lastPollError = null;
  }

  void _log(AgentLogEntry entry) {
    final s = current;
    if (s == null) return;
    s.logs.add(entry);
    history.save(s);
    notifyListeners();
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
    final s = current;
    if (isBusy || s == null) return;
    lastResult = null;
    if (s.isRemote) {
      if (!isRemote) return;
      await _remoteCall(() => _server!.followUp(_remoteTaskId!, message));
      status = AgentStatus.running;
      _startPolling();
      return;
    }
    if (_runner == null) {
      // 앱을 다시 켠 뒤 지난 대화를 이어가는 경우: 저장된 LLM 대화로 실행기를 다시 만든다.
      if (!settings.isLocalLlmConfigured) {
        _log(AgentLogEntry(LogKind.error, '이어서 지시하려면 설정에서 LLM 을 먼저 설정하세요.'));
        return;
      }
      _runner = _newRunner(s);
    }
    await _run(message);
  }

  Future<void> _run(String message) async {
    final s = current;
    final r = await _runner!.run(message);
    if (r != null) {
      lastResult = r;
      if (s != null) {
        s.lastResult = r;
        history.save(s);
      }
    }
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
  void onLog(AgentLogEntry entry) => _log(entry);

  @override
  void onStatus(AgentStatus s) {
    status = s;
    final c = current;
    if (c != null) {
      c.status = s;
      history.save(c, touch: false);
    }
    notifyListeners();
  }

  @override
  void onScreenshot(List<int> jpeg) {
    lastScreenshot = Uint8List.fromList(jpeg);
    final c = current;
    if (c != null) {
      c.screenshot = lastScreenshot;
      c.screenshotDirty = true;
      history.save(c, touch: false);
    }
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

  // ---- 서버 모드 구현 ----

  Future<void> _startRemote(String prompt) async {
    final client = settings.serverClient;
    if (client == null) return;
    _server = client;
    onStatus(AgentStatus.running);
    _log(AgentLogEntry(LogKind.user, prompt));
    try {
      final t = await client.createTask(prompt);
      _adopt(t);
    } catch (e) {
      _log(AgentLogEntry(LogKind.error, '서버에 작업을 보내지 못했습니다: $e'));
      onStatus(AgentStatus.failed);
    }
  }

  /// 앱을 켜거나 다시 열었을 때, 서버에서 진행 중인 작업이 있으면 그 대화를 열어 이어서 보여준다.
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
        return;
      }
      if (isBusy) return;
      var s = history.byRemoteTaskId(t.id);
      // 이미 목록에 있는 끝난 대화라면, 사용자가 보던 대화를 바꾸지 않는다.
      if (s != null && !t.isBusy) return;
      if (s == null) {
        s = ChatSession.create(t.prompt, remoteTaskId: t.id);
        history.add(s);
      }
      _stopRemote();
      _runner = null;
      _select(s);
      _server = client;
      _remoteTaskId = t.id;
      _remoteShotVersion = 0;
      _startPolling();
      await _refreshRemote();
    } catch (_) {
      // 서버에 닿지 않으면 조용히 넘어간다 (설정 화면의 연결 테스트로 확인)
    }
  }

  /// 방금 만든 서버 작업을 현재 대화에 연결한다. 로그는 서버에서 처음부터 받는다.
  void _adopt(RemoteTask t) {
    final s = current!;
    _runner = null;
    s.remoteTaskId = t.id;
    s.remoteLogCount = 0;
    s.logs.clear();
    history.save(s);
    _remoteTaskId = t.id;
    _remoteShotVersion = 0;
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
    final s = current;
    if (client == null || id == null || s == null || _polling) return;
    _polling = true;
    try {
      final t = await client.task(id, since: s.remoteLogCount);
      if (current != s) return; // 기다리는 사이 다른 대화로 바뀜
      _lastPollError = null;
      for (final l in t.logs) {
        final kind = LogKind.values.asNameMap()[l['kind']] ?? LogKind.observation;
        s.logs.add(
          AgentLogEntry(
            kind,
            '${l['text'] ?? ''}',
            detail: l['detail'] as String?,
            time: DateTime.tryParse('${l['time']}'),
          ),
        );
      }
      final before = s.status;
      final hadNew = t.logs.isNotEmpty;
      s.remoteLogCount = t.logCount;
      status = switch (t.status) {
        'waiting_approval' => AgentStatus.waitingApproval,
        'waiting_user' => AgentStatus.waitingUser,
        'finished' => AgentStatus.finished,
        'failed' => AgentStatus.failed,
        'cancelled' => AgentStatus.cancelled,
        _ => AgentStatus.running,
      };
      if (t.result != null) lastResult = t.result;
      s.status = status;
      s.lastResult = lastResult;
      _applyPending(t.pending);
      if (t.screenshotVersion != _remoteShotVersion) {
        _remoteShotVersion = t.screenshotVersion;
        final shot = await client.screenshot(id);
        if (shot != null) {
          lastScreenshot = s.screenshot = shot;
          s.screenshotDirty = true;
        }
      }
      if (hadNew || before != s.status || s.screenshotDirty) history.save(s, touch: hadNew);
      if (!isBusy) _poll?.cancel(); // 끝난 작업은 더 묻지 않는다 (후속 지시 때 다시 시작)
    } on AgentServerException catch (e) {
      if (e.statusCode == 404 && current == s) {
        // 서버가 초기화되어 기록이 없어졌다. 앱에 받아 둔 기록만 보여준다.
        _poll?.cancel();
        _remoteTaskId = null;
        pendingApproval = null;
        pendingQuestion = null;
        if (isBusy) onStatus(AgentStatus.failed);
        _log(AgentLogEntry(LogKind.error, '서버에 이 대화 기록이 없어 이어서 지시할 수 없습니다. 새 작업으로 시작하세요.'));
      } else {
        _pollError(e);
      }
    } catch (e) {
      _pollError(e);
    } finally {
      _polling = false;
      notifyListeners();
    }
  }

  void _pollError(Object e) {
    final msg = '서버 연결 문제: $e';
    if (msg != _lastPollError) _log(AgentLogEntry(LogKind.error, msg));
    _lastPollError = msg;
  }

  void _applyPending(Map<String, dynamic>? p) {
    final type = p?['type'];
    if (type == 'approval') {
      final title = '${p!['title'] ?? '승인 요청'}';
      if (pendingApproval?.title != title || pendingApproval?.summary != p['summary']) {
        pendingApproval = ApprovalRequest(
          kind: ApprovalKind.parse(p['kind']),
          title: title,
          summary: '${p['summary'] ?? ''}',
          details: p['details'] as String?,
        );
      }
    } else {
      pendingApproval = null;
    }
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

  Future<void> _remoteCall(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      _log(AgentLogEntry(LogKind.error, '서버 요청 실패: $e'));
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
      history.flush(); // 앱이 종료되어도 대화가 남도록 바로 저장한다
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
