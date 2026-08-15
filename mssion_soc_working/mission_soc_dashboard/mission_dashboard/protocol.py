"""UART 수신 메시지 Parser.

GUI 와 완전히 분리된 순수 함수 계층이다. 어떤 입력이 들어와도
예외를 밖으로 던지지 않고 :class:`ParseResult` 로 돌려준다.

지원 메시지 (03_MEMBER_C 11장 및 프로토콜 확장):
    $MISSION,timestamp,state,level,device,code,alive,timeout,oe,actuator[,...]
    $EVENT,timestamp,event_type[,arg...]
    $ACK,command[,arg...]
    $ERR,error_code[,description...]
    $IRQ,en_mask,hb_status,fm_status,sc_status
    그 외 문자열 -> RAW (디버그 출력)

Enum 정책:
    알 수 없는 State/Code/Device/Level 은 예외로 만들지 않고 UNKNOWN Enum 을
    사용한다. 숫자로 해석 자체가 불가능한 경우에만 Parse Error 로 처리한다.
    이 원칙을 파일 전체에서 일관되게 유지한다.
"""

from __future__ import annotations

from datetime import datetime

from .constants import (
    IRQ_FIELDS,
    MSG_PREFIX_ACK,
    MSG_PREFIX_ERR,
    MSG_PREFIX_EVENT,
    MSG_PREFIX_IRQ,
    MSG_PREFIX_MISSION,
)
from .models import (
    CommandResponse,
    FaultCode,
    FaultDevice,
    FaultLevel,
    IrqStatus,
    MissionEvent,
    MissionStatus,
    ParseResult,
    SystemState,
)

__all__ = ["parse_line", "parse_int", "ProtocolParser"]


def parse_int(token: str) -> int | None:
    """10진수 또는 `0x` 16진수 문자열을 정수로 변환한다.

    변환 불가면 ``None``. 예외를 던지지 않는다.

    >>> parse_int(" 0x04 ")
    4
    >>> parse_int("12")
    12
    >>> parse_int("nope") is None
    True
    """
    if token is None:
        return None
    text = token.strip()
    if not text:
        return None

    negative = False
    if text[0] in "+-":
        negative = text[0] == "-"
        text = text[1:].strip()
        if not text:
            return None

    try:
        if text.lower().startswith("0x"):
            value = int(text, 16)
        elif text.lower().startswith("0b"):
            value = int(text, 2)
        else:
            value = int(text, 10)
    except (ValueError, TypeError):
        return None
    return -value if negative else value


def _split_csv(line: str) -> list[str]:
    """CSV 를 나누고 각 토큰의 공백을 제거한다."""
    return [tok.strip() for tok in line.split(",")]


def _normalize(line: str) -> str:
    """CR/LF, NUL, 앞뒤 공백을 제거한다."""
    return line.replace("\r", "").replace("\n", "").replace("\x00", "").strip()


def _fail(message_type: str, raw: str, error: str) -> ParseResult:
    return ParseResult(
        success=False, message_type=message_type, raw_line=raw, error=error
    )


def _parse_mission(tokens: list[str], raw: str, now: datetime) -> ParseResult:
    """`$MISSION` 파싱.

    필수 필드 9개(timestamp ~ actuator_enable)를 요구하고,
    그 뒤 control_valid / state_timer / fault_count0~2 는 선택으로 처리한다.
    """
    body = tokens[1:]
    if len(body) < 9:
        return _fail(
            "MISSION",
            raw,
            f"필드 부족: {len(body)}개 (최소 9개 필요)",
        )

    timestamp = parse_int(body[0])
    if timestamp is None or timestamp < 0:
        return _fail("MISSION", raw, f"invalid timestamp: {body[0]!r}")

    state = SystemState.from_raw(body[1])

    level_raw = parse_int(body[2])
    if level_raw is None:
        return _fail("MISSION", raw, f"invalid fault_level: {body[2]!r}")
    fault_level = FaultLevel.from_raw(level_raw)

    device_raw = parse_int(body[3])
    if device_raw is None:
        return _fail("MISSION", raw, f"invalid fault_device: {body[3]!r}")
    fault_device = FaultDevice.from_raw(device_raw)

    code_raw = parse_int(body[4])
    if code_raw is None:
        return _fail("MISSION", raw, f"invalid fault_code: {body[4]!r}")
    fault_code = FaultCode.from_raw(code_raw)

    alive = parse_int(body[5])
    if alive is None:
        return _fail("MISSION", raw, f"invalid alive mask: {body[5]!r}")

    timeout = parse_int(body[6])
    if timeout is None:
        return _fail("MISSION", raw, f"invalid timeout mask: {body[6]!r}")

    output_enable = parse_int(body[7])
    if output_enable is None:
        return _fail("MISSION", raw, f"invalid output_enable mask: {body[7]!r}")

    actuator = parse_int(body[8])
    if actuator is None:
        return _fail("MISSION", raw, f"invalid actuator_enable: {body[8]!r}")

    # ----- 선택 필드 -----------------------------------------------------
    control_valid: bool | None = None
    if len(body) >= 10:
        cv = parse_int(body[9])
        control_valid = None if cv is None else bool(cv)

    state_timer: int | None = None
    if len(body) >= 11:
        state_timer = parse_int(body[10])

    fault_counts: tuple[int, int, int] | None = None
    if len(body) >= 14:
        counts = [parse_int(body[11]), parse_int(body[12]), parse_int(body[13])]
        if all(c is not None for c in counts):
            fault_counts = (counts[0], counts[1], counts[2])  # type: ignore[assignment]

    status = MissionStatus(
        timestamp_ms=timestamp,
        system_state=state,
        fault_level=fault_level,
        fault_device=fault_device,
        fault_code=fault_code,
        alive_mask=alive & 0x7,
        timeout_mask=timeout & 0x7,
        output_enable_mask=output_enable & 0x7,
        actuator_enable=bool(actuator),
        control_valid=control_valid,
        state_timer=state_timer,
        fault_counts=fault_counts,
        raw_line=raw,
        received_at=now,
    )
    return ParseResult(
        success=True, message_type="MISSION", raw_line=raw, status=status
    )


def _parse_event(tokens: list[str], raw: str, now: datetime) -> ParseResult:
    """`$EVENT` 파싱.

    인자 수가 예상과 달라도 실패시키지 않는다. 원본을 보존하는 것이 우선이다.
    """
    body = tokens[1:]
    if len(body) < 2:
        return _fail("EVENT", raw, f"필드 부족: {len(body)}개 (최소 2개 필요)")

    timestamp = parse_int(body[0])
    if timestamp is None or timestamp < 0:
        return _fail("EVENT", raw, f"invalid timestamp: {body[0]!r}")

    event_type = body[1]
    if not event_type:
        return _fail("EVENT", raw, "event_type 이 비어 있음")

    event = MissionEvent(
        timestamp_ms=timestamp,
        event_type=event_type,
        args=tuple(body[2:]),
        raw_line=raw,
        received_at=now,
    )
    return ParseResult(success=True, message_type="EVENT", raw_line=raw, event=event)


def _parse_irq(tokens: list[str], raw: str, timestamp: datetime) -> ParseResult:
    """`$IRQ,<en_mask>,<hb_status>,<fm_status>,<sc_status>` 파싱.

    네 값 모두 마스크라 `0x` 16진수로 온다. :func:`parse_int` 가 10진수도
    받으므로 펌웨어가 표기를 바꿔도 깨지지 않는다.
    """
    body = tokens[1:]
    if len(body) < IRQ_FIELDS:
        return _fail(
            "IRQ", raw, f"필드 부족: {len(body)}개 ({IRQ_FIELDS}개 필요)"
        )

    names = ("en_mask", "hb_status", "fm_status", "sc_status")
    values: list[int] = []
    for name, token in zip(names, body[:IRQ_FIELDS]):
        value = parse_int(token)
        if value is None or value < 0:
            return _fail("IRQ", raw, f"invalid {name}: {token!r}")
        values.append(value)

    irq = IrqStatus(
        en_mask=values[0],
        hb_status=values[1],
        fm_status=values[2],
        sc_status=values[3],
        raw_line=raw,
        received_at=timestamp,
    )
    return ParseResult(success=True, message_type="IRQ", raw_line=raw, irq=irq)


def _parse_response(
    tokens: list[str], raw: str, now: datetime, *, is_ack: bool
) -> ParseResult:
    """`$ACK` / `$ERR` 파싱."""
    kind = "ACK" if is_ack else "ERR"
    body = tokens[1:]
    if not body or not body[0]:
        return _fail(kind, raw, f"{kind} 에 command 가 없음")

    response = CommandResponse(
        is_ack=is_ack,
        command=body[0],
        args=tuple(body[1:]),
        raw_line=raw,
        received_at=now,
    )
    return ParseResult(success=True, message_type=kind, raw_line=raw, response=response)


def parse_line(line: str, *, now: datetime | None = None) -> ParseResult:
    """UART 한 줄을 파싱한다.

    어떤 입력에도 예외를 던지지 않는다.

    Args:
        line: 수신한 원본 문자열. CR/LF 포함 가능.
        now: 수신 시각. 테스트에서 고정하려고 주입할 수 있다.

    Returns:
        성공/실패가 담긴 :class:`ParseResult`.
    """
    timestamp = now or datetime.now()

    try:
        text = _normalize(line if isinstance(line, str) else str(line))
    except Exception:  # pragma: no cover - 방어적
        return _fail("RAW", str(line), "정규화 실패")

    if not text:
        return _fail("EMPTY", "", "빈 줄")

    if not text.startswith("$"):
        # 디버그 문자열. 실패가 아니라 RAW 성공으로 취급해 Raw Log 에 남긴다.
        return ParseResult(success=True, message_type="RAW", raw_line=text)

    try:
        tokens = _split_csv(text)
        prefix = tokens[0].upper()

        if prefix == MSG_PREFIX_MISSION:
            return _parse_mission(tokens, text, timestamp)
        if prefix == MSG_PREFIX_EVENT:
            return _parse_event(tokens, text, timestamp)
        if prefix == MSG_PREFIX_ACK:
            return _parse_response(tokens, text, timestamp, is_ack=True)
        if prefix == MSG_PREFIX_ERR:
            return _parse_response(tokens, text, timestamp, is_ack=False)
        if prefix == MSG_PREFIX_IRQ:
            return _parse_irq(tokens, text, timestamp)

        return ParseResult(success=True, message_type="RAW", raw_line=text)
    except Exception as exc:  # pragma: no cover - 최후 방어
        return _fail("RAW", text, f"예상치 못한 파싱 오류: {exc}")


class ProtocolParser:
    """바이트 스트림을 줄 단위로 조립해 파싱하는 헬퍼.

    Serial 은 한 번에 한 줄이 오지 않는다. 줄바꿈이 들어올 때까지 버퍼에
    모아두고, 비정상적으로 긴 줄은 폐기한다.
    """

    def __init__(self, max_line_bytes: int) -> None:
        self._buffer = bytearray()
        self._max_line_bytes = max_line_bytes
        self.dropped_lines = 0

    def reset(self) -> None:
        """버퍼를 비운다. 연결/해제 시 호출한다."""
        self._buffer.clear()

    def feed(self, chunk: bytes) -> list[str]:
        """수신 바이트를 넣고 완성된 줄 목록을 돌려준다.

        Args:
            chunk: Serial 에서 읽은 raw bytes.

        Returns:
            디코드까지 마친 완성된 줄. 미완성분은 내부 버퍼에 남는다.
        """
        if not chunk:
            return []

        self._buffer.extend(chunk)
        lines: list[str] = []

        while True:
            idx = self._buffer.find(b"\n")
            if idx < 0:
                break
            raw = bytes(self._buffer[:idx])
            del self._buffer[: idx + 1]
            text = raw.decode("utf-8", errors="replace").strip()
            if text:
                lines.append(text)

        # 줄바꿈 없이 과도하게 쌓이면 비정상 -> 폐기
        if len(self._buffer) > self._max_line_bytes:
            self._buffer.clear()
            self.dropped_lines += 1

        return lines
