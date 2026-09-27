import 'dart:async';

enum AgentStatus { idle, running, waitingApproval, waitingUser, finished, failed, cancelled }

enum LogKind { user, thought, action, observation, approval, error, result }

class AgentLogEntry {
  AgentLogEntry(this.kind, this.text, {this.detail, DateTime? time})
    : time = time ?? DateTime.now();

  final LogKind kind;
  final String text;

  /// 펼쳐서 볼 수 있는 긴 내용(페이지 스냅샷 등).
  final String? detail;
  final DateTime time;
}

/// 승인 종류. 종류마다 누를 수 있는 버튼이 정해져 있다 (`SafetyPolicy.allowed`).
enum ApprovalKind {
  purchase('purchase', '구매/결제'),
  sendEmail('send_email', '이메일 전송'),
  sendMessage('send_message', '메시지 전송'),
  booking('booking', '예약/예매'),
  post('post', '글 게시'),
  submit('submit', '지원/제출'),
  terminate('terminate', '취소/해지/탈퇴'),
  other('other', '기타 중요한 동작');

  const ApprovalKind(this.wire, this.label);

  /// request_approval 의 kind 값.
  final String wire;
  final String label;

  static ApprovalKind parse(Object? v) =>
      values.firstWhere((k) => k.wire == v, orElse: () => ApprovalKind.other);
}

class ApprovalRequest {
  ApprovalRequest({
    required this.kind,
    required this.title,
    required this.summary,
    this.details,
    this.handoff = false,
  });

  final ApprovalKind kind;

  /// true 면 승인 후 에이전트가 버튼을 누르는 게 아니라, 준비된 결제 화면을 사용자에게 넘긴다.
  final bool handoff;
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

/// 결제 넘기기 결과.
class PaymentOutcome {
  const PaymentOutcome({required this.approved, this.completed = false, this.url, this.feedback});

  /// 승인 카드에서 "결제하러 가기"를 눌렀는지.
  final bool approved;

  /// 사용자가 결제를 끝까지 마쳤는지 (완료 페이지 자동 감지 또는 "결제 완료" 확인).
  final bool completed;

  /// 결제 화면을 닫을 때의 페이지 (에이전트가 이어서 확인).
  final String? url;
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

  /// 결제 직전 화면을 사용자에게 넘긴다: 승인 카드 → 결제 화면(같은 세션) → 완료 감지.
  Future<PaymentOutcome> requestPaymentHandoff(ApprovalRequest request);

  /// 보이는 브라우저를 열어 사용자가 직접 처리하게 한다(로그인, 캡차, 결제 비밀번호 등).
  /// 사용자가 마친 뒤의 URL 을 돌려준다.
  Future<String?> requestUserHelp(String reason, String? url);
}
