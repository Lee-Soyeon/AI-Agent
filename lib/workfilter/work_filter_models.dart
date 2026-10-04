/// 공유된 통화/문자 내용 한 건의 처리 상태.
enum ShareItemStatus { processing, done, error }

enum SlackSendStatus { notSent, sent, skippedNotWork, failed }

/// LLM 이 판단한 분류 결과.
class WorkClassification {
  const WorkClassification({required this.isWork, required this.contentType, required this.summary});

  /// true = 업무 관련, false = 개인/기타.
  final bool isWork;

  /// LLM 이 내용을 보고 추측한 종류 (예: "통화", "문자", "기타"). 사람이 직접 고르지 않는다.
  final String contentType;

  /// 한두 줄 요약.
  final String summary;

  Map<String, dynamic> toJson() => {'isWork': isWork, 'contentType': contentType, 'summary': summary};

  factory WorkClassification.fromJson(Map<String, dynamic> j) => WorkClassification(
    isWork: j['isWork'] == true,
    contentType: j['contentType'] as String? ?? '기타',
    summary: j['summary'] as String? ?? '',
  );
}

/// 공유(또는 수동 입력)로 들어온 원문 한 건과 처리 결과.
class SharedItem {
  SharedItem({
    required this.id,
    required this.receivedAt,
    required this.rawText,
    this.status = ShareItemStatus.processing,
    this.classification,
    this.slackStatus = SlackSendStatus.notSent,
    this.error,
  });

  final String id;
  final DateTime receivedAt;
  final String rawText;
  ShareItemStatus status;
  WorkClassification? classification;
  SlackSendStatus slackStatus;
  String? error;

  String get preview =>
      rawText.length > 80 ? '${rawText.substring(0, 80).replaceAll('\n', ' ')}…' : rawText.replaceAll('\n', ' ');

  Map<String, dynamic> toJson() => {
    'id': id,
    'receivedAt': receivedAt.toIso8601String(),
    'rawText': rawText,
    'status': status.name,
    if (classification != null) 'classification': classification!.toJson(),
    'slackStatus': slackStatus.name,
    if (error != null) 'error': error,
  };

  factory SharedItem.fromJson(Map<String, dynamic> j) => SharedItem(
    id: j['id'] as String,
    receivedAt: DateTime.tryParse(j['receivedAt'] as String? ?? '') ?? DateTime.now(),
    rawText: j['rawText'] as String? ?? '',
    status: ShareItemStatus.values.asNameMap()[j['status']] ?? ShareItemStatus.done,
    classification: j['classification'] == null
        ? null
        : WorkClassification.fromJson((j['classification'] as Map).cast<String, dynamic>()),
    slackStatus: SlackSendStatus.values.asNameMap()[j['slackStatus']] ?? SlackSendStatus.notSent,
    error: j['error'] as String?,
  );
}
