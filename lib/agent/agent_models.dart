import 'dart:async';

enum AgentStatus { idle, running, waitingApproval, waitingUser, finished, failed, cancelled }

enum LogKind { user, thought, action, observation, approval, error, result }

class AgentLogEntry {
  AgentLogEntry(this.kind, this.text, {this.detail}) : time = DateTime.now();

  final LogKind kind;
  final String text;

  /// 펼쳐서 볼 수 있는 긴 내용(페이지 스냅샷 등).
  final String? detail;
  final DateTime time;
}

enum ApprovalKind {
  purchase('구매/결제'),
  sendEmail('이메일 전송'),
  other('기타 중요한 동작');

  const ApprovalKind(this.label);
  final String label;

  static ApprovalKind parse(Object? v) => switch (v) {
    'purchase' => ApprovalKind.purchase,
    'send_email' => ApprovalKind.sendEmail,
    _ => ApprovalKind.other,
  };
}

class ApprovalRequest {
  ApprovalRequest({required this.kind, required this.title, required this.summary, this.details});

  final ApprovalKind kind;
  final String title;
  final String summary;
  final String? details;
  final Completer<ApprovalDecision> completer = Completer();
}

class ApprovalDecision {
  const ApprovalDecision({required this.approved, this.feedback});

  final bool approved;

  /// 거절하면서 남긴 수정 요청 (예: "본문을 더 공손하게").
  final String? feedback;
}

class UserQuestion {
  UserQuestion(this.question, {this.choices = const []});

  final String question;
  final List<String> choices;
  final Completer<String> completer = Completer();
}

/// 에이전트 실행기가 UI 에 요청하는 것들.
abstract class AgentHooks {
  void onLog(AgentLogEntry entry);
  void onStatus(AgentStatus status);
  void onScreenshot(List<int> jpeg);
  Future<ApprovalDecision> requestApproval(ApprovalRequest request);
  Future<String> askUser(UserQuestion question);

  /// 보이는 브라우저를 열어 사용자가 직접 처리하게 한다(로그인, 캡차, 결제 비밀번호 등).
  /// 사용자가 마친 뒤의 URL 을 돌려준다.
  Future<String?> requestUserHelp(String reason, String? url);
}
