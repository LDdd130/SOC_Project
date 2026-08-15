# 01. 하드웨어 — Vivado Block Design · Custom IP · XDC

`SOC_Pr/soc_project/soc_project.srcs/sources_1/bd/mission_soc/mission_soc.bd` 를 파싱해 추출한 **실측값**이다.
슬라이드의 아키텍처 그림과 이 문서가 다르면 그림이 틀린 것이다.

---

## 1. BD 전체 구성 — 실제 컴포넌트 16개

| 인스턴스 | VLNV | 역할 |
|---|---|---|
| `microblaze_riscv_0` | `xilinx.com:ip:microblaze_riscv:1.0` | CPU (RISC-V). `C_D_AXI=1`, `C_D_LMB=1`, `C_I_LMB=1`, `C_DEBUG_ENABLED=1` |
| `microblaze_riscv_0_local_memory` | (계층) | ILMB/DLMB + BRAM Controller + `lmb_bram` |
| `microblaze_riscv_0_axi_periph` | `axi_interconnect:2.1` | **`NUM_MI=7`** — 주변장치 7개 |
| `microblaze_riscv_0_axi_intc` | `axi_intc:4.1` | `C_HAS_FAST=1` |
| `microblaze_riscv_0_xlconcat` | `xlconcat:2.1` | `NUM_PORTS=4` — IRQ 묶음 |
| `mdm_1` | `mdm_riscv:1.0` | 디버그 모듈 |
| `clk_wiz` | `clk_wiz:6.0` | `CLKOUT1_REQUESTED_OUT_FREQ=100.0`, Board Flow |
| `proc_sys_reset_0` | `proc_sys_reset:5.0` | 리셋 동기화 |
| `axi_uartlite_0` | `axi_uartlite:2.0` | **9600 8N1** (Board Flow, `usb_uart`) |
| `axi_gpio_0` | `axi_gpio:2.0` | `C_IS_DUAL=1`, CH1/CH2 폭 3, **`C_ALL_OUTPUTS=1` / `C_ALL_OUTPUTS_2=1`** |
| `axi_gpio_1` | `axi_gpio:2.0` | `C_IS_DUAL=0`, 폭 3, **`C_ALL_OUTPUTS=1`** |
| `myip_heartbeat_monit_0` | `user.org:user:myip_heartbeat_monitor:1.0` | Custom IP (A) |
| `fault_manager_ip_0` | `user.org:user:fault_manager_ip:1.0` | Custom IP (B) |
| `safety_controller_0` | `user.org:user:safety_controller:1.0` | Custom IP (C) |
| `eval_tick_generator_0` | `xilinx.com:module_ref:eval_tick_generator:1.0` | **Module Reference** (Custom IP 아님) |
| `led_concat` | `xlconcat:2.1` | `NUM_PORTS=8` — LED 묶음 |

> **AXI GPIO 두 개가 모두 출력 전용**이라는 게 이 프로젝트 범위를 결정한다.
> 보드 스위치를 읽을 수 없으므로 Fault 주입은 전부 MicroBlaze → GPIO 출력이다.

---

## 2. 외부 포트 — 4개뿐

| 포트 | 방향 | 폭 | 핀 | 비고 |
|---|---|---|---|---|
| `sys_clock` | I | 1 | `W5` | 100 MHz |
| `reset` | I | 1 | `U18` | **btnC**. 유일한 물리 입력 |
| `usb_uart` | Master (`uart_rtl:1.0`) | — | `B18` rxd / `A18` txd | |
| `led` | O | **16** | U16 E19 U19 V19 W18 U15 U14 V14 V13 V3 W3 U3 P3 N3 P1 L1 | |

XDC: `SOC_Pr/soc_project/soc_project.srcs/constrs_1/imports/digilent-xdc-master/Basys-3-Master.xdc`
프로젝트에 등록된 제약 파일은 **이 하나뿐**이다 (`soc_project.xpr`).

**`create_clock` 은 XDC에 없다** — 11행이 `#create_clock -add ...` 로 주석 처리되어 있다.
primary clock은 BD의 Clocking Wizard가 만드는 것 하나뿐이며, 이것이
`TIMING-6` Critical Warning 2건과 `multiple_clock` 2,730건을 없앤 조치다.
→ 되살리면 그대로 부활한다. (`docs/mission_soc_impl_methodology.md` 3.1)

---

## 3. 신호 체인 — BD net 실측

```text
                 axi_gpio_1 CH1 (out)
                        │ heartbeat_async[2:0]
                        ▼
        ┌───────────────────────────────┐
        │  myip_heartbeat_monit_0  (A)  │  2FF sync → edge det → 장치별 counter
        └───────┬──────────────┬────────┘
        alive[2:0]        timeout[2:0]
                │              ├──────────────────┐
                ▼              ▼                  │
          led_concat In4   led_concat In5         │
                                                  ▼
   axi_gpio_0 CH1 ─ error_flag[2:0] ──▶ ┌──────────────────────────┐
   axi_gpio_0 CH2 ─ critical_fault[2:0]▶│ fault_manager_ip_0  (B)  │
                                        └──┬────┬────┬────┬────────┘
                          fault_level[1:0]─┤    │    │    │
                          fault_device[1:0]─────┤    │    │
                          fault_code[7:0]───────────┤    │
                          fault_valid ──────────────────┤
                                        │    │    │    │
                                        ▼    ▼    ▼    ▼
                              ┌────────────────────────────┐
                              │  safety_controller_0  (C)  │
                              └──┬─────┬─────┬─────┬───────┘
                    system_state[1:0]  │     │     │
                    output_enable[2:0]─┘     │     │
                    actuator_enable ─────────┘     │
                    control_valid ─────────────────┘
                                        │
                                        ▼  led_concat In0~In3
                                     led[15:0]

   eval_tick_generator_0.eval_tick ──┬─▶ fault_manager_ip_0.eval_tick
                                     └─▶ safety_controller_0.eval_tick
```

**검증된 규칙 (BD net 실측으로 확인)**

| 규칙 | 상태 |
|---|---|
| `alive` → `fault_manager` 연결 **금지** | ✅ `alive`는 `led_concat/In4` 로만 간다 |
| `output_enable` → `device_enable` 연결 **금지** | ✅ `output_enable`은 `led_concat/In1` 로만 간다 |
| `eval_tick` 을 B·C가 **같은 소스, 같은 포트명**으로 공유 | ✅ 하나의 net이 두 IP로 |
| `timeout` 이 A→B **직접 연결** (MicroBlaze 중개 없음) | ✅ |
| `fault_level/device/code/valid` 가 B→C **직접 연결** | ✅ |
| `eval_tick_generator` reset은 **active-high** | ✅ `proc_sys_reset_0/peripheral_reset` |
| AXI reset은 `peripheral_aresetn` (active-low) | ✅ 세 Custom IP 모두 |

---

## 4. `eval_tick_generator` — 공통 1클럭 Pulse

```verilog
module eval_tick_generator #(parameter integer DIVISOR = 100_000)
    (input wire clk, input wire reset, output wire eval_tick);
```

- `DIVISOR = 100,000` @ 100 MHz → **1 ms 주기, 1 clock 폭 pulse**
- `reset=1` 동안 `eval_tick=0`, 내부 counter=0
- reset 해제 후 `DIVISOR` 클럭을 센 뒤 첫 pulse
- Testbench는 `DIVISOR` Parameter만 줄인다 (단위 TB는 `DIVISOR=20`)
- **AXI 레지스터 없음 → 네 번째 Custom IP가 아니다**

용도: **Fault 지속 Count**(B)와 **Recovery Count**(C)가 같은 시간 단위를 쓰게 함.

파일: `rtl/eval_tick_generator.v` (정본) = `SOC_Pr/soc_project/soc_project.srcs/sources_1/imports/rtl/eval_tick_generator.v`

---

## 5. Custom IP 레지스터 맵 (정본)

Offset은 세 IP 모두 `SOC_Pr_Vitis/soc_prj/src/mission_ip_regs.h` 가 정본이고, `00` 9장과 일치한다.

### 5.1 `myip_heartbeat_monitor` — Base `0x44A1_0000`

| Offset | 이름 | 접근 | 의미 |
|---:|---|---|---|
| `0x00` | `CTRL` | RW/W1P | bit0 ENABLE, bit1 **CLEAR_ALL (W1P)**, bit2 AUTO_RECOVER |
| `0x04` | `STATUS` | R | bit[2:0] ALIVE, **bit[10:8] TIMEOUT** |
| `0x08` | `TIMEOUT0` | RW | Device 0 Timeout clocks |
| `0x0C` | `TIMEOUT1` | RW | Device 1 |
| `0x10` | `TIMEOUT2` | RW | Device 2 |
| `0x14` | `LAST_COUNT0` | R | Device 0 경과 clock |
| `0x18` | `LAST_COUNT1` | R | |
| `0x1C` | `LAST_COUNT2` | R | |
| `0x20` | `IRQ_EN` | RW | bit[2:0] |
| `0x24` | `IRQ_STATUS` | R/W1C | bit[2:0] Timeout Pending |

- `CLEAR_ALL` = Counter/Timeout Clear, **IRQ Pending은 건드리지 않음**
- `IRQ_STATUS` W1C = Pending만 Clear, **Timeout 상태·Counter는 유지**
- `enable=0` → counter=0, alive=0, timeout=0, timeout_event=0
- **`LAST_COUNTn` 이 하드웨어 시간 기준**이다. UART 송신으로 CPU가 수십 ms 멈춰도
  Heartbeat 생성 주기 판정이 정확한 이유 (`hb_gen.c`)

### 5.2 `fault_manager_ip` — Base `0x44A0_0000`

| Offset | 이름 | 접근 | 의미 |
|---:|---|---|---|
| `0x00` | `CTRL` | RW/W1P | bit0 ENABLE, bit1 **RESET_FAULT (W1P)** |
| `0x04` | `FAULT_INPUT` | R | `[2:0]` timeout, `[10:8]` error_flag, `[18:16]` critical_fault |
| `0x08` | `CRITICAL_MASK` | RW | bit[2:0], 기본 `0x4` |
| `0x0C` | `PERSIST_LIMIT` | RW | **bit[7:0]** — 256 이상은 펌웨어가 거부 |
| `0x10` | `FAULT_LEVEL` | R | bit[1:0] |
| `0x14` | `FAULT_DEVICE` | R | bit[1:0] |
| `0x18` | `FAULT_CODE` | R | bit[7:0] |
| `0x1C` | `FAULT_COUNT` | R | `[7:0]` cnt0, `[15:8]` cnt1, `[23:16]` cnt2 |
| `0x20` | `IRQ_EN` | RW | bit0 Fault Change |
| `0x24` | `IRQ_STATUS` | R/W1C | bit0 Fault Change Pending |
| **`0x2C`** | **`ID`** | **R** | **`0x464D4752` ("FMGR") — 추가분** |

> `0x2C ID` 는 `00` 9.2 확정 맵에 **없다.** `02_MEMBER_B` 6장에는 "2026-07-30 승인"으로 반영되어
> 있으나 `docs/fault_manager_integration.md` 의 CHANGE REQUEST는 아직 미승인 체크박스다. → C-10
> 용도: 보드 브링업에서 AXI 주소 매핑 성립 여부를 즉시 확인 (`main.c` 155행 `FM_SelfCheck()`)

`RESET_FAULT` 동작 (`fault_manager_core.v` 104행):

```verilog
wire reset_fault_ok = reset_fault_pulse && (device_fault == 3'b000);
```

→ **활성 Fault가 하나라도 있으면 무시**. Level 2를 Count만 지워 Level 1로 낮추는 동작은 금지.

### 5.3 `safety_controller` — Base `0x44A2_0000`

| Offset | 이름 | 접근 | 의미 |
|---:|---|---|---|
| `0x00` | `CTRL` | RW/W1P | bit0 ENABLE, bit1 **MANUAL_RESET (W1P)** |
| `0x04` | `SYSTEM_STATE` | R | bit[1:0] |
| `0x08` | `OUTPUT_ENABLE` | R | bit[2:0] |
| `0x0C` | `DEGRADE_MASK` | RW | bit[2:0] |
| `0x10` | `RECOVERY_COUNT` | RW | **bit[15:0]** |
| `0x14` | `STATE_TIMER` | R | **100 MHz clock count** (포화) |
| `0x18` | `IRQ_EN` | RW | bit0 State Change |
| `0x1C` | `IRQ_STATUS` | R/W1C | bit0 State Change Pending |

> **`actuator_enable` / `control_valid` 는 AXI로 읽을 수 없다.** 명세 9.3에 레지스터가 없기 때문.
> 관측 경로는 (a) 하드웨어 핀 → `led_concat` → LD5/LD6, (b) `$MISSION` 필드는 펌웨어가
> `system_state`에서 **유도**한 값 (`sc_regs.c` 122~132행).
> 슬라이드에 "레지스터로 읽는다"고 쓰면 안 된다.

> **`STATE_TIMER` 단위 주의.** 레지스터는 clock count, `$MISSION` 으로 나가는 값은
> 펌웨어가 ms로 환산한 것이다 (`sc_regs.c` 87행 `CLK_TO_MS`). 문서 `03` 11.1은
> "STATE_TIMER (Offset 0x14)"라고만 적어 clock count로 오해할 수 있다. → C-21

### 5.4 세 IP 공통 CTRL 주의점

> 세 IP 모두 CTRL이 **RW(ENABLE) + W1P 혼합**이다. RTL이 CTRL Write마다 ENABLE을
> `wdata[0]`으로 덮어쓰므로, **W1P를 쏠 때 ENABLE을 같이 실어야 IP가 꺼지지 않는다.**
> 그래서 각 드라이버(`hb_regs.c` / `fm_regs.c` / `sc_regs.c`)가 **CTRL Shadow**를 들고 있다.
> (`mission_ip_regs.h` 9~11행) — 통합 트러블슈팅 슬라이드 소재로 좋다.

---

## 6. RTL 파일 구조 — 실제 배치

| IP | Core | AXI Wrapper | 마법사 Top |
|---|---|---|---|
| Heartbeat (A) | `ip_repo/myip_heartbeat_monitor_1_0/src/heartbeat_monitor.v` | (없음 — S00_AXI 안에 통합) | `hdl/myip_heartbeat_monitor.v` + `hdl/..._slave_lite_v1_0_S00_AXI.v` |
| Fault Manager (B) | `ip_repo/fault_manager_ip_1_0/src/fault_manager_core.v` | `src/fault_manager_axi.v` | `hdl/fault_manager_ip.v` + `hdl/..._S00_AXI.v` |
| Safety (C) | `ip_repo/safety_controller_1_0/hdl/safety_controller.v` | (없음 — S00_AXI 안에 통합) | `hdl/..._slave_lite_v1_0_S00_AXI.v` |

> **"3개 IP 모두 core/axi를 분리했다"고 말하면 안 된다.** 실제로 core/axi가 파일로 분리된 건
> **Fault Manager 하나**다. `00` 15장·`01` 1장·`03` 1장의 파일명 권장안과 다르다. → C-14
> 다만 Testbench는 세 IP 모두 core/axi 두 계층으로 나뉘어 있다
> (`sim/tb_heartbeat_monitor.v` 안에 `tb_heartbeat_monitor_core` + `tb_heartbeat_monitor_axi` 두 모듈).

정본 RTL 사본 위치 (동일 내용 2벌 존재):

```text
rtl/                                                    ← 정본/참조
SOC_Pr/soc_project/soc_project.srcs/sources_1/imports/rtl/   ← 프로젝트 등록본
SOC_Pr/ip_repo/*/src/ , */hdl/                          ← IP 패키징본
```

---

## 7. AXI INTC 설정

IRQ가 Level 방식이므로 INTC를 Level-High로 둔다 (`docs/fault_manager_integration.md` 82~87행):

```tcl
set_property CONFIG.C_KIND_OF_INTR {0x00000000} [get_bd_cells <intc>]
set_property CONFIG.C_KIND_OF_LVL  {0xFFFFFFFF} [get_bd_cells <intc>]
```

IRQ 전체 경로 (검증 대상, `04` 5.2):

```text
IRQ_STATUS Set → Custom IP irq High → xlconcat → AXI INTC Pending
  → XIntc Handler → IRQ_STATUS W1C → INTC 처리 완료 → irq Low
```

`irq` 핀은 `IRQ_EN`이 게이팅하지만 **`IRQ_STATUS`의 Set은 `IRQ_EN`과 무관**하다:

```verilog
if (fault_change_event) reg_irq_status <= 1'b1;     // SET 은 irq_en 과 무관
assign irq = reg_irq_status & reg_irq_en;           // 핀만 irq_en 이 막는다
```

→ `SET,IRQ_EN,0` 으로 ISR을 멈추면 Pending이 래치돼 눈으로 볼 수 있다.
이것이 **W1C 동작을 증명하는 유일한 방법**이다 (`05` 15-1~15-7단계).

---

## 8. 구현 결과 — ⚠ 값 충돌 상태

`docs/mission_soc_impl_methodology.md` 기준:

```text
Vivado         : 2024.2
Board          : Basys 3 (xc7a35tcpg236-1)
Top            : mission_soc_wrapper
BD             : mission_soc
Synthesis      : Complete
Implementation : write_bitstream Complete
```

| 지표 | `impl_methodology` | `Mission_SoC_PPT_Audit_v3.md` | 판정 |
|---|---|---|---|
| WNS | `0.963 ns` | `+0.198 ns` | ⚠ **충돌** |
| TNS | `0.000` | `0.000 ns` | 일치 |
| WHS | `0.029 ns` | `+0.033 ns` | ⚠ **충돌** |
| Failed Routes | `0` | — | |
| `multiple_clock` | `0` (이전 2,730) | `0` | 일치 |
| Slice LUT | `2500` | `3,039 / 20,800 = 14.61%` | ⚠ **충돌** |
| Slice Register | 미기재 | `2,646 / 41,600 = 6.36%` | |
| BRAM | `32` | `32 / 50 = 64.0%` | 일치 |
| DSP | `0` | `0 / 90` | 일치 |
| Total Power | `0.202 W` | 미기재 | |

**저장소에 `soc_project.runs/impl_1/*.rpt` 가 없다.** → 코드로 판정 불가. C-01 참조.

Methodology DRC (같은 문서 2장):

| Rule | Severity | 건수 | 처리 |
|---|---|---:|---|
| `TIMING-6` | Critical Warning | **0** | 3.1 클럭 중복 정의 제거로 해결 |
| `TIMING-56` | — | **0** | 〃 |
| `TIMING-9` | Warning | 1 | Unknown CDC. `heartbeat_async`에 `ASYNC_REG` 2FF 적용됨 |
| `TIMING-18` | Warning | 19 | **의도적 예외** — 비동기 외부 I/O라 참조 클럭이 없음 |
| `LUTAR-1` | Warning | 2 | **해결 불가** — MicroBlaze V IP 내부 Serial Debug 셀 |

`TIMING-18` 내역: `no_input_delay(2)` = `reset`, `usb_uart_rxd` / `no_output_delay(17)` = `usb_uart_txd`, `led[15:0]`

> `LUTAR-1` 질문 대응 표준 답변:
> "MicroBlaze RISC-V 디버그 유닛 내부 구조에서 발생하는 경고이며 사용자 설계 로직과 무관하다.
> 디버그 전용 경로라 기능에 영향이 없다."
