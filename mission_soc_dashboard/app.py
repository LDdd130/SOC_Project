#!/usr/bin/env python3
"""Mission SoC Dashboard 실행 진입점.

사용법::

    python app.py

Windows High DPI 환경을 고려해 스케일링 정책을 먼저 지정한다.
"""

from __future__ import annotations

import logging
import sys
import traceback
from pathlib import Path
from types import TracebackType

# 소스 트리에서 바로 실행할 수 있게 패키지 경로를 잡는다
sys.path.insert(0, str(Path(__file__).resolve().parent))

from PySide6.QtCore import Qt  # noqa: E402
from PySide6.QtGui import QGuiApplication  # noqa: E402
from PySide6.QtWidgets import QApplication, QMessageBox  # noqa: E402

from mission_dashboard.constants import (  # noqa: E402
    APP_NAME,
    APP_VERSION,
    ORG_NAME,
    SETTINGS_DIR_NAME,
)
from mission_dashboard.main_window import MainWindow  # noqa: E402

logger = logging.getLogger("mission_dashboard")


def setup_logging() -> None:
    """콘솔 + 파일 로깅 초기화.

    파일 로그를 만들지 못해도 앱은 계속 실행된다.
    """
    handlers: list[logging.Handler] = [logging.StreamHandler(sys.stdout)]
    try:
        log_dir = Path.home() / SETTINGS_DIR_NAME
        log_dir.mkdir(parents=True, exist_ok=True)
        handlers.append(logging.FileHandler(log_dir / "app.log", encoding="utf-8"))
    except Exception:  # pragma: no cover - 권한 문제 등
        pass

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        handlers=handlers,
    )


def install_excepthook() -> None:
    """처리되지 않은 예외를 로깅한다. 앱을 즉시 죽이지 않는다."""

    def hook(
        exc_type: type[BaseException],
        exc_value: BaseException,
        exc_tb: TracebackType | None,
    ) -> None:
        if issubclass(exc_type, KeyboardInterrupt):
            sys.__excepthook__(exc_type, exc_value, exc_tb)
            return
        text = "".join(traceback.format_exception(exc_type, exc_value, exc_tb))
        logger.error("처리되지 않은 예외:\n%s", text)
        try:
            QMessageBox.critical(
                None,
                "오류",
                f"처리되지 않은 오류가 발생했습니다.\n\n{exc_value}\n\n"
                "자세한 내용은 로그 파일을 확인하십시오.",
            )
        except Exception:  # pragma: no cover - GUI 준비 전
            pass

    sys.excepthook = hook


def configure_high_dpi() -> None:
    """QApplication 생성 전에 호출해야 하는 High DPI 설정."""
    try:
        QGuiApplication.setHighDpiScaleFactorRoundingPolicy(
            Qt.HighDpiScaleFactorRoundingPolicy.PassThrough
        )
    except Exception:  # pragma: no cover - Qt 버전 차이
        pass


def main() -> int:
    """앱을 실행하고 종료 코드를 돌려준다."""
    setup_logging()
    configure_high_dpi()

    app = QApplication(sys.argv)
    app.setApplicationName(APP_NAME)
    app.setApplicationVersion(APP_VERSION)
    app.setOrganizationName(ORG_NAME)

    install_excepthook()

    logger.info("%s v%s 시작", APP_NAME, APP_VERSION)

    window = MainWindow()
    window.show()

    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
