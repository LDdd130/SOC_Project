# 임무컴퓨터 SoC — 3인 팀 공동 통합 체크리스트 (Recovery 정책 확정본)

이 문서는 사용자 본인을 포함한 **총 3명**이 작업 결과를 합칠 때 사용한다.

```text
A = heartbeat_monitor_ip
B = fault_manager_ip
C = safety_controller_ip
```

통합 전담 네 번째 인원은 없다. Vivado Block Design, AXI/IRQ 연결, Vitis와 보드 검증은 세 명이 함께 수행한다.

확정 Recovery 정책:

```text
DEGRADED + Level 0 지속 → NORMAL
DEGRADED + Level 1 지속 → WARNING
```

`fault_level=1` 상태에서 `NORMAL`로 복귀하는 결과는 통합 실패로 판정한다.

---

## 구현 범위 (2026-07-30 확정)

**시연·검증은 전부 PC 대시보드(UART 9600) 경로로 한다.**

| 항목 | 상태 |
|---|---|
| 세 Custom IP + MicroBlaze + AXI INTC | 구현 완료 |
| UART 프로토콜 (`GET`/`SET`/`CMD`/`INJECT`) | 구현 완료 |
| Fault Injection (`axi_gpio_0` CH1/CH2 = error/critical, Heartbeat 중단 = timeout) | 구현 완료 |
| LED `LD0~LD15` 상태 표시 | 구현 완료 (매핑표는 03 문서 12.2) |
| 물리 SW0~SW3 / btnU / btnD 입력 | **미구현** — BD·XDC 미배선, `axi_gpio_0/1` 둘 다 출력 전용 |
| FND / RGB LED 출력 | **미구현** |

BD 최상위 외부 포트는 `sys_clock`, `reset`(btnC), `usb_uart`, `led[15:0]` 4개뿐이다.
따라서 이 문서에서 물리 SW/BTN·FND·RGB 를 전제로 한 항목은 **범위 밖**으로 표시했고,
같은 기능을 UART 명령으로 검증하는 대체 항목을 그 자리에 두었다
(1.1 / 3장 38a / 5.1 참고). 근거는 00 공통명세 12.3.

단계별 조작 순서와 기대 로그는 `05_BOARD_INTEGRATION_TEST_SCENARIO.md` 에 있다.

---


## 0. 공동 통합 역할 배분

| 작업 | 주 진행 | 검토·지원 |
|---|---|---|
| Custom IP Packaging | 각 IP 담당자 | 나머지 2명 |
| Vivado Block Design | 3명 공동 | 3명 공동 |
| Address Editor | 1명이 화면 조작 | 2명이 Offset 검토 |
| AXI INTC/xlconcat | 1명이 연결 | 각 IP 담당자가 IRQ 검증 |
| Vitis 초기화 코드 | 공동 | 각 IP 담당자가 본인 Driver 함수 작성 |
| ISR | 공동 | 각 IP 담당자가 IRQ_STATUS/W1C 검증 |
| 보드 I/O (LED만) | C가 초안 | A·B가 입력 및 Fault 시나리오 검토 |
| UART Protocol | 공동 확정 (03_MEMBER_C 11장) | 이후 변경 금지 |
| PC 대시보드 앱 | 공동 | 03_MEMBER_C 11장 규격만 따름 |
| 최종 Test | 3명 공동 | 시나리오별 담당 교대 |
| PPT/발표 | 각자 본인 IP | 전체 흐름은 공동 작성 |

---

## 1. 인터페이스 Freeze 확인

- [ ] IP 이름이 공통 명세와 동일
- [ ] 상태값 인코딩 동일
- [ ] Fault Code 동일
- [ ] Device ID 동일
- [ ] 레지스터 Offset 동일
- [ ] IRQ Level 방식
- [ ] W1C/W1P 동작 동일
- [ ] Clock 100MHz
- [ ] Reset polarity 확인
- [ ] 공통 1클럭 Pulse `eval_tick`을 B/C의 같은 이름 포트에 연결
- [ ] B/C가 모두 `eval_tick` 포트명만 사용
- [ ] 공통 `eval_tick_generator.v` Module Reference가 100MHz에서 1ms 주기의 1클럭 Pulse 생성
- [ ] `fault_valid`가 출력 유효 Level이며 Count Tick으로 사용되지 않음
- [ ] Heartbeat Core의 `CTRL.bit0`이 `enable` 포트에 연결
- [ ] `device_enable=3'b111` 고정, Safety `output_enable`과 독립
- [ ] `device_enable=0`에서 Counter/Timeout/Event/Alive가 모두 0
- [ ] `CRITICAL_MASK`가 Timeout/Error/Critical Fault 모두에 적용
- [ ] DEGRADED 단일 Fault는 실제 `fault_device`만 Disable
- [ ] `fault_device=3`인 DEGRADED에서만 `DEGRADE_MASK` 적용
- [ ] `RECOVERY_COUNT < PERSIST_LIMIT` 설정 확인
- [ ] `DEGRADED + Level 1 → WARNING`, `DEGRADED + Level 0 → NORMAL` 정책 확인
- [ ] Level 1 상태에서 NORMAL 출력 경로가 없는지 확인
- [ ] 각 IP `ENABLE=0` 출력이 공통 안전 정책과 일치

권장 초기값:

```text
device_enable  = 3'b111
CRITICAL_MASK  = 3'b100
PERSIST_LIMIT  = 5
RECOVERY_COUNT = 2
DEGRADE_MASK   = 3'b001
```

`TIMEOUTn=0`, `PERSIST_LIMIT=0`, `RECOVERY_COUNT=0`은 각각 유효값 1로 간주한다.

### 1.1 직접 연결 Freeze

```text
heartbeat_async
→ heartbeat_monitor_ip
→ timeout
→ fault_manager_ip

error_flag ─────────────→ fault_manager_ip
critical_fault ─────────→ fault_manager_ip

fault_level/device/code/valid
→ safety_controller_ip

공통 eval_tick
├─ fault_manager_ip.eval_tick
└─ safety_controller_ip.eval_tick

alive
→ LED / MicroBlaze 상태 표시
```

금지 연결:

```text
heartbeat_monitor_ip.alive → fault_manager_ip
safety_controller_ip.output_enable → heartbeat_monitor_ip.device_enable
```

MicroBlaze가 AXI GPIO로 구동하는 경로 (PC 대시보드 `INJECT` 명령의 실체):

```text
axi_gpio_0 CH1 → error_flag[2:0]      → fault_manager_ip
axi_gpio_0 CH2 → critical_fault[2:0]  → fault_manager_ip
axi_gpio_1 CH1 → heartbeat_async[2:0] → heartbeat_monitor_ip
```

**Timeout은 GPIO로 직접 주입하지 않는다.** `INJECT,TIMEOUT,<dev>,ON` 은 해당 채널의
Heartbeat 생성을 멈추는 것이고, `TIMEOUTn` 초과 판정은 `heartbeat_monitor_ip`가 한다.
이 규칙은 A의 IP 통합 이후 변경 금지다.

- [ ] `INJECT,TIMEOUT` 이 GPIO Timeout 직결이 아니라 Heartbeat 중단으로 구현됨
- [ ] Heartbeat 생성이 UART 송신 블로킹 중에도 끊기지 않음
- [x] ~~`error_flag`/`critical_fault`가 GPIO와 보드 SW 양쪽에서 들어와도 결과가 동일~~
      → **범위 밖.** 이번 빌드에 보드 SW 경로가 없다 (00 공통명세 12.3).
      `axi_gpio_0` 경로가 유일한 주입 수단이다.

### 1.2 UART Protocol Freeze

규격 본문은 **03_MEMBER_C 11장**이다. PC 앱은 `mission_soc_dashboard/`,
MicroBlaze 구현은 `SOC_Pr_Vitis/soc_prj/src/uart_proto.c` 다.

- [ ] Baudrate **9600 8N1** 로 고정. Block Design·펌웨어·PC 앱 3곳이 모두 9600
- [ ] 접두어 **5종** 확정: `$MISSION` `$EVENT` `$ACK` `$ERR` **`$IRQ`**
- [ ] `$MISSION` 필수 9필드 순서 고정
      (`timestamp,state,fault_level,fault_device,fault_code,alive,timeout,output_enable,actuator_enable`)
- [ ] `$MISSION` 선택 5필드 순서 고정 (`control_valid,state_timer,fault_count0~2`)
- [ ] `$MISSION` 의 `state_timer` 는 **ms 단위** (펌웨어가 clock count → ms 환산)
- [ ] `$IRQ` 4필드 순서 고정 (`en_mask,hb_status,fm_status,sc_status`)
- [ ] 마스크 3종은 하위 3비트만 사용
- [ ] `$EVENT` 4종 확정: `FAULT_CHANGE` `STATE_CHANGE` `HEARTBEAT_TIMEOUT` `MANUAL_RESET`
- [ ] `$ERR` 코드 4종 확정: `UNKNOWN_COMMAND` `INVALID_VALUE` `FAULT_ACTIVE` `FAULT_INVALID`
- [ ] PC → FPGA 명령 이름 확정: `GET,*` `SET,*` `CMD,*` `INJECT,*`
- [ ] `GET,IRQ` / `SET,IRQ_EN` 포함 (03_MEMBER_C 11.4 / 11.5-1)
- [ ] `GET,CONFIG` 응답이 `SET,IRQ_EN` 포함 **8줄**
- [ ] `$ACK,INJECT,*` 에 `ON`/`OFF` 를 되돌려 보내지 않음 (`$ACK,INJECT,ERROR,1` 형태)
- [ ] `INJECT,CLEAR,ALL` 응답이 `$ACK,INJECT,CLEAR`
- [ ] 모든 수신 명령이 `$ACK` 또는 `$ERR` 로 응답됨 (무응답 없음)
- [ ] `$` 로 시작하지 않는 줄은 디버그 문자열로만 취급됨
- [ ] 줄 종료 `\r\n` 송신 / `\n` `\r\n` 모두 수신 허용
- [ ] 줄 길이 한계: PC 수신 4096 B / **FPGA 수신 96 B** (초과 시 `$ERR,INVALID_VALUE,LINE_TOO_LONG`)
- [ ] ISR 안에서 UART 출력 없음
- [ ] `SET,*` 이 12.2 초기화와 같은 레지스터·같은 0→1 치환 규칙을 씀
- [ ] `PERSIST_LIMIT` 256 이상이 `$ERR,INVALID_VALUE` 로 거부됨

---

## 2. 파일 제출 확인

### heartbeat_monitor 담당

- [ ] Core RTL
- [ ] AXI RTL/IP package
- [ ] Testbench
- [ ] 파형
- [ ] Register Map
- [ ] Integration Note

### fault_manager 담당

- [ ] Core RTL
- [ ] AXI RTL/IP package
- [ ] Testbench
- [ ] Fault Policy Table
- [ ] 파형
- [ ] Integration Note

### safety_controller 담당

- [ ] Core RTL
- [ ] AXI RTL/IP package
- [ ] Testbench
- [ ] Block Design
- [ ] XSA
- [ ] Vitis Application
- [ ] ISR
- [ ] UART Protocol 규격 (03_MEMBER_C 11장)
- [ ] Board I/O Map (LD0~LD15 매핑. SW/BTN/FND/RGB 는 미구현 — 03 문서 12.2)

### 공동 통합 RTL

- [ ] `eval_tick_generator.v`
- [ ] `tb_eval_tick_generator.v`
- [ ] 100MHz 입력에서 기본 1ms 주기, 1클럭 Pulse 확인
- [ ] Reset 동안 `eval_tick=0`, 해제 후 100,000클럭 뒤 첫 Pulse 확인

### MicroBlaze 펌웨어 (공동)

```text
SOC_Pr_Vitis/soc_prj/src/
  main.c              부팅 13단계 + 메인 루프 + $EVENT 변화 감지
  uart_proto.c/.h     프로토콜 송수신 (03_MEMBER_C 11장 구현)
  hb_gen.c/.h         Heartbeat 생성 (AXI GPIO)
  hb_regs.c           heartbeat_monitor 드라이버   (A 담당자 검증)
  fm_regs.c           fault_manager 드라이버       (B 담당자 검증)
  sc_regs.c           safety_controller 드라이버   (C 담당자 검증)
  mission_intr.c/.h   AXI INTC 및 ISR
  mission_ip_regs.h   Offset/설정 기본값
```

- [ ] `mission_ip_regs.h` 의 Offset이 00 공통명세 9장과 일치
- [ ] 각 IP 담당자가 본인 `*_regs.c` 를 검토
- [ ] `PROTO_SendMission()` 필드 순서가 03_MEMBER_C 11.1과 일치

### PC 대시보드 (공동)

```text
mission_soc_dashboard/
  README_PROTOCOL.md  프로토콜 규격 원본 (03_MEMBER_C 11장과 동일 내용)
  app.py              실행 진입점
  mission_dashboard/  protocol.py / command_builder.py / models.py / widgets
  tests/              파서·명령 생성 단위 테스트
```

- [ ] `protocol.py` 파싱 결과가 실제 보드 출력과 일치
- [ ] `command_builder.py` 명령 문자열이 `uart_proto.c` 파서와 일치
- [ ] 단위 테스트 통과
- [ ] Mock Simulator 모드로 보드 없이 화면 검증 가능

---

## 3. 단계별 통합 Test

| 단계 | 테스트 | 통과 기준 |
|---:|---|---|
| 1 | 모든 AXI Register Read/Write | 값 일치 |
| 2 | W1P | 정확히 1 Clock Pulse |
| 3 | W1C | 지정 비트만 Clear |
| 4 | 각 IP IRQ | Clear 전까지 High |
| 5 | Heartbeat IRQ_STATUS W1C | Pending만 Clear, Timeout 유지 |
| 6 | Heartbeat CLEAR_ALL | Counter/Timeout Clear, Pending은 별도 W1C |
| 7 | 정상 Heartbeat | NORMAL |
| 8 | Device 0 일시 Timeout | WARNING 정책 일치 |
| 9 | Device 0 Timeout 지속 | DEGRADED, Device 0만 Disable |
| 10 | Device 1 단일 Fault 지속 | DEGRADED, Device 1만 Disable |
| 11 | DEGRADED + `fault_device=3` | DEGRADE_MASK 적용 |
| 12 | DEGRADED + Level 1을 Recovery Count 동안 유지 | WARNING 복귀 |
| 13 | DEGRADED + Level 0을 Recovery Count 동안 유지 | NORMAL 복귀 |
| 14 | DEGRADED + Level 1 상태 | NORMAL로 직접 복귀하지 않음 |
| 15 | Device 1 Error | 일시 WARNING, 지속 DEGRADED |
| 16 | Device 2 Timeout | eval_tick 대기 없이 SAFE_MODE |
| 17 | Device 2 Error | eval_tick 대기 없이 SAFE_MODE |
| 18 | Device 2 Critical | eval_tick 대기 없이 SAFE_MODE |
| 19 | Device 0+1 동시 Fault | eval_tick 대기 없이 SAFE_MODE/Multi |
| 20 | 동일 장치 Timeout+Error | ERROR_CODE 우선 |
| 21 | SAFE Fault 제거 | SAFE 유지 |
| 22 | Manual Reset | `fault_valid=1`이고 Level 0일 때만 NORMAL |
| 23 | 세 IP Disable | 공통 명세의 안전 출력 |
| 24 | UART `$MISSION` | 필드 순서·개수 일치, 마스크 하위 3비트 |
| 25 | LED `LD0~LD15` | 03 문서 12.2 매핑표와 일치 (FND/RGB 는 미구현, 범위 밖) |

Critical 입력부터 출력 차단까지 `외부 입력 동기화 + Fault Manager 1Clock + Safety Controller 1Clock` 목표를 파형으로 측정한다.

**8·12·15번의 `WARNING` 은 RTL Testbench에서 `eval_tick` 단위로 검증한다.**
보드 + UART 경로에서도 기본 `PERSIST_LIMIT=5`(Level 1 이 5 ms 유지)에서
**`$EVENT,STATE_CHANGE,WARNING` 은 정상 기록된다** — ISR Snapshot Ring 이 전이 순간
값을 잡기 때문이다 (00 공통명세 10.1). 다만 500 ms 주기의 `$MISSION` 으로 갱신되는
PC 앱 큰 글씨에는 뜨지 않으므로, **판정은 Event Log 로 한다.**

### 3.1 PC 대시보드 연동 Test

`mission_soc_dashboard` 앱을 연결하고 진행한다. 9600 8N1.

| 단계 | 조작 | 통과 기준 |
|---:|---|---|
| 26 | 앱 `연결` | 상태 `CONNECTED`, 부팅 로그 마지막 줄 `Boot complete` |
| 27 | `$MISSION` 수신 | 500 ms 주기로 계속 갱신. `마지막 수신` 시간이 증가 |
| 28 | `GET,CONFIG` | `$ACK,GET,CONFIG` + 설정 **8줄**(`SET,IRQ_EN` 포함)이 6장 부팅값과 일치 |
| 29 | `SET,PERSIST_LIMIT,255` | `$ACK,SET,PERSIST_LIMIT,255`. 256 입력 시 `$ERR,INVALID_VALUE` |
| 30 | Device 1 `Error` ON | Event Log 에 `STATE_CHANGE,WARNING` → `STATE_CHANGE,DEGRADED` 두 줄이 순서대로 |
| 31 | Device 1 `Error` OFF | `STATE_CHANGE,NORMAL`, `output_enable` 이 `0b111` 복귀 |
| 32 | Device 0 `Timeout` ON | 약 300 ms 뒤 `HEARTBEAT_TIMEOUT,0`, `alive` bit0 = 0 |
| 33 | Device 2 `Critical` ON | 즉시 Level 3 / `FAULT_CRITICAL`, `output_enable=0b000`, `actuator=0` |
| 34 | Critical OFF | Level 0 으로 내려가도 `SAFE_MODE` 유지 (자동 복귀 없음) |
| 35 | Fault 남긴 채 `Manual Recovery` | `$ERR,MANUAL_RESET,FAULT_ACTIVE`, 상태 유지 |
| 36 | `Clear All Injection` 후 `Manual Recovery` | `$ACK,CMD,MANUAL_RESET` → `STATE_CHANGE,NORMAL` |
| 37 | 지원하지 않는 명령 수신 | `$ERR,UNKNOWN_COMMAND` 로 응답. 보드가 멈추지 않음 |
| ~~38~~ | ~~보드 SW/BTN 조작~~ | **범위 밖** — 물리 SW/BTN 미배선 (00 공통명세 12.3). 대체 항목은 아래 38a |
| 38a | `CMD,RESET_FAULT` 거부/승인 | Fault 있을 때 `$ERR,RESET_FAULT,FAULT_ACTIVE`, 없을 때 `$ACK,CMD,RESET_FAULT` |
| 39 | Event Log `CSV 저장` | 상태 전이 순서가 파일로 남음 |

38번을 뺀 자리에 38a를 넣은 이유: 원래 38번은 "물리 버튼과 UART 명령이 같은
결과를 내는가"를 보는 **경로 등가성** 항목이다. 물리 경로가 없으면 등가성 자체가
성립하지 않으므로, 대신 아직 검증되지 않았던 UART 명령(`RESET_FAULT`)의
승인·거부 분기를 채운다. 단계별 조작 순서는 `05_BOARD_INTEGRATION_TEST_SCENARIO.md` 참고.

30번 `WARNING` 은 **단일 비Critical 장치** 에서만 나온다. Device 2 Fault와
2개 이상 동시 Fault는 우선순위 1·2에 걸려 곧바로 Level 3 이므로 `WARNING` 이 없다.

---

## 4. 최종 발표용 최소 시연

**시작 전 필수**: PC 대시보드 연결(**Baudrate 9600 확인**) 후 `SET,PERSIST_LIMIT,255` 를 먼저 보낸다.

이유는 두 가지다.
① 이 단계 자체가 `SET,*` 8개 명령과 `설정 전체 전송` 기능의 테스트다.
② 기본값 5는 `WARNING` 구간이 5 ms 라 3번·6번 항목이 **PC 앱 큰 글씨에** 나타나지 않는다.
255로 올리면 255 ms 유지되어 화면에도 잡힐 확률이 생긴다.

**Event Log 에 남는 것 자체는 기본값 5에서도 정상이다** (00 공통명세 10.1 —
ISR Snapshot Ring). 상태 전이의 증거는 0.5초 주기의 `$MISSION` 이 아니라
**`$EVENT` Event Log** 다.

1. 전원 ON → `NORMAL`
2. Device 0 Heartbeat 중단
3. 일시 오류 구간에서 `WARNING`
4. 오류 지속 후 `DEGRADED`
5. Device 0 출력만 차단
6. 별도의 Level 1 조건을 유지하여 Recovery Count 충족 → `WARNING`
7. 모든 Fault를 제거하고 Level 0으로 Recovery Count 충족 → `NORMAL`
8. Device 2 Critical Fault
9. 확정된 Clock 지연 안에 `SAFE_MODE`, `ACTUATOR_ENABLE=0`
10. Critical 해제 후에도 SAFE 유지
11. `fault_valid=1`, Level 0 확인 후 Manual Recovery → `NORMAL`
12. UART 로그에서 상태 전이 순서 확인

권장 시연 복귀 순서:

```text
DEGRADED → WARNING → NORMAL
```

단, Fault Level이 2에서 바로 0으로 내려가고 Level 0이 Recovery Count 동안 유지되면 `DEGRADED → NORMAL` 직접 복귀도 허용한다.

동일 Fault가 완전히 제거되면 Fault Manager는 다음 판정 클럭에 Level 0이 되므로 `DEGRADED → NORMAL`이 더 자연스러운 결과일 수 있다. `DEGRADED → WARNING → NORMAL`을 시연하려면 Level 2 원인을 제거한 뒤 별도의 일시적 Level 1 Fault를 유지한다.

---

## 5. 외부 입력과 IRQ 종단 검증

### 5.1 외부 입력

> **이번 빌드 범위 밖.** 물리 SW/BTN이 BD·XDC에 배선되어 있지 않고
> `axi_gpio_0` / `axi_gpio_1` 은 둘 다 출력 전용이라 보드 스위치를 읽지 못한다
> (00 공통명세 12.3). 아래 항목은 나중에 물리 I/O를 붙일 때 채운다.

- [ ] `SW1/SW2/SW3`에 2FF Synchronizer 적용 *(범위 밖)*
- [ ] 기계식 입력은 필요 시 Debounce 적용 *(범위 밖)*
- [ ] `BTN_U`가 AXI GPIO 또는 동기화/One-shot을 거쳐 MicroBlaze에 전달 *(범위 밖)*
- [ ] `BTN_D`가 세 IP의 `IRQ_STATUS`를 각각 W1C *(범위 밖)*
- [ ] `CMD,MANUAL_RESET` 이 `BTN_U` 와 동일 결과 *(범위 밖 — 비교 대상 없음)*
- [ ] `CMD,CLEAR_IRQ` 가 `BTN_D` 와 동일 결과 *(범위 밖 — 비교 대상 없음)*
- [ ] `INJECT,ERROR/CRITICAL` 이 `SW1/SW2/SW3` 와 동일 결과 *(범위 밖 — 비교 대상 없음)*

**이번 빌드에서 실제로 검증하는 항목** (UART 경로. 위 항목을 대체한다)

- [ ] `CMD,MANUAL_RESET` 이 `CTRL.MANUAL_RESET` W1P 를 실행
- [ ] `CMD,MANUAL_RESET` 이 `fault_valid=1 && fault_level=0` 이 아니면
      `$ERR,MANUAL_RESET,FAULT_ACTIVE` 로 거부
- [ ] `CMD,CLEAR_IRQ` 가 세 IP의 `IRQ_STATUS`를 각각 W1C
- [ ] `CMD,CLEAR_IRQ` 가 Timeout/Fault 상태 자체를 직접 Clear하지 않음
      (`$MISSION` 의 `timeout` / `fault_level` 이 그대로)
- [ ] `INJECT,ERROR/CRITICAL` 이 `axi_gpio_0` CH1/CH2 로 해당 비트만 구동

### 5.2 IRQ 전체 경로

각 Custom IP마다 다음을 확인한다.

```text
IRQ_STATUS Set
→ Custom IP irq High
→ AXI INTC Pending
→ XIntc Handler 실행
→ Custom IP IRQ_STATUS W1C
→ AXI INTC 처리 완료
→ Custom IP irq Low
```

- [ ] Heartbeat/Fault/Safety IRQ를 각각 단독 검증
- [ ] Fault Manager와 Safety Controller IRQ 동시 발생 시 두 ISR 모두 실행
- [ ] Fault Manager IRQ는 Level/Device/Code 중 하나가 변할 때 Set
- [ ] Safety Controller IRQ는 System State가 변할 때 Set
- [ ] W1C 전까지 Custom IP IRQ가 Level High 유지

**xlconcat 연결 순서 = XIntc 인터럽트 ID (8장 변경 금지 대상)**

| xlconcat 포트 | 연결 | XIntc ID | 펌웨어 매크로 |
|---|---|---:|---|
| `In0` | `axi_uartlite_0/interrupt` | 0 | `INTR_ID_UART` (이번 빌드 미사용) |
| `In1` | `fault_manager_ip_0/irq` | 1 | `INTR_ID_FM` |
| `In2` | `myip_heartbeat_monit_0/irq` | 2 | `INTR_ID_HB` |
| `In3` | `safety_controller_0/irq` | 3 | `INTR_ID_SC` |

정의 위치: `SOC_Pr_Vitis/soc_prj/src/mission_intr.h`

**W1C 동작 증명 절차** — 평상시 ISR 이 µs 안에 W1C 해 버려 Pending 이 항상 0 이므로
`$ACK,CMD,CLEAR_IRQ` 만으로는 증거가 되지 않는다. `IRQ_STATUS` 의 Set 은 `IRQ_EN` 과
무관하다는 점을 이용한다 (`assign irq = reg_irq_status & reg_irq_en;`).

- [ ] `SET,IRQ_EN,0` → 고장 주입 → `GET,IRQ` 로 Pending 래치 확인 (`$IRQ,0x00,0x00,0x01,0x01`)
- [ ] `CMD,CLEAR_IRQ` → `GET,IRQ` 로 0 확인 (`$IRQ,0x00,0x00,0x00,0x00`)
- [ ] 앞뒤 `$MISSION` 의 state/level/oe 가 동일 (Pending 만 지웠다는 증거)
- [ ] **검증 후 `SET,IRQ_EN,0x07` 로 원복** (꺼 둔 동안 ISR 이 안 돌아 짧은 전이를 놓친다)

절차 상세는 `05_BOARD_INTEGRATION_TEST_SCENARIO.md` 15~15-7 단계.

---

## 6. MicroBlaze 부팅 순서

- [ ] 1. 세 Custom IP `ENABLE=0`
- [ ] 2. 세 Custom IP `IRQ_EN=0`
- [ ] 3. `TIMEOUT0~2` 설정
- [ ] 4. `CRITICAL_MASK=3'b100` 설정
- [ ] 5. `PERSIST_LIMIT=5` 설정
- [ ] 6. `RECOVERY_COUNT=2` 설정
- [ ] 7. `DEGRADE_MASK=3'b001` 설정
- [ ] 8. `CLEAR_ALL`/`RESET_FAULT` 실행 후 각 `IRQ_STATUS` W1C
- [ ] 9. AXI INTC 초기화 및 Handler 등록
- [ ] 10. Fault Manager와 Safety Controller Enable
- [ ] 11. Heartbeat Monitor Enable
- [ ] 12. 각 IP IRQ Enable
- [ ] 13. MicroBlaze Global Interrupt Enable

---

## 7. 최종 산출 데이터

- [ ] RTL 단위 파형 3종
- [ ] AXI R/W 결과
- [ ] IRQ/W1C 결과
- [ ] 상태 전이 파형
- [ ] Fault Injection 결과표
- [ ] Critical Fault부터 출력 차단까지 Clock 수
- [ ] 공통 eval_tick 주기와 1클럭 Pulse 파형
- [ ] `RECOVERY_COUNT < PERSIST_LIMIT` 설정 증빙
- [ ] Vivado Block Design 캡처
- [ ] Utilization
- [ ] Timing Summary
- [ ] 보드 시연 영상
- [ ] 개인별 담당 내용
- [ ] 발생 문제와 해결 방법

PC 대시보드 산출물:

- [ ] Event Log CSV (`mission_events_*.csv`) — 상태 전이 순서 증빙
- [ ] Mission Log CSV (`mission_log_*.csv`) — 주기 상태 기록
- [ ] `WARNING → DEGRADED → NORMAL` 전이가 남은 CSV 구간
- [ ] Raw Log — `$ERR,MANUAL_RESET,FAULT_ACTIVE` 거부 증빙
- [ ] 앱 화면 캡처 (NORMAL / DEGRADED / SAFE_MODE 3종)

---

## 8. 변경 금지 시점

전체 Block Design에서 정상/DEGRADED/SAFE_MODE가 한 번이라도 동작한 이후에는 다음을 임의 변경하지 않는다.

- 레지스터 Offset
- State Encoding
- Fault Code
- UART 필드 순서
- UART 명령 이름 (`GET,*` `SET,*` `CMD,*` `INJECT,*`)
- `$EVENT` / `$ERR` 코드 이름
- UART Baudrate (9600)
- IRQ 연결 순서
- IP 포트 이름
- AXI GPIO 채널 할당 (`error_flag` / `critical_fault` / `heartbeat`)

필요한 변경은 팀 전체 승인 후 반영한다. 프로토콜을 바꾸면 **PC 앱과 펌웨어를
동시에** 고쳐야 하므로 03_MEMBER_C 11장, `mission_soc_dashboard/README_PROTOCOL.md`,
`uart_proto.c` 세 곳을 같은 커밋에서 갱신한다.
