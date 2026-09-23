import '../llm/llm_types.dart';

/// LLM 에게 제공하는 도구 목록. (임의 JavaScript 실행 도구는 의도적으로 제공하지 않는다.)
class AgentTools {
  static const openUrl = 'open_url';
  static const readPage = 'read_page';
  static const click = 'click';
  static const typeText = 'type_text';
  static const scroll = 'scroll';
  static const goBack = 'go_back';
  static const requestApproval = 'request_approval';
  static const askUser = 'ask_user';
  static const requestUserHelp = 'request_user_help';
  static const finish = 'finish';

  static const _elementId = {
    'type': 'integer',
    'description': '가장 최근 페이지 스냅샷의 요소 id (예: [12] 이면 12)',
  };

  static final List<ToolSpec> specs = [
    const ToolSpec(
      name: openUrl,
      description: '백그라운드 브라우저에서 URL 을 연다. 결과로 새 페이지 스냅샷을 돌려준다.',
      parameters: {
        'type': 'object',
        'properties': {
          'url': {'type': 'string', 'description': 'https:// 로 시작하는 전체 URL'},
        },
        'required': ['url'],
      },
    ),
    const ToolSpec(
      name: readPage,
      description: '현재 페이지의 텍스트와 조작 가능한 요소 목록(id 포함)을 읽는다.',
      parameters: {'type': 'object', 'properties': {}},
    ),
    const ToolSpec(
      name: click,
      description:
          '요소를 클릭한다. 결제/주문 확정/메일 보내기 버튼은 request_approval 로 승인받은 뒤에만 누를 수 있다. '
          '결과로 새 페이지 스냅샷을 돌려준다.',
      parameters: {
        'type': 'object',
        'properties': {'element_id': _elementId},
        'required': ['element_id'],
      },
    ),
    const ToolSpec(
      name: typeText,
      description:
          '입력창/텍스트영역에 텍스트를 입력하거나 select 의 옵션을 고른다. 기존 값은 대체된다. '
          '비밀번호 입력창에는 입력할 수 없다(request_user_help 사용).',
      parameters: {
        'type': 'object',
        'properties': {
          'element_id': _elementId,
          'text': {'type': 'string', 'description': '입력할 텍스트 또는 선택할 옵션 이름'},
          'submit': {'type': 'boolean', 'description': '입력 후 Enter(검색 실행 등)를 누를지 여부'},
        },
        'required': ['element_id', 'text'],
      },
    ),
    const ToolSpec(
      name: scroll,
      description: '페이지를 스크롤하고 새 스냅샷을 돌려준다.',
      parameters: {
        'type': 'object',
        'properties': {
          'direction': {
            'type': 'string',
            'enum': ['down', 'up', 'top', 'bottom'],
          },
        },
        'required': ['direction'],
      },
    ),
    const ToolSpec(
      name: goBack,
      description: '브라우저 뒤로 가기.',
      parameters: {'type': 'object', 'properties': {}},
    ),
    const ToolSpec(
      name: requestApproval,
      description:
          '결제, 주문 확정, 이메일 전송 등 되돌릴 수 없는 동작 직전에 사용자에게 승인을 요청한다. '
          '사용자가 판단할 수 있도록 모든 핵심 정보를 빠짐없이 넣어야 한다. '
          '구매: 상품명·옵션·수량·단가·총 결제금액·배송지·결제수단. 이메일: 받는 사람·참조·제목·본문 전체. '
          '승인되면 해당 버튼을 10분 안에 한 번 누를 수 있다.',
      parameters: {
        'type': 'object',
        'properties': {
          'kind': {
            'type': 'string',
            'enum': ['purchase', 'send_email', 'other'],
          },
          'title': {'type': 'string', 'description': '한 줄 제목 (예: "쿠팡 결제 승인 요청")'},
          'summary': {'type': 'string', 'description': '핵심 요약 (여러 줄 가능)'},
          'details': {'type': 'string', 'description': '이메일 본문 전체, 상품 목록 등 상세 내용'},
        },
        'required': ['kind', 'title', 'summary'],
      },
    ),
    const ToolSpec(
      name: askUser,
      description: '작업을 계속하는 데 사용자의 선택이나 정보가 꼭 필요할 때 질문한다 (예: 여러 상품 중 선택, 수신자 확인).',
      parameters: {
        'type': 'object',
        'properties': {
          'question': {'type': 'string'},
          'choices': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '선택지 (없으면 자유 입력)',
          },
        },
        'required': ['question'],
      },
    ),
    const ToolSpec(
      name: requestUserHelp,
      description:
          '로그인, 2단계 인증, 캡차, 결제 비밀번호 입력처럼 사용자가 직접 해야 하는 일이 있을 때 '
          '현재 페이지를 사용자에게 보여준다. 사용자가 마치면 그 페이지에서 계속한다.',
      parameters: {
        'type': 'object',
        'properties': {
          'reason': {'type': 'string', 'description': '사용자에게 보여줄 안내 (무엇을 해달라는지)'},
        },
        'required': ['reason'],
      },
    ),
    const ToolSpec(
      name: finish,
      description: '작업을 마치고 사용자에게 결과를 보고한다.',
      parameters: {
        'type': 'object',
        'properties': {
          'summary': {'type': 'string', 'description': '한국어 결과 보고 (무엇을 했는지, 확인한 내용, 남은 일)'},
        },
        'required': ['summary'],
      },
    ),
  ];
}
