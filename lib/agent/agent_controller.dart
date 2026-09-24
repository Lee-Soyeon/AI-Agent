import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // ---- 채팅 세션 ----
  static const _sessionsKey = 'chat_sessions';
  static const _maxSavedSessions = 50;

  /// 시작한 대화 목록 (최근 것이 앞). 아직 아무것도 시키지 않은 새 채팅은 들어가지 않는다.
  final List<ChatSession> chats = [];
  ChatSession _current = ChatSession(id: _newId());
  Timer? _saveTimer;

  /// 지금 화면에 보이는(작업 중인) 대화.
  ChatSession get current => _current;

  List<AgentLogEntry> get logs => _current.logs;
  AgentStatus get status => _current.status;
  set status(AgentStatus s) => _current.status = s;
  String? get lastResult => _current.lastResult;
  set lastResult(String? r) => _current.lastResult = r;
  AgentRunner? get _runner => _current.runner;
  set _runner(AgentRunner? r) => _current.runner = r;

  Uint8List? lastScreenshot;
  ApprovalRequest? pendingApproval;
  UserQuestion? pendingQuestion;
  String? helpReason;

  bool get isBusy =>
      status == AgentStatus.running ||
      status == AgentStatus.waitingApproval ||
      status == AgentStatus.waitingUser;

  bool get hasConversation => _current.canContinue;

  // ---- 서버 모드 (server/) ----
  AgentServerClient? _server;
  String? get _remoteTaskId => _current.remoteTaskId;
  int _remoteShotVersion = 0;
  Timer? _poll;
  bool _polling = false;
  bool _helpOpen = false;
  String? _lastPollError;

  bool get isRemote => _remoteTaskId != null;

  static String _newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  /// 저장해 둔 대화 목록을 불러온 뒤, 서버에서 진행 중인 작업이 있으면 붙는다.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_sessionsKey);
      if (raw != null) {
        chats
          ..clear()
          ..addAll([
            for (final j in jsonDecode(raw) as List)
              ChatSession.fromJson((j as Map).cast<String, dynamic>()),
          ]);
      }
    } catch (_) {
      // 저장본이 깨졌으면 빈 목록으로 시작한다.
    }
    notifyListeners();
    await attachToServer();
  }

  /// 새 채팅을 연다 (진행 중인 작업이 있으면 열 수 없다).
  void newSession() {
    if (isBusy || _current.isEmpty) return;
    _switchTo(ChatSession(id: _newId()));
  }

  /// 목록에서 고른 대화를 연다. 서버 작업이면 서버에서 최신 상태를 받아 온다.
  void openSession(String id) {
    if (id == _current.id) return;
    if (isBusy) return;
    final s = chats.where((e) => e.id == id).firstOrNull;
    if (s == null) return;
    _switchTo(s);
    if (s.remoteTaskId != null) {
      _server = settings.serverClient;
      if (_server != null) _refreshRemote();
    }
  }

  void deleteSession(String id) {
    if (id == _current.id && isBusy) return;
    chats.removeWhere((e) => e.id == id);
    if (id == _current.id) _switchTo(ChatSession(id: _newId()));
    _scheduleSave();
    notifyListeners();
  }

  void _switchTo(ChatSession s) {
    _stopRemote();
    _current = s;
    lastScreenshot = null;
    pendingApproval = null;
    pendingQuestion = null;
    _remoteShotVersion = 0;
    _lastPollError = null;
    notifyListeners();
  }

  /// 현재 대화를 목록 맨 위로 올리고 저장을 예약한다.
  void _touch([ChatSession? session]) {
    final s = session ?? _current;
    s.updatedAt = DateTime.now();
    chats.remove(s);
    chats.insert(0, s);
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _save);
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _sessionsKey,
        jsonEncode([for (final s in chats.take(_maxSavedSessions)) s.toJson()]),
      );
    } catch (_) {
      // 저장 실패는 다음 변경 때 다시 시도된다.
    }
  }

  /// 새 작업을 시작한다. 현재 대화에 이미 기록이 있으면 새 채팅으로 시작한다.
  Future<void> startTask(String task) async {
    if (isBusy) return;
    if (!_current.isEmpty) _switchTo(ChatSession(id: _newId()));
    _current.title = ChatSession.titleFrom(task);
    _touch();
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
    final session = _current;
    final r = await session.runner!.run(message);
    if (r != null) session.lastResult = r;
    _touch(session);
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
  void onLog(AgentLogEntry entry) {
    logs.add(entry);
    _scheduleSave();
    notifyListeners();
  }

  @override
  void onStatus(AgentStatus s) {
    status = s;
    _touch();
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
      _adopt(t);
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
        return;
      }
      if (isBusy) return;
      final known = chats.where((s) => s.remoteTaskId == t.id).firstOrNull;
      final active = const {'running', 'waiting_approval', 'waiting_user'}.contains(t.status);
      if (known != null) {
        // 이미 목록에 있는 작업: 아직 진행 중일 때만 그 대화로 넘어간다.
        if (!active) return;
        _switchTo(known);
        _server = client;
        _startPolling();
        await _refreshRemote();
        return;
      }
      // 다른 곳에서 시작한 서버 작업: 새 대화로 목록에 추가한다.
      _switchTo(ChatSession(id: _newId(), title: _remoteTitle));
      _server = client;
      _touch();
      _adopt(t);
    } catch (_) {
      // 서버에 닿지 않으면 조용히 넘어간다 (설정 화면의 연결 테스트로 확인)
    }
  }

  static const _remoteTitle = '서버 작업';

  void _adopt(RemoteTask t) {
    _runner = null;
    _current.remoteTaskId = t.id;
    _current.remoteLogCount = 0;
    _remoteShotVersion = 0;
    logs.clear();
    _startPolling();
    _refreshRemote();
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 1500), (_) => _refreshRemote());
  }

  /// 폴링만 멈춘다. 서버 작업 id 는 대화(ChatSession)에 남아 나중에 이어서 볼 수 있다.
  void _stopRemote() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> _refreshRemote() async {
    final client = _server;
    final session = _current;
    final id = session.remoteTaskId;
    if (client == null || id == null || _polling) return;
    _polling = true;
    try {
      final t = await client.task(id, since: session.remoteLogCount);
      // 기다리는 사이 다른 대화로 넘어갔으면 버린다 (그 대화를 다시 열 때 받아 온다).
      if (!identical(session, _current)) return;
      _lastPollError = null;
      for (final l in t.logs) {
        final kind = LogKind.values.asNameMap()[l['kind']] ?? LogKind.observation;
        final text = '${l['text'] ?? ''}';
        logs.add(AgentLogEntry(kind, text, detail: l['detail'] as String?));
        if (kind == LogKind.user && session.title == _remoteTitle) {
          session.title = ChatSession.titleFrom(text);
        }
      }
      final changed = t.logs.isNotEmpty || session.remoteLogCount != t.logCount;
      session.remoteLogCount = t.logCount;
      final before = status;
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
      if (changed || status != before) _touch(session);
      if (!isBusy) _poll?.cancel(); // 끝난 작업은 더 묻지 않는다 (후속 지시 때 다시 시작)
    } catch (e) {
      if (!identical(session, _current)) return;
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
    _saveTimer?.cancel();
    _browser.dispose();
    super.dispose();
  }
}
