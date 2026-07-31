"""Command Builder 테스트."""

from __future__ import annotations

import pytest

from mission_dashboard.command_builder import CommandBuilder, CommandError
from mission_dashboard.models import ConfigValues


# ---------------------------------------------------------------- 공통 규칙
def test_all_commands_end_with_newline() -> None:
    """모든 명령은 반드시 \\n 으로 끝난다."""
    commands = [
        CommandBuilder.get_status(),
        CommandBuilder.get_config(),
        CommandBuilder.set_timeout(0, 100),
        CommandBuilder.set_critical_mask(0x04),
        CommandBuilder.set_persist_limit(5),
        CommandBuilder.set_recovery_count(2),
        CommandBuilder.set_degrade_mask(0x01),
        CommandBuilder.manual_reset(),
        CommandBuilder.clear_irq(),
        CommandBuilder.clear_heartbeat(),
        CommandBuilder.reset_fault(),
        CommandBuilder.inject_error(1, True),
        CommandBuilder.inject_clear_all(),
    ]
    for command in commands:
        assert command.endswith("\n"), command
        assert command.count("\n") == 1


# ---------------------------------------------------------------- 조회
def test_get_status() -> None:
    assert CommandBuilder.get_status() == "GET,STATUS\n"


def test_get_config() -> None:
    assert CommandBuilder.get_config() == "GET,CONFIG\n"


# ---------------------------------------------------------------- 설정
def test_set_timeout() -> None:
    assert CommandBuilder.set_timeout(0, 30_000_000) == "SET,TIMEOUT,0,30000000\n"
    assert CommandBuilder.set_timeout(2, 0) == "SET,TIMEOUT,2,0\n"


@pytest.mark.parametrize("device", [-1, 3, 99])
def test_set_timeout_device_range(device: int) -> None:
    with pytest.raises(CommandError):
        CommandBuilder.set_timeout(device, 100)


@pytest.mark.parametrize("value", [-1, 0x1_0000_0000])
def test_set_timeout_value_range(value: int) -> None:
    with pytest.raises(CommandError):
        CommandBuilder.set_timeout(0, value)


def test_set_critical_mask_hex_format() -> None:
    assert CommandBuilder.set_critical_mask(0x04) == "SET,CRITICAL_MASK,0x04\n"


@pytest.mark.parametrize("mask", [-1, 0x08, 0xFF])
def test_set_critical_mask_range(mask: int) -> None:
    with pytest.raises(CommandError):
        CommandBuilder.set_critical_mask(mask)


def test_set_degrade_mask_range() -> None:
    assert CommandBuilder.set_degrade_mask(0x01) == "SET,DEGRADE_MASK,0x01\n"
    with pytest.raises(CommandError):
        CommandBuilder.set_degrade_mask(0x10)


def test_set_persist_limit() -> None:
    assert CommandBuilder.set_persist_limit(5) == "SET,PERSIST_LIMIT,5\n"
    with pytest.raises(CommandError):
        CommandBuilder.set_persist_limit(256)


def test_set_recovery_count() -> None:
    assert CommandBuilder.set_recovery_count(2) == "SET,RECOVERY_COUNT,2\n"
    with pytest.raises(CommandError):
        CommandBuilder.set_recovery_count(70000)


def test_bool_is_not_accepted_as_int() -> None:
    """bool 은 int 서브클래스지만 설정 값으로 받지 않는다."""
    with pytest.raises(CommandError):
        CommandBuilder.set_persist_limit(True)  # type: ignore[arg-type]


def test_apply_config_order() -> None:
    """MicroBlaze 초기화 순서와 같은 순서로 나온다."""
    config = ConfigValues(
        timeout0=1,
        timeout1=2,
        timeout2=3,
        critical_mask=0x04,
        persist_limit=5,
        recovery_count=2,
        degrade_mask=0x01,
    )
    commands = CommandBuilder.apply_config(config)
    assert commands == [
        "SET,TIMEOUT,0,1\n",
        "SET,TIMEOUT,1,2\n",
        "SET,TIMEOUT,2,3\n",
        "SET,CRITICAL_MASK,0x04\n",
        "SET,PERSIST_LIMIT,5\n",
        "SET,RECOVERY_COUNT,2\n",
        "SET,DEGRADE_MASK,0x01\n",
    ]


# ---------------------------------------------------------------- 제어
def test_control_commands() -> None:
    assert CommandBuilder.manual_reset() == "CMD,MANUAL_RESET\n"
    assert CommandBuilder.clear_irq() == "CMD,CLEAR_IRQ\n"
    assert CommandBuilder.clear_heartbeat() == "CMD,CLEAR_HEARTBEAT\n"
    assert CommandBuilder.reset_fault() == "CMD,RESET_FAULT\n"


# ---------------------------------------------------------------- Injection
@pytest.mark.parametrize(
    ("kind", "device", "on", "expected"),
    [
        ("ERROR", 0, True, "INJECT,ERROR,0,ON\n"),
        ("ERROR", 1, False, "INJECT,ERROR,1,OFF\n"),
        ("CRITICAL", 2, True, "INJECT,CRITICAL,2,ON\n"),
        ("TIMEOUT", 0, False, "INJECT,TIMEOUT,0,OFF\n"),
    ],
)
def test_inject(kind: str, device: int, on: bool, expected: str) -> None:
    assert CommandBuilder.inject(kind, device, on) == expected


def test_inject_lowercase_kind_normalized() -> None:
    assert CommandBuilder.inject("error", 0, True) == "INJECT,ERROR,0,ON\n"


def test_inject_invalid_kind() -> None:
    with pytest.raises(CommandError):
        CommandBuilder.inject("FIRE", 0, True)


@pytest.mark.parametrize("device", [-1, 3, 100])
def test_inject_device_range(device: int) -> None:
    with pytest.raises(CommandError):
        CommandBuilder.inject_error(device, True)


def test_inject_clear_all() -> None:
    assert CommandBuilder.inject_clear_all() == "INJECT,CLEAR,ALL\n"


def test_multi_device_demo() -> None:
    """Device 0 + Device 1 동시 Fault. Critical 조건 없이 Multi 유발."""
    assert CommandBuilder.multi_device_demo() == [
        "INJECT,TIMEOUT,0,ON\n",
        "INJECT,ERROR,1,ON\n",
    ]


def test_critical_demo() -> None:
    assert CommandBuilder.critical_demo() == ["INJECT,CRITICAL,2,ON\n"]


# ------------------------------------------------------------------ 시연 프리셋
def test_multi_device_demo_is_staged() -> None:
    """Timeout D0 은 0.3초 뒤에야 성립하므로 동시 Fault 가 아니다."""
    assert CommandBuilder.multi_device_demo() == [
        "INJECT,TIMEOUT,0,ON\n",
        "INJECT,ERROR,1,ON\n",
    ]


def test_multi_error_demo_is_simultaneous() -> None:
    """Error 는 지연이 없어 두 장치가 같은 판정에서 함께 선다."""
    assert CommandBuilder.multi_error_demo() == [
        "INJECT,ERROR,0,ON\n",
        "INJECT,ERROR,1,ON\n",
    ]


def test_critical_demo() -> None:
    assert CommandBuilder.critical_demo() == ["INJECT,CRITICAL,2,ON\n"]


def test_critical_mask_error_demo() -> None:
    """CRITICAL_MASK 는 error_flag 에도 걸린다. critical_fault 핀이 아니다."""
    assert CommandBuilder.critical_mask_error_demo() == ["INJECT,ERROR,2,ON\n"]
