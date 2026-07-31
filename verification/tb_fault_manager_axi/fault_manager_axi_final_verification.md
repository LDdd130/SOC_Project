# `fault_manager_axi` 최종 검증 결과

## 1. 검증 목적

`tb_fault_manager_axi.v`를 이용하여 Fault Manager AXI4-Lite Wrapper와 Core의 주요 기능을 통합 검증하였다.

검증 대상은 다음과 같다.

- AXI4-Lite Register Read/Write
- Reset 기본값
- Read-only Register Write 무시
- `CTRL.ENABLE`
- `CRITICAL_MASK`
- `PERSIST_LIMIT`
- `IRQ_EN`
- Fault 입력 및 Fault Level 판정
- `eval_tick` 기반 Persist Count
- IRQ Level 유지 및 `IRQ_STATUS` W1C
- Critical Fault 우선 처리
- `RESET_FAULT` W1P
- 활성 Fault 중 `RESET_FAULT` 무시
- Fault 제거 후 Count/Pending Clear
- `ENABLE=0` 안전 출력
- `IRQ_EN` 게이팅 (pending/irq 분리)
- `FAULT_COUNT` count1/count2 Bit Packing
- `FAULT_INPUT` error_flag Bit Packing

---

## 2. 시뮬레이션 조건

```text
Simulation type : Behavioral Simulation
Testbench       : tb_fault_manager_axi
Simulation end  : 4270 ns
Run method      : Run All
```

Testbench는 Self-checking 방식으로 구성되어 있으며, 검증 결과를 `checks`와 `errors`에 누적한다.

최종 결과:

```text
checks = 46
errors = 0
ALL PASS
```

콘솔 종료 메시지:

```text
$finish called at time : 4270 ns
```

추가로 AXI Bit Packing 및 IRQ 게이팅 세부 항목(A11~A13)은 별도의 단일 목적 Self-checking Testbench로 분리 검증하였다.

```text
tb_fault_manager_axi_A11_irq_gating.v            : checks=6, errors=0, ALL PASS ($finish @ 705 ns)
tb_fault_manager_axi_A12_count_packing.v         : checks=4, errors=0, ALL PASS ($finish @ 1560 ns)
tb_fault_manager_axi_A13_fault_input_packing.v   : checks=4, errors=0, ALL PASS ($finish @ 485 ns)
```

---

## 3. 검증 결과

### A01. Reset 기본값 검증

Reset 직후 주요 Register와 출력의 기본값을 확인하였다.

```text
CTRL reset              = 0
CRITICAL_MASK reset     = 3'b100
PERSIST_LIMIT reset     = 5
FAULT_DEVICE reset      = 3
fault_valid before EN   = 0
```

결과적으로 Reset 이후 Fault Manager가 비활성 안전 상태로 시작함을 확인하였다.

---

### A02. AXI Register Read/Write 검증

다음 설정 Register에 대해 Write 후 Read-back 값을 비교하였다.

```text
CRITICAL_MASK write/read-back
PERSIST_LIMIT write/read-back
IRQ_EN write/read-back
```

검증 결과:

```text
CRITICAL_MASK = 3'b111 write 후 3'b100으로 복원
PERSIST_LIMIT = 3 write/read 일치
IRQ_EN        = 1 write/read 일치
```

AXI Write 및 Read Channel의 Handshake가 정상적으로 수행되고 Register 값이 정확히 저장됨을 확인하였다.

---

### A03. Read-only Register Write 무시 검증

다음 Read-only Register에 임의 값을 Write하였다.

```text
FAULT_LEVEL
FAULT_COUNT
ID
```

Write 이후 값을 다시 읽은 결과 기존 값이 유지되었다.

```text
FAULT_LEVEL write ignored
FAULT_COUNT write ignored
ID write ignored
```

따라서 Read-only Register에 대한 AXI Write가 내부 상태를 변경하지 않음을 확인하였다.

> **참고:** `ID`(`0x2C`, `0x464D4752` = "FMGR")는 00 공통 명세 9.2의 레지스터 맵에 없는 추가 Register다. 기존 Offset `0x00`~`0x24`는 전혀 변경하지 않고 뒤에 덧붙인 것이며, 00 문서 15장 절차에 따른 [CHANGE REQUEST]를 `docs/fault_manager_integration.md`에 기재하여 팀 승인 대기 중이다.

---

### A04. Enable 및 일시 Fault 검증

`CTRL.ENABLE=1`로 설정한 뒤 Device 0 Timeout을 입력하였다.

검증 결과:

```text
fault_valid  = 1
timeout[0]   = 1
fault_level  = 1
fault_device = 0
fault_code   = FAULT_TIMEOUT
```

단일 일반 Fault가 Persist 기준 미만일 때 Level 1로 판정되고, Fault Device와 Code가 현재 원인에 맞게 출력됨을 확인하였다.

---

### A05. Persist Count와 Level 2 검증

Device 0 Timeout을 유지하면서 `eval_tick`을 발생시켰다.

검증 결과:

```text
fault_level  = 2
fault_code   = FAULT_TIMEOUT
fault_count0 = 5
```

일반 Fault Count가 시스템 Clock마다 증가하지 않고 `eval_tick`에서만 증가하며, `PERSIST_LIMIT=5`에 도달하면 Level 2로 상승함을 확인하였다.

---

### A06. IRQ Level 방식 및 W1C 검증

Fault 상태가 변경된 후 IRQ 동작을 확인하였다.

검증 결과:

```text
Fault change 발생       → irq = 1
상태 유지 중            → irq = 1 유지
IRQ_STATUS pending      → 1
IRQ_STATUS에 W1C Write  → pending = 0
W1C 후                  → irq = 0
```

IRQ가 1클럭 Pulse가 아니라 `IRQ_STATUS`가 Clear될 때까지 High를 유지하는 Level 방식으로 동작함을 확인하였다.

---

### A07. Critical Fault 우선순위 검증

Device 2 Critical Fault를 입력하였다.

검증 결과:

```text
critical_fault[2] = 1
fault_level       = 3
fault_device      = 2
fault_code        = FAULT_CRITICAL
IRQ_STATUS        = pending
```

Critical Fault는 Persist Count와 `eval_tick`을 기다리지 않고 즉시 Level 3으로 판정됨을 확인하였다.

또한 `IRQ_STATUS`에 0을 Write하는 동작으로는 Pending이 Clear되지 않고, W1C 방식으로 1을 Write해야 Clear됨을 확인하였다.

---

### A08. 활성 Fault 상태의 `RESET_FAULT` 무시 검증

Device 0의 Level 2 Fault가 유지되는 상태에서 `CTRL.RESET_FAULT`를 실행하였다.

검증 결과:

```text
reset 시도 전 count0 = 10
reset_fault_pulse width = 1 clock
CTRL.bit1 read-back = 0
fault_level remains = 2
fault_count0 remains = 10
```

`RESET_FAULT`는 W1P로 정확히 1클럭 Pulse를 생성하고 자동으로 0으로 복귀하였다.

현재 Fault가 남아 있을 때는 Count와 Fault Level을 임의로 Clear하지 않고 Reset 명령을 무시함을 확인하였다.

---

### A09. Fault 제거 후 `RESET_FAULT` 검증

Fault 입력을 제거한 후 `RESET_FAULT`를 실행하였다.

검증 결과:

```text
fault_level       = 0
fault_count0      = 0
IRQ pending       = 0
irq               = 0
```

현재 Fault가 모두 제거된 상태에서는 Count, 과거 Fault 비교 정보 및 Pending이 정상적으로 Clear됨을 확인하였다.

---

### A10. `ENABLE=0` 안전 출력 검증

Level 3 Fault 상태에서 Fault Manager를 Disable하였다.

검증 결과:

```text
fault_level   = 0
fault_device  = 3
fault_code    = FAULT_NONE
fault_count0  = 0
fault_valid   = 0
new pending   = 0
```

Disable 상태에서 Fault Manager가 공통 명세의 안전 출력으로 전환되고 새로운 IRQ Pending을 발생시키지 않음을 확인하였다.

입력 자체는 `critical_fault[2]=1`로 남아 있어도, `enable=0`이면 출력은 안전한 Disable 값으로 유지되었다.

---

### A11. `IRQ_EN` 게이팅 검증

별도 Testbench(`tb_fault_manager_axi_A11_irq_gating.v`)로 `IRQ_EN`이 `IRQ_STATUS` Pending과 `irq` 출력을 어떻게 분리 제어하는지 확인하였다.

콘솔 캡처:

```text
=== A11 : IRQ_EN 게이팅 검증 ===
  [ ok ] IRQ_EN disabled  (0x00000000)
  [ ok ] pending set while IRQ_EN=0  (0x00000001)
  [ ok ] irq stays low while IRQ_EN=0  (0)
  [ ok ] irq rises after IRQ_EN=1  (1)
  [ ok ] pending cleared by W1C  (0x00000000)
  [ ok ] irq low after pending clear  (0)

=====================================
 checks = 6, errors = 0  -> ALL PASS
=====================================

$finish called at time : 705 ns
```

결과적으로 `IRQ_EN=0`인 상태에서도 Fault 발생 시 `IRQ_STATUS`의 Pending 비트는 정상적으로 Set되지만, `irq` 출력 자체는 `IRQ_EN=1`로 전환되기 전까지 Low로 게이팅됨을 확인하였다. `IRQ_EN=1` 전환 즉시 `irq`가 High로 상승하고, `IRQ_STATUS`에 W1C를 수행하면 Pending과 함께 `irq`도 Low로 복귀함을 확인하였다.

---

### A12. `FAULT_COUNT` count1/count2 Bit Packing 검증

별도 Testbench(`tb_fault_manager_axi_A12_count_packing.v`)로 Device 1(`error_flag[1]`)과 Device 2(`error_flag[2]`)의 Persist Count가 `FAULT_COUNT` 레지스터 내 서로 다른 Byte 필드에 정확히 Packing되는지 확인하였다 (`count1`=bit[15:8], `count2`=bit[23:16]).

콘솔 캡처:

```text
=== A12 : FAULT_COUNT count1/count2 packing 검증 ===
  [ ok ] count1 packing  (0x00000400)
  [ ok ] internal count1 == 4  (0x00000004)
  [ ok ] count2 packing  (0x00040000)
  [ ok ] internal count2 == 4  (0x00000004)

=====================================
 checks = 4, errors = 0  -> ALL PASS
=====================================

$finish called at time : 1560 ns
```

`eval_tick`을 반복 인가한 뒤 Device 1 Fault의 Count가 `FAULT_COUNT[15:8]`에 `0x04`로, Device 2 Fault의 Count가 `FAULT_COUNT[23:16]`에 `0x04`로 서로 겹치지 않고 정확히 Packing됨을 확인하였다. 내부 `fault_count1`, `fault_count2` 레지스터 값도 각각 4로 일치하였다.

> **참고:** Testbench의 `wait_ticks(3)`는 내부 여유 Clock을 포함하므로 실제 `eval_tick`이 4회 발생하였다. 따라서 기대 Count를 4로 설정하여 내부 Count와 AXI Register Packing 값의 일치 여부를 검증하였다.

---

### A13. `FAULT_INPUT` error_flag Bit Packing 검증

별도 Testbench(`tb_fault_manager_axi_A13_fault_input_packing.v`)로 `timeout` / `error_flag` / `critical_fault` 3개 입력 벡터가 `FAULT_INPUT` 레지스터 내 서로 다른 필드(bit[2:0], bit[10:8], bit[18:16])로 정확히 Packing되어 Read되는지 확인하였다.

콘솔 캡처:

```text
=== A13 : FAULT_INPUT error_flag packing 검증 ===
  [ ok ] FAULT_INPUT error_flag[1] packing  (0x00000200)
  [ ok ] FAULT_INPUT bit[10:8] == 3'b010
  [ ok ] FAULT_INPUT all fields packing  (0x00040201)
  [ ok ] timeout/error/critical field split

=====================================
 checks = 4, errors = 0  -> ALL PASS
=====================================

$finish called at time : 485 ns
```

`error_flag[1]=1`일 때 `FAULT_INPUT[10:8]=3'b010`으로 Read됨을 확인하였다. `timeout[0]=1`, `error_flag[1]=1`, `critical_fault[2]=1`을 동시에 인가했을 때 `FAULT_INPUT = 0x00040201`로, 각 필드가 bit[2:0]=`001`, bit[10:8]=`010`, bit[18:16]=`100`으로 서로 겹치지 않고 정확히 분리되어 Packing됨을 확인하였다.

---

## 4. 파형에서 확인되는 주요 상태 변화

전체 파형에서는 다음 순서가 확인된다.

```text
Reset
→ Enable
→ Device 0 Timeout
→ Level 1
→ eval_tick 누적
→ Level 2
→ IRQ High
→ IRQ_STATUS W1C
→ IRQ Low
→ Device 2 Critical Fault
→ Level 3
→ Fault 제거
→ Level 0
→ Critical Fault 재입력
→ Level 3
→ Disable
→ Level 0 / fault_valid=0
```

주요 출력 값:

```text
Temporary Timeout:
fault_level=1, fault_device=0, fault_code=01

Persistent Timeout:
fault_level=2, fault_device=0, fault_code=01

Device 2 Critical:
fault_level=3, fault_device=2, fault_code=03

Disabled:
fault_level=0, fault_device=3, fault_code=00, fault_valid=0
```

---

## 5. 최종 결과표

| 검증 항목 | 결과 |
|---|---|
| Reset 기본값 | 통과 |
| AXI Register Read/Write | 통과 |
| Read-only Register Write 무시 | 통과 |
| Enable 및 `fault_valid` | 통과 |
| 단일 일시 Timeout Level 1 | 통과 |
| Persist Count 기반 Level 2 | 통과 |
| Count가 `eval_tick`에서만 증가 | 통과 |
| IRQ Level 유지 | 통과 |
| `IRQ_STATUS` W1C | 통과 |
| Device 2 Critical Level 3 | 통과 |
| Critical Fault 즉시 판정 | 통과 |
| `RESET_FAULT` W1P 1클럭 | 통과 |
| 활성 Fault 중 Reset 무시 | 통과 |
| Fault 제거 후 Count/Pending Clear | 통과 |
| `ENABLE=0` 안전 출력 | 통과 |
| 전체 Self-checking 결과 (메인 TB) | `checks=46`, `errors=0`, `ALL PASS` |
| `IRQ_EN` 게이팅 (A11) | 통과 (`checks=6`, `errors=0`) |
| `FAULT_COUNT` count1/count2 Packing (A12) | 통과 (`checks=4`, `errors=0`) |
| `FAULT_INPUT` error_flag Packing (A13) | 통과 (`checks=4`, `errors=0`) |
| 전체 Self-checking 결과 (메인 TB + A11~A13 합산) | `checks=60`, `errors=0`, `ALL PASS` |

---

## 6. 명세 적합성 결론

본 시뮬레이션으로 Fault Manager AXI Wrapper가 다음 정책을 만족함을 확인하였다.

```text
Critical > Multi-device > Persistent > Temporary > Normal
```

이번 Testbench에서 직접 확인한 핵심 정책은 다음과 같다.

- 일반 단일 Fault는 Level 1
- Persist Count가 기준에 도달하면 Level 2
- Device 2 Critical Fault는 Tick 대기 없이 Level 3
- IRQ는 Level 방식이며 W1C 전까지 유지
- `RESET_FAULT`는 W1P
- 활성 Fault가 남아 있으면 Reset 무시
- Fault가 없을 때만 Count와 Pending Clear
- Disable 시 안전 출력 및 `fault_valid=0`
- `IRQ_EN=0`일 때 Pending은 Set되지만 `irq` 출력은 게이팅되어 Low 유지
- `FAULT_COUNT`, `FAULT_INPUT`의 Device별 필드가 서로 겹치지 않고 정확히 Bit Packing

최종 Self-checking 결과:

```text
메인 TB (A01~A10) : checks = 46, errors = 0, ALL PASS
A11 (IRQ_EN 게이팅) : checks = 6,  errors = 0, ALL PASS
A12 (COUNT Packing) : checks = 4,  errors = 0, ALL PASS
A13 (INPUT Packing) : checks = 4,  errors = 0, ALL PASS
--------------------------------------------------------
합산                : checks = 60, errors = 0, ALL PASS
```

따라서 `fault_manager_axi`는 00~04 명세에서 요구하는 AXI Register 동작, Fault 판정, Persist Count, IRQ(게이팅 포함), Reset, Disable 정책 및 Register Bit Packing을 만족한다.

---

## 7. 제출용 이미지 구성

최종 보고서에는 다음 이미지를 사용하는 것이 적절하다.

### 필수 이미지 1 — 전체 파형 상단

다음 신호가 보이는 화면:

```text
ACLK
ARESETN
AXI Write/Read Channel
timeout
critical_fault
fault_level
fault_device
fault_code
fault_valid
```

### 필수 이미지 2 — 전체 파형 하단

다음 신호가 보이는 화면:

```text
irq
eval_tick
errors
checks
pulse_len
pulse_max
Register Address localparam
```

### 필수 이미지 3 — 최종 콘솔 결과

다음 결과가 포함된 화면:

```text
A04~A10 검증 결과
checks = 46, errors = 0 -> ALL PASS
$finish called at time : 4270 ns
```

초기 A01~A04 내용만 별도로 보여주는 중간 콘솔 캡처는 선택 사항이다. 최종 콘솔 화면과 본 문서에 A01~A10 결과가 정리되어 있으므로, 보고서 공간이 부족하면 중간 콘솔 캡처는 제외해도 된다.

### 필수 이미지 4 — A11 콘솔 결과

`tb_fault_manager_axi_A11_irq_gating.v` 실행 결과 (`image copy 3.png`):

```text
IRQ_EN 게이팅 검증
checks = 6, errors = 0 -> ALL PASS
$finish called at time : 705 ns
```

### 필수 이미지 5 — A12 콘솔 결과

`tb_fault_manager_axi_A12_count_packing.v` 실행 결과 (`image copy 4.png`):

```text
FAULT_COUNT count1/count2 packing 검증
checks = 4, errors = 0 -> ALL PASS
$finish called at time : 1560 ns
```

### 필수 이미지 6 — A13 콘솔 결과

`tb_fault_manager_axi_A13_fault_input_packing.v` 실행 결과 (`image copy 5.png`):

```text
FAULT_INPUT error_flag packing 검증
checks = 4, errors = 0 -> ALL PASS
$finish called at time : 485 ns
```
