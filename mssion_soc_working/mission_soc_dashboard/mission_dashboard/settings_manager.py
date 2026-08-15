"""JSON 설정 저장/복원.

설정 파일이 손상돼도 기본값으로 실행돼야 한다. 따라서 읽기 실패는
예외가 아니라 "기본값 사용"으로 처리한다.

경로: ``~/.mission_soc_dashboard/settings.json`` (Windows 포함)
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

from .constants import (
    DEFAULT_BAUDRATE,
    DEFAULT_CHART_WINDOW_S,
    DEFAULT_CRITICAL_MASK,
    DEFAULT_DEGRADE_MASK,
    DEFAULT_MAX_LOG_ROWS,
    DEFAULT_MOCK_PERIOD_MS,
    DEFAULT_PERSIST_LIMIT,
    DEFAULT_RECOVERY_COUNT,
    DEFAULT_TIMEOUT_CLOCKS,
    DEFAULT_WINDOW_HEIGHT,
    DEFAULT_WINDOW_WIDTH,
    SETTINGS_DIR_NAME,
    SETTINGS_FILE_NAME,
)
from .log_manager import default_log_dir
from .theme import DEFAULT_THEME

logger = logging.getLogger(__name__)

__all__ = ["SettingsManager", "DEFAULT_SETTINGS"]


DEFAULT_SETTINGS: dict[str, Any] = {
    "last_port": "",
    "last_baudrate": DEFAULT_BAUDRATE,
    "window_width": DEFAULT_WINDOW_WIDTH,
    "window_height": DEFAULT_WINDOW_HEIGHT,
    "window_x": None,
    "window_y": None,
    "log_dir": str(default_log_dir()),
    "auto_log": False,
    "chart_window_s": DEFAULT_CHART_WINDOW_S,
    "max_log_rows": DEFAULT_MAX_LOG_ROWS,
    "mock_period_ms": DEFAULT_MOCK_PERIOD_MS,
    # 화면 테마. theme.PALETTES 의 키. 모르는 값이면 기본 테마로 되돌아간다.
    "theme": DEFAULT_THEME,
    # 접이식 섹션의 펼침 상태. {섹션 키: bool}
    "sections": {},
    "config": {
        "timeout0": DEFAULT_TIMEOUT_CLOCKS[0],
        "timeout1": DEFAULT_TIMEOUT_CLOCKS[1],
        "timeout2": DEFAULT_TIMEOUT_CLOCKS[2],
        "critical_mask": DEFAULT_CRITICAL_MASK,
        "persist_limit": DEFAULT_PERSIST_LIMIT,
        "recovery_count": DEFAULT_RECOVERY_COUNT,
        "degrade_mask": DEFAULT_DEGRADE_MASK,
    },
}


class SettingsManager:
    """설정 dict 를 JSON 파일로 유지한다."""

    def __init__(self, path: Path | None = None) -> None:
        self.path = Path(path) if path else self.default_path()
        self._data: dict[str, Any] = json.loads(json.dumps(DEFAULT_SETTINGS))
        self.last_error: str | None = None

    @staticmethod
    def default_path() -> Path:
        """``~/.mission_soc_dashboard/settings.json``."""
        return Path.home() / SETTINGS_DIR_NAME / SETTINGS_FILE_NAME

    # -- 접근 -------------------------------------------------------------
    def get(self, key: str, default: Any = None) -> Any:
        """단일 키 조회. 없으면 기본 설정 -> 인자 순으로 대체한다."""
        if key in self._data:
            return self._data[key]
        if key in DEFAULT_SETTINGS:
            return DEFAULT_SETTINGS[key]
        return default

    def set(self, key: str, value: Any) -> None:
        self._data[key] = value

    def update(self, values: dict[str, Any]) -> None:
        self._data.update(values)

    def get_config(self) -> dict[str, int]:
        """설정 레지스터 값 묶음. 누락 키는 기본값으로 채운다."""
        stored = self._data.get("config") or {}
        merged = dict(DEFAULT_SETTINGS["config"])
        for key, value in stored.items():
            if key in merged and isinstance(value, int) and not isinstance(value, bool):
                merged[key] = value
        return merged

    def set_config(self, config: dict[str, int]) -> None:
        self._data["config"] = dict(config)

    # -- 파일 -------------------------------------------------------------
    def load(self) -> bool:
        """설정을 읽는다. 실패하면 기본값을 유지하고 False 를 돌려준다."""
        try:
            if not self.path.exists():
                logger.info("설정 파일 없음. 기본값 사용: %s", self.path)
                return False
            with self.path.open("r", encoding="utf-8") as fp:
                loaded = json.load(fp)
            if not isinstance(loaded, dict):
                raise ValueError("최상위가 object 가 아님")

            merged = json.loads(json.dumps(DEFAULT_SETTINGS))
            for key, value in loaded.items():
                if key == "config" and isinstance(value, dict):
                    merged["config"].update(
                        {
                            k: v
                            for k, v in value.items()
                            if k in merged["config"] and isinstance(v, int)
                        }
                    )
                else:
                    merged[key] = value
            self._data = merged
            self.last_error = None
            return True
        except Exception as exc:
            self.last_error = f"설정 파일이 손상돼 기본값을 사용합니다: {exc}"
            logger.warning(self.last_error)
            self._data = json.loads(json.dumps(DEFAULT_SETTINGS))
            return False

    def save(self) -> bool:
        """설정을 저장한다. 실패해도 앱을 죽이지 않는다."""
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            tmp = self.path.with_suffix(".json.tmp")
            with tmp.open("w", encoding="utf-8") as fp:
                json.dump(self._data, fp, indent=2, ensure_ascii=False)
            tmp.replace(self.path)
            self.last_error = None
            return True
        except Exception as exc:
            self.last_error = f"설정 저장 실패: {exc}"
            logger.error(self.last_error)
            return False

    def as_dict(self) -> dict[str, Any]:
        """현재 설정 사본."""
        return json.loads(json.dumps(self._data))
