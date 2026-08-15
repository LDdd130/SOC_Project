# 07. 빈 슬라이드 채우기 — 넣을 내용 그대로

기준 파일: `Mission_SoC_최종.pdf` (24페이지)
회색 블록은 **슬라이드에 그대로 옮겨 쓸 문구**다.

---

## 남은 작업

| p | 제목 | 처리 |
|---:|---|---|
| **18** | GUI 화면 설명 | 채움 — 캡처 3장 + 설명 |
| **19** | 시연영상 | 채움 — 6컷 타임라인 (영상은 내일) |
| **20** | 검증환경 | 채움 — **제목을 `검증 범위`로 변경** |
| **21** | 트러블슈팅 | 채움 — 3소재 |
| **22** | 자원 사용량 | 채움 — **제목을 `합성 · Timing · 자원 사용량`으로** (목차와 일치) |
| **23** | 감사합니다 | 마무리 문구 + QR |
| **24** | (구)시스템 구조 | **삭제** — p10이 완전히 대체함. `Fault Monitor IP` / `Persust Count` 오타도 남아 있음 |

> ⚠ **p22가 Timing을 넣을 유일한 자리다.** 이전 버전에 있던 "구현 결과(WNS/LUT/결론)" 슬라이드가
> 최종본에서 빠졌다. 목차도 `합성·Timing·자원 사용량`이라고 되어 있으니 세 개를 한 장에 담는다.

---

# p18 · GUI 화면 설명

## 제목 / 부제

```
GUI 화면 설명
GUI 는 모니터가 아니라 양방향 검증 단말입니다
상태 관찰 · 설정 변경 · Fault 주입 · 복구 명령 · 로그 증빙을 하나의 UART 링크로 처리
```

## 이미지 — 캡처 3장 (내일 촬영)

**같은 화면을 상태만 바꿔서 3장.** 각 캡처에 **Event Log가 같이 보이게** 할 것.

| 캡처 | 만드는 법 | 화면에 보여야 할 것 |
|---|---|---|
| **① NORMAL** | 연결 직후 | `NORMAL` · Level 0 · `oe=0b111` · Actuator 1 · Device 0·1·2 전부 Alive |
| **② DEGRADED** | `INJECT,TIMEOUT,0,ON` 후 1초 | `DEGRADED` · Level 2 · **`oe=0b110`** · Device 0 Timeout ✓ Alive ✗ · Fault Count 증가 |
| **③ SAFE_MODE** | `Device 2 Critical Demo` 프리셋 | `SAFE_MODE` · Level 3 · **`oe=0b000`** · Actuator 0 · Control Valid 0 |

② 캡처에 Event Log의 `STATE_CHANGE,WARNING` → `STATE_CHANGE,DEGRADED` 두 줄이 같이 잡히면 최고.

**캡처 전 준비**: Baudrate **9600** 확인 → btnC 리셋 → `Boot complete` 확인

## 본문 — 3블록

```
① 양방향 검증 단말
   관찰   $MISSION 500 ms 주기 · $EVENT 전이 이벤트
   설정   SET 8종  TIMEOUT×3 / CRITICAL_MASK / PERSIST_LIMIT /
                   RECOVERY_COUNT / DEGRADE_MASK / IRQ_EN
   주입   INJECT   Error · Critical · Heartbeat 중단
   제어   CMD 4종  Manual Reset · Reset Fault · Clear IRQ · Clear Heartbeat
   증빙   CSV 2종  mission_log(주기 스냅샷) / mission_events(TX·ACK·ERR·EVENT)

② 값을 고치지 않는 앱
   파서가 예외를 던지지 않는다        모르는 값은 UNKNOWN 으로 표시하고 계속 동작
   성공을 가정하지 않는다             Manual Recovery 를 눌러도 $ACK 오기 전엔 상태 안 바꿈
   POLICY WARNING                     명세 위반값이 오면 보정하지 않고 경고만 기록
   색상만으로 구분하지 않는다         [ OK ] [ ! ] [ !! ] [ STOP ] 기호 병기

③ 두 개의 표시 경로
   큰 글씨 상태     ← $MISSION (500 ms 주기)     "지금 상태"
   최근 전이 트레일 ← $EVENT   (전이마다 즉시)   "무슨 일이 있었나"
   WARNING 은 5 ms 라 큰 글씨엔 안 잡히지만 Event Log 에는 남는다
```

## 하단 한 줄

```
안전 판단과 출력 차단은 전부 FPGA 내부 · 앱을 꺼도 SAFE_MODE 전환에 영향 없음
Mock Simulator 모드로 보드 없이 정책 검증 가능
```

## 구두로만 (슬라이드에 안 씀)

- "앱이 값을 보정하면 하드웨어 버그가 화면에서 사라진다. 그래서 절대 고치지 않고 경고만 남긴다."
- "보드 스위치가 없어도 GUI 명령이 Custom IP 입장에선 똑같은 신호를 만든다."

## ❌ 넣지 말 것

탭·위젯 이름 나열 / PySide6·Qt 구조 / 테마 이야기 / p16 UART 프로토콜 반복

---

# p19 · 시연 영상

## 제목 / 부제

```
시연 영상
6 클릭 · 32 초로 감지 → 등급화 → 차단 → 래치 → 조건부 복구를 모두 확인
```

## 본문 — 6컷 타임라인 (영상 옆에 배치)

```
①  D0 Timeout 체크              HEARTBEAT_TIMEOUT,0 → WARNING → DEGRADED
    INJECT,TIMEOUT,0,ON          oe = 0x06  ·  alive = 0x06        고장 장치만 차단

②  D0 Timeout 해제              FAULT_CHANGE,0,3,0 → STATE_CHANGE,NORMAL
    INJECT,TIMEOUT,0,OFF         oe = 0x07                          자동 복귀

③  Device 2 Critical Demo       중간 등급 없이 즉시 SAFE_MODE
    INJECT,CRITICAL,2,ON         FAULT_CHANGE,3,2,3 · oe = 0x00 · alive = 0x07

④  Manual Recovery              $ERR,MANUAL_RESET,FAULT_ACTIVE
    (Critical 켠 채로)           상태 SAFE_MODE 유지                거부 증명

⑤  Clear All Injection          Level 0 인데 STATE_CHANGE 가 안 나온다
    INJECT,CLEAR,ALL             oe = 0x00 유지                      래치 증명

⑥  Manual Recovery              $ACK,CMD,MANUAL_RESET → STATE_CHANGE,NORMAL
    (Level 0 확인 후)            oe = 0x07                          조건부 승인
```

## 하단 한 줄

```
④ 와 ⑥ 은 같은 버튼 · 같은 명령이다. 달라진 것은 fault_level 뿐 — 승인 조건이 하드웨어에 있다.
```

## 촬영 체크리스트 (내일)

```
□ Baudrate 9600 선택
□ btnC 리셋 → Event Log 에 Boot complete
□ SET,PERSIST_LIMIT,255  (WARNING 을 큰 글씨에도 보이게)
□ CSV 기록 시작
□ Fault Injection 탭 + Event Log 가 한 화면에 보이게 배치
□ 촬영 후 CSV 저장 → 영상과 같이 제출
```

## 나레이션 금지어

**"동시에"** — 다중 Fault 두 `INJECT`는 별개 UART 줄이라 순차 처리된다(실측 229 ms).
클럭 단위 동시성은 `tb_fault_manager_core.v`가 커버한다.

---

# p20 · 검증 범위  *(제목 변경)*

> `검증환경 ?` → **`검증 범위`** 또는 **`검증 전략`**
> 환경 나열(Vivado 2024.2 / Basys 3 / Python 3.11)은 표지·개요에 이미 있어 중복이다.
> p16(정책 매트릭스)·p17(IRQ/W1C)이 **깊이**를 보여줬으니, 이 장은 **넓이**를 맡는다.

## 제목 / 부제

```
검증 범위
계층마다 검증할 수 있는 것과 없는 것을 나누고, 못 하는 것은 아래 계층에 맡겼습니다
```

## 본문 블록 1 — 3계층 지도 (왼쪽)

```
① RTL Testbench  ·  sim/
   클럭 단위 · 전수 조합 · 경계조건
   TB 8 종 (core 4 · axi 3 · 통합 1)
        ↓ 여기서 못 하는 것 : 실제 AXI/INTC/펌웨어 통합, 사람 조작

② 보드 + UART  ·  28 단계 시나리오
   GET 3 · SET 8 · CMD 4 · INJECT 전부가 최소 1 회씩 실행
        ↓ 여기서 못 하는 것 : ms 이하 타이밍, GUI 로 도달 불가한 전이

③ Vivado 구현 리포트
   Timing · Utilization · Methodology DRC
```

## 본문 블록 2 — TB 8종 (오른쪽 표)

```
tb_heartbeat_monitor_core     Counter · Timeout · Alive · AUTO_RECOVER · CLEAR_ALL
tb_heartbeat_monitor_axi      AXI R/W · W1P · W1C · Reset 기본값
tb_fault_manager_core         정책 21 항목 + 전수 4,096 조합        4,146 / 0
tb_fault_manager_axi          AXI · IRQ Level · RESET_FAULT · Disable   46 / 0
  └ A11 IRQ Gating 6 / 0 · A12 Count Packing 4 / 0 · A13 Input Packing 4 / 0
tb_safety_controller_core     FSM 26 항목 · Recovery · SAFE Latch
tb_safety_controller_axi      AXI R/W · W1P · W1C
tb_eval_tick_generator        Reset 중 0 · DIVISOR 뒤 첫 pulse · 폭 1 clock   5 / 0
tb_mission_soc_top            mission_soc.bd net 배선을 그대로 옮긴 통합 TB
```

> ⚠ **p17에서 이미 `46/0`, `6/0`을 썼다. p20도 같은 숫자를 쓸 것.**
> 다른 문서에 `73`이라는 값이 있지만 근거 로그가 없다. **46 계열로 통일한다.**
> 나머지 TB 숫자(core 80 / hb_axi 60 / sc_core 44 / sc_axi 64 / top 61)는
> 로그를 확보한 것만 적고, 없으면 **칸을 비우고 항목만** 남긴다.

## 본문 블록 3 — 커버 못 하는 것 (하단, 이게 핵심)

```
보드 + UART 로 검증할 수 없는 것            대신 어디서

DEGRADED → WARNING 하강                     tb_safety_controller_core
  persist_cnt 가 255 에서 포화하고 PERSIST_LIMIT 최대도 255 라
  Fault 가 살아 있는 채로 Level 2 → 1 을 만들 UART 수단이 없다

클럭 단위 동시 다중 Fault                   tb_fault_manager_core
  UART 9600 bps · 관측 분해능이 ms 단위

20 ns 차단 지연 측정                        RTL 파형
```

## 하단 한 줄

```
AXI TB 3 종 공통 : AW/W 도착 순서 변경 · WSTRB 부분 쓰기 · BREADY/RREADY backpressure
                   백투백 연속 요청 · Protocol Monitor(Stall 중 VALID/Payload 변경 감시)
```

## 이미지 (선택)

| 우선 | 이미지 | 만드는 법 |
|:--:|---|---|
| 1 | **`tb_mission_soc_top` 통합 파형** | `NORMAL → WARNING → DEGRADED → SAFE_MODE → (manual_reset) → NORMAL` 전 구간. 신호 6~8개만: `fault_level` `system_state` `output_enable` `actuator_enable` `eval_tick` `manual_reset_pulse` |
| 2 | **xsim 콘솔 `ALL PASS`** | `checks = 4146  errors = 0  ALL PASS` 터미널 캡처 |
| 3 | pytest `N passed` | `cd mission_soc_dashboard && pytest -q` 마지막 줄 |

없어도 슬라이드는 성립한다. 3계층 지도만 있어도 충분하다.

---

# p21 · 트러블슈팅

## 제목 / 부제

```
Troubleshooting
세 번의 문제는 모두 "가정이 틀렸다" 에서 시작했습니다
```

## 3칸 레이아웃 — 각 칸 `증상 → 원인 → 조치 → 결과` 4줄 고정

### 칸 1

```
01  짧은 상태가 로그에서 사라졌다

증상   STATE_CHANGE,WARNING 이 한 줄도 없음
       FAULT_CHANGE 가 level 0 → 2 로 1 을 건너뜀

원인   메인 루프가 5 ms 폴링으로 직전 값과 비교하는 구조
       Level 1 유지 시간 = eval_tick 1 ms × PERSIST_LIMIT 5 = 5 ms
       + 9600 bps 송신 블로킹 → 실제 감지 지연 누적 50 ms 이상
       하드웨어는 0→1 전이에도 이미 IRQ 를 올리고 있었다

조치   ISR Snapshot Ring (깊이 16)
       ISR 진입 순간의 상태값을 저장 → 메인 루프가 순서대로 $EVENT 생성
       ISR 내부 순서 : 원인 읽기 → W1C → Snapshot → 플래그
       (W1C 를 먼저 해야 그 사이 도착한 새 변화를 안 잃는다)

결과   기본값 PERSIST_LIMIT = 5 에서도 WARNING 정상 기록
       Ring 이 넘치면 warn snapshot ring overflow 를 출력해 유실을 숨기지 않음
```

### 칸 2

```
02  경고 2,730 건의 원인은 XDC 한 줄

증상   TIMING-6 Critical Warning × 2
       check_timing multiple_clock register pin = 2,730

원인   BD 에 clk_wiz 가 있으면 Vivado 가 sys_clock 클럭 제약을 자동 생성
       Digilent 마스터 XDC 의 create_clock -add 가 같은 포트에 하나 더 추가
       → 클럭 2 개 → MMCM 출력도 _0 / _0_1 둘로 분리

조치   XDC 의 create_clock -add 줄 제거
       primary clock 은 clk_wiz 가 만드는 것 하나만 유지

결과   TIMING-6   2 → 0
       TIMING-56  2 → 0
       multiple_clock  2,730 → 0
```

### 칸 3

```
03  UART 송신이 수신과 Heartbeat 를 동시에 망가뜨렸다

증상   ⓐ GUI 버튼을 눌러도 명령이 씹힘
       ⓑ 아무 조작 없이 Timeout 이 뜸

원인   9600 bps 에서 $MISSION 한 줄 = 약 73 ms 블로킹
       ⓐ 그동안 UARTLite RX FIFO(16 byte)가 넘쳐 명령이 잘림
       ⓑ 그동안 Heartbeat 생성이 멈춰 진짜 Timeout 이 판정됨
          — 관측 행위가 관측 대상을 바꾼 경우

조치   ⓐ RX Ring 256 byte · tx_putc() 가 글자마다 RX 를 Ring 으로 퍼담음
       ⓑ 모든 송신 함수가 진입 전 HBGEN_Pump() 호출
          시간 판정 기준을 SW 시각이 아니라 HW LAST_COUNTn 으로 변경

결과   명령 유실 0 · Timeout 오탐 0
       CPU 가 멈춰 있어도 경과 시간이 정확
```

## 하단 한 줄

```
공통 교훈 : 하드웨어는 이미 알려주고 있었다 · 도구가 만든 것을 사람이 또 만들지 않는다
```

## 예비 (질문 나오면 답할 것, 슬라이드엔 안 씀)

| 소재 | 한 줄 |
|---|---|
| CTRL Shadow | 세 IP 모두 CTRL 이 RW(ENABLE)+W1P 혼합. W1P 쏠 때 ENABLE 을 같이 안 실으면 **IP 가 꺼진다** → 드라이버가 CTRL Shadow 보유 |
| 부팅 전역 분리 | IP 별 `Init()` 순차 호출 시, 디버거로 CPU 만 재시작하면 AXI IP 는 리셋 안 돼 과도기 출력 오염 → 세 IP 전부 Disable → 전체 설정 → 전체 Clear |
| AUTO_RECOVER | 0 이면 Timeout Latch 가 CLEAR_ALL 전까지 안 풀려 "Fault 제거 → NORMAL" 시연이 성립 안 함 → 부팅에서 1 로 |
| W1C 증명 불가 | ISR 이 µs 안에 W1C 해 Pending 이 항상 0 → `$ACK` 는 증거가 아님. `SET,IRQ_EN,0` → 주입 → `GET,IRQ` → `CLEAR_IRQ` → `GET,IRQ` 절차 고안 |
| GPIO 주입 잔류 | `INJECT` 로 켠 error/critical 은 CPU Reset 으로 안 지워짐 → 부팅 설정 전에 `INJ_ClearAll()` 필요 |

---

# p22 · 합성 · Timing · 자원 사용량  *(제목 변경)*

> `자원 사용량` → **`합성 · Timing · 자원 사용량`** (목차 문구와 일치)
> 이전 버전의 "구현 결과" 슬라이드가 최종본에서 빠져서, **Timing 을 넣을 유일한 자리다.**

## 제목 / 부제

```
합성 · Timing · 자원 사용량
100 MHz 목표를 만족했고, 저비용 FPGA 한 칩에 안전 경로와 제어 경로를 모두 넣었습니다
```

## 본문 블록 1 — 빌드 / Timing

```
BUILD        Vivado 2024.2 · Basys 3 xc7a35tcpg236-1 · Top mission_soc_wrapper
             Synthesis Complete · write_bitstream Complete · BIT + ELF 확보

TIMING       WNS  ____ ns          TNS  0.000 ns
             WHS  ____ ns          THS  0.000 ns
             Failed Routes  0      100 MHz (주기 10 ns) 목표 달성
```

## 본문 블록 2 — 자원 (막대 그래프 권장)

```
Slice LUT        ____ / 20,800    __._%    ████░░░░░░
Slice Register   ____ / 41,600    __._%    ██░░░░░░░░
Block RAM Tile     32 / 50        64.0%    ██████░░░░
DSP                 0 / 90         0.0%    ░░░░░░░░░░
```

**말할 포인트 3개**

```
DSP 0        안전 판단에 곱셈이 없다. 비교 · 카운터 · 비트마스크뿐 → 결정적 지연의 근거
BRAM 64%     대부분 MicroBlaze V Local Memory 128 KB. Custom IP 3 개가 쓰는 자원은 작다
여유 확보    저비용 Artix-7 35T 에 확장 여지를 남기고 들어갔다
```

## 본문 블록 3 — Methodology (하단)

```
RESOLVED     TIMING-6 Critical Warning  2 → 0
             multiple_clock            2,730 → 0
             원인 : BD 자동 클럭 제약 + XDC create_clock -add 중복 (Troubleshooting 02)

REMAINING    TIMING-18 × 19   비동기 외부 I/O · 참조 클럭이 없어 의도적 예외
                              reset(btnC) · usb_uart · led[15:0]
             LUTAR-1  × 2     MicroBlaze V 디버그 유닛 내부 셀 · 수정 대상 아님

             전 항목 Related violations: <none>  → 실제 타이밍 위반 경로 0 개
```

> **이 블록이 이 장의 진짜 값어치다.** "Critical Warning 이 2 건 있었고 원인을 찾아 0 으로 만들었다"가
> "아직 남아 있다"보다 훨씬 강하다. p21 트러블슈팅 02 와 세트로 말한다.

## 숫자 채우는 법

```tcl
open_project SOC_Pr/soc_project/soc_project.xpr
open_run impl_1
report_timing_summary        -file timing_routed.rpt
report_utilization           -file util_routed.rpt
report_utilization -hierarchical -file util_hier.rpt
report_power                 -file power_routed.rpt
```

| 슬라이드 항목 | 리포트 위치 |
|---|---|
| Slice LUT | `report_utilization` → **1. Slice Logic** → **`Slice LUTs`** 행 |
| Slice Register | 같은 표 → `Slice Registers` |
| Block RAM Tile | **3. Memory** → `Block RAM Tile` |
| DSP | **4. DSP** → `DSPs` |
| WNS / TNS / WHS / THS | `report_timing_summary` → **Design Timing Summary** |

⚠ **`Slice LUTs` 행을 쓸 것.** `LUT as Logic` 은 다른 값이다. 기존 문서들이
`2500` vs `3,039` 로 어긋난 원인일 가능성이 크다.

⚠ 저장소에 `soc_project.runs/` 가 없다(`.gitignore` 제외). 원본 Linux 워크스페이스
(`/home/user7/workspace_ondevice_3/SOC_Project/`)에 리포트가 남아 있을 것이다.
없으면 Implementation 을 다시 돌린다(10~20 분). 저장소의 `.dcp` 는 **synth** 체크포인트라
routed 수치가 안 나온다.

## 이미지 (선택)

| 우선 | 이미지 | 만드는 법 |
|:--:|---|---|
| 1 | **Hierarchical Utilization 표** | `report_utilization -hierarchical` — "Custom IP 3 개는 작고 BRAM 은 대부분 LMB"를 숫자로 증명 |
| 2 | **Device View 배치도** | Open Implemented Design → `Device` 탭. 하이라이트 필수 (아래) |
| 3 | Utilization Summary 막대 | Vivado 캡처보다 **슬라이드에서 직접 그리는 게 잘 읽힌다** |

```tcl
# Device View 하이라이트 — 이거 없으면 35T 에 작은 디자인이라 휑하다
highlight_objects -color red    [get_cells -hier -filter {NAME =~ *fault_manager_ip_0*}]
highlight_objects -color blue   [get_cells -hier -filter {NAME =~ *myip_heartbeat_monit_0*}]
highlight_objects -color green  [get_cells -hier -filter {NAME =~ *safety_controller_0*}]
highlight_objects -color yellow [get_cells -hier -filter {NAME =~ *microblaze_riscv_0*}]
```

→ "노란 덩어리가 MicroBlaze, 색점 3 개가 우리 안전 경로 IP" 그림이 나온다.

## ❌ 넣지 말 것

리포트 텍스트 전문 붙여넣기 / Schematic 뷰 / 합성(synth) 수치와 구현(routed) 수치 혼용

---

# p23 · 마무리

## 본문

```
감사합니다

CPU 독립 안전 경로와 관찰 · 설정 가능한 소프트웨어를 결합해
감지 → 판단 → 보호 → 통제된 복구를 하나의 SoC 로 구현했습니다

박기태   김민석   이재운          온디바이스 AI 반도체 설계 3 기
```

## QR

```
□ "QR 삽입" 오타 수정
□ QR 2 개 : GitHub 저장소 / 시연 영상 — 각각 라벨 달 것
```

---

# 내일 준비물 체크리스트

## 캡처 (보드 연결 후)

```
□ GUI NORMAL 화면        Event Log 같이 보이게
□ GUI DEGRADED 화면      oe=0b110 · Event Log 에 WARNING → DEGRADED
□ GUI SAFE_MODE 화면     oe=0b000 · Actuator 0
□ 시연 영상 6 컷          06_DEMO_VIDEO_SCENARIO.md 순서대로
□ CSV 2 개 저장           mission_log_*.csv / mission_events_*.csv
```

**공통 준비**: Baudrate **9600** → btnC 리셋 → `Boot complete` → `SET,PERSIST_LIMIT,255` → CSV 기록 시작

## 데이터 (Vivado / 시뮬레이터)

```
□ report_timing_summary   → p22 WNS · TNS · WHS · THS
□ report_utilization      → p22 LUT · Register · BRAM · DSP
◇ report_utilization -hierarchical → p22 이미지
◇ TB 로그 8 개             → p20 표의 빈 칸
◇ pytest -q               → p20 Python 테스트 수
◇ tb_mission_soc_top 파형 → p20 이미지
```

`□` 없으면 슬라이드를 못 씀 / `◇` 없어도 성립하지만 있으면 확 좋아짐

## 슬라이드 정리

```
□ p24 삭제 (구 시스템 구조 — p10 이 대체)
□ p20 제목 → 검증 범위
□ p22 제목 → 합성 · Timing · 자원 사용량
□ p18~p23 섹션 라벨 05 / TEAM WORK SPLIT → 04 / VALIDATION & RESULTS
□ 페이지 번호 통일 (현재 /18, /20 혼재 · 실제 23 장)
□ p1 Commnuication → Communication
□ p2 목차 프로잭트 → 프로젝트
□ p8 Falut → Fault
□ p23 QR 삽ㅇ입 → QR 삽입
```

---

# 참고 · 이미 채워진 슬라이드 중 손볼 것

| p | 내용 | 조치 |
|---:|---|---|
| p8 | 범례 `Level 0 · NORMAL` | ✅ 이전 버전의 `Level 3 · NORMAL` 오타가 고쳐졌다 |
| p14 | `D2→011` | ✅ 각주 있음. 기본 Mask 에서는 발생하지 않는다는 설명 유지 |
| p17 | "Raw 실행 로그는 저장소에 없음" | ✅ 정직해서 좋다. 로그를 확보하면 이 문구를 결과로 교체 |
| p13 | `G0 critical_fault[2:0]` | `G0` → **`G1`** 또는 `GPIO0 CH2` 로. CH1 과 라벨이 겹친다 |
| p24 | `Fault Monitor IP` · `Persust Count` | 슬라이드째 삭제하면 같이 해결 |
