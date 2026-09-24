from urllib.parse import urlparse

from app import catalog
from app.agent import AgentRunner, Task, system_prompt
from app.llm import LlmResponse

from .fakes import FakeBrowser, ScriptedLlm, call, last_tool_result


def test_catalog_is_well_formed():
    items = catalog.services()
    assert len(items) >= 100
    assert len({s["id"] for s in items}) == len(items)
    for s in items:
        assert s["web"] in ("web", "partial", "app_only", "excluded"), s
        if s["web"] in catalog.SUPPORTED:
            assert urlparse(s["home"]).scheme == "https", s
        else:
            assert s.get("note"), f"{s['id']}: 지원하지 않는 이유(note)가 필요"
        for key in ("login", "search"):
            if s.get(key):
                assert urlparse(s[key]).scheme == "https", s
        if s.get("search"):
            assert "{q}" in s["search"], s


def test_find_and_search_url():
    assert catalog.find("쿠팡")[0]["id"] == "coupang"
    assert catalog.find("네이버지도")[0]["id"] == "naver_map"
    assert catalog.search_url(catalog.find("쿠팡")[0], "제로 콜라") == "https://m.coupang.com/nm/search?q=%EC%A0%9C%EB%A1%9C%20%EC%BD%9C%EB%9D%BC"
    assert "브라우저로는 지원하지 않음" in catalog.describe(catalog.find("배달의민족")[0])
    assert catalog.find("없는서비스xyz") == []


def test_prompt_lists_services_compactly():
    p = system_prompt()
    assert "쿠팡" in p and "배달의민족" in p
    assert "https://m.coupang.com/nm/search" not in p  # 상세 URL 은 도구로만


async def test_service_info_tool():
    llm = ScriptedLlm([
        call("service_info", {"service": "코레일"}, "a"),
        call("service_info", {"service": "G마켓", "keyword": "생수"}, "b"),
        LlmResponse(text="끝"),
    ])
    await AgentRunner(llm, FakeBrowser()).run(Task("x"), "x")
    assert "매크로" in last_tool_result(llm.seen[1])
    assert "https://browse.gmarket.co.kr/search?keyword=%EC%83%9D%EC%88%98" in last_tool_result(llm.seen[2])
