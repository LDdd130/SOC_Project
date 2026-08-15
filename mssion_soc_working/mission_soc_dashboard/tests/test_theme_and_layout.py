"""테마 교체 · 화면 확대 · 접이식 섹션 회귀 테스트.

여기서 막는 버그:

1. **옛 테마 색이 남는다**
   위젯이 계산된 hex 를 캐시해 두고 `apply_theme()` 에서 그대로 다시 칠하면,
   테마를 바꿔도 이전 팔레트 색이 화면에 남는다. DeviceCard 가 실제로 이랬다.
   색이 아니라 **상태**를 기억하고 색은 매번 다시 계산해야 한다.

2. **확대 후 복원이 안 된다**
   스플리터 비율을 저장하지 않고 감췄다 되돌리면 배치가 무너진다.

3. **접이식 섹션이 레이아웃 순서를 바꾼다**
   감싸는 과정에서 위젯이 맨 뒤로 밀리면 화면 구성이 달라진다.
"""

from __future__ import annotations

import os
from datetime import datetime

import pytest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

pytest.importorskip("PySide6")

from PySide6.QtWidgets import QApplication  # noqa: E402

from mission_dashboard import theme  # noqa: E402
from mission_dashboard.models import (  # noqa: E402
    ConnectionState,
    DeviceStatus,
    LogRow,
)
from mission_dashboard.protocol import parse_line  # noqa: E402
from mission_dashboard.state_mapper import state_color  # noqa: E402


@pytest.fixture(scope="module")
def qapp():
    app = QApplication.instance() or QApplication([])
    yield app


@pytest.fixture
def window(qapp, tmp_path, monkeypatch):
    # 설정 파일을 건드리지 않도록 홈을 격리한다
    monkeypatch.setenv("HOME", str(tmp_path))
    theme.set_theme(theme.DEFAULT_THEME)
    from mission_dashboard.main_window import MainWindow

    win = MainWindow()
    yield win
    win.close()


def _populate(win) -> None:
    """동적 색이 실제로 칠해지도록 데이터를 흘려 넣는다."""
    result = parse_line("$MISSION,272600,SAFE_MODE,3,3,4,0x06,0x01,0x00,1,0,1,0,0,0")
    win.state_card.update_status(result.status)
    for i, card in enumerate(win.device_cards):
        card.update_device(
            DeviceStatus(
                index=i,
                alive=(i != 0),
                timeout=(i == 0),
                output_enabled=False,
                is_fault_target=True,
                fault_count=3,
            )
        )
    win.control_panel.update_irq(parse_line("$IRQ,0x00,0x00,0x01,0x01").irq)
    win.serial_panel.set_connection_state(ConnectionState.CONNECTED)
    win.event_table.add_row(
        LogRow(
            received_at=datetime.now(),
            timestamp_ms=1,
            raw_line="$ERR,MANUAL_RESET,FAULT_ACTIVE",
            message_type="ERR",
            is_error=True,
            is_event=False,
        )
    )


def _stale_hits(win, other_palette: dict[str, str]) -> list[str]:
    """반대 테마의 색이 인라인 스타일에 남아 있는지 훑는다."""
    bad = {v.lower() for v in other_palette.values()}
    hits: list[str] = []
    for widget in win.findChildren(object):
        try:
            sheet = widget.styleSheet()
        except Exception:  # pragma: no cover - 스타일시트 없는 객체
            continue
        if not sheet:
            continue
        lowered = sheet.lower()
        hits += [f"{type(widget).__name__}:{c}" for c in bad if c in lowered]
    return hits


def _switch(win, key: str) -> None:
    win.theme_combo.setCurrentIndex(win.theme_combo.findData(key))


# ------------------------------------------------------------------- 테마 교체
def test_default_theme_is_light() -> None:
    assert theme.DEFAULT_THEME == "light"


def test_theme_proxy_follows_active_palette() -> None:
    theme.set_theme("light")
    light_bg = theme.T.bg
    theme.set_theme("dark")
    assert theme.T.bg != light_bg
    assert theme.T.bg == theme.DARK["bg"]
    theme.set_theme("light")
    assert theme.T.bg == light_bg


def test_state_color_follows_theme() -> None:
    from mission_dashboard.models import SystemState

    theme.set_theme("light")
    light = state_color(SystemState.SAFE_MODE)
    theme.set_theme("dark")
    assert state_color(SystemState.SAFE_MODE) != light
    theme.set_theme("light")


def test_switching_theme_leaves_no_stale_colors(window) -> None:
    """반복 교체해도 이전 팔레트 색이 남으면 안 된다."""
    _populate(window)

    for key in ("dark", "light", "dark", "light"):
        _switch(window, key)
        other = theme.LIGHT if key == "dark" else theme.DARK
        assert _stale_hits(window, other) == [], f"{key} 전환 후 잔존 색 발견"


def test_table_row_color_follows_theme(window) -> None:
    """행 글자색은 QSS 가 아니라 아이템에 박혀서 재빌드가 필요하다."""
    _populate(window)

    _switch(window, "dark")
    assert window.event_table.table.item(0, 0).foreground().color().name() == (
        theme.DARK["bad"]
    )

    _switch(window, "light")
    assert window.event_table.table.item(0, 0).foreground().color().name() == (
        theme.LIGHT["bad"]
    )


def test_theme_choice_is_persisted(window) -> None:
    _switch(window, "dark")
    assert window.settings.get("theme") == "dark"
    _switch(window, "light")
    assert window.settings.get("theme") == "light"


def test_device_card_recomputes_color_instead_of_replaying(window) -> None:
    """DeviceCard 가 색이 아니라 상태를 기억하는지 직접 확인한다."""
    card = window.device_cards[0]
    card.update_device(
        DeviceStatus(
            index=0,
            alive=False,
            timeout=True,
            output_enabled=False,
            is_fault_target=True,
            fault_count=1,
        )
    )
    _switch(window, "dark")
    assert theme.DARK["bad"] in card._values["alive"].styleSheet()
    _switch(window, "light")
    assert theme.LIGHT["bad"] in card._values["alive"].styleSheet()


# ------------------------------------------------------------------ 화면 확대
def test_maximize_hides_surroundings_and_restores(window) -> None:
    # 창을 show() 하지 않으면 isVisible() 은 항상 False 다.
    # 여기서 볼 것은 "명시적으로 감췄는가" 이므로 isHidden() 을 쓴다.
    before = window.splitter.sizes()

    window._toggle_maximize()
    assert window.serial_panel.isHidden()
    assert window.state_card.isHidden()
    assert window.device_box.isHidden()
    assert window.right_pane.isHidden()
    assert not window.left_tabs.isHidden()

    window._toggle_maximize()
    assert not window.serial_panel.isHidden()
    assert not window.state_card.isHidden()
    assert not window.device_box.isHidden()
    assert not window.right_pane.isHidden()
    assert window.splitter.sizes() == before


def test_maximize_button_label_tracks_state(window) -> None:
    assert "확대" in window.maximize_btn.text()
    window._toggle_maximize()
    assert "복원" in window.maximize_btn.text()
    window._toggle_maximize()
    assert "확대" in window.maximize_btn.text()


def test_maximize_is_idempotent_across_repeats(window) -> None:
    before = window.splitter.sizes()
    for _ in range(3):
        window._toggle_maximize()
        window._toggle_maximize()
    assert window.splitter.sizes() == before
    assert not window.right_pane.isHidden()


# --------------------------------------------------------------- 접이식 섹션
def test_irq_section_starts_collapsed(window) -> None:
    section = window._sections["irq"]
    assert not section.is_expanded()
    assert section._frame.isHidden()
    assert "접힘" in section._header.text()


def test_irq_section_expands_and_persists(window) -> None:
    section = window._sections["irq"]

    section._on_clicked(True)
    assert section.is_expanded()
    assert not section._frame.isHidden()
    assert window.settings.get("sections")["irq"] is True

    section._on_clicked(False)
    assert not section.is_expanded()
    assert window.settings.get("sections")["irq"] is False


def test_wrapping_keeps_layout_order(window) -> None:
    """섹션으로 감싸도 원래 자리를 지켜야 한다.

    IRQ 는 설정 레지스터 · 제어 명령 다음 세 번째 자리다.
    """
    layout = window.control_panel.layout()
    section = window._sections["irq"]
    assert layout.indexOf(section) == 2


def test_collapsed_section_still_reachable_by_widget(window) -> None:
    """접혀 있어도 위젯 자체는 살아 있어 명령 전송에 영향이 없어야 한다."""
    section = window._sections["irq"]
    assert not section.is_expanded()

    sent: list[int] = []
    window.control_panel.irq_en_requested.connect(sent.append)
    window.control_panel._on_apply_irq_en()
    assert sent == [window.control_panel.current_irq_en_mask()]


# ------------------------------------------------------- 스핀박스 화살표 / 대비
def _luma(hex_color: str) -> float:
    """대충의 상대 밝기. 대비 비교용이라 정밀할 필요는 없다."""
    h = hex_color.lstrip("#")
    r, g, b = (int(h[i : i + 2], 16) for i in (0, 2, 4))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def test_spinbox_arrows_are_styled(qapp) -> None:
    """QSS 로 QSpinBox 를 칠하면 Qt 가 기본 ▲▼ 를 안 그린다.

    직접 만든 이미지를 물려야 화살표가 살아난다. Qt 는 CSS 의 border 삼각형
    트릭을 지원하지 않아(실측: 네모로 렌더링) 이미지 외에 방법이 없다.
    """
    for key in ("light", "dark"):
        theme.set_theme(key)
        qss = theme.app_qss()
        assert "QSpinBox::up-arrow" in qss
        assert "QSpinBox::down-arrow" in qss
        assert "QSpinBox::up-button" in qss
        assert "image:url(" in qss.replace(" ", "")
    theme.set_theme("light")


def test_arrow_icons_exist_and_differ_per_theme(qapp, tmp_path) -> None:
    from pathlib import Path

    theme.set_theme("light")
    light_up, light_down = theme.arrow_icons()
    theme.set_theme("dark")
    dark_up, dark_down = theme.arrow_icons()
    theme.set_theme("light")

    for path in (light_up, light_down, dark_up, dark_down):
        assert path, "화살표 아이콘 생성 실패"
        assert Path(path).is_file()

    # 테마마다 글자색이 달라 파일이 달라야 한다
    assert light_up != dark_up
    assert Path(light_up).read_bytes() != Path(dark_up).read_bytes()


def test_light_border_is_visible_against_card(qapp) -> None:
    """흰 카드 위에서 테두리가 보여야 한다.

    처음 팔레트(border #c3cad4)는 대비가 모자라 구분선이 사라진 것처럼 보였다.
    """
    delta = _luma(theme.LIGHT["bg_card"]) - _luma(theme.LIGHT["border"])
    assert delta > 60, f"밝은 테마 테두리 대비 부족: {delta:.1f}"


def test_light_card_stands_out_from_background(qapp) -> None:
    delta = _luma(theme.LIGHT["bg_card"]) - _luma(theme.LIGHT["bg"])
    assert delta > 10, f"카드와 배경 대비 부족: {delta:.1f}"


# ------------------------------------------------------------- 항목 구분선
def test_state_card_rows_have_dividers(window) -> None:
    """항목마다 밑줄이 있어야 한다.

    예전 어두운 테마에서는 `QWidget { background }` 가 QLabel 까지 칠하는 바람에
    라벨마다 카드와 다른 색 사각형이 생겨 **우연히** 칸처럼 보였다.
    라벨을 투명하게 바꾸면서 그 효과가 사라졌으므로 실제 선을 그어야 한다.
    """
    card = window.state_card
    for label in card._values.values():
        assert "border-bottom" in label.styleSheet()


def test_state_card_has_block_divider(window) -> None:
    assert window.state_card._divider is not None
    assert theme.T.border in window.state_card._divider.styleSheet()


def test_device_card_rows_have_dividers(window) -> None:
    card = window.device_cards[0]
    for label in card._values.values():
        assert "border-bottom" in label.styleSheet()


def test_row_dividers_follow_theme(window) -> None:
    """구분선 색도 테마를 따라가야 한다. 색을 템플릿에 박으면 옛 색이 남는다."""
    card = window.state_card

    _switch(window, "dark")
    assert theme.DARK["border"] in card._values["level"].styleSheet()
    assert theme.LIGHT["border"] not in card._values["level"].styleSheet()

    _switch(window, "light")
    assert theme.LIGHT["border"] in card._values["level"].styleSheet()
    assert theme.DARK["border"] not in card._values["level"].styleSheet()


def test_device_card_value_divider_survives_updates(window) -> None:
    """값이 갱신돼도 구분선이 지워지면 안 된다."""
    card = window.device_cards[1]
    card.update_device(
        DeviceStatus(
            index=1,
            alive=False,
            timeout=True,
            output_enabled=False,
            is_fault_target=True,
            fault_count=7,
        )
    )
    for label in card._values.values():
        assert "border-bottom" in label.styleSheet()
