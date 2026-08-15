# 공통 `eval_tick_generator` 최종 검증 결과

## 1. 검증 목적

`eval_tick_generator`는 Fault Manager의 일반 Fault 지속 Count와 Safety Controller의 Recovery Count에 공통으로 공급되는 1클럭 Pulse를 생성한다.

00~04 명세에 따라 다음 항목을 검증하였다.

- 시스템 클럭: 100 MHz
- Reset 중 `eval_tick = 0`
- Reset 중 내부 Divider Counter 초기화
- Reset 해제 후 `DIVISOR`클럭 뒤 첫 Pulse 발생
- `eval_tick` Pulse 폭이 정확히 1클럭
- 이후 Pulse 주기가 정확히 `DIVISOR`클럭
- 일정 구간 동안 Pulse 개수가 예상값과 일치
- Fault Manager와 Safety Controller가 동일한 `eval_tick`을 사용

실제 통합 환경에서는 `DIVISOR = 100_000`으로 설정하여 1 ms마다 1클럭 Pulse를 생성한다. 단위 Testbench에서는 시뮬레이션 시간을 줄이기 위해 `DIVISOR = 20`으로 설정하였다.

---

## 2. 시뮬레이션 조건

```text
Clock frequency : 100 MHz
Clock period    : 10 ns
Test DIVISOR    : 20
Expected period : 20 clocks = 200 ns
Reset duration  : 12 clocks
Simulation end  : 2515 ns
```

Testbench는 Self-checking 방식으로 구성하였으며, 각 검증 결과를 `checks`와 `errors` 변수에 누적한다.

```text
checks = 수행된 검증 항목 수
errors = 실패한 검증 항목 수
```

최종 결과:

```text
checks = 5
errors = 0
ALL PASS
```

---

## 3. 파형 및 Testbench 검증 결과

### E01. Reset 동작 검증

Reset이 High인 동안 다음 조건을 확인하였다.

```text
eval_tick = 0
dut.div_cnt = 0
```

따라서 Reset 중 잘못된 Tick이 발생하지 않으며 내부 Divider Counter가 정상적으로 초기화됨을 확인하였다.

---

### E02. 첫 Pulse 발생 시점 검증

Reset 해제 시점과 첫 번째 Pulse 발생 시점은 다음과 같다.

```text
rel_clk = 12
t_first = 32
```

따라서:

```text
t_first - rel_clk
= 32 - 12
= 20 clocks
```

첫 번째 `eval_tick`이 Reset 해제 후 정확히 `DIVISOR`인 20클럭 뒤 발생하였다.

---

### E03. Pulse 폭 검증

첫 번째 Pulse가 발생한 다음 클럭에서 `eval_tick`이 다시 0으로 내려가는 것을 확인하였다.

```text
Pulse width = 1 clock
```

따라서 `eval_tick`은 Level 신호가 아니라 정확한 1클럭 Pulse로 동작한다.

이로 인해 Fault Manager의 Persist Count와 Safety Controller의 Recovery Count가 한 평가 시점에 한 번씩만 증가한다.

---

### E04. 반복 주기 검증

첫 번째와 두 번째 Pulse 발생 시점은 다음과 같다.

```text
t_first  = 32
t_second = 52
```

따라서:

```text
t_second - t_first
= 52 - 32
= 20 clocks
```

100 MHz 클럭의 한 주기는 10 ns이므로:

```text
20 clocks × 10 ns = 200 ns
```

Pulse 주기가 Testbench 설정값인 `DIVISOR = 20`과 정확히 일치함을 확인하였다.

---

### E05. 10주기 Pulse 개수 검증

10개의 평가 주기 동안 발생한 `eval_tick` Pulse 개수를 측정하였다.

```text
Expected pulse count = 10
Measured width       = 10
```

콘솔 출력:

```text
[ ok ] pulse count over 10 periods (=10)
checks = 5, errors = 0 -> ALL PASS
$finish called at time : 2515 ns
```

따라서 10주기 동안 정확히 10개의 Pulse가 발생했으며, Pulse 누락이나 중복 발생이 없음을 확인하였다.

---

## 4. 최종 결과표

| 검증 항목 | 기대 결과 | 실제 결과 | 판정 |
|---|---|---|---|
| Reset 중 `eval_tick` | `0` 유지 | `0` 유지 | 통과 |
| Reset 중 Divider Counter | `0` 초기화 | `0` 확인 | 통과 |
| 첫 Pulse 발생 시점 | Reset 해제 후 20클럭 | 20클럭 | 통과 |
| Pulse 폭 | 1클럭 | 1클럭 | 통과 |
| Pulse 반복 주기 | 20클럭, 200 ns | 20클럭, 200 ns | 통과 |
| 10주기 Pulse 개수 | 10회 | 10회 | 통과 |
| Self-checking 결과 | Error 0 | `checks=5`, `errors=0` | 통과 |

---

## 5. 00~04 명세와의 연계

본 `eval_tick_generator`는 다음과 같이 통합한다.

```text
eval_tick_generator.eval_tick
├─ fault_manager_ip.eval_tick
└─ safety_controller_ip.eval_tick
```

### Fault Manager에서의 사용

- 일반 단일 Fault의 지속 Count를 `eval_tick=1`인 클럭에서만 증가
- `PERSIST_LIMIT` 이상 지속 여부 판정에 사용
- Critical Fault 및 다중 장치 Fault 판정에는 사용하지 않음
- Critical 및 Multi-device Fault는 매 시스템 클럭에서 판정

### Safety Controller에서의 사용

- `WARNING → NORMAL` Recovery Count에 사용
- `DEGRADED → WARNING` Recovery Count에 사용
- `DEGRADED → NORMAL` Recovery Count에 사용
- `fault_valid`를 Recovery Tick으로 사용하지 않음
- `SAFE_MODE` 자동 복구에는 사용하지 않음

따라서 본 모듈은 일반 Fault 지속시간과 Recovery 안정화 횟수를 공통 시간 기준으로 맞추는 역할을 수행한다.

---

## 6. 최종 결론

Self-checking Testbench를 통해 `eval_tick_generator`의 Reset 동작, 첫 Pulse 시점, Pulse 폭, 반복 주기 및 장시간 Pulse 개수를 검증하였다.

최종 시뮬레이션 결과는 다음과 같다.

```text
checks = 5
errors = 0
ALL PASS
```

따라서 `eval_tick_generator`는 00~04 공통 명세에서 요구하는 동작을 만족하며, Fault Manager와 Safety Controller에 공통 평가 Tick으로 연결할 수 있다.

---

## 7. 제출용 캡처 권장 구성

최종 보고서에는 다음 두 화면을 함께 첨부한다.

1. 파형 화면  
   - `eval_tick`이 1클럭 Pulse로 반복되는 모습
   - `t_first = 32`
   - `t_second = 52`
   - `width = 10`
   - `checks = 5`
   - `errors = 0`

2. 콘솔 화면  
   - `[ ok ] pulse count over 10 periods (=10)`
   - `checks = 5, errors = 0 -> ALL PASS`
   - `$finish called at time : 2515 ns`

파형 화면은 실제 신호 동작을 보여주고, 콘솔 화면은 Self-checking Testbench의 최종 통과 결과를 증명한다.
