"""설정/제어 패널과 Fault Injection 패널."""

from __future__ import annotations

from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import (
    QCheckBox,
    QFormLayout,
    QGridLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QSpinBox,
    QVBoxLayout,
    QWidget,
)

from ..constants import (
    DEFAULT_CRITICAL_MASK,
    DEFAULT_DEGRADE_MASK,
    DEFAULT_PERSIST_LIMIT,
    DEFAULT_RECOVERY_COUNT,
    DEFAULT_TIMEOUT_CLOCKS,
    DEVICE_COUNT,
    FPGA_CLOCK_HZ,
    IRQ_EN_ALL,
    IRQ_EN_OFF_NOTE,
    IRQ_SOURCES,
    MASK_MAX,
    MASK_MIN,
    PERSIST_LIMIT_MAX,
    PERSIST_LIMIT_MIN,
    RECOVERY_COUNT_MAX,
    RECOVERY_COUNT_MIN,
    RECOVERY_LT_PERSIST_NOTE,
    TIMEOUT_MAX,
    TIMEOUT_MIN,
    ZERO_MEANS_ONE_NOTE,
)
from ..models import ConfigValues, IrqStatus
from ..theme import T

__all__ = ["ControlPanel", "InjectionPanel"]


class ControlPanel(QWidget):
    """설정 레지스터 입력과 제어 버튼.

    Signals:
        apply_config_requested(object): :class:`ConfigValues`.
        command_requested(str): 논리 명령 이름.
        irq_en_requested(int): `SET,IRQ_EN` 마스크 (bit0=A, bit1=B, bit2=C).
    """

    apply_config_requested = Signal(object)
    command_requested = Signal(str)
    irq_en_requested = Signal(int)

    def __init__(self, parent=None) -> None:
        super().__init__(parent)

        # 테마 교체 시 다시 칠할 정적 라벨들. (위젯, 팔레트 키, 나머지 CSS)
        # 상태에 따라 색이 바뀌는 라벨은 여기 넣지 않고 각 갱신 함수가 맡는다.
        self._themed: list[tuple[QLabel, str, str]] = []

        root = QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(10)

        root.addWidget(self._build_config_group())
        root.addWidget(self._build_command_group())

        #: IRQ 블록은 시연에서 매번 쓰지 않아 접어둔다. MainWindow 가 감싼다.
        self.irq_group = self._build_irq_group()
        root.addWidget(self.irq_group)
        root.addStretch(1)

        self.apply_theme()
        self._update_warning()

    # ------------------------------------------------------------------
    def apply_theme(self) -> None:
        """테마 교체 후 인라인 스타일을 다시 그린다."""
        for widget, key, extra in self._themed:
            widget.setStyleSheet(f"color:{T[key]}; {extra}")
        self.warning_label.setStyleSheet(
            f"color:{T.state_warning}; font-size:10px; font-weight:600;"
        )
        # 상태 의존 색은 각자의 갱신 함수를 다시 태워 되살린다.
        self._refresh_irq_note()
        if self._irq_last is not None:
            self.update_irq(self._irq_last)

    # ------------------------------------------------------------------
    def _build_config_group(self) -> QGroupBox:
        box = QGroupBox("설정 레지스터")
        form = QFormLayout(box)
        form.setSpacing(6)

        # TIMEOUT 은 32비트 Unsigned 전 범위를 받아야 한다. QSpinBox 의 상한은
        # signed int32 라 0xFFFFFFFF 를 담지 못하므로 QLineEdit + 직접 검증을 쓴다.
        # 10진수와 0x 16진수를 모두 허용한다.
        self._timeouts: list[QLineEdit] = []
        self._timeout_hints: list[QLabel] = []
        for i in range(DEVICE_COUNT):
            edit = QLineEdit(str(DEFAULT_TIMEOUT_CLOCKS[i]))
            edit.setPlaceholderText("예: 30000000 또는 0x01C9C380")
            edit.textChanged.connect(self._update_ms_hints)
            self._timeouts.append(edit)

            hint = QLabel()
            self._themed.append((hint, "text_dim", "font-size:10px;"))
            self._timeout_hints.append(hint)

            row = QWidget()
            row_layout = QVBoxLayout(row)
            row_layout.setContentsMargins(0, 0, 0, 0)
            row_layout.setSpacing(0)
            row_layout.addWidget(edit)
            row_layout.addWidget(hint)
            form.addRow(f"TIMEOUT{i} (clocks)", row)

        self.critical_mask = QSpinBox()
        self.critical_mask.setRange(MASK_MIN, MASK_MAX)
        self.critical_mask.setDisplayIntegerBase(16)
        self.critical_mask.setPrefix("0x")
        self.critical_mask.setValue(DEFAULT_CRITICAL_MASK)
        self.critical_mask.setToolTip(
            "Timeout / Error / Critical Fault 모두에 적용됩니다. 기본 0x04 = Device 2."
        )
        form.addRow("CRITICAL_MASK", self.critical_mask)

        self.persist_limit = QSpinBox()
        self.persist_limit.setRange(PERSIST_LIMIT_MIN, PERSIST_LIMIT_MAX)
        self.persist_limit.setValue(DEFAULT_PERSIST_LIMIT)
        self.persist_limit.valueChanged.connect(self._update_warning)
        form.addRow("PERSIST_LIMIT", self.persist_limit)

        self.recovery_count = QSpinBox()
        self.recovery_count.setRange(RECOVERY_COUNT_MIN, RECOVERY_COUNT_MAX)
        self.recovery_count.setValue(DEFAULT_RECOVERY_COUNT)
        self.recovery_count.valueChanged.connect(self._update_warning)
        form.addRow("RECOVERY_COUNT", self.recovery_count)

        self.degrade_mask = QSpinBox()
        self.degrade_mask.setRange(MASK_MIN, MASK_MAX)
        self.degrade_mask.setDisplayIntegerBase(16)
        self.degrade_mask.setPrefix("0x")
        self.degrade_mask.setValue(DEFAULT_DEGRADE_MASK)
        self.degrade_mask.setToolTip(
            "fault_device=3 인 DEGRADED 에서만 적용됩니다."
        )
        form.addRow("DEGRADE_MASK", self.degrade_mask)

        note = QLabel(ZERO_MEANS_ONE_NOTE)
        note.setWordWrap(True)
        self._themed.append((note, "text_dim", "font-size:10px;"))
        form.addRow(note)

        self.warning_label = QLabel()
        self.warning_label.setWordWrap(True)
        self.warning_label.setStyleSheet(
            f"color:{T.state_warning}; font-size:10px; font-weight:600;"
        )
        form.addRow(self.warning_label)

        apply_btn = QPushButton("설정 전체 전송 (Apply All Settings)")
        apply_btn.clicked.connect(self._on_apply)
        form.addRow(apply_btn)

        self._update_ms_hints()
        return box

    def _build_command_group(self) -> QGroupBox:
        box = QGroupBox("제어 명령")
        grid = QGridLayout(box)
        grid.setSpacing(6)

        buttons = [
            ("Get Status", "GET_STATUS", False, ""),
            ("Get Config", "GET_CONFIG", False, ""),
            (
                "Manual Recovery",
                "MANUAL_RESET",
                True,
                "SAFE_MODE 는 Fault 가 제거돼도 자동 복구되지 않습니다.\n"
                "Manual Recovery 는 fault_valid=1 이고 fault_level=0 일 때만\n"
                "FPGA 에서 승인됩니다.\n\n"
                "앱은 성공을 가정하지 않으며 $ACK 또는 새 $MISSION 상태로만 확인합니다.\n\n"
                "전송하시겠습니까?",
            ),
            ("Clear IRQ", "CLEAR_IRQ", False, ""),
            (
                "Clear Heartbeat",
                "CLEAR_HEARTBEAT",
                True,
                "Heartbeat Counter 와 Timeout 상태를 Clear 합니다.\n"
                "IRQ Pending 은 별도로 W1C 해야 합니다.\n\n전송하시겠습니까?",
            ),
            (
                "Reset Fault",
                "RESET_FAULT",
                True,
                "현재 Fault 가 하나라도 있으면 FPGA 가 이 명령을 무시합니다.\n"
                "Fault 가 모두 없을 때만 Count 와 Pending 이 Clear 됩니다.\n\n"
                "전송하시겠습니까?",
            ),
        ]

        for index, (text, key, confirm, message) in enumerate(buttons):
            btn = QPushButton(text)
            btn.clicked.connect(
                lambda _=False, k=key, c=confirm, m=message: self._on_command(k, c, m)
            )
            grid.addWidget(btn, index // 2, index % 2)

        return box

    def _build_irq_group(self) -> QGroupBox:
        """IRQ_EN / IRQ_STATUS 관측·조작 패널.

        `CMD,CLEAR_IRQ` 는 IRQ_STATUS 를 W1C 하는데, 평상시엔 ISR 이 us 안에
        먼저 지워 버려서 사람이 누를 때는 이미 0 이다. 그래서 `$ACK` 만으로는
        W1C 가 실제로 동작하는지 알 수 없다.

        `IRQ_EN` 을 끄면 irq 핀이 막혀 ISR 이 돌지 않는다. IRQ_STATUS 의 Set 은
        IRQ_EN 과 무관하므로(rtl/fault_manager_axi.v) Pending 이 그대로 쌓이고,
        그 상태에서 `Clear IRQ` 를 눌러 0 으로 떨어지는 걸 확인하면 W1C 경로가
        증명된다. 05 시나리오 15번이 이 절차다.
        """
        box = QGroupBox("IRQ 상태 (04 체크리스트 5.2 검증용)")
        layout = QVBoxLayout(box)
        layout.setSpacing(6)

        grid = QGridLayout()
        grid.setHorizontalSpacing(12)
        grid.setVerticalSpacing(4)

        header = [
            ("IP", 0),
            ("IRQ_EN (보낼 값)", 1),
            ("보드 실제값", 2),
            ("IRQ_STATUS (Pending)", 3),
        ]
        for text, col in header:
            label = QLabel(text)
            self._themed.append((label, "text_dim", "font-size:10px;"))
            grid.addWidget(label, 0, col)

        self._irq_en_boxes: dict[str, QCheckBox] = {}
        self._irq_actual_labels: dict[str, QLabel] = {}
        self._irq_pending_labels: dict[str, QLabel] = {}
        for row, (key, title, _bit) in enumerate(IRQ_SOURCES, start=1):
            name = QLabel(title)
            name.setStyleSheet("font-size:11px;")
            grid.addWidget(name, row, 0)

            # 체크박스는 "보낼 값"만 담는다. 여기서 전송하지 않는다. 자동 전송을
            # 걸면 체크 3개를 푸는 동안 SET 이 3번 나가고, 늦게 도착한 첫 응답이
            # 이미 푼 체크박스를 도로 켜 버린다. 그래서 적용 버튼으로 분리했다.
            check = QCheckBox()
            check.setChecked(True)
            check.setToolTip(IRQ_EN_OFF_NOTE)
            check.toggled.connect(self._refresh_irq_note)
            self._irq_en_boxes[key] = check
            grid.addWidget(check, row, 1)

            actual = QLabel("--")
            self._themed.append((actual, "text_dim", "font-size:11px;"))
            self._irq_actual_labels[key] = actual
            grid.addWidget(actual, row, 2)

            pending = QLabel("--")
            self._themed.append((pending, "text", "font-size:11px; font-weight:600;"))
            pending.setTextInteractionFlags(
                Qt.TextInteractionFlag.TextSelectableByMouse
            )
            self._irq_pending_labels[key] = pending
            grid.addWidget(pending, row, 3)

        grid.setColumnStretch(3, 1)
        layout.addLayout(grid)

        buttons = QHBoxLayout()
        apply_btn = QPushButton("IRQ_EN 적용 (SET,IRQ_EN)")
        apply_btn.clicked.connect(self._on_apply_irq_en)
        buttons.addWidget(apply_btn)

        read_btn = QPushButton("IRQ 상태 읽기 (GET,IRQ)")
        read_btn.clicked.connect(lambda: self.command_requested.emit("GET_IRQ"))
        buttons.addWidget(read_btn)
        layout.addLayout(buttons)

        self.irq_note = QLabel()
        self.irq_note.setWordWrap(True)
        layout.addWidget(self.irq_note)

        self._irq_last: IrqStatus | None = None
        self._refresh_irq_note()
        return box

    # ------------------------------------------------------------------
    def current_irq_en_mask(self) -> int:
        """체크박스 상태를 `SET,IRQ_EN` 마스크로 모은다."""
        mask = 0
        for key, _title, bit in IRQ_SOURCES:
            if self._irq_en_boxes[key].isChecked():
                mask |= bit
        return mask

    def _refresh_irq_note(self) -> None:
        """안내 문구만 다시 그린다. **절대 전송하지 않는다.**

        전송은 :meth:`_on_apply_irq_en` 만 한다. 이 함수가 신호를 내보내면
        `$IRQ` 수신 -> 갱신 -> 전송 -> `$IRQ` 수신 의 무한 루프가 생긴다.
        """
        mask = self.current_irq_en_mask()
        actual = self._irq_last.en_mask if self._irq_last else None

        def warn(text: str) -> None:
            self.irq_note.setText(text)
            self.irq_note.setStyleSheet(
                f"color:{T.state_warning}; font-size:10px; font-weight:600;"
            )

        if self._irq_last is not None and self._irq_last.any_pending:
            stamp = self._irq_last.received_at.strftime("%H:%M:%S.%f")[:-3]
            warn(
                f"[{stamp}] Pending 이 남아 있습니다 — {self._irq_last.description}. "
                "Clear IRQ 를 눌러 0 으로 떨어지는지 확인하십시오."
            )
            return

        if actual is not None and actual != mask:
            warn(
                f"체크박스(0b{mask:03b})와 보드 실제값(0b{actual:03b})이 다릅니다. "
                "`IRQ_EN 적용` 을 누르십시오."
            )
            return

        if actual is not None and actual != IRQ_EN_ALL:
            warn(f"⚠ 보드 IRQ_EN=0b{actual:03b} — {IRQ_EN_OFF_NOTE}")
            return

        self.irq_note.setText(
            "평상시 Pending 은 전부 0 입니다 (ISR 이 즉시 W1C). "
            "Clear IRQ 를 검증하려면 IRQ_EN 을 끈 뒤 고장을 넣으십시오."
        )
        self.irq_note.setStyleSheet(f"color:{T.text_dim}; font-size:10px;")

    def _on_apply_irq_en(self) -> None:
        """체크박스 값을 한 번만 전송한다. 여러 개를 바꿔도 명령은 1회다."""
        self.irq_en_requested.emit(self.current_irq_en_mask())

    def update_irq(self, irq: IrqStatus) -> None:
        """`$IRQ` 수신 결과를 반영한다.

        **체크박스는 건드리지 않는다.** 체크박스는 조작자가 보내려는 값이고,
        보드가 알려준 실제 값은 옆 칸에 따로 보여준다. 늦게 도착한 응답이
        조작 중인 체크박스를 되돌리는 일이 없다.
        """
        self._irq_last = irq

        for key, _title, bit in IRQ_SOURCES:
            self._irq_actual_labels[key].setText("ON" if irq.enabled(bit) else "OFF")

            value = irq.status_of(key)
            label = self._irq_pending_labels[key]
            label.setText(f"0x{value:02X}  (0b{value:03b})")
            label.setStyleSheet(
                f"color:{T.state_warning}; font-size:11px; font-weight:700;"
                if value
                else f"color:{T.text}; font-size:11px; font-weight:600;"
            )

        self._refresh_irq_note()

    # ------------------------------------------------------------------
    def _timeout_value(self, index: int) -> int | None:
        """TIMEOUT 입력을 정수로 읽는다. 범위를 벗어나면 ``None``."""
        from ..protocol import parse_int

        value = parse_int(self._timeouts[index].text())
        if value is None or not (TIMEOUT_MIN <= value <= TIMEOUT_MAX):
            return None
        return value

    def _update_ms_hints(self) -> None:
        """Clock Count 를 ms 로 환산해 보조 표시하고 입력값을 검증한다."""
        for i, edit in enumerate(self._timeouts):
            hint = self._timeout_hints[i]
            value = self._timeout_value(i)
            if value is None:
                edit.setStyleSheet("border:1px solid #f2545b;")
                hint.setText(
                    f"입력 오류: 0 ~ 0x{TIMEOUT_MAX:08X} (32비트 Unsigned) 범위의 "
                    "정수 또는 0x 16진수"
                )
                continue
            edit.setStyleSheet("")
            effective = value if value > 0 else 1
            ms = effective / (FPGA_CLOCK_HZ / 1000.0)
            suffix = " (0 → 1 로 간주)" if value == 0 else ""
            hint.setText(f"≈ {ms:,.2f} ms @100MHz{suffix}")

    def _update_warning(self) -> None:
        """`RECOVERY_COUNT < PERSIST_LIMIT` 권장 조건 검사."""
        config = self.current_config()
        if config.violates_recovery_rule():
            self.warning_label.setText(
                f"⚠ RECOVERY_COUNT({config.recovery_count}) >= "
                f"PERSIST_LIMIT({config.persist_limit}). {RECOVERY_LT_PERSIST_NOTE}"
            )
        else:
            self.warning_label.setText("")

    def invalid_timeout_indices(self) -> list[int]:
        """검증에 실패한 TIMEOUT 입력의 index 목록."""
        return [i for i in range(DEVICE_COUNT) if self._timeout_value(i) is None]

    def current_config(self) -> ConfigValues:
        """현재 입력값 묶음.

        TIMEOUT 이 잘못 입력됐으면 그 자리는 기본값으로 대체한다.
        실제 전송은 :meth:`_on_apply` 가 먼저 막는다.
        """
        timeouts = [
            self._timeout_value(i) if self._timeout_value(i) is not None
            else DEFAULT_TIMEOUT_CLOCKS[i]
            for i in range(DEVICE_COUNT)
        ]
        return ConfigValues(
            timeout0=int(timeouts[0]),
            timeout1=int(timeouts[1]),
            timeout2=int(timeouts[2]),
            critical_mask=self.critical_mask.value(),
            persist_limit=self.persist_limit.value(),
            recovery_count=self.recovery_count.value(),
            degrade_mask=self.degrade_mask.value(),
        )

    def apply_settings(self, config: dict[str, int]) -> None:
        """저장된 설정을 위젯에 채운다."""
        for i in range(DEVICE_COUNT):
            self._timeouts[i].setText(
                str(config.get(f"timeout{i}", DEFAULT_TIMEOUT_CLOCKS[i]))
            )
        self.critical_mask.setValue(config.get("critical_mask", DEFAULT_CRITICAL_MASK))
        self.persist_limit.setValue(config.get("persist_limit", DEFAULT_PERSIST_LIMIT))
        self.recovery_count.setValue(
            config.get("recovery_count", DEFAULT_RECOVERY_COUNT)
        )
        self.degrade_mask.setValue(config.get("degrade_mask", DEFAULT_DEGRADE_MASK))
        self._update_warning()

    def _on_apply(self) -> None:
        invalid = self.invalid_timeout_indices()
        if invalid:
            QMessageBox.warning(
                self,
                "입력 값 오류",
                "다음 TIMEOUT 입력이 올바르지 않습니다: "
                + ", ".join(f"TIMEOUT{i}" for i in invalid)
                + f"\n\n0 ~ 0x{TIMEOUT_MAX:08X} (32비트 Unsigned) 범위의 "
                "정수 또는 0x 16진수를 입력하십시오.",
            )
            return

        config = self.current_config()
        if config.violates_recovery_rule():
            reply = QMessageBox.warning(
                self,
                "권장 조건 위반",
                f"{RECOVERY_LT_PERSIST_NOTE}\n\n"
                f"현재 RECOVERY_COUNT={config.recovery_count}, "
                f"PERSIST_LIMIT={config.persist_limit} 입니다.\n"
                "그래도 전송하시겠습니까?",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.No,
            )
            if reply != QMessageBox.StandardButton.Yes:
                return
        self.apply_config_requested.emit(config)

    def _on_command(self, key: str, confirm: bool, message: str) -> None:
        if confirm:
            reply = QMessageBox.question(
                self,
                "명령 전송 확인",
                message,
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.No,
            )
            if reply != QMessageBox.StandardButton.Yes:
                return
        self.command_requested.emit(key)


class InjectionPanel(QWidget):
    """Fault Injection 조작 패널.

    GUI 는 주입 성공을 임의로 가정하지 않는다. 실제 모드에서는
    `$ACK` 또는 새 `$MISSION` 상태로만 반영을 확인한다.

    Signals:
        inject_requested(str, int, bool): kind, device, on.
        clear_all_requested(): 전체 해제.
        preset_requested(str): ``MULTI`` / ``MULTI_ERROR`` /
            ``CRITICAL`` / ``CRITICAL_MASK``.
    """

    inject_requested = Signal(str, int, bool)
    clear_all_requested = Signal()
    preset_requested = Signal(str)

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        root = QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(10)

        warn = QLabel(
            "⚠ Fault Injection 은 테스트 및 시연용입니다.\n"
            "실제 출력 또는 액추에이터가 연결된 환경에서는 사용 전 안전 상태를 "
            "확인하십시오."
        )
        warn.setWordWrap(True)
        self._warn_label = warn
        root.addWidget(warn)

        self._checks: dict[tuple[str, int], QCheckBox] = {}
        for device in range(DEVICE_COUNT):
            box = QGroupBox(f"DEVICE {device}")
            layout = QHBoxLayout(box)
            for kind, label in (
                ("TIMEOUT", "Timeout"),
                ("ERROR", "Error"),
                ("CRITICAL", "Critical"),
            ):
                check = QCheckBox(label)
                check.toggled.connect(
                    lambda on, k=kind, d=device: self.inject_requested.emit(k, d, on)
                )
                layout.addWidget(check)
                self._checks[(kind, device)] = check
            layout.addStretch(1)
            root.addWidget(box)

        preset = QGroupBox("시연 프리셋")
        preset_layout = QVBoxLayout(preset)

        multi_btn = QPushButton("D0 Timeout + D1 Error (단계적 상승)")
        multi_btn.setToolTip(
            "Error D1 이 먼저 서고, Device 0 의 TIMEOUT0(기본 0.3초) 이 지난 뒤에야\n"
            "Timeout D0 이 성립한다. 그래서 DEGRADED → 약 0.3초 뒤 SAFE_MODE 로\n"
            "두 번에 걸쳐 올라간다. 하드웨어 지연 없는 쪽은 아래 버튼을 쓴다."
        )
        multi_btn.clicked.connect(lambda: self.preset_requested.emit("MULTI"))
        preset_layout.addWidget(multi_btn)

        multi_error_btn = QPushButton("D0 + D1 Error (다중 장치 Multi)")
        multi_error_btn.setToolTip(
            "Error 주입은 하드웨어 지연이 없다. 그래도 두 INJECT 가 별개 UART 줄이라\n"
            "9600bps 링크에서 순차 처리돼 약 0.2초 간격 2단계로 보인다.\n"
            "DEGRADED(device 0) → SAFE_MODE / FAULT_MULTI_DEVICE(device 3).\n"
            "위 버튼과 달리 지연 원인이 Timeout 0.3초가 아니라 전송 시간뿐이다."
        )
        multi_error_btn.clicked.connect(
            lambda: self.preset_requested.emit("MULTI_ERROR")
        )
        preset_layout.addWidget(multi_error_btn)

        critical_btn = QPushButton("Device 2 Critical Demo")
        critical_btn.setToolTip(
            "기본 CRITICAL_MASK=0x04 이므로 Tick 대기 없이 Level 3 / SAFE_MODE"
        )
        critical_btn.clicked.connect(lambda: self.preset_requested.emit("CRITICAL"))
        preset_layout.addWidget(critical_btn)

        mask_btn = QPushButton("Device 2 Error (CRITICAL_MASK 확인)")
        mask_btn.setToolTip(
            "CRITICAL_MASK 는 timeout | error_flag | critical_fault 전체에 걸린다.\n"
            "Device 2 는 평범한 Error 만으로도 지속시간 없이 Level 3 이 된다."
        )
        mask_btn.clicked.connect(lambda: self.preset_requested.emit("CRITICAL_MASK"))
        preset_layout.addWidget(mask_btn)

        clear_btn = QPushButton("Clear All Injection")
        clear_btn.clicked.connect(self._on_clear_all)
        preset_layout.addWidget(clear_btn)

        root.addWidget(preset)
        root.addStretch(1)

        self.apply_theme()

    # ------------------------------------------------------------------
    def apply_theme(self) -> None:
        """테마 교체 후 인라인 스타일을 다시 그린다."""
        self._warn_label.setStyleSheet(
            f"color:{T.state_warning}; font-size:11px; font-weight:600;"
        )

    def _on_clear_all(self) -> None:
        self.set_checks_silently({})
        self.clear_all_requested.emit()

    def set_checks_silently(self, active: dict[tuple[str, int], bool]) -> None:
        """Signal 을 발생시키지 않고 체크 상태만 맞춘다."""
        for key, check in self._checks.items():
            check.blockSignals(True)
            check.setChecked(active.get(key, False))
            check.blockSignals(False)

    def set_preset_checks(self, kind: str) -> None:
        """프리셋 버튼에 맞춰 체크박스를 갱신한다."""
        if kind == "MULTI":
            self.set_checks_silently({("TIMEOUT", 0): True, ("ERROR", 1): True})
        elif kind == "MULTI_ERROR":
            self.set_checks_silently({("ERROR", 0): True, ("ERROR", 1): True})
        elif kind == "CRITICAL":
            self.set_checks_silently({("CRITICAL", 2): True})
        elif kind == "CRITICAL_MASK":
            self.set_checks_silently({("ERROR", 2): True})
