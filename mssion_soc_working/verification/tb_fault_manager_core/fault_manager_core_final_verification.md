# `fault_manager_core` 최종 검증 결과

## 1. 검증 목적

`tb_fault_manager_core.v`를 이용하여 `fault_manager_core`의 Fault 정책, Persist Count, Critical 우선순위, Event 생성, `RESET_FAULT`, Disable 안전 출력 및 전수 조합 동작을 Self-checking 방식으로 검증하였다.

이번 Testbench는 02 문서의 필수 Core 검증 항목을 수행한 뒤, 마지막에 다음 전수 검증을 추가로 수행한다.

```text
timeout / error_flag / critical_fault : 512개 조합
critical_mask                         : 4개 조합
지속 여부                            : 2개 경우
총 비교 횟수                         : 512 × 4 × 2 = 4096
```

---

## 2. 시뮬레이션 조건

```text
Simulation type : Behavioral Simulation
Testbench       : tb_fault_manager_core
Run method      : Run All
Simulation end  : 196540 ns
Clock           : 100 MHz
Clock period    : 10 ns
persist_limit   : 기본 3
critical_mask   : 기본 3'b100
```

Testbench는 Self-checking 방식으로 구성되어 있으며, 최종 결과는 다음과 같다.

```text
checks = 4146
errors = 0
ALL PASS
```

콘솔 종료 메시지:

```text
$finish called at time : 196540 ns
```

---

## 3. 제출용 캡처 적합성

현재 캡처 구성은 제출용으로 적절하다.

### 사용 권장 이미지

1. **파형 이미지**
   - `timeout`, `error_flag`, `critical_fault`
   - `critical_mask`, `persist_limit`
   - `fault_level`, `fault_device`, `fault_code`
   - `fault_valid`, `fault_change_event`
   - `fault_count0~2`
   - `errors`, `checks`, `event_cnt`

2. **최종 콘솔 이미지**
   - B12~B22 결과
   - 전수 검증 완료 메시지
   - `checks = 4146, errors = 0 -> ALL PASS`
   - `$finish called at time : 196540 ns`

### 제외 가능 이미지

상수 목록 화면(`LEVEL_0`, `F_TIMEOUT`, `DEV0` 등)은 제출에 필수는 아니다.  
이는 Testbench 내부 상수 정의 화면이므로, 실제 DUT 동작 증빙은 파형과 최종 콘솔 화면만으로 충분하다.

---

## 4. 검증 항목별 결과

## B01. 정상 입력 → Level 0

모든 Fault 입력이 0인 상태에서 다음을 확인하였다.

```text
fault_level  = 0
fault_device = 3
fault_code   = FAULT_NONE
fault_valid  = 1
```

즉, Enable 상태에서 정상 입력이면 Level 0 / Device 3 / Code 0이 출력됨을 확인하였다.

---

## B02. Device 0 Timeout 1회 → Level 1

`timeout[0]=1`을 입력하고 Persist 기준 미만 상태를 확인하였다.

```text
fault_level  = 1
fault_device = 0
fault_code   = FAULT_TIMEOUT
fault_count0 = 1 after 1 tick
```

단일 일반 Timeout은 일시 Fault로 Level 1로 판정됨을 확인하였다.

---

## B03. Device 0 Timeout 지속 → Level 2

Device 0 Timeout을 유지한 채 `eval_tick`을 누적하였다.

```text
count0 = 3
fault_level  = 2
fault_device = 0
fault_code   = FAULT_TIMEOUT
```

`persist_limit=3`에 도달하면 Level 2로 상승함을 확인하였다.

---

## B04. Device 1 Error → Level 1

`error_flag[1]=1`을 입력하였다.

```text
fault_level  = 1
fault_device = 1
fault_code   = FAULT_ERROR_CODE
```

단일 일반 Error는 Level 1과 `FAULT_ERROR_CODE`로 판정됨을 확인하였다.

---

## B05. Device 2 Timeout → Tick 대기 없이 Level 3

기본 `critical_mask=3'b100` 상태에서 `timeout[2]=1`을 입력하였다.

```text
fault_level  = 3
fault_device = 2
fault_code   = FAULT_CRITICAL
fault_count2 = 0
```

Device 2는 Critical Mask 대상이므로, Timeout도 Persist Count를 기다리지 않고 즉시 Level 3으로 판정됨을 확인하였다.

---

## B06. Device 2 Error → Tick 대기 없이 Level 3

`error_flag[2]=1`을 입력하였다.

```text
fault_level  = 3
fault_device = 2
fault_code   = FAULT_CRITICAL
```

Device 2의 Error 역시 Critical 조건으로 즉시 Level 3이 됨을 확인하였다.

---

## B07. Device 2 Critical Fault → Tick 대기 없이 Level 3

`critical_fault[2]=1`을 입력하였다.

```text
fault_level  = 3
fault_device = 2
fault_code   = FAULT_CRITICAL
fault_count2 = 0
```

Critical Fault가 Tick 대기 없이 즉시 반영됨을 확인하였다.

---

## B08. Device 0 + 1 동시 Fault → Multi-device Level 3

`timeout[0]=1`, `error_flag[1]=1`을 동시에 입력하였다.

```text
fault_level  = 3
fault_device = 3
fault_code   = FAULT_MULTI_DEVICE
```

Critical 조건이 없고 두 장치 이상 Fault가 존재하면 다중 장치 Fault로 Level 3이 됨을 확인하였다.

---

## B09. Critical 장치 + 일반 Fault → Critical 우선

Device 0 일반 Fault와 Device 2 Critical Fault를 동시에 입력하였다.

```text
fault_level  = 3
fault_device = 2
fault_code   = FAULT_CRITICAL
```

Critical 장치가 하나이면 해당 Device ID를 출력하고, 일반 Fault보다 Critical이 우선함을 확인하였다.

---

## B10. 동일 장치 Timeout + Error → Error Code 우선

같은 Device 0에 Timeout과 Error를 동시에 입력하였다.

```text
fault_level  = 1 또는 2
fault_device = 0
fault_code   = FAULT_ERROR_CODE
```

동일 장치 내 원인 우선순위는 `ERROR_CODE > TIMEOUT`임을 확인하였다.

---

## B11. Critical 장치 둘 이상 → `FAULT_CRITICAL`, Device 3

`critical_mask=3'b111`로 설정한 뒤 두 개 이상의 Critical 장치를 입력하였다.

```text
fault_level  = 3
fault_device = 3
fault_code   = FAULT_CRITICAL
```

Critical 조건 장치가 둘 이상이면 `MULTIPLE_OR_NONE(3)`을 출력함을 확인하였다.  
또한 하나의 Critical 장치만 남기면 해당 Device ID를 출력함도 확인하였다.

---

## B12. Level 1의 Device/Code가 현재 원인과 일치

Device 1 Error와 Device 1 Timeout을 각각 단독으로 입력하였다.

```text
dev1 error   -> level=1, dev=1, code=0x02
dev1 timeout -> level=1, dev=1, code=0x01
```

Level 1에서도 Device ID와 Fault Code가 현재 원인과 정확히 일치함을 확인하였다.

---

## B13. 오류 제거 → Count 0, Level 복귀

Persistent Fault 상태에서 Fault 입력을 제거하였다.

```text
fault cleared -> level 0
count0 cleared on tick -> 0
```

입력 제거 시 Level이 복귀하고 Count도 정상적으로 초기화됨을 확인하였다.

---

## B14. Count는 `eval_tick`에서만 증가

Timeout 입력 후 `eval_tick` 없이 50클럭을 기다린 뒤 Count를 확인하였다.

```text
no tick -> count0 = 0
no tick -> level 1 유지
after tick -> count0 = 1
```

Persist Count는 시스템 Clock마다 증가하지 않고 `eval_tick`에서만 증가함을 확인하였다.

---

## B15. Count Saturation

Timeout Fault를 장시간 유지하여 Count Saturation을 확인하였다.

```text
fault_count0 saturates at 255
```

Count가 8비트 최대값에서 포화되고 Overflow로 되돌아가지 않음을 확인하였다.

---

## B16. `persist_limit=0`은 1로 간주

`persist_limit=0`으로 설정한 뒤 단일 Timeout을 입력하였다.

```text
before tick -> level 1
after 1 tick -> level 2
```

따라서 `persist_limit=0`이 유효값 1로 처리됨을 확인하였다.

---

## B17 / B18. `fault_change_event` 생성 및 중복 방지

출력 상태 변화에 따른 Event를 검증하였다.

```text
level0 -> level1 변환 시 event 1회
같은 상태 유지 중 event 재발생 없음
count만 바뀌고 출력 동일 시 event 없음
level1 -> level2 변환 시 event 추가 1회
```

즉, `fault_change_event`는 출력이 변할 때만 1클럭 Pulse로 발생하고, 동일 상태 유지 중에는 중복 발생하지 않음을 확인하였다.

---

## B19. Fault가 남아 있으면 `RESET_FAULT` 무시

Level 2 Fault가 남아 있는 상태에서 `reset_fault_pulse`를 입력하였다.

```text
fault_count0 remains = 3
fault_level remains  = 2
```

활성 Fault가 존재할 때는 `RESET_FAULT`가 Count나 Fault Level을 임의로 낮추지 않음을 확인하였다.

---

## B20. Fault가 없을 때 `RESET_FAULT`로 Count Clear

Fault 입력이 모두 제거된 상태에서 `reset_fault_pulse`를 입력하였다.

```text
before reset_fault -> count kept = 3
after reset_fault  -> count0 = 0
fault_level        -> 0
fault_device       -> 3
fault_code         -> 0
```

현재 Fault가 없을 때만 Count와 과거 상태 정보가 Clear됨을 확인하였다.

---

## B21. `enable=0` 안전 출력

Level 2 Fault 상태에서 `enable=0`으로 전환하였다.

```text
fault_level  = 0
fault_device = 3
fault_code   = 0
fault_valid  = 0
fault_count0 = 0
no event while disabled
count stays 0 while disabled
re-enable -> level1 (count restart)
```

Disable 상태에서는 안전 출력이 강제되고 새로운 Event가 발생하지 않으며, 재활성화 후 Count가 0부터 다시 시작함을 확인하였다.

---

## B22. 전수 검증

다음 조합 전체에 대해 DUT 출력과 Reference Function 출력을 대조하였다.

```text
timeout         : 0~7
error_flag      : 0~7
critical_fault  : 0~7
critical_mask   : {100, 111, 000, 010}
지속 여부       : 비지속 / 지속
총 검증 횟수    : 4096
```

콘솔 결과:

```text
전수 검증 완료 (누적 checks=4146, errors=0)
```

모든 조합에서 DUT의 `{fault_level, fault_device, fault_code}`가 Reference Model과 일치함을 확인하였다.

---

## 5. 파형에서 확인되는 주요 특징

파형에서는 다음 동작을 확인할 수 있다.

```text
- 일반 Fault에서 Level 1 → Level 2 전이
- Device 2 Fault에서 즉시 Level 3 전이
- critical_mask 변경에 따른 판정 변화
- fault_change_event Pulse 발생
- fault_count0~2의 증가 및 포화
- enable=0 시 안전 출력
- checks / errors 누적
- event_cnt 누적
```

특히 현재 파형의 최종 상태는 다음과 같이 해석할 수 있다.

```text
errors  = 0
checks  = 4146
event_cnt = 4090 (0x0FFA)
```

이는 다수의 상태 변화 및 전수 조합 검증이 모두 수행되었고, 실패 없이 종료되었음을 의미한다.

---

## 6. 최종 결과표

| 검증 항목 | 결과 |
|---|---|
| 정상 입력 Level 0 | 통과 |
| 단일 Timeout Level 1 | 통과 |
| Persist Count 기반 Level 2 | 통과 |
| 단일 Error Level 1 | 통과 |
| Device 2 Timeout 즉시 Level 3 | 통과 |
| Device 2 Error 즉시 Level 3 | 통과 |
| Device 2 Critical 즉시 Level 3 | 통과 |
| 다중 장치 Fault Level 3 | 통과 |
| Critical 우선 정책 | 통과 |
| 동일 장치 Timeout+Error → Error Code | 통과 |
| 복수 Critical 장치 처리 | 통과 |
| Level 1 Device/Code 일치 | 통과 |
| Fault 제거 시 Level 복귀 | 통과 |
| Count의 `eval_tick` 전용 증가 | 통과 |
| Count Saturation | 통과 |
| `persist_limit=0 -> 1` 처리 | 통과 |
| `fault_change_event` 생성 | 통과 |
| 동일 상태 중복 Event 없음 | 통과 |
| 활성 Fault 중 `RESET_FAULT` 무시 | 통과 |
| Fault 없음 상태의 `RESET_FAULT` Clear | 통과 |
| `enable=0` 안전 출력 | 통과 |
| 전수 조합 Reference 비교 | 통과 |
| 전체 Self-checking 결과 | `checks=4146`, `errors=0`, `ALL PASS` |

---

## 7. 명세 적합성 결론

이번 시뮬레이션으로 `fault_manager_core`가 다음 정책을 만족함을 확인하였다.

```text
Critical > Multi-device > Persistent > Temporary > Normal
```

또한 아래 핵심 요구사항이 충족되었다.

- `critical_mask`는 Timeout / Error / Critical Fault 모두에 적용
- Critical 및 Multi-device Fault는 `eval_tick`을 기다리지 않고 즉시 판정
- 일반 단일 Fault의 Persist Count는 `eval_tick`에서만 증가
- Fault 제거 시 상태 복귀
- `fault_change_event`는 출력 변화 시에만 발생
- `RESET_FAULT`는 활성 Fault가 없을 때만 Count/Clear 수행
- `enable=0`에서는 `fault_valid=0` 및 안전 출력 유지

최종 결과:

```text
checks = 4146
errors = 0
ALL PASS
```

따라서 `fault_manager_core`는 00~04 명세에서 요구하는 Core 동작, 우선순위 정책, Count, Event, Reset 및 Disable 정책을 만족한다.
