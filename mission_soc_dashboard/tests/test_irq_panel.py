"""IRQ 패널 GUI 회귀 테스트.

여기서 막는 버그 (2026-07-31 보드 시험 중 발견):

1. **무한 피드백 루프**
   `update_irq()` 가 안내 문구 갱신 함수를 부르는데 그 함수가
   `irq_en_requested` 를 emit 했다. 그래서
   `$IRQ` 수신 -> emit -> `SET,IRQ_EN` + `GET,IRQ` -> 보드가 `$IRQ` 응답 ->
   다시 emit 이 끝없이 돌았다. 9600bps 링크가 포화돼 앱이 버벅였다.

2. **늦게 온 응답이 체크박스를 되돌림**
   체크박스마다 자동 전송을 걸어서, 3개를 푸는 동안 `SET` 이 3번 나갔다
   (0x06 -> 0x04 -> 0x00). 9600bps 라 첫 응답 `$IRQ,0x06,...` 이 한참 뒤에
   도착해 이미 다 푼 체크박스를 도로 켰다. "체크박스가 혼자 깜빡인다".

지금 구조:
    체크박스 = 보내려는 값 (전송 안 함)
    `IRQ_EN 적용` 버튼 = 전송 (1회)
    `$IRQ` 수신 = Pending 램프 + `보드 실제값` 칸만 갱신, 체크박스는 안 건드림
"""

from __future__ import annotations

import os

import pytest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

pytest.importorskip("PySide6")

from PySide6.QtWidgets import QApplication  # noqa: E402

from mission_dashboard.constants import IRQ_EN_ALL, IRQ_SOURCES  # noqa: E402
from mission_dashboard.protocol import parse_line  # noqa: E402
from mission_dashboard.widgets.control_panel import ControlPanel  # noqa: E402


@pytest.fixture(scope="module")
def qapp():
    app = QApplication.instance() or QApplication([])
    yield app


@pytest.fixture
def panel(qapp):
    widget = ControlPanel()
    sent: list[int] = []
    widget.irq_en_requested.connect(sent.append)
    widget._sent_masks = sent  # 테스트에서 꺼내 쓴다
    return widget


def _irq(line: str):
    result = parse_line(line)
    assert result.success and result.irq is not None
    return result.irq


def _checked(panel: ControlPanel) -> dict[str, bool]:
    return {key: panel._irq_en_boxes[key].isChecked() for key, _t, _b in IRQ_SOURCES}


# ------------------------------------------------------- 체크박스는 전송 안 함
def test_unchecking_boxes_sends_nothing(panel: ControlPanel) -> None:
    for key, _title, _bit in IRQ_SOURCES:
        panel._irq_en_boxes[key].setChecked(False)

    assert panel._sent_masks == []
    assert panel.current_irq_en_mask() == 0


def test_apply_button_sends_once(panel: ControlPanel) -> None:
    for key, _title, _bit in IRQ_SOURCES:
        panel._irq_en_boxes[key].setChecked(False)
    panel._on_apply_irq_en()

    assert panel._sent_masks == [0]


def test_apply_sends_current_mask(panel: ControlPanel) -> None:
    panel._irq_en_boxes["fm"].setChecked(False)
    panel._on_apply_irq_en()

    assert panel._sent_masks == [IRQ_EN_ALL & ~0x2]


# ------------------------------------------------------------ 피드백 루프 방지
def test_update_irq_never_emits(panel: ControlPanel) -> None:
    """`$IRQ` 를 아무리 받아도 전송이 유발되면 안 된다."""
    for _ in range(50):
        panel.update_irq(_irq("$IRQ,0x00,0x00,0x01,0x01"))

    assert panel._sent_masks == []


def test_update_irq_does_not_touch_checkboxes(panel: ControlPanel) -> None:
    for key, _title, _bit in IRQ_SOURCES:
        panel._irq_en_boxes[key].setChecked(False)

    panel.update_irq(_irq("$IRQ,0x07,0x00,0x00,0x00"))

    assert _checked(panel) == {"hb": False, "fm": False, "sc": False}


def test_stale_reply_does_not_flip_checkboxes(panel: ControlPanel) -> None:
    """늦게 도착한 중간 상태(0x06)가 조작 결과를 되돌리면 안 된다."""
    for key, _title, _bit in IRQ_SOURCES:
        panel._irq_en_boxes[key].setChecked(False)
    panel._on_apply_irq_en()

    panel.update_irq(_irq("$IRQ,0x06,0x00,0x00,0x00"))
    assert _checked(panel) == {"hb": False, "fm": False, "sc": False}

    panel.update_irq(_irq("$IRQ,0x04,0x00,0x00,0x00"))
    assert _checked(panel) == {"hb": False, "fm": False, "sc": False}


# ------------------------------------------------------------------ 표시 갱신
def test_actual_column_follows_board(panel: ControlPanel) -> None:
    panel.update_irq(_irq("$IRQ,0x05,0x00,0x00,0x00"))

    assert panel._irq_actual_labels["hb"].text() == "ON"
    assert panel._irq_actual_labels["fm"].text() == "OFF"
    assert panel._irq_actual_labels["sc"].text() == "ON"


def test_pending_lamps_show_value(panel: ControlPanel) -> None:
    panel.update_irq(_irq("$IRQ,0x00,0x02,0x01,0x00"))

    assert "0x02" in panel._irq_pending_labels["hb"].text()
    assert "0x01" in panel._irq_pending_labels["fm"].text()
    assert "0x00" in panel._irq_pending_labels["sc"].text()


def test_note_warns_on_pending(panel: ControlPanel) -> None:
    panel.update_irq(_irq("$IRQ,0x00,0x00,0x01,0x01"))
    assert "Pending" in panel.irq_note.text()


def test_note_warns_on_mismatch(panel: ControlPanel) -> None:
    panel._irq_en_boxes["fm"].setChecked(False)
    panel.update_irq(_irq("$IRQ,0x07,0x00,0x00,0x00"))

    assert "다릅니다" in panel.irq_note.text()


def test_note_warns_while_irq_en_off(panel: ControlPanel) -> None:
    """체크박스와 보드가 일치해도 IRQ_EN 이 꺼져 있으면 계속 경고한다.

    15-7 원복을 빠뜨리면 이후 시험에서 짧은 WARNING 을 놓치기 때문이다.
    """
    for key, _title, _bit in IRQ_SOURCES:
        panel._irq_en_boxes[key].setChecked(False)
    panel.update_irq(_irq("$IRQ,0x00,0x00,0x00,0x00"))

    assert "IRQ_EN=0b000" in panel.irq_note.text()


def test_note_returns_to_normal_after_restore(panel: ControlPanel) -> None:
    for key, _title, _bit in IRQ_SOURCES:
        panel._irq_en_boxes[key].setChecked(False)
    panel.update_irq(_irq("$IRQ,0x00,0x00,0x01,0x01"))
    assert "Pending" in panel.irq_note.text()

    for key, _title, _bit in IRQ_SOURCES:
        panel._irq_en_boxes[key].setChecked(True)
    panel.update_irq(_irq("$IRQ,0x07,0x00,0x00,0x00"))

    assert "평상시" in panel.irq_note.text()
    assert panel._sent_masks == []
