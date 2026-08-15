"""Python -> FPGA 송신 명령 생성.

모든 명령은 ASCII CSV 이며 끝에 ``\\n`` 을 붙인다.
검증에 실패하면 :class:`CommandError` 를 던진다. GUI 는 이를 잡아
사용자에게 안내하고, 잘못된 명령을 장치로 보내지 않는다.

명령 체계는 README_PROTOCOL.md 에 정리한 제안 규격이다.
FPGA 펌웨어가 아직 지원하지 않으면 ``$ERR,UNKNOWN_COMMAND`` 가 돌아온다.
"""

from __future__ import annotations

from .constants import (
    DEVICE_COUNT,
    IRQ_EN_ALL,
    LINE_TERMINATOR,
    MASK_MAX,
    MASK_MIN,
    PERSIST_LIMIT_MAX,
    PERSIST_LIMIT_MIN,
    RECOVERY_COUNT_MAX,
    RECOVERY_COUNT_MIN,
    TIMEOUT_MAX,
    TIMEOUT_MIN,
)
from .models import ConfigValues

__all__ = ["CommandError", "CommandBuilder"]


class CommandError(ValueError):
    """명령 인자 검증 실패."""


def _terminate(command: str) -> str:
    return command + LINE_TERMINATOR


def _check_device(device: int) -> int:
    if not isinstance(device, int) or isinstance(device, bool):
        raise CommandError(f"device 는 정수여야 합니다: {device!r}")
    if not (0 <= device < DEVICE_COUNT):
        raise CommandError(f"device 범위는 0~{DEVICE_COUNT - 1} 입니다: {device}")
    return device


def _check_range(name: str, value: int, low: int, high: int) -> int:
    if not isinstance(value, int) or isinstance(value, bool):
        raise CommandError(f"{name} 은 정수여야 합니다: {value!r}")
    if not (low <= value <= high):
        raise CommandError(f"{name} 범위는 {low}~{high} 입니다: {value}")
    return value


class CommandBuilder:
    """송신 명령 문자열 생성기.

    모든 메서드는 줄바꿈까지 포함한 완성된 문자열을 돌려준다.
    상태를 갖지 않으므로 정적 메서드로 구성한다.
    """

    # -- 조회 -------------------------------------------------------------
    @staticmethod
    def get_status() -> str:
        """현재 상태 1회 요청."""
        return _terminate("GET,STATUS")

    @staticmethod
    def get_config() -> str:
        """현재 설정 레지스터 값 요청."""
        return _terminate("GET,CONFIG")

    @staticmethod
    def get_irq() -> str:
        """세 IP 의 `IRQ_EN` / `IRQ_STATUS` 현재값 요청.

        응답은 `$ACK,GET,IRQ` 다음 줄의
        `$IRQ,<en_mask>,<hb_status>,<fm_status>,<sc_status>` 다.
        """
        return _terminate("GET,IRQ")

    # -- 설정 -------------------------------------------------------------
    @staticmethod
    def set_timeout(device: int, clocks: int) -> str:
        """`TIMEOUTn` 설정. 값은 100MHz Clock Count 정수다.

        FPGA 는 0 을 유효값 1 로 간주한다 (00 공통명세 12.1).
        """
        _check_device(device)
        _check_range("TIMEOUT", clocks, TIMEOUT_MIN, TIMEOUT_MAX)
        return _terminate(f"SET,TIMEOUT,{device},{clocks}")

    @staticmethod
    def set_critical_mask(mask: int) -> str:
        """`CRITICAL_MASK` 설정. Timeout/Error/Critical 모두에 적용된다."""
        _check_range("CRITICAL_MASK", mask, MASK_MIN, MASK_MAX)
        return _terminate(f"SET,CRITICAL_MASK,0x{mask:02X}")

    @staticmethod
    def set_persist_limit(value: int) -> str:
        """`PERSIST_LIMIT` 설정. eval_tick 기준 지속 횟수다."""
        _check_range("PERSIST_LIMIT", value, PERSIST_LIMIT_MIN, PERSIST_LIMIT_MAX)
        return _terminate(f"SET,PERSIST_LIMIT,{value}")

    @staticmethod
    def set_recovery_count(value: int) -> str:
        """`RECOVERY_COUNT` 설정.

        권장 조건은 ``RECOVERY_COUNT < PERSIST_LIMIT`` 이지만
        (03_MEMBER_C 6장) 여기서는 막지 않는다. GUI 가 경고만 표시한다.
        """
        _check_range("RECOVERY_COUNT", value, RECOVERY_COUNT_MIN, RECOVERY_COUNT_MAX)
        return _terminate(f"SET,RECOVERY_COUNT,{value}")

    @staticmethod
    def set_degrade_mask(mask: int) -> str:
        """`DEGRADE_MASK` 설정. fault_device=3 인 DEGRADED 에서만 적용된다."""
        _check_range("DEGRADE_MASK", mask, MASK_MIN, MASK_MAX)
        return _terminate(f"SET,DEGRADE_MASK,0x{mask:02X}")

    @staticmethod
    def set_irq_en(mask: int) -> str:
        """세 IP 의 `IRQ_EN` 을 한 번에 설정한다.

        bit0=A(하트비트), bit1=B(고장관리), bit2=C(안전제어).

        `0` 을 보내면 irq 핀이 막혀 ISR 이 돌지 않는다. 그동안 IRQ_STATUS
        래치는 계속 쌓이므로 `GET,IRQ` 로 Pending 을 눈으로 볼 수 있다.
        `CMD,CLEAR_IRQ` 의 W1C 동작을 검증하는 유일한 방법이다
        (05 시나리오 15번). **확인 후에는 반드시 다시 켜야 한다.**
        """
        _check_range("IRQ_EN", mask, 0, IRQ_EN_ALL)
        return _terminate(f"SET,IRQ_EN,0x{mask:02X}")

    @classmethod
    def apply_config(cls, config: ConfigValues) -> list[str]:
        """설정 전체를 순서대로 보낼 명령 목록을 만든다.

        MicroBlaze 초기화 순서(00 공통명세 12.2)와 같은 순서를 따른다.
        """
        commands = [
            cls.set_timeout(0, config.timeout0),
            cls.set_timeout(1, config.timeout1),
            cls.set_timeout(2, config.timeout2),
            cls.set_critical_mask(config.critical_mask),
            cls.set_persist_limit(config.persist_limit),
            cls.set_recovery_count(config.recovery_count),
            cls.set_degrade_mask(config.degrade_mask),
        ]
        return commands

    # -- 제어 -------------------------------------------------------------
    @staticmethod
    def manual_reset() -> str:
        """SAFE_MODE 복구 시도.

        FPGA 는 ``fault_valid=1`` 이고 ``fault_level=0`` 일 때만 승인한다.
        앱이 성공을 가정하면 안 된다.
        """
        return _terminate("CMD,MANUAL_RESET")

    @staticmethod
    def clear_irq() -> str:
        """세 IP 의 `IRQ_STATUS` W1C. Fault/Timeout 상태는 안 바뀐다."""
        return _terminate("CMD,CLEAR_IRQ")

    @staticmethod
    def clear_heartbeat() -> str:
        """Heartbeat `CLEAR_ALL` W1P. Counter/Timeout 만 Clear 한다."""
        return _terminate("CMD,CLEAR_HEARTBEAT")

    @staticmethod
    def reset_fault() -> str:
        """Fault Manager `RESET_FAULT` W1P.

        현재 Fault 가 하나라도 있으면 FPGA 가 무시한다 (02_MEMBER_B 6.1).
        """
        return _terminate("CMD,RESET_FAULT")

    # -- Fault Injection --------------------------------------------------
    @staticmethod
    def inject(kind: str, device: int, on: bool) -> str:
        """Fault 주입 명령.

        Args:
            kind: ``ERROR`` / ``CRITICAL`` / ``TIMEOUT``.
            device: 0~2.
            on: True 면 ON, False 면 OFF.
        """
        token = (kind or "").strip().upper()
        if token not in {"ERROR", "CRITICAL", "TIMEOUT"}:
            raise CommandError(
                f"kind 는 ERROR/CRITICAL/TIMEOUT 중 하나여야 합니다: {kind!r}"
            )
        _check_device(device)
        return _terminate(f"INJECT,{token},{device},{'ON' if on else 'OFF'}")

    @classmethod
    def inject_error(cls, device: int, on: bool) -> str:
        return cls.inject("ERROR", device, on)

    @classmethod
    def inject_critical(cls, device: int, on: bool) -> str:
        return cls.inject("CRITICAL", device, on)

    @classmethod
    def inject_timeout(cls, device: int, on: bool) -> str:
        return cls.inject("TIMEOUT", device, on)

    @staticmethod
    def inject_clear_all() -> str:
        """모든 주입 해제."""
        return _terminate("INJECT,CLEAR,ALL")

    @classmethod
    def multi_device_demo(cls) -> list[str]:
        """Device 0 Timeout + Device 1 Error 시연 — **단계적 상승**.

        Error 는 즉시 성립하지만 Timeout 은 Device 0 의 TIMEOUT0(기본 0.3초)이
        지나야 성립한다. 그래서 두 Fault 가 동시에 서지 않고

            Error D1 성립 -> Level 1/2 (WARNING -> DEGRADED)
            약 0.3초 뒤 Timeout D0 성립 -> Level 3 / FAULT_MULTI_DEVICE

        로 두 번에 걸쳐 올라간다. 승격 과정을 보여주는 데는 좋지만
        "동시 다중 Fault" 자체를 보려면 :meth:`multi_error_demo` 를 써야 한다.
        """
        return [cls.inject_timeout(0, True), cls.inject_error(1, True)]

    @classmethod
    def multi_error_demo(cls) -> list[str]:
        """Device 0 + Device 1 Error 시연 — 다중 장치 `FAULT_MULTI_DEVICE`.

        Error 주입 자체는 AXI GPIO 라 하드웨어 지연이 없다. 그래도 화면에는
        2단계로 보인다. 두 `INJECT` 가 **별개의 UART 줄**이라 9600bps 링크에서
        순차 처리되기 때문이다 (실측 141013 로그 229ms).

            ERROR D0 성립 -> Level 1/2 (WARNING -> DEGRADED, device 0)
            약 0.2초 뒤 ERROR D1 합류 -> Level 3 / FAULT_MULTI_DEVICE (device 3)

        :meth:`multi_device_demo` 와 차이는 지연의 **원인**이다. 저쪽은
        하트비트 Timeout 0.3초라는 하드웨어 지연이고, 이쪽은 링크 전송 시간뿐이라
        보드 내부 지연은 `PERSIST_LIMIT` tick 하나다.

        클럭 단위 동시 성립(`fault_num >= 2` 가 같은 판정에서 서는 경우)은
        UART 로는 만들 수 없다. `sim/tb_fault_manager_core.v` 가 커버한다.
        """
        return [cls.inject_error(0, True), cls.inject_error(1, True)]

    @classmethod
    def critical_demo(cls) -> list[str]:
        """Device 2 Critical 시연. 기본 CRITICAL_MASK=0x04 라 즉시 Level 3."""
        return [cls.inject_critical(2, True)]

    @classmethod
    def critical_mask_error_demo(cls) -> list[str]:
        """Device 2 **Error** 시연 — CRITICAL_MASK 가 Fault 종류를 안 가린다.

        `CRITICAL_MASK` 는 `device_fault = timeout | error_flag | critical_fault`
        에 걸린다 (fault_manager_core.v). 그래서 Device 2 는 `critical_fault`
        핀이 아니라 평범한 Error 만으로도 지속시간 없이 Level 3 이 된다.
        `Device 2 Critical Demo` 와 달리 fault_code 는 `FAULT_CRITICAL` 로
        같지만, 입력이 error_flag 라는 점이 다르다.
        """
        return [cls.inject_error(2, True)]
