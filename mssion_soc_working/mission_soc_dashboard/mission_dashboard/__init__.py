"""Mission SoC Dashboard 패키지.

Basys 3 MicroBlaze SoC 의 UART 상태 메시지를 수신해 표시하는 관제 앱.

계층:
    models / constants   순수 데이터
    protocol             수신 Parser
    command_builder      송신 명령 생성
    state_mapper         표시 변환
    serial_worker        Serial / Mock Worker (QThread)
    mock_device          FPGA 없는 시뮬레이터
    log_manager          CSV 기록
    settings_manager     JSON 설정
    widgets / main_window  GUI
"""

from .constants import APP_NAME, APP_VERSION

__all__ = ["APP_NAME", "APP_VERSION"]
