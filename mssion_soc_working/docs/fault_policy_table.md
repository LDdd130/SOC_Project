# fault_manager_ip — Fault Policy Table

> 산출물 문서 (02_MEMBER_B 9장). 입력 조합별 기대 출력표.
> 이 표는 `docs/gen_policy.py` 기준 모델에서 생성했고, 같은 규칙을
> `tb_fault_manager_core.v` 의 Reference function 과 전수 검증(B22)이 사용한다.

## 우선순위 요약 (00 공통명세 10장 / 02 문서 3장)

| 순위 | 조건 | level | code | device |
|---:|---|---|---|---|
| P1 | `critical_condition = ((timeout\|error_flag\|critical_fault) & CRITICAL_MASK) != 0` | 3 | `FAULT_CRITICAL` | 해당 장치 1개면 그 ID, 2개 이상이면 `MULTIPLE_OR_NONE` |
| P2 | Critical 조건 없음 + `device_fault` 비트 2개 이상 | 3 | `FAULT_MULTI_DEVICE` | `MULTIPLE_OR_NONE` |
| P3 | Mask 밖 단일 장치 오류가 `PERSIST_LIMIT` 이상 지속 | 2 | `FAULT_TIMEOUT` 또는 `FAULT_ERROR_CODE` | 해당 장치 |
| P4 | Mask 밖 단일 장치 오류, 지속 기준 미만 | 1 | `FAULT_TIMEOUT` 또는 `FAULT_ERROR_CODE` | 해당 장치 |
| P5 | 오류 없음 | 0 | `FAULT_NONE` | `MULTIPLE_OR_NONE` |

보조 규칙

- `device_fault[i] = timeout[i] | error_flag[i] | critical_fault[i]`
- **`CRITICAL_MASK` 는 `critical_fault` 전용 Mask 가 아니다.** Mask 된 장치의
  Timeout / Error / Critical Fault 는 모두 지속 횟수를 기다리지 않고 Level 3 이 된다
  (00 문서 10장, 02 문서 3장, 04 체크리스트 1장).
- 단일 장치의 code 는 `error_flag` 또는 Mask 밖 `critical_fault` 가 `timeout` 보다 우선한다.
  같은 장치에 Timeout 과 Error 가 동시에 있으면 `FAULT_ERROR_CODE` 다 (00 문서 10장).
- `CRITICAL_MASK` 에서 빠진 `critical_fault` 비트는 일반 오류로 취급되어 P2~P4 로 내려간다.
- `PERSIST_LIMIT == 0` 은 1 로 간주한다.
- 지속 Count 는 공통 `eval_tick` 인 클럭에만 갱신하고 `0xFF` 에서 Saturation 한다.
- `persist_count` 가 `무관` 인 행은 지속 여부와 무관하게 결과가 같다는 뜻이다
  (P1/P2 가 먼저 걸리거나, 오류가 없는 경우).
- `enable=0` 이면 위 표와 무관하게 `level=0`, `device=MULTIPLE_OR_NONE`, `code=FAULT_NONE`,
  `fault_count=0`, `fault_valid=0` 이다 (02 문서 6.2).

---

### 표 A — critical_fault = 0 (일반 오류만), CRITICAL_MASK = 3'b100

`timeout` / `error_flag` 8x8 = 64 조합 전체.
Device 2 는 Mask 대상이므로 `timeout[2]` 나 `error_flag[2]` 만으로도 Level 3 이다.

| timeout | error_flag | critical_fault | persist_count | level | device | code |
|---|---|---|---|---|---|---|
| `000` | `000` | `000` | 무관 | 0 NORMAL | MULTIPLE_OR_NONE | FAULT_NONE |
| `000` | `001` | `000` | < limit | 1 WARNING | DEVICE_0 | FAULT_ERROR_CODE |
| `000` | `001` | `000` | >= limit | 2 DEGRADED | DEVICE_0 | FAULT_ERROR_CODE |
| `000` | `010` | `000` | < limit | 1 WARNING | DEVICE_1 | FAULT_ERROR_CODE |
| `000` | `010` | `000` | >= limit | 2 DEGRADED | DEVICE_1 | FAULT_ERROR_CODE |
| `000` | `011` | `000` | 무관 | 3 SAFE | MULTIPLE_OR_NONE | FAULT_MULTI_DEVICE |
| `000` | `100` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `000` | `101` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `000` | `110` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `000` | `111` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `001` | `000` | `000` | < limit | 1 WARNING | DEVICE_0 | FAULT_TIMEOUT |
| `001` | `000` | `000` | >= limit | 2 DEGRADED | DEVICE_0 | FAULT_TIMEOUT |
| `001` | `001` | `000` | < limit | 1 WARNING | DEVICE_0 | FAULT_ERROR_CODE |
| `001` | `001` | `000` | >= limit | 2 DEGRADED | DEVICE_0 | FAULT_ERROR_CODE |
| `001` | `010` | `000` | 무관 | 3 SAFE | MULTIPLE_OR_NONE | FAULT_MULTI_DEVICE |
| `001` | `011` | `000` | 무관 | 3 SAFE | MULTIPLE_OR_NONE | FAULT_MULTI_DEVICE |
| `001` | `100` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `001` | `101` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `001` | `110` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `001` | `111` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `010` | `000` | `000` | < limit | 1 WARNING | DEVICE_1 | FAULT_TIMEOUT |
| `010` | `000` | `000` | >= limit | 2 DEGRADED | DEVICE_1 | FAULT_TIMEOUT |
| `010` | `001` | `000` | 무관 | 3 SAFE | MULTIPLE_OR_NONE | FAULT_MULTI_DEVICE |
| `010` | `010` | `000` | < limit | 1 WARNING | DEVICE_1 | FAULT_ERROR_CODE |
| `010` | `010` | `000` | >= limit | 2 DEGRADED | DEVICE_1 | FAULT_ERROR_CODE |
| `010` | `011` | `000` | 무관 | 3 SAFE | MULTIPLE_OR_NONE | FAULT_MULTI_DEVICE |
| `010` | `100` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `010` | `101` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `010` | `110` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `010` | `111` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `011` | `000` | `000` | 무관 | 3 SAFE | MULTIPLE_OR_NONE | FAULT_MULTI_DEVICE |
| `011` | `001` | `000` | 무관 | 3 SAFE | MULTIPLE_OR_NONE | FAULT_MULTI_DEVICE |
| `011` | `010` | `000` | 무관 | 3 SAFE | MULTIPLE_OR_NONE | FAULT_MULTI_DEVICE |
| `011` | `011` | `000` | 무관 | 3 SAFE | MULTIPLE_OR_NONE | FAULT_MULTI_DEVICE |
| `011` | `100` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `011` | `101` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `011` | `110` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `011` | `111` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `100` | `000` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `100` | `001` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `100` | `010` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `100` | `011` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `100` | `100` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `100` | `101` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `100` | `110` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `100` | `111` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `101` | `000` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `101` | `001` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `101` | `010` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `101` | `011` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `101` | `100` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `101` | `101` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `101` | `110` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `101` | `111` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `110` | `000` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `110` | `001` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `110` | `010` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `110` | `011` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `110` | `100` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `110` | `101` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `110` | `110` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `110` | `111` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `111` | `000` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `111` | `001` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `111` | `010` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `111` | `011` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `111` | `100` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `111` | `101` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `111` | `110` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `111` | `111` | `000` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |

### 표 B — critical_fault 포함, CRITICAL_MASK = 3'b100 (Device 2 만 Critical)

| timeout | error_flag | critical_fault | persist_count | level | device | code |
|---|---|---|---|---|---|---|
| `000` | `000` | `000` | 무관 | 0 NORMAL | MULTIPLE_OR_NONE | FAULT_NONE |
| `001` | `000` | `000` | < limit | 1 WARNING | DEVICE_0 | FAULT_TIMEOUT |
| `001` | `000` | `000` | >= limit | 2 DEGRADED | DEVICE_0 | FAULT_TIMEOUT |
| `000` | `010` | `000` | < limit | 1 WARNING | DEVICE_1 | FAULT_ERROR_CODE |
| `000` | `010` | `000` | >= limit | 2 DEGRADED | DEVICE_1 | FAULT_ERROR_CODE |
| `011` | `000` | `000` | 무관 | 3 SAFE | MULTIPLE_OR_NONE | FAULT_MULTI_DEVICE |
| `000` | `000` | `001` | < limit | 1 WARNING | DEVICE_0 | FAULT_ERROR_CODE |
| `000` | `000` | `001` | >= limit | 2 DEGRADED | DEVICE_0 | FAULT_ERROR_CODE |
| `001` | `000` | `001` | < limit | 1 WARNING | DEVICE_0 | FAULT_ERROR_CODE |
| `001` | `000` | `001` | >= limit | 2 DEGRADED | DEVICE_0 | FAULT_ERROR_CODE |
| `000` | `010` | `001` | 무관 | 3 SAFE | MULTIPLE_OR_NONE | FAULT_MULTI_DEVICE |
| `011` | `000` | `001` | 무관 | 3 SAFE | MULTIPLE_OR_NONE | FAULT_MULTI_DEVICE |
| `000` | `000` | `010` | < limit | 1 WARNING | DEVICE_1 | FAULT_ERROR_CODE |
| `000` | `000` | `010` | >= limit | 2 DEGRADED | DEVICE_1 | FAULT_ERROR_CODE |
| `001` | `000` | `010` | 무관 | 3 SAFE | MULTIPLE_OR_NONE | FAULT_MULTI_DEVICE |
| `000` | `010` | `010` | < limit | 1 WARNING | DEVICE_1 | FAULT_ERROR_CODE |
| `000` | `010` | `010` | >= limit | 2 DEGRADED | DEVICE_1 | FAULT_ERROR_CODE |
| `011` | `000` | `010` | 무관 | 3 SAFE | MULTIPLE_OR_NONE | FAULT_MULTI_DEVICE |
| `000` | `000` | `011` | 무관 | 3 SAFE | MULTIPLE_OR_NONE | FAULT_MULTI_DEVICE |
| `001` | `000` | `011` | 무관 | 3 SAFE | MULTIPLE_OR_NONE | FAULT_MULTI_DEVICE |
| `000` | `010` | `011` | 무관 | 3 SAFE | MULTIPLE_OR_NONE | FAULT_MULTI_DEVICE |
| `011` | `000` | `011` | 무관 | 3 SAFE | MULTIPLE_OR_NONE | FAULT_MULTI_DEVICE |
| `000` | `000` | `100` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `001` | `000` | `100` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `000` | `010` | `100` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `011` | `000` | `100` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `000` | `000` | `101` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `001` | `000` | `101` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `000` | `010` | `101` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `011` | `000` | `101` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `000` | `000` | `110` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `001` | `000` | `110` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `000` | `010` | `110` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `011` | `000` | `110` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `000` | `000` | `111` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `001` | `000` | `111` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `000` | `010` | `111` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `011` | `000` | `111` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |

### 표 C — CRITICAL_MASK = 3'b111 (세 장치 모두 Critical 로 지정한 경우)

Mask 가 전부이므로 오류가 하나라도 있으면 항상 Level 3 / `FAULT_CRITICAL` 이다.

| timeout | error_flag | critical_fault | persist_count | level | device | code |
|---|---|---|---|---|---|---|
| `000` | `000` | `000` | 무관 | 0 NORMAL | MULTIPLE_OR_NONE | FAULT_NONE |
| `001` | `000` | `000` | 무관 | 3 SAFE | DEVICE_0 | FAULT_CRITICAL |
| `000` | `010` | `000` | 무관 | 3 SAFE | DEVICE_1 | FAULT_CRITICAL |
| `000` | `000` | `100` | 무관 | 3 SAFE | DEVICE_2 | FAULT_CRITICAL |
| `011` | `000` | `000` | 무관 | 3 SAFE | MULTIPLE_OR_NONE | FAULT_CRITICAL |
| `000` | `000` | `011` | 무관 | 3 SAFE | MULTIPLE_OR_NONE | FAULT_CRITICAL |
| `001` | `010` | `100` | 무관 | 3 SAFE | MULTIPLE_OR_NONE | FAULT_CRITICAL |
| `111` | `000` | `000` | 무관 | 3 SAFE | MULTIPLE_OR_NONE | FAULT_CRITICAL |

### 표 D — CRITICAL_MASK = 3'b000 (Critical 지정 없음)

`critical_fault` 입력도 일반 오류로만 취급된다.

| timeout | error_flag | critical_fault | persist_count | level | device | code |
|---|---|---|---|---|---|---|
| `000` | `000` | `000` | 무관 | 0 NORMAL | MULTIPLE_OR_NONE | FAULT_NONE |
| `001` | `000` | `000` | < limit | 1 WARNING | DEVICE_0 | FAULT_TIMEOUT |
| `001` | `000` | `000` | >= limit | 2 DEGRADED | DEVICE_0 | FAULT_TIMEOUT |
| `000` | `001` | `000` | < limit | 1 WARNING | DEVICE_0 | FAULT_ERROR_CODE |
| `000` | `001` | `000` | >= limit | 2 DEGRADED | DEVICE_0 | FAULT_ERROR_CODE |
| `000` | `000` | `001` | < limit | 1 WARNING | DEVICE_0 | FAULT_ERROR_CODE |
| `000` | `000` | `001` | >= limit | 2 DEGRADED | DEVICE_0 | FAULT_ERROR_CODE |
| `001` | `001` | `000` | < limit | 1 WARNING | DEVICE_0 | FAULT_ERROR_CODE |
| `001` | `001` | `000` | >= limit | 2 DEGRADED | DEVICE_0 | FAULT_ERROR_CODE |
| `001` | `000` | `001` | < limit | 1 WARNING | DEVICE_0 | FAULT_ERROR_CODE |
| `001` | `000` | `001` | >= limit | 2 DEGRADED | DEVICE_0 | FAULT_ERROR_CODE |
| `000` | `000` | `100` | < limit | 1 WARNING | DEVICE_2 | FAULT_ERROR_CODE |
| `000` | `000` | `100` | >= limit | 2 DEGRADED | DEVICE_2 | FAULT_ERROR_CODE |
| `001` | `000` | `010` | 무관 | 3 SAFE | MULTIPLE_OR_NONE | FAULT_MULTI_DEVICE |
| `000` | `000` | `111` | 무관 | 3 SAFE | MULTIPLE_OR_NONE | FAULT_MULTI_DEVICE |
