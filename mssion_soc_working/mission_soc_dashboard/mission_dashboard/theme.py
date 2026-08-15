"""테마(색상표) 관리.

색을 상수로 직접 import 하면 import 시점에 문자열이 박혀 런타임 교체가 안 된다.
그래서 팔레트를 dict 로 두고 :data:`T` 프록시를 통해 **접근할 때마다** 조회한다::

    from ..theme import T
    label.setStyleSheet(f"color:{T.text_dim};")

테마를 바꾸려면 :func:`set_theme` 를 부르고, 각 위젯의 ``apply_theme()`` 을
다시 호출해 인라인 스타일시트를 새로 그린다. MainWindow 가 그 순회를 담당한다.

기본값은 ``light`` 다. 관제/모니터링 화면은 밝은 환경에서 보는 일이 많고,
프로젝터·회의실 빔에서 어두운 테마가 뭉개지기 때문이다.
"""

from __future__ import annotations

import tempfile
from pathlib import Path
from typing import Final

__all__ = [
    "PALETTES",
    "T",
    "theme_name",
    "theme_label",
    "set_theme",
    "app_qss",
    "connection_color",
    "arrow_icons",
]


# ---------------------------------------------------------------- 팔레트 정의
#
# 키 이름은 의미 기준이다. 값만 갈아끼우면 새 테마가 된다.
#
#   bg          창 전체 배경
#   bg_alt      입력/버튼 등 한 단계 들어간 면
#   bg_card     카드(상태/장치) 배경. bg 보다 떠 보여야 한다
#   border      1px 테두리
#   text        본문
#   text_dim    보조 설명
#   accent      강조(연결 상태, 차트 기준선)
#   state_*     시스템 상태 4단계 + UNKNOWN
#   ok/bad/idle 불리언 표시
#   table_alt   표 교차 행
#   hover       버튼 hover 테두리
#   disabled    비활성 글자
#   selection   선택 영역 배경
#
LIGHT: Final[dict[str, str]] = {
    # 카드가 흰색이라 배경과 테두리를 충분히 어둡게 잡아야 경계가 보인다.
    # 처음에 bg #eef1f5 / border #c3cad4 로 잡았더니 흰 카드 위에서 구분선이
    # 사라진 것처럼 보였다.
    "bg": "#e6eaf0",
    "bg_alt": "#dce2ea",
    "bg_card": "#ffffff",
    "border": "#a9b4c2",
    "text": "#16202c",
    "text_dim": "#5a6675",
    "accent": "#1668dc",
    "state_normal": "#137a3b",
    "state_warning": "#a86b00",
    "state_degraded": "#d9600b",
    "state_safe_mode": "#c1121f",
    "state_unknown": "#78838f",
    "ok": "#137a3b",
    "bad": "#c1121f",
    "idle": "#8c96a1",
    "table_alt": "#f1f4f8",
    "hover": "#7d8ca0",
    "disabled": "#9aa4b0",
    "selection": "#cfe0f8",
}

DARK: Final[dict[str, str]] = {
    "bg": "#1e1f22",
    "bg_alt": "#2b2d30",
    "bg_card": "#26282c",
    "border": "#3c3f44",
    "text": "#e6e6e6",
    "text_dim": "#9aa0a6",
    "accent": "#4a9eff",
    "state_normal": "#3fb950",
    "state_warning": "#d2a106",
    "state_degraded": "#e07b39",
    "state_safe_mode": "#f2545b",
    "state_unknown": "#6e7681",
    "ok": "#3fb950",
    "bad": "#f2545b",
    "idle": "#6e7681",
    "table_alt": "#232529",
    "hover": "#5a5f66",
    "disabled": "#5c6066",
    "selection": "#2f4b6e",
}

PALETTES: Final[dict[str, dict[str, str]]] = {"light": LIGHT, "dark": DARK}

THEME_LABELS: Final[dict[str, str]] = {
    "light": "밝은 테마 (관제용)",
    "dark": "어두운 테마",
}

DEFAULT_THEME: Final[str] = "light"

_active: str = DEFAULT_THEME


class _ThemeProxy:
    """속성 접근 시점에 현재 팔레트를 조회한다.

    ``T.text_dim`` 은 항상 지금 적용된 테마의 값을 돌려준다.
    모듈 상수로 import 하는 것과 달리 런타임 교체가 반영된다.
    """

    __slots__ = ()

    def __getattr__(self, name: str) -> str:
        try:
            return PALETTES[_active][name]
        except KeyError:  # pragma: no cover - 오타 방지용
            raise AttributeError(f"테마에 없는 색 이름입니다: {name}") from None

    def __getitem__(self, name: str) -> str:
        return self.__getattr__(name)


T: Final[_ThemeProxy] = _ThemeProxy()


def theme_name() -> str:
    """현재 테마 키."""
    return _active


def theme_label(name: str | None = None) -> str:
    """사용자에게 보여줄 테마 이름."""
    key = name or _active
    return THEME_LABELS.get(key, key)


def set_theme(name: str) -> bool:
    """테마를 바꾼다. 실제로 바뀌었으면 ``True``.

    위젯 갱신은 하지 않는다. 호출자가 ``apply_theme()`` 순회를 해야 한다.
    """
    global _active
    if name not in PALETTES:
        return False
    if name == _active:
        return False
    _active = name
    return True


def connection_color(state_value: str) -> str:
    """연결 상태 문자열 -> 색. 팔레트를 따라간다."""
    table = {
        "DISCONNECTED": T.idle,
        "CONNECTING": T.state_warning,
        "CONNECTED": T.ok,
        "MOCK_CONNECTED": T.accent,
        "ERROR": T.bad,
    }
    return table.get(state_value, T.text_dim)


# --------------------------------------------------------------- 화살표 아이콘
#
# QSpinBox / QComboBox 를 스타일시트로 칠하면 Qt 가 그 위젯을 스타일시트
# 렌더링으로 전환하면서 **기본 ▲▼ 화살표를 그리지 않는다**. 배경만 지정해도
# 그렇다. 그래서 위아래 삼각형이 사라진 빈 네모만 남는다.
#
# Qt 스타일시트는 CSS 의 `border` 삼각형 트릭을 지원하지 않는다(실측: 네모로
# 렌더링됨). `image: url(...)` 만 통하므로 팔레트 색으로 삼각형 PNG 를 직접
# 그려 임시 폴더에 저장하고 그 경로를 물린다. 테마별로 한 번만 만든다.
#
_arrow_cache: dict[str, tuple[str, str]] = {}


def _draw_arrow(path: Path, color: str, *, down: bool, size: int = 9) -> None:
    from PySide6.QtCore import QPoint, Qt
    from PySide6.QtGui import QBrush, QColor, QPainter, QPixmap, QPolygon

    pixmap = QPixmap(size, size)
    pixmap.fill(Qt.GlobalColor.transparent)
    painter = QPainter(pixmap)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing)
    painter.setBrush(QBrush(QColor(color)))
    painter.setPen(Qt.PenStyle.NoPen)
    margin = 1
    if down:
        points = [
            QPoint(margin, margin + 1),
            QPoint(size - margin, margin + 1),
            QPoint(size // 2, size - margin),
        ]
    else:
        points = [
            QPoint(margin, size - margin - 1),
            QPoint(size - margin, size - margin - 1),
            QPoint(size // 2, margin),
        ]
    painter.drawPolygon(QPolygon(points))
    painter.end()
    pixmap.save(str(path))


def arrow_icons() -> tuple[str, str]:
    """현재 테마의 (위, 아래) 화살표 PNG 경로.

    QApplication 이 만들어진 뒤에 불러야 한다. 실패하면 빈 경로를 돌려주고
    호출자가 화살표 스타일을 생략한다 — 앱이 죽는 것보다 낫다.
    """
    cached = _arrow_cache.get(_active)
    if cached is not None:
        return cached
    try:
        base = Path(tempfile.gettempdir()) / "mission_soc_dashboard_icons"
        base.mkdir(parents=True, exist_ok=True)
        up = base / f"up_{_active}.png"
        down = base / f"down_{_active}.png"
        _draw_arrow(up, T.text, down=False)
        _draw_arrow(down, T.text, down=True)
        result = (up.as_posix(), down.as_posix())
    except Exception:  # pragma: no cover - QPixmap 사용 불가 환경
        result = ("", "")
    _arrow_cache[_active] = result
    return result


def app_qss() -> str:
    """QApplication 전역 스타일시트. 테마가 바뀔 때마다 다시 만든다."""
    up, down = arrow_icons()
    arrows = (
        f"""
QSpinBox::up-arrow {{ image:url({up}); width:9px; height:9px; }}
QSpinBox::down-arrow {{ image:url({down}); width:9px; height:9px; }}
QComboBox::down-arrow {{ image:url({down}); width:9px; height:9px; }}
"""
        if up and down
        else ""
    )
    return arrows + f"""
QWidget {{ background:{T.bg}; color:{T.text};
           font-family:'Noto Sans CJK KR','Malgun Gothic',sans-serif; font-size:12px; }}
/* 라벨이 자기 배경을 칠하면 흰 카드 위에 창 배경색 사각형이 찍힌다.
   어두운 테마에서는 bg 와 bg_card 가 비슷해 티가 안 났지만 밝은 테마에서는
   카드가 줄무늬처럼 보인다.
   QCheckBox 는 제외한다. 투명으로 두면 indicator 까지 배경을 잃어 네모가
   사라진다. 체크박스는 카드 위가 아니라 일반 배경 위에만 놓인다. */
QLabel {{ background:transparent; }}
QGroupBox {{ border:1px solid {T.border}; border-radius:6px;
             margin-top:10px; padding-top:8px; font-weight:700; }}
QGroupBox::title {{ subcontrol-origin:margin; left:10px; padding:0 4px;
                    color:{T.text_dim}; }}
/* 접이식 섹션 안에 들어간 그룹은 섹션 프레임이 이미 테두리를 그리므로
   자기 테두리를 지운다. 안 그러면 테두리가 이중으로 겹친다. */
QGroupBox#sectionBody {{ border:0; margin-top:0; padding-top:0; }}
QPushButton {{ background:{T.bg_alt}; border:1px solid {T.border};
               border-radius:4px; padding:5px 12px; }}
QPushButton:hover {{ border-color:{T.hover}; }}
QPushButton:disabled {{ color:{T.disabled}; }}
/* Fault Injection 체크박스는 시연 영상에서 "지금 뭘 눌렀는지"를 보여주는
   핵심 표시다. 플랫폼 기본 렌더링은 어두운 배경에서 네모가 묻히므로
   직접 그린다. 켜지면 accent 색으로 꽉 채워 멀리서도 구분된다. */
QCheckBox::indicator {{ width:13px; height:13px; border-radius:3px;
    border:1px solid {T.border}; background:{T.bg_card}; }}
QCheckBox::indicator:hover {{ border-color:{T.accent}; }}
QCheckBox::indicator:checked {{ background:{T.accent}; border-color:{T.accent}; }}
QCheckBox::indicator:disabled {{ border-color:{T.disabled};
    background:{T.bg_alt}; }}
QComboBox, QSpinBox, QLineEdit {{ background:{T.bg_alt};
    border:1px solid {T.border}; border-radius:4px; padding:3px 6px; }}
QLineEdit:focus, QComboBox:focus, QSpinBox:focus {{ border-color:{T.accent}; }}
/* 스핀박스 증감 버튼. 화살표 이미지는 위쪽 `arrows` 블록이 물린다. */
QSpinBox::up-button {{ subcontrol-origin:border; subcontrol-position:top right;
    width:17px; background:{T.bg_alt}; border-left:1px solid {T.border};
    border-top-right-radius:4px; }}
QSpinBox::down-button {{ subcontrol-origin:border; subcontrol-position:bottom right;
    width:17px; background:{T.bg_alt}; border-left:1px solid {T.border};
    border-top:1px solid {T.border}; border-bottom-right-radius:4px; }}
QSpinBox::up-button:hover, QSpinBox::down-button:hover {{ background:{T.selection}; }}
QComboBox::drop-down {{ subcontrol-origin:padding; subcontrol-position:top right;
    width:18px; border-left:1px solid {T.border}; }}
QTableWidget {{ background:{T.bg_card}; gridline-color:{T.border};
                alternate-background-color:{T.table_alt};
                selection-background-color:{T.selection};
                selection-color:{T.text}; }}
QHeaderView::section {{ background:{T.bg_alt}; border:0;
    border-bottom:1px solid {T.border}; padding:4px; font-weight:700; }}
QTabBar::tab {{ background:{T.bg_alt}; padding:6px 14px;
    border:1px solid {T.border}; border-bottom:0;
    border-top-left-radius:4px; border-top-right-radius:4px; }}
QTabBar::tab:selected {{ background:{T.bg}; font-weight:700;
    border-bottom:2px solid {T.accent}; }}
QScrollArea {{ border:0; }}
QToolButton {{ background:transparent; border:1px solid transparent;
               border-radius:4px; padding:3px 8px; }}
QToolButton:hover {{ border-color:{T.hover}; }}
QToolButton:checked {{ background:{T.bg_alt}; }}
QSplitter::handle {{ background:{T.border}; }}
QStatusBar {{ color:{T.text_dim}; border-top:1px solid {T.border}; }}
"""
