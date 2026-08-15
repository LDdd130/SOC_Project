"""접었다 펼 수 있는 섹션.

시연에서 매번 쓰지는 않지만 검증에는 필요한 블록(IRQ 상태 등)을 접어두고
필요할 때만 펼치기 위한 컨테이너다. 접힌 상태에서는 내용 위젯이
``hide()`` 되므로 레이아웃 높이를 차지하지 않는다.

접힘 여부는 :class:`~mission_dashboard.settings_manager.SettingsManager` 가
아니라 MainWindow 가 모아서 저장한다. 여기서는 상태만 노출한다.
"""

from __future__ import annotations

from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import (
    QFrame,
    QSizePolicy,
    QToolButton,
    QVBoxLayout,
    QWidget,
)

from ..theme import T

__all__ = ["CollapsibleSection"]


class CollapsibleSection(QWidget):
    """제목 줄을 누르면 내용이 접히고 펴지는 섹션.

    Args:
        title: 제목 줄에 표시할 문구.
        content: 안에 넣을 위젯. 소유권을 가져간다.
        expanded: 처음에 펼친 상태로 둘지.
        hint: 제목 아래 회색 한 줄 설명. 접힌 상태에서도 보인다.

    Signals:
        toggled(bool): 펼침 상태가 바뀌었을 때. ``True`` 면 펼쳐짐.
    """

    toggled = Signal(bool)

    def __init__(
        self,
        title: str,
        content: QWidget,
        *,
        expanded: bool = False,
        hint: str = "",
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)

        self._title = title
        self._hint = hint
        self._content = content

        root = QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        self._header = QToolButton()
        self._header.setCheckable(True)
        self._header.setChecked(expanded)
        self._header.setToolButtonStyle(Qt.ToolButtonStyle.ToolButtonTextBesideIcon)
        self._header.setArrowType(
            Qt.ArrowType.DownArrow if expanded else Qt.ArrowType.RightArrow
        )
        self._header.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed
        )
        self._header.setCursor(Qt.CursorShape.PointingHandCursor)
        self._header.clicked.connect(self._on_clicked)
        root.addWidget(self._header)

        self._frame = QFrame()
        self._frame.setObjectName("collapsibleBody")
        frame_layout = QVBoxLayout(self._frame)
        frame_layout.setContentsMargins(8, 8, 8, 8)
        frame_layout.addWidget(content)
        root.addWidget(self._frame)

        self._frame.setVisible(expanded)
        self.apply_theme()

    # ------------------------------------------------------------------
    def _on_clicked(self, checked: bool) -> None:
        self.set_expanded(checked)
        self.toggled.emit(checked)

    def set_expanded(self, expanded: bool) -> None:
        """펼침 상태를 바꾼다. 시그널은 내보내지 않는다."""
        self._header.setChecked(expanded)
        self._header.setArrowType(
            Qt.ArrowType.DownArrow if expanded else Qt.ArrowType.RightArrow
        )
        self._frame.setVisible(expanded)
        self._refresh_header_text()

    def is_expanded(self) -> bool:
        return self._header.isChecked()

    # ------------------------------------------------------------------
    def _refresh_header_text(self) -> None:
        suffix = "" if self.is_expanded() else "  (접힘)"
        self._header.setText(f"{self._title}{suffix}")
        if self._hint:
            self._header.setToolTip(self._hint)

    def apply_theme(self) -> None:
        """테마 교체 후 인라인 스타일을 다시 그린다."""
        self._header.setStyleSheet(
            f"QToolButton {{ color:{T.text}; font-weight:700; font-size:12px;"
            f" text-align:left; padding:6px 4px;"
            f" border:0; border-bottom:1px solid {T.border}; }}"
            f"QToolButton:hover {{ color:{T.accent}; }}"
        )
        self._frame.setStyleSheet(
            f"#collapsibleBody {{ background:{T.bg_card};"
            f" border:1px solid {T.border}; border-top:0;"
            f" border-bottom-left-radius:6px; border-bottom-right-radius:6px; }}"
        )
        self._refresh_header_text()
        inner = getattr(self._content, "apply_theme", None)
        if callable(inner):
            inner()
