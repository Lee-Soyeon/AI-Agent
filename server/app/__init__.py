import sys

if sys.version_info < (3, 10):
    raise RuntimeError(
        f"Python 3.10 이상이 필요합니다 (지금: {sys.version.split()[0]}). "
        "server/README.md 의 '직접 실행' 안내대로 python3.12 로 가상환경을 만들어 주세요."
    )
