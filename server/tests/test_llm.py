from app.llm import AnthropicProvider, GeminiProvider, Message, OpenAiProvider, ToolCall, ToolSpec

TOOLS = [ToolSpec("click", "click", {"type": "object", "properties": {"element_id": {"type": "integer"}}})]
HISTORY = [
    Message("user", "장바구니"),
    Message("assistant", "열게요", [ToolCall("c1", "click", {"element_id": 3}), ToolCall("c2", "click", {"element_id": 4})]),
    Message("tool", "ok1", tool_call_id="c1", tool_name="click"),
    Message("tool", "ok2", tool_call_id="c2", tool_name="click"),
    Message("user", "계속"),
]


def test_openai_body_and_parse():
    b = OpenAiProvider.build_body("m", "sys", HISTORY, TOOLS)
    assert b["messages"][0] == {"role": "system", "content": "sys"}
    assert b["messages"][2]["tool_calls"][0]["function"]["arguments"] == '{"element_id": 3}'
    assert b["messages"][3] == {"role": "tool", "tool_call_id": "c1", "content": "ok1"}
    assert "tools" not in OpenAiProvider.build_body("m", "s", HISTORY, [])
    r = OpenAiProvider.parse({"choices": [{"message": {"content": None, "tool_calls": [
        {"id": "x", "type": "function", "function": {"name": "click", "arguments": '{"element_id": 7}'}}]}}]})
    assert r.tool_calls[0].arguments == {"element_id": 7}


def test_anthropic_groups_tool_results_and_echoes_raw():
    b = AnthropicProvider.build_body("m", 10, "sys", HISTORY, TOOLS)
    msgs = b["messages"]
    assert len(msgs) == 3
    assert [x["type"] for x in msgs[2]["content"]] == ["tool_result", "tool_result", "text"]
    r = AnthropicProvider.parse({"content": [
        {"type": "text", "text": "클릭"}, {"type": "tool_use", "id": "t1", "name": "click", "input": {"element_id": 2}}]})
    assert r.text == "클릭" and r.tool_calls[0].id == "t1"
    echoed = AnthropicProvider.build_body("m", 10, "s", [Message("user", "a"), r.to_message()], TOOLS)
    assert echoed["messages"][1]["content"] == r.raw


def test_gemini_function_response_grouping_and_parse():
    b = GeminiProvider.build_body("sys", HISTORY, TOOLS)
    parts = b["contents"][2]["parts"]
    assert parts[0]["functionResponse"]["name"] == "click"
    assert parts[2] == {"text": "계속"}
    r = GeminiProvider.parse({"candidates": [{"content": {"parts": [
        {"text": "생각", "thought": True},
        {"functionCall": {"name": "click", "args": {"element_id": 5}}, "thoughtSignature": "sig"}]}}]})
    assert r.text is None and r.tool_calls[0].arguments == {"element_id": 5} and len(r.raw) == 2


def test_anthropic_workspace_header_only_when_set():
    assert "anthropic-workspace-id" not in AnthropicProvider("k", "m").headers()
    assert AnthropicProvider("k", "m", workspace_id="wrkspc_1").headers()["anthropic-workspace-id"] == "wrkspc_1"
