# 06. PPT 실물 대조 결과 — `Mission_SoC_White_Keynote_Full_v1.pdf`

34페이지 전부를 저장소 실물(BD·RTL·펌웨어·리포트 문서)과 대조했다.
기준: [`00_FACT_SHEET.md`](00_FACT_SHEET.md), [`04_CONTRADICTIONS.md`](04_CONTRADICTIONS.md)

---

## 결론 3줄

1. **설계·정책 내용은 대부분 정확하다.** Fault 우선순위, FSM, 출력 정책, 두 시간 축,
   주소맵, IRQ 순서, 부팅 13단계 — 전부 코드와 일치한다. 잘 만들었다.
2. **🔴 p33(구현 결과)이 치명적이다.** 3세대 전 숫자를 쓰고 있고, **이미 해결한 문제를
   "미해결"로 발표**하고 있다. 이 한 장이 프로젝트를 실제보다 나쁘게 보이게 만든다.
3. **빈 슬라이드 9장 + 중복/잔재 슬라이드 3장**이 남아 있다. Custom IP 1·2·3은
   **이미 다른 곳(p21·22·23)에 완성본이 있다.**

---

# 🔴 반드시 고칠 것

## A-01 · p33 구현 결과 — 전부 옛날 값 + 해결된 문제를 미해결로 표기

### (1) 숫자가 3세대 전이다

| 항목 | **PPT p33** | `Audit_v3` | `impl_methodology` |
|---|---|---|---|
| WNS | **`+1.118 ns`** | `+0.198 ns` | `0.963 ns` |
| LUT | **`3,099 / 20,800 · 14.9%`** | `3,039 / 20,800 · 14.61%` | `2500` |
| Register | **`2,778 / 41,600 · 6.7%`** | `2,646 / 41,600 · 6.36%` | — |
| BRAM | `32 / 50 · 64.0%` ✅ | 동일 | 동일 |
| DSP | `0 / 90` ✅ | 동일 | 동일 |

`Audit_v3` 4장이 **"기존 21~22장의 `WNS +1.118`, `LUT 3,099`, `Register 2,778` 은
현재 routed report와 일치하지 않아 교체했다"** 고 명시했다.
**PPT는 그 교체 전 값을 그대로 쓰고 있다.**

### (2) 🔴 이미 해결한 문제를 "sign-off pending"으로 발표 중

```text
PPT p33 하단:
  Clean sign-off pending: TIMING-6 Critical Warning ×2 · multiple_clock 2,730
                          Routed PDRC Warning ×4
```

**전부 해결됐다.** `docs/mission_soc_impl_methodology.md` 기준:

| PPT 주장 | 실제 |
|---|---|
| `TIMING-6 Critical Warning ×2` | **0건.** 3.1에서 `create_clock -add` 중복 정의 제거로 해결 |
| `multiple_clock 2,730` | **0건.** 같은 조치로 2,730 → 0 |
| `TIMING-56` | **0건** (PPT엔 없지만 같이 해결됨) |
| `Routed PDRC Warning ×4` | 근거 없음. 현재 Methodology는 Warning 22건 = `TIMING-9`×1 + `TIMING-18`×19 + `LUTAR-1`×2, **전 항목 `Related violations: <none>`** |

**이건 발표 사고다.** "아직 정리 못 했다"고 말하는데 실제로는 다 정리했다.
심사에서 "이거 왜 안 고쳤냐" 질문을 자초하고, 답하려면 "사실 고쳤는데 슬라이드가 옛날 것"이
되어버린다.

### 조치

```tcl
open_project SOC_Pr/soc_project/soc_project.xpr
open_run impl_1
report_timing_summary -file timing_summary.rpt
report_utilization    -file utilization.rpt
report_methodology    -file methodology.rpt
```

→ 나온 값으로 p33을 다시 쓴다. 하단 문구는 이렇게 바꾼다:

```text
(수정안)
RESOLVED   TIMING-6 Critical Warning 2 → 0 · multiple_clock 2,730 → 0
           원인: BD clk_wiz 자동 클럭 제약 + XDC create_clock -add 중복
           조치: XDC 해당 줄 제거 후 재구현

REMAINING  TIMING-18 ×19 (비동기 외부 I/O · 의도적 예외)
           LUTAR-1 ×2 (MicroBlaze V 디버그 유닛 내부 · 수정 대상 아님)
           전 항목 Related violations: <none>
```

> **오히려 이게 발표 포인트다.** "Critical Warning 2건이 있었고, 원인을 찾아 0으로 만들었다"가
> "아직 2건 남았다"보다 훨씬 강하다. 트러블슈팅 슬라이드와 연결하면 스토리가 산다.

---

## A-02 · p20 시스템 구조 — IP 이름 오기

| PPT 표기 | 실제 |
|---|---|
| `Fault **Monitor** IP` | **`Fault Manager`** (`fault_manager_ip_0`) |
| `Safety **Monitor** IP` | **`Safety Controller`** (`safety_controller_0`) |
| `ecal_tick Generator` | `eval_tick_generator` |
| `Persust Count` | `Persist Count` |
| `AXI GPIO 0` / `AXI GPIO 1` 이 각각 2번 등장 | 중복 라벨 — 하나씩만 |

`Monitor`는 IP A(Heartbeat Monitor)의 이름이다. 셋 다 "Monitor"로 적으면
**세 IP의 역할 분리(감시 / 판정 / 제어)라는 프로젝트 핵심 논리가 무너진다.**
p22가 "Fault Manager는 Fault를 '감지'하지 않고 '등급화'합니다"라고 강조하는데
p20이 "Fault Monitor"라고 적으면 자기모순이다.

**추가**: `2FF Sync`가 BD 최상위 블록처럼 그려져 있다.
실제로는 `heartbeat_monitor` IP **내부**에 있다 (`(* ASYNC_REG = "TRUE" *)`).
BD에는 별도 동기화 블록이 없다. IP 안쪽으로 넣어 그릴 것.

### ✅ 맞는 것 (건드리지 말 것)

```text
UART IRQ Int0 · Fault IRQ Int1 · HeartbeatIRQ Int2 · Safety IRQ Int3
```

**실제 BD와 정확히 일치한다.** (`03_MEMBER_C` 10장의 옛 권장안이 아니라 실제 배선을 썼다)

---

## A-03 · p8 Fault 지속 판정 구조 — 범례 오타

```text
PPT 범례:  Level 1 · WARNING   Level 2 · DEGRADED   Level 3 · NORMAL
                                                            ^^^^^^ 틀림
```

**`Level 3 · SAFE_MODE`** 다. 슬라이드 본문 위쪽에는 `LEVEL 3 / SAFE_MODE`로 제대로
적혀 있어서 범례만 틀렸다. 이 슬라이드 전체가 "Level 3 = 즉시 차단"을 설명하는데
범례가 NORMAL이라고 하면 반대 의미가 된다.

---

## A-04 · p22 Fault Manager — `AXI GPIO / SW` 표기

```text
ERROR[2:0]     AXI GPIO / SW
CRITICAL[2:0]  AXI GPIO / SW
```

**물리 SW는 이번 빌드에 없다.** BD 최상위 외부 포트는 `sys_clock` / `reset`(btnC) /
`usb_uart` / `led[15:0]` 4개뿐이고, `axi_gpio_0`/`axi_gpio_1`은 둘 다
`C_ALL_OUTPUTS=1`(출력 전용)이라 보드 스위치를 읽을 수 없다.

→ **`AXI GPIO (MicroBlaze 구동)`** 으로 수정. "SW"를 남기려면 `SW(미구현·설계 의도)`로.

같은 문제가 p28에도 있다: `INJECT Error · Critical · HB stop` 은 맞지만,
p22의 SW 표기와 합쳐지면 "보드 스위치로도 되나요?" 질문이 나온다.

---

## A-05 · p28 UART & GUI — 접두어 4종 / 명령 누락

| PPT | 실제 |
|---|---|
| 접두어 4종 (`$MISSION` `$EVENT` `$ACK` `$ERR`) | **5종** — `$IRQ` 누락 |
| `GET STATUS · CONFIG` | **`GET,IRQ` 누락** |
| `SET Timeout · Mask · Count` | **`SET,IRQ_EN` 누락** |

`$IRQ` / `GET,IRQ` / `SET,IRQ_EN` 은 W1C 동작을 증명하는 **유일한 수단**이고
`05` 시나리오 15-1~15-7단계 전체가 여기 의존한다. GUI에도 `IRQ 상태` 박스로 구현되어 있다.
**GUI 슬라이드에서 가장 내세울 만한 기능인데 빠져 있다.**

---

# 🟡 정리하면 좋은 것

## A-06 · 페이지 번호 / 섹션 라벨이 전부 어긋남

실제 34페이지인데 모든 슬라이드가 `/ 18` 이다. 그리고:

| 페이지 | 표기된 번호 | 표기된 섹션 |
|---:|---|---|
| 1 | `01 / 18` | — |
| 5 | `06 / 18` | `01 / Project Overview` |
| 6 | `04 / 18` | `03 / MONITORED DEVICES` |
| 7 | `09 / 18` | `08 / FAULT PRIORITY` |
| 8 | `04 / 18` | `03 / MONITORED DEVICES` |
| 9~13 | `04 / 18` | `03 / MONITORED DEVICES` (전부 동일) |
| 14~19 | `06 / 18` | `05 / TEAM WORK SPLIT` (전부 동일) |
| 30 | `09 / 18` | `08 / FAULT PRIORITY` |
| 31 | `04 / 18` | `03 / MONITORED DEVICES` |

p10~p13은 Custom IP 이야기인데 섹션이 `MONITORED DEVICES`,
p14~p19는 GUI/검증/트러블슈팅인데 섹션이 `TEAM WORK SPLIT` 이다.
**마스터 슬라이드에서 일괄 수정**하는 게 빠르다. 최종 장수 확정 후 한 번에.

---

## A-07 · 중복 / 잔재 슬라이드 3장

| 페이지 | 문제 | 조치 |
|---:|---|---|
| **p31** | 제목은 "전체 시스템 아키텍처"인데 내용은 **p9(Recovery 구조)와 완전히 동일** | 삭제. 아키텍처는 p10(체인) + p20(BD)이 이미 담당 |
| **p34** | p4(프로젝트 목표)의 재작업본. 하단에 `→ ➜ ➤ ▶ ▷ ⇨ ↳` **화살표 후보 문자열이 그대로 노출** | p4와 둘 중 하나만 남기고 삭제 (p34가 레이아웃이 더 정리됨) |
| **p11·12·13** | "커스텀아이피 1/2/3" **빈 슬라이드**. 부제도 p6에서 잘못 복붙됨 | **A-08 참고 — 이미 완성본이 있다** |

---

## A-08 · ⭐ Custom IP 1·2·3 — **이미 다른 슬라이드에 완성되어 있다**

질문하신 것: "커스텀 ip 123 다른 슬라이드에 내용 있는지"
**있다. p21 / p22 / p23이 완성본이다.**

| 빈 슬롯 | 완성본 | 완성본 제목 |
|---|---|---|
| p11 커스텀아이피 1 | **p21** | `06 / CUSTOM IP ① HEARTBEAT MONITOR` |
| p12 커스텀아이피 2 | **p22** | `07 / CUSTOM IP ② FAULT MANAGER` |
| p13 커스텀아이피 3 | **p23** | `09 / CUSTOM IP ③ SAFETY CONTROLLER` |

p21·22·23의 품질은 좋다. 내용을 코드와 대조한 결과:

| 슬라이드 | 검증 결과 |
|---|---|
| p21 Heartbeat Monitor | 2FF Sync → Edge Detect → 32-bit Count → Compare → alive/timeout/timeout_event ✅<br>`AUTO_RECOVER=1` ✅ `CLEAR_ALL·W1P`(Pending 유지) ✅ `IRQ_STATUS·W1C`(Timeout 유지) ✅<br>"'누락 횟수'가 아니라 실제 경과 시간을 센다" ✅ — 정확하고 좋은 표현 |
| p22 Fault Manager | `device_fault = timeout ∨ error ∨ critical` ✅ Critical Mask / Persist Limit ✅<br>두 시간 축(EVERY CLK vs 1ms EVAL TICK) ✅ `PERSIST_LIMIT=0 → 1` ✅ 8-bit Saturation ✅<br>"'감지'하지 않고 '등급화'한다" ✅ — 핵심을 정확히 짚음<br>⚠ `AXI GPIO / SW` 만 수정 (A-04) |
| p23 Safety Controller | 4상태 출력표 ✅ `D0→110 D1→101 D2→011*` ✅<br>`* 기본 Critical Mask에서 D2 Fault는 Level 3이라 011은 발생하지 않음` ✅ — **이 각주가 특히 좋다**<br>`enable=0 또는 fault_valid=0 → OUTPUT 000` ✅ |

### 조치 (택 1)

**옵션 A (권장) — p11·12·13 삭제**
p21·22·23을 목차 순서에 맞는 위치로 옮긴다. 중복 슬롯이 사라지고 장수도 줄어든다.

**옵션 B — p11·12·13을 "심화" 슬라이드로 재활용**
p21·22·23이 *동작 원리*를 다루므로, p11·12·13은 *구현 근거*(레지스터 맵 + 파형 + TB 결과)를
담는다. 장당 내용은 [`07_MY_SLIDES_GUIDE.md`](07_MY_SLIDES_GUIDE.md) 4장에 정리했다.

> 발표 시간이 넉넉하지 않으면 **옵션 A**. 심사에서 "레지스터 맵 보여달라"가 나올 것 같으면
> 옵션 B로 3장을 채우되, 발표에서는 넘기고 질문 받으면 돌아오는 백업 슬라이드로 쓴다.

---

## A-09 · p29 Scenario A — WARNING 서술이 이제 부정확

```text
PPT: "기본 PERSIST_LIMIT = 5 에서는 WARNING 이 5 ms 라 9600 bps GUI 가 놓칠 수 있음"
```

절반만 맞다. 2026-07-30 펌웨어 변경(ISR Snapshot Ring) 이후:

| 경로 | PL=5(5 ms)에서 WARNING | 이유 |
|---|:--:|---|
| `$EVENT,STATE_CHANGE,WARNING` (Event Log) | **O 기록된다** | ISR이 IRQ 진입 순간 값을 Ring에 저장 |
| GUI 큰 글씨 (`$MISSION` 500 ms) | X | 주기 샘플 |
| GUI "최근 전이" 트레일 | **O** | `$EVENT` 구동 |

수정안:

```text
기본 PERSIST_LIMIT = 5 에서도 $EVENT 로는 WARNING 이 기록된다 (ISR Snapshot).
500 ms 주기의 $MISSION 으로 갱신되는 큰 글씨에만 안 잡히므로,
발표 시 PERSIST_LIMIT = 255 로 올려 화면에서도 보이게 한다.
```

`SET,PERSIST_LIMIT,255` 를 쓰는 이유가 "기록하려고"가 아니라 **"화면에 보이게 하려고"** 로
바뀌는 게 포인트다. 이게 트러블슈팅 슬라이드의 최고 소재이기도 하다
([`07_MY_SLIDES_GUIDE.md`](07_MY_SLIDES_GUIDE.md) 3장 T-01).

---

## A-10 · 오타

| 페이지 | 오타 | 수정 |
|---:|---|---|
| p1 | `Commnuication` | `Communication` |
| p2 목차 | `프로잭트 목표` | `프로젝트 목표` |
| p8 | `Falut` | `Fault` |
| p16 | `검증환경 ?` (물음표) | `검증 환경` |
| p19 | `QR 삽ㅇ입` | `QR 삽입` |
| p20 | `ecal_tick` / `Persust Count` | `eval_tick` / `Persist Count` |
| p22 | `PERSIST_LIMIT = 0 은 1 로 처리` ✅ 맞음 | — |

---

# ✅ 코드와 일치 확인 — 안심하고 발표해도 되는 것

| 페이지 | 내용 | 확인 |
|---:|---|---|
| p3 | "동기화 이후 FM 1clk + SC 1clk 의 결정적 경로" | ✅ |
| p4/p34 | `D0→110 D1→101 Level3→000` | ✅ |
| p6 | Heartbeat 100/200/50 ms · Timeout 300/600/150 ms | ✅ |
| p6 | D2는 "지속 판정 없이 Level 3" | ✅ `CRITICAL_MASK=0x4` |
| p7/p30 | Fault 우선순위 5단계 + `critical_mask=3'b100` | ✅ RTL 182~207행과 일치 |
| p30 | 코드 Tie-break (Timeout+Error → ERROR_CODE) | ✅ |
| p8 | `count ≥ 5` / eval_tick 1 ms / IMMEDIATE BYPASS | ✅ |
| p9 | `Count ≥ 2` Recovery / Level 바뀌면 Counter Clear | ✅ `RECOVERY_COUNT=2` |
| p10 | 체인 + `heartbeat_async[2:0]` / `timeout[2:0]` / `alive[2:0]` | ✅ |
| p20 | IRQ 순서 `Int0 UART · Int1 FM · Int2 HB · Int3 SC` | ✅ **BD 실측과 일치** |
| p21 | Heartbeat Monitor 전 항목 | ✅ |
| p22 | Fault Manager 정책 엔진 · 두 시간 축 | ✅ |
| p23 | Safety Controller 4상태 + D2 각주 | ✅ |
| p24 | Auto Recovery vs Manual Only · `L1에서 NORMAL 직접 복귀 금지` | ✅ |
| p25 | `20 ns CORE TARGET` / `INPUT SYNC EXCLUDED` / eval_tick 100,000 clk | ✅ |
| p26 | 주소맵 HB `0x44A1_0000` FM `0x44A0_0000` SC `0x44A2_0000` | ✅ |
| p26 | UARTLite 9600 8N1 | ✅ |
| p27 | 부팅 13단계 4묶음 · `FM ID = 0x464D4752` | ✅ |
| p32 | SAFE_MODE Latch · `fault_valid=1 && fault_level=0` 승인 조건 | ✅ |

**설계 내용은 정확하다.** 문제는 전부 (a) 결과 숫자 (b) 빈 슬라이드 (c) 라벨/오타다.

---

# 작업 순서 (우선순위)

```text
1순위 — 발표 사고 방지
  □ A-01  p33 재작성 (Vivado 재리포트 필요)  ★ 가장 중요
  □ A-02  p20 IP 이름 Manager / Controller 로
  □ A-03  p8 범례 Level 3 · SAFE_MODE

2순위 — 빈 슬라이드 채우기 (07_MY_SLIDES_GUIDE.md)
  □ p14  GUI 화면 설명
  □ p17  트러블슈팅
  □ p16  검증 환경
  □ p18  자원 사용량  (A-01과 같은 리포트 사용)
  □ p15  시연 영상 · p19 QR

3순위 — 정리
  □ A-08  p11·12·13 처리 (삭제 or 심화)
  □ A-07  p31 삭제 · p34/p4 통합
  □ A-05  p28 에 $IRQ / GET,IRQ / SET,IRQ_EN 추가
  □ A-04  p22 "SW" 표기 수정
  □ A-09  p29 WARNING 문구
  □ A-06  페이지 번호 · 섹션 라벨 일괄
  □ A-10  오타
```
