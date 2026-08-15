"""Protocol Parser 테스트.

실제 Serial 포트나 FPGA 없이 동작한다.
"""

from __future__ import annotations

import pytest

from mission_dashboard.models import (
    FaultCode,
    FaultDevice,
    FaultLevel,
    SystemState,
)
from mission_dashboard.protocol import ProtocolParser, parse_int, parse_line


# ---------------------------------------------------------------- parse_int
@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("0", 0),
        ("42", 42),
        (" 7 ", 7),
        ("0x03", 3),
        ("0X1F", 31),
        ("0b101", 5),
        ("-5", -5),
    ],
)
def test_parse_int_valid(text: str, expected: int) -> None:
    assert parse_int(text) == expected


@pytest.mark.parametrize("text", ["", "   ", "abc", "0xZZ", "1.5", None, "-"])
def test_parse_int_invalid(text) -> None:
    assert parse_int(text) is None


# ------------------------------------------------------------- $MISSION 정상
def test_mission_basic() -> None:
    line = "$MISSION,1250,SAFE_MODE,3,2,3,0x03,0x04,0x00,0"
    result = parse_line(line)

    assert result.success
    assert result.message_type == "MISSION"
    status = result.status
    assert status is not None
    assert status.timestamp_ms == 1250
    assert status.system_state is SystemState.SAFE_MODE
    assert status.fault_level is FaultLevel.LEVEL_3_SAFE
    assert status.fault_device is FaultDevice.DEVICE_2
    assert status.fault_code is FaultCode.FAULT_CRITICAL
    assert status.alive_mask == 0x03
    assert status.timeout_mask == 0x04
    assert status.output_enable_mask == 0x00
    assert status.actuator_enable is False


def test_mission_hex_and_decimal_mixed() -> None:
    """16진수와 10진수를 섞어 보내도 파싱된다."""
    result = parse_line("$MISSION,10,NORMAL,0,3,0,7,0,7,1")
    assert result.success
    status = result.status
    assert status is not None
    assert status.alive_mask == 0b111
    assert status.output_enable_mask == 0b111
    assert status.actuator_enable is True


def test_mission_optional_fields() -> None:
    """control_valid, state_timer, fault_count 확장 필드."""
    line = "$MISSION,1250,SAFE_MODE,3,2,3,0x03,0x04,0x00,0,0,3245,0,0,1"
    result = parse_line(line)

    assert result.success
    status = result.status
    assert status is not None
    assert status.control_valid is False
    assert status.state_timer == 3245
    assert status.fault_counts == (0, 0, 1)


def test_mission_without_optional_fields_gives_none() -> None:
    result = parse_line("$MISSION,10,NORMAL,0,3,0,0x07,0x00,0x07,1")
    status = result.status
    assert status is not None
    assert status.control_valid is None
    assert status.state_timer is None
    assert status.fault_counts is None


def test_mission_device_helpers() -> None:
    """alive=0x05 -> Device 0 Alive, Device 1 Not, Device 2 Alive."""
    result = parse_line("$MISSION,1,NORMAL,0,3,0,0x05,0x02,0x05,1")
    status = result.status
    assert status is not None

    assert status.is_alive(0) is True
    assert status.is_alive(1) is False
    assert status.is_alive(2) is True

    assert status.is_timeout(0) is False
    assert status.is_timeout(1) is True

    assert status.is_output_enabled(0) is True
    assert status.is_output_enabled(1) is False

    # 범위를 벗어난 index 도 예외 없이 False
    assert status.is_alive(9) is False
    assert status.is_alive(-1) is False


def test_mission_with_whitespace_and_crlf() -> None:
    line = "  $MISSION , 100 , WARNING , 1 , 0 , 0x01 , 0x07 , 0x00 , 0x07 , 1 \r\n"
    result = parse_line(line)
    assert result.success
    assert result.status is not None
    assert result.status.system_state is SystemState.WARNING


# ------------------------------------------------------------- $MISSION 오류
def test_mission_missing_fields() -> None:
    result = parse_line("$MISSION,1250,SAFE_MODE,3")
    assert not result.success
    assert result.error is not None
    assert "필드 부족" in result.error


def test_mission_invalid_number() -> None:
    result = parse_line("$MISSION,1250,SAFE_MODE,X,2,3,0x03,0x04,0x00,0")
    assert not result.success
    assert "fault_level" in (result.error or "")


def test_mission_invalid_hex() -> None:
    result = parse_line("$MISSION,1250,SAFE_MODE,3,2,3,0xZZ,0x04,0x00,0")
    assert not result.success
    assert "alive" in (result.error or "")


def test_mission_negative_timestamp_rejected() -> None:
    result = parse_line("$MISSION,-1,NORMAL,0,3,0,0x07,0,0x07,1")
    assert not result.success


def test_mission_unknown_state_becomes_unknown_enum() -> None:
    """알 수 없는 State 는 Parse Error 가 아니라 UNKNOWN Enum 이다."""
    result = parse_line("$MISSION,10,BOOTING,0,3,0,0x07,0x00,0x07,1")
    assert result.success
    assert result.status is not None
    assert result.status.system_state is SystemState.UNKNOWN


def test_mission_unknown_fault_code_becomes_unknown_enum() -> None:
    result = parse_line("$MISSION,10,NORMAL,0,3,0x7F,0x07,0x00,0x07,1")
    assert result.success
    assert result.status is not None
    assert result.status.fault_code is FaultCode.UNKNOWN


def test_mission_unknown_level_becomes_unknown_enum() -> None:
    result = parse_line("$MISSION,10,NORMAL,9,3,0,0x07,0x00,0x07,1")
    assert result.success
    assert result.status is not None
    assert result.status.fault_level is FaultLevel.UNKNOWN


# ---------------------------------------------------------------- $EVENT
def test_event_basic() -> None:
    result = parse_line("$EVENT,1300,FAULT_CHANGE,2,0,1")
    assert result.success
    event = result.event
    assert event is not None
    assert event.timestamp_ms == 1300
    assert event.event_type == "FAULT_CHANGE"
    assert event.args == ("2", "0", "1")


def test_event_with_single_arg() -> None:
    result = parse_line("$EVENT,1301,STATE_CHANGE,DEGRADED")
    assert result.success
    assert result.event is not None
    assert result.event.args == ("DEGRADED",)


def test_event_without_args_is_ok() -> None:
    """인자 수가 예상과 달라도 실패하지 않는다."""
    result = parse_line("$EVENT,1700,SOMETHING_NEW")
    assert result.success
    assert result.event is not None
    assert result.event.args == ()


def test_event_missing_timestamp() -> None:
    result = parse_line("$EVENT")
    assert not result.success


# ------------------------------------------------------------- $ACK / $ERR
def test_ack_parsing() -> None:
    result = parse_line("$ACK,SET,PERSIST_LIMIT,5")
    assert result.success
    response = result.response
    assert response is not None
    assert response.is_ack is True
    assert response.command == "SET"
    assert response.args == ("PERSIST_LIMIT", "5")


def test_err_parsing() -> None:
    result = parse_line("$ERR,MANUAL_RESET,FAULT_ACTIVE")
    assert result.success
    response = result.response
    assert response is not None
    assert response.is_ack is False
    assert response.command == "MANUAL_RESET"
    assert response.is_unknown_command is False


def test_err_unknown_command_detected() -> None:
    result = parse_line("$ERR,UNKNOWN_COMMAND")
    assert result.success
    assert result.response is not None
    assert result.response.is_unknown_command is True


def test_ack_without_command_fails() -> None:
    result = parse_line("$ACK")
    assert not result.success


# ---------------------------------------------------------------- RAW / 빈줄
@pytest.mark.parametrize(
    "text",
    ["Boot complete", "Interrupt controller initialized", "Unknown message"],
)
def test_raw_debug_text(text: str) -> None:
    result = parse_line(text)
    assert result.success
    assert result.is_raw_text
    assert result.raw_line == text


def test_unknown_dollar_prefix_is_raw() -> None:
    result = parse_line("$FOOBAR,1,2,3")
    assert result.success
    assert result.message_type == "RAW"


@pytest.mark.parametrize("text", ["", "   ", "\r\n", "\n"])
def test_empty_line(text: str) -> None:
    result = parse_line(text)
    assert not result.success
    assert result.message_type == "EMPTY"


def test_replacement_char_does_not_crash() -> None:
    """UTF-8 디코드 대체 문자가 섞여도 죽지 않는다."""
    result = parse_line("$MISSION,10,NORM�AL,0,3,0,0x07,0x00,0x07,1")
    assert result.success
    assert result.status is not None
    assert result.status.system_state is SystemState.UNKNOWN


def test_truncated_line() -> None:
    result = parse_line("$MISSION,125")
    assert not result.success


# -------------------------------------------------------- ProtocolParser 버퍼
def test_stream_parser_assembles_lines() -> None:
    parser = ProtocolParser(max_line_bytes=4096)
    assert parser.feed(b"$MISSION,1,NOR") == []
    lines = parser.feed(b"MAL,0,3,0,7,0,7,1\n$ACK,GET,STATUS\n")
    assert lines == ["$MISSION,1,NORMAL,0,3,0,7,0,7,1", "$ACK,GET,STATUS"]


def test_stream_parser_handles_crlf() -> None:
    parser = ProtocolParser(max_line_bytes=4096)
    lines = parser.feed(b"Boot complete\r\nReady\r\n")
    assert lines == ["Boot complete", "Ready"]


def test_stream_parser_drops_oversized_line() -> None:
    parser = ProtocolParser(max_line_bytes=64)
    parser.feed(b"A" * 200)
    assert parser.dropped_lines == 1
    # 폐기 후에도 정상 동작해야 한다
    assert parser.feed(b"$ACK,GET,STATUS\n") == ["$ACK,GET,STATUS"]


def test_stream_parser_invalid_utf8_replaced() -> None:
    parser = ProtocolParser(max_line_bytes=4096)
    lines = parser.feed(b"\xff\xfeBoot\n")
    assert len(lines) == 1
    assert "Boot" in lines[0]


def test_stream_parser_reset() -> None:
    parser = ProtocolParser(max_line_bytes=4096)
    parser.feed(b"partial")
    parser.reset()
    assert parser.feed(b"data\n") == ["data"]
