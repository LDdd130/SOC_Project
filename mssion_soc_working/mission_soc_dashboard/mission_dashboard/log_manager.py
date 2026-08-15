"""CSV 로그 기록.

파일 쓰기가 실패해도 Serial 수신과 GUI 가 멈추지 않아야 한다.
따라서 모든 파일 작업은 예외를 삼키고 :attr:`LogManager.last_error` 에만 남긴다.
"""

from __future__ import annotations

import csv
import logging
from datetime import datetime
from pathlib import Path
from typing import Iterable

from .constants import (
    CSV_FIELDS,
    EVENT_CSV_FIELDS,
    EVENT_LOG_FILE_PREFIX,
    LOG_FILE_PREFIX,
)
from .models import LogRow, MissionStatus

logger = logging.getLogger(__name__)

__all__ = ["LogManager", "status_to_row", "default_log_dir"]


def default_log_dir() -> Path:
    """기본 로그 폴더. 사용자 홈 아래를 쓴다 (Windows 호환)."""
    return Path.home() / "mission_soc_logs"


def _timestamp_suffix() -> str:
    return datetime.now().strftime("%Y%m%d_%H%M%S")


def status_to_row(status: MissionStatus) -> dict[str, object]:
    """`MissionStatus` 를 CSV 한 행 dict 로 변환한다."""
    counts = status.fault_counts or (None, None, None)
    return {
        "received_at": status.received_at.isoformat(timespec="milliseconds"),
        "timestamp_ms": status.timestamp_ms,
        "system_state": status.system_state.value,
        "fault_level": int(status.fault_level),
        "fault_device": int(status.fault_device),
        "fault_code": f"0x{int(status.fault_code):02X}"
        if int(status.fault_code) >= 0
        else "",
        "alive_mask": f"0x{status.alive_mask:02X}",
        "timeout_mask": f"0x{status.timeout_mask:02X}",
        "output_enable_mask": f"0x{status.output_enable_mask:02X}",
        "actuator_enable": int(status.actuator_enable),
        "control_valid": "" if status.control_valid is None else int(status.control_valid),
        "state_timer": "" if status.state_timer is None else status.state_timer,
        "fault_count0": "" if counts[0] is None else counts[0],
        "fault_count1": "" if counts[1] is None else counts[1],
        "fault_count2": "" if counts[2] is None else counts[2],
        "raw_line": status.raw_line,
    }


class LogManager:
    """세션 CSV 로그 기록기.

    :meth:`start` 로 파일을 열고 :meth:`write_status` 로 한 줄씩 추가한다.
    실패하면 자동으로 기록을 중단하고 오류만 보관한다.
    """

    def __init__(self, log_dir: Path | None = None) -> None:
        self.log_dir = Path(log_dir) if log_dir else default_log_dir()
        self._file = None
        self._writer: csv.DictWriter | None = None
        self._path: Path | None = None
        self.rows_written = 0
        self.last_error: str | None = None

    # -- 상태 -------------------------------------------------------------
    @property
    def is_recording(self) -> bool:
        return self._writer is not None

    @property
    def current_path(self) -> Path | None:
        return self._path

    def set_log_dir(self, path: Path) -> None:
        """저장 폴더를 바꾼다. 기록 중이면 새 파일로 다시 시작한다."""
        was_recording = self.is_recording
        if was_recording:
            self.stop()
        self.log_dir = Path(path)
        if was_recording:
            self.start()

    # -- 기록 -------------------------------------------------------------
    def start(self) -> bool:
        """새 로그 파일을 연다.

        Returns:
            성공 여부. 실패해도 예외를 던지지 않는다.
        """
        if self.is_recording:
            return True
        try:
            self.log_dir.mkdir(parents=True, exist_ok=True)
            self._path = self.log_dir / f"{LOG_FILE_PREFIX}_{_timestamp_suffix()}.csv"
            self._file = self._path.open("w", newline="", encoding="utf-8")
            self._writer = csv.DictWriter(self._file, fieldnames=list(CSV_FIELDS))
            self._writer.writeheader()
            self._file.flush()
            self.rows_written = 0
            self.last_error = None
            logger.info("로그 기록 시작: %s", self._path)
            return True
        except Exception as exc:
            self.last_error = f"로그 파일을 열지 못했습니다: {exc}"
            logger.error(self.last_error)
            self._cleanup()
            return False

    def write_status(self, status: MissionStatus) -> None:
        """상태 한 줄을 기록한다. 실패 시 조용히 기록을 중단한다."""
        if self._writer is None or self._file is None:
            return
        try:
            self._writer.writerow(status_to_row(status))
            self.rows_written += 1
            if self.rows_written % 20 == 0:
                self._file.flush()
        except Exception as exc:
            self.last_error = f"로그 기록 실패: {exc}"
            logger.error(self.last_error)
            self._cleanup()

    def stop(self) -> None:
        """파일을 flush 하고 닫는다."""
        if self._file is not None:
            try:
                self._file.flush()
            except Exception:  # pragma: no cover
                pass
        self._cleanup()

    def _cleanup(self) -> None:
        if self._file is not None:
            try:
                self._file.close()
            except Exception:  # pragma: no cover
                pass
        self._file = None
        self._writer = None

    # -- Export -----------------------------------------------------------
    def export_statuses(self, path: Path, statuses: Iterable[MissionStatus]) -> bool:
        """현재 세션의 상태 목록을 별도 CSV 로 내보낸다."""
        try:
            path = Path(path)
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open("w", newline="", encoding="utf-8") as fp:
                writer = csv.DictWriter(fp, fieldnames=list(CSV_FIELDS))
                writer.writeheader()
                for status in statuses:
                    writer.writerow(status_to_row(status))
            return True
        except Exception as exc:
            self.last_error = f"Export 실패: {exc}"
            logger.error(self.last_error)
            return False

    def export_events(self, path: Path, rows: Iterable[LogRow]) -> bool:
        """Event Log 테이블 내용을 CSV 로 내보낸다."""
        try:
            path = Path(path)
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open("w", newline="", encoding="utf-8") as fp:
                writer = csv.DictWriter(fp, fieldnames=list(EVENT_CSV_FIELDS))
                writer.writeheader()
                for row in rows:
                    writer.writerow(
                        {
                            "received_at": row.received_at.isoformat(
                                timespec="milliseconds"
                            ),
                            "timestamp_ms": ""
                            if row.timestamp_ms is None
                            else row.timestamp_ms,
                            "message_type": row.message_type,
                            "event_type": row.event_type,
                            "state": row.state,
                            "fault_level": row.fault_level,
                            "fault_device": row.fault_device,
                            "fault_code": row.fault_code,
                            "description": row.description,
                            "raw_line": row.raw_line,
                        }
                    )
            return True
        except Exception as exc:
            self.last_error = f"Event Export 실패: {exc}"
            logger.error(self.last_error)
            return False

    def suggest_event_path(self) -> Path:
        """Event Export 기본 경로 제안."""
        return self.log_dir / f"{EVENT_LOG_FILE_PREFIX}_{_timestamp_suffix()}.csv"
