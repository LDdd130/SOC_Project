"""System State 대형 표시 카드."""

from __future__ import annotations

from datetime import datetime

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QFrame,
    QGridLayout,
    QLabel,
    QSizePolicy,
    QVBoxLayout,
)

from ..models import MissionStatus, SystemState
from ..theme import T
from ..state_mapper import (
    bool_text,
    fault_code_text,
    fault_device_text,
    fault_level_text,
    state_color,
    state_icon,
    state_korean,
)

__all__ = ["StateCard"]

#: 상세 항목 한 줄의 스타일. `{border}` 는 apply_theme 이 채운다.
#: 이름칸과 값칸 모두에 밑줄을 줘야 한 줄로 이어진다.
_ROW_NAME_CSS = (
    "font-size:12px; padding:5px 8px 5px 0;"
    " border-bottom:1px solid {border};"
)
_ROW_VALUE_CSS = (
    "font-size:12px; font-weight:600; padding:5px 24px 5px 0;"
    " border-bottom:1px solid {border};"
)

#: 전이 이력에 남길 상태 개수. NORMAL → WARNING → DEGRADED → NORMAL 한 사이클이
#: 4 개라 한 화면에 들어오도록 잡았다.
TRANSITION_KEEP = 5


class StateCard(QFrame):
    """현재 System State 와 Fault 요약을 크게 보여주는 카드."""

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self.setObjectName("stateCard")
        self.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred)

        # 테마 교체 시 다시 칠해야 하는 라벨들.
        # (위젯, 팔레트 키, 나머지 CSS 템플릿). 템플릿에는 `{border}` 같은
        # 자리표시자를 쓸 수 있고 apply_theme 이 현재 팔레트로 채운다.
        # 색을 미리 박아 두면 테마를 바꿔도 옛 색이 남는다.
        self._themed: list[tuple[QLabel, str, str]] = []
        #: 마지막으로 표시한 상태. 테마를 바꿔도 색을 되살리려면 기억해야 한다.
        self._state = SystemState.UNKNOWN

        root = QVBoxLayout(self)
        root.setContentsMargins(16, 12, 16, 12)
        root.setSpacing(8)

        title = QLabel("시스템 상태")
        self._themed.append((title, "text_dim", "font-size:12px;"))
        root.addWidget(title)

        # 아이콘 + 상태명을 함께 보여준다. 색상만으로 구분하지 않는다.
        self._state_label = QLabel("[ ? ] UNKNOWN")
        self._state_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._state_label.setStyleSheet("font-size:34px; font-weight:700;")
        root.addWidget(self._state_label)

        self._state_korean = QLabel("알 수 없음")
        self._state_korean.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._themed.append((self._state_korean, "text_dim", "font-size:13px;"))
        root.addWidget(self._state_korean)

        # 위의 큰 글씨는 $MISSION(500ms 주기) 기반이라 그보다 짧은 상태는 절대
        # 못 보여준다. 이 줄은 $EVENT,STATE_CHANGE 기반이라 유지 시간과 무관하게
        # 모든 전이가 남는다. push_transition() 주석 참조.
        self._transitions: list[str] = []
        self._transition_label = QLabel("")
        self._transition_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._transition_label.setWordWrap(True)
        self._themed.append((self._transition_label, "text_dim", "font-size:12px;"))
        self._transition_label.setTextInteractionFlags(
            Qt.TextInteractionFlag.TextSelectableByMouse
        )
        root.addWidget(self._transition_label)

        # 큰 글씨 블록과 상세 항목을 갈라 주는 가로선.
        self._divider = QFrame()
        self._divider.setFrameShape(QFrame.Shape.HLine)
        self._divider.setFixedHeight(1)
        root.addWidget(self._divider)

        # 항목마다 밑줄을 그어 구분한다. 가로 간격을 0 으로 둬야 이름칸과
        # 값칸의 밑줄이 이어져 한 줄로 보인다. 간격은 라벨 padding 으로 준다.
        grid = QGridLayout()
        grid.setHorizontalSpacing(0)
        grid.setVerticalSpacing(0)
        root.addLayout(grid)

        self._values: dict[str, QLabel] = {}
        fields = [
            ("고장 등급", "level"),
            ("고장 장치", "device"),
            ("고장 코드", "code"),
            ("FPGA Timestamp", "timestamp"),
            ("Actuator Enable", "actuator"),
            ("Control Valid", "control_valid"),
            ("Output Enable", "output_enable"),
            ("마지막 수신", "received"),
        ]
        for row, (label_text, key) in enumerate(fields):
            col = (row % 2) * 2
            line = row // 2
            name = QLabel(f"{label_text}:")
            self._themed.append((name, "text_dim", _ROW_NAME_CSS))
            value = QLabel("--")
            self._themed.append((value, "text", _ROW_VALUE_CSS))
            value.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
            grid.addWidget(name, line, col)
            grid.addWidget(value, line, col + 1)
            self._values[key] = value

        grid.setColumnStretch(1, 1)
        grid.setColumnStretch(3, 1)

        self.apply_theme()
        self.clear()

    # ------------------------------------------------------------------
    def apply_theme(self) -> None:
        """테마 교체 후 인라인 스타일을 다시 그린다.

        전역 QSS 로는 못 덮는 인라인 지정만 대상이다.
        마지막 상태(`self._state`)를 다시 칠해 색이 옛 테마로 남지 않게 한다.
        """
        self.setStyleSheet(
            f"#stateCard {{ background:{T.bg_card};"
            f" border:1px solid {T.border}; border-radius:8px; }}"
        )
        self._divider.setStyleSheet(f"background:{T.border}; border:0;")
        for widget, key, extra in self._themed:
            widget.setStyleSheet(
                f"color:{T[key]}; " + extra.format(border=T.border)
            )
        self._apply_state(self._state)

    def clear(self) -> None:
        """수신 전 초기 표시."""
        self._apply_state(SystemState.UNKNOWN)
        for label in self._values.values():
            label.setText("--")
        self._transitions.clear()
        self._transition_label.setText("최근 전이: --")

    def push_transition(self, state_name: str, when: datetime) -> None:
        """`$EVENT,...,STATE_CHANGE,<state>` 한 건을 이력에 남긴다.

        큰 글씨(`update_status`)는 `$MISSION` 을 받아 갱신하므로 그 주기
        (500ms)보다 짧게 스쳐 가는 상태는 구조적으로 표시할 수 없다.
        `eval_tick` 이 1ms 라 `PERSIST_LIMIT=5` 면 WARNING 이 5ms 만
        유지되고, 255 로 올려도 255ms < 500ms 라 여전히 못 잡는다.

        반면 `STATE_CHANGE` 는 하드웨어가 전이 시점에 올린 IRQ 로 만들어져
        유지 시간과 무관하게 전부 도착한다. 그래서 이 줄만 보면 순간
        상태까지 눈으로 확인할 수 있다.

        표시만 하고 큰 글씨는 건드리지 않는다. 큰 글씨는 "지금 상태"를
        말해야 하는데, 이미 지나간 전이로 덮어쓰면 거짓말이 된다.
        """
        self._transitions.append(state_name)
        del self._transitions[:-TRANSITION_KEEP]
        trail = " → ".join(self._transitions)
        self._transition_label.setText(
            f"최근 전이: {trail}  ({when.strftime('%H:%M:%S.%f')[:-3]})"
        )

    def _apply_state(self, state: SystemState) -> None:
        self._state = state
        color = state_color(state)
        self._state_label.setText(f"{state_icon(state)} {state.value}")
        self._state_label.setStyleSheet(
            f"font-size:34px; font-weight:700; color:{color};"
        )
        self._state_korean.setText(state_korean(state))

    def update_status(self, status: MissionStatus) -> None:
        """새 상태를 반영한다. 수신값을 그대로 표시한다."""
        self._apply_state(status.system_state)
        self._values["level"].setText(fault_level_text(status.fault_level))
        self._values["device"].setText(fault_device_text(status.fault_device))
        self._values["code"].setText(fault_code_text(status.fault_code))
        self._values["timestamp"].setText(f"{status.timestamp_ms} ms")
        self._values["actuator"].setText(
            bool_text(status.actuator_enable, true_text="ENABLED", false_text="DISABLED")
        )
        self._values["control_valid"].setText(
            bool_text(status.control_valid, true_text="VALID", false_text="INVALID")
        )
        self._values["output_enable"].setText(
            f"0b{status.output_enable_mask:03b} (0x{status.output_enable_mask:02X})"
        )
        self._values["received"].setText(
            status.received_at.strftime("%H:%M:%S.%f")[:-3]
        )

    def set_stale(self, last_seen: datetime | None) -> None:
        """수신이 끊긴 상태 표시."""
        if last_seen is None:
            self._values["received"].setText("--")
        else:
            elapsed = (datetime.now() - last_seen).total_seconds()
            self._values["received"].setText(
                f"{last_seen.strftime('%H:%M:%S')} ({elapsed:.0f}초 전)"
            )
