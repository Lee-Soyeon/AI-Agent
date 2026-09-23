from .llm import ToolSpec

_ELEMENT_ID = {"type": "integer", "description": "가장 최근 페이지 스냅샷의 요소 id (예: [12] 이면 12)"}

TOOLS = [
    ToolSpec("open_url", "브라우저에서 URL 을 연다. 결과로 새 페이지 스냅샷을 돌려준다.",
             {"type": "object", "properties": {"url": {"type": "string"}}, "required": ["url"]}),
    ToolSpec("read_page", "현재 페이지의 텍스트와 조작 가능한 요소 목록(id 포함)을 읽는다.",
             {"type": "object", "properties": {}}),
    ToolSpec("click", "요소를 클릭한다. 결제·주문 확정·전송·예약 확정 버튼은 request_approval 로 승인받은 뒤에만 누를 수 있다.",
             {"type": "object", "properties": {"element_id": _ELEMENT_ID}, "required": ["element_id"]}),
    ToolSpec("type_text", "입력창에 텍스트를 넣거나 select 옵션을 고른다. 비밀번호 칸에는 입력할 수 없다.",
             {"type": "object", "properties": {
                 "element_id": _ELEMENT_ID,
                 "text": {"type": "string"},
                 "submit": {"type": "boolean", "description": "입력 후 Enter"},
             }, "required": ["element_id", "text"]}),
    ToolSpec("scroll", "페이지를 스크롤한다.",
             {"type": "object", "properties": {"direction": {"type": "string", "enum": ["down", "up", "top", "bottom"]}},
              "required": ["direction"]}),
    ToolSpec("go_back", "뒤로 가기.", {"type": "object", "properties": {}}),
    ToolSpec("request_approval",
             "결제·주문 확정·메일 전송·예약 확정 등 되돌릴 수 없는 동작 직전에 사용자 승인을 요청한다. "
             "상품·수량·금액·배송지 또는 받는 사람·본문 등 판단에 필요한 정보를 빠짐없이 넣는다. "
             "승인되면 해당 버튼을 10분 안에 한 번 누를 수 있다.",
             {"type": "object", "properties": {
                 "kind": {"type": "string", "enum": ["purchase", "send_email", "other"]},
                 "title": {"type": "string"},
                 "summary": {"type": "string"},
                 "details": {"type": "string"},
             }, "required": ["kind", "title", "summary"]}),
    ToolSpec("ask_user", "꼭 필요한 선택·정보를 사용자에게 묻는다.",
             {"type": "object", "properties": {
                 "question": {"type": "string"},
                 "choices": {"type": "array", "items": {"type": "string"}},
             }, "required": ["question"]}),
    ToolSpec("request_user_help",
             "로그인·2단계 인증·캡차·결제 비밀번호처럼 사용자가 직접 해야 하는 일이 있을 때 호출한다. "
             "사용자의 휴대폰에 이 브라우저 화면이 실시간으로 뜨고, 사용자가 마치면 같은 화면에서 이어서 진행한다.",
             {"type": "object", "properties": {"reason": {"type": "string"}}, "required": ["reason"]}),
    ToolSpec("finish", "작업을 마치고 한국어로 결과를 보고한다.",
             {"type": "object", "properties": {"summary": {"type": "string"}}, "required": ["summary"]}),
]
