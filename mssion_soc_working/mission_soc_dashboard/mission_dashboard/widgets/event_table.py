"""Event Log 테이블 위젯."""

from __future__ import annotations

from collections import deque

from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QColor
from PySide6.QtWidgets import (
    QAbstractItemView,
    QCheckBox,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QPushButton,
    QSpinBox,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from ..constants import (
    DEFAULT_MAX_LOG_ROWS,
    MAX_LOG_ROWS_LIMIT,
)
from ..models import LogRow
from ..theme import T

__all__ = ["EventTable"]

_COLUMNS = (
    "PC 수신 시각",
    "FPGA ts",
    "Type",
    "Event",
    "State",
    "Level",
    "Device",
    "Code",
    "설명",
    "Raw Message",
)


class EventTable(QWidget):
    """수신 메시지 로그 테이블.

    최대 표시 행을 넘으면 오래된 행을 지운다. CSV Export 는
    표시된 행이 아니라 내부 보관 목록(`rows`)을 대상으로 한다.

    Signals:
        export_requested: CSV 저장 버튼 클릭.
    """

    export_requested = Signal()

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self._max_rows = DEFAULT_MAX_LOG_ROWS
        self.rows: deque[LogRow] = deque(maxlen=MAX_LOG_ROWS_LIMIT)

        root = QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(6)

        # -- 툴바 ---------------------------------------------------------
        bar = QHBoxLayout()
        bar.setSpacing(8)

        self.auto_scroll = QCheckBox("자동 스크롤")
        self.auto_scroll.setChecked(True)
        bar.addWidget(self.auto_scroll)

        self.errors_only = QCheckBox("Error만")
        self.errors_only.stateChanged.connect(self._rebuild)
        bar.addWidget(self.errors_only)

        self.events_only = QCheckBox("Event만")
        self.events_only.stateChanged.connect(self._rebuild)
        bar.addWidget(self.events_only)

        bar.addWidget(QLabel("최대 행:"))
        self.max_rows_spin = QSpinBox()
        self.max_rows_spin.setRange(100, MAX_LOG_ROWS_LIMIT)
        self.max_rows_spin.setSingleStep(500)
        self.max_rows_spin.setValue(DEFAULT_MAX_LOG_ROWS)
        self.max_rows_spin.valueChanged.connect(self.set_max_rows)
        bar.addWidget(self.max_rows_spin)

        bar.addStretch(1)

        self._count_label = QLabel("0 행")
        bar.addWidget(self._count_label)

        clear_btn = QPushButton("로그 지우기")
        clear_btn.clicked.connect(self.clear_rows)
        bar.addWidget(clear_btn)

        export_btn = QPushButton("CSV 저장")
        export_btn.clicked.connect(self.export_requested.emit)
        bar.addWidget(export_btn)

        root.addLayout(bar)

        # -- 테이블 -------------------------------------------------------
        self.table = QTableWidget(0, len(_COLUMNS))
        self.table.setHorizontalHeaderLabels(list(_COLUMNS))
        self.table.verticalHeader().setVisible(False)
        self.table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        self.table.setSelectionBehavior(
            QAbstractItemView.SelectionBehavior.SelectRows
        )
        self.table.setAlternatingRowColors(True)
        self.table.setWordWrap(False)

        header = self.table.horizontalHeader()
        for i in range(len(_COLUMNS) - 1):
            header.setSectionResizeMode(i, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(
            len(_COLUMNS) - 1, QHeaderView.ResizeMode.Stretch
        )

        root.addWidget(self.table, 1)

    # -- 설정 -------------------------------------------------------------
    def set_max_rows(self, value: int) -> None:
        """표시 최대 행 수를 바꾸고 초과분을 잘라낸다."""
        self._max_rows = max(1, value)
        while self.table.rowCount() > self._max_rows:
            self.table.removeRow(0)
        self._update_count()

    # -- 데이터 -----------------------------------------------------------
    def add_row(self, row: LogRow) -> None:
        """행 하나 추가. 필터에 걸리면 테이블에는 넣지 않는다."""
        self.rows.append(row)
        if self._passes_filter(row):
            self._append_to_table(row)
        self._update_count()

    def _passes_filter(self, row: LogRow) -> bool:
        if self.errors_only.isChecked() and not row.is_error:
            return False
        if self.events_only.isChecked() and not row.is_event:
            return False
        return True

    def _append_to_table(self, row: LogRow) -> None:
        index = self.table.rowCount()
        self.table.insertRow(index)
        for col, text in enumerate(row.as_columns()):
            item = QTableWidgetItem(text)
            if row.is_error:
                item.setForeground(QColor(T.bad))
            elif row.is_event:
                item.setForeground(QColor(T.state_warning))
            self.table.setItem(index, col, item)

        while self.table.rowCount() > self._max_rows:
            self.table.removeRow(0)

        if self.auto_scroll.isChecked():
            self.table.scrollToBottom()

    def apply_theme(self) -> None:
        """테마 교체 후 인라인 스타일과 행 색을 다시 그린다.

        행 글자색은 `QTableWidgetItem.setForeground` 로 박혀 있어 전역 QSS 가
        못 덮는다. 그래서 표를 통째로 다시 채운다.
        """
        self._count_label.setStyleSheet(f"color:{T.text_dim};")
        self._rebuild()

    def _rebuild(self) -> None:
        """필터가 바뀌면 테이블을 다시 채운다."""
        self.table.setRowCount(0)
        visible = [r for r in self.rows if self._passes_filter(r)]
        for row in visible[-self._max_rows :]:
            self._append_to_table(row)
        self._update_count()

    def clear_rows(self) -> None:
        """테이블과 내부 보관 목록을 모두 비운다."""
        self.rows.clear()
        self.table.setRowCount(0)
        self._update_count()

    def _update_count(self) -> None:
        self._count_label.setText(
            f"{self.table.rowCount()} / {len(self.rows)} 행"
        )
