import 'agent_models.dart';

/// 승인이 필요한 버튼의 동작 종류.
///
/// 서버(`server/app/safety.py`)와 같은 규칙이다. 규칙을 바꾸면 양쪽을 함께 고치고
/// `server/tests/sensitive_labels.json` 에 사례를 추가한다 (앱·서버 테스트가 같은 표를 검사).
enum SensitiveAction {
  // 취소·해지를 먼저 본다: "주문 취소", "예약 취소" 가 주문/예약으로 분류되지 않도록.
  terminate('취소·해지·탈퇴', 'terminate'),
  pay('결제', 'purchase'),
  book('예약·예매 확정', 'booking'),
  submit('지원·제출', 'submit'),
  post('글 게시', 'post'),
  send('전송', 'send_message');

  const SensitiveAction(this.label, this.approvalKind);
  final String label;

  /// 이 동작을 승인받을 때 request_approval 에 넣을 kind.
  final String approvalKind;

  RegExp get pattern => _patterns[this]!;

  static final _patterns = {
    terminate: RegExp(
      r'(탈퇴|계정\s*삭제|영구\s*삭제|(구독|멤버십|멤버쉽|정기\s*결제|자동\s*결제)\s*해지|해지\s*하기|'
      r'(주문|예약|예매|결제|구매)\s*취소|delete\s*(my\s*)?account|cancel\s*(my\s*)?subscription)',
      caseSensitive: false,
      multiLine: true,
    ),
    pay: RegExp(
      r'(결제\s*하기|결제\s*완료|\d[\d,]*\s*원\s*결제|주문\s*하기|주문\s*확정|구매\s*확정|'
      r'pay\s*now|place\s*(your\s*)?order|complete\s*purchase|confirm\s*(and\s*)?pay|송금|이체)',
      caseSensitive: false,
      multiLine: true,
    ),
    book: RegExp(
      r'(예약\s*확정|예약\s*신청|예약\s*완료|동의하고\s*예약|예매\s*하기|'
      r'book\s*now|reserve\s*now|confirm\s*(booking|reservation))',
      caseSensitive: false,
      multiLine: true,
    ),
    submit: RegExp(
      r'(지원\s*하기|지원서\s*제출|제출\s*하기|^\s*제출\s*$|apply\s*now|submit\s*application)',
      caseSensitive: false,
      multiLine: true,
    ),
    post: RegExp(
      r'(게시\s*하기|^\s*게시\s*$|^\s*등록\s*$|^\s*올리기\s*$|'
      r'(글|댓글|답글|후기|리뷰|게시글|게시물)\s*(등록|올리기|작성\s*완료)|^\s*(post|tweet)\s*$)',
      caseSensitive: false,
      multiLine: true,
    ),
    send: RegExp(r'(보내기|메일\s*전송|^\s*전송\s*$|\bsend\b)', caseSensitive: false, multiLine: true),
  };

  /// [label] 이 여러 줄이면(폼의 버튼 문구들) 줄마다 검사한다.
  static SensitiveAction? classify(String label) {
    for (final a in values) {
      if (a.pattern.hasMatch(label)) return a;
    }
    return null;
  }
}

/// 코드 레벨 안전장치.
///
/// LLM 이 프롬프트를 무시하거나 웹페이지/이메일 속 악성 지시(prompt injection)에 속더라도,
/// 결제·전송·예약·게시처럼 되돌릴 수 없는 버튼은 사용자가 승인한 경우에만 누를 수 있도록 강제한다.
///
/// 승인은 "아무 버튼 1회"가 아니라 승인한 내용에 묶인다:
/// - 승인 종류와 버튼 동작이 맞아야 한다 (메일 전송 승인으로 결제 버튼을 누를 수 없음).
/// - 승인받은 사이트에서만 쓸 수 있다.
/// - 버튼에 금액이 적혀 있으면 그 금액이 승인 내용에 있어야 한다 (금액이 바뀌면 다시 승인).
class SafetyPolicy {
  SafetyPolicy({this.grantTtl = const Duration(minutes: 10)});

  /// 승인 종류별로 누를 수 있는 동작.
  /// 예약은 마지막 단계에서 결제 버튼이 나오는 경우가 많아 결제도 허용한다.
  /// "기타" 승인으로는 결제·전송을 할 수 없다.
  static const allowed = <ApprovalKind, Set<SensitiveAction>>{
    ApprovalKind.purchase: {SensitiveAction.pay},
    ApprovalKind.sendEmail: {SensitiveAction.send},
    ApprovalKind.sendMessage: {SensitiveAction.send},
    ApprovalKind.booking: {SensitiveAction.book, SensitiveAction.pay},
    ApprovalKind.post: {SensitiveAction.post},
    ApprovalKind.submit: {SensitiveAction.submit},
    ApprovalKind.terminate: {SensitiveAction.terminate},
    ApprovalKind.other: {
      SensitiveAction.book,
      SensitiveAction.post,
      SensitiveAction.submit,
      SensitiveAction.terminate,
    },
  };

  final Duration grantTtl;

  ApprovalGrant? _grant;

  bool isSensitive(String label) => SensitiveAction.classify(label) != null;

  /// [content] 는 사용자에게 보여준 승인 카드의 전체 내용, [url] 은 승인할 때의 페이지.
  void grant(ApprovalKind kind, {required String content, String? url}) {
    _grant = ApprovalGrant(
      kind: kind,
      content: content,
      site: siteOf(url),
      expiresAt: DateTime.now().add(grantTtl),
    );
  }

  void revoke() => _grant = null;

  bool get hasActiveGrant => _grant != null && DateTime.now().isBefore(_grant!.expiresAt);

  /// 민감한 버튼을 누르기 직전 호출. 누를 수 있으면 null, 막아야 하면 이유를 돌려준다.
  /// 민감한 버튼이면 결과와 관계없이 승인은 소진된다 (1회용).
  String? authorize(String label, {String? url}) {
    final action = SensitiveAction.classify(label);
    if (action == null) return null;
    final g = _grant;
    _grant = null;
    if (g == null || !DateTime.now().isBefore(g.expiresAt)) {
      return '${action.label} 버튼입니다. 먼저 request_approval(kind: ${action.approvalKind}) 로 '
          '전체 내용을 보여주고 사용자 승인을 받으세요.';
    }
    if (!allowed[g.kind]!.contains(action)) {
      return '승인받은 것은 "${g.kind.label}"인데 이 버튼은 "${action.label}" 동작입니다. '
          'request_approval(kind: ${action.approvalKind}) 로 다시 승인받으세요.';
    }
    final site = siteOf(url);
    if (g.site != null && site != null && g.site != site) {
      return '승인받은 사이트(${g.site})와 지금 사이트($site)가 다릅니다. 이 사이트에서 다시 승인받으세요.';
    }
    final approvedNumbers = _numbers(g.content);
    final changed = amountsIn(label).where((n) => !approvedNumbers.contains(n)).toList();
    if (changed.isNotEmpty) {
      return '버튼 금액(${changed.map(_won).join(', ')})이 승인받은 내용에 없습니다. '
          '금액이 바뀌었으면 바뀐 금액으로 다시 승인받으세요.';
    }
    return null;
  }

  /// 버튼 문구 속 금액 (콤마 제거). 예: "32,900원 결제하기" → {"32900"}.
  static Set<String> amountsIn(String label) => {
    for (final m in RegExp(r'(\d[\d,]*)\s*원|[₩$]\s*(\d[\d,]*)').allMatches(label))
      (m.group(1) ?? m.group(2)!).replaceAll(',', ''),
  };

  static Set<String> _numbers(String text) => {
    for (final m in RegExp(r'\d[\d,]*').allMatches(text)) m.group(0)!.replaceAll(',', ''),
  };

  static String _won(String n) =>
      '${n.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}원';

  /// 주소의 사이트 단위 (m.coupang.com → coupang.com, m.11st.co.kr → 11st.co.kr).
  static String? siteOf(String? url) {
    if (url == null) return null;
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (host.isEmpty) return null;
    final parts = host.split('.');
    if (parts.length < 2) return host;
    const second = {'co', 'or', 'go', 'ne', 'ac', 're', 'pe', 'com', 'net', 'org'};
    final n =
        parts.length >= 3 && parts.last.length == 2 && second.contains(parts[parts.length - 2])
        ? 3
        : 2;
    return parts.sublist(parts.length - n).join('.');
  }
}

class ApprovalGrant {
  ApprovalGrant({
    required this.kind,
    required this.content,
    required this.site,
    required this.expiresAt,
  });

  final ApprovalKind kind;
  final String content;
  final String? site;
  final DateTime expiresAt;
}
