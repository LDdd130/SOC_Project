# 팀원 C AI 프로젝트 지침 — safety_controller_ip 담당 (Recovery 정책 확정본)

> 이 문서는 `safety_controller_ip` 담당자가 자신의 AI 프로젝트에 넣는 전용 지침이다.  
> Safety Controller는 Fault를 새로 판단하지 않고, Fault Manager의 등급에 따라 시스템 출력을 안전하게 전환한다.  
> 전체 Vivado/Vitis 통합은 팀원 A·B·C 세 명이 공동으로 수행한다.  
> **확정 Recovery 정책:** `DEGRADED + Level 0 지속 → NORMAL`, `DEGRADED + Level 1 지속 → WARNING`.

---

## 0. 3인 팀 내 역할

팀원 C는 `safety_controller_ip`의 주 담당자다.

C의 통합 지원 책임:

- System State와 출력 Enable 확인
- Manual Recovery용 Vitis 함수 제공
- LED 상태 매핑 (LD0~LD15, 12.2 참고. FND/RGB LED 는 이번 빌드 미구현)
- SAFE_MODE Latch와 출력 차단 시연 준비

C가 전체 통합을 혼자 담당하는 구조가 아니다. Vivado Block Design, AXI INTC, MicroBlaze/Vitis와 최종 디버깅은 세 명이 공동으로 진행한다.

---

## 1. 담당 범위

필수 RTL:

- `safety_controller_core.v`
- `safety_controller_axi.v`
- `NORMAL`, `WARNING`, `DEGRADED`, `SAFE_MODE` FSM
- `output_enable[2:0]`
- `actuator_enable`
- `control_valid`
- SAFE_MODE Latch
- Manual Recovery
- 상태 변화 IRQ
- Core/AXI Testbench

공동 통합 항목:

아래 작업은 C 단독 담당이 아니라 세 명 공동 작업이다.

- MicroBlaze Block Design
- AXI UARTLite
- AXI Interrupt Controller
- xlconcat
- 3개 Custom IP 연결
- Address Map 확정
- Vitis BSP/Application
- ISR
- LED 상태 표시 (LD0~LD15)
- 최종 통합 Test
- 발표용 Fault Injection 흐름

확장:

- AXI Timer
- BRAM Event Log
- PC 대시보드

---

## 2. Safety Core 입력과 출력

### 입력

```verilog
input wire        clk;
input wire        reset;
input wire        enable;
input wire        eval_tick;
input wire [1:0]  fault_level;
input wire [1:0]  fault_device;
input wire [7:0]  fault_code;
input wire        fault_valid;
input wire [2:0]  degrade_mask;
input wire [15:0] recovery_count_setting;
input wire        manual_reset_pulse;
```

### 출력

```verilog
output wire [1:0] system_state;
output wire [2:0] output_enable;
output wire       actuator_enable;
output wire       control_valid;
output wire [31:0] state_timer;
output wire       state_change_event;
```

`fault_valid`는 Fault Manager 출력의 사용 가능 여부를 나타내는 Level 신호다. Recovery Count용 Pulse가 아니다.

---

## 3. FSM 인코딩

```verilog
localparam [1:0] ST_NORMAL    = 2'b00;
localparam [1:0] ST_WARNING   = 2'b01;
localparam [1:0] ST_DEGRADED  = 2'b10;
localparam [1:0] ST_SAFE_MODE = 2'b11;
```

공통 명세와 다르게 One-hot으로 바꾸지 않는다.  
내부 인코딩을 바꾸더라도 AXI 출력은 반드시 위 2비트 값으로 변환한다.

---

## 4. 상태 전이

### NORMAL

- `fault_valid=0` → 상태 Hold, 출력은 안전값
- Level 0 → NORMAL
- Level 1 → WARNING
- Level 2 → DEGRADED
- Level 3 → SAFE_MODE

### WARNING

- Level 0이 연속 `RECOVERY_COUNT` 이상 → NORMAL
- Level 1 → WARNING
- Level 2 → DEGRADED
- Level 3 → SAFE_MODE

### DEGRADED

- Level 3 → SAFE_MODE
- Level 2 → DEGRADED
- Level 1이 연속 `RECOVERY_COUNT` 이상 유지 → WARNING
- Level 0이 연속 `RECOVERY_COUNT` 이상 유지 → NORMAL

중요:

- `fault_level=1`인데 `NORMAL`로 복귀하는 경로는 구현하지 않는다.
- 오류가 완화된 수준에 맞춰 단계적으로 복귀한다.
- Level 1은 여전히 경고가 존재하므로 대응 상태는 `WARNING`이다.

### SAFE_MODE

- Fault Level이 0이 되어도 유지
- `manual_reset_pulse=1`, `fault_valid=1`, `fault_level=0`일 때만 NORMAL
- Fault가 남아 있으면 Manual Reset 무시

`enable=1`, `fault_valid=0`이면 FSM 상태는 Hold하되 다음 안전 출력을 강제한다.

```text
output_enable=000
actuator_enable=0
control_valid=0
recovery_counter=0
```

Fault Manager 출력이 다시 유효해지면 현재 `fault_level`에 따라 전이를 재개한다.

---

## 5. 출력 정책

### NORMAL

```text
output_enable = 3'b111
actuator_enable = 1
control_valid = 1
```

### WARNING

```text
output_enable = 3'b111
actuator_enable = 1
control_valid = 1
```

경고 LED/IRQ만 변경한다.

### DEGRADED

단일 Fault Device:

```verilog
case (fault_device)
    2'd0: output_enable = 3'b110;
    2'd1: output_enable = 3'b101;
    2'd2: output_enable = 3'b011;
    default: output_enable = 3'b111 & ~degrade_mask;
endcase
```

- `fault_device=0~2`이면 실제 Fault 장치만 Disable한다.
- `fault_device=3`인 다중 고장 또는 판정 불가 입력에서만 `DEGRADE_MASK`를 적용한다.
- 기본 `DEGRADE_MASK=3'b001`은 `fault_device=3`일 때 Device 0 비필수 기능을 차단하는 대체 정책이다.
- 기본 `CRITICAL_MASK=3'b100`이면 Device 2 Fault는 Fault Manager에서 Level 3이 되므로 일반 통합에서 Device 2 단독 DEGRADED는 발생하지 않는다.

### SAFE_MODE

```text
output_enable = 3'b000
actuator_enable = 0
control_valid = 0
```

CPU 처리와 무관하게 상태가 SAFE_MODE로 전이된 클럭부터 안전값을 출력해야 한다.

### DISABLED

```text
system_state = NORMAL
output_enable = 3'b000
actuator_enable = 0
control_valid = 0
state_timer = 0
state_change_event = 0
```

초기화 전 장치가 켜지지 않도록 `enable=0`에서 `output_enable=3'b111`을 사용하지 않는다.

---

## 6. Recovery Count

Recovery Count는 상태를 낮추기 전에 Fault Level이 일정하게 유지되는지 확인하는 안정화 횟수다.

- `WARNING`에서 Level 0이 연속 유지되면 `NORMAL` 복귀 판단에 사용
- `DEGRADED`에서 Level 1이 연속 유지되면 `WARNING` 복귀 판단에 사용
- `DEGRADED`에서 Level 0이 연속 유지되면 `NORMAL` 복귀 판단에 사용
- Level이 상승하거나 목표 복귀 Level이 바뀌면 Recovery Counter를 0으로 초기화
- `eval_tick=1`인 클럭에서만 Count
- 100MHz 매 클럭 증가시키지 않음
- SAFE_MODE에서는 Recovery Count만으로 자동 복귀하지 않음
- `fault_valid`는 Count Tick으로 사용하지 않음
- `recovery_count_setting=0`은 유효값 1로 간주

권장 구현:

- 현재 Recovery 목표 Level을 내부에 기억하거나,
- Level 0용/Level 1용 Counter를 분리하지 않고 입력 Level이 바뀔 때 단일 Counter를 Clear한다.

공통 `eval_tick_generator.v` Module Reference가 1ms마다 생성하는 `eval_tick`을 Fault Manager와 함께 사용한다. B와 C의 포트명은 모두 `eval_tick`이다. Testbench에서는 Divider Parameter만 줄인다.

`DEGRADED → WARNING` 경로를 사용할 때는 다음 제약을 지킨다.

```text
RECOVERY_COUNT < PERSIST_LIMIT
권장 초기값: RECOVERY_COUNT=2, PERSIST_LIMIT=5
```

동일 Fault가 완전히 사라지면 Fault Manager가 Level 0을 출력하므로 `DEGRADED → NORMAL` 직접 복귀가 정상적으로 발생할 수 있다.

---

## 7. 확정 레지스터 맵

| Offset | 이름 | 접근 | 구현 |
|---:|---|---|---|
| `0x00` | `CTRL` | RW/W1P | bit0 ENABLE, bit1 MANUAL_RESET |
| `0x04` | `SYSTEM_STATE` | R | bit[1:0] |
| `0x08` | `OUTPUT_ENABLE` | R | bit[2:0] |
| `0x0C` | `DEGRADE_MASK` | RW | bit[2:0] |
| `0x10` | `RECOVERY_COUNT` | RW | bit[15:0] |
| `0x14` | `STATE_TIMER` | R | 현재 상태 유지 Count |
| `0x18` | `IRQ_EN` | RW | bit0 State Change |
| `0x1C` | `IRQ_STATUS` | R/W1C | bit0 State Change Pending |

`STATE_TIMER`는 100MHz Clock Count 또는 별도 Tick Count 중 하나로 정하고 문서에 단위를 명시한다.

5일 구현 권장:

- 100MHz Clock Count
- Saturation
- UART 출력 시 MicroBlaze에서 ms로 환산

Reset 후 `DEGRADE_MASK`, `RECOVERY_COUNT`, `IRQ_EN`, `IRQ_STATUS`는 0이다. MicroBlaze는 `RECOVERY_COUNT=2`, `DEGRADE_MASK=3'b001`을 권장 초기값으로 설정한 뒤 Safety Controller를 Enable한다.

---

## 8. 필수 Testbench

1. Reset → NORMAL
2. NORMAL + Level 1 → WARNING
3. NORMAL/WARNING + Level 2 → DEGRADED
4. 어느 상태에서든 Level 3 → SAFE_MODE
5. Level 0→1→2→3 전체 상승 전이
6. WARNING + Level 0이 `RECOVERY_COUNT-1`회 유지 → WARNING 유지
7. WARNING + Level 0이 `RECOVERY_COUNT`회 유지 → NORMAL
8. DEGRADED + Level 1이 `RECOVERY_COUNT-1`회 유지 → DEGRADED 유지
9. DEGRADED + Level 1이 `RECOVERY_COUNT`회 유지 → WARNING
10. DEGRADED + Level 0이 `RECOVERY_COUNT-1`회 유지 → DEGRADED 유지
11. DEGRADED + Level 0이 `RECOVERY_COUNT`회 유지 → NORMAL
12. DEGRADED에서 Level 1 유지 중 NORMAL로 직접 복귀하지 않는지 확인
13. Recovery 도중 Level이 0↔1로 바뀌면 Counter가 초기화되는지 확인
14. SAFE_MODE에서 Fault 제거만으로 복귀하지 않음
15. SAFE_MODE에서 Fault가 남은 상태의 Manual Reset 거부
16. `fault_valid=1` + Level 0 + Manual Reset → NORMAL
17. 각 상태의 출력 Enable
18. DEGRADED 단일 Device 0/1 입력에서 실제 해당 장치만 Disable
19. `fault_device=3`인 DEGRADED에서만 DEGRADE_MASK 적용
20. `RECOVERY_COUNT=0`을 1로 처리
21. Recovery Count가 `eval_tick`에서만 증가
22. `fault_valid=0`에서 상태 Hold, Recovery Count Clear와 안전 출력
23. State Timer
24. State Change Event 중복 방지
25. IRQ_STATUS W1C
26. `enable=0` 안전 출력

---

## 9. 세 명 공동 Vivado Block Design 기준

필수 연결:

```text
MicroBlaze
├─ M_AXI_DP → AXI SmartConnect
│  ├─ heartbeat_monitor_ip/S_AXI
│  ├─ fault_manager_ip/S_AXI
│  ├─ safety_controller_ip/S_AXI
│  ├─ AXI UARTLite
│  └─ 선택: AXI Timer / AXI GPIO
│
├─ INTERRUPT ← AXI Interrupt Controller
│               ↑
│             xlconcat
│               ├─ heartbeat irq
│               ├─ fault_manager irq
│               └─ safety_controller irq
│
└─ Local Memory 또는 BRAM
```

Custom IP 간 핵심 상태 신호는 MicroBlaze 레지스터 중개가 아니라 직접 연결한다.

```text
heartbeat_monitor_ip.timeout
→ fault_manager_ip

fault_manager_ip.fault_level/device/code/valid
→ safety_controller_ip

공통 eval_tick
├─ fault_manager_ip.eval_tick
└─ safety_controller_ip.eval_tick

heartbeat_monitor_ip.alive
→ LED / MicroBlaze 상태 표시
```

`eval_tick_generator.v`는 100MHz 입력에서 기본 1ms마다 1클럭 Pulse를 생성하는 공통 Module Reference다. AXI가 없는 보조 RTL이므로 네 번째 Custom IP로 계산하지 않는다.

`safety_controller_ip.output_enable`은 `heartbeat_monitor_ip.device_enable`에 연결하지 않는다. 기본 감시 설정은 `device_enable=3'b111`로 독립 유지한다.

---

## 10. 권장 Interrupt 순서

xlconcat 입력 예:

```text
In0 = heartbeat_monitor_irq
In1 = fault_manager_irq
In2 = safety_controller_irq
In3 = AXI UARTLite IRQ 또는 Timer IRQ
```

실제 Vector ID는 Vivado 생성 후 `xparameters.h` 기준으로 확정한다.  
AI가 임의의 숫자 ID를 고정해서 코드에 넣지 않게 한다.

ISR 원칙:

```c
void HeartbeatIsr(void *Ref);
void FaultManagerIsr(void *Ref);
void SafetyControllerIsr(void *Ref);
```

각 ISR:

1. 해당 IP `IRQ_STATUS` Read
2. 전역 Event 구조체에 저장
3. 해당 비트 W1C
4. 메인 루프용 Flag Set

UART 출력은 메인 루프에서 수행한다.

Custom IP IRQ부터 MicroBlaze 처리까지 다음 전체 경로를 검증한다.

```text
IRQ_STATUS Set
→ Custom IP irq High
→ AXI INTC Pending
→ XIntc Handler
→ Custom IP IRQ_STATUS W1C
→ AXI INTC 처리 완료
→ Custom IP irq Low
```

Fault Manager IRQ와 Safety Controller IRQ가 동시에 발생하는 것은 정상이며 두 Pending을 각각 처리한다.

---

## 11. UART 프로토콜 (PC 대시보드 연동 확정본)

PC 측 Python 대시보드(`mission_soc_dashboard/`)가 이 규격을 그대로 구현하고 있고,
MicroBlaze 측 구현은 `SOC_Pr_Vitis/soc_prj/src/uart_proto.c` 다.
전체 규격 원본은 `mission_soc_dashboard/README_PROTOCOL.md` 이며 이 장은 그 확정 요약이다.

**필드 순서와 명령 이름은 통합 후 변경하지 않는다** (04 체크리스트 1장 Freeze 대상).

### 11.0 링크 기본 규칙

| 항목 | 값 |
|---|---|
| Baudrate | **9600 8N1** (AXI UARTLite 기본값). PC 앱에서 반드시 9600 선택 |
| 인코딩 | ASCII (UTF-8 호환) |
| 구분자 | 쉼표 `,` |
| 줄 종료 | `\n`. 보드는 `\r\n` 을 보내고 PC 는 둘 다 허용한다 |
| 최대 줄 길이 | 4096 bytes. 초과분은 PC 가 폐기한다 |
| 접두어 | `$MISSION`, `$EVENT`, `$ACK`, `$ERR` |
| 그 외 | `$` 로 시작하지 않는 줄은 디버그 문자열. PC 는 Raw Log 에만 기록한다 |

9600bps 는 한 글자에 약 1.04 ms 다. `$MISSION` 한 줄이 70자를 넘으므로 전송에만
약 73 ms 가 걸린다. 송신 함수는 블로킹이므로 그동안 메인 루프가 멈춘다는 점을
전제로 주기를 잡는다.

---

### 11.1 `$MISSION` — 주기 상태 보고 (FPGA → PC)

```text
$MISSION,timestamp,state,fault_level,fault_device,fault_code,alive,timeout,output_enable,actuator_enable[,control_valid][,state_timer][,fault_count0][,fault_count1][,fault_count2]
```

예:

```text
$MISSION,1250,SAFE_MODE,3,2,3,0x03,0x04,0x00,0
$MISSION,1250,SAFE_MODE,3,2,3,0x03,0x04,0x00,0,0,3245,0,0,1
```

| # | 이름 | 형식 | 의미 |
|--:|---|---|---|
| 1 | `timestamp` | 0 이상 정수 | MicroBlaze 기준 ms |
| 2 | `state` | 문자열 | `NORMAL` / `WARNING` / `DEGRADED` / `SAFE_MODE` |
| 3 | `fault_level` | 0~3 | 00 공통명세 7.2 |
| 4 | `fault_device` | 0~3 | 00 공통명세 7.4. `3` = `MULTIPLE_OR_NONE` |
| 5 | `fault_code` | 0x00~0x05 | 00 공통명세 7.3 |
| 6 | `alive` | 3비트 마스크 | bit0=Device0, bit1=Device1, bit2=Device2 |
| 7 | `timeout` | 3비트 마스크 | 동일 |
| 8 | `output_enable` | 3비트 마스크 | 동일 |
| 9 | `actuator_enable` | 0 / 1 | |
| 10 | `control_valid` | 0 / 1 | **선택** |
| 11 | `state_timer` | 정수 | **선택**. `STATE_TIMER` (Offset `0x14`) |
| 12~14 | `fault_count0~2` | 0~255 | **선택**. `FAULT_COUNT` 언패킹 값 |

- **1~9 번은 필수.** 10 번 이후는 없어도 PC 가 파싱한다.
- 10진수와 `0x` 16진수를 섞어 써도 된다.
- 마스크는 하위 3비트만 사용한다.
- 알 수 없는 state/level/device/code 값이 와도 PC 는 `UNKNOWN` 으로 표시하고 죽지 않는다.
- `actuator_enable` 과 `control_valid` 는 AXI 레지스터로 직접 읽을 수 없으므로
  MicroBlaze 가 `SYSTEM_STATE` 와 두 IP 의 `ENABLE` 에서 유도한다.

**권장 전송 주기**: 메인 루프에서 100~500 ms. 9600bps 에서는 **500 ms** 를 쓴다.
ISR 안에서 UART 를 출력하지 않는다 (00 공통명세 12장).

---

### 11.2 `$EVENT` — 상태 변화 이벤트 (FPGA → PC)

```text
$EVENT,timestamp,event_type[,arg0][,arg1][,arg2]
```

| `event_type` | 인자 | 발생 시점 |
|---|---|---|
| `FAULT_CHANGE` | level, device, code | `fault_level`/`device`/`code` 중 하나라도 변경 |
| `STATE_CHANGE` | state 문자열 | Safety Controller 상태 전이 |
| `HEARTBEAT_TIMEOUT` | device | `timeout[i]` 가 0 → 1 |
| `MANUAL_RESET` | `ACCEPTED` / `REJECTED` | Manual Recovery 시도 결과 |

예:

```text
$EVENT,1300,FAULT_CHANGE,2,0,1
$EVENT,1301,STATE_CHANGE,DEGRADED
$EVENT,1700,HEARTBEAT_TIMEOUT,0
```

`$MISSION` 은 주기 샘플이라 짧은 상태를 놓친다. **상태 전이의 증거는 `$EVENT` 다.**
IRQ 는 "변화가 있었다" 만 알려주므로 실제 값은 메인 루프가 폴링으로 직전 값과
비교해 만든다 (ISR 안에서 레지스터를 읽지 않는다).

`event_type` 이나 인자 수가 위와 달라도 PC 는 원본을 Event Log 에 보존한다.
새 이벤트를 추가해도 PC 수정이 필요 없다.

---

### 11.3 `$ACK` / `$ERR` — 명령 응답 (FPGA → PC)

```text
$ACK,command[,arg0][,arg1][,arg2]
$ERR,error_code[,description]
```

**수신한 모든 명령에 `$ACK` 또는 `$ERR` 중 하나로 반드시 응답한다.**

| `error_code` | 의미 |
|---|---|
| `UNKNOWN_COMMAND` | 지원하지 않는 명령. PC 는 "지원하지 않는 기능" 으로 표시할 뿐 오류로 처리하지 않는다 |
| `INVALID_VALUE` | 인자 범위 초과 |
| `FAULT_ACTIVE` | 활성 Fault 때문에 거부 |
| `FAULT_INVALID` | `fault_valid=0` 이라 판단 불가 |

예:

```text
$ACK,SET,PERSIST_LIMIT,5
$ACK,CMD,MANUAL_RESET
$ERR,MANUAL_RESET,FAULT_ACTIVE
$ERR,INVALID_VALUE,PERSIST_LIMIT
```

---

### 11.4 설정 명령 (PC → FPGA)

```text
SET,TIMEOUT,<device>,<clocks>      device: 0~2, clocks: 0~0xFFFFFFFF
SET,CRITICAL_MASK,<mask>           mask: 0x00~0x07
SET,PERSIST_LIMIT,<value>          value: 0~255
SET,RECOVERY_COUNT,<value>         value: 0~65535
SET,DEGRADE_MASK,<mask>            mask: 0x00~0x07
```

| 명령 | IP | Offset (00 공통명세 9장) |
|---|---|---|
| `SET,TIMEOUT,0/1/2` | heartbeat_monitor | `0x08` / `0x0C` / `0x10` |
| `SET,CRITICAL_MASK` | fault_manager | `0x08` |
| `SET,PERSIST_LIMIT` | fault_manager | `0x0C` |
| `SET,RECOVERY_COUNT` | safety_controller | `0x10` |
| `SET,DEGRADE_MASK` | safety_controller | `0x0C` |

- `TIMEOUTn=0`, `PERSIST_LIMIT=0`, `RECOVERY_COUNT=0` 은 유효값 **1** 로 간주 (00 공통명세 12.1)
- `PERSIST_LIMIT` 레지스터는 8비트다. **256 이상은 `$ERR,INVALID_VALUE`** 로 거부한다.
- `DEGRADED → WARNING` 경로를 쓰려면 `RECOVERY_COUNT < PERSIST_LIMIT` (6장).
  PC 는 위반 시 경고만 표시하고 전송은 막지 않는다.

---

### 11.5 조회 명령 (PC → FPGA)

| 명령 | 응답 |
|---|---|
| `GET,STATUS` | `$ACK,GET,STATUS` + `$MISSION,...` 한 줄 |
| `GET,CONFIG` | `$ACK,GET,CONFIG` + 현재 설정값을 `SET,...` 형태 `$ACK` 로 나열 |

`GET,CONFIG` 응답 예:

```text
$ACK,GET,CONFIG
$ACK,SET,TIMEOUT,0,30000000
$ACK,SET,TIMEOUT,1,60000000
$ACK,SET,TIMEOUT,2,15000000
$ACK,SET,CRITICAL_MASK,4
$ACK,SET,PERSIST_LIMIT,5
$ACK,SET,RECOVERY_COUNT,2
$ACK,SET,DEGRADE_MASK,1
```

---

### 11.6 제어 명령 (PC → FPGA)

| 명령 | 대응 동작 | 거부 조건 |
|---|---|---|
| `CMD,MANUAL_RESET` | safety_controller `CTRL.bit1` W1P | `fault_valid=1` && `fault_level=0` 이 아니면 `$ERR,MANUAL_RESET,FAULT_ACTIVE` |
| `CMD,RESET_FAULT` | fault_manager `CTRL.bit1` W1P | 활성 `device_fault` 가 있으면 `$ERR,RESET_FAULT,FAULT_ACTIVE` (02 문서 6.1) |
| `CMD,CLEAR_IRQ` | 세 IP `IRQ_STATUS` 각각 W1C | 없음 |
| `CMD,CLEAR_HEARTBEAT` | heartbeat_monitor `CTRL.bit1` (`CLEAR_ALL`) W1P | 없음 |

`CLEAR_IRQ` 는 Pending 만 지운다. Fault/Timeout 상태는 바뀌지 않는다.
`CLEAR_HEARTBEAT` 는 Counter/Timeout 만 지우고 IRQ Pending 은 건드리지 않는다.

이 두 명령은 12장의 `BTN_U` / `BTN_D` 와 **같은 동작을 UART 로 대체한 경로**다.
보드 버튼과 PC 명령 중 어느 쪽을 써도 결과가 같아야 한다.
**이번 빌드에는 물리 버튼이 배선되어 있지 않으므로 UART 경로만 존재한다**
(12장 참고).

---

### 11.7 Fault Injection 명령 (PC → FPGA)

```text
INJECT,ERROR,<device>,ON|OFF
INJECT,CRITICAL,<device>,ON|OFF
INJECT,TIMEOUT,<device>,ON|OFF
INJECT,CLEAR,ALL
```

`device` 는 0~2. 00 공통명세 8.3 의 `error_flag[2:0]` / `critical_fault[2:0]` 을
MicroBlaze 가 AXI GPIO 로 구동해서 만든다. 00 공통명세 12.3 의 보드 SW0~SW3
시연 입력과 등가이며, **이번 빌드에서는 이 GPIO 경로가 유일한 주입 수단**이다
(물리 스위치 미배선).

| 종류 | 구현 |
|---|---|
| `ERROR` | `GPIO0 CH1` = `error_flag` 비트 Set/Clear |
| `CRITICAL` | `GPIO0 CH2` = `critical_fault` 비트 Set/Clear |
| `TIMEOUT` | **GPIO 직접 주입이 아니다.** 해당 Device 의 Heartbeat 생성을 중단해 `heartbeat_monitor` 가 `TIMEOUTn` 초과를 스스로 판정하게 한다 (04 체크리스트 1.1 Freeze) |
| `CLEAR,ALL` | 위 셋 전부 해제 + Heartbeat 재개 |

`INJECT,TIMEOUT` 은 하드웨어가 실제로 Counter 를 세야 하므로 즉시 반응하지 않는다.
Device 0 = 300 ms, Device 1 = 600 ms, Device 2 = 150 ms 뒤에 반응한다.

---

### 11.8 WARNING 관측 조건 (중요)

`WARNING` 은 FSM 에 정상적으로 존재하지만 **머무는 시간이 매우 짧다.**

```text
Level 1 지속시간 = PERSIST_LIMIT × eval_tick 주기(1 ms)
기본 PERSIST_LIMIT=5  →  5 ms
```

MicroBlaze 가 상태 변화를 감지하는 지연은 9600bps 기준 다음과 같다.

```text
INJECT 파싱 -> Level 1 성립          : 수 클럭
같은 함수의 $ACK 송신 (약 21자)      : 약 22 ms  (블로킹)
irq 로그 1줄 (약 29자)               : 약 30 ms  (블로킹)
report_changes() 가 레지스터를 읽음  : 누적 50 ms 이상
```

즉 **기본 설정에서는 Level 1 이 이미 Level 2 로 바뀐 뒤에 읽히므로
`$EVENT,STATE_CHANGE,WARNING` 이 아예 나오지 않는다.** 이는 정상 동작이다.

WARNING 을 시연하려면 다음을 지킨다.

1. `SET,PERSIST_LIMIT,255` 로 올린다 → Level 1 창이 255 ms 가 되어 확실히 잡힌다.
2. **단일 비Critical 장치** 하나만 주입한다. 아래는 설정과 무관하게 WARNING 이 없다.

| 조작 | WARNING 발생 | 이유 |
|---|---|---|
| Device 0 **또는** 1 단독 `ERROR`/`TIMEOUT` | O | 유일한 경로 |
| Device 2 아무 Fault | X | `CRITICAL_MASK=0x04` → 지속 무시, 즉시 Level 3 (00 공통명세 10장 우선순위 1) |
| 2개 이상 장치 동시 Fault | X | `FAULT_MULTI_DEVICE` → 즉시 Level 3 (우선순위 2) |

3. 확인은 `$MISSION` (500 ms 주기) 이 아니라 **`$EVENT,STATE_CHANGE,WARNING`** 으로 한다.

---

### 11.9 구현 체크리스트

```text
□ AXI UARTLite Baudrate 를 PC 앱과 일치시켰는가 (9600)
□ $MISSION 필수 9개 필드를 명세 순서대로 보내는가
□ 마스크는 하위 3비트만 쓰는가
□ 줄 끝에 \n(또는 \r\n)을 붙이는가
□ ISR 안에서 UART 출력을 하지 않는가 (00 공통명세 12장)
□ 상태 변화 시 $EVENT 를 보내는가
□ 모든 수신 명령에 $ACK 또는 $ERR 로 응답하는가
□ MANUAL_RESET 을 fault_valid=1 && fault_level=0 에서만 승인하는가
□ RESET_FAULT 를 활성 Fault 상태에서 거부하는가
□ TIMEOUTn=0, PERSIST_LIMIT=0, RECOVERY_COUNT=0 을 1 로 처리하는가
□ PERSIST_LIMIT 256 이상을 $ERR,INVALID_VALUE 로 거부하는가
□ 긴 UART 송신 중에도 Heartbeat 생성이 끊기지 않는가
```

---

## 12. 보드 시연 입력과 출력

### 12.1 입력 — **물리 SW/BTN 미구현 (설계 의도 기록)**

> **상태 : 이번 빌드에 포함되지 않음.**
> BD 최상위 외부 포트는 `sys_clock`, `reset`(btnC), `usb_uart`, `led[15:0]` 뿐이고
> `axi_gpio_0` / `axi_gpio_1` 은 둘 다 출력 전용(`C_ALL_OUTPUTS=1`)이라 보드
> 스위치·버튼을 읽지 못한다. 아래는 나중에 물리 I/O를 붙일 때의 배선 규칙이다.
> 현재 시연은 전부 PC 대시보드(UART)로 한다.

```text
SW0 = Device 0 Heartbeat 중단
SW1 = Device 1 일반 Error
SW2 = Device 2 Critical Fault
SW3 = Device 0+1 동시 Fault 또는 테스트 모드
BTN_U = MicroBlaze를 통한 Manual Recovery 명령
BTN_D = MicroBlaze를 통한 세 IP IRQ Pending Clear 명령
```

외부 입력 경로:

```text
SW1/SW2/SW3
→ 2FF Synchronizer
→ 필요 시 Debounce
→ fault_manager_ip

BTN_U
→ AXI GPIO 또는 Synchronizer/One-shot
→ MicroBlaze
→ CTRL.MANUAL_RESET W1P

BTN_D
→ AXI GPIO 또는 Synchronizer/One-shot
→ MicroBlaze
→ 세 IP IRQ_STATUS를 각각 W1C
```

BTN_D는 Timeout/Fault 상태 자체를 직접 Clear하지 않는다.

**이번 빌드의 실제 입력 수단** — 대응표는 00 공통명세 12.3 참고.
전부 `mission_soc_dashboard` 의 UART 명령이다.

| 설계상 입력 | 실제 사용 명령 |
|---|---|
| `SW0` | `INJECT,TIMEOUT,0,ON` |
| `SW1` | `INJECT,ERROR,1,ON` |
| `SW2` | `INJECT,CRITICAL,2,ON` |
| `SW3` | `INJECT,TIMEOUT,0,ON` + `INJECT,ERROR,1,ON` (앱의 `Multi Fault` 프리셋) |
| `BTN_U` | `CMD,MANUAL_RESET` (앱의 `Manual Recovery` 버튼) |
| `BTN_D` | `CMD,CLEAR_IRQ` (앱의 `Clear IRQ` 버튼) |
| 보드 리셋 | btnC (유일하게 실제 배선된 물리 입력) |

### 12.2 출력 — LED 16개 (실제 구현)

`led_concat`(xlconcat, In0 이 LSB)가 세 IP의 상태 신호를 모아 `led[15:0]` 으로
낸다. Basys 3 의 LD0~LD15 에 그대로 매핑된다.

| LED | 폭 | 신호 | 의미 |
|---|---|---|---|
| `LD1:LD0` | 2 | `system_state` | 0=NORMAL, 1=WARNING, 2=DEGRADED, 3=SAFE_MODE |
| `LD4:LD2` | 3 | `output_enable[2:0]` | Device 0/1/2 출력 허용 |
| `LD5` | 1 | `actuator_enable` | 구동기 허용 |
| `LD6` | 1 | `control_valid` | 제어 유효 |
| `LD9:LD7` | 3 | `alive[2:0]` | Device 0/1/2 Heartbeat 살아있음 |
| `LD12:LD10` | 3 | `timeout[2:0]` | Device 0/1/2 Timeout |
| `LD14:LD13` | 2 | `fault_level` | 0~3 |
| `LD15` | 1 | `fault_valid` | Fault Manager Enable 과 동일 |

> **RGB LED / FND — 미구현.**
> 아래는 원래 계획이었으나 이번 빌드에는 배선하지 않았다. 같은 정보를
> `LD1:LD0`(system_state) 와 `LD14:LD13`(fault_level) 으로 대체 표시한다.
>
> ```text
> RGB LED:  Green=NORMAL  Yellow=WARNING  Orange=DEGRADED  Red=SAFE_MODE
> FND:      Fault Level 또는 Fault Device
> ```

핀 배치는 프로젝트에 등록된 `Basys-3-Master.xdc` 를 따른다
(저장소 루트의 `constraints/mission_soc.xdc` 는 프로젝트에 포함되지 않은
참고용 사본이다).

---

## 13. 세 명 공동 통합 순서

1. 세 IP AXI Register Read/Write만 연결
2. 각 IP 개별 IRQ 확인
3. `eval_tick_generator.v`와 B/C 공통 `eval_tick` 연결
4. IP 간 직접 상태 신호 연결
5. 정상 입력에서 NORMAL 확인
6. Device 0 Timeout → DEGRADED
7. Device 2 Timeout/Error/Critical → SAFE_MODE
8. SAFE_MODE Latch
9. Manual Recovery
10. UART 출력
11. LED (LD0~LD15)
12. 확장 기능

한 번에 모든 기능을 연결하지 않는다.

---

## 14. AI 작업 원칙

AI에게 다음을 고정해서 요청한다.

```text
Safety Controller는 Fault를 새로 판정하지 말고 fault_level 입력만 기준으로 FSM을 구성할 것.
SAFE_MODE는 정상 입력만으로 자동 복귀하지 않을 것.
MANUAL_RESET은 W1P일 것.
IRQ는 Level + W1C일 것.
Vivado Vector ID는 xparameters.h에서 가져올 것.
ISR 안에서 UART 출력하지 않을 것.
Custom IP 간 상태 신호는 MicroBlaze가 중개하지 않을 것.
```

통합 중 공통 신호나 레지스터 변경이 필요하면 AI가 임의 수정하지 말고 Change Request 초안을 먼저 작성하게 한다.
