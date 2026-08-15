# Mission SoC Dashboard

Basys 3 MicroBlaze SoC 실시간 관제용 데스크톱 애플리케이션.

FPGA 의 세 Custom IP (`heartbeat_monitor_ip`, `fault_manager_ip`, `safety_controller_ip`)
가 MicroBlaze 와 AXI UARTLite 를 통해 내보내는 상태 메시지를 PC 에서 수신하고,
시스템 상태·고장 등급·장치별 출력 상태를 실시간으로 표시한다.

---

## 안전 설계 원칙

**이 앱은 안전 판단을 수행하지 않는다.**

고장 판단과 출력 차단은 FPGA 내부의 직접 연결 경로가 담당한다.

```text
heartbeat_monitor_ip
  → fault_manager_ip
    → safety_controller_ip
```

- 앱이 종료되거나 UART 가 끊겨도 FPGA 의 Fault 판단과 SAFE_MODE 전환에는 영향이 없다.
- 앱의 역할은 **모니터링, 명령 전송, 로그 저장** 세 가지뿐이다.
- 수신된 값은 그대로 표시한다. 앱이 계산한 값으로 덮어쓰지 않는다.
- 정책과 수신값이 어긋나면 `POLICY WARNING` 로그만 남기고 값은 건드리지 않는다.
- `Manual Recovery` 성공 여부를 앱이 가정하지 않는다. FPGA 의 `$ACK` 또는
  새로운 `$MISSION` 상태로만 확인한다.

---

## 주요 기능

| 분류 | 기능 |
|---|---|
| 실시간 표시 | System State, Fault Level/Device/Code, Timestamp, Actuator/Control Valid |
| 장치 상태 | Device 0~2 별 Alive / Timeout / Output Enable / Fault 대상 / Fault Count |
| 로그 | 상태·이벤트·명령·오류 통합 Event Log, 필터, CSV 저장 |
| 차트 | Fault Level, System State, Actuator Enable, Device별 Timeout 시계열 |
| 설정 | TIMEOUT0~2, CRITICAL_MASK, PERSIST_LIMIT, RECOVERY_COUNT, DEGRADE_MASK |
| 제어 | Get Status/Config, Apply All Settings, Manual Recovery, Clear IRQ/Heartbeat, Reset Fault |
| 주입 | Device별 Timeout/Error/Critical ON·OFF, Multi Fault·Critical 시연 프리셋 |
| Mock | FPGA 없이 앱 전체를 시험하는 내장 시뮬레이터 |

---

## 화면 구성

```text
┌──────────────────────────────────────────────────────────────┐
│ [상단] COM Port · Baudrate · 연결/해제 · Mock 모드 · 연결 상태 │
│        수신 Bytes / Message / Parse Error / 마지막 수신        │
├────────────────────────────────┬─────────────────────────────┤
│ System State 카드               │ [탭] 설정 · 제어            │
│   상태 · Level · Device · Code  │   설정 레지스터 입력        │
│   Timestamp · Actuator · Valid  │   제어 명령 버튼            │
├────────────────────────────────┤                             │
│ Device 0 │ Device 1 │ Device 2 │ [탭] Fault Injection        │
│  Alive/Timeout/OE/Fault/Count  │   Device별 ON·OFF           │
├────────────────────────────────┤   시연 프리셋               │
│ [탭] Event Log │ 실시간 차트    │ [탭] 로그 · 정보            │
└────────────────────────────────┴─────────────────────────────┘
```

---

## 설치

Python 3.11 이상이 필요하다.

```bash
python -m venv .venv
```

**Windows**

```bash
.venv\Scripts\activate
pip install -r requirements.txt
python app.py
```

**Linux / macOS**

```bash
source .venv/bin/activate
pip install -r requirements.txt
python app.py
```

---

## 실행

```bash
python app.py
```

---

## Mock Mode 사용법

FPGA 가 없어도 모든 기능을 시험할 수 있다.

1. 앱 실행
2. 상단의 **Mock 주기(ms)** 를 설정 (기본 200 ms)
3. **Mock 모드** 버튼 클릭 → 상태가 `Mock 연결됨 (MOCK_CONNECTED)` 으로 바뀐다
4. `$MISSION` 메시지가 주기적으로 들어오며 카드와 차트가 갱신된다

### 시연 순서

```text
1. Mock 모드 연결                    → NORMAL, output_enable=0b111
2. Fault Injection 탭
   Device 0 Timeout 체크             → Level 1 / WARNING
   그대로 두고 몇 초 대기             → Level 2 / DEGRADED (Device 0 만 Disable)
3. Clear All Injection               → Level 0, RECOVERY_COUNT 만큼 뒤 NORMAL 복귀
4. "Device 2 Critical Demo" 버튼     → Level 3 / SAFE_MODE, 모든 출력 차단
5. Clear All Injection               → Level 0 이 되어도 SAFE_MODE 유지 (Latch)
6. 설정·제어 탭 → Manual Recovery    → $ACK 수신 후 NORMAL 복귀
7. "Device 0 + Device 1 Multi Fault" → Level 3 / FAULT_MULTI_DEVICE / Device 3
```

Mock Simulator 는 명세의 다음 정책을 재현한다.

- Fault 우선순위: Critical > Multi-device > Persistent > Temporary > Normal
- `CRITICAL_MASK` 는 Timeout / Error / Critical Fault 모두에 적용
- 같은 장치의 Timeout + Error → `FAULT_ERROR_CODE` 우선
- SAFE_MODE 는 Fault 제거만으로 자동 복구되지 않음
- `DEGRADED + Level 1` 은 `WARNING` 까지만 복귀 (NORMAL 직행 금지)
- `TIMEOUTn`, `PERSIST_LIMIT`, `RECOVERY_COUNT` 의 `0` 은 유효값 `1` 로 간주

---

## 실제 FPGA 연결

### UART 설정

| 항목 | 값 |
|---|---|
| Baudrate | 115200 (기본). AXI UARTLite 설정에 맞춘다 |
| Data bits | 8 |
| Parity | None |
| Stop bits | 1 |
| Flow control | None |
| Timeout | 0.1 초 |
| Encoding | UTF-8 (디코드 실패는 대체 문자 처리) |

> Vivado 의 AXI UARTLite 기본값이 9600 인 경우가 있다.
> Block Design 의 UARTLite 설정과 앱의 Baudrate 를 반드시 일치시켜야 한다.

### 연결 절차

1. 보드를 USB 로 연결하고 비트스트림을 다운로드
2. Vitis 애플리케이션 실행
3. 앱에서 **새로고침** → 포트 선택 (Linux 는 보통 `/dev/ttyUSB1`, Windows 는 `COM*`)
4. Baudrate 선택 후 **연결**
5. `$MISSION` 이 들어오면 정상. `Boot complete` 같은 디버그 문자열도 Raw Log 에 남는다

### Linux 권한

```bash
sudo usermod -a -G dialout $USER    # 재로그인 필요
```

---

## 수신 Protocol (FPGA → Python)

자세한 규격은 [README_PROTOCOL.md](README_PROTOCOL.md) 참고.

```text
$MISSION,timestamp,state,fault_level,fault_device,fault_code,alive,timeout,output_enable,actuator_enable
$EVENT,timestamp,event_type,arg0,arg1,arg2
$ACK,command,arg0,arg1
$ERR,error_code,description
```

`$` 로 시작하지 않는 문자열은 디버그 출력으로 보고 Raw Log 에 기록한다.
잘못된 메시지를 받아도 앱은 종료되지 않는다.

---

## 송신 Command (Python → FPGA)

```text
GET,STATUS
GET,CONFIG

SET,TIMEOUT,<device>,<value>
SET,CRITICAL_MASK,<value>
SET,PERSIST_LIMIT,<value>
SET,RECOVERY_COUNT,<value>
SET,DEGRADE_MASK,<value>

CMD,MANUAL_RESET
CMD,CLEAR_IRQ
CMD,CLEAR_HEARTBEAT
CMD,RESET_FAULT

INJECT,ERROR,<device>,ON|OFF
INJECT,CRITICAL,<device>,ON|OFF
INJECT,TIMEOUT,<device>,ON|OFF
INJECT,CLEAR,ALL
```

모든 명령은 `\n` 으로 끝난다.

`INJECT` 계열은 향후 MicroBlaze 또는 AXI GPIO 가 지원할 확장 기능이다.
현재 펌웨어가 지원하지 않으면 `$ERR,UNKNOWN_COMMAND` 가 돌아오고,
앱은 상태바에 "지원하지 않는 명령" 이라고 표시한다.

---

## CSV 로그 형식

파일명 예: `mission_log_20260729_001530.csv`

```text
received_at, timestamp_ms, system_state, fault_level, fault_device, fault_code,
alive_mask, timeout_mask, output_enable_mask, actuator_enable,
control_valid, state_timer, fault_count0, fault_count1, fault_count2, raw_line
```

- 기본 저장 폴더: `~/mission_soc_logs/`
- **로그 · 정보** 탭에서 폴더 변경, 자동 기록, 세션 Export 가능
- Event Log 는 별도 CSV 로 Export
- 로그 쓰기가 실패해도 Serial 수신과 GUI 는 계속 동작한다

---

## 설정 저장

`~/.mission_soc_dashboard/settings.json`

저장 항목: 마지막 COM Port / Baudrate, 창 크기·위치, 로그 폴더, 자동 로그 여부,
차트 시간 범위, 최대 로그 행 수, 설정 레지스터 값, Mock 주기.

설정 파일이 손상돼도 기본값으로 실행된다.

---

## 테스트

```bash
pytest -v
```

실제 Serial 포트나 FPGA 없이 동작한다.

| 파일 | 내용 |
|---|---|
| `test_protocol.py` | 정상/비정상 메시지 파싱, 스트림 버퍼 조립 |
| `test_command_builder.py` | 명령 생성, 범위 검증, 줄바꿈 |
| `test_state_mapper.py` | Bit Mask 해석, 표시 문자열, 정책 검증 |
| `test_mock_device.py` | Fault 정책, Safety FSM, SAFE_MODE Latch, Recovery |

---

## 문제 해결

| 증상 | 원인과 조치 |
|---|---|
| 포트 목록이 비어 있음 | pyserial 미설치 또는 권한 부족. Linux 는 `dialout` 그룹 확인 |
| 연결은 되는데 데이터가 없음 | Baudrate 불일치. UARTLite 설정과 맞춘다 |
| Parse Error 가 계속 증가 | Baudrate 불일치이거나 필드 순서가 다름. Raw Log 에서 원문 확인 |
| 글자가 깨져 보임 | UTF-8 이 아닌 데이터. 대체 문자로 표시되며 앱은 죽지 않는다 |
| `POLICY WARNING` 이 뜸 | 수신값이 명세 정책과 어긋남. FPGA 쪽 확인이 필요하다 |
| 차트가 안 보임 | pyqtgraph 미설치. `pip install pyqtgraph` |
| 포트가 사용 중이라고 나옴 | 다른 터미널 프로그램이 점유 중. 닫고 재시도 |
| 장치를 뽑았는데 앱이 살아 있음 | 정상 동작. 오류 로그를 남기고 연결만 해제된다 |

---

## 프로젝트 구조

```text
mission_soc_dashboard/
├─ app.py                     실행 진입점
├─ requirements.txt
├─ pyproject.toml
├─ README.md
├─ README_PROTOCOL.md         MicroBlaze 개발자용 프로토콜 규격
├─ mission_dashboard/
│  ├─ constants.py            상수 (명세 값 단일 출처)
│  ├─ models.py               dataclass / Enum
│  ├─ protocol.py             수신 Parser
│  ├─ command_builder.py      송신 명령 생성
│  ├─ state_mapper.py         표시 변환 · 정책 검증
│  ├─ serial_worker.py        Serial / Mock Worker (QThread)
│  ├─ mock_device.py          FPGA 시뮬레이터
│  ├─ log_manager.py          CSV 기록
│  ├─ settings_manager.py     JSON 설정
│  ├─ main_window.py          GUI 조립
│  └─ widgets/                개별 위젯
└─ tests/                     pytest
```

계층 분리 원칙: GUI · Serial · Parser · 명령 생성 · 데이터 모델 · 로그 · Mock 을
서로 다른 모듈로 나눈다. Parser 와 Mock 은 Qt 에 의존하지 않아 단독 테스트가 가능하다.

---

## 참고 문서

| 문서 | 내용 |
|---|---|
| `00_TEAM_COMMON_SPEC_*.md` | 상태/코드 인코딩, 레지스터 맵, Fault 정책, Safety FSM |
| `01_MEMBER_A_HEARTBEAT_MONITOR.md` | Alive/Timeout 의미 |
| `02_MEMBER_B_FAULT_MANAGER.md` | Fault Level/Device/Code 결정 규칙 |
| `03_MEMBER_C_SAFETY_CONTROLLER_*.md` | 출력 정책, Recovery Count, UART 형식 |
| `04_TEAM_SHARED_INTEGRATION_CHECKLIST_*.md` | 권장 초기값, 통합 검증 항목 |
