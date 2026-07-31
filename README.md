# Mission SoC

Basys 3와 MicroBlaze RISC-V를 사용하는 미션 안전 SoC 프로젝트입니다.

FPGA 내부의 안전 경로는 다음 세 Custom IP로 구성됩니다.

```text
heartbeat_monitor
  -> fault_manager
    -> safety_controller
```

Python 대시보드는 UART를 통한 모니터링, 명령 전송, CSV 로그 저장만 담당하며
안전 판단과 출력 차단은 FPGA 내부에서 수행합니다.

## 개발 환경

- AMD Vivado 2024.2
- AMD Vitis Unified IDE 2024.2
- Python 3.11 이상
- Digilent Basys 3
- UART 9600 baud, 8-N-1

## 저장소 구성

```text
SOC_Pr/                    Vivado 프로젝트와 Custom IP
SOC_Pr_Vitis/              Vitis 플랫폼 정의와 통합 펌웨어 소스
mission_soc_dashboard/     PySide6 기반 Windows/Linux 대시보드
rtl/                       RTL 정본/참조 소스
sim/                       단위 및 통합 Testbench
verification/              상세 검증 문서와 추가 Testbench
docs/                      설계 및 구현 문서
00_*.md ~ 06_*.md          팀 명세, 통합 체크리스트, 보드/영상 시나리오
```

## Windows에서 Python 앱 실행

```powershell
git clone https://github.com/LDdd130/SOC_Project.git
cd SOC_Project\mission_soc_dashboard

py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements.txt
python app.py
```

실제 보드에 연결할 때 앱에서 baudrate를 반드시 `9600`으로 선택합니다.

## Windows에서 Vivado 프로젝트 열기

Vivado 2024.2에서 다음 파일을 엽니다.

```text
SOC_Pr/soc_project/soc_project.xpr
```

클론 직후 생성물이 없다는 메시지가 나오면 Block Design에서
`Generate Output Products`를 실행합니다. HDL wrapper는 저장소에 포함되어
있지만, 필요한 경우 `Create HDL Wrapper`로 다시 생성할 수 있습니다.

활성 Block Design, XDC와 시뮬레이션 소스는 모두
`SOC_Pr/soc_project/soc_project.srcs/`에 포함되어 있습니다.

## Windows에서 Vitis 프로젝트 구성

Linux에서 생성된 Vitis `build`, `_ide`, `export`, BSP 산출물은 운영체제와
절대경로에 종속되므로 저장소에 포함하지 않습니다.

Vitis 2024.2에서 다음 XSA를 사용해 `mission_soc` 플랫폼을 다시 생성하거나
기존 플랫폼의 hardware specification을 이 파일로 연결합니다.

```text
SOC_Pr_Vitis/mission_soc_wrapper.xsa
```

통합 애플리케이션 소스는 다음 위치에 있습니다.

```text
SOC_Pr_Vitis/soc_prj/src/
```

`SOC_Pr_Vitis/mission_soc/vitis-comp.json`과
`SOC_Pr_Vitis/soc_prj/vitis-comp.json`은 기존 플랫폼/애플리케이션 구성
참조용으로 포함되어 있습니다.

## 주요 검증 결과

- Vivado routed timing: WNS `+0.963 ns`, WHS `+0.029 ns`
- RTL 단위/AXI/통합 Testbench: 총 4,533 checks, 0 fail
- Python 테스트: 202 passed
- 보드 로그에서 Timeout, IRQ Pending/W1C, SAFE_MODE latch,
  Manual Recovery 승인/거부 및 최종 NORMAL 복귀 확인

세부 명세와 시연 절차는 루트의 `00`~`06` 문서를 참고하십시오.
