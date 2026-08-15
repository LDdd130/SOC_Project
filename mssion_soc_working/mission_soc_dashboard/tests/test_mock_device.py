"""Mock Simulator 테스트.

명세의 Fault 정책과 Safety FSM 을 재현하는지 확인한다.
실제 Serial 포트나 FPGA 는 쓰지 않는다.
"""

from __future__ import annotations

import pytest

from mission_dashboard.mock_device import MockConfig, MockDevice
from mission_dashboard.models import FaultCode, FaultDevice, FaultLevel, SystemState
from mission_dashboard.protocol import parse_line


def run_ticks(device: MockDevice, count: int) -> None:
    for _ in range(count):
        device.tick(200)


@pytest.fixture()
def dev() -> MockDevice:
    """PERSIST_LIMIT=3, RECOVERY_COUNT=2 로 짧게 잡아 테스트를 빠르게 한다."""
    return MockDevice(
        MockConfig(critical_mask=0b100, persist_limit=3, recovery_count=2)
    )


# ---------------------------------------------------------------- 정상
def test_initial_state_normal(dev: MockDevice) -> None:
    dev.tick()
    assert dev.fault_level is FaultLevel.LEVEL_0_NORMAL
    assert dev.system_state is SystemState.NORMAL
    assert dev.output_enable == 0b111
    assert dev.actuator_enable is True
    assert dev.control_valid is True


def test_mission_line_is_parseable(dev: MockDevice) -> None:
    """생성한 줄이 실제 Parser 로 다시 읽혀야 한다."""
    dev.tick()
    result = parse_line(dev.build_mission_line())
    assert result.success
    assert result.status is not None
    assert result.status.system_state is SystemState.NORMAL


def test_boot_messages_emitted_once(dev: MockDevice) -> None:
    first = dev.tick()
    second = dev.tick()
    assert any("Boot complete" in line for line in first)
    assert not any("Boot complete" in line for line in second)


# ---------------------------------------------------------------- 단일 Fault
def test_single_temporary_fault_level1(dev: MockDevice) -> None:
    """지속 횟수 미만이면 Level 1 / WARNING."""
    dev.handle_command("INJECT,TIMEOUT,0,ON")
    dev.tick()
    assert dev.fault_level is FaultLevel.LEVEL_1_WARNING
    assert dev.fault_device is FaultDevice.DEVICE_0
    assert dev.fault_code is FaultCode.FAULT_TIMEOUT
    assert dev.system_state is SystemState.WARNING


def test_persistent_fault_level2(dev: MockDevice) -> None:
    """PERSIST_LIMIT 도달 시 Level 2 / DEGRADED."""
    dev.handle_command("INJECT,TIMEOUT,0,ON")
    run_ticks(dev, 5)
    assert dev.fault_level is FaultLevel.LEVEL_2_DEGRADED
    assert dev.system_state is SystemState.DEGRADED
    # DEGRADED + fault_device=0 -> Device 0 만 Disable
    assert dev.output_enable == 0b110


def test_same_device_timeout_and_error_prefers_error_code(dev: MockDevice) -> None:
    """같은 장치에 Timeout 과 Error 가 겹치면 FAULT_ERROR_CODE 우선."""
    dev.handle_command("INJECT,TIMEOUT,1,ON")
    dev.handle_command("INJECT,ERROR,1,ON")
    dev.tick()
    assert dev.fault_device is FaultDevice.DEVICE_1
    assert dev.fault_code is FaultCode.FAULT_ERROR_CODE


# ---------------------------------------------------------------- Critical
def test_critical_device_immediate_level3(dev: MockDevice) -> None:
    """CRITICAL_MASK 장치는 지속 횟수를 기다리지 않는다."""
    dev.handle_command("INJECT,CRITICAL,2,ON")
    dev.tick()
    assert dev.fault_level is FaultLevel.LEVEL_3_SAFE
    assert dev.fault_code is FaultCode.FAULT_CRITICAL
    assert dev.fault_device is FaultDevice.DEVICE_2
    assert dev.system_state is SystemState.SAFE_MODE
    assert dev.output_enable == 0b000
    assert dev.actuator_enable is False
    assert dev.control_valid is False


def test_critical_mask_applies_to_timeout_too(dev: MockDevice) -> None:
    """critical_mask 는 Timeout/Error/Critical 모두에 적용된다."""
    dev.handle_command("INJECT,TIMEOUT,2,ON")
    dev.tick()
    assert dev.fault_level is FaultLevel.LEVEL_3_SAFE
    assert dev.fault_code is FaultCode.FAULT_CRITICAL


# ---------------------------------------------------------------- Multi
def test_multi_device_fault(dev: MockDevice) -> None:
    """Critical 없이 두 장치 이상이면 Level 3 / MULTI_DEVICE / Device 3."""
    dev.handle_command("INJECT,TIMEOUT,0,ON")
    dev.handle_command("INJECT,ERROR,1,ON")
    dev.tick()
    assert dev.fault_level is FaultLevel.LEVEL_3_SAFE
    assert dev.fault_code is FaultCode.FAULT_MULTI_DEVICE
    assert dev.fault_device is FaultDevice.MULTIPLE_OR_NONE


def test_critical_beats_multi_device(dev: MockDevice) -> None:
    """Critical 이 Multi-device 보다 우선한다."""
    dev.handle_command("INJECT,TIMEOUT,0,ON")
    dev.handle_command("INJECT,CRITICAL,2,ON")
    dev.tick()
    assert dev.fault_code is FaultCode.FAULT_CRITICAL
    assert dev.fault_device is FaultDevice.DEVICE_2


# ---------------------------------------------------------------- SAFE_MODE
def test_safe_mode_latches_after_fault_cleared(dev: MockDevice) -> None:
    """Fault 를 제거해도 SAFE_MODE 는 자동 복구되지 않는다."""
    dev.handle_command("INJECT,CRITICAL,2,ON")
    dev.tick()
    assert dev.system_state is SystemState.SAFE_MODE

    dev.handle_command("INJECT,CLEAR,ALL")
    run_ticks(dev, 20)
    assert dev.fault_level is FaultLevel.LEVEL_0_NORMAL
    assert dev.system_state is SystemState.SAFE_MODE  # Latch 유지
    assert dev.output_enable == 0b000


def test_manual_reset_rejected_while_fault_active(dev: MockDevice) -> None:
    dev.handle_command("INJECT,CRITICAL,2,ON")
    dev.tick()
    replies = dev.handle_command("CMD,MANUAL_RESET")
    assert any("$ERR" in r and "FAULT_ACTIVE" in r for r in replies)
    assert dev.system_state is SystemState.SAFE_MODE


def test_manual_reset_succeeds_at_level0(dev: MockDevice) -> None:
    dev.handle_command("INJECT,CRITICAL,2,ON")
    dev.tick()
    dev.handle_command("INJECT,CLEAR,ALL")
    run_ticks(dev, 3)

    replies = dev.handle_command("CMD,MANUAL_RESET")
    assert any("$ACK,CMD,MANUAL_RESET" in r for r in replies)
    assert dev.system_state is SystemState.NORMAL
    assert dev.output_enable == 0b111
    assert dev.actuator_enable is True


# ---------------------------------------------------------------- Recovery
def test_degraded_level1_recovers_to_warning_not_normal(dev: MockDevice) -> None:
    """DEGRADED 에서 Level 1 이 유지되면 WARNING 까지만 복귀한다.

    Level 1 상태에서 NORMAL 로 복귀하면 통합 실패다 (04 문서 서두).

    Fault 는 그대로 둔 채 PERSIST_LIMIT 을 크게 올려 Level 2 -> Level 1 로
    낮춘다. 이렇게 하면 Level 1 이 계속 유지되므로 복귀 목표가 WARNING 하나로
    고정된다.
    """
    dev.handle_command("INJECT,TIMEOUT,0,ON")
    run_ticks(dev, 5)
    assert dev.system_state is SystemState.DEGRADED
    assert dev.fault_level is FaultLevel.LEVEL_2_DEGRADED

    # Fault 는 유지한 채 지속 기준만 크게 올린다 -> Level 1 로 완화
    dev.handle_command("SET,PERSIST_LIMIT,200")
    dev.tick()
    assert dev.fault_level is FaultLevel.LEVEL_1_WARNING
    assert dev.system_state is SystemState.DEGRADED  # 아직 복귀 전

    # RECOVERY_COUNT(2) 만큼 Level 1 이 유지되면 WARNING 으로만 복귀한다
    run_ticks(dev, 3)
    assert dev.fault_level is FaultLevel.LEVEL_1_WARNING
    assert dev.system_state is SystemState.WARNING
    assert dev.system_state is not SystemState.NORMAL


def test_degraded_level1_never_jumps_to_normal(dev: MockDevice) -> None:
    """Level 1 이 아무리 오래 유지돼도 NORMAL 로 가지 않는다.

    PERSIST_LIMIT 은 bit[7:0] 이므로 최대 255 다 (02_MEMBER_B 6장).
    """
    dev.handle_command("INJECT,TIMEOUT,0,ON")
    run_ticks(dev, 5)
    assert dev.handle_command("SET,PERSIST_LIMIT,250") == [
        "$ACK,SET,PERSIST_LIMIT,250"
    ]

    for _ in range(30):
        dev.tick()
        assert dev.system_state is not SystemState.NORMAL
    assert dev.system_state is SystemState.WARNING


def test_degraded_level0_recovers_to_normal(dev: MockDevice) -> None:
    dev.handle_command("INJECT,TIMEOUT,0,ON")
    run_ticks(dev, 5)
    assert dev.system_state is SystemState.DEGRADED

    dev.handle_command("INJECT,CLEAR,ALL")
    run_ticks(dev, 5)
    assert dev.system_state is SystemState.NORMAL


def test_recovery_needs_enough_ticks() -> None:
    """RECOVERY_COUNT 미만에서는 복귀하지 않는다."""
    device = MockDevice(
        MockConfig(critical_mask=0b100, persist_limit=3, recovery_count=5)
    )
    device.handle_command("INJECT,TIMEOUT,0,ON")
    run_ticks(device, 5)
    assert device.system_state is SystemState.DEGRADED

    device.handle_command("INJECT,CLEAR,ALL")
    device.tick()
    device.tick()
    assert device.system_state is SystemState.DEGRADED  # 아직 부족


def test_recovery_count_zero_treated_as_one() -> None:
    """RECOVERY_COUNT=0 은 유효값 1 로 간주한다."""
    device = MockDevice(
        MockConfig(critical_mask=0b100, persist_limit=3, recovery_count=0)
    )
    device.handle_command("INJECT,TIMEOUT,0,ON")
    run_ticks(device, 5)
    device.handle_command("INJECT,CLEAR,ALL")
    device.tick()
    assert device.system_state is SystemState.NORMAL


# ---------------------------------------------------------------- 명령
def test_get_status_returns_ack_and_mission(dev: MockDevice) -> None:
    replies = dev.handle_command("GET,STATUS")
    assert replies[0] == "$ACK,GET,STATUS"
    assert replies[1].startswith("$MISSION,")


def test_set_commands_ack(dev: MockDevice) -> None:
    assert dev.handle_command("SET,PERSIST_LIMIT,7") == ["$ACK,SET,PERSIST_LIMIT,7"]
    assert dev.config.persist_limit == 7

    assert dev.handle_command("SET,CRITICAL_MASK,0x04") == [
        "$ACK,SET,CRITICAL_MASK,4"
    ]
    assert dev.config.critical_mask == 0x04


def test_set_invalid_value_returns_err(dev: MockDevice) -> None:
    replies = dev.handle_command("SET,CRITICAL_MASK,0xFF")
    assert replies == ["$ERR,INVALID_VALUE,CRITICAL_MASK"]


def test_unknown_command_returns_err(dev: MockDevice) -> None:
    assert dev.handle_command("FLY,TO,MOON") == ["$ERR,UNKNOWN_COMMAND"]
    assert dev.handle_command("") == ["$ERR,UNKNOWN_COMMAND,empty"]


def test_reset_fault_rejected_while_fault_active(dev: MockDevice) -> None:
    dev.handle_command("INJECT,TIMEOUT,0,ON")
    dev.tick()
    replies = dev.handle_command("CMD,RESET_FAULT")
    assert any("FAULT_ACTIVE" in r for r in replies)


def test_reset_fault_clears_counts_when_no_fault(dev: MockDevice) -> None:
    dev.handle_command("INJECT,TIMEOUT,0,ON")
    run_ticks(dev, 4)
    dev.handle_command("INJECT,CLEAR,ALL")
    dev.tick()
    replies = dev.handle_command("CMD,RESET_FAULT")
    assert replies == ["$ACK,CMD,RESET_FAULT"]
    assert dev.fault_counts == [0, 0, 0]


def test_inject_invalid_device_returns_err(dev: MockDevice) -> None:
    assert dev.handle_command("INJECT,ERROR,9,ON") == ["$ERR,INVALID_VALUE,DEVICE"]


# ---------------------------------------------------------------- Event
def test_state_change_event_emitted(dev: MockDevice) -> None:
    dev.tick()
    dev.handle_command("INJECT,CRITICAL,2,ON")
    lines = dev.tick()
    assert any("STATE_CHANGE,SAFE_MODE" in line for line in lines)


def test_heartbeat_timeout_event_emitted(dev: MockDevice) -> None:
    dev.tick()
    dev.handle_command("INJECT,TIMEOUT,0,ON")
    lines = dev.tick()
    assert any("HEARTBEAT_TIMEOUT,0" in line for line in lines)


def test_alive_mask_reflects_timeout(dev: MockDevice) -> None:
    dev.handle_command("INJECT,TIMEOUT,1,ON")
    dev.tick()
    assert dev.timeout_mask == 0b010
    assert dev.alive_mask == 0b101
