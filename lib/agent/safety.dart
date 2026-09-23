/// 코드 레벨 안전장치.
///
/// LLM 이 프롬프트를 무시하거나 웹페이지/이메일 속 악성 지시(prompt injection)에 속더라도,
/// 결제·전송처럼 되돌릴 수 없는 버튼은 사용자가 승인한 경우에만 누를 수 있도록 강제한다.
class SafetyPolicy {
  SafetyPolicy({RegExp? sensitivePattern, this.grantTtl = const Duration(minutes: 10)})
    : sensitivePattern = sensitivePattern ?? defaultSensitivePattern;

  /// 결제 확정, 주문 확정, 메일 전송 등을 나타내는 버튼 문구.
  /// (장바구니 담기, 구매하기(주문서 이동) 등 되돌릴 수 있는 단계는 제외)
  static final defaultSensitivePattern = RegExp(
    r'(결제\s*하기|결제\s*완료|\d[\d,]*\s*원\s*결제|주문\s*하기|주문\s*확정|구매\s*확정|'
    r'pay\s*now|place\s*(your\s*)?order|complete\s*purchase|confirm\s*(and\s*)?pay|'
    r'보내기|메일\s*전송|^\s*전송\s*$|\bsend\b|송금|이체)',
    caseSensitive: false,
  );

  final RegExp sensitivePattern;
  final Duration grantTtl;

  ApprovalGrant? _grant;

  bool isSensitive(String label) => sensitivePattern.hasMatch(label);

  void grant(String kind, String summary) {
    _grant = ApprovalGrant(kind: kind, summary: summary, expiresAt: DateTime.now().add(grantTtl));
  }

  void revoke() => _grant = null;

  bool get hasActiveGrant => _grant != null && DateTime.now().isBefore(_grant!.expiresAt);

  /// 민감한 버튼을 누르기 직전 호출. 승인이 있으면 1회 소진하고 true.
  bool consumeGrant() {
    if (!hasActiveGrant) {
      _grant = null;
      return false;
    }
    _grant = null;
    return true;
  }
}

class ApprovalGrant {
  ApprovalGrant({required this.kind, required this.summary, required this.expiresAt});

  final String kind;
  final String summary;
  final DateTime expiresAt;
}
