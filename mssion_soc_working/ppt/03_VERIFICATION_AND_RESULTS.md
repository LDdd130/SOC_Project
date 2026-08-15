# 03. 검증과 결과 — 무엇을 어디서 증명했나

발표에서 가장 많이 찔리는 부분이다. **"검증했다"의 근거가 어느 파일인지**를 장별로 정리했다.

---

## 1. 검증 3계층

```text
① RTL Testbench (sim/)            클럭 단위 · 전수 조합 · 경계조건
       ↓ 커버 못 하는 것
② 보드 + UART (05 시나리오)        실제 하드웨어에서 GUI로 낼 수 있는 전 기능
       ↓ 커버 못 하는 것
③ Vivado 구현 리포트               Timing / Utilization / Methodology DRC
```

**각 계층이 커버 못 하는 것을 명시하는 게 이 프로젝트 검증 서술의 강점이다.**

| 항목 | 보드+UART로 검증 불가한 이유 | 대체 근거 |
|---|---|---|
| `DEGRADED → WARNING` 하강 | `persist_cnt`가 255에서 포화, `PERSIST_LIMIT` 최대도 255 → Fault가 살아 있는 채로 Level 2→1을 만들 UART 수단이 없음 | `sim/tb_safety_controller_core.v` |
| `WARNING → NORMAL` (RECOVERY_COUNT 연속 확인) | `RECOVERY_COUNT=2` → 2 ms. 사람이 조작할 시간 창이 아님 | 같은 TB |
| 클럭 단위 동시 다중 Fault | UART 9600 bps, 관측 분해능 ms | `sim/tb_fault_manager_core.v` |
| 100 MHz 클럭 단위 타이밍 | 〃 | 각 IP TB |

---

## 2. Testbench 목록 — 파일 실측

`sim/` 에 파일 7개, **모듈 8개** (`tb_heartbeat_monitor.v` 안에 core/axi 두 모듈).

| 모듈 | 파일 | 검증 범위 |
|---|---|---|
| `tb_heartbeat_monitor_core` | `sim/tb_heartbeat_monitor.v:3` | Counter, Timeout, Alive, AUTO_RECOVER, CLEAR_ALL, Saturation |
| `tb_heartbeat_monitor_axi` | `sim/tb_heartbeat_monitor.v:409` | AXI R/W, W1P, W1C, Reset 기본값 |
| `tb_fault_manager_core` | `sim/tb_fault_manager_core.v` | 정책 21항목 + **전수 4,096 조합** |
| `tb_fault_manager_axi` | `sim/tb_fault_manager_axi.v` | AXI R/W, W1P, W1C, IRQ Level, RESET_FAULT, Disable |
| `tb_safety_controller_core` | `sim/tb_safety_controller_core.v` | FSM 26항목, Recovery Count, SAFE Latch |
| `tb_safety_controller_axi` | `sim/tb_safety_controller_axi.v` | AXI R/W, W1P, W1C |
| `tb_eval_tick_generator` | `sim/tb_eval_tick_generator.v` | Reset 중 0, DIVISOR 뒤 첫 pulse, 폭 1 clock, 주기 |
| `tb_mission_soc_top` | `sim/tb_mission_soc_top.v` | **`mission_soc.bd` net 배선을 그대로 옮긴 통합 TB** |

추가 TB (`verification/tb_fault_manager_axi/`):
`A11_irq_gating.v` / `A12_count_packing.v` / `A13_fault_input_packing.v`

**AXI TB 3종이 공통으로 포함하는 것** (`impl_methodology` 6장):
AW/W 도착 순서 변경, WSTRB 부분 쓰기, BREADY/RREADY backpressure, 백투백 연속 요청,
AXI Protocol Monitor(Stall 중 VALID/Payload 변경 감시)

`tb_mission_soc_top` 이 확인하는 것:
`NORMAL → WARNING → DEGRADED → SAFE_MODE → (manual reset) → NORMAL` 전이 + 전역 Disable 안전 출력

---

## 3. ⚠ Testbench check 수 — 값이 충돌한다

### 3-A. `docs/mission_soc_impl_methodology.md` 6장 (2026-07-30, `run_tb_batch.sh` 결과)

| Testbench | checks | fail |
|---|---:|---:|
| `tb_heartbeat_monitor_core` | 80 | 0 |
| `tb_heartbeat_monitor_axi` | 60 | 0 |
| `tb_fault_manager_core` | 4,146 | 0 |
| **`tb_fault_manager_axi`** | **73** | 0 |
| `tb_safety_controller_core` | 44 | 0 |
| `tb_safety_controller_axi` | 64 | 0 |
| `tb_eval_tick_generator` | 5 | 0 |
| `tb_mission_soc_top` | 61 | 0 |
| **합계** | **4,533** | **0** |

→ `README.md` 92행이 인용하는 값. 산술 검산: 80+60+4146+73+44+64+5+61 = **4,533 ✅ 내부 정합**

### 3-B. `verification/` 최종 검증 문서

| 문서 | 값 |
|---|---|
| `tb_fault_manager_core/...md` | `checks = 4146, errors = 0, ALL PASS` — **3-A와 일치** |
| `tb_eval_tick_generator/...md` | `checks = 5, errors = 0, ALL PASS` — **3-A와 일치** |
| `tb_fault_manager_axi/...md` | 메인 TB **46** + A11 **6** + A12 **4** + A13 **4** = **60** — ⚠ **3-A의 73과 불일치** |

### 3-C. `Mission_SoC_PPT_Audit_v3.md` 4장

`4146` + `60`(46+14) + `5` 만 인용. 나머지 5개 TB는 "추가 권장"으로 적혀 있으나 3-A에 결과가 있다.

### 3-D. `docs/fault_manager_integration.md` 8장

세 TB 모두 **"재실행 필요"** 로 남아 있고 "이전 버전의 2076 checks는 무효"라고만 적혀 있다.
→ 이 문서는 **통합 이전 시점 상태**다. C-12

### 판정

**세 문서가 서로 다르다. 발표 전 재실행이 유일한 해결책이다.**

```bash
# 저장소에 run_tb_batch.sh 가 없으므로 개별 실행 (Icarus 예시)
iverilog -g2005 -o /tmp/fm_core rtl/fault_manager_core.v sim/tb_fault_manager_core.v && vvp /tmp/fm_core
iverilog -g2005 -o /tmp/fm_axi  rtl/fault_manager_core.v rtl/fault_manager_axi.v sim/tb_fault_manager_axi.v && vvp /tmp/fm_axi
iverilog -g2005 -o /tmp/tick    rtl/eval_tick_generator.v sim/tb_eval_tick_generator.v && vvp /tmp/tick
# 또는 Vivado batch: xvlog / xelab / xsim
```

**8개 로그를 다시 뽑아 `tb_logs_batch/` 로 저장소에 넣고, 그 숫자만 슬라이드에 쓸 것.**

---

## 4. `tb_fault_manager_core` 전수 검증 — 발표 하이라이트

```text
timeout / error_flag / critical_fault : 2^9 = 512 조합
critical_mask                          : 4종 (100 / 111 / 000 / 010)
지속 성립 / 미성립                     : 2종
─────────────────────────────────────────────
Reference model 대조                   : 512 × 4 × 2 = 4,096 케이스
+ 02 문서 필수 21항목                   = checks 4,146
```

시뮬레이션 조건: 100 MHz, `persist_limit=3`, `critical_mask=3'b100`, 종료 `196,540 ns`

**말할 포인트**: 정책표(`docs/fault_policy_table.md`)를 같은 규칙에서 생성했으므로
**표와 RTL이 구조적으로 일치**한다. 손으로 고른 몇 케이스가 아니라 입력 공간 전수다.

---

## 5. ⚠ 구현 결과 — 값이 충돌한다

| 지표 | `docs/mission_soc_impl_methodology.md` | `Mission_SoC_PPT_Audit_v3.md` | `README.md` |
|---|---|---|---|
| WNS | `0.963 ns` | `+0.198 ns` | `+0.963 ns` |
| TNS | `0.000` | `0.000 ns` | — |
| WHS | `0.029 ns` | `+0.033 ns` | `+0.029 ns` |
| THS | `0.000` | — | — |
| Failed Routes | `0` | — | — |
| `multiple_clock` | `0` | `0` | — |
| Slice LUT | `2500` | `3,039 / 20,800 (14.61%)` | — |
| Slice Register | — | `2,646 / 41,600 (6.36%)` | — |
| BRAM | `32` | `32 / 50 (64.0%)` | — |
| DSP | `0` | `0 / 90` | — |
| Power | `0.202 W` | — | — |

`Audit_v3` 는 "기존 21~22장 슬라이드의 `multiple_clock 2,730`, `WNS +1.118`, `LUT 3,099`,
`Register 2,778` 은 현재 routed report와 불일치해 교체했다"고 적고 있다.
즉 **슬라이드에 이미 3세대째 서로 다른 숫자가 돌아다닌 이력이 있다.**

**저장소에 `SOC_Pr/soc_project/soc_project.runs/` 가 없다** → 코드로 판정 불가.

### 확정 절차 (발표 전 필수)

```tcl
open_project SOC_Pr/soc_project/soc_project.xpr
open_run impl_1
report_timing_summary -file timing_summary.rpt
report_utilization    -file utilization.rpt
report_power          -file power.rpt
report_methodology    -file methodology.rpt
report_cdc -details   -file report_cdc.rpt
```

→ 나온 값 **한 세트**로 `README.md` / `docs/mission_soc_impl_methodology.md` /
`Mission_SoC_PPT_Audit_v3.md` / 슬라이드 21~22장을 동시에 갱신.

---

## 6. Methodology DRC — 이건 서술이 일관적이다

| Rule | Severity | 건수 | 상태 |
|---|---|---:|---|
| `TIMING-6` | Critical Warning | **0** | ✅ 해결 (클럭 중복 정의 제거) |
| `TIMING-56` | — | **0** | ✅ 해결 |
| `TIMING-9` | Warning | 1 | 잔존. `heartbeat_async`에 `(* ASYNC_REG = "TRUE" *)` 2FF 적용됨 |
| `TIMING-18` | Warning | 19 | **의도적 예외** |
| `LUTAR-1` | Warning | 2 | **해결 불가** (Xilinx IP 내부) |

**전 항목 `Related violations: <none>`** → 실제 타이밍 위반 경로 0개, 설계 스타일 권고 수준.

### `TIMING-6` 해결 스토리 — **발표에 넣기 좋은 트러블슈팅 사례**

```text
[증상]  clk_out1_..._0 과 clk_out1_..._0_1 이 related 인데 common primary clock 이 없음
        Critical Warning ×2, multiple_clock register pin 2,730개

[원인]  BD에 clk_wiz 가 있으면 Vivado 가 sys_clock (FREQ_HZ=100000000) 에 대한
        클럭 제약을 자동 생성한다. 여기에 Digilent 마스터 XDC 의
          create_clock -add -name sys_clk_pin -period 10.00 ... [get_ports sys_clock]
        가 -add 로 클럭을 하나 더 얹으면서 같은 포트에 클럭이 2개가 되었고,
        MMCM 출력 클럭도 둘로 갈라졌다.

[조치]  Basys-3-Master.xdc 의 해당 줄 제거(현재 11행 주석 처리)
        → 현재 활성 XDC 에 create_clock 이 한 줄도 없다. primary clock 은 clk_wiz 하나.

[결과]  TIMING-6  2 → 0
        TIMING-56 2 → 0
        multiple_clock 2,730 → 0
```

⚠ **되살리지 말 것.** `constraints/mission_soc.xdc`(저장소에 없는 참고용 사본)에도 같은 줄이 있었다.
이 파일을 `constrs_1`에 다시 추가하면 2,730건이 부활한다.

### `TIMING-18` ×19 를 고치지 않은 근거 — 질문 대응용

```text
no_input_delay  (2)  : reset, usb_uart_rxd
no_output_delay (17) : usb_uart_txd, led[15:0]
```

| 포트 | 성격 | I/O delay 를 걸 수 없는 이유 |
|---|---|---|
| `reset` (btnC) | 사람이 누르는 푸시버튼 | 클럭과 무관. `proc_sys_reset` 이 내부 동기화 |
| `usb_uart_rxd/txd` | 9600 8N1 비동기 시리얼 | 클럭 동봉 없는 프로토콜. UARTLite 가 16× 오버샘플링으로 복원 |
| `led[15:0]` | 사람이 보는 LED | 수신단이 사람 눈. setup/hold 개념 없음 |

→ `set_input_delay` / `set_output_delay` 에 넣을 **의미 있는 숫자가 존재하지 않는다.**
억지로 0을 넣으면 리포트 경고만 사라지고 검증 강도는 그대로다.
판정 기준인 `TIMING-6` Critical Warning 0건은 이미 충족했으므로 **문서로 예외를 명시**했다.

---

## 7. 보드 통합 검증 — `05` 시나리오 28단계

**커버 범위**: GUI로 낼 수 있는 모든 제어 명령.
`GET,*` 3개 · `SET,*` 8개(TIMEOUT×3 포함) · `CMD,*` 4개 · `INJECT,*` 전부가 **최소 1회씩** 나간다.

핵심 증명 5가지:

| # | 무엇을 | 어떻게 증명 | 단계 |
|---|---|---|---|
| 1 | 단일 고장 → 등급 상승 → **해당 장치만** 차단 | `FAULT_CHANGE,2,1,2` + `oe=0x05` | 3~5 |
| 2 | **`RESET_FAULT` 거부/승인 분기** | Fault 有 → `$ERR,RESET_FAULT,FAULT_ACTIVE` / 無 → `$ACK` | 9~14 |
| 3 | **IRQ 래치 + W1C** | `SET,IRQ_EN,0` → `$IRQ,0x00,0x00,0x01,0x01` → `CLEAR_IRQ` → `$IRQ,...,0x00,0x00` | 15-1~15-5 |
| 4 | **SAFE_MODE Latch** | `fault_level` 3→0 인데 `STATE_CHANGE` 안 나옴 | 18, 22 |
| 5 | **Manual Recovery 조건부 승인** | 같은 버튼, `fault_level` 만 다른데 `$ERR` vs `$ACK` | 21 vs 23 |

`06` 시연 영상 시나리오는 이 중 ①③④⑤ 를 **6클릭 / 약 32초** 로 압축한 발췌본이다.

### `05` 15-1~15-7이 왜 중요한가

평상시 ISR이 IRQ 뜨자마자 µs 안에 W1C 하므로 `IRQ_STATUS`는 **항상 이미 0**이다.
따라서 `$ACK,CMD,CLEAR_IRQ` 는 "명령이 파싱됐다"는 뜻일 뿐 **W1C 동작 증거가 아니다.**

```verilog
if (fault_change_event) reg_irq_status <= 1'b1;   // SET 은 irq_en 과 무관
assign irq = reg_irq_status & reg_irq_en;         // 핀만 irq_en 이 막는다
```

`IRQ_EN=0` → 핀은 안 올라가는데 STATUS는 래치 → ISR 안 돎 → **Pending 이 살아남는다.**
이것이 W1C를 실제로 증명하는 **유일한 절차**다. 그리고 이 상황은 "부팅 순서 꼬임"
(IRQ_EN 켜기 전 STATUS에 값이 남는 상황)을 그대로 재현한 것이기도 하다.

> **15-7(IRQ_EN 원복)을 빠뜨리면 안 된다.** IRQ_EN이 꺼진 동안 ISR이 안 돌아
> Snapshot이 안 쌓이고, 짧게 스쳐 가는 WARNING을 놓친다. (메인 루프 폴링 백스톱은
> 살아 있어 `FAULT_CHANGE`/`STATE_CHANGE` 자체는 계속 나온다.)

---

## 8. ⚠ 저장소에 없는 증거 파일 — 발표 전 확보 필요

문서가 근거로 인용하는데 저장소에 **없는** 것들이다. 슬라이드에서 파일명을 인용할 거면 미리 확보한다.

| 파일 | 인용처 | 용도 |
|---|---|---|
| `tb_logs_batch/*.log` (8개) | `impl_methodology` 6장, `05` 5-1장 | TB check 수 근거 |
| `run_tb_batch.sh` | `impl_methodology` 6장 | 재현 절차 |
| `SOC_Pr/soc_project/soc_project.runs/impl_1/*.rpt` | `impl_methodology` 2장 | Timing/Util/Methodology |
| `docs/report_cdc.rpt` | `impl_methodology` 2.3 | CDC 커버리지 |
| `bd_connect_ac.tcl` | `05` 6.1 (296행) | BD 배선 근거 |
| `constraints/mission_soc.xdc` | `03` 12.2, `impl_methodology` 3.1 | 참고용 사본 |
| `mission_events_20260730_104707.csv` (318 rows) | `Audit_v3` 4장 | D0 UART/GUI E2E |
| `mission_events_20260731_104026.csv` | `05` 5-1장 | PL=5에서 WARNING 기록 증거 |
| `mission_events_20260731_141013.csv` | `05` 2장, `06` 0-4 | 다중 Fault 229 ms 실측 |
| `mission_events_20260731_094029/100054.csv` | `05` 5-1장 | 폴링 시절 WARNING 0건 (개선 전후 비교) |
| `mission_log_*.csv` | `04` 7장 | 주기 상태 기록 |
| 앱 화면 캡처 3종 (NORMAL/DEGRADED/SAFE_MODE) | `04` 7장 | GUI 슬라이드 |
| Vivado Block Design 캡처 | `04` 7장 | 아키텍처 슬라이드 |

> **개선 전후 비교 로그(`094029` vs `104026`)는 발표 가치가 매우 높다.**
> "폴링 → ISR Snapshot Ring" 변경으로 `STATE_CHANGE,WARNING` 이 0건 → 기록됨으로 바뀐
> 실측 증거다. 있으면 반드시 슬라이드에 넣을 것.

---

## 9. ⚠ Python 테스트 수

`README.md` 93행: **"Python 테스트: 202 passed"**

저장소 실측 (`def test_` 개수, parametrize 확장 전):

| 파일 | 함수 수 |
|---|---:|
| `test_command_builder.py` | 25 |
| `test_protocol.py` | 33 |
| `test_mock_device.py` | 28 |
| `test_theme_and_layout.py` | 23 |
| `test_irq.py` | 21 |
| `test_state_mapper.py` | 18 |
| `test_irq_panel.py` | 12 |
| **합계** | **160** |

`@pytest.mark.parametrize` 가 15곳 있어 실행 시 개수가 늘어난다. 202는 그럴듯하지만
**현재 환경에 pytest가 설치되어 있지 않아 확인하지 못했다.**

```powershell
cd mission_soc_dashboard
py -3.11 -m venv .venv; .\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
pytest -q          # ← 이 숫자를 슬라이드에 쓸 것
```

---

## 10. 검증 문서 커버리지 — 불균형 주의

`verification/` 에는 **3건만** 있다: `tb_fault_manager_core`, `tb_fault_manager_axi`, `tb_eval_tick_generator`
(모두 팀원 B 담당분 + 공동 RTL)

`tb_heartbeat_monitor_*` / `tb_safety_controller_*` / `tb_mission_soc_top` 의 최종 검증 문서는 없다.
`04` 2장은 세 IP 담당자 모두에게 Testbench + 파형 + Integration Note 제출을 요구한다.
`docs/` 에도 `fault_manager_integration.md` 만 있고 A/C의 integration note는 없다.

> **"3개 IP를 동일 수준으로 문서화했다"고 말하지 말 것.** TB 자체는 8종 다 있지만
> 최종 검증 문서와 Integration Note는 B 담당분만 있다. → C-22
