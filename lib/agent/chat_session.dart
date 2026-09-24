import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../llm/llm_types.dart';
import 'agent_models.dart';

/// 에이전트와 나눈 대화 하나. 끝나도 버리지 않고 저장해 두었다가 목록에서 다시 열어 이어서 지시한다.
class ChatSession {
  ChatSession({
    required this.id,
    required this.title,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.status = AgentStatus.idle,
    List<AgentLogEntry>? logs,
    List<ChatMessage>? messages,
    this.lastResult,
    this.vendor,
    this.remoteTaskId,
    this.remoteLogCount = 0,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now(),
       logs = logs ?? [],
       messages = messages ?? [];

  factory ChatSession.create(String firstMessage, {String? vendor, String? remoteTaskId}) =>
      ChatSession(
        id: _newId(),
        title: titleFrom(firstMessage),
        vendor: vendor,
        remoteTaskId: remoteTaskId,
      );

  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  AgentStatus status;
  final List<AgentLogEntry> logs;

  /// 기기에서 실행한 대화의 LLM 메시지 기록 (이어서 지시할 때 그대로 이어 붙인다).
  final List<ChatMessage> messages;
  String? lastResult;

  /// 기기에서 실행할 때 쓴 LLM 공급자 (LlmVendor.name).
  String? vendor;

  /// 서버에서 실행한 대화면 서버 작업 ID. 서버가 기록을 갖고 있고, 앱은 로그를 캐시해 둔다.
  String? remoteTaskId;

  /// 서버 로그 중 몇 개를 받아 두었는지.
  int remoteLogCount;

  /// 마지막 브라우저 화면 (별도 파일로 저장).
  Uint8List? screenshot;
  bool screenshotDirty = false;

  bool get isRemote => remoteTaskId != null;

  bool get isBusy =>
      status == AgentStatus.running ||
      status == AgentStatus.waitingApproval ||
      status == AgentStatus.waitingUser;

  /// 목록에 보여줄 한 줄 요약: 결과가 있으면 결과, 없으면 마지막 로그.
  String get preview {
    if (lastResult != null && lastResult!.trim().isNotEmpty) return lastResult!.trim();
    for (final l in logs.reversed) {
      if (l.kind != LogKind.observation && l.text.trim().isNotEmpty) return l.text.trim();
    }
    return '';
  }

  static String titleFrom(String text) {
    final line = text.trim().split('\n').first.trim();
    return line.length > 60 ? '${line.substring(0, 60)}…' : line;
  }

  static String _newId() {
    final r = Random();
    return '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
        '${r.nextInt(1 << 32).toRadixString(36)}';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'status': status.name,
    'logs': [for (final l in logs) l.toJson()],
    'messages': [for (final m in messages) m.toJson()],
    if (lastResult != null) 'lastResult': lastResult,
    if (vendor != null) 'vendor': vendor,
    if (remoteTaskId != null) 'remoteTaskId': remoteTaskId,
    'remoteLogCount': remoteLogCount,
  };

  factory ChatSession.fromJson(Map<String, dynamic> j) => ChatSession(
    id: '${j['id']}',
    title: '${j['title'] ?? ''}',
    createdAt: DateTime.tryParse('${j['createdAt']}'),
    updatedAt: DateTime.tryParse('${j['updatedAt']}'),
    status: AgentStatus.values.asNameMap()[j['status']] ?? AgentStatus.finished,
    logs: [
      for (final l in (j['logs'] as List? ?? const []))
        AgentLogEntry.fromJson((l as Map).cast<String, dynamic>()),
    ],
    messages: [
      for (final m in (j['messages'] as List? ?? const []))
        ChatMessage.fromJson((m as Map).cast<String, dynamic>()),
    ],
    lastResult: j['lastResult'] as String?,
    vendor: j['vendor'] as String?,
    remoteTaskId: j['remoteTaskId'] as String?,
    remoteLogCount: j['remoteLogCount'] as int? ?? 0,
  );
}

/// 대화 목록을 기기에 저장한다 (대화마다 JSON 파일 하나 + 마지막 화면 JPEG).
class ChatSessionStore extends ChangeNotifier {
  /// [directory] 가 없으면 앱 지원 폴더의 chat_sessions/ 를 쓴다.
  ChatSessionStore({Directory? directory}) : _dir = directory;

  /// 테스트용: 디스크에 저장하지 않는다.
  ChatSessionStore.memory() : _dir = null, _memoryOnly = true;

  Directory? _dir;
  bool _memoryOnly = false;

  /// 이보다 많으면 오래된 대화부터 지운다.
  static const maxSessions = 100;
  static const _saveDelay = Duration(milliseconds: 400);

  final Map<String, ChatSession> _sessions = {};
  final Map<String, Timer> _pending = {};

  /// 최근에 바뀐 순.
  List<ChatSession> get sessions =>
      _sessions.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  ChatSession? byId(String id) => _sessions[id];

  ChatSession? byRemoteTaskId(String taskId) {
    for (final s in _sessions.values) {
      if (s.remoteTaskId == taskId) return s;
    }
    return null;
  }

  Future<Directory?> _directory() async {
    if (_memoryOnly) return null;
    final dir = _dir ??= Directory(
      '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}chat_sessions',
    );
    await dir.create(recursive: true);
    return dir;
  }

  File _file(Directory dir, String id, String ext) =>
      File('${dir.path}${Platform.pathSeparator}$id.$ext');

  Future<void> load() async {
    try {
      final dir = await _directory();
      if (dir == null) return;
      await for (final f in dir.list()) {
        if (f is! File || !f.path.endsWith('.json')) continue;
        try {
          final s = ChatSession.fromJson(
            (jsonDecode(await f.readAsString()) as Map).cast<String, dynamic>(),
          );
          // 기기에서 돌던 작업은 앱이 꺼지면서 멈췄다. 서버 작업은 서버에서 계속된다.
          if (s.isBusy && !s.isRemote) {
            s.status = AgentStatus.cancelled;
            s.logs.add(AgentLogEntry(LogKind.error, '앱이 종료되어 작업이 중단되었습니다. 이어서 지시할 수 있습니다.'));
            save(s);
          }
          _sessions[s.id] = s;
        } catch (e) {
          debugPrint('대화 기록을 읽지 못했습니다: ${f.path} $e');
        }
      }
    } catch (e) {
      debugPrint('대화 기록 폴더를 열지 못했습니다: $e');
    }
    notifyListeners();
  }

  /// 새 대화를 목록에 추가한다.
  void add(ChatSession s) {
    _sessions[s.id] = s;
    _trim();
    save(s);
  }

  /// 대화가 바뀌었을 때 호출한다. 연달아 호출되면 잠깐 모아서 한 번에 쓴다.
  void save(ChatSession s, {bool touch = true}) {
    if (touch) s.updatedAt = DateTime.now();
    notifyListeners();
    if (_memoryOnly || _pending.containsKey(s.id)) return;
    _pending[s.id] = Timer(_saveDelay, () {
      _pending.remove(s.id);
      _write(s);
    });
  }

  /// 기다리던 저장을 지금 모두 쓴다 (앱이 백그라운드로 갈 때).
  Future<void> flush() async {
    final ids = _pending.keys.toList();
    for (final id in ids) {
      _pending.remove(id)?.cancel();
      final s = _sessions[id];
      if (s != null) await _write(s);
    }
  }

  Future<void> _write(ChatSession s) async {
    if (!_sessions.containsKey(s.id)) return; // 저장 전에 삭제됨
    try {
      final dir = await _directory();
      if (dir == null) return;
      final tmp = _file(dir, s.id, 'tmp');
      await tmp.writeAsString(jsonEncode(s.toJson()), flush: true);
      await tmp.rename(_file(dir, s.id, 'json').path);
      final shot = s.screenshot;
      if (shot != null && s.screenshotDirty) {
        s.screenshotDirty = false;
        await _file(dir, s.id, 'jpg').writeAsBytes(shot);
      }
    } catch (e) {
      debugPrint('대화 기록을 저장하지 못했습니다: ${s.id} $e');
    }
  }

  /// 저장해 둔 마지막 브라우저 화면을 읽는다.
  Future<Uint8List?> loadScreenshot(ChatSession s) async {
    if (s.screenshot != null) return s.screenshot;
    try {
      final dir = await _directory();
      if (dir == null) return null;
      final f = _file(dir, s.id, 'jpg');
      if (await f.exists()) s.screenshot = await f.readAsBytes();
    } catch (_) {}
    return s.screenshot;
  }

  Future<void> delete(String id) async {
    _pending.remove(id)?.cancel();
    if (_sessions.remove(id) == null) return;
    notifyListeners();
    try {
      final dir = await _directory();
      if (dir == null) return;
      for (final ext in ['json', 'jpg', 'tmp']) {
        final f = _file(dir, id, ext);
        if (await f.exists()) await f.delete();
      }
    } catch (e) {
      debugPrint('대화 기록을 지우지 못했습니다: $id $e');
    }
  }

  void _trim() {
    final all = sessions;
    for (final s in all.skip(maxSessions)) {
      if (!s.isBusy) delete(s.id);
    }
  }

  @override
  void dispose() {
    for (final t in _pending.values) {
      t.cancel();
    }
    super.dispose();
  }
}
