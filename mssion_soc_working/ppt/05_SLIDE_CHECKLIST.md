# 05. 슬라이드별 체크리스트 + 예상 질문 대응

`Mission_SoC_PPT_Audit_v3.md` 5장의 **Canva 초안 20장** 구성을 기준으로 했다.
각 장에 **✅ 해도 되는 말 / ❌ 하면 안 되는 말 / 📎 근거**를 붙였다.

---

## 전체 공통 규칙

```text
✅ 슬라이드 1장 = 결론 1개, 본문 3~5줄
✅ 본문 글자 14pt 이상  (기존 7~12pt, 30~68개 텍스트 요소 → 발표 화면에서 판독 불가)
✅ 흰 배경 + Noto Sans KR + Blue/Teal/Red 상태 색상 유지, 표지만 Dark Navy
✅ 숫자는 ppt/00_FACT_SHEET.md 와 대조한 것만
✅ "MicroBlaze" 는 최소 1회 "MicroBlaze V (RISC-V)" 로 표기
❌ 미구현 항목(SW/BTN, FND, RGB, AXI Timer, event_logger)을 그림에 넣지 않는다
❌ Member A/B/C 를 그대로 두지 않는다 → 실제 이름으로 교체
```

---

## 01 Cover

| | |
|---|---|
| ✅ | `임무컴퓨터 상태 감시·고장 대응 SoC` / Basys 3 · `xc7a35tcpg236-1` / Vivado·Vitis **2024.2** / 3인 팀 |
| ❌ | 팀원 이름을 `Member A/B/C` 로 두지 않기 |
| 📎 | `00_FACT_SHEET.md` 2장 |

## 02 Compact Contents

| | |
|---|---|
| ✅ | 5개 섹션(개요 / 설계 / 구현·통합 / 검증 / 결과)만. 항목 10개 이내 |
| ❌ | 기존 52개 텍스트 요소 목차 재사용 |
| 📎 | `Mission_SoC_PPT_Audit_v3.md` 2·3장 |

## 03 Background

| | |
|---|---|
| ✅ | "고신뢰 임베디드의 상태 감시·고장 분류·안전 출력 차단 원리를 **교육용 프로토타입**으로 축소 구현" |
| ❌ | "실제 군용 임무컴퓨터를 만든다" — `00` 1장이 명시적으로 부정 |
| 📎 | `00` 1장 |

## 04 Goals

| | |
|---|---|
| ✅ | 4상태 자동 전환 / 중요도·지속시간 기반 등급화 / **안전 판단은 FPGA 내부**, PC는 감시·명령·로그만 |
| ✅ | "Critical 입력 → 출력 차단까지 **결정적 2 clock(20 ns)**" |
| ❌ | "즉시(0 ns) 차단" — `00` 10장이 "0 ns 조합 응답이 아니다"라고 정의 |
| 📎 | `00` 1장·10장, `README.md` 13~14행 |

## 05 Target Devices & Requirements

| | |
|---|---|
| ✅ | Device 0 일반센서 100 ms/300 ms·일반 / Device 1 통신 200 ms/600 ms·중간 / Device 2 모터·핵심 50 ms/150 ms·**Critical** |
| ✅ | clock count 병기: 30,000,000 / 60,000,000 / 15,000,000 @100 MHz |
| ❌ | "하위 장치를 실제로 연결" — MicroBlaze가 `axi_gpio_1` 로 Heartbeat를 **생성**한다 |
| 📎 | `00_FACT_SHEET.md` 12장 |

## 06 R&R & Schedule

| | |
|---|---|
| ✅ | A=heartbeat / B=fault_manager / C=safety_controller, **BD·AXI/IRQ·Vitis·보드검증은 3명 공동** |
| ✅ | "통합 전담 4번째 인원 없음" |
| ⚠ | 산출물 편중을 알고 있을 것 — 최종 검증 문서·Integration Note는 **B 담당분 + 공통 RTL만** 존재 (C-22) |
| ❌ | "3개 IP를 동일 수준으로 문서화" |
| 📎 | `00` 0장, `04` 0장, `03_VERIFICATION_AND_RESULTS.md` 10장 |

---

## 07 Architecture ★ 가장 많이 틀리는 장

| | |
|---|---|
| ✅ | 체인: `heartbeat_monitor → (timeout) → fault_manager → (level/device/code/valid) → safety_controller → LED` |
| ✅ | `error_flag` / `critical_fault` 는 **`MicroBlaze → axi_gpio_0` CH1/CH2** 에서 온다고 그릴 것 |
| ✅ | `heartbeat_async` 는 **`axi_gpio_1` CH1** 에서 온다 |
| ✅ | 공통 `eval_tick` 이 B·C 두 IP로 갈라진다 (Module Reference, Custom IP 아님) |
| ✅ | IP 간 상태 신호는 **MicroBlaze 중개 없이 직접 연결** — 이게 설계 핵심 논거 |
| ❌ | `alive → fault_manager` 선 (금지 연결. 실제 BD에도 없음) |
| ❌ | `output_enable → device_enable` 선 (금지 연결) |
| ❌ | 보드 SW/BTN 을 입력으로 그리기 (C-19) |
| ❌ | AXI Timer 그리기 (C-20) |
| 📎 | `01_HW_BLOCK_DESIGN_AND_IP.md` 3장 (BD net 실측) |

## 08 Heartbeat Monitor (A)

| | |
|---|---|
| ✅ | 2FF Synchronizer → rising edge 검출 → 장치별 Counter → `counter ≥ TIMEOUTn` 이면 Timeout Set |
| ✅ | `alive` / `timeout` 3비트, `device_enable=3'b111` 고정 (`output_enable`과 **독립**) |
| ✅ | 레지스터 10개 (`0x00`~`0x24`), `CLEAR_ALL` W1P, `IRQ_STATUS` W1C |
| ✅ | **`AUTO_RECOVER=1`** 로 운용 — 0이면 Timeout Latch가 안 풀려 "Fault 제거 → NORMAL" 시연이 불가 |
| ✅ | `LAST_COUNTn` 이 **하드웨어 시간 기준** — UART로 CPU가 수십 ms 멈춰도 정확 |
| ❌ | "`INJECT,TIMEOUT` 이 timeout을 직접 주입" — Heartbeat 생성을 **멈출 뿐**, 판정은 IP가 |
| 📎 | `01_HW` 5.1, `01_MEMBER_A` 3장 |

## 09 Fault Manager (B)

| | |
|---|---|
| ✅ | 우선순위 P1~P5 표 (`00_FACT_SHEET.md` 10장 그대로) |
| ✅ | **`CRITICAL_MASK` 는 `critical_fault` 전용 Mask가 아니다** — Device 2의 Timeout/Error만으로도 Level 3 |
| ✅ | 같은 장치 Timeout+Error → `FAULT_ERROR_CODE` (Timeout 아님) |
| ✅ | 지속 Count만 `eval_tick`(1 ms), **Critical/다중은 매 100 MHz 클럭 판정** |
| ✅ | `RESET_FAULT` 는 **활성 Fault가 있으면 무시** (Count만 지워 Level을 낮추는 동작 금지) |
| ✅ | 전수 검증 `512 × 4 × 2 = 4,096` 케이스 |
| ⚠ | `0x2C ID` 레지스터를 넣을 거면 "브링업 진단용 확장" 으로 설명 (C-10) |
| ❌ | Fault Level 4 이상 언급. `FAULT_RECOVERY_REQUIRED(0x05)` 는 **"(미사용)"** 표기 (C-23) |
| 📎 | `rtl/fault_manager_core.v`, `docs/fault_policy_table.md` |

## 10 Two Time Axes ★ 이 프로젝트의 설계 논거

| | |
|---|---|
| ✅ | **축 1 — 느린 축**: 일반 Fault 지속 Count / Recovery Count는 공통 `eval_tick`(1 ms)에서만 |
| ✅ | **축 2 — 빠른 축**: Critical 조건 / 다중 장치 Fault는 매 100 MHz 클럭에서 판정 |
| ✅ | 이유: 중요한 고장을 다음 Tick까지 미루지 않기 위해 |
| ✅ | 총 지연 = `입력 동기화 + FM 1 clock + SC 1 clock` = **20 ns** |
| ✅ | `eval_tick_generator` 는 AXI 없는 공통 RTL, **네 번째 Custom IP가 아니다** |
| 📎 | `00` 5.2·10장, `02_MEMBER_B` 4장 |

## 11 Safety Output Policy (C)

| | |
|---|---|
| ✅ | 상태별 출력표 (`00_FACT_SHEET.md` 11장) |
| ✅ | **DEGRADED는 실제 `fault_device` 만 차단** (`dev0→110`, `dev1→101`, `dev2→011`) |
| ✅ | `DEGRADE_MASK` 는 **`fault_device=3` 일 때만** 적용 |
| ✅ | `enable=0`(DISABLED) → `output_enable=000`, actuator=0 — 초기화 전 장치가 켜지지 않게 |
| ✅ | `fault_valid=0` → 상태 Hold + 안전 출력 강제 + Recovery Count Clear |
| ❌ | "`actuator_enable`/`control_valid` 를 AXI 레지스터로 읽는다" — **읽을 수 없다.** LED 핀 또는 유도값 |
| 📎 | `01_HW` 5.3, `sc_regs.c` 122~132행 |

## 12 State & Recovery

| | |
|---|---|
| ✅ | FSM 4상태 + 확정 Recovery 정책: `DEGRADED + L0 지속 → NORMAL`, `DEGRADED + L1 지속 → WARNING` |
| ✅ | **`fault_level=1` 에서 `NORMAL` 로 가는 경로는 없다** (통합 실패 판정 기준) |
| ✅ | SAFE_MODE 자동 복귀 금지 → `fault_valid=1 && fault_level=0 && MANUAL_RESET` |
| ✅ | `RECOVERY_COUNT < PERSIST_LIMIT` (2 < 5) |
| ✅ | Recovery Count는 `eval_tick`에서만 증가, `fault_valid`를 Tick으로 쓰지 않음 |
| ⚠ | WARNING 관측 서술은 **C-03 통일 문구**를 쓸 것 |
| ❌ | "보드에서 `DEGRADED → WARNING` 하강을 시연했다" — **GUI로 도달 불가**, TB가 커버 |
| 📎 | `00_FACT_SHEET.md` 11장, `03_VERIFY` 1장 |

---

## 13 Vivado Block Design

| | |
|---|---|
| ✅ | 실제 컴포넌트 16개 (`01_HW` 1장 표) |
| ✅ | Address Map 7종 (`01_HW` 4장) |
| ✅ | 외부 포트 **4개뿐**: `sys_clock`(W5) / `reset`(U18=btnC) / `usb_uart`(B18·A18) / `led[15:0]` |
| ✅ | IP Catalog 증빙: `AXI Interrupt Controller` + `AXI UARTLite` |
| ✅ | `AXI GPIO ×2 는 둘 다 출력 전용(C_ALL_OUTPUTS=1)` — 범위 결정 요인 |
| ✅ | BD 캡처 이미지 삽입 (`04` 7장 요구 산출물) |
| ❌ | 물리 SW/BTN, FND, RGB, AXI Timer, event_logger 그리기 |
| 📎 | `01_HW` 1·2·4장 |

## 14 MicroBlaze Firmware

| | |
|---|---|
| ✅ | **MicroBlaze V (RISC-V)** 명시 |
| ✅ | 부팅 13단계 (전역 단계 분리: 세 IP Disable → 설정 → Clear → INTC → FM/SC → HB → IRQ → Global) |
| ✅ | 왜 전역 분리인가: 디버거로 CPU만 재시작하면 AXI IP는 리셋 안 됨 → 과도기 출력 오염 |
| ✅ | `FM_SelfCheck()` 로 AXI 매핑 검증 후 진행 |
| ✅ | **CTRL Shadow** 트릭 — CTRL Write마다 ENABLE이 `wdata[0]`로 덮여서, W1P 쏠 때 ENABLE을 같이 실어야 IP가 안 꺼짐 |
| ✅ | AXI Timer 없음 → 메인 루프가 직접 ms 카운트 (`timestamp` 표시용) |
| 📎 | `02_FW_AND_PROTOCOL.md` 2장 |

## 15 AXI & Interrupt ★ 순서 주의

| | |
|---|---|
| ✅ | **실제 순서**: In0=`axi_uartlite`(미사용), In1=**FM**, In2=**HB**, In3=**SC** → XIntc ID 1/2/3 |
| ✅ | IRQ는 **Level + W1C** (`irq = IRQ_STATUS & IRQ_EN`) |
| ✅ | 전체 경로: `IRQ_STATUS Set → irq High → xlconcat → INTC → Handler → W1C → irq Low` |
| ✅ | ISR은 **읽기 → W1C → Snapshot → 플래그** 4단계. UART 출력·긴 Delay 금지 |
| ✅ | **W1C를 Snapshot보다 먼저** 하는 이유 설명 (뒤에 하면 새 변화의 Pending까지 삭제) |
| ✅ | `IRQ_STATUS` Set은 `IRQ_EN`과 무관 → `SET,IRQ_EN,0` 으로 래치를 눈으로 증명 |
| ❌ | `03` 10장의 권장 순서(In0=HB…) 그대로 쓰기 (C-04) |
| 📎 | `00_FACT_SHEET.md` 5장, `01_HW` 7장 |

## 16 UART & GUI

| | |
|---|---|
| ✅ | 9600 8N1, 4+1 접두어(`$MISSION` `$EVENT` `$ACK` `$ERR` **`$IRQ`**) |
| ✅ | `$MISSION` 필수 9 + 선택 5, 펌웨어는 14개 전부 송신, 500 ms 주기 |
| ✅ | **수신한 모든 명령에 `$ACK` 또는 `$ERR`** — 무응답 없음 |
| ✅ | **RX Ring 256 B** 로 TX 블로킹 중에도 명령 유실 없음 (기존 HW FIFO 16 B는 넘쳤음) |
| ✅ | 모든 송신 함수가 진입 전 `HBGEN_Pump()` → 73 ms 블로킹 중에도 Heartbeat 유지 |
| ✅ | Python 앱: 파서가 예외를 안 던짐, 모르는 값은 `UNKNOWN`, 색상만으로 상태 구분 안 함 |
| ✅ | Mock Simulator 모드 — 보드 없이 화면 검증 |
| ⚠ | 시연 전 **앱 Baudrate를 9600으로 변경** (기본값 115200) |
| ❌ | `$ACK,INJECT,CRITICAL,2,ON` 형식 인용 (실제는 `ON` 없음, C-07) |
| 📎 | `02_FW_AND_PROTOCOL.md` 4~7장 |

---

## 17 Verification Strategy & Pass Metrics ★ 숫자 확정 후 작성

| | |
|---|---|
| ✅ | 3계층 구조: RTL TB → 보드+UART → Vivado 리포트 |
| ✅ | **각 계층이 커버 못 하는 것을 명시** (이게 강점) |
| ✅ | TB 8종, 전수 검증 4,096 케이스 |
| ✅ | AXI TB 3종이 AW/W 순서 변경·WSTRB·backpressure·백투백·Protocol Monitor 포함 |
| ✅ | `tb_mission_soc_top` 은 BD net 배선을 그대로 옮긴 통합 TB |
| 🔴 | **총 checks 수는 재실행 전까지 쓰지 말 것** (4,533 vs 4,211 충돌, C-02) |
| 🔴 | **Python 테스트 수도 재실행 전까지 쓰지 말 것** (C-16) |
| 📎 | `03_VERIFICATION_AND_RESULTS.md` 2·3·4장 |

## 18 Device 0 / Device 1 Scenario

| | |
|---|---|
| ✅ | D0 Timeout: 체크 → **0.3초 뒤** `HEARTBEAT_TIMEOUT,0` → `WARNING` → `DEGRADED`, **`oe=0x06`**, `alive=0x06` |
| ✅ | 해제하면 **자동 복귀** → `FAULT_CHANGE,0,3,0` → `NORMAL`, `oe=0x07` |
| ✅ | D1 Error: **즉시** 성립 → `FAULT_CHANGE,1,1,2` → `2,1,2`, **`oe=0x05`** |
| ✅ | `oe` 읽는 법: bit0=Device0. `0x06=0b110` → Device 0만 차단 |
| ❌ | "Timeout과 Error가 동시에 성립" — Timeout은 0.3초 하드웨어 지연 |
| 📎 | `06` 컷①②, `05` 3~7단계 |

## 19 Device 2 / Multi Fault / Manual Reset

| | |
|---|---|
| ✅ | D2 Critical: 중간 등급 **없이** 곧바로 SAFE_MODE. `FAULT_CHANGE,3,2,3`, `oe=0x00`, **`alive=0x07`** |
| ✅ | `alive=0x07` 강조 — 하트비트는 멀쩡한데 Critical 하나로 전면 차단 |
| ✅ | **D2 Error(평범한 Error)도 즉시 Level 3** → `CRITICAL_MASK`가 Fault 종류를 안 가린다는 증명 |
| ✅ | Multi: `FAULT_CHANGE,3,3,4` (`fault_device=3` = 특정 불가) |
| ✅ | Latch: `Clear All` 후 `fault_level` 3→0 인데 `STATE_CHANGE` 가 **안 나온다** |
| ✅ | 같은 버튼·같은 명령인데 `fault_level` 만 달라 `$ERR` vs `$ACK` → **조건이 하드웨어에 박혀 있다** |
| ❌ | 다중 Fault를 "동시에"라고 표현 — UART 두 줄이라 순차 처리(실측 229 ms). 클럭 단위 동시성은 TB가 커버 |
| 📎 | `06` 컷③④⑤⑥, `05` 16~27단계 |

## 20 Routed Result, Remaining Sign-off, Conclusion

| | |
|---|---|
| 🔴 | **Timing / Utilization 숫자는 재리포트 후 기입** (C-01) |
| ✅ | Methodology: `TIMING-6` Critical Warning **0건**, 전 항목 `Related violations: <none>` |
| ✅ | `TIMING-6` 해결 스토리 (create_clock 중복 → multiple_clock 2,730 → 0) — **트러블슈팅 하이라이트** |
| ✅ | `TIMING-18` ×19 는 **의도적 예외** — 비동기 외부 I/O라 참조 클럭이 없음 |
| ✅ | `LUTAR-1` ×2 는 MicroBlaze V IP 내부 Serial Debug 셀, 사용자 로직 무관 |
| ✅ | 남은 항목: I/O delay 미지정 2 in / 17 out, `report_cdc` 첨부 |
| 📎 | `03_VERIFICATION_AND_RESULTS.md` 5·6장 |

---

# 예상 질문 대응 (Q&A)

| Q | A |
|---|---|
| **Custom IP가 몇 개인가? `eval_tick_generator`는?** | 3개. `eval_tick_generator`는 AXI 레지스터가 없는 공통 보조 RTL(Module Reference)이라 IP로 세지 않는다 (`00` 5.2) |
| **MicroBlaze인가 RISC-V인가?** | `xilinx.com:ip:microblaze_riscv:1.0` — **MicroBlaze V**, RISC-V ISA다. BSP도 `XTIMER_DEFAULT_TIMER_IS_MB_RISCV` 를 쓴다 |
| **왜 보드 스위치를 안 썼나?** | `axi_gpio_0/1` 이 둘 다 출력 전용이고 BD·XDC에 SW/BTN이 배선되어 있지 않다. 같은 기능을 UART 명령으로 **등가 구현**했고 Custom IP가 보는 신호는 동일하므로 RTL 검증 결과가 그대로 유효하다 |
| **`WARNING`이 왜 화면에 안 보이나?** | 유지 시간이 `PERSIST_LIMIT × 1 ms` = 5 ms인데 `$MISSION`은 500 ms 주기 샘플이라 큰 글씨에 안 잡힌다. **상태 전이 자체는 ISR Snapshot 경로로 `$EVENT,STATE_CHANGE,WARNING`에 기록된다.** 영상용으로는 255로 올려 255 ms로 늘린다 |
| **`PERSIST_LIMIT=255`면 고장 판정이 255 ms나 걸리는 것 아닌가?** | 255는 **촬영용 임시값**이고 운용 기본값은 5(5 ms)다. WARNING 단계를 화면에 보이게 하려는 것이며 `SET,PERSIST_LIMIT` 런타임 경로 증명도 겸한다 |
| **`LUTAR-1` Critical Warning은?** | MicroBlaze V 디버그 유닛 내부 구조에서 발생하는 경고이며 사용자 설계 로직과 무관하다. 디버그 전용 경로라 기능에 영향이 없다 |
| **I/O delay를 왜 안 걸었나?** | `reset`(푸시버튼), `usb_uart`(비동기 시리얼), `led`(사람 눈) 전부 참조 클럭이 없는 비동기 I/O다. 넣을 수 있는 의미 있는 숫자가 없어 억지로 0을 넣으면 경고만 사라지고 검증 강도는 그대로다. 판정 기준인 `TIMING-6` 0건은 충족했다 |
| **"즉시 차단"이 정확히 얼마인가?** | 0 ns 조합 응답이 아니다. `외부 입력 동기화 + FM 1 clock + SC 1 clock` = 100 MHz 기준 **2 clock (20 ns)** 안에 결정적으로 차단한다 |
| **`$ACK,CMD,CLEAR_IRQ` 가 W1C 증거 아닌가?** | 아니다. ISR이 µs 안에 이미 W1C 해서 Pending이 항상 0이다. `SET,IRQ_EN,0` → 고장 주입 → `GET,IRQ`로 래치 확인 → `CLEAR_IRQ` → `GET,IRQ`로 0 확인, 이 4단계가 유일한 증명이다 (`05` 15-1~15-5) |
| **`irq FM ... count=17` 다음이 19로 건너뛰는데 UART가 씹힌 건가?** | 아니다. ISR은 진입마다 `count`를 올리지만 메인 루프에 넘기는 `flag`는 0/1이다. 5 ms 안에 IRQ가 두 번이면 count는 2 오르고 줄은 한 번 나간다. **값 자체는 Snapshot Ring이 전부 받는다** |
| **`DEGRADED → WARNING` 하강은 시연 안 하나?** | GUI로는 도달 불가하다. `persist_cnt`가 255에서 포화되고 `PERSIST_LIMIT` 최대도 255라 Fault가 살아 있는 채로 Level 2→1을 만들 UART 수단이 없다. `sim/tb_safety_controller_core.v` 가 커버한다 |
| **`timestamp`가 실제 시간과 안 맞는데?** | BD에 AXI Timer가 없어 메인 루프가 직접 ms를 센다. UART 전송 시간만큼 느려 실측 약 10% 오차다. **표시용이라 판정에 쓰지 않는다.** 실제 경과 시간은 CSV `received_at`(PC 시각)을 본다 |
| **`Reset Fault` 를 눌러도 Count가 안 변하는데?** | 정상이다. Count는 Fault가 있는 동안 유지되고 없어지면 **다음 `eval_tick`(최대 1 ms)에** 0이 된다. `RESET_FAULT`가 실제로 하는 일은 `$ACK` vs `$ERR` 응답 차이로 확인한다 |
| **`Reset Fault` 와 `Manual Recovery` 차이는?** | 대상 IP가 다르다. `Reset Fault`는 **B(fault_manager)** 의 Count·과거 비교 정보를 지우고, `Manual Recovery`는 **C(safety_controller)** 의 SAFE_MODE 래치를 푼다. 둘 다 "고장이 다 없어졌을 때만" 통과한다 |
| **`actuator_enable` 은 어디서 읽나?** | AXI 레지스터에 없다 (`00` 9.3 확정 맵). 하드웨어 핀 → `led_concat` → LD5로 관측하고, `$MISSION` 필드는 펌웨어가 `system_state`에서 유도한 값이다 |
| **다중 Fault가 왜 두 단계로 보이나?** | 두 `INJECT`가 별개 UART 줄이라 9600 bps에서 순차 처리된다(실측 229 ms). 보드 내부 지연은 `PERSIST_LIMIT` tick 하나뿐이다. 클럭 단위 동시 성립은 UART로 관측 불가하고 `sim/tb_fault_manager_core.v` 가 커버한다 |
| **`CRITICAL_MASK`는 `critical_fault` 핀 전용인가?** | 아니다. `device_fault = timeout \| error_flag \| critical_fault` 전체에 걸린다. 그래서 Device 2는 **평범한 Error만으로도** 지속시간 없이 Level 3이 된다 |
| **PC 앱이 안전 판단을 하나?** | 하지 않는다. 안전 판단과 출력 차단은 전부 FPGA 내부다. 앱은 모니터링·명령 전송·CSV 로그만 한다. `MANUAL_RESET`도 앱이 승인 여부를 결정하지 않고 하드웨어 조건(`fault_valid=1 && fault_level=0`)이 결정한다 |

---

# 최종 리허설 체크리스트

```text
□ 04_CONTRADICTIONS.md 의 [즉시 조치] 6개 완료
□ Timing / Utilization 숫자가 모든 문서·슬라이드에서 동일
□ TB check 총합이 모든 문서·슬라이드에서 동일 + 로그 8개 첨부
□ Python 테스트 수 재확인
□ Member A/B/C → 실제 이름
□ 아키텍처 그림에 미구현 항목(SW/BTN/FND/RGB/AXI Timer) 없음
□ IRQ 다이어그램이 실제 순서(In0=UART, In1=FM, In2=HB, In3=SC)
□ 본문 글자 14pt 이상, 슬라이드당 메시지 5개 이하
□ BD 캡처 / GUI 캡처 3종(NORMAL·DEGRADED·SAFE_MODE) / 시연 영상 QR 삽입
□ 시연 전 앱 Baudrate 9600 확인 → 0-4 단계(PERSIST_LIMIT=255) 수행
□ 인용할 CSV 로그 파일 실물 확보
```
