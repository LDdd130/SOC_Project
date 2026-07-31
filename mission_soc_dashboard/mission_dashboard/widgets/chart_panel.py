"""실시간 차트 패널.

pyqtgraph 가 없으면 안내 문구만 표시하고 앱은 계속 동작한다.
"""

from __future__ import annotations

import time
from collections import deque

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from ..constants import (
    CHART_WINDOW_CHOICES_S,
    DEFAULT_CHART_WINDOW_S,
    DEVICE_COUNT,
    MAX_CHART_SAMPLES,
)
from ..models import MissionStatus
from ..theme import T

__all__ = ["ChartPanel", "PYQTGRAPH_AVAILABLE"]

try:
    import pyqtgraph as pg

    PYQTGRAPH_AVAILABLE = True
except ImportError:  # pragma: no cover
    pg = None  # type: ignore[assignment]
    PYQTGRAPH_AVAILABLE = False


class ChartPanel(QWidget):
    """Fault Level / System State / Actuator / Device Timeout 시계열 표시.

    샘플 수를 :data:`MAX_CHART_SAMPLES` 로 제한해 메모리 무한 증가를 막는다.
    수신 주기가 불규칙해도 실제 수신 시각을 x 축으로 쓰므로 문제없다.
    """

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self._paused = False
        self._t0 = time.monotonic()
        self._window_s = DEFAULT_CHART_WINDOW_S

        self._t: deque[float] = deque(maxlen=MAX_CHART_SAMPLES)
        self._level: deque[int] = deque(maxlen=MAX_CHART_SAMPLES)
        self._state: deque[int] = deque(maxlen=MAX_CHART_SAMPLES)
        self._actuator: deque[int] = deque(maxlen=MAX_CHART_SAMPLES)
        self._timeouts: list[deque[int]] = [
            deque(maxlen=MAX_CHART_SAMPLES) for _ in range(DEVICE_COUNT)
        ]

        root = QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(6)

        root.addLayout(self._build_toolbar())

        if not PYQTGRAPH_AVAILABLE:
            notice = QLabel(
                "pyqtgraph 가 설치돼 있지 않아 차트를 표시할 수 없습니다.\n"
                "pip install pyqtgraph 후 다시 실행하십시오."
            )
            notice.setStyleSheet(f"color:{T.text_dim}; font-size:12px;")
            self._notice = notice
            root.addWidget(notice)
            root.addStretch(1)
            return

        pg.setConfigOptions(antialias=True, background=T.bg, foreground=T.text)

        self._plot_top = pg.PlotWidget()
        self._plot_top.setYRange(-0.2, 3.4)
        self._plot_top.setLabel("left", "Level / State")
        self._plot_top.showGrid(x=True, y=True, alpha=0.25)
        self._plot_top.addLegend(offset=(10, 5))
        self._curve_level = self._plot_top.plot(
            pen=pg.mkPen(T.state_safe_mode, width=2), name="Fault Level"
        )
        # State 는 점선으로 그려 Fault Level 과 겹쳐도 구분되게 한다
        self._curve_state = self._plot_top.plot(
            pen=pg.mkPen(T.accent, width=2, style=Qt.PenStyle.DashLine),
            name="System State",
        )
        root.addWidget(self._plot_top, 2)

        self._plot_bottom = pg.PlotWidget()
        self._plot_bottom.setYRange(-0.2, 1.4)
        self._plot_bottom.setLabel("left", "Actuator / Timeout")
        self._plot_bottom.setLabel("bottom", "시간 (s)")
        self._plot_bottom.showGrid(x=True, y=True, alpha=0.25)
        self._plot_bottom.addLegend(offset=(10, 5))
        self._plot_bottom.setXLink(self._plot_top)

        self._curve_actuator = self._plot_bottom.plot(
            pen=pg.mkPen(T.state_warning, width=2), name="Actuator Enable"
        )
        timeout_colors = (T.state_degraded, T.accent, T.state_safe_mode)
        self._curve_timeouts = []
        for i in range(DEVICE_COUNT):
            curve = self._plot_bottom.plot(
                pen=pg.mkPen(timeout_colors[i % len(timeout_colors)], width=1),
                name=f"Timeout D{i}",
            )
            self._curve_timeouts.append(curve)
        root.addWidget(self._plot_bottom, 1)

    def _build_toolbar(self) -> QHBoxLayout:
        bar = QHBoxLayout()
        bar.setSpacing(8)

        bar.addWidget(QLabel("표시 범위:"))
        self._range_combo = QComboBox()
        for seconds in CHART_WINDOW_CHOICES_S:
            self._range_combo.addItem(f"{seconds}초", seconds)
        self._range_combo.setCurrentText(f"{DEFAULT_CHART_WINDOW_S}초")
        self._range_combo.currentIndexChanged.connect(self._on_range_changed)
        bar.addWidget(self._range_combo)

        self._pause_check = QCheckBox("일시정지")
        self._pause_check.toggled.connect(self._on_pause)
        bar.addWidget(self._pause_check)

        clear_btn = QPushButton("차트 지우기")
        clear_btn.clicked.connect(self.clear)
        bar.addWidget(clear_btn)

        bar.addStretch(1)

        legend = QLabel("State 매핑: NORMAL=0 · WARNING=1 · DEGRADED=2 · SAFE_MODE=3")
        legend.setStyleSheet(f"color:{T.text_dim}; font-size:10px;")
        self._legend_label = legend
        bar.addWidget(legend)
        return bar

    # ------------------------------------------------------------------
    def apply_theme(self) -> None:
        """테마 교체 후 차트 배경/곡선 색을 다시 칠한다.

        pyqtgraph 는 전역 QSS 를 따르지 않아 위젯마다 직접 지정해야 한다.
        """
        legend = getattr(self, "_legend_label", None)
        if legend is not None:
            legend.setStyleSheet(f"color:{T.text_dim}; font-size:10px;")

        notice = getattr(self, "_notice", None)
        if notice is not None:
            notice.setStyleSheet(f"color:{T.text_dim}; font-size:12px;")

        if not PYQTGRAPH_AVAILABLE:
            return

        pg.setConfigOptions(background=T.bg, foreground=T.text)
        for plot in (self._plot_top, self._plot_bottom):
            plot.setBackground(T.bg)
            for axis_name in ("left", "bottom"):
                axis = plot.getAxis(axis_name)
                axis.setPen(T.text_dim)
                axis.setTextPen(T.text)

        self._curve_level.setPen(pg.mkPen(T.state_safe_mode, width=2))
        self._curve_state.setPen(
            pg.mkPen(T.accent, width=2, style=Qt.PenStyle.DashLine)
        )
        self._curve_actuator.setPen(pg.mkPen(T.state_warning, width=2))
        timeout_colors = (T.state_degraded, T.accent, T.state_safe_mode)
        for i, curve in enumerate(self._curve_timeouts):
            curve.setPen(pg.mkPen(timeout_colors[i % len(timeout_colors)], width=1))

    # ------------------------------------------------------------------
    def _on_pause(self, paused: bool) -> None:
        self._paused = paused

    def _on_range_changed(self) -> None:
        value = self._range_combo.currentData()
        if value:
            self._window_s = int(value)
            self._refresh()

    def set_window_seconds(self, seconds: int) -> None:
        """저장된 설정에서 표시 범위를 복원한다."""
        self._window_s = seconds
        idx = self._range_combo.findData(seconds)
        if idx >= 0:
            self._range_combo.setCurrentIndex(idx)

    def window_seconds(self) -> int:
        return self._window_s

    def clear(self) -> None:
        """모든 샘플을 버린다."""
        self._t.clear()
        self._level.clear()
        self._state.clear()
        self._actuator.clear()
        for series in self._timeouts:
            series.clear()
        self._t0 = time.monotonic()
        self._refresh()

    def add_status(self, status: MissionStatus) -> None:
        """새 상태를 샘플로 추가한다. 일시정지 중이면 무시한다."""
        if self._paused:
            return
        now = time.monotonic() - self._t0
        self._t.append(now)
        level = int(status.fault_level)
        self._level.append(max(0, level))
        self._state.append(max(0, status.system_state.numeric))
        self._actuator.append(int(status.actuator_enable))
        for i in range(DEVICE_COUNT):
            self._timeouts[i].append(1 if status.is_timeout(i) else 0)
        self._refresh()

    def _refresh(self) -> None:
        if not PYQTGRAPH_AVAILABLE or not self._t:
            return
        xs = list(self._t)
        self._curve_level.setData(xs, list(self._level))
        self._curve_state.setData(xs, list(self._state))
        self._curve_actuator.setData(xs, list(self._actuator))
        for i, curve in enumerate(self._curve_timeouts):
            # Device 별로 살짝 띄워 겹침을 피한다
            offset = i * 0.06
            curve.setData(xs, [v + offset for v in self._timeouts[i]])

        latest = xs[-1]
        self._plot_top.setXRange(max(0.0, latest - self._window_s), latest + 0.5)
