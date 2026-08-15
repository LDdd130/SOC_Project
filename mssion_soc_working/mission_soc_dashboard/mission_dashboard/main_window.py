"""MainWindow. 위젯을 배치하고 Worker/로그/설정을 묶는 조립 계층.

안전 설계 원칙:
    이 앱은 안전 판단을 하지 않는다. FPGA 내부의
    heartbeat_monitor_ip -> fault_manager_ip -> safety_controller_ip
    직접 연결 경로가 판단과 출력 차단을 담당한다.
    앱이 죽거나 UART 가 끊겨도 FPGA 동작에는 영향이 없다.
"""

from __future__ import annotations

import logging
from datetime import datetime
from pathlib import Path

from PySide6.QtCore import Qt, QTimer
from PySide6.QtGui import QKeySequence, QShortcut
from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QFileDialog,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QMessageBox,
    QScrollArea,
    QSplitter,
    QPushButton,
    QStatusBar,
    QTabWidget,
    QToolButton,
    QVBoxLayout,
    QWidget,
)

from .command_builder import CommandBuilder, CommandError
from .constants import (
    APP_NAME,
    APP_VERSION,
    DEVICE_COUNT,
    IRQ_EN_ALL,
    IRQ_EN_OFF_NOTE,
    MIN_WINDOW_HEIGHT,
    MIN_WINDOW_WIDTH,
)
from .log_manager import LogManager
from .models import (
    ConfigValues,
    ConnectionState,
    DeviceStatus,
    IrqStatus,
    LogRow,
    MissionStatus,
    ParseResult,
    SerialStatistics,
)
from .serial_worker import MockWorker, SerialWorker, WorkerThread
from .settings_manager import SettingsManager
from .state_mapper import check_policy
from .theme import PALETTES, T, app_qss, set_theme, theme_label, theme_name
from .widgets.chart_panel import ChartPanel
from .widgets.collapsible import CollapsibleSection
from .widgets.control_panel import ControlPanel, InjectionPanel
from .widgets.device_card import DeviceCard
from .widgets.event_table import EventTable
from .widgets.serial_panel import SerialPanel
from .widgets.state_card import StateCard

logger = logging.getLogger(__name__)

__all__ = ["MainWindow"]


class MainWindow(QMainWindow):
    """관제 앱 메인 창."""

    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle(f"{APP_NAME} v{APP_VERSION}")
        self.setMinimumSize(MIN_WINDOW_WIDTH, MIN_WINDOW_HEIGHT)

        self.settings = SettingsManager()
        self.settings.load()

        # 테마는 위젯을 만들기 전에 정해야 한다. 각 위젯이 생성 시점에
        # 현재 팔레트로 인라인 스타일을 굽기 때문이다.
        set_theme(str(self.settings.get("theme") or "light"))

        #: 패널 최대화 전에 되돌릴 정보를 담아둔다. None 이면 최대화 상태가 아니다.
        self._maximize_backup: dict[str, object] | None = None

        self.log_manager = LogManager(Path(self.settings.get("log_dir")))
        self.statistics = SerialStatistics()
        self.session_statuses: list[MissionStatus] = []

        self._thread: WorkerThread | None = None
        self._worker: SerialWorker | MockWorker | None = None
        self._connection = ConnectionState.DISCONNECTED
        self._last_status: MissionStatus | None = None
        self._policy_warned: set[str] = set()

        #: 전역 QSS 로 못 덮는 회색 설명 라벨들. 테마 교체 때 다시 칠한다.
        self._themed_labels: list[QLabel] = []

        self._build_ui()
        self._install_shortcuts()
        self._apply_theme_all()
        self._restore_settings()

        # 통계/경과시간 갱신용 타이머
        self._ui_timer = QTimer(self)
        self._ui_timer.setInterval(500)
        self._ui_timer.timeout.connect(self._refresh_periodic)
        self._ui_timer.start()

    # ==================================================================
    # UI 구성
    # ==================================================================
    def _build_ui(self) -> None:
        central = QWidget()
        self.setCentralWidget(central)
        root = QVBoxLayout(central)
        root.setContentsMargins(10, 10, 10, 10)
        root.setSpacing(10)

        self.serial_panel = SerialPanel()
        self.serial_panel.connect_requested.connect(self._on_connect)
        self.serial_panel.disconnect_requested.connect(self._on_disconnect)
        self.serial_panel.mock_requested.connect(self._on_mock)
        root.addWidget(self.serial_panel)

        self.splitter = QSplitter(Qt.Orientation.Horizontal)
        self.splitter.addWidget(self._build_left())
        self.right_pane = self._build_right()
        self.splitter.addWidget(self.right_pane)
        self.splitter.setStretchFactor(0, 3)
        self.splitter.setStretchFactor(1, 2)
        root.addWidget(self.splitter, 1)

        self.setStatusBar(QStatusBar())
        self._set_status("준비됨. Mock 모드 또는 실제 포트로 연결하십시오.")

    def _build_left(self) -> QWidget:
        panel = QWidget()
        layout = QVBoxLayout(panel)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(10)

        self.state_card = StateCard()
        layout.addWidget(self.state_card)

        self.device_box = QGroupBox("장치 상태")
        device_layout = QHBoxLayout(self.device_box)
        device_layout.setSpacing(8)
        self.device_cards: list[DeviceCard] = []
        for i in range(DEVICE_COUNT):
            card = DeviceCard(i)
            self.device_cards.append(card)
            device_layout.addWidget(card)
        layout.addWidget(self.device_box)

        self.left_tabs = QTabWidget()

        self.event_table = EventTable()
        self.event_table.export_requested.connect(self._on_export_events)
        self.left_tabs.addTab(self.event_table, "Event Log")

        self.chart_panel = ChartPanel()
        self.left_tabs.addTab(self.chart_panel, "실시간 차트")

        # 탭 오른쪽 구석에 최대화 토글을 단다. Event Log 와 실시간 차트 둘 다
        # 이 한 버튼으로 창 전체를 쓰게 만든다.
        self.maximize_btn = QToolButton()
        self.maximize_btn.setCheckable(True)
        self.maximize_btn.setText("⛶ 확대")
        self.maximize_btn.setToolTip(
            "이 탭을 창 전체로 넓힌다 (Ctrl+M).\n"
            "연결 바 · 시스템 상태 · 장치 상태 · 오른쪽 패널을 잠시 감춘다.\n"
            "한 번 더 누르면 원래대로 돌아온다."
        )
        self.maximize_btn.clicked.connect(self._on_toggle_maximize)
        self.left_tabs.setCornerWidget(
            self.maximize_btn, Qt.Corner.TopRightCorner
        )

        layout.addWidget(self.left_tabs, 1)
        return panel

    def _build_right(self) -> QWidget:
        tabs = QTabWidget()
        self.right_tabs = tabs

        self.control_panel = ControlPanel()
        self.control_panel.apply_config_requested.connect(self._on_apply_config)
        self.control_panel.command_requested.connect(self._on_command)
        self.control_panel.irq_en_requested.connect(self._on_irq_en)

        # IRQ 블록은 검증용이라 시연 중엔 자리만 차지한다. 접어서 내보낸다.
        self._sections: dict[str, CollapsibleSection] = {}
        self._wrap_in_section(
            "irq",
            self.control_panel.irq_group,
            self.control_panel.layout(),
            title="IRQ 상태 (검증용)",
            hint=(
                "CMD,CLEAR_IRQ 의 W1C 를 증명할 때만 쓴다 (05 시나리오 15번).\n"
                "평상시 시연에는 필요 없어 접어 둔다."
            ),
        )

        tabs.addTab(self._scrollable(self.control_panel), "설정 · 제어")

        self.injection_panel = InjectionPanel()
        self.injection_panel.inject_requested.connect(self._on_inject)
        self.injection_panel.clear_all_requested.connect(self._on_clear_injection)
        self.injection_panel.preset_requested.connect(self._on_preset)
        tabs.addTab(self._scrollable(self.injection_panel), "Fault Injection")

        tabs.addTab(self._scrollable(self._build_log_panel()), "로그 · 정보")
        return tabs

    @staticmethod
    def _scrollable(widget: QWidget) -> QScrollArea:
        """작은 화면에서도 스크롤되게 감싼다."""
        area = QScrollArea()
        area.setWidgetResizable(True)
        area.setWidget(widget)
        return area

    def _wrap_in_section(
        self,
        key: str,
        target: QWidget,
        layout,
        *,
        title: str,
        hint: str = "",
    ) -> CollapsibleSection:
        """이미 배치된 위젯을 같은 자리에서 접이식 섹션으로 감싼다.

        ``target`` 이 붙어 있던 인덱스를 찾아 그 자리에 섹션을 끼워 넣는다.
        레이아웃 순서가 바뀌지 않아야 화면 구성이 유지된다.
        """
        index = layout.indexOf(target)
        layout.takeAt(index)

        # 섹션 헤더가 제목을 가지므로 안쪽 QGroupBox 의 제목/테두리는 지운다.
        # 그대로 두면 같은 제목이 두 줄로 겹쳐 보인다.
        if isinstance(target, QGroupBox):
            target.setTitle("")
            target.setObjectName("sectionBody")

        expanded = bool(self.settings.get("sections", {}).get(key, False))
        section = CollapsibleSection(
            title, target, expanded=expanded, hint=hint
        )
        section.toggled.connect(
            lambda checked, k=key: self._on_section_toggled(k, checked)
        )
        layout.insertWidget(index, section)
        self._sections[key] = section
        return section

    def _on_section_toggled(self, key: str, expanded: bool) -> None:
        sections = dict(self.settings.get("sections") or {})
        sections[key] = expanded
        self.settings.set("sections", sections)

    # ==================================================================
    # 테마 / 화면 확대
    # ==================================================================
    def _install_shortcuts(self) -> None:
        QShortcut(QKeySequence("Ctrl+M"), self, activated=self._toggle_maximize)
        QShortcut(QKeySequence("F11"), self, activated=self._toggle_fullscreen)

    def _on_theme_changed(self) -> None:
        key = self.theme_combo.currentData()
        if not isinstance(key, str) or not set_theme(key):
            return
        self.settings.set("theme", key)
        self._apply_theme_all()
        self._set_status(f"테마를 {theme_label(key)} 로 바꿨습니다.")

    def _apply_theme_all(self) -> None:
        """전역 QSS 를 다시 깔고 모든 위젯의 인라인 스타일을 새로 그린다.

        전역 QSS 만으로는 부족하다. 위젯들이 상태별 색(정상/경고/고장)을
        인라인으로 지정하는데, 인라인 지정이 QSS 보다 우선하기 때문이다.
        그래서 각 위젯의 ``apply_theme()`` 을 직접 호출한다.
        """
        self.setStyleSheet(app_qss())

        for label in self._themed_labels:
            label.setStyleSheet(f"color:{T.text_dim}; font-size:11px;")

        themables: list[object] = [
            self.serial_panel,
            self.state_card,
            self.event_table,
            self.chart_panel,
            self.control_panel,
            self.injection_panel,
            *self.device_cards,
            *self._sections.values(),
        ]
        for widget in themables:
            apply = getattr(widget, "apply_theme", None)
            if callable(apply):
                apply()

    def _toggle_maximize(self) -> None:
        """확대/복원을 토글한다. 버튼과 단축키가 함께 쓴다."""
        self.maximize_btn.setChecked(self._maximize_backup is None)
        self._on_toggle_maximize()

    def _on_toggle_maximize(self) -> None:
        """Event Log / 실시간 차트를 창 전체로 넓히거나 되돌린다.

        위젯을 재배치하지 않고 주변을 감추기만 한다. 재배치하면 스플리터
        비율과 스크롤 위치가 날아가고, 수신 중 위젯이 잠깐 부모를 잃는다.
        """
        if self._maximize_backup is None:
            self._maximize_backup = {"sizes": self.splitter.sizes()}
            self.serial_panel.setVisible(False)
            self.state_card.setVisible(False)
            self.device_box.setVisible(False)
            self.right_pane.setVisible(False)
            self.maximize_btn.setText("⛶ 복원")
            self.maximize_btn.setChecked(True)
            self._set_status("확대 모드입니다. Ctrl+M 또는 ⛶ 복원으로 돌아갑니다.")
            return

        sizes = self._maximize_backup.get("sizes")
        self._maximize_backup = None
        self.serial_panel.setVisible(True)
        self.state_card.setVisible(True)
        self.device_box.setVisible(True)
        self.right_pane.setVisible(True)
        if isinstance(sizes, list) and sizes:
            self.splitter.setSizes(sizes)
        self.maximize_btn.setText("⛶ 확대")
        self.maximize_btn.setChecked(False)
        self._set_status("원래 배치로 복원했습니다.")

    def _toggle_fullscreen(self) -> None:
        """창 자체를 전체화면으로. 확대 모드와는 독립이다."""
        if self.isFullScreen():
            self.showNormal()
        else:
            self.showFullScreen()

    def _build_log_panel(self) -> QWidget:
        panel = QWidget()
        layout = QVBoxLayout(panel)
        layout.setSpacing(10)

        layout.addWidget(self._build_view_group())

        box = QGroupBox("CSV 로그")
        box_layout = QVBoxLayout(box)

        self._log_path_label = QLabel("기록 중이 아닙니다.")
        self._log_path_label.setWordWrap(True)
        self._themed_labels.append(self._log_path_label)
        box_layout.addWidget(self._log_path_label)

        self.auto_log_check = QCheckBox("연결 시 자동으로 CSV 기록 시작")
        self.auto_log_check.toggled.connect(self._on_auto_log_toggled)
        box_layout.addWidget(self.auto_log_check)

        start_btn = QPushButton("기록 시작 / 중지")
        start_btn.clicked.connect(self._toggle_logging)
        box_layout.addWidget(start_btn)

        folder_btn = QPushButton("저장 폴더 선택")
        folder_btn.clicked.connect(self._on_choose_log_dir)
        box_layout.addWidget(folder_btn)

        export_btn = QPushButton("현재 세션 Export")
        export_btn.clicked.connect(self._on_export_session)
        box_layout.addWidget(export_btn)

        layout.addWidget(box)

        info = QGroupBox("안전 설계 원칙")
        info_layout = QVBoxLayout(info)
        text = QLabel(
            "이 앱은 안전 판단을 수행하지 않습니다.\n\n"
            "고장 판단과 출력 차단은 FPGA 내부의 직접 연결 경로가 담당합니다.\n"
            "    heartbeat_monitor_ip\n"
            "    → fault_manager_ip\n"
            "    → safety_controller_ip\n\n"
            "앱이 종료되거나 UART 가 끊겨도 FPGA 의 Fault 판단과\n"
            "SAFE_MODE 전환에는 영향이 없습니다.\n\n"
            "앱의 역할은 모니터링, 명령 전송, 로그 저장뿐입니다.\n"
            "수신된 값은 그대로 표시하며 앱이 계산한 값으로 덮어쓰지 않습니다."
        )
        text.setWordWrap(True)
        self._themed_labels.append(text)
        info_layout.addWidget(text)
        layout.addWidget(info)

        layout.addStretch(1)
        return panel

    # ------------------------------------------------------------------
    def _build_view_group(self) -> QGroupBox:
        """테마 교체와 화면 확대 조작."""
        box = QGroupBox("화면")
        layout = QVBoxLayout(box)
        layout.setSpacing(6)

        row = QHBoxLayout()
        row.addWidget(QLabel("테마:"))
        self.theme_combo = QComboBox()
        for key in PALETTES:
            self.theme_combo.addItem(theme_label(key), key)
        index = self.theme_combo.findData(theme_name())
        if index >= 0:
            self.theme_combo.setCurrentIndex(index)
        self.theme_combo.currentIndexChanged.connect(self._on_theme_changed)
        row.addWidget(self.theme_combo, 1)
        layout.addLayout(row)

        note = QLabel(
            "밝은 테마가 기본입니다. 회의실 프로젝터·인쇄 캡처에서 가독성이 좋습니다.\n"
            "테마는 즉시 적용되고 다음 실행에도 유지됩니다."
        )
        note.setWordWrap(True)
        self._themed_labels.append(note)
        layout.addWidget(note)

        max_btn = QPushButton("Event Log / 차트 확대 · 복원  (Ctrl+M)")
        max_btn.clicked.connect(self._toggle_maximize)
        layout.addWidget(max_btn)

        full_btn = QPushButton("창 전체화면 · 복원  (F11)")
        full_btn.clicked.connect(self._toggle_fullscreen)
        layout.addWidget(full_btn)

        return box

    # ==================================================================
    # 설정
    # ==================================================================
    def _restore_settings(self) -> None:
        width = int(self.settings.get("window_width"))
        height = int(self.settings.get("window_height"))
        self.resize(width, height)
        x = self.settings.get("window_x")
        y = self.settings.get("window_y")
        if isinstance(x, int) and isinstance(y, int):
            self.move(x, y)

        self.serial_panel.apply_settings(
            str(self.settings.get("last_port") or ""),
            int(self.settings.get("last_baudrate")),
            int(self.settings.get("mock_period_ms")),
        )
        self.control_panel.apply_settings(self.settings.get_config())
        self.event_table.max_rows_spin.setValue(int(self.settings.get("max_log_rows")))
        self.chart_panel.set_window_seconds(int(self.settings.get("chart_window_s")))
        self.auto_log_check.setChecked(bool(self.settings.get("auto_log")))

        if self.settings.last_error:
            self._set_status(self.settings.last_error)

    def _persist_settings(self) -> None:
        config = self.control_panel.current_config()
        self.settings.update(
            {
                "last_port": self.serial_panel.selected_port(),
                "last_baudrate": int(
                    self.serial_panel.baud_combo.currentData()
                    or self.serial_panel.baud_combo.currentText()
                ),
                "window_width": self.width(),
                "window_height": self.height(),
                "window_x": self.x(),
                "window_y": self.y(),
                "log_dir": str(self.log_manager.log_dir),
                "auto_log": self.auto_log_check.isChecked(),
                "chart_window_s": self.chart_panel.window_seconds(),
                "max_log_rows": self.event_table.max_rows_spin.value(),
                "mock_period_ms": self.serial_panel.mock_period.value(),
            }
        )
        self.settings.set_config(config.to_dict())
        self.settings.save()

    # ==================================================================
    # 연결
    # ==================================================================
    def _set_connection(self, state: ConnectionState) -> None:
        self._connection = state
        self.serial_panel.set_connection_state(state)

    def _start_worker(self, worker: SerialWorker | MockWorker) -> None:
        self._worker = worker
        worker.parse_result_ready.connect(self._on_parse_result)
        worker.bytes_received.connect(self._on_bytes)
        worker.connected.connect(self._on_worker_connected)
        worker.disconnected.connect(self._on_worker_disconnected)
        worker.error_occurred.connect(self._on_worker_error)

        self._thread = WorkerThread(worker)
        self._thread.start()

    def _on_connect(self, port: str, baudrate: int) -> None:
        if self._thread is not None:
            return
        port = self.serial_panel.selected_port() or port
        if not port:
            QMessageBox.warning(self, "연결 실패", "포트를 선택하십시오.")
            return
        self._set_connection(ConnectionState.CONNECTING)
        self._set_status(f"{port} 연결 시도 중...")
        self._start_worker(SerialWorker(port, baudrate))

    def _on_mock(self, period_ms: int) -> None:
        if self._thread is not None:
            return
        self._set_connection(ConnectionState.CONNECTING)
        self._set_status("Mock Simulator 시작 중...")
        self._start_worker(MockWorker(period_ms))

    def _on_disconnect(self) -> None:
        self._shutdown_worker()
        self._set_connection(ConnectionState.DISCONNECTED)
        self._set_status("연결이 해제되었습니다.")

    def _shutdown_worker(self) -> None:
        """Worker 와 스레드를 협조적으로 종료한다."""
        if self._thread is not None:
            try:
                self._thread.shutdown()
            except Exception as exc:  # pragma: no cover
                logger.warning("스레드 종료 실패: %s", exc)
            self._thread = None
        self._worker = None

    def _on_worker_connected(self, name: str) -> None:
        is_mock = name == "MOCK"
        self._set_connection(
            ConnectionState.MOCK_CONNECTED if is_mock else ConnectionState.CONNECTED
        )
        self.statistics.reset()
        self._policy_warned.clear()
        self._set_status(
            "Mock Simulator 연결됨." if is_mock else f"{name} 연결됨."
        )
        if self.auto_log_check.isChecked() and not self.log_manager.is_recording:
            self._toggle_logging()

    def _on_worker_disconnected(self) -> None:
        if self._connection is not ConnectionState.ERROR:
            self._set_connection(ConnectionState.DISCONNECTED)

    def _on_worker_error(self, message: str) -> None:
        self._set_connection(ConnectionState.ERROR)
        self._set_status(f"오류: {message}")
        self._add_log_row(
            LogRow(
                received_at=datetime.now(),
                timestamp_ms=None,
                message_type="APP",
                event_type="ERROR",
                description=message,
                raw_line=message,
                is_error=True,
            )
        )

    # ==================================================================
    # 수신 처리
    # ==================================================================
    def _on_bytes(self, count: int) -> None:
        self.statistics.bytes_received += count

    def _on_parse_result(self, result: ParseResult) -> None:
        """Worker 가 넘긴 파싱 결과를 화면에 반영한다."""
        try:
            self.statistics.last_received_at = datetime.now()

            if not result.success:
                self.statistics.parse_errors += 1
                self._add_log_row(
                    LogRow(
                        received_at=datetime.now(),
                        timestamp_ms=None,
                        message_type=result.message_type,
                        event_type="PARSE_ERROR",
                        description=result.error or "파싱 실패",
                        raw_line=result.raw_line,
                        is_error=True,
                    )
                )
                return

            self.statistics.messages_received += 1

            if result.status is not None:
                self._handle_status(result.status)
            elif result.irq is not None:
                self._handle_irq(result.irq)
            elif result.event is not None:
                self._handle_event(result)
            elif result.response is not None:
                self._handle_response(result)
            else:
                self._handle_raw(result)
        except Exception as exc:  # pragma: no cover - GUI 보호
            logger.exception("수신 처리 실패")
            self._set_status(f"수신 처리 오류: {exc}")

    def _handle_status(self, status: MissionStatus) -> None:
        self._last_status = status
        self.session_statuses.append(status)

        self.state_card.update_status(status)
        for i, card in enumerate(self.device_cards):
            card.update_device(DeviceStatus.from_status(status, i))
        self.chart_panel.add_status(status)
        self.log_manager.write_status(status)

        # 정책 위반은 경고만. FPGA 출력을 고치지 않는다.
        degrade_mask = self.control_panel.current_config().degrade_mask
        for warning in check_policy(status, degrade_mask):
            if warning in self._policy_warned:
                continue
            self._policy_warned.add(warning)
            self._add_log_row(
                LogRow(
                    received_at=status.received_at,
                    timestamp_ms=status.timestamp_ms,
                    message_type="POLICY",
                    event_type="POLICY_WARNING",
                    state=status.system_state.value,
                    description=warning,
                    raw_line=status.raw_line,
                    is_error=True,
                )
            )

        self._add_log_row(
            LogRow(
                received_at=status.received_at,
                timestamp_ms=status.timestamp_ms,
                message_type="MISSION",
                state=status.system_state.value,
                fault_level=str(int(status.fault_level)),
                fault_device=str(int(status.fault_device)),
                fault_code=f"0x{int(status.fault_code):02X}",
                description=(
                    f"alive=0x{status.alive_mask:02X} "
                    f"timeout=0x{status.timeout_mask:02X} "
                    f"oe=0x{status.output_enable_mask:02X}"
                ),
                raw_line=status.raw_line,
            )
        )

    def _handle_irq(self, irq: IrqStatus) -> None:
        """`$IRQ` 수신. 제어 패널을 갱신하고 로그에도 한 줄 남긴다."""
        self.control_panel.update_irq(irq)
        self._add_log_row(
            LogRow(
                received_at=irq.received_at,
                timestamp_ms=None,
                message_type="IRQ",
                event_type="IRQ_SNAPSHOT",
                description=irq.description,
                raw_line=irq.raw_line,
                # Pending 이 남아 있는 건 비정상이 아니라 IRQ_EN 을 꺼 둔
                # 검증 구간이라는 뜻이다. 눈에 띄게만 표시한다.
                is_error=irq.any_pending,
            )
        )
        if irq.any_pending:
            self._set_status(
                f"IRQ Pending 이 남아 있습니다: {irq.description}. "
                "Clear IRQ 로 W1C 동작을 확인하십시오."
            )

    def _handle_event(self, result: ParseResult) -> None:
        event = result.event
        assert event is not None

        # 상태 카드의 큰 글씨는 $MISSION 으로만 갱신된다(500ms 주기). 그보다
        # 짧은 전이는 거기 안 뜨므로 전이 이력 줄에 따로 남긴다.
        if event.event_type == "STATE_CHANGE" and event.args:
            self.state_card.push_transition(event.args[0], event.received_at)

        self._add_log_row(
            LogRow(
                received_at=event.received_at,
                timestamp_ms=event.timestamp_ms,
                message_type="EVENT",
                event_type=event.event_type,
                description=event.description,
                raw_line=event.raw_line,
                is_event=True,
            )
        )

    def _handle_response(self, result: ParseResult) -> None:
        response = result.response
        assert response is not None

        if response.is_unknown_command:
            self._set_status(
                f"FPGA 펌웨어가 지원하지 않는 명령입니다: {response.description}"
            )
        elif not response.is_ack:
            self._set_status(f"명령 실패: {response.description}")

        self._add_log_row(
            LogRow(
                received_at=response.received_at,
                timestamp_ms=None,
                message_type="ACK" if response.is_ack else "ERR",
                event_type=response.command,
                description=response.description,
                raw_line=response.raw_line,
                is_error=not response.is_ack,
            )
        )

    def _handle_raw(self, result: ParseResult) -> None:
        self._add_log_row(
            LogRow(
                received_at=datetime.now(),
                timestamp_ms=None,
                message_type="RAW",
                description=result.raw_line,
                raw_line=result.raw_line,
            )
        )

    def _add_log_row(self, row: LogRow) -> None:
        self.event_table.add_row(row)

    # ==================================================================
    # 명령 전송
    # ==================================================================
    def _send(self, command: str) -> bool:
        """Worker 송신 큐에 명령을 넣는다."""
        if self._worker is None:
            self._set_status("연결되지 않아 명령을 보낼 수 없습니다.")
            return False
        self._worker.send_command(command)
        self._add_log_row(
            LogRow(
                received_at=datetime.now(),
                timestamp_ms=None,
                message_type="TX",
                event_type="COMMAND",
                description=command.strip(),
                raw_line=command.strip(),
            )
        )
        return True

    def _send_many(self, commands: list[str]) -> None:
        for command in commands:
            if not self._send(command):
                return

    def _on_apply_config(self, config: ConfigValues) -> None:
        try:
            commands = CommandBuilder.apply_config(config)
        except CommandError as exc:
            QMessageBox.warning(self, "설정 값 오류", str(exc))
            return
        self._send_many(commands)
        self._set_status("설정 전체를 전송했습니다. $ACK 응답을 확인하십시오.")

    def _on_command(self, key: str) -> None:
        builders = {
            "GET_STATUS": CommandBuilder.get_status,
            "GET_CONFIG": CommandBuilder.get_config,
            "GET_IRQ": CommandBuilder.get_irq,
            "MANUAL_RESET": CommandBuilder.manual_reset,
            "CLEAR_IRQ": CommandBuilder.clear_irq,
            "CLEAR_HEARTBEAT": CommandBuilder.clear_heartbeat,
            "RESET_FAULT": CommandBuilder.reset_fault,
        }
        builder = builders.get(key)
        if builder is None:
            return
        if self._send(builder()) and key == "MANUAL_RESET":
            self._set_status(
                "Manual Recovery 를 전송했습니다. "
                "복구 성공 여부는 $ACK 또는 새 $MISSION 상태로만 확인됩니다."
            )

    def _on_irq_en(self, mask: int) -> None:
        """`IRQ_EN 적용` 버튼. 전송 후 실제 반영값을 한 번 되읽는다.

        체크박스 변경이 아니라 버튼에만 연결돼 있다. 체크박스마다 전송하면
        3개를 푸는 동안 명령이 3번 나가고, 9600bps 라 늦게 도착한 첫 응답이
        화면을 되돌린다.
        """
        try:
            command = CommandBuilder.set_irq_en(mask)
        except CommandError as exc:
            self._set_status(f"IRQ_EN 값 오류: {exc}")
            return
        if not self._send(command):
            return
        if mask != IRQ_EN_ALL:
            self._set_status(
                f"IRQ_EN=0b{mask:03b} 로 전송했습니다. {IRQ_EN_OFF_NOTE}"
            )
        self._send(CommandBuilder.get_irq())

    def _on_inject(self, kind: str, device: int, on: bool) -> None:
        try:
            command = CommandBuilder.inject(kind, device, on)
        except CommandError as exc:
            QMessageBox.warning(self, "Injection 오류", str(exc))
            return
        self._send(command)

    def _on_clear_injection(self) -> None:
        self._send(CommandBuilder.inject_clear_all())

    def _on_preset(self, kind: str) -> None:
        if kind == "MULTI":
            self._send_many(CommandBuilder.multi_device_demo())
        elif kind == "MULTI_ERROR":
            self._send_many(CommandBuilder.multi_error_demo())
        elif kind == "CRITICAL":
            self._send_many(CommandBuilder.critical_demo())
        elif kind == "CRITICAL_MASK":
            self._send_many(CommandBuilder.critical_mask_error_demo())
        self.injection_panel.set_preset_checks(kind)

    # ==================================================================
    # 로그
    # ==================================================================
    def _toggle_logging(self) -> None:
        if self.log_manager.is_recording:
            self.log_manager.stop()
            self._log_path_label.setText("기록 중이 아닙니다.")
            self._set_status("CSV 기록을 중지했습니다.")
            return

        if self.log_manager.start():
            self._log_path_label.setText(f"기록 중: {self.log_manager.current_path}")
            self._set_status("CSV 기록을 시작했습니다.")
        else:
            self._log_path_label.setText(self.log_manager.last_error or "기록 실패")
            self._set_status(self.log_manager.last_error or "로그 시작 실패")

    def _on_auto_log_toggled(self, checked: bool) -> None:
        self.settings.set("auto_log", checked)

    def _on_choose_log_dir(self) -> None:
        directory = QFileDialog.getExistingDirectory(
            self, "로그 저장 폴더 선택", str(self.log_manager.log_dir)
        )
        if directory:
            self.log_manager.set_log_dir(Path(directory))
            self._set_status(f"로그 폴더: {directory}")

    def _on_export_session(self) -> None:
        if not self.session_statuses:
            QMessageBox.information(self, "Export", "내보낼 상태 데이터가 없습니다.")
            return
        path, _ = QFileDialog.getSaveFileName(
            self,
            "세션 Export",
            str(self.log_manager.log_dir / "session_export.csv"),
            "CSV (*.csv)",
        )
        if not path:
            return
        if self.log_manager.export_statuses(Path(path), self.session_statuses):
            self._set_status(f"세션을 저장했습니다: {path}")
        else:
            QMessageBox.warning(
                self, "Export 실패", self.log_manager.last_error or "알 수 없는 오류"
            )

    def _on_export_events(self) -> None:
        if not self.event_table.rows:
            QMessageBox.information(self, "Export", "내보낼 로그가 없습니다.")
            return
        path, _ = QFileDialog.getSaveFileName(
            self,
            "Event Log Export",
            str(self.log_manager.suggest_event_path()),
            "CSV (*.csv)",
        )
        if not path:
            return
        if self.log_manager.export_events(Path(path), list(self.event_table.rows)):
            self._set_status(f"Event Log 를 저장했습니다: {path}")
        else:
            QMessageBox.warning(
                self, "Export 실패", self.log_manager.last_error or "알 수 없는 오류"
            )

    # ==================================================================
    # 주기 갱신 / 종료
    # ==================================================================
    def _refresh_periodic(self) -> None:
        self.serial_panel.update_statistics(self.statistics)
        self.state_card.set_stale(self.statistics.last_received_at)

    def _set_status(self, message: str) -> None:
        self.statusBar().showMessage(message)

    def closeEvent(self, event) -> None:  # noqa: N802 - Qt 규약
        """종료 시 Worker/로그/설정을 정리한다."""
        try:
            self._shutdown_worker()
            self.log_manager.stop()
            self._persist_settings()
        except Exception as exc:  # pragma: no cover
            logger.exception("종료 처리 실패: %s", exc)
        super().closeEvent(event)
