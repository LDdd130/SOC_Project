"""Serial 수신 Worker 와 Mock Worker.

GUI 스레드에서 ``serial.readline()`` 을 호출하지 않는다. 수신은 항상
별도 QThread 에서 돌고, 결과는 Qt Signal 로만 전달한다.

두 Worker 는 같은 Signal 집합을 노출하므로 MainWindow 입장에서
실제 장치와 Mock 을 동일하게 다룰 수 있다.
"""

from __future__ import annotations

import logging
import queue
import time
from datetime import datetime

from PySide6.QtCore import QObject, QThread, Signal

from .constants import (
    MAX_LINE_BYTES,
    SERIAL_TIMEOUT_S,
)
from .mock_device import MockDevice
from .protocol import ProtocolParser, parse_line

logger = logging.getLogger(__name__)

try:  # pyserial 은 Mock 전용 실행에서는 없어도 되게 한다
    import serial
    from serial.tools import list_ports

    SERIAL_AVAILABLE = True
except ImportError:  # pragma: no cover
    serial = None  # type: ignore[assignment]
    list_ports = None  # type: ignore[assignment]
    SERIAL_AVAILABLE = False


__all__ = [
    "SERIAL_AVAILABLE",
    "available_ports",
    "SerialWorker",
    "MockWorker",
    "BaseWorker",
]


def available_ports() -> list[tuple[str, str]]:
    """사용 가능한 시리얼 포트 목록.

    Returns:
        ``(device, description)`` 튜플 목록. 조회 실패 시 빈 목록.
    """
    if not SERIAL_AVAILABLE or list_ports is None:
        return []
    try:
        return [(p.device, p.description or p.device) for p in list_ports.comports()]
    except Exception as exc:  # pragma: no cover - 플랫폼 의존
        logger.warning("포트 목록 조회 실패: %s", exc)
        return []


class BaseWorker(QObject):
    """Serial/Mock Worker 공통 Signal 정의.

    Signals:
        line_received: 파싱 전 원본 줄.
        parse_result_ready: :class:`ParseResult` 객체.
        bytes_received: 이번에 읽은 바이트 수.
        connected: 연결 성공.
        disconnected: 정상 종료.
        error_occurred: 사용자에게 보여줄 오류 문구.
        finished: 스레드 루프 종료.
    """

    line_received = Signal(str)
    parse_result_ready = Signal(object)
    bytes_received = Signal(int)
    connected = Signal(str)
    disconnected = Signal()
    error_occurred = Signal(str)
    finished = Signal()

    def __init__(self) -> None:
        super().__init__()
        self._running = False
        self._tx_queue: "queue.Queue[str]" = queue.Queue()

    # -- 공통 API ---------------------------------------------------------
    def stop(self) -> None:
        """루프 종료를 요청한다. 스레드 밖에서 호출해도 안전하다."""
        self._running = False

    def send_command(self, command: str) -> None:
        """송신 큐에 명령을 넣는다. Thread-safe.

        실제 write 는 Worker 스레드가 수행한다.
        """
        if command:
            self._tx_queue.put(command)

    def _drain_tx(self) -> list[str]:
        """큐에 쌓인 송신 명령을 모두 꺼낸다."""
        items: list[str] = []
        while True:
            try:
                items.append(self._tx_queue.get_nowait())
            except queue.Empty:
                break
        return items

    def _emit_line(self, text: str) -> None:
        """한 줄을 파싱해 Signal 로 내보낸다. 예외를 밖으로 흘리지 않는다."""
        try:
            self.line_received.emit(text)
            result = parse_line(text, now=datetime.now())
            self.parse_result_ready.emit(result)
        except Exception as exc:  # pragma: no cover - 방어적
            logger.exception("줄 처리 실패: %s", exc)


class SerialWorker(BaseWorker):
    """실제 UART 수신 Worker.

    :meth:`run` 은 QThread 안에서 실행된다. 포트가 갑자기 사라져도
    Signal 로 오류만 알리고 스레드를 정상 종료한다.
    """

    def __init__(self, port: str, baudrate: int) -> None:
        super().__init__()
        self._port = port
        self._baudrate = baudrate
        self._serial: "serial.Serial | None" = None
        self._parser = ProtocolParser(MAX_LINE_BYTES)

    def run(self) -> None:
        """수신 루프. QThread.started 에 연결한다."""
        if not SERIAL_AVAILABLE or serial is None:
            self.error_occurred.emit(
                "pyserial 이 설치돼 있지 않습니다. pip install pyserial"
            )
            self.finished.emit()
            return

        try:
            self._serial = serial.Serial(
                port=self._port,
                baudrate=self._baudrate,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
                timeout=SERIAL_TIMEOUT_S,
            )
        except Exception as exc:
            self.error_occurred.emit(f"포트 열기 실패 ({self._port}): {exc}")
            self.finished.emit()
            return

        self._running = True
        self._parser.reset()
        self.connected.emit(self._port)
        logger.info("Serial 연결: %s @ %d", self._port, self._baudrate)

        try:
            self._loop()
        except Exception as exc:  # pragma: no cover - 방어적
            logger.exception("Serial 루프 예외")
            self.error_occurred.emit(f"수신 오류: {exc}")
        finally:
            self._close()
            self.disconnected.emit()
            self.finished.emit()

    def _loop(self) -> None:
        assert self._serial is not None
        while self._running:
            # -- 송신 먼저 처리 -------------------------------------------
            for command in self._drain_tx():
                try:
                    self._serial.write(command.encode("utf-8", errors="replace"))
                    self._serial.flush()
                except Exception as exc:
                    self.error_occurred.emit(f"송신 실패: {exc}")
                    self._running = False
                    return

            # -- 수신 ----------------------------------------------------
            try:
                waiting = self._serial.in_waiting or 1
                chunk = self._serial.read(waiting)
            except Exception as exc:
                # 장치가 뽑혔거나 포트가 사라진 경우
                self.error_occurred.emit(f"장치 연결이 끊어졌습니다: {exc}")
                self._running = False
                return

            if not chunk:
                continue

            self.bytes_received.emit(len(chunk))
            for text in self._parser.feed(chunk):
                self._emit_line(text)

    def _close(self) -> None:
        if self._serial is not None:
            try:
                if self._serial.is_open:
                    self._serial.close()
            except Exception as exc:  # pragma: no cover
                logger.warning("포트 닫기 실패: %s", exc)
            self._serial = None


class MockWorker(BaseWorker):
    """Mock Simulator Worker.

    :class:`MockDevice` 를 주기적으로 tick 시키고 그 출력을 실제 Serial 과
    똑같은 Signal 로 흘린다. FPGA 없이 GUI 전체를 시험할 수 있다.
    """

    def __init__(self, period_ms: int, device: MockDevice | None = None) -> None:
        super().__init__()
        self._period_ms = max(1, period_ms)
        self.device = device or MockDevice()

    def set_period(self, period_ms: int) -> None:
        """tick 주기를 바꾼다. 실행 중 호출해도 된다."""
        self._period_ms = max(1, period_ms)

    def run(self) -> None:
        """Mock 루프."""
        self._running = True
        self.connected.emit("MOCK")
        logger.info("Mock Simulator 시작 (주기 %d ms)", self._period_ms)

        try:
            while self._running:
                for command in self._drain_tx():
                    for reply in self.device.handle_command(command):
                        self._emit_reply(reply)

                for text in self.device.tick(self._period_ms):
                    self._emit_reply(text)

                # 주기를 잘게 쪼개 자야 stop() 반응이 빠르다
                slept = 0.0
                period_s = self._period_ms / 1000.0
                while self._running and slept < period_s:
                    step = min(0.02, period_s - slept)
                    time.sleep(step)
                    slept += step
        except Exception as exc:  # pragma: no cover - 방어적
            logger.exception("Mock 루프 예외")
            self.error_occurred.emit(f"Mock 오류: {exc}")
        finally:
            self.disconnected.emit()
            self.finished.emit()

    def _emit_reply(self, text: str) -> None:
        self.bytes_received.emit(len(text) + 1)
        self._emit_line(text)


class WorkerThread(QThread):
    """Worker 를 담아 돌리는 QThread.

    ``terminate()`` 를 쓰지 않고 협조적으로 종료한다.
    """

    def __init__(self, worker: BaseWorker) -> None:
        super().__init__()
        self.worker = worker
        self.worker.moveToThread(self)
        self.started.connect(self.worker.run)  # type: ignore[arg-type]

    def shutdown(self, timeout_ms: int = 3000) -> None:
        """Worker 에 종료를 알리고 스레드가 끝날 때까지 기다린다."""
        self.worker.stop()
        self.quit()
        if not self.wait(timeout_ms):  # pragma: no cover - 타임아웃 경로
            logger.warning("Worker 스레드가 %d ms 안에 끝나지 않음", timeout_ms)
