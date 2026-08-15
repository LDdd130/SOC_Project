"""데이터 모델과 Enum.

FPGA 가 보내오는 상태를 표현하는 순수 데이터 계층이다.
GUI, Serial, 파일 입출력에 의존하지 않는다.

근거:
    00_TEAM_COMMON_SPEC 7.1~7.4 (System State / Fault Level / Fault Code / Device ID)
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum, IntEnum
from typing import Any

from .constants import DEVICE_COUNT


class _NamedEnumMixin:
    """`from_raw` 로 안전하게 변환되는 Enum 공통 동작."""

    @classmethod
    def _unknown(cls) -> Any:
        return getattr(cls, "UNKNOWN")


class SystemState(Enum):
    """시스템 상태 (00 공통명세 7.1).

    FPGA 는 2비트 값으로 내보내지만 UART 문자열은 이름을 그대로 쓴다.
    """

    NORMAL = "NORMAL"
    WARNING = "WARNING"
    DEGRADED = "DEGRADED"
    SAFE_MODE = "SAFE_MODE"
    UNKNOWN = "UNKNOWN"

    @property
    def numeric(self) -> int:
        """차트용 숫자 매핑. UNKNOWN 은 -1."""
        return _STATE_TO_NUM.get(self, -1)

    @classmethod
    def from_raw(cls, raw: str) -> "SystemState":
        """대소문자와 앞뒤 공백을 허용해 변환한다. 모르는 값은 UNKNOWN."""
        token = (raw or "").strip().upper()
        try:
            return cls(token)
        except ValueError:
            return cls.UNKNOWN

    @classmethod
    def from_numeric(cls, value: int) -> "SystemState":
        return _NUM_TO_STATE.get(value, cls.UNKNOWN)


_STATE_TO_NUM: dict[SystemState, int] = {
    SystemState.NORMAL: 0,
    SystemState.WARNING: 1,
    SystemState.DEGRADED: 2,
    SystemState.SAFE_MODE: 3,
}
_NUM_TO_STATE: dict[int, SystemState] = {v: k for k, v in _STATE_TO_NUM.items()}


class FaultLevel(IntEnum):
    """Fault 등급 (00 공통명세 7.2). 2비트 0~3 으로 고정한다."""

    LEVEL_0_NORMAL = 0
    LEVEL_1_WARNING = 1
    LEVEL_2_DEGRADED = 2
    LEVEL_3_SAFE = 3
    UNKNOWN = -1

    @classmethod
    def from_raw(cls, value: int) -> "FaultLevel":
        try:
            return cls(value)
        except ValueError:
            return cls.UNKNOWN

    @property
    def label(self) -> str:
        if self is FaultLevel.UNKNOWN:
            return "LEVEL ?"
        return f"LEVEL {int(self)}"


class FaultDevice(IntEnum):
    """주요 고장 장치 (00 공통명세 7.4)."""

    DEVICE_0 = 0
    DEVICE_1 = 1
    DEVICE_2 = 2
    MULTIPLE_OR_NONE = 3
    UNKNOWN = -1

    @classmethod
    def from_raw(cls, value: int) -> "FaultDevice":
        try:
            return cls(value)
        except ValueError:
            return cls.UNKNOWN

    @property
    def label(self) -> str:
        return self.name


class FaultCode(IntEnum):
    """Fault Code (00 공통명세 7.3)."""

    FAULT_NONE = 0x00
    FAULT_TIMEOUT = 0x01
    FAULT_ERROR_CODE = 0x02
    FAULT_CRITICAL = 0x03
    FAULT_MULTI_DEVICE = 0x04
    FAULT_RECOVERY_REQUIRED = 0x05
    UNKNOWN = -1

    @classmethod
    def from_raw(cls, value: int) -> "FaultCode":
        try:
            return cls(value)
        except ValueError:
            return cls.UNKNOWN

    @property
    def label(self) -> str:
        return self.name


class ConnectionState(Enum):
    """상단 연결 패널 표시용 상태."""

    DISCONNECTED = "DISCONNECTED"
    CONNECTING = "CONNECTING"
    CONNECTED = "CONNECTED"
    MOCK_CONNECTED = "MOCK_CONNECTED"
    ERROR = "ERROR"

    @property
    def korean(self) -> str:
        return _CONNECTION_KOREAN[self]


_CONNECTION_KOREAN: dict[ConnectionState, str] = {
    ConnectionState.DISCONNECTED: "연결 안 됨",
    ConnectionState.CONNECTING: "연결 중",
    ConnectionState.CONNECTED: "연결됨",
    ConnectionState.MOCK_CONNECTED: "Mock 연결됨",
    ConnectionState.ERROR: "오류",
}


def _bit(mask: int, index: int) -> bool:
    """`mask` 의 `index` 번째 비트를 bool 로 반환한다.

    범위를 벗어난 index 는 False 로 처리해 GUI 가 죽지 않게 한다.
    """
    if index < 0 or index >= DEVICE_COUNT:
        return False
    return bool((mask >> index) & 0x1)


@dataclass(frozen=True, slots=True)
class MissionStatus:
    """`$MISSION` 한 줄을 파싱한 결과."""

    timestamp_ms: int
    system_state: SystemState
    fault_level: FaultLevel
    fault_device: FaultDevice
    fault_code: FaultCode
    alive_mask: int
    timeout_mask: int
    output_enable_mask: int
    actuator_enable: bool
    raw_line: str
    received_at: datetime
    control_valid: bool | None = None
    state_timer: int | None = None
    fault_counts: tuple[int, int, int] | None = None

    # -- 편의 접근자 -------------------------------------------------------
    def is_alive(self, device_index: int) -> bool:
        return _bit(self.alive_mask, device_index)

    def is_timeout(self, device_index: int) -> bool:
        return _bit(self.timeout_mask, device_index)

    def is_output_enabled(self, device_index: int) -> bool:
        return _bit(self.output_enable_mask, device_index)

    def is_fault_target(self, device_index: int) -> bool:
        """이 장치가 현재 `fault_device` 로 지목됐는지."""
        return self.fault_device.value == device_index

    def fault_count(self, device_index: int) -> int | None:
        if self.fault_counts is None:
            return None
        if 0 <= device_index < len(self.fault_counts):
            return self.fault_counts[device_index]
        return None


@dataclass(frozen=True, slots=True)
class MissionEvent:
    """`$EVENT` 한 줄."""

    timestamp_ms: int
    event_type: str
    args: tuple[str, ...]
    raw_line: str
    received_at: datetime

    @property
    def description(self) -> str:
        if not self.args:
            return self.event_type
        return f"{self.event_type} ({', '.join(self.args)})"


@dataclass(frozen=True, slots=True)
class IrqStatus:
    """`$IRQ` 한 줄. 세 IP 의 IRQ_EN / IRQ_STATUS 스냅샷이다.

    `en_mask` 는 `SET,IRQ_EN` 과 같은 인코딩(bit0=A, bit1=B, bit2=C)이고,
    `*_status` 는 각 IP 의 IRQ_STATUS 레지스터 원본값이다.

    평상시 `*_status` 는 전부 0 이다. ISR 이 인터럽트 진입 즉시 W1C 하기
    때문이다. 0 이 아닌 값을 보려면 `SET,IRQ_EN,0` 으로 irq 핀을 막아 ISR 을
    멈춘 뒤 고장을 넣어야 한다 (05 시나리오 15번).
    """

    en_mask: int
    hb_status: int
    fm_status: int
    sc_status: int
    raw_line: str
    received_at: datetime

    def enabled(self, bit: int) -> bool:
        """`IRQ_EN_BIT_*` 하나가 켜져 있는지."""
        return bool(self.en_mask & bit)

    def status_of(self, key: str) -> int:
        """`IRQ_SOURCES` 의 key 로 해당 IP 의 IRQ_STATUS 를 꺼낸다."""
        return {
            "hb": self.hb_status,
            "fm": self.fm_status,
            "sc": self.sc_status,
        }[key]

    @property
    def any_pending(self) -> bool:
        return bool(self.hb_status or self.fm_status or self.sc_status)

    @property
    def description(self) -> str:
        return (
            f"EN=0b{self.en_mask:03b} "
            f"PENDING A=0x{self.hb_status:02X} "
            f"B=0x{self.fm_status:02X} C=0x{self.sc_status:02X}"
        )


@dataclass(frozen=True, slots=True)
class CommandResponse:
    """`$ACK` 또는 `$ERR` 한 줄."""

    is_ack: bool
    command: str
    args: tuple[str, ...]
    raw_line: str
    received_at: datetime

    @property
    def description(self) -> str:
        head = "ACK" if self.is_ack else "ERR"
        if not self.args:
            return f"{head} {self.command}"
        return f"{head} {self.command}: {', '.join(self.args)}"

    @property
    def is_unknown_command(self) -> bool:
        """FPGA 펌웨어가 지원하지 않는 명령인지."""
        if self.is_ack:
            return False
        tokens = (self.command, *self.args)
        return any("UNKNOWN_COMMAND" in t.upper() for t in tokens)


@dataclass(frozen=True, slots=True)
class ParseResult:
    """Parser 반환값.

    Parser 는 예외를 GUI 로 전파하지 않는다. 실패도 결과 객체로 돌려준다.
    """

    success: bool
    message_type: str
    raw_line: str
    status: MissionStatus | None = None
    event: MissionEvent | None = None
    response: CommandResponse | None = None
    irq: IrqStatus | None = None
    error: str | None = None

    @property
    def is_raw_text(self) -> bool:
        """`$` 로 시작하지 않는 디버그 문자열인지."""
        return self.message_type == "RAW"


@dataclass(slots=True)
class DeviceStatus:
    """Device 카드 한 장이 표시할 값."""

    index: int
    alive: bool = False
    timeout: bool = False
    output_enabled: bool = False
    is_fault_target: bool = False
    fault_count: int | None = None

    @classmethod
    def from_status(cls, status: MissionStatus, index: int) -> "DeviceStatus":
        return cls(
            index=index,
            alive=status.is_alive(index),
            timeout=status.is_timeout(index),
            output_enabled=status.is_output_enabled(index),
            is_fault_target=status.is_fault_target(index),
            fault_count=status.fault_count(index),
        )


@dataclass(slots=True)
class SerialStatistics:
    """Serial 패널에 표시할 누적 통계."""

    bytes_received: int = 0
    messages_received: int = 0
    parse_errors: int = 0
    last_received_at: datetime | None = None

    def reset(self) -> None:
        self.bytes_received = 0
        self.messages_received = 0
        self.parse_errors = 0
        self.last_received_at = None


@dataclass(slots=True)
class ConfigValues:
    """제어 패널의 설정 레지스터 묶음."""

    timeout0: int
    timeout1: int
    timeout2: int
    critical_mask: int
    persist_limit: int
    recovery_count: int
    degrade_mask: int

    def timeouts(self) -> tuple[int, int, int]:
        return (self.timeout0, self.timeout1, self.timeout2)

    def violates_recovery_rule(self) -> bool:
        """`RECOVERY_COUNT < PERSIST_LIMIT` 권장 조건 위반 여부.

        0 은 FPGA 에서 1 로 간주되므로 비교 전에 보정한다.
        """
        persist = self.persist_limit if self.persist_limit else 1
        recovery = self.recovery_count if self.recovery_count else 1
        return recovery >= persist

    def to_dict(self) -> dict[str, int]:
        return {
            "timeout0": self.timeout0,
            "timeout1": self.timeout1,
            "timeout2": self.timeout2,
            "critical_mask": self.critical_mask,
            "persist_limit": self.persist_limit,
            "recovery_count": self.recovery_count,
            "degrade_mask": self.degrade_mask,
        }


@dataclass(slots=True)
class LogRow:
    """Event Log 테이블 한 행."""

    received_at: datetime
    timestamp_ms: int | None
    message_type: str
    event_type: str = ""
    state: str = ""
    fault_level: str = ""
    fault_device: str = ""
    fault_code: str = ""
    description: str = ""
    raw_line: str = ""
    is_error: bool = False
    is_event: bool = False

    def as_columns(self) -> list[str]:
        ts = "" if self.timestamp_ms is None else str(self.timestamp_ms)
        return [
            self.received_at.strftime("%H:%M:%S.%f")[:-3],
            ts,
            self.message_type,
            self.event_type,
            self.state,
            self.fault_level,
            self.fault_device,
            self.fault_code,
            self.description,
            self.raw_line,
        ]


@dataclass(slots=True)
class ChartSample:
    """차트 한 점."""

    t_s: float
    fault_level: int
    state_numeric: int
    actuator_enable: int
    timeout_mask: int
    timeouts: tuple[int, int, int] = field(default_factory=lambda: (0, 0, 0))
