# 팀원 A AI 프로젝트 지침 — heartbeat_monitor_ip 담당

> 이 문서는 `heartbeat_monitor_ip` 담당자가 자신의 AI 프로젝트에 넣는 전용 지침이다.  
> 팀 공통 명세가 최우선이며, 여기서는 Heartbeat 감시 IP 범위만 담당한다.

---

## 0. 3인 팀 내 역할

팀원 A는 `heartbeat_monitor_ip`의 주 담당자다.  
전체 Block Design과 최종 통합은 A·B·C 세 명이 함께 수행한다.

A의 통합 지원 책임:

- Heartbeat 또는 Device Simulator 입력 생성
- Timeout 설정용 Vitis 함수 제공
- Heartbeat/Timeout Fault Injection 시나리오 준비
- 통합 시 `alive`, `timeout`, IRQ 동작 확인

---

## 1. 담당 범위

필수 담당:

- `heartbeat_monitor_core.v`
- `heartbeat_monitor_axi.v` 또는 Vivado AXI Template 수정
- 3채널 Heartbeat 입력 동기화
- 상승 에지 검출
- 장치별 Timeout Counter
- `alive[2:0]`, `timeout[2:0]` 생성
- AXI4-Lite 레지스터 구현
- Level IRQ + `IRQ_STATUS` W1C
- Core 단위 Testbench
- AXI Read/Write 검증
- 통합용 포트 및 사용법 문서화

담당하지 않는 범위:

- Fault Level 정책 결정
- Safety FSM 상태 전이
- UART 출력 문구 및 PC 대시보드 프로토콜 (MicroBlaze 펌웨어 담당)
- 다른 IP 레지스터 구현
- Event Logger 구현

### 1.1 PC 대시보드가 이 IP에서 쓰는 값

프로토콜 자체는 구현하지 않지만, 아래 레지스터가 그대로 PC 화면에 나가므로
이름·비트 위치·동작을 바꾸면 앱이 깨진다. 전체 규격은 03_MEMBER_C 11장.

| PC 쪽 항목 | 출처 |
|---|---|
| `$MISSION` 6번 필드 `alive` | `STATUS[2:0]` |
| `$MISSION` 7번 필드 `timeout` | `STATUS[10:8]` |
| `$EVENT,...,HEARTBEAT_TIMEOUT,<dev>` | `timeout[i]` 가 0 → 1 로 바뀐 순간 |
| `SET,TIMEOUT,<dev>,<clocks>` 명령 | `TIMEOUT0/1/2` (`0x08`/`0x0C`/`0x10`) 쓰기 |
| `CMD,CLEAR_HEARTBEAT` 명령 | `CTRL.bit1` (`CLEAR_ALL`) W1P |
| `CMD,CLEAR_IRQ` 명령 | `IRQ_STATUS` W1C |

추가로 요구되는 사항:

- `alive`와 `timeout`은 **하위 3비트만** 유효해야 한다. 상위 비트에 쓰레기가 남으면
  PC 앱의 장치 패널이 잘못 표시된다.
- MicroBlaze가 `heartbeat_async[2:0]`를 AXI GPIO로 생성한다. PC의
  `INJECT,TIMEOUT,<dev>,ON` 은 GPIO로 Timeout을 직접 넣는 것이 아니라
  **해당 채널의 Heartbeat 생성을 멈추는 것**이다. 즉 실제 `TIMEOUTn` Counter가
  돌아 Timeout을 판정해야 한다 (04 체크리스트 1.1 Freeze).
- 따라서 `LAST_COUNTn`이 실제 경과 시간을 반영해야 한다. MicroBlaze 메인 루프는
  UART 송신 때문에 수십 ms씩 멈추므로, 소프트웨어 시간이 아니라 이 IP의
  하드웨어 Counter가 시간 판정의 기준이다.

---

## 2. 입력과 출력

### Core 입력

```verilog
input  wire        clk;
input  wire        reset;
input  wire        enable;
input  wire [2:0]  heartbeat_async;
input  wire [2:0]  device_enable;
input  wire [31:0] timeout0;
input  wire [31:0] timeout1;
input  wire [31:0] timeout2;
input  wire        clear_all_pulse;
input  wire        auto_recover;
```

### Core 출력

```verilog
output wire [2:0]  alive;
output wire [2:0]  timeout;
output wire [31:0] last_count0;
output wire [31:0] last_count1;
output wire [31:0] last_count2;
output wire [2:0]  timeout_event;
```

`timeout_event[i]`는 Timeout 상태가 0→1로 바뀌는 순간의 1클럭 Pulse다.  
최종 IRQ는 AXI wrapper의 `IRQ_STATUS`에 Latch하여 Level로 만든다.

5일 기본 구현에서는 AXI wrapper가 다음과 같이 연결한다.

```text
CTRL.bit0 ENABLE → core.enable
device_enable    → 3'b111 고정
```

`device_enable`은 감시 설정이다. Safety Controller의 `output_enable`과 연결하지 않는다.

---

## 3. 필수 동작

### 3.1 입력 동기화

각 Heartbeat 입력마다:

```text
heartbeat_async
→ 2FF Synchronizer
→ rising edge detector
→ heartbeat_pulse
```

비동기 입력을 Counter/FSM에 직접 사용하지 않는다.

### 3.2 Counter

- `enable == 0`: 모든 Counter와 상태를 Clear하고 안전한 Disable 출력을 유지
- `device_enable[i] == 0`: Counter, Timeout, Timeout Event를 0으로 Clear하고 Timeout 판단 제외
- `heartbeat_pulse[i] == 1`: Counter 0으로 초기화
- 그 외: Counter 증가
- `counter >= timeout_setting`: Timeout Set
- Counter Saturation 권장
- Overflow wraparound 금지
- `timeout_setting == 0`: 유효값 1로 간주

### 3.3 Alive

```text
device_enable=1 && timeout=0 → alive=1
device_enable=1 && timeout=1 → alive=0
device_enable=0 → alive=0
enable=0 → alive=0
```

비활성 장치를 Alive로 표시하지 않는다.

### 3.4 Timeout 복구

- `AUTO_RECOVER=1`: 정상 Heartbeat 수신 시 Timeout Clear
- `AUTO_RECOVER=0`: `CLEAR_ALL`로만 Timeout Clear
- 두 정책이 동시에 충돌하지 않도록 우선순위를 명시

권장 우선순위:

```text
reset
> enable=0 또는 device_enable=0
> clear_all
> heartbeat auto recovery
> timeout set
> counter increment
```

`IRQ_STATUS` W1C는 IRQ Pending만 Clear하며 Timeout 상태와 Counter를 변경하지 않는다.

`CLEAR_ALL` W1P는 모든 Counter와 Timeout 상태를 Clear하지만 `IRQ_STATUS`는 변경하지 않는다. IRQ Pending은 `IRQ_STATUS` W1C로 별도 Clear한다.

### 3.5 Disable 출력

```text
enable=0
→ counter=0
→ timeout=0
→ alive=0
→ timeout_event=0
```

Disable 중에는 새로운 IRQ Pending을 Set하지 않는다.

---

## 4. 확정 레지스터 맵

| Offset | 이름 | 접근 | 구현 |
|---:|---|---|---|
| `0x00` | `CTRL` | RW/W1P | bit0 ENABLE, bit1 CLEAR_ALL, bit2 AUTO_RECOVER |
| `0x04` | `STATUS` | R | bit[2:0] ALIVE, bit[10:8] TIMEOUT |
| `0x08` | `TIMEOUT0` | RW | Device 0 |
| `0x0C` | `TIMEOUT1` | RW | Device 1 |
| `0x10` | `TIMEOUT2` | RW | Device 2 |
| `0x14` | `LAST_COUNT0` | R | Counter 0 |
| `0x18` | `LAST_COUNT1` | R | Counter 1 |
| `0x1C` | `LAST_COUNT2` | R | Counter 2 |
| `0x20` | `IRQ_EN` | RW | bit[2:0] |
| `0x24` | `IRQ_STATUS` | R/W1C | bit[2:0] |

`CTRL.bit0 ENABLE`은 전체 IP Enable이다. 전체 Disable이면 Counter를 단순 Hold하지 않고 0으로 Clear하며 `alive`, `timeout`, `timeout_event`를 모두 0으로 만든다.

`CTRL.bit1 CLEAR_ALL`은 W1P다. AXI 레지스터 값으로 저장하지 말고 내부 1클럭 Pulse를 생성한다.

Reset 후 `CTRL`, `TIMEOUT0~2`, `IRQ_EN`, `IRQ_STATUS`는 0이다. MicroBlaze는 Timeout을 먼저 설정한 뒤 마지막에 ENABLE과 IRQ_EN을 켠다.

---

## 5. IRQ 규칙

```verilog
assign irq = |(irq_status_reg[2:0] & irq_en_reg[2:0]);
```

- Timeout Event 발생 시 해당 `IRQ_STATUS` 비트 Set
- W1C Write 시 해당 비트 Clear
- Set과 Clear가 같은 클럭이면 Set 우선 권장
- IRQ는 Status가 남아 있는 동안 High
- W1C는 Pending만 지우며 Timeout 복구 명령으로 사용하지 않음

---

## 6. 필수 Testbench

### Core TB

1. Reset 후 모든 출력 초기값
2. Device 0 정상 Heartbeat 반복
3. Device 0 Heartbeat 중단 후 정확한 Count에서 Timeout
4. Device 0/1/2 서로 다른 Timeout
5. 비활성 Device의 Counter/Timeout/Event/Alive가 모두 0
6. Counter Saturation
7. AUTO_RECOVER=1 복구
8. AUTO_RECOVER=0에서 Heartbeat만으로 Timeout이 지워지지 않음
9. IRQ_STATUS W1C 후에도 Timeout 상태 유지
10. CLEAR_ALL 후 Counter/Timeout Clear, IRQ Pending 유지
11. 두 장치 동시 Timeout
12. `timeout_setting=0`을 1로 처리
13. `enable=0` 안전 출력
14. `enable` 재활성화 후 Counter가 0에서 재시작

### AXI 검증

1. TIMEOUT 설정 Write/Read-back
2. CTRL ENABLE/AUTO_RECOVER
3. CLEAR_ALL W1P
4. STATUS Read-only
5. IRQ_EN
6. IRQ_STATUS W1C
7. 일부 비트만 W1C
8. Reset 기본값과 MicroBlaze 설정 순서

---

## 7. 팀에 전달할 산출물

```text
heartbeat_monitor_core.v
heartbeat_monitor_axi.v 또는 패키징 IP
tb_heartbeat_monitor_core.v
tb_heartbeat_monitor_axi.v (가능하면)
heartbeat_monitor_register_map.md
heartbeat_monitor_waveform.png
heartbeat_monitor_integration.md
```

`integration.md`에는 다음을 반드시 적는다.

- Clock/Reset
- Heartbeat 입력 극성
- `alive`, `timeout` 의미
- `device_enable=3'b111` 고정 및 `output_enable`과 독립임
- IRQ 연결
- AXI Base Address는 Vivado에서 확정
- 테스트 완료 항목
- 알려진 제한사항

---

## 8. AI 작업 원칙

AI가 새로운 기능을 제안해도 필수 동작이 완료되기 전에는 추가하지 않는다.

AI에게 코드 작성을 요청할 때 항상 다음을 요구한다.

```text
공통 명세의 레지스터 Offset과 신호명을 그대로 유지할 것.
Core RTL과 AXI Wrapper를 가능하면 분리할 것.
Latch, Counter overflow, W1P/W1C, Set/Clear 동시 발생 우선순위를 설명할 것.
전체 코드와 함께 self-checking Testbench를 제공할 것.
```
