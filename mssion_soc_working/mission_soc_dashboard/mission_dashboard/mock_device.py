"""FPGA 없이 앱 전체를 시험하기 위한 Mock Simulator.

명세의 핵심 정책을 재현한다. RTL 검증 도구가 아니라 GUI 시연/테스트용이다.

재현 범위:
    00_TEAM_COMMON_SPEC 10장  Fault 정책 우선순위
    00_TEAM_COMMON_SPEC 11장  Safety FSM 및 Recovery 정책
    02_MEMBER_B         3장   Fault Code / Device 결정 규칙
    03_MEMBER_C         5장   상태별 출력 정책

의도적으로 재현하지 않는 것:
    - 100MHz 클럭 단위 타이밍
    - Heartbeat Counter 의 실제 Clock Count
      (Timeout 은 주입 명령으로 직접 제어한다)

이 클래스는 Qt 에 의존하지 않는다. 순수 파이썬이라 pytest 로 직접 돌린다.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .constants import (
    DEFAULT_CRITICAL_MASK,
    DEFAULT_DEGRADE_MASK,
    DEFAULT_PERSIST_LIMIT,
    DEFAULT_RECOVERY_COUNT,
    DEFAULT_TIMEOUT_CLOCKS,
    DEVICE_COUNT,
    IRQ_EN_ALL,
    IRQ_EN_BIT_FM,
    IRQ_EN_BIT_HB,
    IRQ_EN_BIT_SC,
)
from .models import FaultCode, FaultDevice, FaultLevel, SystemState

__all__ = ["MockConfig", "MockDevice"]


def _effective(value: int) -> int:
    """0 을 유효값 1 로 간주한다 (00 공통명세 12.1)."""
    return value if value > 0 else 1


def _popcount3(mask: int) -> int:
    return bin(mask & 0b111).count("1")


@dataclass(slots=True)
class MockConfig:
    """FPGA 설정 레지스터의 Mock 사본."""

    timeout: list[int] = field(default_factory=lambda: list(DEFAULT_TIMEOUT_CLOCKS))
    critical_mask: int = DEFAULT_CRITICAL_MASK
    persist_limit: int = DEFAULT_PERSIST_LIMIT
    recovery_count: int = DEFAULT_RECOVERY_COUNT
    degrade_mask: int = DEFAULT_DEGRADE_MASK


class MockDevice:
    """MicroBlaze + 3개 Custom IP 의 동작을 흉내내는 시뮬레이터.

    사용법::

        dev = MockDevice()
        lines = dev.tick()          # $MISSION / $EVENT 문자열 목록
        replies = dev.handle_command("CMD,MANUAL_RESET")

    시간은 :meth:`tick` 호출 횟수로 센다. 한 tick 이 공통 ``eval_tick`` 한 번에
    대응한다고 본다.
    """

    def __init__(self, config: MockConfig | None = None) -> None:
        self.config = config or MockConfig()

        # 주입된 입력 (AXI GPIO 또는 보드 스위치에 해당)
        self.timeout_inject = 0
        self.error_inject = 0
        self.critical_inject = 0

        # Fault Manager 내부 상태
        self.fault_counts = [0, 0, 0]
        self.fault_level = FaultLevel.LEVEL_0_NORMAL
        self.fault_device = FaultDevice.MULTIPLE_OR_NONE
        self.fault_code = FaultCode.FAULT_NONE
        self.fault_valid = True

        # Safety Controller 내부 상태
        self.system_state = SystemState.NORMAL
        self.recovery_counter = 0
        self._recovery_target: SystemState | None = None
        self.state_timer = 0

        # 출력
        self.output_enable = 0b111
        self.actuator_enable = True
        self.control_valid = True

        self.timestamp_ms = 0
        self._tick_ms = 0
        self.enabled = True

        self._prev_state = self.system_state
        self._prev_fault_key: tuple[int, int, int] = (0, 3, 0)
        self._prev_timeout_mask = 0
        self._boot_sent = False

        # -- IRQ 모델 ----------------------------------------------------
        # 실물과 같은 규칙으로 흉내낸다.
        #   * IRQ_STATUS 의 Set 은 IRQ_EN 과 무관하다.
        #   * irq 핀 = IRQ_STATUS & IRQ_EN. 핀이 올라가야 ISR 이 돈다.
        #   * ISR 만 W1C 한다. 그래서 IRQ_EN=0 이면 Pending 이 그대로 쌓인다.
        # 이 성질이 없으면 05 시나리오 15번(CLEAR_IRQ 검증)을 Mock 으로
        # 연습할 수 없다.
        self.irq_en_mask = IRQ_EN_ALL
        self.irq_pending_hb = 0      # bit[2:0] Device 별 Timeout
        self.irq_pending_fm = 0      # bit0
        self.irq_pending_sc = 0      # bit0

    # ------------------------------------------------------------------
    # 입력 집계
    # ------------------------------------------------------------------
    @property
    def timeout_mask(self) -> int:
        return self.timeout_inject & 0b111

    @property
    def device_fault_mask(self) -> int:
        """``device_fault = timeout | error_flag | critical_fault``."""
        return (self.timeout_inject | self.error_inject | self.critical_inject) & 0b111

    @property
    def alive_mask(self) -> int:
        """Timeout 이 아닌 장치가 alive (01_MEMBER_A 3.3)."""
        if not self.enabled:
            return 0
        return (~self.timeout_mask) & 0b111

    # ------------------------------------------------------------------
    # Fault Manager 정책 (00 공통명세 10장)
    # ------------------------------------------------------------------
    def _evaluate_fault(self) -> None:
        """현재 입력으로 fault_level/device/code 를 다시 계산한다."""
        device_fault = self.device_fault_mask
        critical_condition = device_fault & (self.config.critical_mask & 0b111)

        # -- 지속 Count 갱신. eval_tick 에서만 증가한다 (00 5.2) -----------
        limit = _effective(self.config.persist_limit)
        for i in range(DEVICE_COUNT):
            if (device_fault >> i) & 1:
                self.fault_counts[i] = min(255, self.fault_counts[i] + 1)
            else:
                self.fault_counts[i] = 0

        # -- 우선순위 1 : Critical --------------------------------------
        if critical_condition:
            self.fault_level = FaultLevel.LEVEL_3_SAFE
            self.fault_code = FaultCode.FAULT_CRITICAL
            if _popcount3(critical_condition) == 1:
                self.fault_device = FaultDevice(critical_condition.bit_length() - 1)
            else:
                self.fault_device = FaultDevice.MULTIPLE_OR_NONE
            return

        # -- 우선순위 2 : 다중 장치 --------------------------------------
        if _popcount3(device_fault) >= 2:
            self.fault_level = FaultLevel.LEVEL_3_SAFE
            self.fault_code = FaultCode.FAULT_MULTI_DEVICE
            self.fault_device = FaultDevice.MULTIPLE_OR_NONE
            return

        # -- 우선순위 5 : Fault 없음 -------------------------------------
        if device_fault == 0:
            self.fault_level = FaultLevel.LEVEL_0_NORMAL
            self.fault_code = FaultCode.FAULT_NONE
            self.fault_device = FaultDevice.MULTIPLE_OR_NONE
            return

        # -- 단일 장치 Fault : 우선순위 3(지속) 또는 4(일시) --------------
        index = device_fault.bit_length() - 1
        self.fault_device = FaultDevice(index)

        # 같은 장치에 Timeout 과 Error 가 겹치면 ERROR_CODE 가 우선 (02 3장)
        if (self.error_inject >> index) & 1:
            self.fault_code = FaultCode.FAULT_ERROR_CODE
        elif (self.critical_inject >> index) & 1:
            # Mask 밖 critical_fault 도 ERROR_CODE 로 본다 (02 3장 Code 우선순위)
            self.fault_code = FaultCode.FAULT_ERROR_CODE
        else:
            self.fault_code = FaultCode.FAULT_TIMEOUT

        if self.fault_counts[index] >= limit:
            self.fault_level = FaultLevel.LEVEL_2_DEGRADED
        else:
            self.fault_level = FaultLevel.LEVEL_1_WARNING

    # ------------------------------------------------------------------
    # Safety FSM (00 공통명세 11장)
    # ------------------------------------------------------------------
    def _target_state_for_level(self) -> SystemState:
        return {
            FaultLevel.LEVEL_0_NORMAL: SystemState.NORMAL,
            FaultLevel.LEVEL_1_WARNING: SystemState.WARNING,
            FaultLevel.LEVEL_2_DEGRADED: SystemState.DEGRADED,
            FaultLevel.LEVEL_3_SAFE: SystemState.SAFE_MODE,
        }.get(self.fault_level, SystemState.NORMAL)

    def _evaluate_state(self) -> None:
        """Fault Level 에 따라 System State 를 전이한다."""
        level = self.fault_level
        current = self.system_state
        recovery_needed = _effective(self.config.recovery_count)

        # SAFE_MODE 는 Latch. 자동 복귀 금지 (00 11장)
        if current is SystemState.SAFE_MODE:
            self.recovery_counter = 0
            self._recovery_target = None
            return

        # 등급 상승은 즉시 반영한다
        if level is FaultLevel.LEVEL_3_SAFE:
            self._set_state(SystemState.SAFE_MODE)
            return
        if level is FaultLevel.LEVEL_2_DEGRADED:
            self._set_state(SystemState.DEGRADED)
            return

        if current is SystemState.NORMAL:
            if level is FaultLevel.LEVEL_1_WARNING:
                self._set_state(SystemState.WARNING)
            self.recovery_counter = 0
            self._recovery_target = None
            return

        # -- 복귀 판단. WARNING / DEGRADED 에서만 발생한다 ----------------
        if current is SystemState.WARNING:
            # Level 1 이면 그대로 WARNING 유지
            target = SystemState.NORMAL if level is FaultLevel.LEVEL_0_NORMAL else None
        elif current is SystemState.DEGRADED:
            if level is FaultLevel.LEVEL_0_NORMAL:
                target = SystemState.NORMAL
            elif level is FaultLevel.LEVEL_1_WARNING:
                # Level 1 에서 NORMAL 직행 금지. WARNING 까지만 (04 서두)
                target = SystemState.WARNING
            else:
                target = None
        else:
            target = None

        if target is None:
            self.recovery_counter = 0
            self._recovery_target = None
            return

        # 목표가 바뀌면 Counter 초기화 (03_MEMBER_C 6장)
        if self._recovery_target is not target:
            self._recovery_target = target
            self.recovery_counter = 0

        self.recovery_counter += 1
        if self.recovery_counter >= recovery_needed:
            self._set_state(target)
            self.recovery_counter = 0
            self._recovery_target = None

    def _set_state(self, state: SystemState) -> None:
        if state is not self.system_state:
            self.system_state = state
            self.state_timer = 0
            self.recovery_counter = 0
            self._recovery_target = None

    # ------------------------------------------------------------------
    # 출력 정책 (03_MEMBER_C 5장)
    # ------------------------------------------------------------------
    def _apply_outputs(self) -> None:
        if not self.enabled:
            self.output_enable = 0b000
            self.actuator_enable = False
            self.control_valid = False
            return

        state = self.system_state
        if state in (SystemState.NORMAL, SystemState.WARNING):
            self.output_enable = 0b111
            self.actuator_enable = True
            self.control_valid = True
        elif state is SystemState.DEGRADED:
            device = self.fault_device
            if device is FaultDevice.DEVICE_0:
                self.output_enable = 0b110
            elif device is FaultDevice.DEVICE_1:
                self.output_enable = 0b101
            elif device is FaultDevice.DEVICE_2:
                self.output_enable = 0b011
            else:
                self.output_enable = 0b111 & ~(self.config.degrade_mask & 0b111)
            self.actuator_enable = True
            self.control_valid = True
        else:  # SAFE_MODE
            self.output_enable = 0b000
            self.actuator_enable = False
            self.control_valid = False

    # ------------------------------------------------------------------
    # tick
    # ------------------------------------------------------------------
    def tick(self, period_ms: int = 200) -> list[str]:
        """한 주기 진행하고 내보낼 UART 줄 목록을 만든다.

        Args:
            period_ms: 이번 주기의 밀리초. FPGA timestamp 증가에 쓴다.

        Returns:
            ``$MISSION`` 과 필요 시 ``$EVENT`` 문자열 목록.
        """
        lines: list[str] = []

        if not self._boot_sent:
            self._boot_sent = True
            lines.append("Boot complete")
            lines.append("Interrupt controller initialized")

        self._tick_ms = max(1, period_ms)
        self.timestamp_ms += self._tick_ms
        self.state_timer += self._tick_ms

        self._evaluate_fault()
        self._evaluate_state()
        self._apply_outputs()

        # -- Event 생성 --------------------------------------------------
        fault_key = (
            int(self.fault_level),
            int(self.fault_device),
            int(self.fault_code),
        )
        if fault_key != self._prev_fault_key:
            lines.append(
                f"$EVENT,{self.timestamp_ms},FAULT_CHANGE,"
                f"{fault_key[0]},{fault_key[1]},{fault_key[2]}"
            )
            self._prev_fault_key = fault_key
            self.irq_pending_fm = 1

        if self.system_state is not self._prev_state:
            lines.append(
                f"$EVENT,{self.timestamp_ms},STATE_CHANGE,{self.system_state.value}"
            )
            self._prev_state = self.system_state
            self.irq_pending_sc = 1

        new_timeouts = self.timeout_mask & ~self._prev_timeout_mask
        for i in range(DEVICE_COUNT):
            if (new_timeouts >> i) & 1:
                lines.append(f"$EVENT,{self.timestamp_ms},HEARTBEAT_TIMEOUT,{i}")
        self.irq_pending_hb |= new_timeouts & 0x7
        self._prev_timeout_mask = self.timeout_mask

        self._service_irq()

        lines.append(self.build_mission_line())
        return lines

    def _service_irq(self) -> None:
        """ISR 을 흉내낸다. irq 핀이 올라간 IP 의 Pending 만 W1C 한다.

        IRQ_EN 이 꺼진 IP 는 핀이 안 올라가 ISR 이 돌지 않으므로 Pending 이
        그대로 남는다. 실물과 같은 동작이다.
        """
        if self.irq_en_mask & IRQ_EN_BIT_HB:
            self.irq_pending_hb = 0
        if self.irq_en_mask & IRQ_EN_BIT_FM:
            self.irq_pending_fm = 0
        if self.irq_en_mask & IRQ_EN_BIT_SC:
            self.irq_pending_sc = 0

    def build_irq_line(self) -> str:
        """현재 IRQ_EN / IRQ_STATUS 를 `$IRQ` 한 줄로 직렬화한다."""
        return (
            f"$IRQ,0x{self.irq_en_mask:02X},"
            f"0x{self.irq_pending_hb:02X},"
            f"0x{self.irq_pending_fm:02X},"
            f"0x{self.irq_pending_sc:02X}"
        )

    def build_mission_line(self) -> str:
        """현재 상태를 `$MISSION` 한 줄로 직렬화한다 (확장 필드 포함)."""
        return (
            f"$MISSION,{self.timestamp_ms},{self.system_state.value},"
            f"{int(self.fault_level)},{int(self.fault_device)},"
            f"{int(self.fault_code)},"
            f"0x{self.alive_mask:02X},0x{self.timeout_mask:02X},"
            f"0x{self.output_enable:02X},{int(self.actuator_enable)},"
            f"{int(self.control_valid)},{self.state_timer},"
            f"{self.fault_counts[0]},{self.fault_counts[1]},{self.fault_counts[2]}"
        )

    # ------------------------------------------------------------------
    # 명령 처리
    # ------------------------------------------------------------------
    def handle_command(self, command: str) -> list[str]:
        """Python 이 보낸 명령 한 줄을 처리하고 응답 줄을 돌려준다."""
        text = (command or "").strip()
        if not text:
            return ["$ERR,UNKNOWN_COMMAND,empty"]

        parts = [p.strip() for p in text.split(",")]
        head = parts[0].upper()

        try:
            if head == "GET":
                return self._handle_get(parts)
            if head == "SET":
                return self._handle_set(parts)
            if head == "CMD":
                return self._handle_cmd(parts)
            if head == "INJECT":
                return self._handle_inject(parts)
        except Exception as exc:  # pragma: no cover - 방어적
            return [f"$ERR,INTERNAL,{exc}"]

        return ["$ERR,UNKNOWN_COMMAND"]

    def _handle_get(self, parts: list[str]) -> list[str]:
        if len(parts) < 2:
            return ["$ERR,UNKNOWN_COMMAND,GET"]
        what = parts[1].upper()
        if what == "STATUS":
            return ["$ACK,GET,STATUS", self.build_mission_line()]
        if what == "CONFIG":
            cfg = self.config
            return [
                "$ACK,GET,CONFIG",
                f"$ACK,SET,TIMEOUT0,{cfg.timeout[0]}",
                f"$ACK,SET,TIMEOUT1,{cfg.timeout[1]}",
                f"$ACK,SET,TIMEOUT2,{cfg.timeout[2]}",
                f"$ACK,SET,CRITICAL_MASK,0x{cfg.critical_mask:02X}",
                f"$ACK,SET,PERSIST_LIMIT,{cfg.persist_limit}",
                f"$ACK,SET,RECOVERY_COUNT,{cfg.recovery_count}",
                f"$ACK,SET,DEGRADE_MASK,0x{cfg.degrade_mask:02X}",
                f"$ACK,SET,IRQ_EN,0x{self.irq_en_mask:02X}",
            ]
        if what == "IRQ":
            return ["$ACK,GET,IRQ", self.build_irq_line()]
        return ["$ERR,UNKNOWN_COMMAND,GET"]

    def _handle_set(self, parts: list[str]) -> list[str]:
        from .protocol import parse_int  # 지역 import 로 순환 참조 회피

        if len(parts) < 3:
            return ["$ERR,UNKNOWN_COMMAND,SET"]
        name = parts[1].upper()

        if name == "TIMEOUT":
            if len(parts) < 4:
                return ["$ERR,INVALID_VALUE,TIMEOUT"]
            dev = parse_int(parts[2])
            val = parse_int(parts[3])
            if dev is None or not (0 <= dev < DEVICE_COUNT) or val is None or val < 0:
                return ["$ERR,INVALID_VALUE,TIMEOUT"]
            self.config.timeout[dev] = val
            return [f"$ACK,SET,TIMEOUT{dev},{val}"]

        value = parse_int(parts[2])
        if value is None or value < 0:
            return [f"$ERR,INVALID_VALUE,{name}"]

        if name == "CRITICAL_MASK":
            if value > 0x07:
                return ["$ERR,INVALID_VALUE,CRITICAL_MASK"]
            self.config.critical_mask = value
        elif name == "PERSIST_LIMIT":
            if value > 255:
                return ["$ERR,INVALID_VALUE,PERSIST_LIMIT"]
            self.config.persist_limit = value
        elif name == "RECOVERY_COUNT":
            if value > 65535:
                return ["$ERR,INVALID_VALUE,RECOVERY_COUNT"]
            self.config.recovery_count = value
        elif name == "DEGRADE_MASK":
            if value > 0x07:
                return ["$ERR,INVALID_VALUE,DEGRADE_MASK"]
            self.config.degrade_mask = value
        elif name == "IRQ_EN":
            if value > IRQ_EN_ALL:
                return ["$ERR,INVALID_VALUE,IRQ_EN"]
            self.irq_en_mask = value
            # 방금 켠 IP 는 밀린 Pending 을 즉시 소화한다 (실물의 ISR 과 같다).
            self._service_irq()
        else:
            return ["$ERR,UNKNOWN_COMMAND,SET"]

        return [f"$ACK,SET,{name},{value}"]

    def _handle_cmd(self, parts: list[str]) -> list[str]:
        if len(parts) < 2:
            return ["$ERR,UNKNOWN_COMMAND,CMD"]
        what = parts[1].upper()

        if what == "MANUAL_RESET":
            return self._manual_reset()
        if what == "CLEAR_IRQ":
            # 세 IP 의 IRQ_STATUS 를 W1C 한다. Fault/Timeout 상태는 그대로다.
            self.irq_pending_hb = 0
            self.irq_pending_fm = 0
            self.irq_pending_sc = 0
            return ["$ACK,CMD,CLEAR_IRQ"]
        if what == "CLEAR_HEARTBEAT":
            # Heartbeat Counter/Timeout Clear. 주입이 살아 있으면 곧 다시 뜬다.
            self.timeout_inject = 0
            return ["$ACK,CMD,CLEAR_HEARTBEAT"]
        if what == "RESET_FAULT":
            if self.device_fault_mask != 0:
                # 활성 Fault 가 있으면 무시한다 (02_MEMBER_B 6.1)
                return ["$ERR,RESET_FAULT,FAULT_ACTIVE"]
            self.fault_counts = [0, 0, 0]
            return ["$ACK,CMD,RESET_FAULT"]

        return ["$ERR,UNKNOWN_COMMAND,CMD"]

    def _manual_reset(self) -> list[str]:
        """SAFE_MODE 복구. fault_valid=1 이고 Level 0 일 때만 승인한다."""
        if not self.fault_valid:
            return ["$ERR,MANUAL_RESET,FAULT_INVALID"]
        if self.fault_level is not FaultLevel.LEVEL_0_NORMAL:
            return ["$ERR,MANUAL_RESET,FAULT_ACTIVE"]

        self._set_state(SystemState.NORMAL)
        self._apply_outputs()
        return [
            "$ACK,CMD,MANUAL_RESET",
            f"$EVENT,{self.timestamp_ms},STATE_CHANGE,NORMAL",
        ]

    def _handle_inject(self, parts: list[str]) -> list[str]:
        from .protocol import parse_int

        if len(parts) < 2:
            return ["$ERR,UNKNOWN_COMMAND,INJECT"]

        kind = parts[1].upper()
        if kind == "CLEAR":
            self.timeout_inject = 0
            self.error_inject = 0
            self.critical_inject = 0
            return ["$ACK,INJECT,CLEAR,ALL"]

        if len(parts) < 4:
            return ["$ERR,UNKNOWN_COMMAND,INJECT"]

        dev = parse_int(parts[2])
        if dev is None or not (0 <= dev < DEVICE_COUNT):
            return ["$ERR,INVALID_VALUE,DEVICE"]

        on_token = parts[3].upper()
        if on_token not in {"ON", "OFF"}:
            return ["$ERR,INVALID_VALUE,ON_OFF"]
        on = on_token == "ON"
        bit = 1 << dev

        if kind == "TIMEOUT":
            self.timeout_inject = (self.timeout_inject | bit) if on else (
                self.timeout_inject & ~bit
            )
        elif kind == "ERROR":
            self.error_inject = (self.error_inject | bit) if on else (
                self.error_inject & ~bit
            )
        elif kind == "CRITICAL":
            self.critical_inject = (self.critical_inject | bit) if on else (
                self.critical_inject & ~bit
            )
        else:
            return ["$ERR,UNKNOWN_COMMAND,INJECT"]

        return [f"$ACK,INJECT,{kind},{dev},{on_token}"]

    # ------------------------------------------------------------------
    def clear_all_injection(self) -> None:
        """테스트 편의용 직접 해제."""
        self.timeout_inject = 0
        self.error_inject = 0
        self.critical_inject = 0
