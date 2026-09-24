import 'agent_models.dart';
import 'agent_runner.dart';

/// 채팅 탭의 대화 하나. 에이전트에게 준 작업과 그 진행 기록을 담는다.
class ChatSession {
  ChatSession({
    required this.id,
    this.title = '새 채팅',
    DateTime? updatedAt,
    List<AgentLogEntry>? logs,
    this.status = AgentStatus.idle,
    this.lastResult,
    this.remoteTaskId,
    this.remoteLogCount = 0,
  }) : updatedAt = updatedAt ?? DateTime.now(),
       logs = logs ?? [];

  /// 저장할 때 대화당 남기는 최대 로그 수 (오래된 것부터 버린다).
  static const maxSavedLogs = 300;

  final String id;
  String title;
  DateTime updatedAt;
  final List<AgentLogEntry> logs;
  AgentStatus status;
  String? lastResult;

  /// 서버 모드 작업 id. 있으면 앱을 다시 켜도 이어서 지시할 수 있다.
  String? remoteTaskId;
  int remoteLogCount;

  /// 이 폰에서 실행한 대화의 실행기. 메모리에만 있으므로 앱을 다시 켜면 사라진다.
  AgentRunner? runner;

  bool get isEmpty => logs.isEmpty && remoteTaskId == null && runner == null;

  /// 이어서 지시할 수 있는지 (실행기가 살아 있거나 서버 작업이 있을 때).
  bool get canContinue => runner != null || remoteTaskId != null;

  /// 목록에 보여줄 마지막 한 줄.
  String get preview {
    if (lastResult != null && lastResult!.trim().isNotEmpty) return lastResult!.trim();
    for (final l in logs.reversed) {
      if (l.kind != LogKind.observation && l.text.trim().isNotEmpty) return l.text.trim();
    }
    return '';
  }

  static String titleFrom(String task) {
    final t = task.trim().replaceAll(RegExp(r'\s+'), ' ');
    return t.length > 40 ? '${t.substring(0, 40)}…' : t;
  }

  // 페이지 스냅샷 같은 긴 detail 은 저장하지 않는다 (용량, 민감 정보 최소화).
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'updatedAt': updatedAt.toIso8601String(),
    'status': status.name,
    'lastResult': lastResult,
    'remoteTaskId': remoteTaskId,
    'remoteLogCount': remoteLogCount,
    'logs': [
      for (final l in logs.length > maxSavedLogs ? logs.sublist(logs.length - maxSavedLogs) : logs)
        {'kind': l.kind.name, 'text': l.text, 'time': l.time.toIso8601String()},
    ],
  };

  factory ChatSession.fromJson(Map<String, dynamic> j) {
    final remoteId = j['remoteTaskId'] as String?;
    var status = AgentStatus.values.asNameMap()[j['status']] ?? AgentStatus.idle;
    // 이 폰에서 돌던 작업은 앱이 꺼지면서 멈췄다. 서버 작업은 열 때 서버에서 상태를 다시 받는다.
    final wasBusy =
        status == AgentStatus.running ||
        status == AgentStatus.waitingApproval ||
        status == AgentStatus.waitingUser;
    if (remoteId == null && wasBusy) status = AgentStatus.cancelled;
    return ChatSession(
      id: j['id'] as String,
      title: j['title'] as String? ?? '채팅',
      updatedAt: DateTime.tryParse('${j['updatedAt']}'),
      status: status,
      lastResult: j['lastResult'] as String?,
      remoteTaskId: remoteId,
      remoteLogCount: j['remoteLogCount'] as int? ?? 0,
      logs: [
        for (final l in (j['logs'] as List? ?? const []))
          AgentLogEntry(
            LogKind.values.asNameMap()['${(l as Map)['kind']}'] ?? LogKind.observation,
            '${l['text'] ?? ''}',
            time: DateTime.tryParse('${l['time']}'),
          ),
      ],
    );
  }
}
