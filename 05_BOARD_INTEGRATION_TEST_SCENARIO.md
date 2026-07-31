# 보드 전체 기능 검증 시나리오 (로그 제출용)

이 문서 순서대로 버튼/체크박스를 누르면 앱이 지원하는 **모든 제어 명령**이
최소 1번씩 보드로 나간다. 끝나면 CSV 2개를 뽑아서 그대로 전달하면
로그만 보고 어떤 기능이 정상/비정상인지 확인 가능하다.

명령어 타이핑 필요 없음. 전부 마우스 클릭/체크박스다.

---

## 0. 시작 전 준비 (딱 한 번)

| # | 할 일 | 위치 |
|---|---|---|
| 0-1 | 보드 연결 | `연결` 탭 — COM Port 선택, **Baudrate 9600** 확인 → `연결` 버튼. 우측 상단 `연결됨 (CONNECTED)` 초록색 되면 완료 |
| 0-2 | 보드 리셋 | Basys3 **가운데 버튼(btnC)** 1회. Event Log 마지막 줄 `Boot complete` 확인 |
| 0-3 | **미션 로그 기록 시작** | `연결` 탭 하단 `CSV 로그` 박스 → **`기록 시작 / 중지`** 버튼 클릭. "기록 중: ..." 문구 뜨면 성공. **이 문서 끝날 때까지 절대 다시 누르지 말 것** (계속 켜둔다) |
| 0-4 | 설정 값 초기화 | `설정 · 제어` 탭 → `PERSIST_LIMIT` 칸을 **5 → 255** 로 변경 → **`설정 전체 전송 (Apply All Settings)`** 클릭 (나머지 값은 기본값 그대로 둔다) |

> **왜 PERSIST_LIMIT=255?** 두 가지 목적이다.
> 1. 이 단계 자체가 **`SET,*` 7개 명령 + `설정 전체 전송` 기능 테스트**다.
>    이걸 건너뛰면 CSV 에 `TX,COMMAND,SET,...` 줄이 하나도 안 남아서 설정 경로가
>    미검증으로 남는다. **가장 자주 빠뜨리는 단계니 꼭 확인할 것.**
> 2. 기본값 5는 WARNING → DEGRADED 승격이 5ms 만에 끝나 CSV 에서 두 전이가 같은
>    timestamp 로 붙어 나온다. 255로 올리면 255ms 벌어져 승격 과정이 눈에 보인다.
>
> **주의**: `WARNING` 이 로그에 남는 것 자체는 이 값과 무관하다. 상태 전이는
> 하드웨어 IRQ 로 잡히므로 PERSIST_LIMIT=5 여도 `STATE_CHANGE,WARNING` 은 찍힌다.
> 큰 글씨(①)에 WARNING 이 뜨지 않는 것도 이 값과 무관하다 (6.2 마지막 질문 참조).
>
> **확인**: 전송 후 `Get Config` 를 눌러 `$ACK,SET,PERSIST_LIMIT,255` 가 오는지
> 봐라. 여전히 `5` 면 버튼이 안 눌린 것이다. 다음으로 넘어가지 말 것.

---

## 1. 전체 단계표 — 이 순서대로만 누르면 끝

**모든 조작은 `Fault Injection` 탭 (체크박스/프리셋 버튼) 아니면 `설정 · 제어` 탭 (제어 명령 버튼) 에서 한다.**

| # | 탭 | 누르는 것 | 테스트하는 명령 | 눌러야 할 타이밍 |
|---|---|---|---|---|
| 1 | 설정·제어 | **`Get Status`** 버튼 | `GET,STATUS` | 아무 때나, NORMAL 상태에서 |
| 2 | 설정·제어 | **`Get Config`** 버튼 | `GET,CONFIG` | 1번 직후 |
| 3 | Fault Injection | **DEVICE 1** `Error` 체크 | `INJECT,ERROR,1,ON` | NORMAL 상태 확인 후 |
| 4 | — | (1초 대기) | — | WARNING → DEGRADED 전이 로그 쌓일 때까지 |
| 5 | Fault Injection | **DEVICE 1** `Error` 체크 해제 | `INJECT,ERROR,1,OFF` | 4번 끝나고 |
| 6 | Fault Injection | **DEVICE 0** `Timeout` 체크 | `INJECT,TIMEOUT,0,ON` | 5번으로 NORMAL 복귀 확인 후 |
| 7 | — | (1초 대기) | — | DEGRADED 전이까지 |
| 8 | 설정·제어 | **`Clear Heartbeat`** 버튼 (체크박스는 그대로 둠, 풀지 않음) | `CMD,CLEAR_HEARTBEAT` | 7번 직후. **약 0.3초 뒤 자동으로 다시 DEGRADED 된다 — 정상이다.** 화면에서 NORMAL 을 못 봐도 로그에 남으니 서두르지 말 것 |
| 9 | Fault Injection | **DEVICE 0** `Timeout` 체크 해제 | `INJECT,TIMEOUT,0,OFF` | 8번 `$ACK` 확인 후 (정리용). 급할 것 없다 |
| 10 | Fault Injection | **DEVICE 0** `Timeout` 다시 체크 | `INJECT,TIMEOUT,0,ON` | 9번 직후 |
| 10-1 | — | **`STATE_CHANGE,DEGRADED` 가 Event Log 에 뜰 때까지 대기 (약 0.5초)** | — | **여기서 안 기다리면 11번이 실패한다.** Timeout 은 0.3초 뒤에 성립하므로 그전에 누르면 Fault 가 없어 `$ACK` 가 온다 |
| 11 | 설정·제어 | **`Reset Fault`** 버튼 → 확인창 `Yes` | `CMD,RESET_FAULT` (거부 확인용) | 10-1 에서 DEGRADED 확인한 뒤 |
| 12 | Fault Injection | **DEVICE 0** `Timeout` 체크 해제 | `INJECT,TIMEOUT,0,OFF` | 11번 직후 |
| 13 | — | (0.5초 대기, NORMAL 복귀 확인) | — | |
| 14 | 설정·제어 | **`Reset Fault`** 버튼 → `Yes` | `CMD,RESET_FAULT` (승인 확인용) | 13번 직후 |
| 15 | 설정·제어 | **`IRQ 상태 읽기`** 버튼 | `GET,IRQ` | 14번 직후. NORMAL 상태에서 |
| 15-1 | 설정·제어 | `IRQ 상태` 박스 — 체크박스 3개 전부 해제 → **`IRQ_EN 적용`** 클릭 | `SET,IRQ_EN,0x00` | 15번 확인 후. 체크만 해서는 안 나간다 |
| 15-2 | Fault Injection | **DEVICE 1** `Error` 체크 | `INJECT,ERROR,1,ON` | 15-1 직후 |
| 15-3 | 설정·제어 | **`IRQ 상태 읽기`** | `GET,IRQ` | 15-2 직후 |
| 15-4 | 설정·제어 | **`Clear IRQ`** 버튼 | `CMD,CLEAR_IRQ` | 15-3 에서 Pending 확인한 뒤 |
| 15-5 | 설정·제어 | **`IRQ 상태 읽기`** | `GET,IRQ` | 15-4 직후 |
| 15-6 | Fault Injection | **DEVICE 1** `Error` 체크 해제 | `INJECT,ERROR,1,OFF` | 15-5 직후 |
| 15-7 | 설정·제어 | 체크박스 3개 다시 체크 → **`IRQ_EN 적용`** 클릭 | `SET,IRQ_EN,0x07` | **절대 빠뜨리지 말 것.** `보드 실제값` 이 전부 `ON` 인지 확인 |
| 16 | Fault Injection | **`D0 Timeout + D1 Error (단계적 상승)`** 프리셋 | `INJECT,TIMEOUT,0,ON` + `INJECT,ERROR,1,ON` | NORMAL 상태에서. **동시 Fault 가 아니다** — 아래 2장 참조 |
| 17 | — | (0.5초 대기) | — | DEGRADED → 약 0.3초 뒤 SAFE_MODE 까지 **두 번** 올라간다 |
| 18 | Fault Injection | **`Clear All Injection`** 버튼 | `INJECT,CLEAR,ALL` | 17번 직후 |
| 19 | 설정·제어 | **`Manual Recovery`** 버튼 → `Yes` | `CMD,MANUAL_RESET` (승인 확인용) | **`FAULT_CHANGE,0,3,0` 또는 `고장 등급 LEVEL_0` 을 먼저 확인하고** 누른다. 18번 직후 바로 누르면 아직 Level 이 안 내려가 거부될 수 있다 |
| 20 | Fault Injection | **`Device 2 Critical Demo`** 프리셋 버튼 | `INJECT,CRITICAL,2,ON` | 19번으로 NORMAL 복귀 확인 후 |
| 21 | 설정·제어 | **`Manual Recovery`** 버튼 → `Yes` (Critical 안 끈 채로!) | `CMD,MANUAL_RESET` (거부 확인용) | 20번 직후, 체크 끄지 말고 바로 |
| 22 | Fault Injection | **`Clear All Injection`** 버튼 | `INJECT,CLEAR,ALL` | 21번 직후 |
| 23 | 설정·제어 | **`Manual Recovery`** 버튼 → `Yes` | `CMD,MANUAL_RESET` (승인 확인용) | 19번과 같이 **`LEVEL_0` 확인 후** |
| 24 | Fault Injection | **`D0 + D1 Error (다중 장치 Multi)`** 프리셋 | `INJECT,ERROR,0,ON` + `INJECT,ERROR,1,ON` | NORMAL 복귀 후. **하드웨어 지연은 없지만 UART 가 두 줄을 순차 전송해 약 0.2초 간격으로 2단계 상승한다** — 아래 2장 참조 |
| 25 | Fault Injection | **`Clear All Injection`** → `LEVEL_0` 확인 → **`Manual Recovery`** → `Yes` | `INJECT,CLEAR,ALL` + `CMD,MANUAL_RESET` | 24번 확인 후 |
| 26 | Fault Injection | **`Device 2 Error (CRITICAL_MASK 확인)`** 프리셋 | `INJECT,ERROR,2,ON` | NORMAL 복귀 후 |
| 27 | Fault Injection | **`Clear All Injection`** → `LEVEL_0` 확인 → **`Manual Recovery`** → `Yes` | `INJECT,CLEAR,ALL` + `CMD,MANUAL_RESET` | 26번 확인 후 |
| 28 | Event Log 탭 | **`CSV 저장`** 버튼 | (명령 아님, 로그 파일로 뽑기) | 다 끝나고 마지막 |

**소요 시간 약 4~5분.**

> **타이밍 주의.** `Error` / `Critical` 주입은 즉시 성립하지만 `Timeout` 은 그
> 장치의 `TIMEOUT` 설정만큼 기다려야 성립한다 (D0 0.3초 / D1 0.6초 / D2 0.15초).
> 그래서 `Timeout` 을 켠 직후에 다른 명령을 누르면 아직 Fault 가 없어 기대와
> 다른 응답이 온다. 위 표에서 **"확인한 뒤"** 라고 적힌 단계는 반드시 Event Log
> 에서 해당 줄을 보고 넘어가야 한다.

---

## 2. 단계별로 뭘 확인하려는 건지 (참고용)

| 단계 | 테스트 목적 | CSV에 이렇게 찍히면 정상 |
|---|---|---|
| 1~2 | 조회 명령이 응답하는가 | `TX,COMMAND,GET,STATUS` 다음 줄에 `$ACK,GET,STATUS` + `$MISSION,...` |
| 3~5 | 즉시 반응형 단일 고장 (Error) → 지속되면 등급 상승 → 해제하면 복귀 | `FAULT_CHANGE,1,1,2` + `STATE_CHANGE,WARNING` → `FAULT_CHANGE,2,1,2` + `STATE_CHANGE,DEGRADED`(oe=0x05, Device1만 차단) → 해제 후 `FAULT_CHANGE,0,3,0` + `NORMAL`. **level 1 줄이 있어야 정상**이다 (없으면 WARNING 미검증) |
| 6~7 | 하트비트 실제 끊김 (Timeout) — Error와 달리 0.3초 지연 있음 | `HEARTBEAT_TIMEOUT,0` 이벤트 → `WARNING` → `DEGRADED` |
| 8 | **Clear Heartbeat 단독 효과** — 주입 켜진 채로도 강제로 풀리는지 | Device0 Timeout 체크박스는 켜진 채로 `STATE_CHANGE,NORMAL` 한 줄. **약 0.3초 뒤 `HEARTBEAT_TIMEOUT,0` → 다시 `DEGRADED` 가 정상이다** (원인이 그대로라 Counter 가 다시 찬다). 큰 글씨로는 못 볼 수 있고 로그의 `NORMAL` 한 줄이 증거다 |
| 9~11 | **Reset Fault 거부** — Fault 살아있을 때 누르면 무시돼야 함 | `TX,COMMAND,CMD,RESET_FAULT` 다음 줄에 **`$ERR,RESET_FAULT,FAULT_ACTIVE`** (ACK 아님). **`$ACK` 가 왔다면 10-1 을 안 기다린 것** — Timeout 성립 전이라 Fault 가 없었다는 뜻이다. 다시 하면 된다 |
| 12~14 | **Reset Fault 승인** — Fault 다 없어진 뒤엔 통과돼야 함 | 같은 명령인데 이번엔 **`$ACK,CMD,RESET_FAULT`** |
| 15 | 평상시 Pending 은 0 이다 (ISR 이 즉시 W1C) | `$IRQ,0x07,0x00,0x00,0x00` |
| 15-1 | IRQ_EN 을 끄면 irq 핀이 막혀 ISR 이 안 돈다 | `$ACK,SET,IRQ_EN,0` |
| 15-2 | 고장은 나는데 **`irq FM` / `irq SC` RAW 줄이 안 나온다** | `FAULT_CHANGE` / `STATE_CHANGE` 는 나오는데(폴링 백스톱) `irq ...` 줄은 없음 |
| 15-3 | **래치 증명** — Pending 이 스스로 안 내려간다 | `$IRQ,0x00,0x00,0x01,0x01` — B/C 가 `1` |
| 15-4~5 | **W1C 증명** — Clear IRQ 가 실제로 내린다 | `$ACK,CMD,CLEAR_IRQ` 후 `$IRQ,0x00,0x00,0x00,0x00` |
| 15-4~5 | Clear IRQ 는 상태를 안 건드린다 | 앞뒤 `$MISSION` 의 state/level/oe 가 완전히 동일 |
| 15-7 | 원복 | `$ACK,SET,IRQ_EN,7`, 이후 `irq ...` RAW 줄이 다시 나옴 |
| 16~17 | **단계적 상승** — Error 는 즉시, Timeout 은 0.3초 뒤 | 두 번에 걸쳐 올라간다.<br>① `FAULT_CHANGE,2,1,2` + `DEGRADED` (Error D1 만 성립)<br>② 약 0.3초 뒤 `HEARTBEAT_TIMEOUT,0` + `FAULT_CHANGE,3,3,4` + `SAFE_MODE`<br>실측 094029 로그에서 ①→② 간격 208ms |
| 18 | Fault 원인 제거해도 SAFE_MODE는 안 풀림 (Latch) | fault_level은 `0`으로 내려가는데 state는 계속 `SAFE_MODE` |
| 19 | Manual Recovery 승인 (fault_level=0 조건 만족) | `$ACK,CMD,MANUAL_RESET` + `STATE_CHANGE,NORMAL` |
| 20 | Critical 고장은 지속시간 안 따지고 즉시 최고 등급 | `eval_tick` 을 기다리지 않는다. FM 이 조합 판정 후 1클럭, SC 가 다시 1클럭 — **100MHz 기준 2클럭(20ns)** 만에 `SAFE_MODE`. fault_code `3`(`FAULT_CRITICAL`), device `2` |
| 21 | **Manual Recovery 거부** — fault_level이 0이 아니면 승인 안 됨 | **`$ERR,MANUAL_RESET,FAULT_ACTIVE`**, 상태는 `SAFE_MODE` 그대로 |
| 22~23 | 원인 제거 후 Manual Recovery 재시도 → 이번엔 승인 | `$ACK,CMD,MANUAL_RESET` + `NORMAL` 복귀 |
| 24 | **다중 장치 Fault** — `fault_num >= 2` 면 `FAULT_MULTI_DEVICE` | ① `FAULT_CHANGE,1,0,2`+`WARNING` → `FAULT_CHANGE,2,0,2`+`DEGRADED` (Error D0 만 성립)<br>② `FAULT_CHANGE,3,3,4` + `SAFE_MODE`, fault_device `3`(특정 불가)<br>**16번과 마찬가지로 2단계다.** 다만 지연 원인이 다르다 — 16번은 하드웨어 Timeout(0.3초), 24번은 **UART 전송 시간뿐**(실측 141013 로그 229ms). 두 `INJECT` 가 별개 줄이라 9600bps 링크에서 순차 처리되기 때문이다. 보드 내부 지연은 `PERSIST_LIMIT` tick 하나(실측 board ts 311860→311865, 5ms)뿐이다.<br>**클럭 단위 진짜 동시성은 UART 로 관측 불가** — `sim/tb_fault_manager_core.v` 가 커버한다 |
| 26 | **CRITICAL_MASK 는 Fault 종류를 안 가린다** | Device 2 에 평범한 `Error` 만 넣었는데 지속시간 없이 `FAULT_CHANGE,3,2,3` + `SAFE_MODE`. `CRITICAL_MASK` 가 `timeout \| error_flag \| critical_fault` 전체에 걸리기 때문 (20번의 `Critical` 주입과 fault_code 가 `3` 으로 같다) |

---

## 3. 화면 어디를 봐야 하나 (참고)

```
┌─ 시스템 상태 ────────────────────────────┐
│        [ STOP ] SAFE_MODE      ← ①      │
│  최근 전이: NORMAL → WARNING            │
│             → DEGRADED         ← ⑥      │
│  고장 등급: LEVEL_x            ← ②      │
│  Output Enable: 0b000          ← ③      │
└──────────────────────────────────────────┘
┌─ 장치 상태 ──────────────────────────────┐
│  DEVICE 0 / 1 / 2  각각 Alive, Timeout,  │
│  Output Enable, Fault 대상, Count ← ④    │
└──────────────────────────────────────────┘
┌─ Event Log ──────────────────────────────┐
│  TX / ACK / ERR / EVENT / MISSION 전부   │
│  여기 쌓임 ← ⑤ (CSV 저장이 이걸 내보냄)  │
└──────────────────────────────────────────┘
```

| 번호 | 이름 | 뜻 |
|---|---|---|
| ① | 큰 글씨 | 지금 시스템 상태. NORMAL / WARNING / DEGRADED / SAFE_MODE |
| ② | 고장 등급 | 0=정상 1=경고 2=성능저하 3=위험 |
| ③ | Output Enable | 장치 3개 출력 허용 여부. `0b111`=전부 정상 |
| ④ | 장치 패널 | Count 칸 = 그 장치가 몇 tick 연속 고장 중인지 (Fault 없어지면 자동으로 0) |
| ⑤ | Event Log | 명령/응답/상태변화 전부 기록. **CSV 저장 버튼으로 통째로 뽑는 게 이 파일** |
| ⑥ | 최근 전이 | 상태가 바뀔 때마다 즉시 갱신되는 이력. 최근 5개까지 남는다 |

**중요**: 큰 글씨(①)는 0.5초마다 갱신되어 짧은 상태를 **반드시** 놓친다.
`WARNING` 은 5ms 만 유지되므로 여기에 뜨는 일이 없다고 보면 된다. 짧은 상태는
**최근 전이(⑥)** 로 보고, 확실한 증거는 Event Log(⑤) → `CSV 저장` 파일이다.
자세한 이유는 6.2 마지막 질문 참조.

### 보드 LED (선택 참고용)

| LED | 뜻 |
|---|---|
| LD0, LD1 | 시스템 상태. 둘 다 꺼짐=NORMAL, LD0만=WARNING, LD1만=DEGRADED, 둘 다=SAFE_MODE |
| LD2, LD3, LD4 | Device 0/1/2 출력 허용 (꺼지면 그 장치 차단) |
| LD5 | 액추에이터. SAFE_MODE 에서만 꺼짐 |
| LD6 | 제어 유효. SAFE_MODE 에서만 꺼짐 |
| LD7, LD8, LD9 | Device 0/1/2 살아있음 |
| LD10, LD11, LD12 | Device 0/1/2 타임아웃 발생 |
| LD13, LD14 | 고장 등급 (2비트) |
| LD15 | Fault Manager 동작 중 (항상 켜져 있어야 정상) |

---

## 4. 마무리 — 나한테 보낼 파일

| 파일 | 어떻게 뽑나 | 위치 |
|---|---|---|
| `mission_log_*.csv` | 0-3에서 이미 켜놨으면 자동으로 계속 쌓인 상태. 24번 끝나고 `기록 시작 / 중지` 버튼 다시 눌러서 중지 | `~/mission_soc_logs/` |
| `mission_events_*.csv` | 24번 `CSV 저장` 버튼으로 방금 막 뽑은 파일 | `~/mission_soc_logs/` |

**두 파일 다 보내라.** `mission_log`는 0.5초 간격 스냅샷이라 순간적인 변화 확인용,
`mission_events`는 TX/ACK/ERR까지 다 들어있어서 명령이 실제로 씹혔는지/거부됐는지
판단하는 용도다.

---

## 5. 이상할 때

| 증상 | 어떻게 |
|---|---|
| 글자가 다 깨져 보임 | Baudrate 9600 확인 |
| 체크/버튼 눌렀는데 CSV에 `TX,COMMAND` 줄 자체가 안 남 | 연결 안 된 상태. 상태바 문구 확인, 재연결 |
| `TX,COMMAND` 는 찍혔는데 그 다음에 **`$ACK`도 `$ERR`도 없이 조용함** | **명령 씹힘.** 보드가 그 순간 다른 걸 처리 중이었을 가능성. 같은 버튼 한 번 더 눌러라. 이 현상이 자꾸 반복되면 몇 번째 단계에서 그랬는지 알려줘라 |
| 계속 SAFE_MODE 에서 안 나옴 | `Clear All Injection` → 고장 등급 LEVEL 0 확인 → `Manual Recovery` |
| `WARNING` 을 못 봤음 | 큰 글씨에는 원래 안 뜬다. 상태 카드의 **`최근 전이:`** 줄과 CSV의 `STATE_CHANGE,WARNING` 줄로 확인한다. 이유는 6장 마지막 질문 참조 |
| `Timeout` 체크했는데 반응 없음 | 정상. Device 0=0.3초, Device 1=0.6초, Device 2=0.15초 걸림 |
| PERSIST_LIMIT 에 256 이상 넣음 | 거부됨. 최대 255 (8비트 레지스터) |
| 뭔가 꼬였다 | btnC 리셋 → 0-3, 0-4 다시 |

---

## 5-1. 이 시나리오가 다루는 범위 (검토자용)

### 다루는 것

GUI 로 낼 수 있는 **모든 제어 명령** 과 대표 Fault 정책 경로다.
`GET,*` 3개, `SET,*` 8개, `CMD,*` 4개, `INJECT,*` 전부가 최소 1회씩 나간다.

### 다루지 않는 것 — 그리고 그 이유

| 항목 | 왜 여기서 못 하나 | 어디서 검증했나 |
|---|---|---|
| `DEGRADED` → `WARNING` 복구 | `persist_cnt` 가 255 에서 포화되고 `PERSIST_LIMIT` 최대도 255 라, Fault 가 살아 있는 채로 Level 2→1 을 만들 방법이 UART 명령에는 없다 | `sim/tb_safety_controller_core.v` (44개 검증 통과, `tb_logs_batch/`) |
| `WARNING` → `NORMAL` 복구 (`RECOVERY_COUNT` 연속 확인) | `RECOVERY_COUNT=2` 면 2ms 라 사람이 조작할 수 있는 시간 창이 아니다 | 같은 TB. 보드에서는 5번·12번의 `DEGRADED`→`NORMAL` 이 같은 복구 카운터를 지난다 |
| 100MHz 클럭 단위 타이밍 | UART 가 9600bps 라 관측 분해능이 ms 단위다 | 각 IP 의 TB |

**따라서 이 문서는 "보드 위에서 GUI 로 낼 수 있는 전 기능"의 검증이지,
RTL 전체 기능의 검증이 아니다.** RTL 커버리지는 `sim/` 의 테스트벤치가 담당한다.

### 펌웨어 사실 관계 (2026-07-31 기준)

검토 시 자주 어긋나는 부분이라 근거를 박아 둔다. **`$EVENT` 는 메인 루프
폴링이 아니라 ISR 스냅샷에서 만들어진다.**

| 사실 | 근거 |
|---|---|
| ISR 이 상태 스냅샷을 Ring 에 넣는다 | `mission_intr.c:45` `snap_push()`, ISR 3개가 `:83 / :93 / :103` 에서 호출 |
| Ring 깊이 16, 넘치면 경고 출력 | `mission_intr.h` `MISSION_SNAP_DEPTH`, `main.c` `warn snapshot ring overflow` |
| 메인 루프가 순서대로 꺼내 `$EVENT` 생성 | `main.c:229` `drain_snapshots()` → `report_state()` |
| 폴링(`report_changes()`)은 백스톱으로만 남았다 | `main.c` 메인 루프 5번 단계 |
| `PERSIST_LIMIT=5` 여도 WARNING 이 기록된다 | 실측: `mission_events_20260731_104026.csv` 에 `FAULT_CHANGE,1,1,2` + `STATE_CHANGE,WARNING` |

2026-07-30 이전 펌웨어는 실제로 폴링 방식이었고, 그래서 짧은 WARNING 이
통째로 사라졌다 (`094029` / `100054` 로그에 `WARNING` 0건). 그 문제를 고친 것이
위 Snapshot Ring 이다.

**단, "절대 안 잃는다"는 아니다.** 한 Tick 안에 전이가 16번을 넘으면 Ring 이
넘치고, 그때는 `warn snapshot ring overflow dropped=N` 이 출력된다. 이 줄이
로그에 없으면 유실이 없었다는 뜻이다.

> `PERSIST_LIMIT=255` 는 WARNING 을 **기록**하기 위한 값이 아니다 (5 여도 기록된다).
> `SET,*` 경로를 시험하고, WARNING→DEGRADED 승격이 같은 timestamp 로 뭉치지 않게
> 벌려 주기 위한 값이다. 0-4 단계 설명 참조.

---

## 6. 자주 나올 질문

**Q. Device 2 만 왜 특별한가?**
모터/핵심 제어 장치라서. `CRITICAL_MASK = 0x04` 가 "Device 2 고장은 지속시간
안 따지고 즉시 최고 등급"이라는 뜻이다.

**Q. WARNING 과 DEGRADED 차이는?**
WARNING = 고장 났지만 일시적일 수 있음 → 출력 안 막음.
DEGRADED = 고장이 `PERSIST_LIMIT` 만큼 지속됨 → 해당 장치만 출력 차단.

**Q. 왜 SAFE_MODE 는 자동 복구가 안 되나?**
치명적 고장이 잠깐 정상처럼 보인다고 자동으로 액추에이터를 다시 켜면 위험하다.
사람이 원인을 확인하고 `Manual Recovery` 로 명시적으로 복구해야 한다.

**Q. Clear Heartbeat 랑 그냥 Timeout 체크 해제랑 뭐가 다른가?**
체크 해제는 "원인(가짜 heartbeat 끊김)을 없앤다"고, Clear Heartbeat 는
"원인이 있든 없든 Counter/Timeout 래치를 강제로 지운다"다. 8번 단계에서
체크박스는 그대로 두고 버튼만 눌러서 이 차이를 직접 보는 거다.

**Q. Reset Fault 눌러도 Count 숫자가 안 바뀌는데?**
정상이다. Count 는 Fault 가 있는 동안만 유지되고, Fault 가 없어지면
**다음 `eval_tick`(최대 1ms)에** 0 이 된다 — `Reset Fault` 명령을 기다리지
않는다 (`fault_manager_core.v` 의 `persist_cnt` 갱신은 `eval_tick` 에서만 일어난다).
`Reset Fault` 가 실제로 하는 일은 로그 상 `$ACK` vs `$ERR` 응답 차이로만
확인된다 (11번 vs 14번 비교).

---

### 6.1 Clear IRQ — 이게 대체 뭘 하는 건가

**한 줄 요약: 세 IP 의 "인터럽트 깃발"만 강제로 내린다. 고장 상태는 하나도 안 건드린다.**

#### (1) 블록 디자인에서 IRQ 가 어떻게 흘러가나

우리 IP 세 개는 각자 `irq` 출력 핀이 하나씩 있다. 그게 BD 에서 이렇게 묶인다.

```
myip_heartbeat_monit_0 ──irq──┐
    (A, 하트비트 감시)         │
                              │      ┌──────────┐
fault_manager_ip_0 ─────irq──┼─────▶│ xlconcat │──▶ axi_intc ──▶ MicroBlaze
    (B, 고장 판정)             │      │  In0~In3 │      (인터럽트     Interrupt
                              │      └──────────┘       컨트롤러)      핀
safety_controller_0 ────irq──┘
    (C, 안전 제어)
```

`xlconcat` 은 선 4개를 4비트 묶음 하나로 만드는 부품이다. **어느 In 에 꽂히느냐가
곧 소프트웨어의 인터럽트 ID** 라서 이 순서는 절대 바꾸면 안 된다.

| xlconcat 포트 | 연결된 IP | XIntc ID | 소스 |
|---|---|---|---|
| In0 | `axi_uartlite_0/interrupt` | 0 | (이번 빌드는 미사용) |
| In1 | `fault_manager_ip_0/irq` | 1 | `INTR_ID_FM` |
| In2 | `myip_heartbeat_monit_0/irq` | 2 | `INTR_ID_HB` |
| In3 | `safety_controller_0/irq` | 3 | `INTR_ID_SC` |

> 배선은 `bd_connect_ac.tcl` 5번 섹션, ID 정의는 `mission_intr.h` 에 있다.

#### (2) IP 안쪽 — 레지스터 딱 2개다

각 IP 는 IRQ 관련 레지스터를 2개만 가진다. 이름은 셋 다 같고 주소만 다르다.

| IP | IRQ_EN (주소) | IRQ_STATUS (주소) | STATUS 비트 뜻 |
|---|---|---|---|
| A 하트비트 | `0x20` | `0x24` | bit[2:0] = Device 0/1/2 Timeout 발생 |
| B 고장관리 | `0x20` | `0x24` | bit0 = fault level/device/code 중 하나 바뀜 |
| C 안전제어 | `0x18` | `0x1C` | bit0 = system_state 바뀜 |

그리고 `irq` 핀은 이 두 개를 AND 한 것이다.

```verilog
// rtl/fault_manager_axi.v
assign irq = reg_irq_status & reg_irq_en;
```

#### (3) 핵심 — irq 는 "펄스"가 아니라 "계속 켜져 있는 신호"다

여기가 제일 헷갈리는 부분이다. 순서대로 보면:

```
① 고장 발생
      fault_change_event 가 1클럭짜리 짧은 펄스로 튄다
                 │
                 ▼
② IRQ_STATUS bit0 = 1  ← 여기서 래치된다. 스스로 안 내려간다.
                 │
                 ▼
③ irq 핀 HIGH 유지 ────▶ xlconcat In1 ────▶ INTC ────▶ MicroBlaze 인터럽트
                 │
                 ▼
④ ISR 진입 : IRQ_STATUS 읽어서 원인 확인 → 그 자리에 1 을 써서 Clear (W1C)
                 │
                 ▼
⑤ IRQ_STATUS = 0  →  irq 핀 LOW  →  조용해짐
```

**②의 래치를 아무도 안 내려주면 ③이 영원히 HIGH다.** 그러면 INTC 가 계속
"인터럽트 났다"고 알려서 MicroBlaze 가 같은 ISR 만 무한히 재진입하고, 메인 루프가
못 돌아 UART 도 멈춘다. 그래서 **W1C 는 선택이 아니라 필수**다.

> **W1C = Write 1 to Clear.** 지우고 싶은 비트 자리에 `1` 을 써 넣으면 그 비트가
> `0` 이 된다. `0` 을 쓰는 게 아니다. 이렇게 만들면 "지우려던 순간에 새로 들어온
> 다른 비트"를 실수로 같이 지우지 않는다.

#### (4) 그럼 평소엔 누가 지우나

ISR 이 자동으로 한다. 사람이 누를 일이 없다.

```c
/* SOC_Pr_Vitis/soc_prj/src/mission_intr.c */
static void FM_IsrHandler(void *ref)
{
    g_fm_irq.cause = FM_ReadIrqStatus();      /* ① 원인 읽고            */
    FM_ClearIrq(FM_IRQ_FAULT_CHANGE);         /* ② 바로 W1C — 이게 그거 */
    snap_push();                              /* ③ 그 순간 상태 스냅샷  */
    g_fm_irq.count++;
    g_fm_irq.flag = 1;
}
```

#### (5) 그럼 `Clear IRQ` 버튼은 왜 있나

**비상용 겸 검증용이다.** 세 IP 의 Pending 을 한 번에, 조건 없이 내린다.

> **주의 — `$ACK` 만으로는 아무것도 증명 못 한다.**
> ISR 이 IRQ 뜨자마자 us 안에 W1C 한다. 사람이 버튼을 누르는 건 그로부터 수백 ms
> 뒤라 IRQ_STATUS 는 **항상 이미 0** 이다. 0 을 지우면 그대로 0 이다.
> `$ACK,CMD,CLEAR_IRQ` 는 "명령이 파싱됐다"는 뜻이지 W1C 가 동작한다는 증거가
> 아니다. 진짜 증명은 (5-1) 절차로 한다.

```c
/* SOC_Pr_Vitis/soc_prj/src/uart_proto.c — CMD,CLEAR_IRQ */
FM_ClearIrq(FM_IRQ_FAULT_CHANGE);   /* B bit0        */
HB_ClearIrq(HB_IRQ_ALL);            /* A bit[2:0] 전부 */
SC_ClearIrq(SC_IRQ_STATE_CHANGE);   /* C bit0        */
```

쓸 데가 생기는 상황:

- **부팅 순서 꼬였을 때.** IRQ_EN 을 켜는 순간 IRQ_STATUS 에 옛날 값이 남아 있으면
  아무 일도 없었는데 인터럽트가 터진다. 그래서 부팅 8단계에서 세 Pending 을 먼저
  다 지우고 12단계에서 IRQ_EN 을 켠다 (`main.c` `boot_sequence()`).
- **디버거로 MicroBlaze 만 재시작했을 때.** AXI IP 들은 리셋이 안 돼서 Pending 이
  살아 있다. 이때 수동으로 정리하는 용도.
- **점검자가 "IRQ 정리 경로도 UART 로 조작 가능한가"를 물을 때.** 15번 단계가
  그 답이다.

#### (5-1) W1C 를 진짜로 증명하는 방법

핵심은 (3)의 이 한 줄이다.

```verilog
if (fault_change_event) reg_irq_status <= 1'b1;   // SET 은 irq_en 과 무관
assign irq = reg_irq_status & reg_irq_en;         // 핀만 irq_en 이 막는다
```

**`IRQ_EN=0` 이면 STATUS 는 그대로 래치되는데 irq 핀은 안 올라간다.**
→ ISR 이 안 돈다 → **Pending 이 살아남는다.**

이게 "부팅 순서 꼬임"(IRQ_EN 을 켜기 전에 STATUS 에 값이 남는 상황)을 그대로
재현하는 것이기도 하다. 15번 단계가 이 절차다.

```
15    IRQ 상태 읽기            → $IRQ,0x07,0x00,0x00,0x00   평상시 = 전부 0
15-1  체크 3개 해제 + 적용     → SET,IRQ_EN,0x00
15-2  DEVICE 1 Error           → 고장 발생. irq 핀이 막혀 ISR 이 안 돈다
15-3  IRQ 상태 읽기            → $IRQ,0x00,0x00,0x01,0x01   ← 래치 증명
15-4  Clear IRQ                → $ACK,CMD,CLEAR_IRQ
15-5  IRQ 상태 읽기            → $IRQ,0x00,0x00,0x00,0x00   ← W1C 증명
15-6  Error 체크 해제
15-7  체크 3개 재체크 + 적용   → SET,IRQ_EN,0x07            ← 빠뜨리지 말 것
```

> **체크박스는 "보낼 값"일 뿐 누른다고 전송되지 않는다.** 반드시 `IRQ_EN 적용`
> 버튼을 눌러야 나간다. 체크박스마다 자동 전송하면 3개를 푸는 동안 명령이
> 3번 나가고, 9600bps 라 늦게 도착한 첫 응답이 화면을 되돌린다.
> 보드가 실제로 어떤 값인지는 옆의 `보드 실제값` 칸에서 확인한다.

| 증거 | 어느 단계에서 나오나 |
|---|---|
| Pending 은 스스로 안 내려간다 (래치다) | 15-3 |
| IRQ_EN 이 irq 핀을 막는다 | 15-2 에 `irq FM` RAW 줄이 없음 |
| `Clear IRQ` 가 실제로 W1C 한다 | 15-3 → 15-5 의 차이 |
| `Clear IRQ` 는 상태를 안 건드린다 | 15-4 앞뒤 `$MISSION` 이 동일 |

> **15-7 을 빠뜨리면 안 되는 이유.** IRQ_EN 이 꺼진 동안은 ISR 이 돌지 않아
> 상태 Snapshot 이 쌓이지 않는다. 그러면 짧게 스쳐 가는 WARNING 을 다시 놓친다.
> (메인 루프 폴링 백스톱은 살아 있어서 `FAULT_CHANGE` / `STATE_CHANGE` 자체는
> 계속 나온다.) 앱은 `IRQ_EN` 이 `0b111` 이 아니면 `IRQ 상태` 박스에 주황색
> 경고를 계속 띄우니 그걸로 확인하면 된다.

#### (6) 그래서 눌러도 화면이 안 바뀌는 게 정상이다

`Clear IRQ` 가 만지는 건 IRQ_STATUS 레지스터 **하나뿐**이다. 아래 것들은 **전혀
안 건드린다.**

| 안 바뀌는 것 | 이유 |
|---|---|
| `fault_level` / `fault_device` / `fault_code` | B 의 판정 결과. 입력(고장)이 그대로면 그대로다 |
| `system_state` (NORMAL/WARNING/…) | C 의 상태. Pending 과 무관 |
| `output_enable`, `actuator_enable` | C 의 출력. 상태 따라 결정 |
| Heartbeat Timeout 래치, Fault Count | `Clear Heartbeat` / `Reset Fault` 담당 |

**확인 방법 = CSV 뿐이다.** `$ACK,CMD,CLEAR_IRQ` 앞뒤의 `$MISSION` 값이 완전히
똑같으면 정상이다. 15-4 단계가 이걸 본다.

그리고 "Pending 이 실제로 지워졌는가"는 앞뒤 `$IRQ` 두 줄을 비교해서 본다
(15-3 vs 15-5). `$MISSION` 에는 IRQ 정보가 없으므로 `GET,IRQ` 를 따로 눌러야 한다.

#### (7) 비슷해 보이는 3형제 정리

| 명령 | 만지는 것 | 안 만지는 것 | 조건 |
|---|---|---|---|
| `CMD,CLEAR_IRQ` | 세 IP 의 IRQ_STATUS | 고장 상태 전부 | 없음. 항상 통과 |
| `CMD,CLEAR_HEARTBEAT` | A 의 Counter / Timeout 래치 | IRQ Pending | 없음. 항상 통과 |
| `CMD,RESET_FAULT` | B 의 Fault Count + B 의 Pending | A / C 는 안 건드림 | **현재 Fault 0개일 때만.** 하나라도 있으면 `$ERR,...,FAULT_ACTIVE` |

---

### 6.2 그 밖에 나올 만한 질문

**Q. Reset Fault 랑 Manual Recovery 랑 뭐가 다른가?**
대상 IP 가 다르다.
- `Reset Fault` → **B(fault_manager)** 의 Count 와 과거 비교 정보를 지운다.
  "고장 판정 기록을 청소"하는 것.
- `Manual Recovery` → **C(safety_controller)** 의 SAFE_MODE 래치를 푼다.
  "안전 모드에서 빠져나오는" 것.

둘 다 "고장이 다 없어졌을 때만" 통과한다는 점은 같다. 그래서 SAFE_MODE 에서
빠져나오려면 순서가 `Clear All Injection` → `Manual Recovery` 다. 순서를 바꾸면
`$ERR,MANUAL_RESET,FAULT_ACTIVE` 가 뜬다 (21번 단계가 일부러 그걸 본다).

**Q. Event Log 의 `irq FM status=0x01 count=17` 은 뭔가?**
IRQ 가 실제로 MicroBlaze 까지 도달했다는 증거 줄이다. `status` 는 ISR 이 읽은
IRQ_STATUS 값, `count` 는 그 IP 의 ISR 누적 진입 횟수다. 04 체크리스트 5.2 의
"IRQ 전체 경로가 살아 있는가"를 이 줄로 증명한다.

**Q. 그 `count` 가 17 다음에 19 로 건너뛰던데, UART 가 씹힌 건가?**
아니다. 정상이다. ISR 은 진입할 때마다 `count` 를 올리지만, 메인 루프에 넘기는
`flag` 는 카운터가 아니라 0/1 이다. 한 Tick(5ms) 안에 같은 IP 의 IRQ 가 두 번
들어오면 `count` 는 2 오르고 이 줄은 한 번만 나간다. **값 자체는 하나도 안 잃는다** —
ISR 이 매번 상태 스냅샷을 Ring 에 넣고 메인 루프가 순서대로 전부 보고한다.
오히려 `count` 가 건너뛴 건 "5ms 안에 전이가 여러 번 있었다"는 증거다.

**Q. `FAULT_CHANGE (2, 1, 2)` — 괄호 안 숫자 순서가 뭔가?**
`(fault_level, fault_device, fault_code)` 순이다. 그러니까 이건
"등급 2(DEGRADED), Device 1, 코드 2(FAULT_ERROR)".

| 자리 | 값 |
|---|---|
| level | 0=정상 1=WARNING 2=DEGRADED 3=위험 |
| device | 0/1/2 = 해당 장치, **3 = 없음 또는 다중** |
| code | 0=없음 1=TIMEOUT 2=ERROR 3=CRITICAL 4=MULTI_DEVICE |

`FAULT_CHANGE (0, 3, 0)` 은 "고장 전부 해소" 라는 뜻이다.

**Q. `oe=0x05` 는 어떻게 읽나?**
bit0 이 Device 0 이다. `0x05` = `0b101` → Device 0 켜짐, **Device 1 차단**,
Device 2 켜짐. `alive` / `timeout` 마스크도 같은 규칙이다.

| 값 | 뜻 |
|---|---|
| `0x07` (`0b111`) | 셋 다 정상 출력 |
| `0x06` (`0b110`) | Device 0 만 차단 |
| `0x05` (`0b101`) | Device 1 만 차단 |
| `0x00` (`0b000`) | 전부 차단 = SAFE_MODE |

**Q. Device 마다 Timeout 걸리는 시간이 다른 이유는?**
`SET,TIMEOUT,n,<클럭수>` 로 장치별로 따로 잡아놨다. 100MHz 기준이라
클럭수 ÷ 100,000,000 이 초다.

| Device | 클럭 수 | 시간 |
|---|---|---|
| 0 | 30,000,000 | 0.30초 |
| 1 | 60,000,000 | 0.60초 |
| 2 | 15,000,000 | 0.15초 |

Device 2 가 제일 짧은 건 핵심 장치라 빨리 잡아야 해서다. `Get Config` 응답으로
현재 값을 언제든 확인할 수 있다.

**Q. `WARNING` 이 왜 큰 글씨엔 안 뜨고 `최근 전이:` 줄에만 뜨나?**
**갱신 방식이 다르다.**

| 표시 | 무엇으로 갱신되나 | 주기 |
|---|---|---|
| 큰 글씨 (①) | `$MISSION` 주기 보고 | **500ms 마다** |
| `최근 전이:` 줄 | `$EVENT,...,STATE_CHANGE` | **전이가 일어날 때마다** |

`eval_tick` 이 1ms 이므로 WARNING 유지 시간은 `PERSIST_LIMIT` × 1ms 다.
**이 시나리오는 0-4 단계에서 255 로 올리므로 255ms 다** (설정을 안 바꾼
기본값이면 5ms). 어느 쪽이든 500ms 마다 한 번 찍는 큰 글씨보다 짧아서
큰 글씨에는 안 잡힌다.

반면 `STATE_CHANGE` 는 하드웨어가 전이 순간에 올린 IRQ 로 만들어져서 **유지 시간과
무관하게 전부 도착한다.** 그래서 짧은 상태는 `최근 전이:` 줄로 확인하는 게 맞다.
큰 글씨는 일부러 `$MISSION` 만 따르게 뒀다 — 그건 "지금 상태"를 말해야 하는데
이미 지나간 전이로 덮어쓰면 거짓말이 되기 때문이다.

**Q. `$MISSION` 의 `timestamp_ms` 가 실제 시간이랑 안 맞는데?**
정상이다. BD 에 AXI Timer 가 없어서 메인 루프가 직접 ms 를 센다
(`main.c` 의 `g_ms += TICK_MS`). UART 전송 시간만큼 실제보다 느리게 흘러서
실측 약 10% 느리다. **표시용이라 판정에는 안 쓴다.** 순서를 볼 때는
`timestamp_ms` 를, 실제 경과 시간을 볼 때는 CSV 첫 칸 `received_at`(PC 시각)을
보면 된다.

**Q. `Device 0 + Device 1 Multi Fault` 는 왜 fault_code 가 4 인가?**
장치 두 개가 동시에 고장이면 "어느 장치 탓"이라고 특정할 수 없다. 그래서
`fault_device = 3`(=없음/다중), `fault_code = 4`(`FAULT_MULTI_DEVICE`) 로 보고하고
등급은 무조건 최고(3)로 올린다. 16번 단계가 이걸 본다.
