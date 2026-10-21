import copy

import pytest

from app import recipes
from app.recipes import RecipeError, check, fill_prompt


def test_catalog_loads_and_has_nine_or_more_recipes():
    rs = recipes.recipes()
    assert len(rs) >= 9
    assert recipes.find("excel_fill")["title"] == "엑셀 빈 열 채우기"
    assert recipes.find("nope") is None


def test_invariants_hold_for_every_recipe():
    for r in recipes.recipes():
        assert len(r["steps"]) <= recipes.MAX_STEPS, r["id"]
        for s in r["steps"]:
            assert s["kind"] in recipes.STEP_KINDS, (r["id"], s)
            if s["kind"] == "chips":
                assert s.get("options") or s.get("options_from"), (r["id"], s["id"])
        assert r["engine"] in ("llm", "browser", "gmail")
        assert r["gallery"]["before"] and r["gallery"]["after"] and r["gallery"]["line"]


def test_persona_ordering_puts_matches_first():
    rs = recipes.for_persona("home")
    first = [r["id"] for r in rs if "home" in r["personas"]]
    assert [r["id"] for r in rs[: len(first)]] == first
    assert len(recipes.for_persona(None)) == len(recipes.recipes())


def test_intake_defaults_have_three_each():
    for k in ("photo", "file", "text"):
        assert len(recipes.intake_defaults(k)) == 3
    assert recipes.intake_defaults("weird")  # 모르는 종류도 빈 목록은 아니다


def test_fill_prompt_replaces_step_answers():
    r = recipes.find("excel_fill")
    p = fill_prompt(r, {"column": "카테고리", "values": "식품·생활·전자", "file": "품목,단가\n물,900"})
    assert "'카테고리' 열" in p and "식품·생활·전자" in p and "물,900" in p
    assert "{" not in p


def test_check_rejects_broken_catalogs():
    base = copy.deepcopy(recipes.data())

    too_many = copy.deepcopy(base)
    too_many["recipes"][0]["steps"] = [{"id": f"s{i}", "kind": "keyword", "text": "?"} for i in range(4)]
    with pytest.raises(RecipeError, match="단계"):
        check(too_many)

    bad_kind = copy.deepcopy(base)
    bad_kind["recipes"][0]["steps"][0]["kind"] = "slider"
    with pytest.raises(RecipeError, match="kind"):
        check(bad_kind)

    missing_placeholder = copy.deepcopy(base)
    missing_placeholder["recipes"][0]["prompt_template"] = "{ghost} 를 해줘"
    with pytest.raises(RecipeError, match="ghost"):
        check(missing_placeholder)

    chips_without_options = copy.deepcopy(base)
    chips_without_options["recipes"][0]["steps"] = [{"id": "c", "kind": "chips", "text": "?"}]
    with pytest.raises(RecipeError, match="options"):
        check(chips_without_options)

    dangling_next = copy.deepcopy(base)
    dangling_next["recipes"][0]["next"] = "nowhere"
    with pytest.raises(RecipeError, match="next"):
        check(dangling_next)
