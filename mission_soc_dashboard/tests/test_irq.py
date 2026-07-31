"""`$IRQ` / `GET,IRQ` / `SET,IRQ_EN` 검증.

이 경로가 있는 이유:
    `CMD,CLEAR_IRQ` 는 세 IP 의 IRQ_STATUS 를 W1C 한다. 그런데 평상시엔 ISR 이
    인터럽트 진입 즉시 W1C 해 버려서, 사람이 버튼을 누를 때는 Pending 이 항상
    0 이다. `$ACK` 만으로는 W1C 가 실제로 동작하는지 알 수 없었다.

    IRQ_STATUS 의 Set 은 IRQ_EN 과 무관하다
    (rtl/fault_manager_axi.v: `assign irq = reg_irq_status & reg_irq_en;`).
    그래서 IRQ_EN 을 끄면 ISR 이 돌지 않아 Pending 이 그대로 남고, 그 상태에서
    Clear IRQ 가 0 으로 떨어뜨리는 걸 확인할 수 있다. 05 시나리오 15번이다.
"""

from __future__ import annotations

import pytest

from mission_dashboard.command_builder import CommandBuilder, CommandError
from mission_dashboard.constants import (
    IRQ_EN_ALL,
    IRQ_EN_BIT_FM,
    IRQ_EN_BIT_HB,
    IRQ_EN_BIT_SC,
)
from mission_dashboard.mock_device import MockDevice
from mission_dashboard.protocol import parse_line


@pytest.fixture
def dev() -> MockDevice:
    return MockDevice()


# ------------------------------------------------------------- CommandBuilder
def test_get_irq_command() -> None:
    assert CommandBuilder.get_irq() == "GET,IRQ\n"


@pytest.mark.parametrize("mask", [0, 1, 3, 7])
def test_set_irq_en_command(mask: int) -> None:
    assert CommandBuilder.set_irq_en(mask) == f"SET,IRQ_EN,0x{mask:02X}\n"


@pytest.mark.parametrize("mask", [-1, 8, 255])
def test_set_irq_en_rejects_out_of_range(mask: int) -> None:
    with pytest.raises(CommandError):
        CommandBuilder.set_irq_en(mask)


# ------------------------------------------------------------------- Parser
def test_parse_irq_line() -> None:
    result = parse_line("$IRQ,0x07,0x02,0x01,0x00")
    assert result.success
    assert result.message_type == "IRQ"

    irq = result.irq
    assert irq is not None
    assert irq.en_mask == 0x07
    assert (irq.hb_status, irq.fm_status, irq.sc_status) == (0x02, 0x01, 0x00)
    assert irq.enabled(IRQ_EN_BIT_HB)
    assert irq.enabled(IRQ_EN_BIT_FM)
    assert irq.enabled(IRQ_EN_BIT_SC)
    assert irq.any_pending


def test_parse_irq_accepts_decimal() -> None:
    """펌웨어가 표기를 바꿔도 깨지지 않아야 한다."""
    irq = parse_line("$IRQ,7,2,1,0").irq
    assert irq is not None
    assert (irq.en_mask, irq.hb_status) == (7, 2)


def test_parse_irq_no_pending() -> None:
    irq = parse_line("$IRQ,0x07,0x00,0x00,0x00").irq
    assert irq is not None
    assert not irq.any_pending


def test_parse_irq_disabled_mask() -> None:
    irq = parse_line("$IRQ,0x00,0x00,0x00,0x00").irq
    assert irq is not None
    assert not irq.enabled(IRQ_EN_BIT_HB)
    assert not irq.enabled(IRQ_EN_BIT_FM)
    assert not irq.enabled(IRQ_EN_BIT_SC)


@pytest.mark.parametrize(
    "line",
    ["$IRQ", "$IRQ,0x07", "$IRQ,0x07,0x00,0x00"],
)
def test_parse_irq_field_shortage(line: str) -> None:
    result = parse_line(line)
    assert not result.success
    assert result.message_type == "IRQ"


@pytest.mark.parametrize("line", ["$IRQ,x,0,0,0", "$IRQ,0x07,-1,0,0"])
def test_parse_irq_invalid_value(line: str) -> None:
    assert not parse_line(line).success


def test_irq_status_of_keys() -> None:
    irq = parse_line("$IRQ,0x07,0x05,0x01,0x00").irq
    assert irq is not None
    assert irq.status_of("hb") == 0x05
    assert irq.status_of("fm") == 0x01
    assert irq.status_of("sc") == 0x00


# --------------------------------------------------------------- MockDevice
def test_mock_get_irq_default(dev: MockDevice) -> None:
    replies = dev.handle_command("GET,IRQ")
    assert replies[0] == "$ACK,GET,IRQ"
    assert replies[1] == "$IRQ,0x07,0x00,0x00,0x00"


def test_mock_isr_clears_pending_when_enabled(dev: MockDevice) -> None:
    """IRQ_EN 이 켜져 있으면 ISR 이 즉시 W1C 해서 Pending 이 안 보인다.

    이게 바로 15번이 지금까지 아무것도 증명하지 못한 이유다.
    """
    dev.error_inject = 0b010
    for _ in range(8):
        dev.tick(200)

    irq = parse_line(dev.handle_command("GET,IRQ")[1]).irq
    assert irq is not None
    assert not irq.any_pending


def test_mock_pending_latches_when_irq_en_off(dev: MockDevice) -> None:
    """IRQ_EN=0 이면 ISR 이 안 돌아 Pending 이 그대로 쌓인다."""
    assert dev.handle_command("SET,IRQ_EN,0x00") == ["$ACK,SET,IRQ_EN,0"]

    dev.error_inject = 0b010
    for _ in range(8):
        dev.tick(200)

    irq = parse_line(dev.handle_command("GET,IRQ")[1]).irq
    assert irq is not None
    assert irq.en_mask == 0
    assert irq.fm_status == 1      # fault level/device/code 가 바뀌었다
    assert irq.sc_status == 1      # system_state 가 바뀌었다
    assert irq.any_pending


def test_mock_clear_irq_actually_clears(dev: MockDevice) -> None:
    """15번의 핵심. Pending 이 살아 있을 때 CLEAR_IRQ 가 0 으로 떨어뜨린다."""
    dev.handle_command("SET,IRQ_EN,0x00")
    dev.error_inject = 0b010
    for _ in range(8):
        dev.tick(200)
    assert parse_line(dev.handle_command("GET,IRQ")[1]).irq.any_pending

    assert dev.handle_command("CMD,CLEAR_IRQ") == ["$ACK,CMD,CLEAR_IRQ"]

    irq = parse_line(dev.handle_command("GET,IRQ")[1]).irq
    assert irq is not None
    assert not irq.any_pending


def test_mock_clear_irq_keeps_fault_state(dev: MockDevice) -> None:
    """CLEAR_IRQ 는 Pending 만 만진다. 고장 상태는 그대로여야 한다."""
    dev.handle_command("SET,IRQ_EN,0x00")
    dev.error_inject = 0b010
    for _ in range(8):
        dev.tick(200)

    before = (dev.fault_level, dev.fault_device, dev.fault_code, dev.system_state)
    dev.handle_command("CMD,CLEAR_IRQ")
    after = (dev.fault_level, dev.fault_device, dev.fault_code, dev.system_state)
    assert before == after


def test_mock_timeout_sets_hb_pending(dev: MockDevice) -> None:
    dev.handle_command("SET,IRQ_EN,0x00")
    dev.handle_command("INJECT,TIMEOUT,1,ON")
    dev.tick(200)

    irq = parse_line(dev.handle_command("GET,IRQ")[1]).irq
    assert irq is not None
    assert irq.hb_status & 0b010


def test_mock_reenabling_irq_drains_pending(dev: MockDevice) -> None:
    """다시 켜면 밀린 Pending 을 ISR 이 소화한다 (원복 절차)."""
    dev.handle_command("SET,IRQ_EN,0x00")
    dev.error_inject = 0b010
    for _ in range(8):
        dev.tick(200)

    dev.handle_command(f"SET,IRQ_EN,0x{IRQ_EN_ALL:02X}")
    irq = parse_line(dev.handle_command("GET,IRQ")[1]).irq
    assert irq is not None
    assert irq.en_mask == IRQ_EN_ALL
    assert not irq.any_pending


def test_mock_partial_irq_en(dev: MockDevice) -> None:
    """일부만 끄면 끈 IP 의 Pending 만 남는다."""
    dev.handle_command(f"SET,IRQ_EN,0x{IRQ_EN_BIT_HB:02X}")   # A 만 켬
    dev.error_inject = 0b010
    for _ in range(8):
        dev.tick(200)

    irq = parse_line(dev.handle_command("GET,IRQ")[1]).irq
    assert irq is not None
    assert irq.hb_status == 0      # A 는 ISR 이 돈다
    assert irq.fm_status == 1      # B 는 안 돈다
    assert irq.sc_status == 1      # C 도 안 돈다


def test_mock_set_irq_en_rejects_out_of_range(dev: MockDevice) -> None:
    assert dev.handle_command("SET,IRQ_EN,0x08") == ["$ERR,INVALID_VALUE,IRQ_EN"]
    assert dev.irq_en_mask == IRQ_EN_ALL


def test_mock_get_config_reports_irq_en(dev: MockDevice) -> None:
    dev.handle_command("SET,IRQ_EN,0x05")
    replies = dev.handle_command("GET,CONFIG")
    assert "$ACK,SET,IRQ_EN,0x05" in replies


def test_mock_full_scenario_15() -> None:
    """05 시나리오 15번 전체를 그대로 밟는다."""
    dev = MockDevice()

    # 15-1 평상시
    assert not parse_line(dev.handle_command("GET,IRQ")[1]).irq.any_pending

    # 15-2 IRQ_EN 전부 해제
    dev.handle_command("SET,IRQ_EN,0x00")

    # 15-3 고장 주입
    dev.handle_command("INJECT,ERROR,1,ON")
    for _ in range(8):
        dev.tick(200)

    # 15-4 래치 확인
    latched = parse_line(dev.handle_command("GET,IRQ")[1]).irq
    assert latched.fm_status and latched.sc_status

    # 15-5, 15-6 Clear 후 확인
    dev.handle_command("CMD,CLEAR_IRQ")
    assert not parse_line(dev.handle_command("GET,IRQ")[1]).irq.any_pending

    # 15-7 원복
    dev.handle_command("INJECT,ERROR,1,OFF")
    dev.handle_command(f"SET,IRQ_EN,0x{IRQ_EN_ALL:02X}")
    restored = parse_line(dev.handle_command("GET,IRQ")[1]).irq
    assert restored.en_mask == IRQ_EN_ALL
    assert not restored.any_pending
    assert IRQ_EN_BIT_FM | IRQ_EN_BIT_SC | IRQ_EN_BIT_HB == IRQ_EN_ALL
