# app.py 사용법 — 00~04 명세 시나리오 기준

`mission_soc_dashboard/app.py` 를 실행해서 팀 공통 명세(`00`~`04`)의 검증 시나리오를
그대로 재현·확인하는 방법을 정리한 문서다.

- 앱 기능 전체 설명 → [README.md](README.md)
- 메시지 규격 → [README_PROTOCOL.md](README_PROTOCOL.md)
- 이 문서 → **"어느 문서의 어느 시나리오를 앱에서 어떻게 눌러 보는가"**

이 문서의 Mock 결과값(상태 전이, `output_enable`, Fault Code)은 실제로
`MockDevice` 를 돌려 확인한 값이다.

---

## 0. 30초 요약

```bash
cd mission_soc_dashboard
python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt
python app.py
```

1. 상단 **Mock 주기(ms)** 를 `1000` 으로 → **Mock 모드** 클릭 (FPGA 없이 시연)
2. **설정 · 제어** 탭 → 권장 초기값 확인 → **설정 전체 전송**
3. **Fault Injection** 탭에서 체크박스로 고장 주입
4. 왼쪽 카드/Event Log/차트로 상태 전이 확인
5. **로그 · 정보** 탭에서 CSV 기록 → 발표 증빙

---

## 1. app.py 가 하는 일

`app.py` 는 GUI 를 만들지 않는다. 실행 진입점이며 순서만 책임진다.

| 순서 | 함수 | 하는 일 | 실패해도 되는가 |
|---:|---|---|---|
| 1 | `setup_logging()` (`app.py:37`) | 콘솔 + `~/.mission_soc_dashboard/app.log` 로깅 | 예. 파일 로그 실패해도 실행 계속 |
| 2 | `configure_high_dpi()` (`app.py:83`) | `QApplication` **생성 전에** High DPI 정책 지정 | 예. Qt 버전 차이 무시 |
| 3 | — | `QApplication` 생성, 앱 이름/버전/조직 설정 | 아니오 |
| 4 | `install_excepthook()` (`app.py:57`) | 처리되지 않은 예외를 로그 + 팝업으로. **앱을 죽이지 않는다** | 예 |
| 5 | — | `MainWindow()` 생성 후 `show()`, `app.exec()` | 아니오 |

실행 방법은 두 가지이며 동작은 같다.

```bash
python app.py                 # 진입점 스크립트
python -m mission_dashboard   # 패키지 실행 (__main__.py)
```

종료(창 닫기) 시 `MainWindow.closeEvent` 가 Worker 종료 → CSV 닫기 →
`~/.mission_soc_dashboard/settings.json` 저장을 순서대로 처리한다.
포트/Baudrate/창 크기/로그 폴더/설정 레지스터 값/Mock 주기가 다음 실행에 복원된다.

---

## 2. 화면 위치 지도

```text
┌ 상단 ─────────────────────────────────────────────────────────┐
│ COM Port · 새로고침 · Baudrate · 연결 · 연결 해제              │
│ Mock 주기(ms) · [Mock 모드]            ● 연결 상태             │
│ 수신 Bytes · 수신 Message · Parse Error · 마지막 수신          │
├ 왼쪽 ─────────────────────────┬ 오른쪽 ───────────────────────┤
│ System State 카드              │ [탭] 설정 · 제어              │
│  상태 / Level / Device / Code  │   TIMEOUT0~2, CRITICAL_MASK,  │
│  Timestamp / Actuator / Valid  │   PERSIST_LIMIT,              │
│                                │   RECOVERY_COUNT,             │
│ 장치 상태 (Device 0 · 1 · 2)   │   DEGRADE_MASK                │
│  Alive / Timeout / OE /        │   [설정 전체 전송]            │
│  Fault 대상 / Fault Count      │   Get Status · Get Config     │
│                                │   Manual Recovery · Clear IRQ │
│ [탭] Event Log │ 실시간 차트   │   Clear Heartbeat·Reset Fault │
│                                │ [탭] Fault Injection          │
│                                │ [탭] 로그 · 정보              │
└────────────────────────────────┴───────────────────────────────┘
```

---

## 3. 명세 문서 ↔ 앱 화면 대응

| 명세 | 항목 | 앱에서 보는 곳 |
|---|---|---|
| `00` 7.1 System State | NORMAL/WARNING/DEGRADED/SAFE_MODE | System State 카드 상단 |
| `00` 7.2 Fault Level | 0~3 | State 카드 `Level`, 차트 |
| `00` 7.3 Fault Code | `0x00`~`0x05` | State 카드 `Code` |
| `00` 7.4 Device ID | 0~2, 3=MULTIPLE_OR_NONE | State 카드 `Device` |
| `00` 9.1 `TIMEOUT0~2` | Clock Count | 설정 탭 (ms 환산 힌트 표시) |
| `00` 9.2 `CRITICAL_MASK`/`PERSIST_LIMIT` | Fault 판정 | 설정 탭 |
| `00` 9.3 `DEGRADE_MASK`/`RECOVERY_COUNT` | 출력/복구 | 설정 탭 |
| `00` 10 Fault 정책 | 우선순위 5단계 | Mock 이 그대로 재현 |
| `00` 11 Safety FSM | 복귀/Latch 정책 | Mock 이 그대로 재현 |
| `01` 3.3 Alive | Timeout 아닌 장치가 Alive | Device 카드 `Alive` |
| `02` 3 Fault Code 우선순위 | ERROR_CODE > TIMEOUT | State 카드 `Code` |
| `03` 5 출력 정책 | 상태별 `output_enable` | Device 카드 `OE`, State 카드 Actuator |
| `03` 11 UART 형식 | `$MISSION,...` | Event Log 의 `raw_line` |
| `04` 1 권장 초기값 | 아래 표 | 설정 탭 기본값 |

### 권장 초기값 (`04` 1장) — 앱 기본값과 동일

| 항목 | 값 | 앱 표시 |
|---|---|---|
| `TIMEOUT0` | 30,000,000 clk | ≈ 300.00 ms @100MHz |
| `TIMEOUT1` | 60,000,000 clk | ≈ 600.00 ms |
| `TIMEOUT2` | 15,000,000 clk | ≈ 150.00 ms |
| `CRITICAL_MASK` | `0x04` (Device 2) | SpinBox `0x04` |
| `PERSIST_LIMIT` | 5 | |
| `RECOVERY_COUNT` | 2 | `RECOVERY_COUNT < PERSIST_LIMIT` 위반 시 노란 경고 |
| `DEGRADE_MASK` | `0x01` | |

`TIMEOUTn=0`, `PERSIST_LIMIT=0`, `RECOVERY_COUNT=0` 은 FPGA 에서 **1 로 간주**된다
(`00` 12.1). 앱도 힌트에 `(0 → 1 로 간주)` 를 표시한다.

---

## 4. 시연 준비 (Mock 모드)

1. **Mock 주기(ms) = 1000** 으로 설정
   - 주기는 **연결 전에** 정해야 한다. 연결 중 변경은 반영되지 않는다.
   - 1 tick = 공통 `eval_tick` 1회로 본다. 주기 1000 ms 기준
     `PERSIST_LIMIT=5` → **5초 뒤 DEGRADED**, `RECOVERY_COUNT=2` → **2초 뒤 복귀**.
   - 기본값 200 ms 로 두면 전이가 1초 안에 끝나 눈으로 따라가기 어렵다.
2. **Mock 모드** 클릭 → 상태 표시가 `Mock 연결됨 (MOCK_CONNECTED)`
3. Event Log 에 부팅 문자열이 먼저 뜨는지 확인
   ```text
   Boot complete
   Interrupt controller initialized
   $MISSION,1000,NORMAL,0,3,0,0x07,0x00,0x07,1,1,1000,0,0,0
   ```
4. **설정 · 제어** 탭 → **설정 전체 전송** → `$ACK,SET,...` 7줄 확인
5. **로그 · 정보** 탭 → **기록 시작 / 중지** (또는 "연결 시 자동 기록" 체크)

> Mock 은 GUI/정책 시연용이다. 100 MHz 클럭 단위 타이밍은 재현하지 않는다.
> Clock 지연 측정은 RTL 파형에서만 한다.

---

## 5. 시나리오별 실습

표기: `Lv` = Fault Level, `Dev` = Fault Device, `OE` = output_enable.
아래 결과는 기본 설정(`CRITICAL_MASK=0x04`, `PERSIST_LIMIT=5`, `RECOVERY_COUNT=2`)
기준으로 Mock 을 실제 실행해 확인한 값이다.

### SC-1 · 정상 상태 — `00` T01 / `04` 3장 7단계

| 조작 | 기대 결과 |
|---|---|
| Mock 연결만 한다 | `NORMAL`, Lv 0, Dev 3, Code `0x00`, Alive `0x07`, OE `0b111`, Actuator 1 |

### SC-2 · Device 0 Timeout 일시 → 지속 — `00` T02·T03 / `04` 3장 8·9단계

| 순서 | 조작 | 기대 결과 |
|---:|---|---|
| 1 | Fault Injection → **Device 0 · Timeout** 체크 | 1 tick 후 `WARNING`, Lv 1, Dev 0, Code `0x01`(TIMEOUT), OE `0b111` |
| 2 | 그대로 5 tick 대기 | `DEGRADED`, Lv 2, **OE `0b110`** (Device 0 만 차단), Actuator 유지 1 |
| 3 | Device 카드 확인 | Device 0 : Alive ✗ / Timeout ✓ / OE ✗ / Fault Count 증가 |

- WARNING 구간에서는 출력이 끊기지 않는다(`03` 5장). 이 점을 시연에서 짚는다.
- Fault Count 는 `eval_tick` 에서만 증가한다(`00` 5.2).

### SC-3 · Device 1 단일 지속 Fault — `00` T13 / `04` 3장 10·15단계

| 순서 | 조작 | 기대 결과 |
|---:|---|---|
| 1 | **Device 1 · Error** 체크 | `WARNING`, Lv 1, Dev 1, Code `0x02`(ERROR_CODE) |
| 2 | 5 tick 유지 | `DEGRADED`, Lv 2, **OE `0b101`** (Device 1 만 차단) |

### SC-4 · 같은 장치 Timeout + Error — `04` 3장 20단계

| 조작 | 기대 결과 |
|---|---|
| **Device 0 · Timeout** + **Device 0 · Error** 동시 체크 | Code 가 `0x01` 이 아니라 **`0x02` FAULT_ERROR_CODE** (`00` 10장, `02` 3장 우선순위) |

### SC-5 · Device 2 Critical → SAFE_MODE Latch → Manual Recovery
`00` T05·T09·T10 / `04` 3장 16~18·21·22단계 / `04` 4장 8~11단계

| 순서 | 조작 | 기대 결과 |
|---:|---|---|
| 1 | 프리셋 **Device 2 Critical Demo** (또는 Device 2 · Critical 체크) | 다음 tick 즉시 `SAFE_MODE`, Lv 3, Dev 2, Code `0x03`, **OE `0b000`, Actuator 0, Control Valid 0** |
| 2 | **Clear All Injection** | Lv 0 / Code `0x00` 으로 내려가지만 **상태는 `SAFE_MODE` 유지** (Latch) |
| 3 | Lv 0 을 확인한 뒤 **Manual Recovery** → Yes | `$ACK,CMD,MANUAL_RESET` + `STATE_CHANGE,NORMAL` → `NORMAL`, OE `0b111` |

주의할 점:

- **Clear 직후 다음 `$MISSION` 이 오기 전에** Manual Recovery 를 누르면
  `$ERR,MANUAL_RESET,FAULT_ACTIVE` 가 돌아온다. Level 0 표시를 보고 누른다.
  (`00` 8.5: `fault_valid=1 && fault_level=0` 일 때만 승인)
- 앱은 복구 성공을 가정하지 않는다. 상태바에도 "$ACK 또는 새 $MISSION 으로만 확인"
  이라고 뜬다.
- `CRITICAL_MASK=0x04` 이므로 Device 2 의 **Timeout / Error / Critical 어느 쪽이든**
  지속 Count 없이 Lv 3 이다(`04` 3장 16·17·18단계). 세 가지를 각각 눌러 확인한다.

### SC-6 · 다중 장치 Fault — `00` T06 / `04` 3장 19단계

| 조작 | 기대 결과 |
|---|---|
| 프리셋 **Device 0 + Device 1 Multi Fault** | `SAFE_MODE`, Lv 3, **Dev 3(MULTIPLE_OR_NONE)**, Code `0x04` FAULT_MULTI_DEVICE, OE `0b000` |

Critical 조건이 없어도 2개 장치 이상이면 Lv 3 이다(`00` 10장 우선순위 2).

### SC-7 · DEGRADED → WARNING → NORMAL — `00` T07·T08 / `04` 3장 12~14단계 / `04` 4장 6·7단계

`04` 4장 주석대로, Level 2 원인을 지우고 **별도의 일시 Level 1 원인을 유지**해야
`DEGRADED → WARNING` 경로를 보여줄 수 있다.

| 순서 | 조작 | 기대 결과 |
|---:|---|---|
| 1 | **Device 0 · Timeout** 체크 후 5 tick | `DEGRADED`, Lv 2, OE `0b110` |
| 2 | Device 0 · Timeout **해제** 하고 곧바로 **Device 1 · Error** 체크 | Lv 1 / Dev 1 로 바뀌지만 상태는 아직 `DEGRADED` |
| 3 | 2 tick(= `RECOVERY_COUNT`) 대기 | **`WARNING`** 복귀. `NORMAL` 로 직행하지 않는다 |
| 4 | Device 1 · Error 를 계속 두면 | Fault Count 가 5에 닿아 다시 `DEGRADED` 로 내려간다. 3단계 확인 직후 해제할 것 |
| 5 | **Clear All Injection** 후 2 tick | Lv 0 유지 → `NORMAL` 복귀 |

`DEGRADED` 에서 Fault 를 한 번에 모두 지우면 `DEGRADED → NORMAL` 직접 복귀가 나온다
(`00` 11.1 마지막 항목, `04` 4장 허용). 시연에서는 두 경로를 모두 보여주면 좋다.

### SC-8 · 제어 명령 확인 — `00` 12.1 / `02` 6.1

| 버튼 | 보내는 명령 | Mock 응답 / 의미 |
|---|---|---|
| Get Status | `GET,STATUS` | `$ACK,GET,STATUS` + `$MISSION` 1줄 |
| Get Config | `GET,CONFIG` | `$ACK,SET,...` 7줄로 현재 설정 회신 |
| 설정 전체 전송 | `SET,...` × 7 | MicroBlaze 초기화 순서(`00` 12.2)와 같은 순서로 전송 |
| Manual Recovery | `CMD,MANUAL_RESET` | Lv 0 아닐 때 `$ERR,MANUAL_RESET,FAULT_ACTIVE` |
| Clear IRQ | `CMD,CLEAR_IRQ` | Pending 만 Clear. Fault/Timeout 상태는 그대로 |
| Clear Heartbeat | `CMD,CLEAR_HEARTBEAT` | Counter/Timeout Clear. IRQ Pending 은 별도 |
| Reset Fault | `CMD,RESET_FAULT` | **Fault 가 하나라도 있으면 `$ERR,RESET_FAULT,FAULT_ACTIVE`** (`02` 6.1) |

Reset Fault 확인 순서: Fault 주입 상태에서 눌러 거절되는 것 → Clear All Injection
후 다시 눌러 `$ACK` 나오는 것, 두 번 보여준다.

> Mock 에서 **Clear Heartbeat** 는 주입된 Timeout 을 지우지만 Injection 탭의
> 체크박스는 그대로 남는다. 같은 Timeout 을 다시 주입하려면 체크를 껐다 켠다.

---

## 6. 발표용 최소 시연 — `04` 4장 그대로 따라 하기

Mock 주기 1000 ms, 권장 초기값 상태에서 순서대로 클릭한다.

| `04` 4장 | 앱 조작 | 확인 포인트 |
|---:|---|---|
| 1. 전원 ON → NORMAL | Mock 모드 연결 | `NORMAL` / OE `0b111` / Actuator 1 |
| 2. Device 0 Heartbeat 중단 | Device 0 · Timeout 체크 | Alive 비트 0 으로 |
| 3. 일시 오류 → WARNING | 1 tick | Lv 1, 출력 유지 |
| 4. 지속 → DEGRADED | 5 tick 유지 | Lv 2 |
| 5. Device 0 출력만 차단 | Device 카드 확인 | OE `0b110` |
| 6. Level 1 유지 → WARNING | Timeout 해제 + Device 1 Error 체크, 2 tick | `WARNING` (NORMAL 아님) |
| 7. 전부 제거 → NORMAL | Clear All Injection, 2 tick | `NORMAL` |
| 8. Device 2 Critical | Device 2 Critical Demo | Lv 3 / Code `0x03` |
| 9. SAFE_MODE, Actuator 0 | 상태 카드 | OE `0b000`, Actuator 0, Valid 0 |
| 10. Critical 해제해도 SAFE 유지 | Clear All Injection | 상태 `SAFE_MODE` 유지, Lv 만 0 |
| 11. Manual Recovery → NORMAL | Lv 0 확인 후 Manual Recovery | `$ACK,CMD,MANUAL_RESET` |
| 12. UART 로그로 전이 순서 확인 | Event Log 필터 / CSV Export | `STATE_CHANGE` 순서가 2→3→4→…와 일치 |

---

## 7. 앱(Mock)으로는 확인할 수 없는 항목

아래는 RTL Testbench 또는 보드에서만 확인한다. 앱에서 억지로 만들지 않는다.

| 명세 항목 | 이유 | 확인처 |
|---|---|---|
| `00` T11·T12, `04` 3장 2~6단계 (W1P/W1C 비트 단위) | 앱은 AXI 를 직접 만지지 않는다 | 각 IP Testbench, Vitis |
| `00` T14, `04` 3장 11단계 (`fault_device=3` + DEGRADED → `DEGRADE_MASK`) | Mock 에서 Dev 3 은 항상 Lv 3(SAFE_MODE)이라 DEGRADED 와 함께 나오지 않는다 | `tb_safety_controller_core`, 실제 FPGA |
| `00` T15, `04` 3장 23단계 (각 IP `ENABLE=0` 안전 출력) | 앱에 Enable 제어 명령이 없다 | Vitis / Testbench |
| `00` T16, `04` 5.2 (IRQ 동시 발생·경로) | 앱은 IRQ 신호를 못 본다 | INTC/ISR 검증 |
| Critical 입력→출력 차단 Clock 수 | Mock 은 클럭 타이밍을 재현하지 않는다 | RTL 파형 측정 |

---

## 8. 실제 FPGA 로 같은 시나리오 돌리기

### 연결

1. 비트스트림 다운로드 → Vitis 애플리케이션 실행
2. 앱 상단 **새로고침** → 포트 선택 (Linux `/dev/ttyUSB1`, Windows `COM*`)
3. Baudrate 를 **AXI UARTLite 설정과 동일하게** (기본 115200, Vivado 기본이 9600 인 경우 주의)
4. **연결** → `$MISSION` 이 들어오면 정상
5. Linux 권한: `sudo usermod -a -G dialout $USER` 후 재로그인

### 고장 주입은 보드 스위치로 (`03` 12장)

`INJECT,*` 명령은 펌웨어가 지원할 때만 동작한다. 지원하지 않으면
`$ERR,UNKNOWN_COMMAND` 가 돌아오고 상태바에 "지원하지 않는 명령" 이 뜬다.
그 경우 아래 보드 입력으로 대체한다.

| 앱 조작 (Mock) | 보드 입력 |
|---|---|
| Device 0 · Timeout | `SW0` (Device 0 Heartbeat 중단) |
| Device 1 · Error | `SW1` |
| Device 2 · Critical | `SW2` |
| Multi Fault 프리셋 | `SW3` (Device 0+1 동시) |
| Manual Recovery | `BTN_U` |
| Clear IRQ | `BTN_D` |

앱은 이때도 **표시·명령·로그** 역할만 한다. 판단과 차단은 FPGA 내부
`heartbeat_monitor_ip → fault_manager_ip → safety_controller_ip` 경로가 담당한다.
앱을 꺼도 SAFE_MODE 전환에는 영향이 없다.

### 수신값이 명세와 다르면

앱은 값을 고치지 않고 Event Log 에 `POLICY WARNING` 만 남긴다
(예: `SAFE_MODE` 인데 `actuator_enable=1`). 이때는 앱이 아니라 FPGA 쪽을 확인한다.

---

## 9. 로그로 `04` 7장 산출물 만들기

| `04` 7장 항목 | 앱에서 만드는 방법 |
|---|---|
| Fault Injection 결과표 | Event Log 를 CSV Export → `FAULT_CHANGE` / `STATE_CHANGE` 행 정리 |
| 상태 전이 기록 | **로그 · 정보** 탭 → 기록 시작 → `~/mission_soc_logs/mission_log_*.csv` |
| 세션 스냅샷 | **현재 세션 Export** |
| `RECOVERY_COUNT < PERSIST_LIMIT` 증빙 | 설정 탭 캡처 + `GET,CONFIG` 응답 로그 |

CSV 열 구성:

```text
received_at, timestamp_ms, system_state, fault_level, fault_device, fault_code,
alive_mask, timeout_mask, output_enable_mask, actuator_enable,
control_valid, state_timer, fault_count0, fault_count1, fault_count2, raw_line
```

---

## 10. 자주 막히는 곳

| 증상 | 원인 / 조치 |
|---|---|
| Mock 주기를 바꿔도 안 변함 | 주기는 연결 시점에 고정된다. 연결 해제 → 주기 변경 → 다시 연결 |
| 전이가 너무 빨라 안 보임 | Mock 주기를 1000 ms 로, 필요하면 `PERSIST_LIMIT` 을 늘린다 |
| Manual Recovery 가 `$ERR,...FAULT_ACTIVE` | Fault 가 아직 Level 0 이 아니다. Clear 후 `$MISSION` 한 번 받고 누른다 |
| SAFE_MODE 가 자동으로 안 풀림 | 정상. Latch 정책(`00` 11장). Manual Recovery 필수 |
| `DEGRADE_MASK` 효과가 안 보임 | 단일 장치 DEGRADED 에서는 실제 `fault_device` 만 차단된다. Mask 는 `fault_device=3` 인 DEGRADED 전용 |
| 차트 탭이 비어 있음 | `pip install pyqtgraph` |
| 포트 목록이 비어 있음 | pyserial 미설치 또는 `dialout` 그룹 권한 |
| Parse Error 만 증가 | Baudrate 불일치 또는 필드 순서 불일치. Event Log 의 `raw_line` 원문 확인 |
| 앱이 꺼졌다 | `~/.mission_soc_dashboard/app.log` 확인. 미처리 예외는 로그와 팝업으로 남는다 |

---

## 11. 테스트

```bash
pytest -v
```

Serial 포트도 FPGA 도 필요 없다. `test_mock_device.py` 가 `00` 10·11장의 Fault 정책,
Safety FSM, SAFE_MODE Latch, Recovery 경로를 직접 검증한다.
