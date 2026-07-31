"""프로젝트 전역 상수.

값의 출처는 팀 공통 명세 문서다. 숫자를 코드 곳곳에 흩뿌리지 않고
여기에서만 정의한다.

근거:
    00_TEAM_COMMON_SPEC  5.1(클럭), 7장(상태/코드 인코딩), 10장(Fault 정책)
    03_MEMBER_C          5장(출력 정책), 6장(Recovery Count)
    04_TEAM_SHARED       1장(권장 초기값)
"""

from __future__ import annotations

from typing import Final

# --------------------------------------------------------------------------
# 애플리케이션
# --------------------------------------------------------------------------
APP_NAME: Final[str] = "Mission SoC Dashboard"
APP_VERSION: Final[str] = "1.0.0"
ORG_NAME: Final[str] = "mission_soc"

SETTINGS_DIR_NAME: Final[str] = ".mission_soc_dashboard"
SETTINGS_FILE_NAME: Final[str] = "settings.json"

DEFAULT_WINDOW_WIDTH: Final[int] = 1280
DEFAULT_WINDOW_HEIGHT: Final[int] = 800
MIN_WINDOW_WIDTH: Final[int] = 960
MIN_WINDOW_HEIGHT: Final[int] = 600

# --------------------------------------------------------------------------
# 하드웨어 (00 공통명세 5.1)
# --------------------------------------------------------------------------
FPGA_CLOCK_HZ: Final[int] = 100_000_000
"""시스템 클럭 100 MHz. 1 clock = 10 ns."""

DEVICE_COUNT: Final[int] = 3
"""Device 0~2 (00 공통명세 6장)."""

DEVICE_NAMES: Final[tuple[str, str, str]] = (
    "일반 센서 처리 장치",
    "통신 장치",
    "모터/핵심 제어 장치",
)

DEVICE_CRITICALITY: Final[tuple[str, str, str]] = ("일반", "중간", "Critical")

# --------------------------------------------------------------------------
# Serial (09 요구사항)
# --------------------------------------------------------------------------
DEFAULT_BAUDRATE: Final[int] = 115200
SUPPORTED_BAUDRATES: Final[tuple[int, ...]] = (
    9600,
    19200,
    38400,
    57600,
    115200,
    230400,
    460800,
    921600,
)
SERIAL_TIMEOUT_S: Final[float] = 0.1
SERIAL_ENCODING: Final[str] = "utf-8"
SERIAL_DECODE_ERRORS: Final[str] = "replace"
"""UTF-8 디코드 실패를 예외로 올리지 않고 대체 문자로 바꾼다."""

MAX_LINE_BYTES: Final[int] = 4096
"""줄바꿈 없이 이만큼 쌓이면 비정상으로 보고 폐기한다."""

LINE_TERMINATOR: Final[str] = "\n"

# --------------------------------------------------------------------------
# 프로토콜 (03_MEMBER_C 11장)
# --------------------------------------------------------------------------
MSG_PREFIX_MISSION: Final[str] = "$MISSION"
MSG_PREFIX_EVENT: Final[str] = "$EVENT"
MSG_PREFIX_ACK: Final[str] = "$ACK"
MSG_PREFIX_ERR: Final[str] = "$ERR"
MSG_PREFIX_IRQ: Final[str] = "$IRQ"

KNOWN_PREFIXES: Final[frozenset[str]] = frozenset(
    {
        MSG_PREFIX_MISSION,
        MSG_PREFIX_EVENT,
        MSG_PREFIX_ACK,
        MSG_PREFIX_ERR,
        MSG_PREFIX_IRQ,
    }
)

IRQ_FIELDS: Final[int] = 4
"""$IRQ 의 데이터 필드 수 (prefix 제외): en_mask, hb_status, fm_status, sc_status."""

# --------------------------------------------------------------------------
# IRQ_EN 마스크 (SET,IRQ_EN 인코딩 — 펌웨어 uart_proto.c 와 일치해야 한다)
# --------------------------------------------------------------------------
IRQ_EN_BIT_HB: Final[int] = 0x1
IRQ_EN_BIT_FM: Final[int] = 0x2
IRQ_EN_BIT_SC: Final[int] = 0x4
IRQ_EN_ALL: Final[int] = 0x7

IRQ_SOURCES: Final[tuple[tuple[str, str, int], ...]] = (
    # (key, 화면 표시 이름, IRQ_EN 마스크 비트)
    ("hb", "A  하트비트 감시", IRQ_EN_BIT_HB),
    ("fm", "B  고장 관리", IRQ_EN_BIT_FM),
    ("sc", "C  안전 제어", IRQ_EN_BIT_SC),
)

IRQ_EN_OFF_NOTE: Final[str] = (
    "IRQ_EN 을 끄면 IRQ_STATUS 래치는 계속 쌓이지만 ISR 이 돌지 않습니다. "
    "그동안 짧게 스쳐 가는 상태 전이(WARNING 등)를 놓칩니다. "
    "확인이 끝나면 반드시 다시 켜십시오."
)

MISSION_REQUIRED_FIELDS: Final[int] = 9
"""$MISSION 의 필수 데이터 필드 수 (prefix 제외).

timestamp, state, fault_level, fault_device, fault_code,
alive, timeout, output_enable, actuator_enable 까지 9개다
(03_MEMBER_C 11.1). 10번째 control_valid 부터는 선택이다.
"""

MISSION_MAX_FIELDS: Final[int] = 14
"""$MISSION 의 선택 필드까지 포함한 최대 개수 (03_MEMBER_C 11.1).

9개 + control_valid, state_timer, fault_count0~2.
"""

# --------------------------------------------------------------------------
# 설정 레지스터 권장 초기값 (04 체크리스트 1장 / 00 공통명세 10장)
# --------------------------------------------------------------------------
DEFAULT_CRITICAL_MASK: Final[int] = 0x04
"""Device 2 만 Critical."""

DEFAULT_PERSIST_LIMIT: Final[int] = 5
DEFAULT_RECOVERY_COUNT: Final[int] = 2
DEFAULT_DEGRADE_MASK: Final[int] = 0x01
DEFAULT_TIMEOUT_CLOCKS: Final[tuple[int, int, int]] = (
    30_000_000,  # Device 0 : 300 ms
    60_000_000,  # Device 1 : 600 ms
    15_000_000,  # Device 2 : 150 ms
)

# Validation 범위
TIMEOUT_MIN: Final[int] = 0
TIMEOUT_MAX: Final[int] = 0xFFFF_FFFF
MASK_MIN: Final[int] = 0x00
MASK_MAX: Final[int] = 0x07
PERSIST_LIMIT_MIN: Final[int] = 0
PERSIST_LIMIT_MAX: Final[int] = 255
RECOVERY_COUNT_MIN: Final[int] = 0
RECOVERY_COUNT_MAX: Final[int] = 65535

ZERO_MEANS_ONE_NOTE: Final[str] = (
    "TIMEOUTn=0, PERSIST_LIMIT=0, RECOVERY_COUNT=0 은 FPGA 에서 유효값 1 로 간주합니다."
)
RECOVERY_LT_PERSIST_NOTE: Final[str] = (
    "권장 조건: RECOVERY_COUNT < PERSIST_LIMIT "
    "(DEGRADED → WARNING 복귀 경로를 쓰려면 필요합니다.)"
)

# --------------------------------------------------------------------------
# Mock Simulator
# --------------------------------------------------------------------------
DEFAULT_MOCK_PERIOD_MS: Final[int] = 200
MIN_MOCK_PERIOD_MS: Final[int] = 20
MAX_MOCK_PERIOD_MS: Final[int] = 2000

# --------------------------------------------------------------------------
# 차트 / 로그
# --------------------------------------------------------------------------
DEFAULT_CHART_WINDOW_S: Final[int] = 60
CHART_WINDOW_CHOICES_S: Final[tuple[int, ...]] = (10, 30, 60, 120, 300)
MAX_CHART_SAMPLES: Final[int] = 10_000

DEFAULT_MAX_LOG_ROWS: Final[int] = 5_000
MAX_LOG_ROWS_LIMIT: Final[int] = 100_000

CSV_FIELDS: Final[tuple[str, ...]] = (
    "received_at",
    "timestamp_ms",
    "system_state",
    "fault_level",
    "fault_device",
    "fault_code",
    "alive_mask",
    "timeout_mask",
    "output_enable_mask",
    "actuator_enable",
    "control_valid",
    "state_timer",
    "fault_count0",
    "fault_count1",
    "fault_count2",
    "raw_line",
)

EVENT_CSV_FIELDS: Final[tuple[str, ...]] = (
    "received_at",
    "timestamp_ms",
    "message_type",
    "event_type",
    "state",
    "fault_level",
    "fault_device",
    "fault_code",
    "description",
    "raw_line",
)

LOG_FILE_PREFIX: Final[str] = "mission_log"
EVENT_LOG_FILE_PREFIX: Final[str] = "mission_events"

# --------------------------------------------------------------------------
# 색상
# --------------------------------------------------------------------------
# 색은 여기 두지 않는다. `theme.py` 의 팔레트를 `theme.T` 로 조회한다.
# 상수로 import 하면 import 시점 값이 박혀 런타임 테마 교체가 안 되기 때문이다.
#
# 19장 원칙(색상만으로 상태를 구분하지 않는다)은 그대로다.
# `state_mapper.state_icon()` 이 [ OK ] / [ ! ] / [ !! ] / [ STOP ] 기호를 준다.
