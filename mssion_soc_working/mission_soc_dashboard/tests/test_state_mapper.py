"""State Mapper 테스트."""

from __future__ import annotations

from datetime import datetime

import pytest

from mission_dashboard.models import (
    DeviceStatus,
    FaultCode,
    FaultDevice,
    FaultLevel,
    MissionStatus,
    SystemState,
)
from mission_dashboard.state_mapper import (
    bool_text,
    check_policy,
    device_title,
    expected_output_enable,
    fault_code_text,
    fault_device_text,
    fault_level_text,
    mask_to_bits,
    mask_to_text,
    state_color,
    state_icon,
    state_korean,
)


def make_status(**overrides) -> MissionStatus:
    """테스트용 MissionStatus 생성 헬퍼."""
    base = {
        "timestamp_ms": 100,
        "system_state": SystemState.NORMAL,
        "fault_level": FaultLevel.LEVEL_0_NORMAL,
        "fault_device": FaultDevice.MULTIPLE_OR_NONE,
        "fault_code": FaultCode.FAULT_NONE,
        "alive_mask": 0b111,
        "timeout_mask": 0b000,
        "output_enable_mask": 0b111,
        "actuator_enable": True,
        "raw_line": "$MISSION,...",
        "received_at": datetime(2026, 7, 29, 12, 0, 0),
    }
    base.update(overrides)
    return MissionStatus(**base)  # type: ignore[arg-type]


# ---------------------------------------------------------------- Bit Mask
@pytest.mark.parametrize(
    ("mask", "expected"),
    [
        (0b000, [False, False, False]),
        (0b001, [True, False, False]),
        (0b101, [True, False, True]),
        (0b111, [True, True, True]),
    ],
)
def test_mask_to_bits(mask: int, expected: list[bool]) -> None:
    assert mask_to_bits(mask) == expected


def test_mask_to_text() -> None:
    assert mask_to_text(0b101) == "0b101 (0x05)"
    assert mask_to_text(0b000) == "0b000 (0x00)"


# ---------------------------------------------------------------- 표시 문자열
def test_state_strings_unique() -> None:
    states = [
        SystemState.NORMAL,
        SystemState.WARNING,
        SystemState.DEGRADED,
        SystemState.SAFE_MODE,
        SystemState.UNKNOWN,
    ]
    colors = {state_color(s) for s in states}
    icons = {state_icon(s) for s in states}
    koreans = {state_korean(s) for s in states}
    assert len(colors) == len(states)
    assert len(icons) == len(states)
    assert len(koreans) == len(states)


def test_state_numeric_mapping() -> None:
    assert SystemState.NORMAL.numeric == 0
    assert SystemState.WARNING.numeric == 1
    assert SystemState.DEGRADED.numeric == 2
    assert SystemState.SAFE_MODE.numeric == 3
    assert SystemState.UNKNOWN.numeric == -1


def test_fault_text_helpers() -> None:
    assert fault_code_text(FaultCode.FAULT_CRITICAL) == "FAULT_CRITICAL (0x03)"
    assert fault_device_text(FaultDevice.DEVICE_2) == "DEVICE_2 (2)"
    assert "LEVEL 3" in fault_level_text(FaultLevel.LEVEL_3_SAFE)
    assert "알 수 없음" in fault_code_text(FaultCode.UNKNOWN)


def test_bool_text() -> None:
    assert bool_text(True) == "ON"
    assert bool_text(False) == "OFF"
    assert bool_text(None) == "--"
    assert bool_text(True, true_text="ALIVE", false_text="DOWN") == "ALIVE"


def test_device_title_includes_meaning() -> None:
    """00 공통명세 6장의 장치 의미를 함께 보여준다."""
    assert "DEVICE 0" in device_title(0)
    assert "센서" in device_title(0)
    assert "통신" in device_title(1)
    assert "모터" in device_title(2)


# --------------------------------------------------------- DeviceStatus 변환
def test_device_status_from_status() -> None:
    status = make_status(
        alive_mask=0b101,
        timeout_mask=0b010,
        output_enable_mask=0b110,
        fault_device=FaultDevice.DEVICE_1,
        fault_counts=(1, 2, 3),
    )

    d0 = DeviceStatus.from_status(status, 0)
    assert d0.alive is True
    assert d0.timeout is False
    assert d0.output_enabled is False
    assert d0.is_fault_target is False
    assert d0.fault_count == 1

    d1 = DeviceStatus.from_status(status, 1)
    assert d1.alive is False
    assert d1.timeout is True
    assert d1.output_enabled is True
    assert d1.is_fault_target is True
    assert d1.fault_count == 2


def test_fault_count_none_when_absent() -> None:
    status = make_status()
    assert DeviceStatus.from_status(status, 0).fault_count is None


# ------------------------------------------------------- expected_output_enable
@pytest.mark.parametrize(
    ("state", "device", "expected"),
    [
        (SystemState.NORMAL, FaultDevice.MULTIPLE_OR_NONE, 0b111),
        (SystemState.WARNING, FaultDevice.MULTIPLE_OR_NONE, 0b111),
        (SystemState.SAFE_MODE, FaultDevice.DEVICE_2, 0b000),
        (SystemState.DEGRADED, FaultDevice.DEVICE_0, 0b110),
        (SystemState.DEGRADED, FaultDevice.DEVICE_1, 0b101),
        (SystemState.DEGRADED, FaultDevice.DEVICE_2, 0b011),
    ],
)
def test_expected_output_enable(state, device, expected: int) -> None:
    assert expected_output_enable(state, device) == expected


def test_expected_output_enable_degrade_mask() -> None:
    """fault_device=3 인 DEGRADED 에서만 DEGRADE_MASK 를 적용한다."""
    assert (
        expected_output_enable(
            SystemState.DEGRADED, FaultDevice.MULTIPLE_OR_NONE, degrade_mask=0b001
        )
        == 0b110
    )
    assert (
        expected_output_enable(
            SystemState.DEGRADED, FaultDevice.MULTIPLE_OR_NONE, degrade_mask=0b011
        )
        == 0b100
    )


def test_expected_output_enable_unknown_state() -> None:
    assert expected_output_enable(SystemState.UNKNOWN, FaultDevice.DEVICE_0) is None


# ---------------------------------------------------------------- 정책 검증
def test_policy_ok_for_normal() -> None:
    assert check_policy(make_status()) == []


def test_policy_safe_mode_with_actuator_on() -> None:
    status = make_status(
        system_state=SystemState.SAFE_MODE,
        fault_level=FaultLevel.LEVEL_3_SAFE,
        actuator_enable=True,
        output_enable_mask=0b000,
    )
    warnings = check_policy(status)
    assert any("actuator_enable" in w for w in warnings)


def test_policy_safe_mode_with_output_enabled() -> None:
    status = make_status(
        system_state=SystemState.SAFE_MODE,
        actuator_enable=False,
        output_enable_mask=0b111,
    )
    warnings = check_policy(status)
    assert any("output_enable" in w for w in warnings)


def test_policy_level1_must_not_be_normal() -> None:
    """Level 1 에서 NORMAL 복귀는 통합 실패 조건이다 (04 문서 서두)."""
    status = make_status(
        system_state=SystemState.NORMAL,
        fault_level=FaultLevel.LEVEL_1_WARNING,
    )
    warnings = check_policy(status)
    assert any("Level 1" in w or "fault_level=1" in w for w in warnings)


def test_policy_degraded_output_mismatch() -> None:
    status = make_status(
        system_state=SystemState.DEGRADED,
        fault_level=FaultLevel.LEVEL_2_DEGRADED,
        fault_device=FaultDevice.DEVICE_0,
        output_enable_mask=0b111,  # 기대는 0b110
    )
    warnings = check_policy(status)
    assert any("DEGRADED" in w for w in warnings)


def test_policy_alive_and_timeout_conflict() -> None:
    status = make_status(alive_mask=0b001, timeout_mask=0b001)
    warnings = check_policy(status)
    assert any("동시에" in w for w in warnings)
