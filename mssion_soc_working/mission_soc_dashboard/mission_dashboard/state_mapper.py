"""상태 값을 화면 표시용 문자열/색상으로 바꾸는 계층.

GUI 위젯이 Enum 해석 로직을 각자 갖지 않도록 여기에 모은다.
정책 판단은 하지 않는다. FPGA 수신값을 그대로 표시하는 것이 원칙이다.
"""

from __future__ import annotations

from .constants import (
    DEFAULT_DEGRADE_MASK,
    DEVICE_COUNT,
    DEVICE_NAMES,
)
from .models import (
    FaultCode,
    FaultDevice,
    FaultLevel,
    MissionStatus,
    SystemState,
)
from .theme import T

__all__ = [
    "state_color",
    "state_korean",
    "state_icon",
    "level_color",
    "mask_to_bits",
    "mask_to_text",
    "device_title",
    "expected_output_enable",
    "check_policy",
    "bool_text",
]


# 값이 아니라 **팔레트 키**를 담는다. 테마가 바뀌면 조회 결과도 따라 바뀐다.
_STATE_COLOR_KEYS: dict[SystemState, str] = {
    SystemState.NORMAL: "state_normal",
    SystemState.WARNING: "state_warning",
    SystemState.DEGRADED: "state_degraded",
    SystemState.SAFE_MODE: "state_safe_mode",
    SystemState.UNKNOWN: "state_unknown",
}

_STATE_KOREAN: dict[SystemState, str] = {
    SystemState.NORMAL: "정상",
    SystemState.WARNING: "경고",
    SystemState.DEGRADED: "성능 저하",
    SystemState.SAFE_MODE: "안전 모드",
    SystemState.UNKNOWN: "알 수 없음",
}

# 색상만으로 상태를 구분하지 않기 위한 텍스트 기호 (19장 요구사항)
_STATE_ICON: dict[SystemState, str] = {
    SystemState.NORMAL: "[ OK ]",
    SystemState.WARNING: "[ ! ]",
    SystemState.DEGRADED: "[ !! ]",
    SystemState.SAFE_MODE: "[ STOP ]",
    SystemState.UNKNOWN: "[ ? ]",
}

_LEVEL_COLOR_KEYS: dict[FaultLevel, str] = {
    FaultLevel.LEVEL_0_NORMAL: "state_normal",
    FaultLevel.LEVEL_1_WARNING: "state_warning",
    FaultLevel.LEVEL_2_DEGRADED: "state_degraded",
    FaultLevel.LEVEL_3_SAFE: "state_safe_mode",
    FaultLevel.UNKNOWN: "state_unknown",
}


def state_color(state: SystemState) -> str:
    """상태별 강조 색상 코드. 현재 테마 기준이다."""
    return T[_STATE_COLOR_KEYS.get(state, "state_unknown")]


def state_korean(state: SystemState) -> str:
    """상태의 한국어 설명. 상태 이름 자체는 영어 원문을 유지한다."""
    return _STATE_KOREAN.get(state, "알 수 없음")


def state_icon(state: SystemState) -> str:
    """색맹 사용자를 위한 텍스트 기호."""
    return _STATE_ICON.get(state, "[ ? ]")


def level_color(level: FaultLevel) -> str:
    return T[_LEVEL_COLOR_KEYS.get(level, "state_unknown")]


def bool_text(value: bool | None, *, true_text: str = "ON", false_text: str = "OFF") -> str:
    """3-state bool 을 텍스트로. ``None`` 은 ``--``."""
    if value is None:
        return "--"
    return true_text if value else false_text


def bool_color(value: bool | None, *, invert: bool = False) -> str:
    """bool 표시 색. ``invert=True`` 면 True 가 나쁜 의미(예: Timeout)."""
    if value is None:
        return T.idle
    good = (not value) if invert else value
    return T.ok if good else T.bad


def mask_to_bits(mask: int, width: int = DEVICE_COUNT) -> list[bool]:
    """비트 마스크를 device index 순 bool 리스트로 변환.

    >>> mask_to_bits(0x05)
    [True, False, True]
    """
    return [bool((mask >> i) & 1) for i in range(width)]


def mask_to_text(mask: int, width: int = DEVICE_COUNT) -> str:
    """마스크를 ``0b101 (0x05)`` 형태로 표시."""
    return f"0b{mask:0{width}b} (0x{mask:02X})"


def device_title(index: int) -> str:
    """Device 카드 제목. 명세 6장의 장치 의미를 함께 보여준다."""
    if 0 <= index < len(DEVICE_NAMES):
        return f"DEVICE {index} — {DEVICE_NAMES[index]}"
    return f"DEVICE {index}"


def fault_code_text(code: FaultCode) -> str:
    """``FAULT_CRITICAL (0x03)`` 형태."""
    if code is FaultCode.UNKNOWN:
        return "FAULT_? (알 수 없음)"
    return f"{code.name} (0x{int(code):02X})"


def fault_device_text(device: FaultDevice) -> str:
    if device is FaultDevice.UNKNOWN:
        return "DEVICE_? (알 수 없음)"
    return f"{device.name} ({int(device)})"


def fault_level_text(level: FaultLevel) -> str:
    if level is FaultLevel.UNKNOWN:
        return "LEVEL ? (알 수 없음)"
    return f"{level.label} — {level.name}"


def expected_output_enable(
    state: SystemState,
    fault_device: FaultDevice,
    degrade_mask: int = DEFAULT_DEGRADE_MASK,
) -> int | None:
    """명세상 기대되는 `output_enable` 값을 계산한다.

    **표시 및 검증 목적이다.** 실제 수신값을 덮어쓰는 데 쓰지 않는다
    (프롬프트 14장, 03_MEMBER_C 5장).

    Returns:
        기대 마스크. 계산 불가면 ``None``.
    """
    if state is SystemState.NORMAL or state is SystemState.WARNING:
        return 0b111
    if state is SystemState.SAFE_MODE:
        return 0b000
    if state is SystemState.DEGRADED:
        if fault_device is FaultDevice.DEVICE_0:
            return 0b110
        if fault_device is FaultDevice.DEVICE_1:
            return 0b101
        if fault_device is FaultDevice.DEVICE_2:
            return 0b011
        if fault_device is FaultDevice.MULTIPLE_OR_NONE:
            return 0b111 & ~(degrade_mask & 0b111)
    return None


def check_policy(
    status: MissionStatus, degrade_mask: int = DEFAULT_DEGRADE_MASK
) -> list[str]:
    """수신값이 명세 정책과 어긋나는지 점검한다.

    앱은 FPGA 출력을 고치지 않는다. 경고 문자열만 돌려준다.

    Returns:
        위반 설명 목록. 문제 없으면 빈 리스트.
    """
    warnings: list[str] = []
    state = status.system_state

    if state is SystemState.SAFE_MODE:
        if status.actuator_enable:
            warnings.append("SAFE_MODE 인데 actuator_enable 이 1 로 수신됨")
        if status.output_enable_mask != 0:
            warnings.append(
                f"SAFE_MODE 인데 output_enable 이 "
                f"{mask_to_text(status.output_enable_mask)} 로 수신됨"
            )
        if status.control_valid:
            warnings.append("SAFE_MODE 인데 control_valid 가 1 로 수신됨")

    if state in (SystemState.NORMAL, SystemState.WARNING):
        if status.output_enable_mask != 0b111:
            warnings.append(
                f"{state.value} 인데 output_enable 이 "
                f"{mask_to_text(status.output_enable_mask)} 로 수신됨 (기대 0b111)"
            )
        if not status.actuator_enable:
            warnings.append(f"{state.value} 인데 actuator_enable 이 0 으로 수신됨")

    # Level 1 에서 NORMAL 로 복귀하는 경로는 금지 (04 문서 서두)
    if state is SystemState.NORMAL and status.fault_level is FaultLevel.LEVEL_1_WARNING:
        warnings.append(
            "fault_level=1 인데 system_state 가 NORMAL 로 수신됨 "
            "(명세상 Level 1 은 WARNING 이어야 함)"
        )

    expected = expected_output_enable(state, status.fault_device, degrade_mask)
    if (
        state is SystemState.DEGRADED
        and expected is not None
        and status.output_enable_mask != expected
    ):
        warnings.append(
            f"DEGRADED / fault_device={int(status.fault_device)} 인데 "
            f"output_enable 이 {mask_to_text(status.output_enable_mask)} 로 수신됨 "
            f"(기대 {mask_to_text(expected)})"
        )

    # alive 와 timeout 은 서로 반대여야 정상이다 (01_MEMBER_A 3.3)
    for i in range(DEVICE_COUNT):
        if status.is_alive(i) and status.is_timeout(i):
            warnings.append(f"DEVICE {i} 가 alive 와 timeout 을 동시에 보고함")

    return warnings
