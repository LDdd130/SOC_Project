# 임무컴퓨터 상태 감시·고장 대응 SoC — 3인 팀 공통 AI 프로젝트 지침 (Recovery 정책 확정본)

> 이 문서는 팀원별 AI 프로젝트에 공통으로 적용하는 **최상위 기준 문서**다.  
> 아래 명세와 충돌하는 새로운 구조, 신호명, 상태값, 레지스터 의미를 임의로 만들지 않는다.  
> **Recovery 정책 확정:** `DEGRADED + Level 0 지속 → NORMAL`, `DEGRADED + Level 1 지속 → WARNING`.

---


## 0. 팀 구성과 역할 원칙

본 프로젝트의 인원은 **사용자 본인을 포함해 총 3명**이다.

```text
팀원 A: heartbeat_monitor_ip
팀원 B: fault_manager_ip
팀원 C: safety_controller_ip
```

공통 명세 문서와 통합 체크리스트는 별도의 네 번째 담당자가 맡는 문서가 아니다.

각 팀원은 자신이 맡은 Custom IP의 RTL, AXI4-Lite, 단위 Testbench와 통합 문서를 책임진다. 전체 Vivado Block Design, IP 간 신호 연결, AXI Interrupt Controller, MicroBlaze/Vitis, 보드 시연과 최종 디버깅은 **세 명이 공동으로 수행한다**.

통합 과정에서 특정 한 명에게 모든 작업을 몰지 않는다.

| 구분 | 팀원 A | 팀원 B | 팀원 C |
|---|---|---|---|
| 주 Custom IP | Heartbeat Monitor | Fault Manager | Safety Controller |
| 단위 RTL/TB | 책임 | 책임 | 책임 |
| AXI Wrapper | 책임 | 책임 | 책임 |
| 입력·고장 시나리오 | Heartbeat/Timeout | Error/Critical/Fault Level | State/Manual Recovery |
| Vitis 지원 | Timeout 설정 함수 | Fault 상태 해석 함수 | 상태 출력·Recovery 함수 |
| 전체 Block Design | 공동 | 공동 | 공동 |
| 전체 통합 Test | 공동 | 공동 | 공동 |
| PPT·발표 자료 | 본인 IP 부분 | 본인 IP 부분 | 본인 IP 부분 |

---

## 1. 프로젝트 한 문장 정의

여러 하위 장치의 Heartbeat와 오류 상태를 FPGA Custom IP가 병렬로 감시하고, 오류의 중요도와 지속시간에 따라 시스템을 `NORMAL`, `WARNING`, `DEGRADED`, `SAFE_MODE`로 자동 전환하는 MicroBlaze 기반 SoC를 구현한다.

이 프로젝트는 실제 군용 임무컴퓨터를 제작하는 것이 아니라, 고신뢰 임베디드 시스템의 상태 감시·고장 분류·안전 출력 차단 원리를 Basys 3에서 축소 구현하는 교육용 프로토타입이다.

---

## 2. 확정된 전체 구조

```text
Device 0~2 또는 Device Simulator
        │ heartbeat[2:0]
        ▼
┌─────────────────────────┐
│ heartbeat_monitor_ip    │
│ - 입력 동기화            │
│ - 장치별 Counter         │
│ - Timeout / Alive 판정   │
└───────────┬─────────────┘
            │ timeout[2:0]
            ▼
┌─────────────────────────┐
│ fault_manager_ip        │
│ - 오류 중요도           │
│ - 지속 횟수             │
│ - Fault Level 결정      │
└───────────┬─────────────┘
            │ fault_level[1:0], fault_device[1:0], fault_code[7:0]
            ▼
┌─────────────────────────┐
│ safety_controller_ip    │
│ - 시스템 상태 FSM       │
│ - 장치 Enable 제어      │
│ - SAFE_MODE 래치        │
└───────────┬─────────────┘
            │ system_state[1:0], output_enable[2:0], actuator_enable
            ▼
      LED[15:0] / 모의 출력

error_flag[2:0] ────────────────→ fault_manager_ip
critical_fault[2:0] ────────────→ fault_manager_ip
heartbeat_monitor_ip.alive ─────→ LED / MicroBlaze 상태 표시
공통 eval_tick ─────────────┬───→ fault_manager_ip
                            └───→ safety_controller_ip

각 Custom IP ── AXI4-Lite ── MicroBlaze
각 IRQ ── xlconcat ── AXI INTC ── MicroBlaze
MicroBlaze ── AXI UARTLite ── PC 대시보드 (Python)
```

`alive`는 Fault Manager 입력이 아니다. Fault Manager에는 Heartbeat Monitor의 `timeout`만 직접 연결한다.

PC 대시보드는 단순 터미널 출력 확인용이 아니라 **양방향 제어 단말**이다.
UART 프로토콜은 03_MEMBER_C 11장에서 확정하며 요약은 다음과 같다.

```text
FPGA → PC : $MISSION (주기 상태)  $EVENT (상태 전이)  $ACK / $ERR (명령 응답)
PC → FPGA : GET,...  SET,...  CMD,...  INJECT,...
```

`SET`/`CMD`/`INJECT`는 12.3의 SW/BTN 외부 입력 경로와 **등가**로 설계했다.
어느 쪽으로 조작해도 결과가 같아야 한다. Custom IP RTL은 PC 존재를 모른다.
프로토콜 계층은 전적으로 MicroBlaze 펌웨어 책임이다.

> **구현 범위 (2026-07-30 확정)**
> 현재 빌드는 **PC 대시보드(UART) 경로만** 구현했다. 12.3의 물리 SW/BTN 경로는
> Block Design과 XDC에 배선되어 있지 않다 (BD 최상위 외부 포트는
> `sys_clock` / `reset(btnC)` / `usb_uart` / `led[15:0]` 4개뿐).
> 따라서 이 문서에서 SW/BTN을 전제로 한 항목은 **설계 의도 기록**이며,
> 검증·시연은 전부 UART 경로로 한다. 자세한 내용은 12.3 참고.

---

## 3. 필수 Custom IP

팀의 필수 신규 IP는 정확히 다음 3개다.

1. `heartbeat_monitor_ip`
2. `fault_manager_ip`
3. `safety_controller_ip`

다음 기능은 필수 IP 완성 후에만 확장한다.

- `event_logger_ip`
- BRAM 로그
- 별도 `device_simulator_ip`
- 성능 측정용 추가 IP

핵심 3개 IP가 동작하기 전에는 확장 기능을 추가하지 않는다.

**PC 대시보드는 확장 항목에서 제외한다.** 3개 IP 통합 이후 단계에서 확정된
필수 검증/시연 도구이며 신규 Custom IP를 요구하지 않는다.

```text
mission_soc_dashboard/          PC 측 Python 앱 (PySide6)
  README_PROTOCOL.md            UART 프로토콜 규격 원본
SOC_Pr_Vitis/soc_prj/src/
  uart_proto.c                  MicroBlaze 측 프로토콜 구현
```

Custom IP RTL은 대시보드 때문에 바뀌지 않는다. 추가되는 것은 MicroBlaze 펌웨어의
프로토콜 계층과, Fault 주입을 위한 `AXI GPIO` 뿐이다.

---

## 4. 필수 IP Catalog 구성

반드시 실제 Block Design에 사용한다.

- `MicroBlaze`
- `AXI Interrupt Controller`
- `AXI UARTLite`
- `AXI GPIO` × 2 (PC 대시보드 Fault Injection 경로. 아래 참조)

`AXI UARTLite` 설정은 **9600 8N1** 으로 고정한다. PC 대시보드 앱에서도 같은 값을
선택해야 하며 이 값은 통합 이후 변경하지 않는다.

`AXI GPIO` 용도 (03_MEMBER_C 11.7):

```text
axi_gpio_0  CH1 = error_flag[2:0]      MicroBlaze -> fault_manager_ip
            CH2 = critical_fault[2:0]  MicroBlaze -> fault_manager_ip
axi_gpio_1  CH1 = heartbeat[2:0]       MicroBlaze -> heartbeat_monitor_ip
```

`heartbeat`를 MicroBlaze가 생성하므로 하위 장치 없이도 실제 Timeout을 재현할 수
있다. Timeout은 GPIO로 직접 주입하지 않는다 (04 체크리스트 1.1 Freeze).

권장 추가 IP:

- `AXI Timer`
- `xlconcat`
- `Processor System Reset`
- `Clocking Wizard` 또는 보드 기본 Clock
- 필요 시 `Block Memory Generator`, `AXI BRAM Controller`

교육과정의 “IP Catalog IP 2개 이상” 증빙에는 `AXI Interrupt Controller`와 `AXI UARTLite`를 우선 사용한다.

---

## 5. 전역 설계 규칙

### 5.1 클럭과 리셋

- 시스템 클럭: `100 MHz`
- 1 clock: `10 ns`
- AXI 리셋: Vivado 템플릿의 `S_AXI_ARESETN` 사용
- 내부 core 리셋은 필요하면 `reset = ~S_AXI_ARESETN`으로 변환
- 비동기 외부 입력은 반드시 2FF Synchronizer 적용

### 5.2 공통 평가 Tick

Fault 지속 Count와 Safety Recovery Count는 하나의 공통 입력을 사용한다.

```verilog
module eval_tick_generator #(
    parameter integer DIVISOR = 100_000
) (
    input  wire clk,
    input  wire reset,
    output wire eval_tick
);
```

연결:

```text
공통 eval_tick
├─ fault_manager_ip.eval_tick
└─ safety_controller_ip.eval_tick
```

- `eval_tick`은 1클럭 폭의 Pulse다.
- 생성 위치는 공통 통합 RTL `eval_tick_generator.v`로 고정하고 Vivado Block Design에 Module Reference로 추가한다.
- 기본 주기는 1ms, 즉 100MHz 기준 100,000클럭마다 1클럭 Pulse다.
- `reset=1` 동안 `eval_tick=0`이고 내부 Divider Counter는 0이다.
- Reset 해제 후 `DIVISOR`개 클럭을 센 뒤 첫 Pulse를 출력한다.
- Testbench에서는 Divider Parameter만 작은 값으로 Override할 수 있다.
- B와 C는 모두 `eval_tick`이라는 동일한 포트명만 사용한다.
- `eval_tick_generator.v`는 AXI 레지스터가 없는 공통 보조 RTL이며 네 번째 Custom IP로 계산하지 않는다.
- Fault Manager의 일반 Fault 지속 Count와 Safety Controller의 Recovery Count만 `eval_tick`에서 갱신한다.
- Critical 조건과 다중 장치 Fault는 매 100MHz Clock에서 판정한다.

### 5.3 데이터 폭

- AXI4-Lite 데이터 폭: `32 bit`
- AXI 주소는 word-aligned
- 상태와 설정 레지스터는 32비트
- Counter 폭은 Timeout 최대값을 수용하도록 최소 32비트 권장

### 5.4 레지스터 동작 규칙

- `W1P`: 1을 쓰면 내부에서 1클럭 Pulse 생성 후 자동 해제
- `W1C`: 1을 쓴 비트만 Clear
- IRQ는 Pulse가 아니라 **Level 방식**
- `IRQ_STATUS != 0 && IRQ_EN 해당 비트 == 1`이면 IRQ High 유지
- ISR이 `IRQ_STATUS`를 W1C로 Clear할 때까지 IRQ 유지
- Read-only 상태 레지스터에 대한 Write는 무시
- `IRQ_STATUS` W1C는 IRQ Pending만 Clear하며 Fault/Timeout 상태는 변경하지 않음

### 5.5 RTL 작성 규칙

- Verilog-2001 또는 팀이 합의한 SystemVerilog 중 하나만 사용
- 조합논리는 기본값을 먼저 할당해 Latch 방지
- 순차논리는 Non-blocking assignment 사용
- Magic number 대신 `localparam` 사용
- IP core와 AXI wrapper를 가능한 한 분리
- 타 팀원 IP 내부 구현에 직접 의존하지 말고 확정된 인터페이스만 사용

---

## 6. 장치 정의

| Device | 의미 | 기본 Heartbeat 주기 | 기본 Timeout | 중요도 |
|---|---|---:|---:|---|
| Device 0 | 일반 센서 처리 장치 | 100 ms | 300 ms | 일반 |
| Device 1 | 통신 장치 | 200 ms | 600 ms | 중간 |
| Device 2 | 모터/핵심 제어 장치 | 50 ms | 150 ms | Critical |

위 시간은 데모 초기값이다. 실제 RTL에서는 AXI 레지스터를 통해 Clock count로 설정할 수 있어야 한다.

100MHz 기준 예:

```text
100 ms = 10,000,000 clocks
150 ms = 15,000,000 clocks
300 ms = 30,000,000 clocks
600 ms = 60,000,000 clocks
```

Testbench에서는 시뮬레이션 시간을 줄이기 위해 작은 Count 값을 사용해도 된다. 단, RTL 구조는 실제 값도 수용해야 한다.

---

## 7. 공통 상태 및 코드 정의

### 7.1 System State

```text
2'b00 = NORMAL
2'b01 = WARNING
2'b10 = DEGRADED
2'b11 = SAFE_MODE
```

### 7.2 Fault Level

```text
2'b00 = LEVEL_0_NORMAL
2'b01 = LEVEL_1_WARNING
2'b10 = LEVEL_2_DEGRADED
2'b11 = LEVEL_3_SAFE
```

Fault Level 4 이상은 만들지 않는다. 2비트로 통일한다.

### 7.3 Fault Code

```text
8'h00 = FAULT_NONE
8'h01 = FAULT_TIMEOUT
8'h02 = FAULT_ERROR_CODE
8'h03 = FAULT_CRITICAL
8'h04 = FAULT_MULTI_DEVICE
8'h05 = FAULT_RECOVERY_REQUIRED
```

팀원이 임의로 새로운 코드값을 추가하려면 먼저 공통 명세를 수정하고 공유한다.

### 7.4 Device ID

```text
2'b00 = DEVICE_0
2'b01 = DEVICE_1
2'b10 = DEVICE_2
2'b11 = MULTIPLE_OR_NONE
```

---

## 8. IP 간 확정 인터페이스

### 8.1 heartbeat_monitor_ip Core 제어

```verilog
input wire       enable;
input wire [2:0] device_enable;
```

- AXI `CTRL.bit0`을 `enable`에 연결한다.
- 5일 기본 구현에서는 `device_enable = 3'b111`로 고정한다.
- `device_enable`은 감시 설정이며 Safety Controller의 `output_enable`과 독립이다.
- `safety_controller_ip.output_enable`을 `heartbeat_monitor_ip.device_enable`에 연결하지 않는다.

### 8.2 heartbeat_monitor_ip → fault_manager_ip

```verilog
output wire [2:0] timeout;
```

의미:

- `timeout[i] = 1`: 해당 장치의 Heartbeat Counter가 설정값 이상
- `device_enable[i] = 0`이면 `timeout[i] = 0`이므로 Fault 판단에서 제외
- `alive[2:0]`는 LED/MicroBlaze 상태 표시용으로 유지하지만 Fault Manager에는 연결하지 않는다.

### 8.3 외부/Simulator → fault_manager_ip

```verilog
input wire [2:0] error_flag;
input wire [2:0] critical_fault;
```

- `error_flag[i]`: 일반 오류
- `critical_fault[i]`: `critical_mask[i]`가 설정된 장치에서 지속 Count 없이 Level 3으로 처리할 치명적 오류
- Device 2의 `critical_fault[2]`가 기본 Critical 시연 입력

### 8.4 공통 eval_tick

```verilog
input wire eval_tick;  // fault_manager_ip, safety_controller_ip 공통
```

`eval_tick`은 Count 갱신 전용이다. Critical/다중 Fault의 현재 조건 판정을 지연시키는 Enable로 사용하지 않는다.

### 8.5 fault_manager_ip → safety_controller_ip

```verilog
output wire [1:0] fault_level;
output wire [1:0] fault_device;
output wire [7:0] fault_code;
output wire       fault_valid;
```

- `fault_valid = 1`: 현재 Fault Manager 출력이 사용 가능한 상태
- `fault_valid`는 Pulse가 아니라 Level 신호이며 Count용 Tick으로 사용하지 않는다.
- Fault Manager `enable=0`이면 `fault_valid=0`이다.
- Safety Controller는 `fault_valid=0`에서 상태를 Hold하고 Recovery Count를 0으로 Clear하며 안전 출력을 강제한다.
- Manual Reset은 `fault_valid=1 && fault_level=0`일 때만 인정한다.
- Fault Level, Device 또는 Code가 바뀌면 IRQ_STATUS를 설정한다.

### 8.6 safety_controller_ip 출력

```verilog
output wire [1:0] system_state;
output wire [2:0] output_enable;
output wire       actuator_enable;
output wire       control_valid;
```

정책:

- `NORMAL`: `output_enable=3'b111`, `actuator_enable=1`
- `WARNING`: 기능 유지, 경고 상태만 출력
- `DEGRADED`: 단일 `fault_device=0~2`이면 해당 장치 Disable, `fault_device=3`이면 `DEGRADE_MASK` 대상 Disable
- `SAFE_MODE`: `output_enable=3'b000`, `actuator_enable=0`, `control_valid=0`
- `SAFE_MODE`는 자동 복구 금지
- 정상 입력 + `MANUAL_RESET` 명령이 있어야 복구 가능

---

## 9. 확정 레지스터 맵

주소 Base는 Vivado Address Editor에서 변경될 수 있다. Offset과 의미는 변경하지 않는다.

### 9.1 heartbeat_monitor_ip

| Offset | 이름 | 접근 | 의미 |
|---:|---|---|---|
| `0x00` | `CTRL` | RW/W1P | bit0 ENABLE, bit1 CLEAR_ALL(W1P), bit2 AUTO_RECOVER |
| `0x04` | `STATUS` | R | bit[2:0] ALIVE, bit[10:8] TIMEOUT |
| `0x08` | `TIMEOUT0` | RW | Device 0 Timeout clocks |
| `0x0C` | `TIMEOUT1` | RW | Device 1 Timeout clocks |
| `0x10` | `TIMEOUT2` | RW | Device 2 Timeout clocks |
| `0x14` | `LAST_COUNT0` | R | Device 0 경과 Count |
| `0x18` | `LAST_COUNT1` | R | Device 1 경과 Count |
| `0x1C` | `LAST_COUNT2` | R | Device 2 경과 Count |
| `0x20` | `IRQ_EN` | RW | bit[2:0] Timeout IRQ Enable |
| `0x24` | `IRQ_STATUS` | R/W1C | bit[2:0] Timeout Pending |

### 9.2 fault_manager_ip

| Offset | 이름 | 접근 | 의미 |
|---:|---|---|---|
| `0x00` | `CTRL` | RW/W1P | bit0 ENABLE, bit1 RESET_FAULT(W1P) |
| `0x04` | `FAULT_INPUT` | R | Timeout/Error/Critical 요약 |
| `0x08` | `CRITICAL_MASK` | RW | 모든 Fault 원인에 대한 Critical 장치 지정, 기본 `3'b100` |
| `0x0C` | `PERSIST_LIMIT` | RW | 지속 오류 판정 횟수 |
| `0x10` | `FAULT_LEVEL` | R | 0~3 |
| `0x14` | `FAULT_DEVICE` | R | 주요 고장 Device ID |
| `0x18` | `FAULT_CODE` | R | 최종 Fault Code |
| `0x1C` | `FAULT_COUNT` | R | 구현 시 packing 방식 명시 |
| `0x20` | `IRQ_EN` | RW | Fault/Level 변화 IRQ Enable |
| `0x24` | `IRQ_STATUS` | R/W1C | 오류 및 등급 변화 Pending |

`FAULT_COUNT` packing 권장:

```text
bit[7:0]   Device 0 count
bit[15:8]  Device 1 count
bit[23:16] Device 2 count
```

### 9.3 safety_controller_ip

| Offset | 이름 | 접근 | 의미 |
|---:|---|---|---|
| `0x00` | `CTRL` | RW/W1P | bit0 ENABLE, bit1 MANUAL_RESET(W1P) |
| `0x04` | `SYSTEM_STATE` | R | NORMAL/WARNING/DEGRADED/SAFE_MODE |
| `0x08` | `OUTPUT_ENABLE` | R | bit[2:0] 장치별 Enable |
| `0x0C` | `DEGRADE_MASK` | RW | DEGRADED에서 `fault_device=3`일 때 차단할 출력 |
| `0x10` | `RECOVERY_COUNT` | RW | 복구에 필요한 연속 정상 횟수 |
| `0x14` | `STATE_TIMER` | R | 현재 상태 유지 Count |
| `0x18` | `IRQ_EN` | RW | 상태 변화 IRQ Enable |
| `0x1C` | `IRQ_STATUS` | R/W1C | 상태 변화 Pending |

---

## 10. Fault 정책

우선순위는 높은 조건이 낮은 조건을 덮어쓴다.

장치별 현재 Fault와 Critical 조건:

```verilog
device_fault = timeout | error_flag | critical_fault;
critical_condition = |(device_fault & critical_mask);
```

1. `critical_condition != 0`
   - `fault_level = 3`
   - `fault_code = FAULT_CRITICAL`
2. 두 장치 이상에서 `device_fault` 발생
   - `fault_level = 3`
   - `fault_code = FAULT_MULTI_DEVICE`
3. Critical Mask가 없는 단일 장치 Fault가 `PERSIST_LIMIT` 이상 지속
   - `fault_level = 2`
4. Critical Mask가 없는 단일 장치의 일시 Fault
   - `fault_level = 1`
5. 모두 정상
   - `fault_level = 0`

`fault_code`와 `fault_device`의 결정 우선순위는 다음으로 고정한다.

```text
critical_condition       → FAULT_CRITICAL
critical_condition 없음,
2개 이상 device_fault   → FAULT_MULTI_DEVICE
단일 error_flag 또는
Mask 밖 critical_fault  → FAULT_ERROR_CODE
단일 timeout             → FAULT_TIMEOUT
Fault 없음               → FAULT_NONE
```

- 같은 단일 장치에 Timeout과 Error가 동시에 있으면 `FAULT_ERROR_CODE`를 출력한다.
- Level 1에서도 현재 원인에 맞는 `FAULT_ERROR_CODE` 또는 `FAULT_TIMEOUT`을 출력한다.
- `critical_condition`에 해당하는 장치가 하나이면 해당 Device ID를 출력한다.
- `critical_condition`에 해당하는 장치가 둘 이상이면 `FAULT_CRITICAL`, `MULTIPLE_OR_NONE`을 출력한다.
- Critical 조건 장치 하나와 일반 장치 Fault가 동시에 있으면 Critical 조건 장치 ID와 `FAULT_CRITICAL`을 출력한다.
- Critical이 없는 다중 Fault이면 `FAULT_MULTI_DEVICE`, `MULTIPLE_OR_NONE`을 출력한다.

Device 0 Timeout은 일시적으로 Level 1이 될 수 있으며 지속되면 Level 2가 된다.

기본 `CRITICAL_MASK=3'b100`이므로 Device 2의 Timeout, Error, Critical Fault는 모두 지속 횟수를 기다리지 않고 Level 3으로 처리한다.

일반 Fault 지속 Count는 `eval_tick=1`에서만 증가한다. 반면 Critical 조건과 다중 Fault 검출은 매 100MHz Clock에서 판정하므로 다음 Tick까지 대응을 미루지 않는다. 여기서 “즉시”는 0ns 조합 응답이 아니라 입력 동기화 지연, Fault Manager 1클럭, Safety Controller 1클럭 안에 결정적으로 차단한다는 뜻이다.

`PERSIST_LIMIT=0`은 1로 간주한다. 권장 초기값은 `PERSIST_LIMIT=5`다.
레지스터 폭이 8비트이므로 유효 범위는 `0~255`이고, 그 이상은 거부한다.

### 10.1 Level 1 관측 가능 시간

`PERSIST_LIMIT`은 **Level 1(WARNING)이 유지되는 시간을 그대로 결정한다.**

```text
Level 1 지속시간 = PERSIST_LIMIT × eval_tick 주기(1 ms)
PERSIST_LIMIT=5   ->   5 ms
PERSIST_LIMIT=255 -> 255 ms
```

MicroBlaze가 상태 변화를 감지하는 지연은 9600bps UART 송신 블로킹 때문에
**50 ms 이상**이다. 따라서 기본값 `PERSIST_LIMIT=5`에서는 Level 1이 이미 Level 2로
바뀐 뒤에 읽히며 `WARNING`이 UART/PC 어디에도 나타나지 않는다.
이는 RTL 결함이 아니라 샘플링 한계다.

- RTL Testbench에서는 `eval_tick`을 관측하므로 기본값으로도 Level 1이 보인다.
- 보드 시연에서 `WARNING`을 보여야 하면 `SET,PERSIST_LIMIT,255`로 올린다.
- Level 1은 **단일 비Critical 장치 Fault**에서만 발생한다. Device 2 Fault와
  2개 이상 동시 Fault는 우선순위 1·2에 걸려 설정과 무관하게 곧바로 Level 3이다.

---

## 11. Safety FSM 정책

```text
NORMAL
  ├─ Level 0 → NORMAL
  ├─ Level 1 → WARNING
  ├─ Level 2 → DEGRADED
  └─ Level 3 → SAFE_MODE

WARNING
  ├─ Level 0이 연속 RECOVERY_COUNT 이상 유지 → NORMAL
  ├─ Level 1 → WARNING
  ├─ Level 2 → DEGRADED
  └─ Level 3 → SAFE_MODE

DEGRADED
  ├─ Level 0이 연속 RECOVERY_COUNT 이상 유지 → NORMAL
  ├─ Level 1이 연속 RECOVERY_COUNT 이상 유지 → WARNING
  ├─ Level 2 → DEGRADED
  └─ Level 3 → SAFE_MODE

SAFE_MODE
  ├─ Fault 입력이 남아 있음 → 유지
  ├─ Fault Level이 0으로 복귀해도 자동 복귀 금지
  └─ fault_valid=1 + Level 0 + MANUAL_RESET → NORMAL
```

### 11.1 Recovery 정책 해석

- `NORMAL`은 Fault Level 0과만 대응한다.
- `WARNING`은 Fault Level 1과 대응한다.
- `DEGRADED`에서 오류가 완화되어도 현재 Fault Level에 맞는 상태까지만 복귀한다.
- 따라서 `fault_level=1`인 동안 `NORMAL` 상태가 되는 경로는 만들지 않는다.
- `SAFE_MODE`는 Fault가 사라져도 자동 복귀하지 않고, `fault_valid=1`인 Level 0 상태에서 `MANUAL_RESET`이 있어야 복귀한다.
- Recovery Counter는 `eval_tick=1`인 클럭에서만 증가하며 `fault_valid`를 Tick으로 사용하지 않는다.
- `RECOVERY_COUNT=0`은 1로 간주한다.
- `DEGRADED → WARNING` 경로를 사용할 때는 `RECOVERY_COUNT < PERSIST_LIMIT`이어야 한다.
- 권장 초기값은 `PERSIST_LIMIT=5`, `RECOVERY_COUNT=2`다.
- 같은 Fault가 완전히 제거되어 Level 2에서 Level 0으로 바뀌면 `DEGRADED → NORMAL` 직접 복귀가 정상이다.

`SAFE_MODE` 자동 복귀는 금지한다.

---

## 12. MicroBlaze 공통 원칙

MicroBlaze 담당:

- Timeout, Critical Mask, Persist Limit, Recovery Count 설정
- 각 IP Enable 및 IRQ Enable
- ISR에서 IRQ 원인 읽기
- W1C로 IRQ Clear
- 메인 루프에서 UART 출력 (FND/LCD 는 이번 빌드 미구현)
- Manual Recovery 명령
- **PC 대시보드 UART 프로토콜 송수신** (12.4)
- 필요 시 상태 Snapshot 저장

ISR에서는 다음만 한다.

```text
1. IRQ_STATUS 읽기
2. 원인을 전역 변수/큐에 저장
3. W1C Clear
4. 메인 루프 처리 플래그 설정
```

ISR 안에서 UART 문자열 출력, 긴 Delay, 전체 로그 출력은 금지한다.

### 12.1 Reset 기본값과 Disable 정책

AXI 설정 레지스터는 Reset 후 0일 수 있으므로 MicroBlaze 초기화가 끝날 때까지 출력은 안전값을 유지한다.

```text
Heartbeat Monitor enable=0
→ counter=0, alive=0, timeout=0, timeout_event=0

Fault Manager enable=0
→ fault_valid=0, fault_level=0, fault_device=3, fault_code=FAULT_NONE

Safety Controller enable=0
→ system_state=NORMAL, output_enable=000,
  actuator_enable=0, control_valid=0
```

- `TIMEOUTn=0`은 유효값 1로 간주한다.
- `PERSIST_LIMIT=0`과 `RECOVERY_COUNT=0`도 유효값 1로 간주한다.
- Heartbeat `IRQ_STATUS` W1C는 Pending만 Clear한다.
- Heartbeat `CLEAR_ALL` W1P는 Counter와 Timeout 상태를 Clear하며 IRQ Pending은 변경하지 않는다.
- Fault Manager `RESET_FAULT`는 현재 Fault가 하나라도 있으면 무시한다.
- 현재 Fault가 모두 없을 때만 `RESET_FAULT`가 Count, 과거 비교 정보와 Fault Manager Pending을 Clear한다.

### 12.2 MicroBlaze 초기화 순서

```text
1. 세 Custom IP ENABLE=0
2. 세 Custom IP IRQ_EN=0
3. TIMEOUT0~2 설정
4. CRITICAL_MASK 설정
5. PERSIST_LIMIT 설정
6. RECOVERY_COUNT 설정
7. DEGRADE_MASK 설정
8. Heartbeat CLEAR_ALL, Fault RESET_FAULT, 각 IRQ_STATUS W1C
9. AXI INTC 초기화 및 Handler 등록
10. Fault Manager와 Safety Controller Enable
11. Heartbeat Monitor Enable
12. 각 IP IRQ Enable
13. MicroBlaze Global Interrupt Enable
```

### 12.3 외부 입력 경로 — **미구현 (설계 의도 기록)**

> **상태 : 이번 빌드에 포함되지 않음.**
> Block Design 최상위 외부 포트는 `sys_clock`, `reset`(btnC), `usb_uart`,
> `led[15:0]` 뿐이다. 슬라이드 스위치·btnU·btnD는 BD에도 XDC에도 배선되어
> 있지 않고, `axi_gpio_0` / `axi_gpio_1` 은 둘 다 `C_ALL_OUTPUTS=1` (출력 전용)
> 이라 보드 SW/BTN을 읽을 수 없다.
> 아래 경로는 나중에 물리 I/O를 붙일 때 지켜야 할 **설계 규칙**으로 남긴다.
> 현재 구현에서 같은 기능은 전부 12.4의 UART 명령으로 수행한다.

```text
SW1/SW2/SW3
→ 2FF Synchronizer
→ 필요 시 Debounce
→ fault_manager_ip 입력

BTN_U
→ AXI GPIO 또는 Synchronizer/One-shot
→ MicroBlaze
→ safety_controller_ip CTRL.MANUAL_RESET W1P

BTN_D
→ AXI GPIO 또는 Synchronizer/One-shot
→ MicroBlaze
→ 세 IP의 IRQ_STATUS를 각각 W1C
```

외부 Switch/Button 동기화는 공통 Block Design 입력 조정부에서 담당한다. BTN_D는 Fault/Timeout 상태를 직접 지우는 RTL 신호가 아니다.

**현재 구현에서의 대체 경로**

| 12.3 설계상 입력 | 이번 빌드의 실제 경로 |
|---|---|
| `SW0` (Device 0 Heartbeat 중단) | `INJECT,TIMEOUT,0,ON` — MicroBlaze가 해당 Device Heartbeat 생성을 중단 |
| `SW1` (Device 1 Error) | `INJECT,ERROR,1,ON` — MicroBlaze가 `axi_gpio_0 CH1` 로 `error_flag` 구동 |
| `SW2` (Device 2 Critical) | `INJECT,CRITICAL,2,ON` — MicroBlaze가 `axi_gpio_0 CH2` 로 `critical_fault` 구동 |
| `BTN_U` (Manual Recovery) | `CMD,MANUAL_RESET` |
| `BTN_D` (IRQ Pending Clear) | `CMD,CLEAR_IRQ` |

즉 `axi_gpio_0` 은 "보드 스위치를 읽는 입력"이 아니라 **MicroBlaze가 스위치를
대신 흉내내는 출력**이다. Custom IP 입장에서 보이는 신호는 동일하므로
RTL 검증 결과는 물리 SW 경로를 붙여도 그대로 유효하다.

### 12.4 PC 대시보드 UART 프로토콜 계층

전체 규격은 03_MEMBER_C 11장에서 확정한다. 여기서는 MicroBlaze가 지켜야 할
공통 원칙만 둔다.

```text
FPGA → PC
  $MISSION,timestamp,state,level,device,code,alive,timeout,oe,actuator[,cv][,state_timer][,cnt0..2]
  $EVENT,timestamp,event_type[,arg...]
  $ACK,command[,arg...]
  $ERR,error_code[,description]

PC → FPGA
  GET,STATUS | GET,CONFIG
  SET,TIMEOUT,<dev>,<clk> | SET,CRITICAL_MASK | SET,PERSIST_LIMIT
  SET,RECOVERY_COUNT | SET,DEGRADE_MASK
  CMD,MANUAL_RESET | CMD,RESET_FAULT | CMD,CLEAR_IRQ | CMD,CLEAR_HEARTBEAT
  INJECT,ERROR|CRITICAL|TIMEOUT,<dev>,ON|OFF | INJECT,CLEAR,ALL
```

원칙:

- 프로토콜 계층은 **전적으로 MicroBlaze 책임**이다. Custom IP RTL에 프로토콜을
  넣지 않는다.
- `SET` 명령은 12.2 초기화 순서와 **같은 레지스터, 같은 값 처리 규칙**을 쓴다.
  `TIMEOUTn=0`, `PERSIST_LIMIT=0`, `RECOVERY_COUNT=0`은 12.1대로 1로 간주한다.
- `CMD,MANUAL_RESET` / `CMD,CLEAR_IRQ`는 12.3의 `BTN_U` / `BTN_D`와 등가 경로다.
  버튼과 PC 명령의 결과가 달라지면 안 된다.
  단, **이번 빌드에는 물리 버튼이 없으므로 UART 경로만 존재한다** (12.3 참고).
  나중에 버튼을 붙일 때 두 경로가 같은 펌웨어 함수를 호출하도록 구현한다.
- `CMD,MANUAL_RESET`은 11장 정책대로 `fault_valid=1` 이고 `fault_level=0`일 때만
  승인한다. 거부는 `$ERR`로 알린다. 무응답으로 두지 않는다.
- `CMD,RESET_FAULT`는 12.1대로 현재 Fault가 하나라도 있으면 거부한다.
- **수신한 모든 명령에 `$ACK` 또는 `$ERR`로 응답한다.** 미구현 명령도
  `$ERR,UNKNOWN_COMMAND`로 답한다.
- `$EVENT`의 인자값은 ISR이 아니라 메인 루프가 폴링으로 만든다. ISR은 Pending을
  W1C하고 플래그만 세운다 (12장 본문).
- UART 송신은 블로킹이다. 9600bps에서 `$MISSION` 한 줄이 약 73 ms 걸린다.
  이 동안에도 Heartbeat 생성이 끊기지 않도록 송신 함수 진입 전에 Heartbeat를
  갱신한다.

---

## 13. 공통 검증 시나리오

| ID | 입력 | 예상 결과 |
|---|---|---|
| `T01` | 모든 Heartbeat 정상 | `NORMAL`, all enable |
| `T02` | Device 0 Heartbeat 1회 누락 | `WARNING` 또는 정책상 유지 |
| `T03` | Device 0 Heartbeat 지속 중단 | `DEGRADED`, Device 0 disable |
| `T04` | Device 1 일시 Error | `WARNING` |
| `T05` | Device 2 Timeout/Error/Critical Fault | 결정된 Clock 지연 안에 `SAFE_MODE`, actuator off |
| `T06` | Device 0과 1 동시 Fault | `SAFE_MODE` 또는 Level 3 |
| `T07` | DEGRADED에서 Level 1이 Recovery Count 동안 유지 | `WARNING` 복귀, `NORMAL` 금지 |
| `T08` | DEGRADED에서 Level 0이 Recovery Count 동안 유지 | `NORMAL` 복귀 |
| `T09` | SAFE_MODE에서 Fault 제거 | SAFE_MODE 유지 |
| `T10` | Level 0 + Manual Reset | `NORMAL` 복귀 |
| `T11` | IRQ_STATUS 미클리어 | IRQ High 유지 |
| `T12` | W1C 일부 비트 Clear | 지정 비트만 Clear |
| `T13` | Device 1 단일 지속 Fault | `DEGRADED`, Device 1만 disable |
| `T14` | `fault_device=3`인 DEGRADED 입력 | `DEGRADE_MASK` 대상 disable |
| `T15` | 각 IP `ENABLE=0` | 12.1의 안전 출력과 일치 |
| `T16` | Fault/Safety IRQ 동시 발생 | 두 ISR 모두 처리 후 각 W1C로 IRQ Low |

---

## 14. AI에게 항상 요구할 출력 방식

이 프로젝트에서 AI가 코드나 설계를 제안할 때 다음 순서를 지킨다.

1. 변경 대상 파일과 변경 이유
2. 변경되는 인터페이스가 공통 명세와 일치하는지 확인
3. RTL 코드
4. Testbench 또는 검증 방법
5. 예상 파형
6. 통합 시 주의점
7. 미확정 사항

AI는 다음 행동을 해서는 안 된다.

- 사용자 승인 없이 IP 이름 변경
- 사용자 승인 없이 레지스터 Offset 변경
- 2비트 State/Fault Level을 다른 폭으로 변경
- Pulse IRQ로 임의 변경
- SAFE_MODE 자동 복구 추가
- 새 IP를 필수 범위에 임의 추가
- 실제 구현 전 성능 수치를 실측값처럼 단정
- 다른 팀원 담당 IP 내부 코드를 대신 확정

---

## 15. 버전 및 변경 관리

공통 인터페이스 변경이 필요한 경우:

```text
[CHANGE REQUEST]
요청자:
변경 항목:
기존:
변경안:
변경 이유:
영향 IP:
Vitis 영향:
Testbench 영향:
팀 승인:
```

팀 승인을 받기 전까지 기존 명세를 유지한다.

파일명 권장:

```text
heartbeat_monitor_core.v
heartbeat_monitor_axi.v
fault_manager_core.v
fault_manager_axi.v
safety_controller_core.v
safety_controller_axi.v
eval_tick_generator.v

tb_heartbeat_monitor_core.v
tb_fault_manager_core.v
tb_safety_controller_core.v
tb_eval_tick_generator.v
tb_mission_soc_top.v

mission_ip_regs.h
interrupt.c
main.c
```
