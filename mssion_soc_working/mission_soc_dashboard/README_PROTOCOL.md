# UART Protocol 규격 — MicroBlaze 구현용

Mission SoC Dashboard 와 Basys 3 MicroBlaze 사이의 UART 프로토콜 규격이다.
MicroBlaze 펌웨어 담당자가 이 문서만 보고 그대로 구현할 수 있도록 정리했다.

## 위치

```text
FPGA (MicroBlaze + AXI UARTLite)  ⇄  USB Serial  ⇄  PC (Python 앱)
```

## 기본 규칙

| 항목 | 값 |
|---|---|
| **Baudrate** | **9600 8N1** (AXI UARTLite 기본값). 앱에서도 9600 을 선택한다 |
| 인코딩 | ASCII (UTF-8 호환) |
| 구분자 | 쉼표 `,` |
| 줄 종료 | `\n` (LF). `\r\n` 도 허용 |
| 최대 줄 길이 | 4096 bytes. 초과분은 PC 가 폐기한다 |
| 접두어 | `$MISSION`, `$EVENT`, `$ACK`, `$ERR` |
| 그 외 | `$` 로 시작하지 않는 줄은 디버그 문자열로 간주해 Raw Log 에 기록 |

앱의 Baudrate 기본값은 115200 이지만 **보드는 9600 이다.** 연결 전에 9600 으로
바꾼다. 틀리면 글자가 전부 깨져 보인다.

**필드 순서와 명령 이름은 통합 후 변경하지 않는다** (03_MEMBER_C 11장 = 팀 확정본).
이 문서와 03_MEMBER_C 11장이 다르면 03 이 우선이다.

---

# 1. FPGA → Python

## 1.1 `$MISSION` — 주기 상태 보고

```text
$MISSION,timestamp,state,fault_level,fault_device,fault_code,alive,timeout,output_enable,actuator_enable[,control_valid][,state_timer][,fault_count0][,fault_count1][,fault_count2]
```

예시:

```text
$MISSION,1250,SAFE_MODE,3,2,3,0x03,0x04,0x00,0
$MISSION,1250,SAFE_MODE,3,2,3,0x03,0x04,0x00,0,0,3245,0,0,1
```

### 필드

| # | 이름 | 형식 | 의미 |
|--:|---|---|---|
| 1 | `timestamp` | 0 이상 정수 | MicroBlaze 기준 밀리초 |
| 2 | `state` | 문자열 | `NORMAL` / `WARNING` / `DEGRADED` / `SAFE_MODE` |
| 3 | `fault_level` | 0~3 | 00 공통명세 7.2 |
| 4 | `fault_device` | 0~3 | 00 공통명세 7.4. `3` = `MULTIPLE_OR_NONE` |
| 5 | `fault_code` | 0x00~0x05 | 00 공통명세 7.3 |
| 6 | `alive` | 3비트 마스크 | bit0=Device0, bit1=Device1, bit2=Device2 |
| 7 | `timeout` | 3비트 마스크 | 동일 |
| 8 | `output_enable` | 3비트 마스크 | 동일 |
| 9 | `actuator_enable` | 0 / 1 | |
| 10 | `control_valid` | 0 / 1 | **선택** |
| 11 | `state_timer` | 정수 | **선택**. 현재 상태 유지 Count |
| 12~14 | `fault_count0~2` | 0~255 | **선택**. 장치별 지속 Count |

- **1~9 번은 필수.** 10 번 이후는 없어도 된다.
- 10진수와 `0x` 16진수를 섞어 써도 된다. PC 가 둘 다 파싱한다.
- 마스크는 하위 3비트만 사용한다.

### 인코딩 표

```text
state              fault_level                fault_code
NORMAL             0 = LEVEL_0_NORMAL         0x00 = FAULT_NONE
WARNING            1 = LEVEL_1_WARNING        0x01 = FAULT_TIMEOUT
DEGRADED           2 = LEVEL_2_DEGRADED       0x02 = FAULT_ERROR_CODE
SAFE_MODE          3 = LEVEL_3_SAFE           0x03 = FAULT_CRITICAL
                                              0x04 = FAULT_MULTI_DEVICE
fault_device                                  0x05 = FAULT_RECOVERY_REQUIRED
0 = DEVICE_0
1 = DEVICE_1
2 = DEVICE_2
3 = MULTIPLE_OR_NONE
```

### 권장 전송 주기

메인 루프에서 100~500 ms 주기. ISR 안에서 UART 를 출력하지 않는다
(00 공통명세 12장).

---

## 1.2 `$EVENT` — 상태 변화 이벤트

```text
$EVENT,timestamp,event_type[,arg0][,arg1][,arg2]
```

예시:

```text
$EVENT,1300,FAULT_CHANGE,2,0,1
$EVENT,1301,STATE_CHANGE,DEGRADED
$EVENT,1500,STATE_CHANGE,SAFE_MODE
$EVENT,1700,HEARTBEAT_TIMEOUT,0
```

### 권장 `event_type`

| 이름 | 인자 | 발생 시점 |
|---|---|---|
| `FAULT_CHANGE` | level, device, code | Fault Manager `IRQ_STATUS` Set |
| `STATE_CHANGE` | state 문자열 | Safety Controller 상태 전이 |
| `HEARTBEAT_TIMEOUT` | device | Heartbeat Timeout Event |
| `MANUAL_RESET` | 결과 | Manual Recovery 시도 |

`event_type` 이나 인자 수가 위와 달라도 PC 는 죽지 않는다. 원본을 Event Log 에
그대로 보존하므로 새 이벤트를 자유롭게 추가해도 된다.

---

## 1.3 `$ACK` — 명령 성공

```text
$ACK,command[,arg0][,arg1]
```

예시:

```text
$ACK,SET,PERSIST_LIMIT,5
$ACK,CMD,MANUAL_RESET
$ACK,GET,STATUS
$ACK,INJECT,CRITICAL,2,ON
```

`GET,STATUS` 에 대해서는 `$ACK` 뒤에 `$MISSION` 한 줄을 이어 보내는 것을 권장한다.

---

## 1.4 `$ERR` — 명령 실패

```text
$ERR,error_code[,description]
```

예시:

```text
$ERR,MANUAL_RESET,FAULT_ACTIVE
$ERR,INVALID_VALUE,PERSIST_LIMIT
$ERR,UNKNOWN_COMMAND
$ERR,RESET_FAULT,FAULT_ACTIVE
```

### 권장 `error_code`

| 코드 | 의미 |
|---|---|
| `UNKNOWN_COMMAND` | 지원하지 않는 명령. PC 가 "지원하지 않는 기능" 으로 표시 |
| `INVALID_VALUE` | 인자 범위 초과 |
| `FAULT_ACTIVE` | 활성 Fault 때문에 명령이 거부됨 |
| `FAULT_INVALID` | `fault_valid=0` 이라 판단 불가 |

---

## 1.5 `$IRQ` — IRQ_EN / IRQ_STATUS 스냅샷

`GET,IRQ` 에 대한 응답이다. `$ACK,GET,IRQ` 다음 줄에 나온다.

```text
$IRQ,<en_mask>,<hb_status>,<fm_status>,<sc_status>
```

| 필드 | 뜻 | 폭 |
|---|---|---|
| `en_mask` | IRQ_EN 묶음. bit0=A(heartbeat), bit1=B(fault), bit2=C(safety) | 3비트 |
| `hb_status` | heartbeat_monitor `IRQ_STATUS` (Device 별 Timeout Pending) | 3비트 |
| `fm_status` | fault_manager `IRQ_STATUS` (Fault Change Pending) | 1비트 |
| `sc_status` | safety_controller `IRQ_STATUS` (State Change Pending) | 1비트 |

예시:

```text
$IRQ,0x07,0x00,0x00,0x00     평상시. ISR 이 즉시 W1C 해서 Pending 은 항상 0
$IRQ,0x00,0x00,0x01,0x01     IRQ_EN 을 끈 상태. B/C Pending 이 래치돼 있다
```

**평상시 status 는 항상 0 이다.** ISR 이 인터럽트 진입 즉시 W1C 하기 때문이다.
0 이 아닌 값을 보려면 `SET,IRQ_EN,0` 으로 irq 핀을 막아 ISR 을 멈춰야 한다.
IRQ_STATUS 의 Set 은 IRQ_EN 과 무관하므로 Pending 이 그대로 쌓인다
(`rtl/fault_manager_axi.v` : `assign irq = reg_irq_status & reg_irq_en;`).

이것이 `CMD,CLEAR_IRQ` 의 W1C 동작을 검증하는 유일한 방법이다
(05 보드 시나리오 15번).

---

## 1.6 디버그 문자열

```text
Boot complete
Interrupt controller initialized
Unknown message
```

`$` 로 시작하지 않으면 PC 가 Raw Log 에만 기록한다. 자유롭게 써도 된다.

---

# 2. Python → FPGA

모든 명령은 `\n` 으로 끝난다. 대소문자는 명령 이름 기준 대문자를 쓴다.

## 2.1 조회

| 명령 | 기대 응답 |
|---|---|
| `GET,STATUS` | `$ACK,GET,STATUS` + `$MISSION,...` |
| `GET,CONFIG` | `$ACK,GET,CONFIG` + 설정 값 `$ACK` 들 (`SET,IRQ_EN` 포함) |
| `GET,IRQ` | `$ACK,GET,IRQ` + `$IRQ,...` (1.5 참조) |

## 2.2 설정

```text
SET,TIMEOUT,<device>,<clocks>      device: 0~2, clocks: 0~0xFFFFFFFF
SET,CRITICAL_MASK,<mask>           mask: 0x00~0x07
SET,PERSIST_LIMIT,<value>          value: 0~255
SET,RECOVERY_COUNT,<value>         value: 0~65535
SET,DEGRADE_MASK,<mask>            mask: 0x00~0x07
SET,IRQ_EN,<mask>                  mask: 0x00~0x07 (bit0=A, bit1=B, bit2=C)
```

예시:

```text
SET,TIMEOUT,0,30000000
SET,CRITICAL_MASK,0x04
SET,PERSIST_LIMIT,5
SET,RECOVERY_COUNT,2
SET,DEGRADE_MASK,0x01
SET,IRQ_EN,0x07
```

### 대응 레지스터

| 명령 | IP | Offset |
|---|---|---|
| `SET,TIMEOUT,0` | heartbeat_monitor | `0x08` |
| `SET,TIMEOUT,1` | heartbeat_monitor | `0x0C` |
| `SET,TIMEOUT,2` | heartbeat_monitor | `0x10` |
| `SET,CRITICAL_MASK` | fault_manager | `0x08` |
| `SET,PERSIST_LIMIT` | fault_manager | `0x0C` |
| `SET,RECOVERY_COUNT` | safety_controller | `0x10` |
| `SET,DEGRADE_MASK` | safety_controller | `0x0C` |
| `SET,IRQ_EN` bit0 | heartbeat_monitor | `0x20` |
| `SET,IRQ_EN` bit1 | fault_manager | `0x20` |
| `SET,IRQ_EN` bit2 | safety_controller | `0x18` |

### 값 처리 규칙

- `TIMEOUTn = 0`, `PERSIST_LIMIT = 0`, `RECOVERY_COUNT = 0` 은 **유효값 1** 로 간주
  (00 공통명세 12.1)
- 권장 초기값: `CRITICAL_MASK=0x04`, `PERSIST_LIMIT=5`,
  `RECOVERY_COUNT=2`, `DEGRADE_MASK=0x01`
- `DEGRADED → WARNING` 경로를 쓰려면 `RECOVERY_COUNT < PERSIST_LIMIT`
  (03_MEMBER_C 6장). PC 는 위반 시 경고만 하고 전송은 막지 않는다
- `IRQ_EN` 은 기본 `0x07`(전부 켬)이다. **검증 목적으로만 끄고 반드시 되돌린다.**
  꺼 둔 동안은 ISR 이 돌지 않아 상태 Snapshot 이 쌓이지 않으므로 짧게 스쳐 가는
  전이(WARNING 등)를 놓친다. 메인 루프 폴링 백스톱은 살아 있어 상태 전이 자체는
  계속 `$EVENT` 로 나간다

## 2.3 제어

| 명령 | 대응 동작 |
|---|---|
| `CMD,MANUAL_RESET` | safety_controller `CTRL.bit1` W1P |
| `CMD,CLEAR_IRQ` | 세 IP `IRQ_STATUS` 각각 W1C |
| `CMD,CLEAR_HEARTBEAT` | heartbeat_monitor `CTRL.bit1` (CLEAR_ALL) W1P |
| `CMD,RESET_FAULT` | fault_manager `CTRL.bit1` W1P |

### 거부 조건

```text
CMD,MANUAL_RESET
  fault_valid=1 이고 fault_level=0 일 때만 승인
  아니면 $ERR,MANUAL_RESET,FAULT_ACTIVE

CMD,RESET_FAULT
  현재 device_fault 가 하나라도 있으면 무시
  $ERR,RESET_FAULT,FAULT_ACTIVE
```

`CLEAR_IRQ` 는 Pending 만 지운다. Fault / Timeout 상태는 바뀌지 않는다.

### 주입 성립 시점 (시나리오 작성 시 주의)

| 주입 | 성립 시점 |
|---|---|
| `INJECT,ERROR,<dev>` | **즉시** (AXI GPIO → `error_flag`) |
| `INJECT,CRITICAL,<dev>` | **즉시** (AXI GPIO → `critical_fault`) |
| `INJECT,TIMEOUT,<dev>` | 그 장치의 `TIMEOUT<dev>` 만큼 뒤. 기본 D0 0.3초 / D1 0.6초 / D2 0.15초 |

`TIMEOUT` 을 켠 직후에 `CMD,RESET_FAULT` 같은 "Fault 가 있어야 거부되는" 명령을
보내면 아직 Fault 가 없어 `$ACK` 가 온다. `$EVENT,...,HEARTBEAT_TIMEOUT,<dev>`
또는 `fault_level >= 1` 을 확인한 뒤 보내야 한다.

같은 이유로 `TIMEOUT` + `ERROR` 조합은 **동시 다중 Fault 가 아니다.** 진짜
동시 다중을 만들려면 `INJECT,ERROR,0,ON` + `INJECT,ERROR,1,ON` 처럼 즉시 성립
주입 두 개를 써야 한다.

평상시엔 ISR 이 먼저 W1C 해 버려 지울 Pending 자체가 없다. 그래서 `$ACK` 만으로는
W1C 가 동작한다는 증거가 되지 않는다. 검증하려면 `SET,IRQ_EN,0` → 고장 주입 →
`GET,IRQ` 로 Pending 확인 → `CMD,CLEAR_IRQ` → `GET,IRQ` 로 0 확인 순으로 밟는다.
`CLEAR_HEARTBEAT` 는 Counter 와 Timeout 만 지우고 IRQ Pending 은 건드리지 않는다.

## 2.4 Fault Injection (확장)

```text
INJECT,ERROR,<device>,ON|OFF
INJECT,CRITICAL,<device>,ON|OFF
INJECT,TIMEOUT,<device>,ON|OFF
INJECT,CLEAR,ALL
```

`device` 는 0~2.

### 구현 (확정)

```c
/* axi_gpio_0 CH1 = error_flag[2:0], CH2 = critical_fault[2:0]
   axi_gpio_1 CH1 = heartbeat[2:0]  */
Xil_Out32(GPIO0_BASE + 0x00, error_mask    & 0x7);
Xil_Out32(GPIO0_BASE + 0x08, critical_mask & 0x7);
```

`INJECT,TIMEOUT` 은 **GPIO 로 timeout 을 직접 주입하지 않는다.** 해당 Device 의
Heartbeat 생성을 멈춰서 `heartbeat_monitor_ip` 가 `TIMEOUTn` 초과를 스스로 판정하게
한다 (04 체크리스트 1.1 Freeze). 따라서 즉시 반응하지 않고
Device 0 = 300 ms, Device 1 = 600 ms, Device 2 = 150 ms 뒤에 반응한다.

지원하지 않는 명령은 `$ERR,UNKNOWN_COMMAND` 를 보내면 된다.
PC 는 그것을 받아 "지원하지 않는 기능" 으로 표시할 뿐 오류로 처리하지 않는다.

---

# 3. 구현 체크리스트

```text
□ AXI UARTLite Baudrate 를 PC 앱과 일치시켰는가 (9600)
□ $MISSION 필수 9개 필드를 명세 순서대로 보내는가
□ 마스크는 하위 3비트만 쓰는가
□ 줄 끝에 \n 을 붙이는가
□ ISR 안에서 UART 출력을 하지 않는가 (00 공통명세 12장)
□ 상태 변화 시 $EVENT 를 보내는가
□ 모든 수신 명령에 $ACK 또는 $ERR 로 응답하는가
□ MANUAL_RESET 을 fault_valid=1 && fault_level=0 에서만 승인하는가
□ RESET_FAULT 를 활성 Fault 상태에서 거부하는가
□ TIMEOUTn=0, PERSIST_LIMIT=0, RECOVERY_COUNT=0 을 1 로 처리하는가
```

---

# 4. 최소 구현 예시

```c
#include <stdio.h>
#include "xil_printf.h"

/* 주기 상태 보고. 메인 루프에서 호출한다. */
void send_mission(u32 ts, const char *state,
                  u8 level, u8 device, u8 code,
                  u8 alive, u8 timeout, u8 oe, u8 actuator)
{
    xil_printf("$MISSION,%u,%s,%d,%d,%d,0x%02X,0x%02X,0x%02X,%d\r\n",
               ts, state, level, device, code, alive, timeout, oe, actuator);
}

/* 상태 전이 이벤트 */
void send_state_change(u32 ts, const char *state)
{
    xil_printf("$EVENT,%u,STATE_CHANGE,%s\r\n", ts, state);
}

void send_ack(const char *cmd, const char *a0)
{
    if (a0) xil_printf("$ACK,%s,%s\r\n", cmd, a0);
    else    xil_printf("$ACK,%s\r\n", cmd);
}

void send_err(const char *code, const char *desc)
{
    if (desc) xil_printf("$ERR,%s,%s\r\n", code, desc);
    else      xil_printf("$ERR,%s\r\n", code);
}
```

수신은 UARTLite 에서 한 글자씩 모아 `\n` 이 오면 파싱한다.
버퍼 크기를 넘으면 그 줄을 버리고 다음 `\n` 까지 건너뛴다.
