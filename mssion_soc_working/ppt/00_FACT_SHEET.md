# 00. Fact Sheet — 슬라이드에 쓸 수 있는 값의 정본

모든 값은 저장소 실물에서 추출했다. 근거 파일을 옆에 적어 뒀다.
**⚠ 표시가 붙은 항목은 저장소만으로 확정할 수 없다.** → [`04_CONTRADICTIONS.md`](04_CONTRADICTIONS.md) 참조

---

## 1. 프로젝트 한 줄 정의 (슬라이드 표지/개요용)

> 여러 하위 장치의 Heartbeat와 오류 상태를 FPGA Custom IP가 **병렬로 감시**하고,
> 오류의 **중요도와 지속시간**에 따라 시스템을 `NORMAL` / `WARNING` / `DEGRADED` / `SAFE_MODE`로
> 자동 전환하는 **MicroBlaze V(RISC-V) 기반 SoC**.

> 실제 군용 임무컴퓨터가 아니라, 고신뢰 임베디드의 상태 감시·고장 분류·안전 출력 차단 원리를
> Basys 3에서 축소 구현한 **교육용 프로토타입**이다.

근거: `00_TEAM_COMMON_SPEC_3MEMBERS_RECOVERY_FIXED.md` 1장

**안전 판단은 전부 FPGA 안에서 한다. PC 앱은 감시·명령·로그 저장만 한다.** (`README.md` 13~14행)

---

## 2. 환경 — 슬라이드 표지/환경 슬라이드

| 항목 | 값 | 근거 |
|---|---|---|
| 보드 | Digilent **Basys 3** | — |
| Part | **`xc7a35tcpg236-1`** | `SOC_Pr/soc_project/soc_project.xpr` |
| Vivado | **2024.2** | `soc_project.xpr` 헤더 `Vivado v2024.2 (64-bit)` |
| Vitis | **2024.2** (Unified IDE) | `README.md` |
| CPU | **MicroBlaze V (RISC-V)** — `xilinx.com:ip:microblaze_riscv:1.0` | `mission_soc.bd` |
| 시스템 클럭 | **100 MHz** (1 clock = 10 ns), `clk_wiz` CLKOUT1 = 100.0 | `mission_soc.bd` |
| 메모리 | LMB BRAM **128 KB** @ `0x00000000` (I/D 공용 영역) | `mission_soc.bd` addressing |
| UART | **9600 8N1**, AXI UARTLite | `mission_soc_axi_uartlite_0_0.xci` `C_BAUDRATE=9600` |
| Python | 3.11 이상, PySide6 | `README.md`, `requirements.txt` |

> **용어 주의.** IP는 고전 MicroBlaze가 아니라 **MicroBlaze V(RISC-V ISA)** 다.
> 슬라이드에 "MicroBlaze"라고만 쓰면 질문이 들어온다. 최소 한 번은 "MicroBlaze V (RISC-V)"로 표기.
> BSP도 이 때문에 `XTIMER_DEFAULT_TIMER_IS_MB_RISCV` 를 쓴다 (`main.c` 36~42행).

---

## 3. Custom IP — 정확히 3개

| # | 명세상 이름 | **실제 VLNV** | **BD 인스턴스명** | 담당 |
|---|---|---|---|---|
| 1 | `heartbeat_monitor_ip` | `user.org:user:myip_heartbeat_monitor:1.0` | `myip_heartbeat_monit_0` | 팀원 A |
| 2 | `fault_manager_ip` | `user.org:user:fault_manager_ip:1.0` | `fault_manager_ip_0` | 팀원 B |
| 3 | `safety_controller_ip` | `user.org:user:safety_controller:1.0` | `safety_controller_0` | 팀원 C |

`eval_tick_generator` 는 **AXI 없는 공통 보조 RTL(Module Reference)** 이며 **네 번째 Custom IP가 아니다.**
(`00` 5.2 / BD `xilinx.com:module_ref:eval_tick_generator:1.0`)

> 다이어그램 라벨은 **BD 인스턴스명**으로 쓰거나 "명세명(인스턴스명)" 병기. → C-13

**IP Catalog IP(교육과정 "2개 이상" 증빙)**: `AXI Interrupt Controller`, `AXI UARTLite`
추가 사용: `AXI GPIO ×2`, `Clocking Wizard`, `Processor System Reset`, `xlconcat ×2`, `MDM`, `AXI Interconnect`, LMB BRAM 일체
**AXI Timer는 없다.** → C-20

---

## 4. Address Map (Vivado Address Editor 확정값)

| 대상 | Base | Range | 근거 |
|---|---|---|---|
| `fault_manager_ip_0` | **`0x44A0_0000`** | 64K | `mission_soc.bd` addressing |
| `myip_heartbeat_monit_0` | **`0x44A1_0000`** | 64K | 〃 |
| `safety_controller_0` | **`0x44A2_0000`** | 64K | 〃 |
| `axi_gpio_0` (error/critical) | **`0x4000_0000`** | 64K | 〃 |
| `axi_gpio_1` (heartbeat) | **`0x4001_0000`** | 64K | 〃 |
| `axi_uartlite_0` | **`0x4060_0000`** | 64K | 〃 |
| `axi_intc` | **`0x4120_0000`** | 64K | 〃 |
| LMB BRAM (D/I) | **`0x0000_0000`** | 128K | 〃 |

펌웨어는 숫자를 직접 쓰지 않고 `xparameters.h` 매크로를 쓴다 (`mission_ip_regs.h` 29~42행).

---

## 5. 인터럽트 — **실제 순서 (슬라이드에 이 표를 쓸 것)**

| xlconcat 포트 | 연결 | XIntc ID | 펌웨어 매크로 |
|---|---|---:|---|
| `In0` | `axi_uartlite_0/interrupt` | 0 | `INTR_ID_UART` (이번 빌드 미사용) |
| `In1` | `fault_manager_ip_0/irq` | **1** | `INTR_ID_FM` |
| `In2` | `myip_heartbeat_monit_0/irq` | **2** | `INTR_ID_HB` |
| `In3` | `safety_controller_0/irq` | **3** | `INTR_ID_SC` |

근거: `mission_soc.bd` nets, `SOC_Pr_Vitis/soc_prj/src/mission_intr.h` 20~23행

> `03_MEMBER_C` 10장의 "권장 순서(In0=HB, In1=FM, In2=SC, In3=UART)" 는 **실제와 다르다.** → C-04

IRQ 방식: **Level + W1C** (Pulse 아님). `assign irq = reg_irq_status & reg_irq_en;`

---

## 6. LED 매핑 — `led_concat`(xlconcat 8입력) → `led[15:0]`

| LED | 폭 | 신호 | xlconcat |
|---|---:|---|---|
| `LD1:LD0` | 2 | `system_state` (0=N,1=W,2=D,3=SAFE) | `In0` |
| `LD4:LD2` | 3 | `output_enable[2:0]` | `In1` |
| `LD5` | 1 | `actuator_enable` | `In2` |
| `LD6` | 1 | `control_valid` | `In3` |
| `LD9:LD7` | 3 | `alive[2:0]` | `In4` |
| `LD12:LD10` | 3 | `timeout[2:0]` | `In5` |
| `LD14:LD13` | 2 | `fault_level` | `In6` |
| `LD15` | 1 | `fault_valid` | `In7` |

근거: `mission_soc.bd` (`led_concat` IN0~IN7 폭 2/3/1/1/3/3/2/1 = 16), `03_MEMBER_C` 12.2 — **일치함**

**FND / RGB LED는 미구현.** 슬라이드에 그리지 말 것.

---

## 7. 보드 외부 포트 — **딱 4개**

| BD 포트 | 핀 | 의미 |
|---|---|---|
| `sys_clock` | `W5` | 100 MHz 입력 |
| `reset` | `U18` (**btnC**) | 유일하게 배선된 물리 입력 |
| `usb_uart` | `B18`(rxd) / `A18`(txd) | USB-UART |
| `led[15:0]` | U16 … L1 | 상태 표시 |

근거: `mission_soc.bd` ports, `SOC_Pr/soc_project/soc_project.srcs/constrs_1/imports/digilent-xdc-master/Basys-3-Master.xdc`

**슬라이드 스위치(SW0~SW3), btnU, btnD는 BD·XDC 어디에도 배선되어 있지 않다.**
`axi_gpio_0` / `axi_gpio_1` 은 둘 다 `C_ALL_OUTPUTS=1`(출력 전용)이라 보드 입력을 읽을 수 없다.
→ **모든 시연·검증은 UART 경로**로 한다. (`00` 12.3, `04` 구현 범위)

---

## 8. Fault Injection 실제 경로

```text
PC 앱  ──UART──▶ MicroBlaze V ──┬─ axi_gpio_0 CH1 ─▶ fault_manager.error_flag[2:0]
                                ├─ axi_gpio_0 CH2 ─▶ fault_manager.critical_fault[2:0]
                                └─ axi_gpio_1 CH1 ─▶ heartbeat_monitor.heartbeat_async[2:0]
```

- `INJECT,ERROR` / `INJECT,CRITICAL` → **즉시 성립** (GPIO 쓰기)
- `INJECT,TIMEOUT` → **GPIO 직접 주입 아님.** 해당 Device Heartbeat 생성을 멈추고
  `heartbeat_monitor` 가 `TIMEOUTn` 초과를 **스스로 판정**한다 (`04` 1.1 Freeze)
  → D0 **0.3초** / D1 **0.6초** / D2 **0.15초** 뒤 반응

근거: `mission_soc.bd` nets, `uart_proto.c` 485~535행, `hb_gen.c`

---

## 9. 공통 인코딩 (변경 금지)

```text
System State   2'b00 NORMAL   2'b01 WARNING   2'b10 DEGRADED   2'b11 SAFE_MODE
Fault Level    0 LEVEL_0_NORMAL  1 LEVEL_1_WARNING  2 LEVEL_2_DEGRADED  3 LEVEL_3_SAFE
Fault Code     0x00 NONE  0x01 TIMEOUT  0x02 ERROR_CODE  0x03 CRITICAL  0x04 MULTI_DEVICE  0x05 RECOVERY_REQUIRED*
Device ID      0 DEVICE_0  1 DEVICE_1  2 DEVICE_2  3 MULTIPLE_OR_NONE
```

\* `0x05 FAULT_RECOVERY_REQUIRED` 는 **현재 정책에서 사용처가 없다.** RTL에 localparam도 없다
(`fault_manager_core.v` 62~66행). 슬라이드 코드표에 넣되 "미사용"으로 표기하는 게 안전하다.

세 곳이 모두 같은 값을 쓴다: `fault_manager_core.v` / `mission_ip_regs.h` 63~87행 / `mission_dashboard/models.py`

---

## 10. Fault 정책 우선순위 (P1이 P5를 덮어씀)

```verilog
device_fault       = timeout | error_flag | critical_fault;   // 장치별 OR
critical_condition = |(device_fault & critical_mask);
```

| 순위 | 조건 | level | code | device |
|---:|---|:--:|---|---|
| P1 | `critical_condition != 0` | 3 | `FAULT_CRITICAL` | 해당 1개면 그 ID, 2개↑면 `3` |
| P2 | Critical 없음 + `device_fault` 2비트 이상 | 3 | `FAULT_MULTI_DEVICE` | `3` |
| P3 | Mask 밖 단일 장치가 `PERSIST_LIMIT` 이상 지속 | 2 | `TIMEOUT`/`ERROR_CODE` | 해당 장치 |
| P4 | Mask 밖 단일 장치, 지속 미만 | 1 | `TIMEOUT`/`ERROR_CODE` | 해당 장치 |
| P5 | 오류 없음 | 0 | `FAULT_NONE` | `3` |

근거: `rtl/fault_manager_core.v` 182~207행 (문서 `00` 10장 / `02` 3장과 일치)

**꼭 말해야 하는 3가지**

1. `CRITICAL_MASK` 는 `critical_fault` **전용 Mask가 아니다.** 기본 `0x4`에서 Device 2의
   **Timeout이나 Error만으로도** 지속 횟수 없이 Level 3이다.
2. 같은 단일 장치에 Timeout + Error 동시 → **`FAULT_ERROR_CODE`** (Timeout 아님).
3. 지속 Count만 `eval_tick`(1 ms)에서 갱신. **Critical / 다중 Fault는 매 100 MHz 클럭 판정.**

**"즉시"의 정확한 의미**: 0 ns 조합 응답이 아니라
`외부 입력 동기화 + Fault Manager 1 clock + Safety Controller 1 clock`
= 100 MHz 기준 **2 clock = 20 ns** 안에 결정적으로 차단.

---

## 11. Safety FSM 및 복구 정책

```text
NORMAL   ─ L1→WARNING  L2→DEGRADED  L3→SAFE_MODE
WARNING  ─ L0 연속 RECOVERY_COUNT → NORMAL   / L2→DEGRADED / L3→SAFE_MODE
DEGRADED ─ L1 연속 RECOVERY_COUNT → WARNING
           L0 연속 RECOVERY_COUNT → NORMAL   / L3→SAFE_MODE
SAFE_MODE─ 자동 복귀 금지. fault_valid=1 && fault_level=0 && MANUAL_RESET → NORMAL
```

- `fault_level=1`에서 `NORMAL`로 가는 경로는 **없다** (통합 실패 판정 기준, `04` 20행)
- Recovery Counter는 `eval_tick`에서만 증가. `fault_valid`를 Tick으로 쓰지 않는다
- `fault_valid=0` → 상태 Hold + `output_enable=000`, `actuator=0`, `control_valid=0`, recovery counter clear

출력 정책:

| 상태 | `output_enable` | `actuator_enable` | `control_valid` |
|---|---|:--:|:--:|
| NORMAL | `3'b111` | 1 | 1 |
| WARNING | `3'b111` | 1 | 1 |
| DEGRADED | dev0→`110` / dev1→`101` / dev2→`011` / dev3→`111 & ~DEGRADE_MASK` | 1 | 1 |
| SAFE_MODE | `3'b000` | 0 | 0 |
| **DISABLED (`enable=0`)** | `3'b000` | 0 | 0 (state=NORMAL) |

근거: `SOC_Pr/ip_repo/safety_controller_1_0/hdl/safety_controller.v`

---

## 12. 설정 기본값 (부팅 시 MicroBlaze가 씀)

| 항목 | 값 | 시간 환산 | 근거 |
|---|---|---|---|
| `TIMEOUT0` | `30,000,000` clk | 300 ms | `mission_ip_regs.h` `CFG_TIMEOUT0_MS=300` |
| `TIMEOUT1` | `60,000,000` clk | 600 ms | `CFG_TIMEOUT1_MS=600` |
| `TIMEOUT2` | `15,000,000` clk | 150 ms | `CFG_TIMEOUT2_MS=150` |
| Heartbeat 주기 | D0 100 / D1 200 / D2 50 ms | — | `CFG_HB_PERIOD0~2_MS` |
| `CRITICAL_MASK` | `0x4` (Device 2만) | — | `CFG_CRITICAL_MASK` |
| `PERSIST_LIMIT` | `5` | Level 1 유지 = 5 × 1 ms = **5 ms** | `CFG_PERSIST_LIMIT` |
| `RECOVERY_COUNT` | `2` | 2 ms | `CFG_RECOVERY_COUNT` |
| `DEGRADE_MASK` | `0x1` | — | `CFG_DEGRADE_MASK` |
| `AUTO_RECOVER` | **1 (켬)** | — | `main.c` 135행 |
| `eval_tick` DIVISOR | `100,000` | **1 ms** | `rtl/eval_tick_generator.v` |
| `device_enable` | `3'b111` 고정 | — | `00` 8.1 |
| 제약 | `RECOVERY_COUNT < PERSIST_LIMIT` | 2 < 5 ✓ | `03` 6장 |
| 0의 해석 | `TIMEOUTn`/`PERSIST_LIMIT`/`RECOVERY_COUNT` = 0 → **1로 간주** | — | `00` 12.1 |

`AUTO_RECOVER=1` 인 이유: 0이면 Timeout Latch가 `CLEAR_ALL` 전까지 안 풀려서
"모든 Fault 제거 → Level 0 → NORMAL" 시연이 성립하지 않는다 (`main.c` 130~134행).

---

## 13. UART 프로토콜 — 한 줄 요약

```text
FPGA → PC :  $MISSION (500 ms 주기)   $EVENT (전이)   $ACK / $ERR (명령 응답)   $IRQ (GET,IRQ 응답)
PC → FPGA :  GET,*    SET,*    CMD,*    INJECT,*
```

`$MISSION` 필드 순서 (**필수 9 + 선택 5, 펌웨어는 14개 전부 전송**):

```text
$MISSION,timestamp,state,fault_level,fault_device,fault_code,alive,timeout,
         output_enable,actuator_enable,control_valid,state_timer,
         fault_count0,fault_count1,fault_count2
```

- 마스크(`alive`/`timeout`/`output_enable`)는 **하위 3비트만**, `0x%02x` 소문자 16진
- `timestamp` / `state_timer` 단위는 **ms** (`state_timer`는 펌웨어가 clock→ms 변환. `sc_regs.c` 87행)
- `actuator_enable` / `control_valid` 는 AXI로 읽을 수 없어 **`system_state`에서 유도** (`sc_regs.c` 122~132행)
- 9600 bps에서 `$MISSION` 한 줄 ≈ **73 ms 블로킹 전송**

전체 명령표는 [`02_FW_AND_PROTOCOL.md`](02_FW_AND_PROTOCOL.md) 4장.

---

## 14. ⚠ 확정 불가 — 슬라이드에 쓰기 전 반드시 재확인

| 항목 | 문서마다 다른 값 | 어떻게 확정 | 상세 |
|---|---|---|---|
| **Timing** | WNS `+0.963` vs `+0.198` / WHS `+0.029` vs `+0.033` | Vivado `open_run impl_1` → `report_timing_summary` | C-01 |
| **Utilization** | LUT `2500` vs `3,039` / Register 미기재 vs `2,646` | 〃 → `report_utilization` | C-01 |
| **TB 총 checks** | `4,533` (FM AXI 73) vs `4,211` (FM AXI 60) | TB 8종 재실행 후 로그 첨부 | C-02 |
| **Python 테스트 수** | `202 passed` (저장소엔 `def test_` 160개 + parametrize) | `pytest -q` 재실행 | C-16 |
| **WARNING 관측** | "PL=5면 안 나옴" vs "PL=5여도 기록됨" | 코드 기준 **기록은 됨** | C-03 |

**저장소에 Vivado 리포트(`soc_project.runs/`)와 TB 로그(`tb_logs_batch/`)가 없다.**
따라서 위 숫자는 코드만으로 검증 불가하다. 발표 전 재실행이 유일한 방법이다.

---

## 15. 이번 빌드에 **없는** 것 (슬라이드에 그리면 사고)

| 항목 | 상태 |
|---|---|
| 물리 SW0~SW3 / btnU / btnD 입력 | ❌ BD·XDC 미배선, GPIO는 출력 전용 |
| FND (7-seg) | ❌ 미구현 |
| RGB LED | ❌ 미구현 |
| AXI Timer | ❌ BD에 없음 (timestamp는 소프트웨어 카운트, 실측 ~10% 느림) |
| `event_logger_ip` / BRAM 로그 | ❌ 확장 항목, 미구현 |
| `device_simulator_ip` | ❌ MicroBlaze가 Heartbeat를 대신 생성 |
| `DEGRADED → WARNING` 하강 시연 (보드) | ❌ GUI로 도달 불가 → `sim/tb_safety_controller_core.v`가 커버 |
| `FAULT_RECOVERY_REQUIRED (0x05)` | ❌ 정책에 사용처 없음 |
