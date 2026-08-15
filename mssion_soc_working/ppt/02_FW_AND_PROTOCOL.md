# 02. 소프트웨어 — Vitis 펌웨어 · UART 프로토콜 · Python 대시보드

세 계층이 한 줄의 ASCII CSV로 묶여 있다. 어느 한쪽만 바뀌면 즉시 깨진다.

```text
Custom IP (AXI 레지스터)  ←→  Vitis 펌웨어  ←UART 9600 8N1→  Python 앱
   Offset 정본:              mission_ip_regs.h
   프로토콜 구현:            uart_proto.c            protocol.py / command_builder.py
```

---

## 1. Vitis 프로젝트 구성

```text
SOC_Pr_Vitis/
  mission_soc_wrapper.xsa       하드웨어 명세 (플랫폼 재생성용)
  mission_soc/vitis-comp.json   플랫폼 구성 참조본
  soc_prj/
    vitis-comp.json
    src/
      main.c              부팅 13단계 + 메인 루프 + $EVENT 변화 감지
      mission_ip_regs.h   Offset / 인코딩 / 기본값 정본
      mission_intr.c/.h   AXI INTC + ISR 3개 + Snapshot Ring
      uart_proto.c/.h     프로토콜 송수신 (파서 + 출력)
      hb_gen.c/.h         Heartbeat 생성 (axi_gpio_1)
      hb_regs.c           heartbeat_monitor 드라이버 (A 검증)
      fm_regs.c           fault_manager 드라이버   (B 검증)
      sc_regs.c           safety_controller 드라이버 (C 검증)
      platform.c/.h , lscript.ld , CMakeLists.txt
```

**Linux에서 생성된 `build` / `_ide` / `export` / BSP 산출물은 저장소에 없다** (OS·절대경로 종속).
Windows에서는 `SOC_Pr_Vitis/mission_soc_wrapper.xsa` 로 플랫폼을 다시 만든다.
원본 프로젝트 경로 흔적: `/home/user7/workspace_ondevice_3/SOC_Project/...` (`soc_project.xpr`)

BSP 특이사항: BD에 AXI Timer가 없어 `usleep()` 이 MicroBlaze V 내부 Cycle Counter로 구현된다
(`XTIMER_DEFAULT_TIMER_IS_MB_RISCV`, `XTIMER_NO_TICK_TIMER`). 주기 인터럽트가 없으므로
**메인 루프가 직접 ms를 센다** (`main.c` 36~42행).

---

## 2. 부팅 순서 13단계 — `main.c boot_sequence()`

`04` 체크리스트 6장과 1:1 대응한다.

| # | 동작 | 코드 |
|---:|---|---|
| 1~2 | 세 IP **전부** Disable → 세 IRQ **전부** Disable | `HB/FM/SC_Enable(0)`, `*_EnableIrq(0)` |
| — | **`INJ_ClearAll()`** — GPIO 주입 잔류값 제거 | 8단계 `FM_ResetFault()` 성공 보장용 |
| 3 | `TIMEOUT0/1/2` = 300 / 600 / 150 ms → clock | `HB_SetTimeout()` |
| — | `AUTO_RECOVER = 1` | `HB_SetAutoRecover(1)` |
| 4 | `CRITICAL_MASK = 0x4` | `FM_SetCriticalMask()` |
| 5 | `PERSIST_LIMIT = 5` | `FM_SetPersistLimit()` |
| 6 | `RECOVERY_COUNT = 2` | `SC_SetRecoveryCount()` |
| 7 | `DEGRADE_MASK = 0x1` | `SC_SetDegradeMask()` |
| 8 | `CLEAR_ALL` / `RESET_FAULT` / 세 `IRQ_STATUS` W1C | |
| — | `HBGEN_Init()` + **`FM_SelfCheck()`** (ID `0x464D4752`) | 실패 시 `FATAL` 후 halt |
| 9 | AXI INTC 초기화 + Handler 3개 등록 | `MissionIntr_Init()` |
| 10 | **FM → SC** 순서로 Enable | C가 `fault_valid=0`이면 안전값을 강제하므로 B 먼저 |
| 11 | HB Enable | |
| 12 | 세 IP IRQ Enable | |
| 13 | `Xil_ExceptionEnable()` — Global Interrupt | |

완료 시 `Boot complete` 출력 → PC 앱 Raw Log에 이 줄이 보이면 부팅 성공.

> **왜 "전역 단계로 분리"했나** (2026-07-30 수정, `main.c` 95~107행)
> 예전에는 `HB_Init()` → `FM_Init()` → `SC_Init()` 를 순서대로 불러 각 IP가 자기만
> "Disable → 설정 → Clear"를 마쳤다. Cold Reset이면 문제없지만 **디버거로 CPU만 재시작**하면
> AXI IP는 리셋되지 않아, HB를 재설정하는 동안 FM/SC가 Enable인 채로 HB의 과도기 출력을
> 읽어 엉뚱한 Fault/State 이벤트를 만들 수 있었다. → 발표 트러블슈팅 소재.

---

## 3. 메인 루프와 ISR — 짧은 상태를 잃지 않는 구조

### 3.1 메인 루프 (`TICK_MS = 5 ms`)

```c
while (1) {
    HBGEN_Pump();        /* 1) Heartbeat 생성 — LAST_COUNTn(HW) 기준 판정 */
    PROTO_PollRx(g_ms);  /* 2) PC 명령 수신 (RX Ring) */
    drain_irq_flags();   /* 3) IRQ 경로 확인 → "irq FM status=.. count=.." */
    drain_snapshots();   /* 4) ISR Snapshot → $EVENT   ★ 주 경로 */
    report_changes();    /* 5) 폴링 백스톱 → $EVENT */
    if (500ms 경과) PROTO_SendMission(g_ms);   /* 6) $MISSION */
    usleep(5000); g_ms += 5;
}
```

### 3.2 ISR — `mission_intr.c`

```c
static void FM_IsrHandler(void *ref) {
    g_fm_irq.cause = FM_ReadIrqStatus();   /* 원인 읽기 */
    FM_ClearIrq(FM_IRQ_FAULT_CHANGE);      /* W1C — Snapshot 보다 먼저 */
    snap_push();                           /* 그 순간 상태 Ring 에 저장 */
    g_fm_irq.count++; g_fm_irq.flag = 1;
}
```

**W1C를 Snapshot보다 먼저** 하는 이유: 반대로 하면 Snapshot을 뜨는 동안 도착한 새 변화의
Pending까지 같이 지워져 그 전이를 통째로 잃는다. 지금 순서면 새 변화는 Pending을 다시 세워
ISR이 한 번 더 돌고, 값이 안 바뀐 중복 Snapshot은 메인 루프가 걸러낸다.

ISR이 `snap_push()` 에서 AXI 읽기 12회를 하는 것은 `00` 12장 위반이 아니다.
12장이 ISR에 금지하는 것은 **문자열 출력 / 긴 Delay / 전체 로그 출력**이다 (`mission_intr.c` 33~44행).

### 3.3 Snapshot Ring — **이 프로젝트의 핵심 설계 개선점 (발표 소재)**

| 항목 | 값 |
|---|---|
| 깊이 | `MISSION_SNAP_DEPTH = 16` |
| 저장 내용 | `hb_timeout`, `fm_level`, `fm_device`, `fm_code`, `sc_state` |
| 넘칠 때 | `warn snapshot ring overflow dropped=N` 출력 (정상 동작에선 안 나옴) |

**왜 필요했나** — 2026-07-30 이전 펌웨어는 메인 루프 폴링(5 ms)만으로 변화를 감지했다.
`eval_tick` 1 ms × `PERSIST_LIMIT` 5 = **Level 1(WARNING)이 5 ms만 유지**되므로 폴링이
눈을 뜰 때는 이미 Level 2였다. 실제로 `094029` / `100054` 로그에는 `STATE_CHANGE,WARNING` 이
0건이고 `FAULT_CHANGE` 가 level 0 → 2 로 1을 건너뛰었다.

**하드웨어는 0→1 전이에서도 IRQ를 올리고 있었다** (`fault_manager_core.v` `out_changed`).
그 순간 값을 ISR에서 받아 두면 유지 시간과 무관하게 보고된다. 그래서 Ring으로 받는다.

> ⚠ 이 개선 때문에 `00` 10.1 / `03` 11.8 / `04` 3·4장의 "PERSIST_LIMIT=5면 WARNING이
> 어디에도 안 나온다"는 서술이 **현재 펌웨어와 맞지 않는다.** → C-03

**정확한 현재 동작:**

| 표시 경로 | PL=5 (5 ms) 에서 WARNING이 보이나 | 이유 |
|---|---|---|
| `$EVENT,STATE_CHANGE,WARNING` (Event Log) | ✅ **보인다** | ISR Snapshot이 전이 순간 값을 잡음 |
| `$MISSION` 기반 GUI 큰 글씨 | ❌ 안 보인다 | 500 ms 주기 샘플 |
| GUI "최근 전이" 트레일 | ✅ 보인다 | `$EVENT` 구동 |

`PERSIST_LIMIT=255` 를 쓰는 진짜 이유 두 가지:
① `SET,*` 명령 경로 자체를 시험 ② WARNING→DEGRADED 승격이 같은 timestamp로 뭉치지 않게 벌림
(`05` 5-1장 마지막 인용문)

### 3.4 UART TX 블로킹 대응

9600 bps에서 한 글자 ≈ 1.04 ms, `$MISSION` 한 줄 ≈ **73 ms 블로킹**.

| 문제 | 대책 | 코드 |
|---|---|---|
| TX 중 RX FIFO(16 B) 넘침 → 명령 잘림 | **RX Ring 256 B**. `tx_putc()` 가 글자마다 `PROTO_RxPump()` | `uart_proto.c` 34~87행 |
| TX 중 Heartbeat 끊김 → 가짜 Timeout | 모든 송신 함수가 진입 전 `HBGEN_Pump()` | `uart_proto.c` 전 송신 함수 |
| 시간 판정이 CPU 정지에 영향받음 | 시간 기준을 **HW `LAST_COUNTn`** 으로 | `hb_gen.c` |
| `xil_printf` 가 RX를 굶김 | 자체 최소 `PROTO_Printf` (`%u %d %s %x %02x %08x %%`) | `uart_proto.c` 135행 |

---

## 4. UART 프로토콜 — 실측 정본

### 4.1 링크 규칙

| 항목 | 값 |
|---|---|
| Baudrate | **9600 8N1** (BD·펌웨어·PC 앱 3곳 모두) |
| 인코딩 | ASCII (UTF-8 호환) |
| 구분자 | `,` |
| 줄 종료 | 보드 송신 `\r\n` / 보드 수신은 `\n` `\r` 둘 다 허용 |
| 최대 줄 길이 | **PC 수신 4096 B** (`constants.py MAX_LINE_BYTES`) / **FPGA 수신 96 B** (`uart_proto.c RX_LINE_MAX`) |
| 접두어 | `$MISSION` `$EVENT` `$ACK` `$ERR` `$IRQ` |
| 그 외 | `$` 로 시작하지 않으면 디버그 문자열 → PC는 Raw Log에만 기록 |

> **4096 vs 96** — 두 값은 방향이 다르다. 슬라이드에 "최대 줄 길이 4096"이라고만 쓰면
> FPGA 수신 한계(96 B, 초과 시 `$ERR,INVALID_VALUE,LINE_TOO_LONG`)를 놓친다. → C-09

### 4.2 FPGA → PC

**`$MISSION`** (500 ms 주기, 펌웨어는 14필드 전부 전송)

```text
$MISSION,timestamp,state,fault_level,fault_device,fault_code,alive,timeout,
         output_enable,actuator_enable,control_valid,state_timer,
         fault_count0,fault_count1,fault_count2
```

| # | 필드 | 형식 | 출처 |
|--:|---|---|---|
| 1 | `timestamp` | ms 정수 | `main.c g_ms` (SW 카운트, 실측 ~10% 느림) |
| 2 | `state` | 문자열 | `SC_SYSTEM_STATE` → `SC_StateStr()` |
| 3 | `fault_level` | 0~3 | `FM_FAULT_LEVEL` |
| 4 | `fault_device` | 0~3 | `FM_FAULT_DEVICE` |
| 5 | `fault_code` | 0x00~0x04 | `FM_FAULT_CODE` |
| 6 | `alive` | `0x0N` 3비트 | `HB_STATUS[2:0]` |
| 7 | `timeout` | `0x0N` 3비트 | `HB_STATUS[10:8]` |
| 8 | `output_enable` | `0x0N` 3비트 | `SC_OUTPUT_ENABLE` |
| 9 | `actuator_enable` | 0/1 | **유도** `SC_ActuatorEnable()` |
| 10 | `control_valid` | 0/1 | **유도** `SC_ControlValid()` |
| 11 | `state_timer` | **ms** | `SC_STATE_TIMER` × `CLK_TO_MS` |
| 12~14 | `fault_count0~2` | 0~255 | `FM_FAULT_COUNT` 언패킹 |

유도식 (`sc_regs.c`):

```c
u8 SC_ActuatorEnable(state, enabled, fault_valid) {
    if (!enabled || !fault_valid) return 0;
    return (state == ST_SAFE_MODE) ? 0 : 1;
}   /* SC_ControlValid 도 동일 */
```

**`$EVENT`** — 상태 전이 증거

| `event_type` | 인자 | 발생 |
|---|---|---|
| `FAULT_CHANGE` | level, device, code | 셋 중 하나라도 변경 |
| `STATE_CHANGE` | state 문자열 | Safety Controller 전이 |
| `HEARTBEAT_TIMEOUT` | device | `timeout[i]` 0→1 |
| `MANUAL_RESET` | `ACCEPTED` / `REJECTED` | Manual Recovery 시도 결과 |

**`$ACK` / `$ERR`** — **수신한 모든 명령에 둘 중 하나로 반드시 응답**

| `$ERR` 코드 | 의미 |
|---|---|
| `UNKNOWN_COMMAND` | 미지원 명령 (PC는 "지원하지 않는 기능"으로 표시, 오류 취급 안 함) |
| `INVALID_VALUE` | 인자 범위 초과 |
| `FAULT_ACTIVE` | 활성 Fault로 거부 |
| `FAULT_INVALID` | `fault_valid=0` 이라 판단 불가 (정의만 존재, 현재 펌웨어에서 미발신) |

**`$IRQ`** — `GET,IRQ` 응답

```text
$IRQ,<en_mask>,<hb_status>,<fm_status>,<sc_status>
```

`en_mask` bit0=A / bit1=B / bit2=C (각 IP `IRQ_EN`을 0/1로 정규화)
평상시 status는 **항상 0** (ISR이 즉시 W1C). 0이 아닌 값을 보려면 `SET,IRQ_EN,0` 이 필요하다.

### 4.3 PC → FPGA — **펌웨어 실측 기준 전체 명령표**

`uart_proto.c` `handle_get/set/cmd/inject` 에서 추출.

| 명령 | 인자 범위 | 성공 응답 | 실패 |
|---|---|---|---|
| `GET,STATUS` | — | `$ACK,GET,STATUS` + `$MISSION,...` | |
| `GET,CONFIG` | — | `$ACK,GET,CONFIG` + **`$ACK,SET,...` 8줄** | |
| `GET,IRQ` | — | `$ACK,GET,IRQ` + `$IRQ,...` | |
| `SET,TIMEOUT,<dev>,<clk>` | dev 0~2 / clk 32bit | `$ACK,SET,TIMEOUT,<dev>,<clk>` | `$ERR,INVALID_VALUE,TIMEOUT` |
| `SET,CRITICAL_MASK,<m>` | 0x00~0x07 | `$ACK,SET,CRITICAL_MASK,<m>` | `$ERR,INVALID_VALUE,CRITICAL_MASK` |
| `SET,PERSIST_LIMIT,<v>` | **0~255** | `$ACK,SET,PERSIST_LIMIT,<v>` | `$ERR,INVALID_VALUE,PERSIST_LIMIT` |
| `SET,RECOVERY_COUNT,<v>` | 0~65535 | `$ACK,SET,RECOVERY_COUNT,<v>` | `$ERR,INVALID_VALUE,RECOVERY_COUNT` |
| `SET,DEGRADE_MASK,<m>` | 0x00~0x07 | `$ACK,SET,DEGRADE_MASK,<m>` | `$ERR,INVALID_VALUE,DEGRADE_MASK` |
| `SET,IRQ_EN,<m>` | 0x00~0x07 | `$ACK,SET,IRQ_EN,<m>` | `$ERR,INVALID_VALUE,IRQ_EN` |
| `CMD,MANUAL_RESET` | — | `$ACK,CMD,MANUAL_RESET` + `$EVENT,..,MANUAL_RESET,ACCEPTED` | `$ERR,MANUAL_RESET,FAULT_ACTIVE` + `..,REJECTED` |
| `CMD,RESET_FAULT` | — | `$ACK,CMD,RESET_FAULT` | `$ERR,RESET_FAULT,FAULT_ACTIVE` |
| `CMD,CLEAR_IRQ` | — | `$ACK,CMD,CLEAR_IRQ` | (거부 조건 없음) |
| `CMD,CLEAR_HEARTBEAT` | — | `$ACK,CMD,CLEAR_HEARTBEAT` | (거부 조건 없음) |
| `INJECT,ERROR,<dev>,ON\|OFF` | dev 0~2 | **`$ACK,INJECT,ERROR,<dev>`** | `$ERR,INVALID_VALUE,ERROR` |
| `INJECT,CRITICAL,<dev>,ON\|OFF` | dev 0~2 | **`$ACK,INJECT,CRITICAL,<dev>`** | `$ERR,INVALID_VALUE,CRITICAL` |
| `INJECT,TIMEOUT,<dev>,ON\|OFF` | dev 0~2 | **`$ACK,INJECT,TIMEOUT,<dev>`** | `$ERR,INVALID_VALUE,TIMEOUT` |
| `INJECT,CLEAR,ALL` | — | **`$ACK,INJECT,CLEAR`** | |
| 그 외 | — | — | `$ERR,UNKNOWN_COMMAND` |
| 줄 96 B 초과 | — | — | `$ERR,INVALID_VALUE,LINE_TOO_LONG` |

> **⚠ 두 가지가 문서와 다르다.**
> ① `$ACK,INJECT,*` 에 **ON/OFF 인자가 없다.** `README_PROTOCOL.md` 132행의
>    예시 `$ACK,INJECT,CRITICAL,2,ON` 은 틀렸다. → C-07
> ② `$ACK,INJECT,CLEAR` 로 응답한다 (`ALL` 없음). → C-08

`GET,CONFIG` 실제 응답 **8줄** (`uart_proto.c` 546~556행):

```text
$ACK,GET,CONFIG
$ACK,SET,TIMEOUT,0,30000000
$ACK,SET,TIMEOUT,1,60000000
$ACK,SET,TIMEOUT,2,15000000
$ACK,SET,CRITICAL_MASK,4
$ACK,SET,PERSIST_LIMIT,5
$ACK,SET,RECOVERY_COUNT,2
$ACK,SET,DEGRADE_MASK,1
$ACK,SET,IRQ_EN,7          ← 03 문서 예시(7줄)에 없는 8번째 줄
```

→ `03` 11.5 예시와 `04` 3.1 28번("설정 7줄")이 **8줄로 수정**되어야 한다. C-06

### 4.4 명령 거부 로직 (펌웨어 실측)

```c
/* CMD,MANUAL_RESET  — uart_proto.c 441~457행 */
if (!FM_IsEnabled() || fm.level != FM_LEVEL_0_NORMAL) {
    PROTO_Err2("MANUAL_RESET", "FAULT_ACTIVE");
    PROTO_SendEventManualReset(ts, "REJECTED");  return;
}
/* CMD,RESET_FAULT   — uart_proto.c 458~466행 */
if (FM_HasActiveFault()) { PROTO_Err2("RESET_FAULT", "FAULT_ACTIVE"); return; }
```

`FM_IsEnabled()` = `fault_valid` (`02_MEMBER_B` 2장: `enable=1 → fault_valid=1`)
**IP도 같은 조건으로 걸러내지만**, 거부 사유를 PC에 알려주려고 소프트웨어가 먼저 판정한다.
→ 발표에서 "하드웨어가 거부한다"고 말할 때 정확히는 **HW와 FW가 이중으로 거부**한다.

---

## 5. Python 대시보드 구조

```text
mission_soc_dashboard/
  app.py                        진입점
  mission_dashboard/
    protocol.py         수신 파서 (예외를 밖으로 안 던짐 → ParseResult)
    command_builder.py  송신 명령 생성 (검증 실패 시 CommandError)
    constants.py        기본값·범위·CSV 필드 정본
    models.py           Enum/데이터클래스 (UNKNOWN 허용)
    state_mapper.py     상태 → 표시 문자열/아이콘
    serial_worker.py    시리얼 스레드
    mock_device.py      보드 없이 화면 검증
    log_manager.py      mission_log_*.csv / mission_events_*.csv
    settings_manager.py , theme.py , main_window.py , widgets/*
  tests/                파서·명령·IRQ·상태매핑·테마 단위 테스트
```

**설계 원칙 (발표 소재)**

- **알 수 없는 값에 죽지 않는다.** 모르는 state/level/device/code는 `UNKNOWN` Enum으로,
  숫자 해석 자체가 불가능할 때만 Parse Error (`protocol.py` 14~17행)
- `$EVENT` 는 인자 수가 달라도 원본을 Event Log에 보존 → **새 이벤트를 추가해도 PC 수정 불필요**
- 색상만으로 상태를 구분하지 않는다 → `state_icon()` 이 `[ OK ] / [ ! ] / [ !! ] / [ STOP ]` 제공
- Mock Simulator 모드로 보드 없이 화면 검증 가능

---

## 6. 3계층 대조표 — **이게 어긋나면 GUI가 안 뜬다**

| 항목 | Custom IP / BD | Vitis 펌웨어 | Python 앱 | 일치 |
|---|---|---|---|:--:|
| Baudrate | `C_BAUDRATE=9600` | `UART_BASE` 직접 제어 | `SUPPORTED_BAUDRATES` 에 9600 존재 | ✅ |
| FM Base | `0x44A00000` | `XPAR_FAULT_MANAGER_IP_0_BASEADDR` | — | ✅ |
| HB Base | `0x44A10000` | `XPAR_MYIP_HEARTBEAT_MONIT_0_BASEADDR` (fallback 있음) | — | ✅ |
| SC Base | `0x44A20000` | `XPAR_SAFETY_CONTROLLER_0_BASEADDR` | — | ✅ |
| IRQ ID | xlconcat In1/In2/In3 | `INTR_ID_FM=1 / HB=2 / SC=3` | — | ✅ |
| `$MISSION` 필드 수 | — | 14개 전송 | 필수 9 / 최대 14 파싱 | ✅ |
| 마스크 폭 | 3비트 | `& 0x7` | `& 0x7` | ✅ |
| `IRQ_EN` 인코딩 | — | bit0=HB, bit1=FM, bit2=SC | `IRQ_EN_BIT_HB/FM/SC` 동일 | ✅ |
| `PERSIST_LIMIT` 상한 | 레지스터 8비트 | `v > 255` 거부 | `PERSIST_LIMIT_MAX=255` | ✅ |
| `RECOVERY_COUNT` 상한 | 레지스터 16비트 | `v > 65535` 거부 | `RECOVERY_COUNT_MAX=65535` | ✅ |
| 마스크 상한 | 3비트 | `v > 0x7` 거부 | `MASK_MAX=0x07` | ✅ |
| 기본 Timeout | — | 300/600/150 ms | `(30_000_000, 60_000_000, 15_000_000)` | ✅ |
| `$IRQ` 필드 수 | — | 4개 송신 | `IRQ_FIELDS=4` | ✅ |
| **앱 기본 Baudrate** | 9600 고정 | — | **`DEFAULT_BAUDRATE = 115200`** | ⚠ |
| **`$ACK,INJECT` 인자** | — | ON/OFF **없음** | 무관(원본 보존) | ⚠ 문서만 틀림 |

⚠ **`DEFAULT_BAUDRATE = 115200`** (`constants.py` 51행) — 보드는 9600이다.
문서에 경고는 있지만(`README.md` 50행, `README_PROTOCOL.md` 24행) **시연 전 반드시 9600 선택**.
틀리면 글자가 전부 깨진다. → C-18

---

## 7. Python 앱 명령 생성기 ↔ 펌웨어 파서 대조

| `command_builder` 메서드 | 생성 문자열 | 펌웨어 처리 |
|---|---|---|
| `get_status()` | `GET,STATUS\n` | ✅ |
| `get_config()` | `GET,CONFIG\n` | ✅ |
| `get_irq()` | `GET,IRQ\n` | ✅ |
| `set_timeout(d, c)` | `SET,TIMEOUT,{d},{c}\n` | ✅ |
| `set_critical_mask(m)` | `SET,CRITICAL_MASK,0x{m:02X}\n` | ✅ (`parse_u32` 가 `0x` 처리) |
| `set_persist_limit(v)` | `SET,PERSIST_LIMIT,{v}\n` | ✅ |
| `set_recovery_count(v)` | `SET,RECOVERY_COUNT,{v}\n` | ✅ |
| `set_degrade_mask(m)` | `SET,DEGRADE_MASK,0x{m:02X}\n` | ✅ |
| `set_irq_en(m)` | `SET,IRQ_EN,0x{m:02X}\n` | ✅ |
| `manual_reset()` | `CMD,MANUAL_RESET\n` | ✅ |
| `reset_fault()` | `CMD,RESET_FAULT\n` | ✅ |
| `clear_irq()` | `CMD,CLEAR_IRQ\n` | ✅ |
| `clear_heartbeat()` | `CMD,CLEAR_HEARTBEAT\n` | ✅ |
| `inject(kind, d, on)` | `INJECT,{KIND},{d},{ON\|OFF}\n` | ✅ |
| `inject_clear_all()` | `INJECT,CLEAR,ALL\n` | ✅ |
| `apply_config()` | 위 `SET` 7개 순차 (IRQ_EN 제외) | ✅ |

펌웨어 파서는 `0x` / `0b` / 10진수를 모두 받는다 (`uart_proto.c parse_u32`).
Python 파서도 `0x` / `0b` / 10진수를 모두 받는다 (`protocol.py parse_int`). **양방향 대칭.**

**GUI 프리셋 4종** (`command_builder.py`)

| 프리셋 | 명령 | 기대 결과 |
|---|---|---|
| `D0 Timeout + D1 Error (단계적 상승)` | `INJECT,TIMEOUT,0,ON` + `INJECT,ERROR,1,ON` | Error 즉시 → **0.3초 뒤** Timeout 합류 → `MULTI_DEVICE` (하드웨어 지연) |
| `D0 + D1 Error (다중 장치 Multi)` | `INJECT,ERROR,0,ON` + `INJECT,ERROR,1,ON` | 둘 다 즉시지만 **UART 두 줄이라 ~0.2초 간격** (링크 지연, 실측 229 ms) |
| `Device 2 Critical Demo` | `INJECT,CRITICAL,2,ON` | 즉시 Level 3 / `FAULT_CRITICAL` |
| `Device 2 Error (CRITICAL_MASK 확인)` | `INJECT,ERROR,2,ON` | **평범한 Error인데도** 즉시 Level 3 / `FAULT_CRITICAL` |

> **나레이션 주의**: 두 다중 Fault 프리셋 모두 "동시에"라고 말하면 안 된다.
> 클럭 단위 동시 성립은 UART로 만들 수 없고 `sim/tb_fault_manager_core.v` 가 커버한다.
> 지연 원인이 다르다는 게 포인트다 — 앞은 **HW Timeout 0.3초**, 뒤는 **링크 전송 시간**.
