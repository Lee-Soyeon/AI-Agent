import pytest


@pytest.fixture(autouse=True)
def _tmp_data_dir(tmp_path, monkeypatch):
    # 작업 기록이 저장소의 server/data 에 쌓이지 않도록 테스트마다 임시 폴더를 쓴다.
    monkeypatch.setenv("DATA_DIR", str(tmp_path / "data"))
