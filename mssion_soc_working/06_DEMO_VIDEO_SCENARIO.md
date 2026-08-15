# 06. 시연 영상 촬영 시나리오 (1분 편집본)

**목적** — Mission SoC 의 존재 이유 네 가지를 최단 경로로 보여준다.

| # | 보여줄 것 | 담당 IP |
|---|---|---|
| ① | 하트비트로 장치 생존을 **실제로** 감시한다 | A `heartbeat_monitor` |
| ② | 고장 지속성·우선순위로 **등급을 산출**한다 | B `fault_manager` |
| ③ | 등급에 따라 출력을 차단하고 SAFE_MODE 는 **래치**된다 | C `safety_controller` |
| ④ | 복구는 **조건부 승인**이다. 아무 때나 안 풀린다 | C `safety_controller` |

**앱 조작 6클릭 / 약 32초.** 편집 후 나레이션 포함 55~60초 목표.
전체 28단계 검증본은 `05_BOARD_INTEGRATION_TEST_SCENARIO.md` 다. 이 문서는 촬영용 발췌다.

---

## 0. 촬영 전 준비 (녹화 시작 전에 끝낼 것)

| 순서  | 할 일                                                      | 확인                             |
| --- | -------------------------------------------------------- | ------------------------------ |
| 0-1 | 앱 **재시작** (프리셋 버튼 라벨 최신본 반영)                             | `Fault Injection` 탭에 프리셋 4개 보임 |
| 0-2 | `연결` 탭 → COM Port 선택, **Baudrate 9600** → `연결`           | 우측 상단 `연결됨 (CONNECTED)` 초록색    |
| 0-3 | Basys3 **가운데 버튼(btnC)** 1회 리셋                            | Event Log 에 `Boot complete`    |
| 0-4 | `설정 · 제어` 탭 → `PERSIST_LIMIT` 칸 **5 → 255** → `설정 전체 전송` | `$ACK,SET,PERSIST_LIMIT,255`   |
| 0-5 | `연결` 탭 → `기록 시작 / 중지` (CSV 로그 켜기)                        | "기록 중: ..." 문구                 |
| 0-6 | 화면 상태가 **`NORMAL` / `LEVEL_0` / `oe=0x07`** 인지 확인        | 초록                             |

> **0-4 를 빼먹으면 WARNING 이 화면에 안 뜬다.**
> `PERSIST_LIMIT` 이 기본값 5 면 WARNING 구간이 5ms 라, `$MISSION` 갱신 주기(실측 약 550ms)에
> 걸릴 확률이 사실상 0 이다. 255 로 올리면 255ms 가 되어 큰 글씨 상태 표시에도 잡힌다.
> (`최근 전이` 트레일은 이벤트 구동이라 두 경우 다 남지만, 영상은 큰 글씨가 잘 보인다.)

### 0-4 에서 **`PERSIST_LIMIT` 만** 바꾼다 — 나머지는 손대지 말 것

| 설정 | 값 | 바꾸나 | 이유 |
|---|---|---|---|
| `PERSIST_LIMIT` | 5 → **255** | **바꾼다** | WARNING 구간을 255ms 로 늘려 화면에 보이게 한다 |
| `RECOVERY_COUNT` | **2 그대로** | 안 바꾼다 | 아래 참조 |
| `TIMEOUT0/1/2` | 기본값 | 안 바꾼다 | 컷 ① 의 0.3초 지연이 기본값 기준 설명이다 |
| `CRITICAL_MASK` | `0x04` | 안 바꾼다 | 컷 ③ 이 Device 2 를 임무 필수로 쓴다 |
| `DEGRADE_MASK` | `0x01` | 안 바꾼다 | 컷 ① 의 `oe=0x06` 부분 차단이 이 값 기준이다 |

**`RECOVERY_COUNT=2` 는 그대로 둔다. 이 시연에서 바꿀 의미가 없다.**

`safety_controller.v` 를 보면 `recovery_count` 는 **하강 전이에만** 쓰인다 —
`WARNING → NORMAL`, `DEGRADED → WARNING`, `DEGRADED → NORMAL` 세 경로다.
등급이 **올라갈 때는 전혀 개입하지 않고**, `SAFE_MODE` 탈출은 오직 `MANUAL_RESET` 이라
`recovery_count` 와 무관하다.

| 컷 | `RECOVERY_COUNT` 영향 |
|---|---|
| ① 등급 상승 | 없음 (상승 경로는 `PERSIST_LIMIT` 이 결정) |
| ② DEGRADED → NORMAL | **여기만 영향.** 2 × `eval_tick`(1ms) = **2ms** — 사실상 즉시 |
| ③ 즉시 SAFE_MODE | 없음 |
| ④⑤⑥ 복구 거부 / 래치 / 승인 | 없음 (`MANUAL_RESET` 전용 경로) |

올려봐야 컷 ② 에서 죽은 시간만 늘어나고 **새로 보이는 상태가 없다.**
`DEGRADED → WARNING` 하강은 `RECOVERY_COUNT` 를 아무리 만져도 GUI 로는 도달 불가다
(`persist_cnt` 가 255 에서 포화). 게다가 권장 조건 `RECOVERY_COUNT < PERSIST_LIMIT`
(03_MEMBER_C 6장) 이 `2 < 255` 로 이미 충족이라, 올리면 이 조건만 위태로워진다.

> **예상 질문 대비** — "왜 고장 판정이 255ms 나 걸리냐" 고 물으면:
> **255 는 촬영용 임시값**이고 운용 기본값은 `5`(5ms) 라고 답한다.
> WARNING 단계를 화면에 보이게 하려고 일부러 늘린 것이며, `SET,PERSIST_LIMIT` 경로가
> 런타임에 동작한다는 증명도 겸한다. 로그 `mission_events_20260731_141013.csv` 는
> 기본값 5 로 돌린 것이고 거기서도 WARNING 이 정상 기록됐다.

**촬영 레이아웃 권장** — `Fault Injection` 탭과 `Event Log` 가 한 화면에 같이 보이게 배치한다.
클릭하는 손과 로그가 같은 프레임에 있어야 인과가 보인다.

---

## 1. 전체 단계표 (촬영 중엔 이 표만 본다)

녹화 ON 상태에서 위에서 아래로 그대로 따라간다. **총 6클릭.**

| 단계 | 탭 | 조작 | 보내는 명령 | 대기 | 화면에서 확인할 것 |
|---|---|---|---|---|---|
| 1 | Fault Injection | **DEVICE 0 `Timeout`** 체크 | `INJECT,TIMEOUT,0,ON` | — | `$ACK,INJECT,TIMEOUT,0` |
| 2 | — | (대기) | — | **약 1초** | `HEARTBEAT_TIMEOUT,0` → `WARNING` → `DEGRADED` 순서대로.<br>큰 글씨 `DEGRADED`, **`oe=0x06`**, `alive=0x06` |
| 3 | Fault Injection | **DEVICE 0 `Timeout`** 체크 해제 | `INJECT,TIMEOUT,0,OFF` | 약 0.5초 | `FAULT_CHANGE,0,3,0` → `STATE_CHANGE,NORMAL`, `oe=0x07` **자동 복귀** |
| 4 | Fault Injection | **`Device 2 Critical Demo`** 프리셋 버튼 | `INJECT,CRITICAL,2,ON` | — | 중간 등급 **없이** 곧바로 `SAFE_MODE`.<br>`FAULT_CHANGE,3,2,3`, **`oe=0x00`**, `alive=0x07` |
| 5 | 설정 · 제어 | **`Manual Recovery`** → 확인창 `Yes`<br>(Critical 체크는 **끄지 않은 채로**) | `CMD,MANUAL_RESET` | — | **`$ERR,MANUAL_RESET,FAULT_ACTIVE`** + `MANUAL_RESET,REJECTED`.<br>상태는 `SAFE_MODE` 그대로 → **거부 증명** |
| 6 | Fault Injection | **`Clear All Injection`** 버튼 | `INJECT,CLEAR,ALL` | 약 0.5초 | `FAULT_CHANGE,0,3,0` — **고장 등급은 `LEVEL_0` 인데 상태는 `SAFE_MODE` 유지**.<br>`STATE_CHANGE` 가 **안 나온다** → **래치 증명** |
| 7 | 설정 · 제어 | **`Manual Recovery`** → `Yes` | `CMD,MANUAL_RESET` | — | 이번엔 **`$ACK,CMD,MANUAL_RESET`** + `MANUAL_RESET,ACCEPTED` + `STATE_CHANGE,NORMAL`, `oe=0x07` |
| 8 | Event Log | **`CSV 저장`** (녹화 정지 후) | — | — | 영상과 함께 제출할 로그 파일 |

**선택 확장** — 다중 장치 판정까지 넣으려면 3 과 4 사이에 끼운다. 약 +10초, 1분을 넘긴다.

| 단계 | 탭 | 조작 | 보내는 명령 | 대기 | 화면에서 확인할 것 |
|---|---|---|---|---|---|
| 3-1 | Fault Injection | **`D0 + D1 Error (다중 장치 Multi)`** 프리셋 | `INJECT,ERROR,0,ON` + `INJECT,ERROR,1,ON` | 약 1초 | `WARNING` → `DEGRADED`(device 0) → 약 0.2초 뒤 **`FAULT_CHANGE,3,3,4`** + `SAFE_MODE`.<br>fault_device 가 **`3`**(특정 불가), code 가 `MULTI_DEVICE` |
| 3-2 | Fault Injection | **`Clear All Injection`** → `LEVEL_0` 확인 → 설정·제어 **`Manual Recovery`** → `Yes` | `INJECT,CLEAR,ALL` + `CMD,MANUAL_RESET` | 약 1초 | `NORMAL` 복귀 후 4단계로 진행 |

> **3-1 나레이션 주의 — "동시에"라고 말하지 말 것.**
> 두 `INJECT` 는 별개 UART 줄이라 9600bps 링크에서 순차 처리된다(실측 229ms).
> 보드 내부 지연은 `PERSIST_LIMIT` tick 하나뿐이고, 화면상 2단계로 보이는 건
> **링크 전송 시간 때문**이다. 클럭 단위 동시 성립은 UART 로 관측할 수 없고
> `sim/tb_fault_manager_core.v` 가 커버한다.

---

## 2. 컷별 상세 — 나레이션 대본과 실측 기대값

표만으로 충분하면 이 장은 안 봐도 된다. 나레이션 짤 때 참고용이다.

### 컷 ① 하트비트 끊김 → 등급 상승 → 부분 차단  · 약 8초

| 조작 | 화면에서 짚을 것 |
|---|---|
| `Fault Injection` → **DEVICE 0 `Timeout`** 체크 | — |
| (약 0.5초 대기) | `HEARTBEAT_TIMEOUT,0` → `WARNING` → `DEGRADED` 가 **순서대로** 흐른다 |

**여기서 말할 것** — Error 주입이 아니라 **하트비트를 진짜로 멈춘 것**이다.
A 가 `TIMEOUT0`(30,000,000 clk = 0.3초) 초과를 스스로 판정해 `timeout[0]` 을 세운다.

실측 기대값:

```
$EVENT,HEARTBEAT_TIMEOUT,0
$EVENT,FAULT_CHANGE,1,0,1     ← Level 1 WARNING, device 0, code TIMEOUT
$EVENT,STATE_CHANGE,WARNING
$EVENT,FAULT_CHANGE,2,0,1     ← 지속되어 Level 2 로 승격
$EVENT,STATE_CHANGE,DEGRADED
$MISSION  DEGRADED  lvl 2  dev 0  code 0x01   alive=0x06 timeout=0x01 oe=0x06
```

**`oe=0x06` 이 핵심이다.** 전체 차단이 아니라 **고장 난 Device 0 만** 끊었다.
`alive=0x06` 은 Device 0 의 하트비트가 실제로 죽었다는 뜻이다.

---

### 컷 ② 원인이 사라지면 자동 복귀  · 약 4초

| 조작 | 화면에서 짚을 것 |
|---|---|
| **DEVICE 0 `Timeout`** 체크 해제 | `FAULT_CHANGE,0,3,0` → `STATE_CHANGE,NORMAL`, `oe=0x07` 복귀 |

**여기서 말할 것** — DEGRADED 까지는 **자동 복귀**한다. 사람 개입이 필요 없다.
다음 컷에서 SAFE_MODE 는 그렇지 않다는 걸 대비시킨다.

---

### 컷 ③ Critical 은 지속시간을 안 따진다 → 즉시 전면 차단  · 약 5초

| 조작 | 화면에서 짚을 것 |
|---|---|
| **`Device 2 Critical Demo`** 프리셋 버튼 | 중간 등급 없이 **곧바로** `SAFE_MODE` |

실측 기대값:

```
$EVENT,FAULT_CHANGE,3,2,3     ← Level 3, device 2, code CRITICAL
$EVENT,STATE_CHANGE,SAFE_MODE
$MISSION  SAFE_MODE  lvl 3  dev 2  code 0x03   alive=0x07 timeout=0x00 oe=0x00
```

**여기서 말할 것** — `CRITICAL_MASK=0x04` 로 Device 2 를 임무 필수 장치로 지정해 뒀다.
그래서 `PERSIST_LIMIT` 지속 판정을 **건너뛴다**. FM 조합 판정 1클럭 + SC 전이 1클럭,
100MHz 기준 **2클럭(20ns)** 만에 SAFE_MODE 다. `eval_tick` 도 안 기다린다.

`alive=0x07` 인 점을 짚으면 좋다 — 하트비트는 멀쩡한데 Critical 하나로 전면 차단(`oe=0x00`)됐다.

---

### 컷 ④ 복구 거부 — 고장이 살아있으면 안 풀어준다  · 약 5초

| 조작 | 화면에서 짚을 것 |
|---|---|
| `설정 · 제어` → **`Manual Recovery`** → `Yes` | **`$ERR,MANUAL_RESET,FAULT_ACTIVE`**, 상태는 `SAFE_MODE` 그대로 |

**여기서 말할 것** — 이게 이 프로젝트의 안전 논거다.
운용자가 눌러도 `fault_level != 0` 이면 **하드웨어가 거부**한다. 소프트웨어 판단이 아니다.

```
$ERR,MANUAL_RESET,FAULT_ACTIVE
$EVENT,MANUAL_RESET,REJECTED
```

---

### 컷 ⑤ 원인을 없애도 SAFE_MODE 는 안 풀린다 (Latch)  · 약 5초

| 조작 | 화면에서 짚을 것 |
|---|---|
| `Fault Injection` → **`Clear All Injection`** | `fault_level` 이 `3 → 0` 인데 **상태는 `SAFE_MODE` 유지** |

실측 기대값:

```
$EVENT,FAULT_CHANGE,0,3,0
$MISSION  SAFE_MODE  lvl 0  dev 3  code 0x00   alive=0x07 timeout=0x00 oe=0x00
                     ~~~~~~~~~~~~~ 등급은 0     ~~~~~~~ 그래도 SAFE_MODE / 전면 차단
```

**여기서 말할 것** — 고장이 사라졌다고 스스로 복귀하면 안 된다.
이유가 사라진 것과 **안전이 확인된 것은 다르다.** 그래서 SAFE_MODE 는 래치다.
`STATE_CHANGE` 이벤트가 **안 나온다**는 점을 짚어라.

---

### 컷 ⑥ 조건이 갖춰지면 그때 승인  · 약 5초

| 조작 | 화면에서 짚을 것 |
|---|---|
| `설정 · 제어` → **`Manual Recovery`** → `Yes` | 이번엔 **`$ACK`**, `NORMAL` 복귀, `oe=0x07` |

```
$ACK,CMD,MANUAL_RESET
$EVENT,MANUAL_RESET,ACCEPTED
$EVENT,STATE_CHANGE,NORMAL
```

**여기서 말할 것** — 컷 ④ 와 **완전히 같은 버튼, 같은 명령**이다.
달라진 건 `fault_level` 뿐이다. 승인 조건이 하드웨어에 박혀 있다는 증명이다.

---

## 3. 타임라인 요약 — 나레이션 한 줄

| 단계 | 컷 | 조작 | 누적 | 핵심 한 줄 |
|---|---|---|---|---|
| 1~2 | ① | D0 Timeout 체크 | 8초 | 하트비트 끊기면 스스로 감지해 등급을 올리고 **그 장치만** 끊는다 |
| 3 | ② | D0 Timeout 해제 | 12초 | DEGRADED 는 원인 사라지면 자동 복귀 |
| 4 | ③ | Critical Demo | 17초 | 임무 필수 장치는 지속시간 무시, **20ns** 만에 전면 차단 |
| 5 | ④ | Manual Recovery | 22초 | 고장 살아있으면 **하드웨어가 거부** |
| 6 | ⑤ | Clear All Injection | 27초 | 등급 0 이어도 SAFE_MODE **래치 유지** |
| 7 | ⑥ | Manual Recovery | 32초 | 조건 충족 시에만 승인 |

**총 6클릭 / 약 32초.** 편집에서 대기 구간을 0.5배속 컷하면 25초까지 줄어든다.

---

## 4. 영상에서 뺀 것과 그 이유

빠졌다고 미검증이 아니다. 질문 나오면 이렇게 답한다.

| 항목 | 왜 뺐나 | 어디서 검증했나 |
|---|---|---|
| IRQ 래치 / `Clear IRQ` W1C | 조작 7단계라 30초 예산 초과. 화면 변화도 작다 | `05` 15-1~15-7, 로그 `mission_events_20260731_141013.csv` |
| `Reset Fault` 거부/승인 | `Manual Recovery` 와 논리가 같아 중복 | `05` 9~14 단계 |
| `Clear Heartbeat` 단독 효과 | 0.3초 뒤 재고장이라 영상에서 오해 소지 | `05` 8 단계 |
| `DEGRADED → WARNING` 하강 | **GUI 로 도달 불가** — `persist_cnt` 가 255 포화, `PERSIST_LIMIT` 최대도 255 | `sim/tb_safety_controller_core.v` (44개 통과) |
| 클럭 단위 타이밍 | UART 9600bps 라 관측 분해능이 ms 단위 | 각 IP 의 TB |

---

## 5. 촬영 중 사고 대응

| 증상 | 원인 | 대응 |
|---|---|---|
| WARNING 이 큰 글씨에 안 뜸 | 0-4 를 빼먹음 (`PERSIST_LIMIT=5`) | `최근 전이` 트레일에는 남아있다. 그대로 진행하고 재촬영 때 255 적용 |
| **5단계**에서 `$ACK` 가 옴 (거부 안 됨) | 6단계(`Clear All Injection`)를 먼저 눌렀음 | 순서 확인. Critical 체크가 **켜진 상태**여야 거부된다 |
| **7단계**에서 `$ERR` 가 옴 | `LEVEL_0` 되기 전에 눌렀음 | `고장 등급 LEVEL_0` 확인 후 다시 클릭. **재촬영 불필요** |
| **2단계**에서 `DEGRADED` 가 안 옴 | Timeout 은 0.3초 뒤 성립 — 덜 기다림 | 1초까지 기다린다. 그래도 없으면 `alive` 마스크 확인 |
| 상태가 `SAFE_MODE` 에 갇힘 | 정상 동작(래치) | `Clear All Injection` → `Manual Recovery` |
| 명령이 씹힘 | — | 이번 빌드는 `PROTO_Printf` 가 RX 를 계속 펌프해 유실이 없다. 로그의 `TX,COMMAND` 줄과 `$ACK` 를 대조해라 |

---

## 6. 촬영 후

1. `연결` 탭 → `기록 시작 / 중지` 눌러 CSV 종료
2. `Event Log` 탭 → `CSV 저장`
3. 파일명에 촬영 회차 표기 (예: `demo_take1_<timestamp>.csv`)

영상과 CSV 를 같이 제출하면 화면에 보인 것이 실제 UART 로그와 일치함을 바로 확인시킬 수 있다.
