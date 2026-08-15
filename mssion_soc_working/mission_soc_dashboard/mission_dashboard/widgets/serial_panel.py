"""상단 Serial 연결 패널."""

from __future__ import annotations

from PySide6.QtCore import Signal
from PySide6.QtWidgets import (
    QComboBox,
    QFrame,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QSpinBox,
    QVBoxLayout,
)

from ..constants import (
    DEFAULT_BAUDRATE,
    DEFAULT_MOCK_PERIOD_MS,
    MAX_MOCK_PERIOD_MS,
    MIN_MOCK_PERIOD_MS,
    SUPPORTED_BAUDRATES,
)
from ..models import ConnectionState, SerialStatistics
from ..serial_worker import available_ports
from ..theme import T, connection_color

__all__ = ["SerialPanel"]


class SerialPanel(QFrame):
    """포트 선택, 연결/해제, Mock 전환, 수신 통계 표시.

    Signals:
        connect_requested(str, int): 포트명, baudrate.
        disconnect_requested(): 연결 해제.
        mock_requested(int): Mock 시작. 인자는 tick 주기(ms).
        refresh_requested(): 포트 목록 새로고침.
    """

    connect_requested = Signal(str, int)
    disconnect_requested = Signal()
    mock_requested = Signal(int)
    refresh_requested = Signal()

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self.setObjectName("serialPanel")
        #: 마지막 연결 상태. 테마 교체 때 색을 되살리려고 기억한다.
        self._state = ConnectionState.DISCONNECTED

        root = QVBoxLayout(self)
        root.setContentsMargins(12, 10, 12, 10)
        root.setSpacing(8)

        # -- 1행 : 연결 조작 ----------------------------------------------
        row = QHBoxLayout()
        row.setSpacing(8)

        row.addWidget(QLabel("COM Port:"))
        self.port_combo = QComboBox()
        self.port_combo.setMinimumWidth(220)
        self.port_combo.setEditable(True)
        row.addWidget(self.port_combo)

        self.refresh_btn = QPushButton("새로고침")
        self.refresh_btn.clicked.connect(self._on_refresh)
        row.addWidget(self.refresh_btn)

        row.addWidget(QLabel("Baudrate:"))
        self.baud_combo = QComboBox()
        for rate in SUPPORTED_BAUDRATES:
            self.baud_combo.addItem(str(rate), rate)
        self.baud_combo.setCurrentText(str(DEFAULT_BAUDRATE))
        row.addWidget(self.baud_combo)

        self.connect_btn = QPushButton("연결")
        self.connect_btn.clicked.connect(self._on_connect)
        row.addWidget(self.connect_btn)

        self.disconnect_btn = QPushButton("연결 해제")
        self.disconnect_btn.clicked.connect(self.disconnect_requested.emit)
        self.disconnect_btn.setEnabled(False)
        row.addWidget(self.disconnect_btn)

        row.addSpacing(12)
        row.addWidget(QLabel("Mock 주기(ms):"))
        self.mock_period = QSpinBox()
        self.mock_period.setRange(MIN_MOCK_PERIOD_MS, MAX_MOCK_PERIOD_MS)
        self.mock_period.setSingleStep(50)
        self.mock_period.setValue(DEFAULT_MOCK_PERIOD_MS)
        row.addWidget(self.mock_period)

        self.mock_btn = QPushButton("Mock 모드")
        self.mock_btn.setToolTip("FPGA 없이 내장 시뮬레이터로 앱 전체를 시험합니다.")
        self.mock_btn.clicked.connect(
            lambda: self.mock_requested.emit(self.mock_period.value())
        )
        row.addWidget(self.mock_btn)

        row.addStretch(1)

        self.status_label = QLabel("● 연결 안 됨 (DISCONNECTED)")
        self.status_label.setStyleSheet("font-weight:700;")
        row.addWidget(self.status_label)

        root.addLayout(row)

        # -- 2행 : 수신 통계 ----------------------------------------------
        stats = QHBoxLayout()
        stats.setSpacing(18)
        self._stat_labels: dict[str, QLabel] = {}
        for key, text in [
            ("bytes", "수신 Bytes"),
            ("messages", "수신 Message"),
            ("errors", "Parse Error"),
            ("last", "마지막 수신"),
        ]:
            label = QLabel(f"{text}: 0")
            stats.addWidget(label)
            self._stat_labels[key] = label
        stats.addStretch(1)
        root.addLayout(stats)

        self.apply_theme()
        self.refresh_ports()

    # ------------------------------------------------------------------
    def apply_theme(self) -> None:
        """테마 교체 후 인라인 스타일을 다시 그린다."""
        self.setStyleSheet(
            f"#serialPanel {{ background:{T.bg_card};"
            f" border:1px solid {T.border}; border-radius:8px; }}"
        )
        for label in self._stat_labels.values():
            label.setStyleSheet(f"color:{T.text_dim}; font-size:11px;")
        self.set_connection_state(self._state)

    # -- 조작 -------------------------------------------------------------
    def _on_refresh(self) -> None:
        self.refresh_ports()
        self.refresh_requested.emit()

    def _on_connect(self) -> None:
        port = self.port_combo.currentText().strip()
        if not port:
            return
        baud = self.baud_combo.currentData() or int(self.baud_combo.currentText())
        self.connect_requested.emit(port, int(baud))

    def refresh_ports(self) -> None:
        """시스템 포트 목록을 다시 읽는다."""
        current = self.port_combo.currentText()
        self.port_combo.clear()
        ports = available_ports()
        for device, description in ports:
            self.port_combo.addItem(f"{device} — {description}", device)
        if not ports:
            self.port_combo.addItem("(사용 가능한 포트 없음)", "")
        if current:
            self.port_combo.setCurrentText(current)

    def selected_port(self) -> str:
        """콤보에서 실제 장치 경로만 뽑아낸다."""
        data = self.port_combo.currentData()
        if data:
            return str(data)
        text = self.port_combo.currentText().strip()
        return text.split(" — ")[0] if " — " in text else text

    # -- 표시 -------------------------------------------------------------
    def set_connection_state(self, state: ConnectionState) -> None:
        """연결 상태 표시. 색과 텍스트를 함께 바꾼다."""
        self._state = state
        color = connection_color(state.value)
        self.status_label.setText(f"● {state.korean} ({state.value})")
        self.status_label.setStyleSheet(f"color:{color}; font-weight:700;")

        busy = state in (
            ConnectionState.CONNECTED,
            ConnectionState.MOCK_CONNECTED,
            ConnectionState.CONNECTING,
        )
        self.connect_btn.setEnabled(not busy)
        self.mock_btn.setEnabled(not busy)
        self.disconnect_btn.setEnabled(busy)
        self.port_combo.setEnabled(not busy)
        self.baud_combo.setEnabled(not busy)

    def update_statistics(self, stats: SerialStatistics) -> None:
        """수신 통계 갱신."""
        self._stat_labels["bytes"].setText(f"수신 Bytes: {stats.bytes_received:,}")
        self._stat_labels["messages"].setText(
            f"수신 Message: {stats.messages_received:,}"
        )
        self._stat_labels["errors"].setText(f"Parse Error: {stats.parse_errors:,}")
        last = (
            stats.last_received_at.strftime("%H:%M:%S.%f")[:-3]
            if stats.last_received_at
            else "--"
        )
        self._stat_labels["last"].setText(f"마지막 수신: {last}")

    def apply_settings(self, port: str, baudrate: int, mock_period_ms: int) -> None:
        """저장된 설정을 위젯에 반영한다."""
        if port:
            self.port_combo.setCurrentText(port)
        self.baud_combo.setCurrentText(str(baudrate))
        self.mock_period.setValue(mock_period_ms)
