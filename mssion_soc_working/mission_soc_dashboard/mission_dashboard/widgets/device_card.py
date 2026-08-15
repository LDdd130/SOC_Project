"""Device 0~2 상태 카드."""

from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QFrame, QGridLayout, QLabel, QVBoxLayout

from ..constants import DEVICE_CRITICALITY
from ..models import DeviceStatus
from ..state_mapper import bool_color, bool_text, device_title
from ..theme import T

__all__ = ["DeviceCard"]

#: 항목 한 줄의 스타일. `{border}` 는 apply_theme / _set 이 채운다.
#: 이름칸과 값칸 양쪽에 밑줄을 줘야 한 줄로 이어져 보인다.
_ROW_NAME_CSS = "font-size:11px; padding:4px 0; border-bottom:1px solid {border};"
_ROW_VALUE_CSS = (
    "font-size:11px; font-weight:700; padding:4px 0;"
    " border-bottom:1px solid {border};"
)


class DeviceCard(QFrame):
    """장치 하나의 Alive/Timeout/Output Enable/Fault 표시."""

    def __init__(self, index: int, parent=None) -> None:
        super().__init__(parent)
        self.index = index
        self.setObjectName("deviceCard")

        # 테마 교체 시 다시 칠할 라벨들.
        # (위젯, 팔레트 키, CSS 템플릿). `{border}` 는 칠할 때 채운다.
        self._themed: list[tuple[QLabel, str, str]] = []
        #: 마지막으로 표시한 장치 상태.
        #: 색이 아니라 **상태**를 기억해야 한다. 색을 기억하면 테마를 바꿔도
        #: 옛 팔레트의 hex 를 그대로 다시 칠하게 된다.
        self._last: DeviceStatus | None = None

        root = QVBoxLayout(self)
        root.setContentsMargins(12, 10, 12, 10)
        root.setSpacing(6)

        title = QLabel(device_title(index))
        self._themed.append((title, "text", "font-size:12px; font-weight:700;"))
        self._title = title
        title.setWordWrap(True)
        root.addWidget(title)

        criticality = (
            DEVICE_CRITICALITY[index] if index < len(DEVICE_CRITICALITY) else "-"
        )
        sub = QLabel(f"중요도: {criticality}")
        self._themed.append(
            (sub, "text_dim",
             "font-size:11px; padding-bottom:5px;"
             " border-bottom:1px solid {border};")
        )
        root.addWidget(sub)

        # 항목마다 밑줄. 가로 간격 0 이어야 이름칸/값칸 밑줄이 이어진다.
        grid = QGridLayout()
        grid.setHorizontalSpacing(0)
        grid.setVerticalSpacing(0)
        root.addLayout(grid)

        self._values: dict[str, QLabel] = {}
        rows = [
            ("Alive", "alive"),
            ("Timeout", "timeout"),
            ("Output Enable", "output"),
            ("Fault 대상", "fault_target"),
            ("Fault Count", "count"),
        ]
        for row, (label_text, key) in enumerate(rows):
            name = QLabel(f"{label_text}:")
            self._themed.append((name, "text_dim", _ROW_NAME_CSS))
            value = QLabel("--")
            value.setAlignment(
                Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter
            )
            grid.addWidget(name, row, 0)
            grid.addWidget(value, row, 1)
            self._values[key] = value

        grid.setColumnStretch(0, 1)
        self.apply_theme()
        self.clear()

    # ------------------------------------------------------------------
    def apply_theme(self) -> None:
        """테마 교체 후 인라인 스타일을 다시 그린다.

        값 라벨은 저장해 둔 색을 다시 칠하면 안 된다. 그 색은 이전 테마에서
        뽑은 hex 라, 그대로 쓰면 새 테마 위에 옛 색이 남는다.
        마지막 상태로부터 색을 **다시 계산**한다.
        """
        self.setStyleSheet(
            f"#deviceCard {{ background:{T.bg_card};"
            f" border:1px solid {T.border}; border-radius:8px; }}"
        )
        for widget, key, extra in self._themed:
            widget.setStyleSheet(
                f"color:{T[key]}; " + extra.format(border=T.border)
            )
        if self._last is None:
            self.clear()
        else:
            self.update_device(self._last)

    def clear(self) -> None:
        self._last = None
        for label in self._values.values():
            label.setText("--")
            label.setStyleSheet(self._value_css(T.idle))

    @staticmethod
    def _value_css(color: str) -> str:
        return f"color:{color}; " + _ROW_VALUE_CSS.format(border=T.border)

    def _set(self, key: str, text: str, color: str) -> None:
        label = self._values[key]
        label.setText(text)
        label.setStyleSheet(self._value_css(color))

    def update_device(self, device: DeviceStatus) -> None:
        """장치 상태를 반영한다."""
        self._last = device
        self._set(
            "alive",
            bool_text(device.alive, true_text="ALIVE", false_text="DOWN"),
            bool_color(device.alive),
        )
        # Timeout 은 True 가 나쁜 의미라 invert
        self._set(
            "timeout",
            bool_text(device.timeout, true_text="TIMEOUT", false_text="정상"),
            bool_color(device.timeout, invert=True),
        )
        self._set(
            "output",
            bool_text(device.output_enabled, true_text="ENABLED", false_text="DISABLED"),
            bool_color(device.output_enabled),
        )
        self._set(
            "fault_target",
            bool_text(device.is_fault_target, true_text="예", false_text="아니오"),
            bool_color(device.is_fault_target, invert=True),
        )
        count_text = "--" if device.fault_count is None else str(device.fault_count)
        self._set("count", count_text, T.text)
