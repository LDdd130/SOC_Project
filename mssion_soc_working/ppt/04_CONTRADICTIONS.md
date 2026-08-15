# 04. 모순 감사 — 문서 ↔ 문서, 문서 ↔ 코드

저장소 전체(문서 12건 + BD + XDC + XCI + RTL + 펌웨어 + Python)를 대조해 찾은 **불일치 22건**이다.
각 항목에 **정본 판정**과 **조치**를 붙였다.

**우선순위 규칙**: 슬라이드에 숫자·이름이 그대로 나가는 것 = HIGH.

| 등급 | 건수 | 의미 |
|---|---:|---|
| 🔴 HIGH | 5 | 슬라이드에 그대로 나가면 발표 중 지적당함 |
| 🟡 MED | 9 | 시연 판정 기준이 어긋나거나 문서 신뢰도 하락 |
| ⚪ LOW | 8 | 표기·참조 정리 |

---

## 진행 상황 (2026-08-07 갱신)

**문서 수정으로 해결 가능한 것은 전부 반영 완료.** 남은 것은 도구 재실행이 필요한 3건뿐이다.

```text
■ 남음 (재실행 필요)
  □ C-01  Vivado impl_1 재리포트 → Timing/Utilization 한 세트로 통일
  □ C-02  TB 8종 재실행 → 로그 8개 확보 → check 수 확정
  □ C-16  pytest -q 실행 → Python 테스트 수 확정

■ 해결 완료 (문서 수정)
  ☑ C-03  WARNING 서술    → 00 10.1 / 02 1.1 / 03 11.8 / 04 3·4장
  ☑ C-04  xlconcat 순서   → 03 10장 (+ 04 5.2 에 실제 표 추가)
  ☑ C-05  IRQ 명령 3종    → 03 11.4 / 11.5 / 11.5-1 신설, 00 2장·12.4, 04 1.2
  ☑ C-06  GET,CONFIG 8줄  → 03 11.5 / 04 3.1 28번
  ☑ C-07  $ACK,INJECT     → README_PROTOCOL 1.3 / 03 11.7
  ☑ C-08  INJECT,CLEAR    → README_PROTOCOL 2.4 / 03 11.7
  ☑ C-09  줄 길이 방향 분리 → README_PROTOCOL / 03 11.0 / 04 1.2
  ☑ C-10  0x2C ID 승인     → 00 9.2 추가, fault_manager_integration 4장 종결
  ☑ C-11  impl_methodology → 6→7장 번호 수정, XDC 실제 상태 반영, 3.3 정정
  ☑ C-12  integration.md   → 1·7·8·10장 통합 후 상태로 갱신
  ☑ C-21  state_timer ms   → 03 11.1 / 04 1.2
  ☑ C-23  0x05 미사용 명시  → fault_manager_integration 10장
  ☑ 부가   constraints/mission_soc.xdc 참조 정리 → 03 12.2
```

아래 각 항목의 "조치"는 원래 계획이며, 완료분은 위 목록으로 상태를 확인한다.

---

# 🔴 HIGH

## C-01 · Timing / Utilization 수치가 3중으로 충돌한다

| 출처 | WNS | WHS | LUT | Register |
|---|---|---|---|---|
| `README.md:91` | `+0.963 ns` | `+0.029 ns` | — | — |
| `docs/mission_soc_impl_methodology.md` 1.1 / 1.2 | `0.963 ns` | `0.029 ns` | `2500` | — |
| `Mission_SoC_PPT_Audit_v3.md` 4장 | **`+0.198 ns`** | **`+0.033 ns`** | **`3,039` (14.61%)** | `2,646` (6.36%) |
| (Audit_v3가 "옛 슬라이드 값"이라 폐기한 값) | `+1.118 ns` | — | `3,099` | `2,778` |

BRAM `32`, DSP `0`, `multiple_clock 0` 은 세 문서가 일치한다.

**정본 판정**: **불가.** 저장소에 `SOC_Pr/soc_project/soc_project.runs/` 가 없어 리포트를 볼 수 없다.
슬라이드에 이미 3세대의 서로 다른 숫자가 돌아다닌 이력이 있다.

**조치**

```tcl
open_project SOC_Pr/soc_project/soc_project.xpr
open_run impl_1
report_timing_summary -file timing_summary.rpt
report_utilization    -file utilization.rpt
report_power          -file power.rpt
```

→ 나온 값 한 세트로 `README.md` · `docs/mission_soc_impl_methodology.md` ·
`Mission_SoC_PPT_Audit_v3.md` · 슬라이드를 **동시에** 갱신. 리포트 파일을 저장소에 커밋.

> **주의**: LUT `2500` vs `3,039` 는 22% 차이다. "Slice LUT"와 "LUT as Logic" 같은
> 서로 다른 행을 인용했을 가능성이 있다. 리포트에서 **어느 행인지까지** 확정할 것.

---

## C-02 · Testbench check 총합이 문서마다 다르다

| 출처 | `tb_fault_manager_axi` | 총합 |
|---|---:|---:|
| `docs/mission_soc_impl_methodology.md` 6장 (배치 실행 결과) | **73** | **4,533** |
| `verification/tb_fault_manager_axi/..._final_verification.md` | **60** (46 + 6 + 4 + 4) | — |
| `Mission_SoC_PPT_Audit_v3.md` 4장 | **60** | (4,146+60+5 만 인용) |
| `docs/fault_manager_integration.md` 8장 | **"재실행 필요"** | "2076 checks 는 무효" |

`README.md:92` 는 `4,533 checks, 0 fail` 을 인용한다.
산술 검산은 3-A 세트 내부에서만 맞는다: 80+60+4146+73+44+64+5+61 = 4,533.

**정본 판정**: **불가.** `tb_logs_batch/` 가 저장소에 없다.
`4,146`(FM core)과 `5`(eval_tick)는 두 출처가 일치하므로 신뢰도가 높다. 문제는 FM AXI다.

**조치**: TB 8종 재실행 → 로그 8개를 `tb_logs_batch/` 에 커밋 → 그 숫자만 슬라이드에.
`docs/fault_manager_integration.md` 8장의 "재실행 필요"도 결과로 교체.

---

## C-03 · "WARNING이 관측되는가"에 대해 문서가 정반대로 말한다

| 출처 | 주장 |
|---|---|
| `00` 10.1 (520~522행) | "기본값 `PERSIST_LIMIT=5`에서는 Level 1이 이미 Level 2로 바뀐 뒤에 읽히며 **`WARNING`이 UART/PC 어디에도 나타나지 않는다**" |
| `03` 11.8 (637~638행) | "**`$EVENT,STATE_CHANGE,WARNING` 이 아예 나오지 않는다.** 이는 정상 동작이다" |
| `04` 3장 (279~281행) | "보드+UART 경로에서는 기본 `PERSIST_LIMIT=5` 기준 Level 1이 5 ms밖에 유지되지 않아 **관측되지 않는다**" |
| `04` 4장 (317~319행) | "기본값 5는 `WARNING` 구간이 5 ms라 3번·6번 항목이 **화면에 나타나지 않는다**" |
| **`05` 5-1장 (223행)** | "**`PERSIST_LIMIT=5` 여도 WARNING이 기록된다** — 실측 `mission_events_20260731_104026.csv`" |
| **`05` 0-4장 (27~28행)** | "`WARNING`이 로그에 남는 것 자체는 이 값과 무관하다. 상태 전이는 하드웨어 IRQ로 잡히므로 **`PERSIST_LIMIT=5` 여도 `STATE_CHANGE,WARNING`은 찍힌다**" |
| **`main.c` 62~71행 / `mission_intr.h` 47~59행** | 2026-07-30 Snapshot Ring 도입 근거 주석. 이전 폴링 방식이 문제였다고 명시 |

**정본 판정**: **코드가 정본.** `05` 와 펌웨어 주석이 맞다.
2026-07-30 이전 펌웨어는 메인 루프 폴링(5 ms)이라 5 ms짜리 WARNING을 놓쳤다.
현재는 ISR이 IRQ 진입 순간 값을 Snapshot Ring(깊이 16)에 넣으므로 **유지 시간과 무관하게 보고된다.**

정확한 현재 동작:

| 경로 | PL=5(5 ms)에서 WARNING | 이유 |
|---|:--:|---|
| `$EVENT,STATE_CHANGE,WARNING` | ✅ 나온다 | ISR Snapshot |
| GUI 큰 글씨 (`$MISSION` 500 ms) | ❌ 안 나온다 | 주기 샘플 |
| GUI "최근 전이" 트레일 | ✅ 나온다 | `$EVENT` 구동 |

`06` 0-4장("0-4를 빼먹으면 WARNING이 화면에 안 뜬다")은 **큰 글씨 한정**이라 사실상 맞다.

**조치**: `00` 10.1, `03` 11.8, `04` 3·4장을 다음 문구로 통일.

> `PERSIST_LIMIT` 은 Level 1(WARNING) 유지 시간을 결정한다 (`PL × eval_tick 1 ms`).
> 기본값 5(=5 ms)에서도 **상태 전이 자체는 ISR Snapshot 경로로 `$EVENT,STATE_CHANGE,WARNING` 에 기록된다.**
> 다만 500 ms 주기의 `$MISSION` 에는 잡히지 않으므로 GUI 큰 글씨에는 뜨지 않는다.
> 시연에서 큰 글씨에도 보이게 하려면 `SET,PERSIST_LIMIT,255` (255 ms)로 올린다.

**발표 리스크**: 이대로 두면 슬라이드가 "WARNING은 관측 불가"라고 말하는데 시연 로그에는
`STATE_CHANGE,WARNING` 이 찍혀 있는 상황이 나온다.

---

## C-04 · xlconcat / IRQ 연결 순서가 문서와 실제가 다르다

| 출처 | In0 | In1 | In2 | In3 |
|---|---|---|---|---|
| `03` 10장 (361~366행, "권장") | heartbeat | fault_manager | safety_controller | UARTLite/Timer |
| **실제 `mission_soc.bd`** | **`axi_uartlite_0/interrupt`** | **`fault_manager_ip_0/irq`** | **`myip_heartbeat_monit_0/irq`** | **`safety_controller_0/irq`** |
| `mission_intr.h` 20~23행 | UART=0 | **FM=1** | **HB=2** | **SC=3** |
| `05` 6.1 (289~294행) | 실제와 일치 | | | |

**정본 판정**: **BD가 정본.** `mission_intr.h` 와 `05` 가 이미 맞춰져 있다.
`04` 8장은 "IRQ 연결 순서"를 변경 금지 항목으로 지정했으므로 **BD를 바꾸면 안 되고 문서를 고쳐야 한다.**

**조치**: `03` 10장의 표를 실제 값으로 교체 + "권장" → "확정(BD 실측)"으로 문구 변경.
슬라이드의 AXI/Interrupt 다이어그램도 실제 순서로.

---

## C-05 · 프로토콜 정본 문서(`03` 11장)에 명령 3개가 빠져 있다

`README_PROTOCOL.md:28` — "**이 문서와 `03_MEMBER_C` 11장이 다르면 03이 우선이다**"

그런데 `03` 11장에 **없고** 나머지 전부에 **있는** 것:

| 항목 | `03` 11장 | `README_PROTOCOL.md` | `uart_proto.c` | `command_builder.py` | `protocol.py` | `05` 시나리오 |
|---|:--:|:--:|:--:|:--:|:--:|:--:|
| `SET,IRQ_EN,<mask>` | ❌ | ✅ 2.2 | ✅ 413~430행 | ✅ `set_irq_en()` | — | ✅ 15-1, 15-7 |
| `GET,IRQ` | ❌ | ✅ 2.1 | ✅ 557~560행 | ✅ `get_irq()` | — | ✅ 15, 15-3, 15-5 |
| `$IRQ` 응답 | ❌ | ✅ 1.5 | ✅ `PROTO_SendIrq()` | — | ✅ `_parse_irq()` | ✅ |

**정본 판정**: **코드가 정본.** 세 구현체가 모두 동작하고 `05` 시나리오의 W1C 증명 절차
(15-1~15-7)가 이 명령들에 **전적으로 의존**한다. 문서만 뒤처졌다.

**심각성**: `03` 11장이 "프로토콜 확정본 / 우선 문서"로 선언되어 있어서, 규칙대로면
**구현된 기능 3개가 규격 위반**이 된다. 심사에서 지적당하기 쉬운 형태다.

**조치**: `03` 11장에 11.5-1(`GET,IRQ` / `$IRQ`), 11.4에 `SET,IRQ_EN` 추가.
`04` 1.2 Freeze 목록의 "접두어 4종"도 **5종(`$IRQ` 포함)** 으로 수정.

---

# 🟡 MEDIUM

## C-06 · `GET,CONFIG` 응답 줄 수 (7 vs 8)

- `03` 11.5 (562~570행) 예시: **7줄**
- `04` 3.1 28번: "설정 **7줄**이 6장 부팅값과 일치"
- **실제** `uart_proto.c` 546~556행: **8줄** (`$ACK,SET,IRQ_EN,7` 포함)
- `README_PROTOCOL.md:218`: "(`SET,IRQ_EN` 포함)" — 실제와 일치

**정본**: 코드(8줄). **조치**: `03` 예시와 `04` 28번을 8줄로 수정.
그대로 두면 시연 중 "7줄이어야 하는데 8줄"로 오판정한다.

---

## C-07 · `$ACK,INJECT,*` 에 ON/OFF 인자가 없다

- `README_PROTOCOL.md:132` 예시: `$ACK,INJECT,CRITICAL,2,ON`
- **실제** `uart_proto.c` 513 / 520 / 530행: `PROTO_Ack3("INJECT","CRITICAL",dev)` → **`$ACK,INJECT,CRITICAL,2`**
- `06` 1장 1단계: `$ACK,INJECT,TIMEOUT,0` — 실제와 일치 ✅

**정본**: 코드. **조치**: `README_PROTOCOL.md` 예시에서 `,ON` 제거.

---

## C-08 · `INJECT,CLEAR,ALL` 응답 형식이 문서에 없다

**실제**: `uart_proto.c` 497행 `PROTO_Ack2("INJECT","CLEAR")` → **`$ACK,INJECT,CLEAR`** (`ALL` 없음)

문서 어디에도 명시가 없어 시연 판정 기준이 모호하다.
**조치**: `03` 11.7 / `README_PROTOCOL.md` 2.4에 `$ACK,INJECT,CLEAR` 명시.

---

## C-09 · 최대 줄 길이 4096 vs 96

- `03` 11.0 / `README_PROTOCOL.md:20`: "최대 줄 길이 **4096 bytes**. 초과분은 PC가 폐기"
- **FPGA 수신**: `uart_proto.c:298` `RX_LINE_MAX = 96` → 초과 시 `$ERR,INVALID_VALUE,LINE_TOO_LONG`
- **PC 수신**: `constants.py:67` `MAX_LINE_BYTES = 4096` ✅ 문서와 일치

**정본**: 둘 다 맞지만 **방향이 다르다.**
**조치**: 표를 방향별로 분리 — "PC 수신 한계 4096 B / FPGA 수신 한계 96 B".
`$ERR,INVALID_VALUE,LINE_TOO_LONG` 도 문서에 없으니 추가.

---

## C-10 · `0x2C ID` 레지스터의 승인 상태가 문서마다 다르다

| 출처 | 상태 |
|---|---|
| `00` 9.2 레지스터 맵 | **없음** (0x00~0x24만) |
| `02` 6장 (272~281행) | "**2026-07-30 승인**. 확정 맵에 반영한다" |
| `docs/fault_manager_integration.md` 4장 | CHANGE REQUEST **`팀 승인: [ ] A  [ ] C`** — 미승인 |
| 같은 문서 10장 | 미확정 사항에 "0x2C ID CHANGE REQUEST 승인 여부(A·C)" 잔존 |
| **구현** | HW + `mission_ip_regs.h` `FM_ID` / `FM_ID_VALUE` 양쪽에 **이미 존재** |

**정본**: 구현되어 있고 `main.c:155` `FM_SelfCheck()` 가 부팅마다 쓴다 → 사실상 확정.
**조치**: `00` 9.2 표에 `0x2C ID` 추가 + `fault_manager_integration.md` CHANGE REQUEST를
승인 완료로 종결. `00` 14장이 "승인 없이 레지스터 Offset 변경 금지"를 규정하므로 정리 필요.

---

## C-11 · `docs/mission_soc_impl_methodology.md` 내부 모순 + 장 번호 중복

**(1) XDC 상태가 자기 문서 안에서 모순**

- 3.1 (115~148행): "`create_clock` 줄을 **제거했다**. 현재 활성 XDC에 `create_clock` 이 한 줄도 없다"
- **6장 "현재 XDC 상태"** (265~282행): 활성 제약 목록에
  `create_clock -add -name sys_clk_pin ... ;# TODO 3.1` 가 **여전히 적혀 있음**
- **실제** `Basys-3-Master.xdc:11`: `#create_clock -add ...` → **주석 처리됨** (3.1이 맞음)

**(2) `## 6` 장 번호가 두 번 쓰임** (235행 "시뮬레이션 검증 결과", 265행 "현재 XDC 상태")

**(3) 3.3 "적용 절차"** 가 "1. 3.1 주석 처리 + 3.2 세 줄 추가"로 시작하는데,
3.2는 바로 위에서 **"적용하지 않기로 확정"** 이라고 선언되어 있다.

**조치**: 6장(XDC)을 실제 상태로 갱신 후 번호를 7로 변경. 3.3의 3.2 언급 제거.

---

## C-12 · `docs/fault_manager_integration.md` 전체가 통합 이전 시점 상태

| 항목 | 문서 | 실제 |
|---|---|---|
| 8장 TB 상태 | "재실행 필요" ×3 | 결과 있음 (4,146 / 73 또는 60 / 5) |
| 10장 미확정 | "`error_flag`/`critical_fault` 를 보드 스위치 직결 vs AXI GPIO 경유 — 미확정" | `axi_gpio_0` CH1/CH2로 **확정**, `04` 1.1 Freeze |
| 10장 미확정 | "`eval_tick` 주기와 `PERSIST_LIMIT`/`RECOVERY_COUNT` 최종값 미확정" | 1 ms / 5 / 2 로 **확정** |
| 1장 파일 경로 | `sw/fault_manager_ip.h`, `.c` | 실제는 `SOC_Pr/ip_repo/fault_manager_ip_1_0/drivers/fault_manager_ip_v1_0/src/` |
| 7장 API | `FM_SelfCheck(FM_BASE)` / `FM_Init(FM_BASE, 0x4u, 5u)` | `mission_ip_regs.h`: **`FM_SelfCheck(void)`** / **`FM_Init(u32 mask, u32 limit)`** |
| 7장 매크로 | `XPAR_FAULT_MANAGER_IP_0_S00_AXI_BASEADDR` | 실제 `XPAR_FAULT_MANAGER_IP_0_BASEADDR` |
| 9장 시연표 6번 | "Device 0 Timeout을 추가로 발생 → `FAULT_MULTI_DEVICE`" | 맞지만 `05`/`06`은 D0 Timeout에 **0.3초 지연**이 있음을 명시 |

**조치**: 통합 후 상태로 갱신하거나, 문서 상단에 **"IP 개발 시점(통합 전) 문서"** 라고 명시.
발표에서 이 문서를 근거로 인용하지 말 것.

---

## C-13 · IP 이름이 명세와 실제가 다르다

| 명세 이름 | 실제 VLNV | BD 인스턴스 |
|---|---|---|
| `heartbeat_monitor_ip` | `user.org:user:**myip_heartbeat_monitor**:1.0` | `myip_heartbeat_monit_0` |
| `fault_manager_ip` | `user.org:user:fault_manager_ip:1.0` ✅ | `fault_manager_ip_0` |
| `safety_controller_ip` | `user.org:user:**safety_controller**:1.0` | `safety_controller_0` |

`00` 14장은 "사용자 승인 없이 IP 이름 변경"을 금지 행위로 지정했다.
`mission_ip_regs.h` 31~35행은 이 때문에 `XPAR_MYIP_HEARTBEAT_MONIT_0_BASEADDR` /
`XPAR_MYIP_HEARTBEAT_MONITOR_0_BASEADDR` 둘 다 받는 `#ifdef` 방어 코드를 갖고 있다.

**조치**: 슬라이드 다이어그램 라벨을 **BD 인스턴스명**으로 쓰거나 "명세명(인스턴스명)" 병기.
문서와 그림이 다른 이름을 쓰면 심사에서 "IP가 몇 개냐"는 질문이 나온다.

---

## C-14 · RTL core/axi 파일 분리가 IP마다 다르다

| 문서 요구 | 실제 |
|---|---|
| `00` 15장 파일명 권장: `heartbeat_monitor_core.v` + `_axi.v`, `safety_controller_core.v` + `_axi.v` | |
| `01` 1장 필수: `heartbeat_monitor_core.v`, `heartbeat_monitor_axi.v` | HB는 `src/heartbeat_monitor.v` **1개** + 마법사 S00_AXI |
| `03` 1장 필수: `safety_controller_core.v`, `safety_controller_axi.v` | SC는 `hdl/safety_controller.v` **1개** + 마법사 S00_AXI |
| `02` 1장 필수: `fault_manager_core.v`, `fault_manager_axi.v` | FM만 **분리됨** ✅ |

Testbench는 세 IP 모두 core/axi 두 계층으로 나뉘어 있다
(`sim/tb_heartbeat_monitor.v` 안에 `tb_heartbeat_monitor_core` + `tb_heartbeat_monitor_axi`).

**조치**: 슬라이드에서 "3개 IP 모두 core/AXI wrapper 분리"라고 말하지 말 것.
"IP core와 AXI wrapper를 **가능한 한** 분리" (`00` 5.5 원문)로 표현.

---

# ⚪ LOW

## C-15 · 문서가 인용하는데 저장소에 없는 파일 (13종)

`tb_logs_batch/`, `run_tb_batch.sh`, `soc_project.runs/impl_1/*.rpt`, `docs/report_cdc.rpt`,
`bd_connect_ac.tcl`, `constraints/mission_soc.xdc`, `mission_events_*.csv` 5종, `mission_log_*.csv`,
앱 화면 캡처, BD 캡처 — 전체 목록은 [`03_VERIFICATION_AND_RESULTS.md`](03_VERIFICATION_AND_RESULTS.md) 8장.

**조치**: 슬라이드에서 파일명을 인용할 것만 미리 확보. `.gitignore` 확인.

---

## C-16 · Python 테스트 수 202가 미검증

`README.md:93` "202 passed" / 저장소 실측 `def test_` **160개** + `parametrize` 15곳.
현재 환경에 pytest 미설치로 확인 불가. **조치**: `pytest -q` 실행 후 확정.

---

## C-17 · `Mission_SoC_PPT_Audit_v3.md` 자체가 구버전 기준

- 4장 Timing/Utilization이 `impl_methodology` 와 불일치 (C-01)
- 4장 "Heartbeat/Safety self-checking TB ... **추가 권장**" — 실제로는 `impl_methodology` 6장에 결과 존재
- 5장 Canva 초안 20장 구성은 유효

**조치**: Timing/검증 절만 갱신하거나 상단에 "2026-07-30 기준, 최신 수치는 `ppt/00_FACT_SHEET.md`" 명시.

---

## C-18 · Python 앱 기본 Baudrate가 115200

`constants.py:51` `DEFAULT_BAUDRATE = 115200` / 보드는 **9600 고정** (`04` 8장 변경 금지 항목).
문서에 경고는 있다 (`README.md:50`, `README_PROTOCOL.md:24`, `05` 0-1).

**조치**: 시연·영상 슬라이드에 "연결 전 9600 선택" 단계 명시. 틀리면 글자가 전부 깨진다.

---

## C-19 · `00` 2장 블록도가 error/critical을 외부 장치 입력처럼 그린다

```text
error_flag[2:0]    ────────────────→ fault_manager_ip
critical_fault[2:0] ───────────────→ fault_manager_ip
```

실제 경로는 `MicroBlaze → axi_gpio_0 CH1/CH2`. `00` 12.3에 범위 설명은 있으나
2장 다이어그램 자체는 수정되지 않았다.

**조치**: 아키텍처 슬라이드는 **GPIO 경로로 그릴 것**. "`axi_gpio_0`은 보드 스위치를 읽는 입력이
아니라 MicroBlaze가 스위치를 대신 흉내내는 출력" (`00` 680~682행)이라는 설명을 함께.

---

## C-20 · AXI Timer가 없다

`00` 4장 "권장 추가 IP: `AXI Timer`" / BD에 **없음**.
결과: `usleep()` 이 MicroBlaze V Cycle Counter로 구현, 메인 루프가 직접 ms 카운트,
`timestamp` 가 실제보다 **약 10% 느림** (`main.c` 36~42행, `05` 6.2).

**조치**: 슬라이드 BD 다이어그램에 AXI Timer를 그리지 말 것.
"timestamp는 표시용, 실제 경과 시간은 CSV `received_at`(PC 시각)" 로 설명.

---

## C-21 · `STATE_TIMER` 단위 표기가 애매하다

- 레지스터 `0x14`: **100 MHz clock count** (포화) — `03` 7장
- `$MISSION` 11번 필드: 펌웨어가 **ms로 환산해 송신** (`sc_regs.c:87` `CLK_TO_MS`)
- `03` 11.1 표: "`state_timer` 정수 — **선택**. `STATE_TIMER` (Offset `0x14`)" → clock count로 오해 가능
- `README_PROTOCOL.md`: "현재 상태 유지 Count" → 단위 미표기

**조치**: `03` 11.1에 "**ms 단위** (MicroBlaze가 clock count → ms 환산)" 명시.

---

## C-22 · 검증 문서 커버리지가 B 담당분에 편중

`verification/` 3건 = `tb_fault_manager_core`, `tb_fault_manager_axi`, `tb_eval_tick_generator`
`docs/` integration note 1건 = `fault_manager_integration.md`

`04` 2장은 세 IP 담당자 모두에게 Testbench 결과 + 파형 + Register Map + Integration Note를 요구한다.
A(heartbeat) / C(safety)의 최종 검증 문서와 Integration Note는 없다.

**조치**: 슬라이드에서 "3개 IP를 동일 수준으로 문서화"라고 말하지 말 것.
"TB는 8종 전부, 최종 검증 문서는 B 담당분 + 공통 RTL" 로 정확히.

---

## C-23 · `FAULT_RECOVERY_REQUIRED (0x05)` 는 사용처가 없다

`00` 7.3 / `02` / `README_PROTOCOL.md` 인코딩 표에는 있으나
`fault_manager_core.v` 62~66행 localparam에도 없고 정책 어디에서도 출력하지 않는다.
`docs/fault_manager_integration.md` 10장이 "현재 정책에서 사용처가 없다"고 이미 인정.

**조치**: 슬라이드 Fault Code 표에 넣되 **"(미사용)"** 표기.

---

## C-25 · `APP_USAGE.md` 8장이 통합 이전 상태 *(2026-08-07 추가 발견)*

| 위치 | 문서 | 실제 |
|---|---|---|
| 8장 연결 3번 | "Baudrate를 AXI UARTLite 설정과 동일하게 (**기본 115200**, Vivado 기본이 9600인 경우 주의)" | 보드는 **9600 확정** (`04` 8장 변경 금지 항목) |
| 8장 "고장 주입은 보드 스위치로" | `SW0`/`SW1`/`SW2`/`SW3`/`BTN_U`/`BTN_D` 대응표 | **물리 SW/BTN 미구현.** UART 가 유일한 주입 수단 |
| 8장 | "`INJECT,*` 명령은 펌웨어가 지원할 때만 동작. 지원하지 않으면 `$ERR,UNKNOWN_COMMAND`" | **지원한다.** `uart_proto.c` 에 구현 완료 |
| 4장 / 5장 SC-8 | `$ACK,SET,...` **7줄** | 실제 **8줄** (`SET,IRQ_EN` 포함) |

**조치**: 8장을 UART 경로 기준으로 재작성하거나 "보드 스위치" 절을 삭제.
7줄 → 8줄 수정. 발표에서 이 문서를 근거로 인용하지 말 것.

---

## C-24 · `constants.py` 가 존재하지 않는 문서를 참조

`constants.py:49` "09 요구사항", `:220` "19장 원칙" — 저장소에 09/19 문서 없음.
(개발 과정의 다른 문서 번호로 추정) **조치**: 주석 정리 또는 무시.

---

# 부록 — 일치가 확인된 항목 (안심하고 슬라이드에 써도 됨)

BD/코드 실측으로 **문서와 일치**를 확인한 것들이다.

| 항목 | 확인 방법 |
|---|---|
| Address Map 7종 | `mission_soc.bd` addressing ↔ `mission_ip_regs.h` 주석 |
| 세 IP 레지스터 Offset 전체 | `00` 9장 ↔ `01`/`02`/`03` ↔ `mission_ip_regs.h` |
| LED 매핑 16비트 전체 | `led_concat` IN0~IN7 폭 ↔ `03` 12.2 표 |
| Baudrate 9600 3곳 | `.xci C_BAUDRATE` ↔ 펌웨어 ↔ `SUPPORTED_BAUDRATES` |
| 인코딩 4종 (state/level/code/device) | RTL localparam ↔ `mission_ip_regs.h` ↔ `models.py` |
| Fault 정책 우선순위 P1~P5 | `fault_manager_core.v` 182~207행 ↔ `00` 10장 ↔ `02` 3장 |
| `alive` → FM 연결 금지 | BD net: `alive`는 `led_concat/In4` 로만 |
| `output_enable` → `device_enable` 연결 금지 | BD net: `led_concat/In1` 로만 |
| `eval_tick` 을 B·C가 공유 | BD net 하나가 두 IP로 |
| 외부 포트 4개 = XDC 배선 | `mission_soc.bd` ports ↔ `Basys-3-Master.xdc` |
| `C_ALL_OUTPUTS=1` (GPIO 출력 전용) | `.bd` parameters — 물리 SW 미구현 근거 |
| 부팅 13단계 | `04` 6장 ↔ `main.c boot_sequence()` |
| 명령 문자열 15종 | `command_builder.py` ↔ `uart_proto.c` 파서 |
| 값 범위 검증 (mask/persist/recovery) | `constants.py` ↔ `uart_proto.c` |
| `IRQ_EN` 비트 인코딩 | `uart_proto.c irq_en_mask()` ↔ `constants.py IRQ_EN_BIT_*` |
| `eval_tick` 1 ms @ DIVISOR=100,000 | `rtl/eval_tick_generator.v` ↔ `00` 5.2 |
| 설정 기본값 8종 | `mission_ip_regs.h CFG_*` ↔ `04` 1장 ↔ `constants.py DEFAULT_*` |
