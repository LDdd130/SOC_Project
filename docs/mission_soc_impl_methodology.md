# `mission_soc` Implementation 결과 및 Methodology 미해결 항목

> 상태: **비트스트림 생성 완료, 보드 동작 가능.**
> Methodology Critical Warning 2건은 실제 타이밍 위반이 아니며 추후 정리 예정.
> 작성일: 2026-07-28

---

## 1. 빌드 결과

```text
Vivado         : 2024.2
Board          : Basys 3 (xc7a35tcpg236-1)
Top            : mission_soc_wrapper
BD             : mission_soc
Synthesis      : synth_design Complete
Implementation : write_bitstream Complete
```

### 1.1 타이밍

> **갱신 (2026-07-30).** 3.1 의 `create_clock` 중복 정의를 제거하고 재구현했다.
> 아래는 그 결과(`impl_1`, 2026-07-30 15:44)이며 이전 값이 아니다.

| 지표 | 값 | 판정 |
|---|---:|---|
| WNS (Worst Negative Slack) | `0.963 ns` | 통과 (양수) |
| TNS (Total Negative Slack) | `0.000` | 위반 없음 |
| WHS (Worst Hold Slack) | `0.029 ns` | 통과 (양수) |
| THS (Total Hold Slack) | `0.000` | 위반 없음 |
| Failed Routes | `0` | 통과 |
| `check_timing` multiple_clock | `0` | **이전 2,730 → 0** |

100 MHz(주기 10 ns)에서 setup/hold 모두 여유가 있으며 라우팅 실패도 없다.
클럭 중복 정의가 사라지면서 multiple-clock register pin 2,730개가 전부 없어졌다.

### 1.2 리소스 / 전력

```text
LUT        : 2500
BRAM       : 32
URAM / DSP : 0
Total Power: 0.202 W
```

---

## 2. Methodology 결과 : Critical Warning 0 + Warning 22

리포트 경로:

```text
SOC_Pr/soc_project/soc_project.runs/impl_1/mission_soc_wrapper_methodology_drc_routed.rpt
```

### 2.1 현재 (2026-07-30 재구현 후)

| Rule | Severity | Checks | 설명 | 조치 |
|---|---|---:|---|---|
| `TIMING-9` | Warning | 1 | Unknown CDC Logic | 잔존 — 2.3 |
| `TIMING-18` | Warning | 19 | Missing input or output delay | **의도적 예외** — 2.2 |
| `LUTAR-1` | Warning | 2 | LUT drives async reset alert | **해결 불가 (Xilinx IP 내부)** — 4장 |

**`TIMING-6` Critical Warning 0건.** `TIMING-56` 도 0건이다. 둘 다 3.1 의 클럭
중복 정의를 제거하면서 사라졌다.

전 항목이 `Related violations: <none>` 이다. 즉 **실제 타이밍 위반 경로는 0개**이며,
설계 스타일에 대한 권고 수준의 경고다.

### 2.2 `TIMING-18` ×19 는 의도적 예외다

`check_timing` 내역:

```text
no_input_delay  (2)   : reset, usb_uart_rxd
no_output_delay (17)  : usb_uart_txd, led[15:0]
```

전부 **비동기 외부 I/O** 라 참조할 송신/수신 클럭 자체가 없다.

| 포트 | 성격 | I/O delay 를 걸 수 없는 이유 |
|---|---|---|
| `reset` (btnC) | 사람이 누르는 푸시버튼 | 클럭과 무관. `proc_sys_reset` 이 내부에서 동기화한다 |
| `usb_uart_rxd` / `txd` | 9600 8N1 비동기 시리얼 | 클럭 동봉이 없는 프로토콜. UARTLite 가 16× 오버샘플링으로 복원한다 |
| `led[15:0]` | 사람이 보는 LED | 수신단이 사람 눈이다. setup/hold 개념이 없다 |

즉 `set_input_delay` / `set_output_delay` 에 넣을 의미 있는 숫자가 존재하지
않는다. 억지로 0 을 넣으면 리포트에서 경고만 사라지고 검증 강도는 그대로다.
따라서 **제약을 추가하지 않고 이 문서로 예외를 명시**한다. 04 체크리스트의
판정 기준은 `TIMING-6` Critical Warning 0건이고, 그 조건은 충족했다.

보드 I/O 를 나중에 추가하더라도(SW/BTN/FND/RGB — 00 문서 12.3, 이번 빌드
범위 밖) 전부 같은 성격의 비동기 I/O 라 이 예외가 그대로 적용된다.

### 2.3 `TIMING-9` ×1 (Unknown CDC Logic)

UART 와 reset 계열의 비동기 경로에서 나온다. 실제 CDC 커버리지는 `report_cdc`
로 확인한다. 기존 구현 결과를 열어서 리포트만 뽑으면 되고 **재합성은 필요 없다**:

```tcl
open_run impl_1
report_cdc -details -file /home/user7/workspace_ondevice_3/SOC_Project/docs/report_cdc.rpt
```

`heartbeat_monitor_channel` 은 `heartbeat_async` 에 대해 이미
`(* ASYNC_REG = "TRUE" *)` 2FF 동기화를 넣어 두었다 (04 체크리스트 5.1 요구사항).

---

## 3. 조치 이력

> **상태 (2026-07-30).** 3.1 은 **적용 완료**. 3.2 는 **적용하지 않기로 확정**
> (2.2 참고 — 넣을 수 있는 의미 있는 숫자가 없어서 경고만 가리는 조치가 된다).

### 3.1 `TIMING-6` — 클럭 중복 정의 (Critical Warning ×2) — **해결됨**

리포트 원문:

```text
TIMING-6#1 Critical Warning
The clocks clk_out1_mission_soc_clk_wiz_0 and clk_out1_mission_soc_clk_wiz_0_1
are related (timed together) but they have no common primary clock.
```

**원인**

Block Design 에 `clk_wiz` 가 있으면 Vivado 가 BD 최상위 포트 `sys_clock`
(`FREQ_HZ = 100000000`) 에 대한 클럭 제약을 자동 생성한다.
여기에 Digilent 마스터 XDC 의 기본 줄이 `-add` 로 클럭을 하나 더 얹으면서
같은 포트에 클럭이 2개가 되었고, 그 결과 MMCM 출력 클럭도
`clk_out1_..._0` / `clk_out1_..._0_1` 둘로 갈라졌다.

문제의 줄 (`Basys-3-Master.xdc`):

```tcl
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports sys_clock]
```

**해결 (적용 완료)**

`Basys-3-Master.xdc` 에서 해당 줄을 제거했다. 현재 활성 XDC 에는 `create_clock`
이 한 줄도 없고, primary clock 은 BD 의 Clock Wizard 가 만드는 것 하나뿐이다.

재구현 결과: `TIMING-6` 0건, `TIMING-56` 0건, `multiple_clock` 2,730 → 0.

> **되살리지 말 것.** `constraints/mission_soc.xdc` 에도 같은 줄이 있었고
> 2026-07-30 에 주석 처리 + 경고 주석을 달아 두었다. 이 파일을 `constrs_1`
> 에 다시 추가하면 2,730건이 그대로 부활한다.

### 3.2 `TIMING-18` — 비동기 I/O delay 누락 — **적용하지 않음**

재구현 후 대상이 3개에서 19개로 늘었다 (`led[15:0]` 이 BD 최상위로 나오면서).

```text
no_input_delay  (2)   : reset, usb_uart_rxd
no_output_delay (17)  : usb_uart_txd, led[15:0]
```

한때 아래 제약을 넣는 안을 검토했다:

```tcl
# 검토했으나 채택하지 않음
set_false_path -from [get_ports reset]
set_false_path -from [get_ports usb_uart_rxd]
set_false_path -to   [get_ports usb_uart_txd]
set_false_path -to   [get_ports {led[*]}]
```

**채택하지 않은 이유** — 2.2 에 적은 대로 이 포트들은 참조 클럭이 없는 비동기
I/O 라 `set_false_path` 를 걸어도 검증이 강해지지 않고 리포트의 경고 줄만
사라진다. 판정 기준인 `TIMING-6` Critical Warning 0건은 이미 충족했으므로,
제약을 추가해 재합성하는 대신 **2.2 에 예외 근거를 명시하는 것으로 갈음한다.**
재합성 0회이므로 BIT/XSA/ELF 를 다시 만들 필요도 없다.

### 3.3 적용 절차

1. 위 3.1 주석 처리 + 3.2 세 줄 추가
2. Synthesis 를 열고 클럭 제약이 살아 있는지 먼저 확인

   ```tcl
   report_clocks
   ```

   `sys_clock` 에 period `10.000` 클럭이 **하나** 잡혀 있어야 한다.
   아무것도 없으면 `clk_wiz` 자동 제약이 안 걸린 것이므로 `-add` 없이 되살린다.

   ```tcl
   create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} [get_ports sys_clock]
   ```

3. `Reset Runs` → `Generate Bitstream` 재실행
4. 기대 결과: **Critical Warning 2 → 0**, `TIMING-56` 2 → 0

> **이 절차는 2026-07-30 에 이미 수행했다.** 실측 결과는 1.1 / 2.1 에 있다.
> 다시 돌릴 필요 없다.

---

## 4. 해결하지 않는 항목 — `LUTAR-1` ×2

```text
mission_soc_i/microblaze_riscv_0/U0/riscv_core_I/Base.Core/Decode_I/
  Serial_Dbg_Intf.abstractcs_busy_rst_i_i_1  -> abstractcs_busy_reg/CLR

mission_soc_i/microblaze_riscv_0/U0/riscv_core_I/Base.Core/Use_Debug_Logic.
  Master_Core.Debug_Perf/Serial_Dbg_Intf.resume_rst_i_i_1 -> resumeack_reg/PRE
```

`microblaze_riscv` IP 의 **Serial Debug Interface 내부 셀**이다.
사용자 로직이 아니라 Xilinx IP 구조에서 발생하며 수정 대상이 아니다.
디버그 전용 경로라 정상 동작에 영향이 없다.

발표/제출 시 질문을 받으면 다음과 같이 답한다.

> MicroBlaze RISC-V 디버그 유닛 내부 구조에서 발생하는 경고이며
> 사용자 설계 로직과 무관하다. 디버그 전용 경로라 기능에 영향이 없다.

---

## 5. 04 체크리스트 7장 산출물 연계

| 04 §7 항목 | 상태 |
|---|---|
| Utilization | LUT 2500 / BRAM 32 — 캡처 필요 |
| Timing Summary | WNS 0.963 / WHS 0.029 / Failed Routes 0 — 캡처 필요 |
| Methodology | Critical Warning 0 — 캡처 필요 |
| `report_cdc` | 2.3 의 명령으로 생성 후 첨부 |
| Vivado Block Design 캡처 | 필요 |
| Testbench 결과 | `tb_logs_batch/` 에 8개 로그, 총 4,533 checks / 0 fail — 6장 |

`Open Implemented Design` → `Report Utilization` / `Report Timing Summary` 에서 캡처한다.

---

## 6. 시뮬레이션 검증 결과 (2026-07-30)

`run_tb_batch.sh` 로 Vivado GUI 없이 batch(`xvlog`/`xelab`/`xsim`) 실행한 결과다.
GUI 로 돌리면 이 PC(RAM 15GB)에서 Vivado 가 8GB 를 점유한 위에 시뮬레이터가
얹혀 크래시한다.

| Testbench | checks | fail |
|---|---:|---:|
| `tb_heartbeat_monitor_core` | 80 | 0 |
| `tb_heartbeat_monitor_axi` | 60 | 0 |
| `tb_fault_manager_core` | 4,146 | 0 |
| `tb_fault_manager_axi` | 73 | 0 |
| `tb_safety_controller_core` | 44 | 0 |
| `tb_safety_controller_axi` | 64 | 0 |
| `tb_eval_tick_generator` | 5 | 0 |
| `tb_mission_soc_top` | 61 | 0 |
| **합계** | **4,533** | **0** |

`tb_mission_soc_top` 은 `mission_soc.bd` 의 net 배선을 그대로 옮긴 통합 TB 로,
`NORMAL → WARNING → DEGRADED → SAFE_MODE → (manual reset) → NORMAL` 전이와
전역 Disable 안전 출력을 체인 전체에서 확인한다.

`tb_fault_manager_axi` / `tb_heartbeat_monitor_axi` / `tb_safety_controller_axi`
는 AW/W 도착 순서 변경, WSTRB 부분 쓰기, BREADY/RREADY backpressure, 백투백
연속 요청, AXI Protocol Monitor(Stall 중 VALID/Payload 변경 감시)를 포함한다.

로그: `tb_logs_batch/<top>.log`

---

## 6. 현재 XDC 상태

`SOC_Pr/soc_project/soc_project.srcs/constrs_1/imports/digilent-xdc-master/Basys-3-Master.xdc`

활성 제약:

```tcl
set_property -dict { PACKAGE_PIN W5  IOSTANDARD LVCMOS33 } [get_ports sys_clock]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports sys_clock]  ;# TODO 3.1
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports reset]
set_property -dict { PACKAGE_PIN B18 IOSTANDARD LVCMOS33 } [get_ports usb_uart_rxd]
set_property -dict { PACKAGE_PIN A18 IOSTANDARD LVCMOS33 } [get_ports usb_uart_txd]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO      [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33  [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
```

주석으로 남겨둔 것 (나중에 사용):

```text
led[0..2]  U16 / E19 / U19   -> C 의 system_state 표시
btnU       T18               -> MANUAL_RESET (00 공통명세 12.3)
btnD       U17               -> IRQ_STATUS W1C
sw[0..2]   V17 / V16 / W16   -> 04 체크리스트 5.1 (2FF Synchronizer 필요)
```
