import pytest

from app import ui_schema
from app.ui_schema import UiSchemaError, coerce, is_interactive, label, validate


def test_all_eight_parts_validate():
    ok = [
        {"type": "chips", "question": "어느 열?", "options": ["품목", "단가"]},
        {"type": "keyword", "question": "값은?", "placeholder": "예: 식품", "options": ["그대로"]},
        {"type": "file_button", "question": "올려주세요", "label": "엑셀 올리기", "accept": "file"},
        {"type": "confirm", "sentence": "이렇게 시킬까요?"},
        {"type": "table", "headers": ["품목", "단가"], "rows": [["물", "900"], ["빵", None]]},
        {"type": "before_after", "before": "초안", "after": "고친 글", "caption": "문장만"},
        {"type": "checklist", "items": ["마감 10/30", "서울"], "done": [True]},
        {"type": "text_block", "text": "안녕"},
    ]
    for tree in ok:
        out = validate(tree)
        assert out["type"] == tree["type"]
    assert set(ui_schema.parts()) == {t["type"] for t in ok}


def test_interactive_flag_matches_schema():
    assert is_interactive({"type": "chips"}) and is_interactive({"type": "confirm"})
    assert not is_interactive({"type": "table"}) and not is_interactive({"type": "nope"})


def test_chips_limits_and_dedupe():
    with pytest.raises(UiSchemaError):
        validate({"type": "chips", "question": "q", "options": ["하나"]})
    with pytest.raises(UiSchemaError):
        validate({"type": "chips", "question": "q", "options": [f"o{i}" for i in range(7)]})
    out = validate({"type": "chips", "question": "q", "options": ["a", "a", "b", 3]})
    assert out["options"] == ["a", "b", "3"] and out["allow_free"] is True


def test_table_pads_and_truncates():
    out = validate({"type": "table", "headers": ["a", "b"], "rows": [["1"], ["1", "2", "3"]] + [["x", "y"]] * 30})
    assert out["rows"][0] == ["1", ""] and out["rows"][1] == ["1", "2"]
    assert len(out["rows"]) == ui_schema.limits()["table_rows_max"]
    assert out["truncated"] == 12


def test_checklist_done_is_aligned():
    out = validate({"type": "checklist", "items": ["a", "b", "c"], "done": [True]})
    assert out["done"] == [True, False, False]


def test_coerce_never_raises_and_falls_back_to_text_block():
    bad = coerce({"type": "html", "html": "<b>x</b>"})
    assert bad["type"] == "text_block" and "html" in bad["text"] and "오류" in bad["caption"]
    assert coerce("그냥 글")["type"] == "text_block"
    assert coerce(None)["type"] == "text_block"
    assert coerce({"type": "chips", "question": "q", "options": ["a", "b"]})["type"] == "chips"


def test_text_is_clipped():
    out = validate({"type": "text_block", "text": "가" * 5000})
    assert len(out["text"]) == ui_schema.limits()["text_max_chars"]


def test_labels():
    assert label(validate({"type": "table", "headers": ["a"], "rows": [["1"], ["2"]]})) == "표 2행"
    assert label({"type": "chips", "question": "어느 열?"}) == "질문: 어느 열?"
    assert "8" not in ui_schema.prompt_help() or "chips" in ui_schema.prompt_help()
