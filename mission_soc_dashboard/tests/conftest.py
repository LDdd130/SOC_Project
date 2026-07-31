"""pytest 공통 설정.

소스 트리에서 바로 테스트할 수 있게 프로젝트 루트를 sys.path 에 넣는다.
GUI 테스트가 아니므로 QApplication 은 만들지 않는다.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
