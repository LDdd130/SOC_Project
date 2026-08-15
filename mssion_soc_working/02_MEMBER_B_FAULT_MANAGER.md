# 팀원 B AI 프로젝트 지침 — fault_manager_ip 담당

> 이 문서는 `fault_manager_ip` 담당자가 자신의 AI 프로젝트에 넣는 전용 지침이다.  
> Fault Manager는 오류의 존재를 감지하는 IP가 아니라, 입력된 오류를 **중요도와 지속 횟수에 따라 등급화**하는 IP다.

---

## 0. 3인 팀 내 역할

팀원 B는 `fault_manager_ip`의 주 담당자다.  
전체 Block Design과 최종 통합은 A·B·C 세 명이 함께 수행한다.

B의 통합 지원 책임:

- 일반 Error와 Critical Fault 입력 시나리오 정의
- Fault Level·Device·Code 해석용 Vitis 함수 제공
- Fault 정책표와 통합 결과 대조
- 발표용 Fault Injection 순서와 예상 결과 정리

---

## 1. 담당 범위

필수 담당:

- `fault_manager_core.v`
- `fault_manager_axi.v`
- Timeout/Error/Critical 입력 조합
- 장치별 오류 지속 Count
- Fault Level 결정
- 주요 Fault Device와 Fault Code 결정
- AXI 설정 레지스터
- Fault/Level 변화 IRQ
- Core 및 AXI Testbench
- Fault 정책표와 RTL 결과 비교

담당하지 않는 범위:

- Heartbeat Counter
- 외부 비동기 입력 동기화
- Safety 출력 Enable 제어
- SAFE_MODE 복구 FSM
- UART 문자열 출력 및 PC 대시보드 프로토콜 (MicroBlaze 펌웨어 담당)

### 1.1 PC 대시보드가 이 IP에서 쓰는 값

프로토콜 자체는 구현하지 않지만, 아래 레지스터가 그대로 PC 화면에 나가므로
이름·비트 위치·동작을 바꾸면 앱이 깨진다. 전체 규격은 03_MEMBER_C 11장.

| PC 쪽 항목 | 출처 |
|---|---|
| `$MISSION` 3번 필드 `fault_level` | `FAULT_LEVEL` (`0x10`) |
| `$MISSION` 4번 필드 `fault_device` | `FAULT_DEVICE` (`0x14`) |
| `$MISSION` 5번 필드 `fault_code` | `FAULT_CODE` (`0x18`) |
| `$MISSION` 12~14번 필드 `fault_count0~2` | `FAULT_COUNT` (`0x1C`) 언패킹 |
| `$EVENT,...,FAULT_CHANGE,<level>,<dev>,<code>` | level/device/code 중 하나라도 변경 |
| `SET,CRITICAL_MASK,<mask>` 명령 | `CRITICAL_MASK` (`0x08`) 쓰기 |
| `SET,PERSIST_LIMIT,<value>` 명령 | `PERSIST_LIMIT` (`0x0C`) 쓰기 |
| `CMD,RESET_FAULT` 명령 | `CTRL.bit1` W1P |
| `CMD,CLEAR_IRQ` 명령 | `IRQ_STATUS` W1C |
| `INJECT,ERROR/CRITICAL,<dev>,ON\|OFF` | `error_flag[2:0]` / `critical_fault[2:0]` (AXI GPIO 구동) |

추가로 요구되는 사항:

- `FAULT_COUNT` packing은 00 공통명세 9.2 권장안을 **그대로** 쓴다.
  PC 앱이 `bit[7:0]`=Device0, `bit[15:8]`=Device1, `bit[23:16]`=Device2 로 언패킹한다.
- `PERSIST_LIMIT`은 8비트다. PC는 `0~255`만 허용하고 그 이상은 전송 전에 막는다.
  펌웨어도 `$ERR,INVALID_VALUE,PERSIST_LIMIT` 으로 거부한다.
- `RESET_FAULT`는 6.1대로 활성 Fault가 있으면 무시한다. 펌웨어가 이 조건을
  먼저 확인해 `$ERR,RESET_FAULT,FAULT_ACTIVE` 를 보내므로 RTL 동작과 응답이
  일치해야 한다.
- **`PERSIST_LIMIT`은 Level 1(WARNING)의 지속 시간을 그대로 결정한다**
  (00 공통명세 10.1). 기본값 5는 5 ms 다. 짧지만 `fault_change_event`(0→1 전이)가
  IRQ를 올리고 ISR이 그 순간 값을 Snapshot에 남기므로 **`$EVENT` 로는 기본값에서도
  기록된다.** 500 ms 주기의 `$MISSION` 에만 잡히지 않는다.
  RTL Testbench에서는 `eval_tick` 단위로 Level 1을 반드시 검증한다.

---

## 2. 입력과 출력

### Core 입력

```verilog
input  wire        clk;
input  wire        reset;
input  wire        enable;
input  wire        eval_tick;
input  wire [2:0]  timeout;
input  wire [2:0]  error_flag;
input  wire [2:0]  critical_fault;
input  wire [2:0]  critical_mask;
input  wire [7:0]  persist_limit;
input  wire        reset_fault_pulse;
```

### Core 출력

```verilog
output wire [1:0]  fault_level;
output wire [1:0]  fault_device;
output wire [7:0]  fault_code;
output wire        fault_valid;
output wire [7:0]  fault_count0;
output wire [7:0]  fault_count1;
output wire [7:0]  fault_count2;
output wire        fault_change_event;
```

`fault_change_event`는 Fault Level, Fault Device 또는 Fault Code 중 하나가 바뀌는 순간 1클럭 Pulse다.  
AXI wrapper가 이를 `IRQ_STATUS`에 Latch한다.

`fault_valid`는 출력 상태가 사용 가능함을 나타내는 Level 신호다.

```text
enable=1 → fault_valid=1
enable=0 → fault_valid=0
```

`fault_valid`를 Persist Count 또는 Recovery Count용 Tick으로 사용하지 않는다.

---

## 3. 확정 Fault 정책

우선순위:

### Priority 1 — Critical

```text
device_fault = timeout | error_flag | critical_fault
critical_condition = |(device_fault & critical_mask)

critical_condition != 0
→ LEVEL 3
→ FAULT_CRITICAL
```

`critical_mask`는 `critical_fault` 입력에만 적용하는 Mask가 아니다. Mask된 장치의 Timeout, Error, Critical Fault를 모두 Critical 조건으로 처리하며 지속 횟수를 기다리지 않는다.

### Priority 2 — 다중 장치 오류

Critical 조건이 없고, Timeout, Error, Critical을 합친 장치별 Fault 비트 중 2개 이상:

```text
fault_level = 3
fault_code = FAULT_MULTI_DEVICE
fault_device = MULTIPLE_OR_NONE
```

Critical 우선순위가 더 높다.

### Priority 3 — 지속 일반 오류

Critical Mask가 없는 한 장치의 Fault가 `PERSIST_LIMIT` 이상 지속:

```text
fault_level = 2
fault_code = 원인 우선순위에 따른 Code
fault_device = 해당 장치
```

### Priority 4 — 일시 일반 오류

Critical Mask가 없는 단일 장치 Fault가 존재하지만 Persist 기준 미만:

```text
fault_level = 1
fault_code = 원인 우선순위에 따른 Code
fault_device = 해당 장치
```

### Priority 5 — 정상

```text
fault_level = 0
fault_code = FAULT_NONE
fault_device = MULTIPLE_OR_NONE
```

### Fault Code 우선순위

```text
critical_condition       → FAULT_CRITICAL
critical_condition 없음,
2개 이상 device_fault   → FAULT_MULTI_DEVICE
단일 error_flag 또는
Mask 밖 critical_fault  → FAULT_ERROR_CODE
단일 timeout             → FAULT_TIMEOUT
Fault 없음               → FAULT_NONE
```

- 같은 단일 장치에 `timeout`과 `error_flag`가 동시에 있으면 `FAULT_ERROR_CODE`를 출력한다.
- `critical_condition`에 해당하는 장치가 하나이면 해당 Device ID를 출력한다.
- `critical_condition`에 해당하는 장치가 둘 이상이면 `FAULT_CRITICAL`, `MULTIPLE_OR_NONE`을 출력한다.
- Critical 조건 장치 하나와 일반 장치 Fault가 동시에 있으면 Critical 조건 장치 ID와 `FAULT_CRITICAL`을 출력한다.
- Critical이 없는 다중 장치 Fault이면 `FAULT_MULTI_DEVICE`, `MULTIPLE_OR_NONE`을 출력한다.

---

## 4. 지속 Count 정의

장치별 현재 오류:

```verilog
device_fault[i] = timeout[i] | error_flag[i] | critical_fault[i];
```

- `eval_tick=1`이고 오류가 있는 클럭에서만 Count 증가
- 오류가 없으면 Count 0
- Count Saturation
- `persist_limit == 0`일 때의 정책을 명시

권장:

```text
persist_limit == 0 → 1로 간주
```

실제 Heartbeat Timeout은 오랜 시간 유지되는 Level이므로 매 100MHz Clock마다 Count하지 않는다. 공통 `eval_tick_generator.v` Module Reference가 1ms마다 생성하는 1클럭 Pulse `eval_tick`을 Safety Controller와 함께 사용한다. Testbench에서는 Divider Parameter만 줄인다.

Critical 조건과 다중 장치 Fault 검출은 `eval_tick`과 무관하게 매 100MHz Clock에서 현재 입력으로 판정한다. 일반 단일 Fault의 Persist Count만 `eval_tick`에서 갱신한다.

Critical 입력부터 출력 차단까지의 목표 지연은 다음과 같다.

```text
외부 입력 동기화 지연
+ Fault Manager 최대 1 Clock
+ Safety Controller 최대 1 Clock
```

문서의 “즉시”는 위와 같이 정해진 Clock 수 안에 결정적으로 차단한다는 뜻이다.

---

## 5. Device 선택 규칙

단일 Fault:

- 해당 Device ID 출력

다중 Fault:

- `2'b11`

Critical 장치가 하나이고 다른 일반 Fault도 동시에 있는 경우:

- Critical Device를 `fault_device`로 출력
- `fault_code = FAULT_CRITICAL`

동일 등급의 단일 Fault가 여러 개라면:

- `fault_device = 2'b11`
- `fault_code = FAULT_MULTI_DEVICE`

같은 장치에 여러 원인이 있으면 다중 장치 Fault가 아니며 Fault Code 우선순위로 하나를 선택한다.

---

## 6. 확정 레지스터 맵

| Offset | 이름 | 접근 | 구현 |
|---:|---|---|---|
| `0x00` | `CTRL` | RW/W1P | bit0 ENABLE, bit1 RESET_FAULT |
| `0x04` | `FAULT_INPUT` | R | 입력 요약 |
| `0x08` | `CRITICAL_MASK` | RW | 모든 Fault 원인에 적용, 기본 `3'b100` |
| `0x0C` | `PERSIST_LIMIT` | RW | bit[7:0] 사용 |
| `0x10` | `FAULT_LEVEL` | R | bit[1:0] |
| `0x14` | `FAULT_DEVICE` | R | bit[1:0] |
| `0x18` | `FAULT_CODE` | R | bit[7:0] |
| `0x1C` | `FAULT_COUNT` | R | 3개 Count packing |
| `0x20` | `IRQ_EN` | RW | bit0 Fault Change |
| `0x24` | `IRQ_STATUS` | R/W1C | bit0 Fault Change Pending |
| `0x2C` | `ID` | R | `0x464D4752` (`"FMGR"`). 브링업 진단용 — 아래 참고 |

> **`0x2C` ID 레지스터 (2026-07-30 승인)**
>
> 원래 확정 맵에는 없던 확장이다. Read-only 상수라 Fault 정책·IRQ·상태
> 어디에도 영향을 주지 않고, 보드 브링업에서 AXI 주소 매핑이 제대로 붙었는지
> 한 번에 확인하는 용도다. `0x28` 은 비워 두어 향후 확장에 남긴다.
>
> HW(`src/fault_manager_axi.v`)와 FW(`mission_ip_regs.h` 의 `FM_ID` /
> `FM_ID_VALUE`) 양쪽에 이미 구현되어 있으므로 확정 맵에 반영한다.

`FAULT_INPUT` 권장 Packing:

```text
bit[2:0]   timeout
bit[10:8]  error_flag
bit[18:16] critical_fault
```

`FAULT_COUNT`:

```text
bit[7:0]   count0
bit[15:8]  count1
bit[23:16] count2
```

Reset 후 설정 레지스터가 0이면 `persist_limit=0`은 유효값 1로 처리한다. MicroBlaze 권장 초기값은 `CRITICAL_MASK=3'b100`, `PERSIST_LIMIT=5`다.

### 6.1 RESET_FAULT 정의

```text
현재 device_fault가 하나라도 있음
→ RESET_FAULT 무시

현재 device_fault가 모두 없음
→ Count, 출력 변화 비교용 과거 정보, IRQ_STATUS Pending Clear
```

활성 Fault가 남아 있는데 Count만 지워 Level 2를 Level 1로 낮추는 동작은 금지한다.

### 6.2 Disable 출력

```text
enable=0
→ fault_valid=0
→ fault_level=0
→ fault_device=MULTIPLE_OR_NONE
→ fault_code=FAULT_NONE
→ fault_count0~2=0
→ fault_change_event=0
```

Disable 중에는 새로운 IRQ Pending을 Set하지 않는다.

---

## 7. IRQ 규칙

- Fault Level, Device 또는 Code 변화 시 `IRQ_STATUS.bit0 = 1`
- 출력 상태가 유지되는 동안 반복 Set하지 않음
- W1C 전까지 IRQ High
- Reset Fault 명령과 Fault 입력이 동시에 존재하면 실제 Fault 입력 우선
- Fault Manager와 Safety Controller의 IRQ가 같은 시점에 발생하는 것은 정상

---

## 8. 필수 Testbench

1. 정상 입력 → Level 0
2. Device 0 Timeout 1회 → Level 1
3. Device 0 Timeout 지속 → Level 2
4. Device 1 Error → Level 1
5. Device 2 Timeout → Tick 대기 없이 Level 3
6. Device 2 Error → Tick 대기 없이 Level 3
7. Device 2 Critical → Tick 대기 없이 Level 3
8. Device 0+1 동시 Fault → Tick 대기 없이 Level 3, Multi
9. Critical 장치 + 일반 Fault → Critical 우선
10. 동일 장치 Timeout+Error → Error Code
11. Critical 장치 둘 이상 → Critical Code, Device 3
12. Level 1에서 Device와 Code가 현재 원인과 일치
13. 오류 제거 → Count 0, Level 복귀
14. Count가 `eval_tick`에서만 증가
15. Count Saturation
16. `persist_limit=0`
17. Fault 출력 변화 Event
18. 동일 상태가 유지될 때 중복 Event 없음
19. RESET_FAULT 입력 중 실제 Fault가 남아 있으면 정상으로 잘못 복귀하지 않음
20. Fault가 없을 때 RESET_FAULT가 Count/과거 정보/Pending Clear
21. `enable=0` 안전 출력

Self-checking Testbench에서 Reference function 또는 예상값 Task를 사용한다.

---

## 9. 팀에 전달할 산출물

```text
fault_manager_core.v
fault_manager_axi.v 또는 패키징 IP
tb_fault_manager_core.v
tb_fault_manager_axi.v (가능하면)
fault_policy_table.md
fault_manager_waveform.png
fault_manager_integration.md
```

`fault_policy_table.md`에는 입력 조합별 다음 값을 기록한다.

```text
timeout
error_flag
critical_fault
persist_count
expected level
expected device
expected code
```

---

## 10. AI 작업 원칙

AI가 임의로 Level 4를 만들지 않도록 한다.

AI 요청 시 다음을 명시한다.

```text
Fault Level은 2비트 0~3으로 고정한다.
Critical > Multi-device > Persistent > Temporary > Normal 우선순위를 지킨다.
Critical Mask를 Timeout, Error, Critical Fault 모두에 적용한다.
지속 Count는 공통 eval_tick에서만 갱신한다.
Critical과 다중 Fault는 매 Clock 판정한다.
출력 변화 Event와 Level IRQ를 구분해 설명한다.
공통 레지스터 Offset을 변경하지 않는다.
Self-checking Testbench와 경계조건을 포함한다.
```
