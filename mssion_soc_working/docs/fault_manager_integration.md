# fault_manager_ip — Integration Note (팀원 B)

> 산출물 문서 (02_MEMBER_B 9장). A·C 와 Block Design 을 합칠 때 이 문서만 보면 된다.
> 기준 문서 : `00_TEAM_COMMON_SPEC_3MEMBERS_RECOVERY_FIXED.md`,
> `02_MEMBER_B_FAULT_MANAGER.md`, `04_TEAM_SHARED_INTEGRATION_CHECKLIST_RECOVERY_FIXED.md`

## 1. 파일 구성

| 파일 | 역할 |
|---|---|
| `rtl/fault_manager_core.v` | 순수 로직. 우선순위 판정, 지속 Count, 변화 Event |
| `rtl/fault_manager_axi.v` | AXI4-Lite 레지스터 + core 인스턴스 |
| `rtl/fault_manager_ip_v1_0_S00_AXI.v` | Vivado 마법사 파일 대체 (연결만) |
| `rtl/fault_manager_ip_v1_0.v` | IP 최상위 (Block Design 에 보이는 포트) |
| `sim/tb_fault_manager_core.v` | Core Self-checking TB (02 문서 8장 21항목 + 전수 검증) |
| `sim/tb_fault_manager_axi.v` | AXI R/W · W1P · W1C · IRQ Level · Disable TB |
| `sw/fault_manager_ip.h`, `.c` | 드라이버 + Level/Device/Code 해석 함수 |
| `docs/fault_policy_table.md` | 입력 조합별 기대 출력표 |

계층:

```text
fault_manager_ip_v1_0
  └─ fault_manager_ip_v1_0_S00_AXI
       └─ fault_manager_axi
            └─ fault_manager_core
```

**공동 통합 RTL (B 전용 파일 아님)** — 04 체크리스트 2장 항목이라 함께 올려둔다.

| 파일 | 역할 |
|---|---|
| `rtl/eval_tick_generator.v` | 공통 1클럭 Pulse `eval_tick` 생성 (00 문서 5.2) |
| `sim/tb_eval_tick_generator.v` | 위 모듈 검증 |

## 2. IP 패키징 절차

1. Tools → Create and Package New IP → **Create a new AXI4 peripheral**
   - Name `fault_manager_ip`, Version `1.0`
   - Interface `S00_AXI`, **Lite / Slave / Data Width 32 / Number of Registers 16**
   - 마지막에 **Edit IP** 선택
2. 열린 편집 창에서
   - 마법사가 만든 `fault_manager_ip_v1_0.v` 와 `fault_manager_ip_v1_0_S00_AXI.v` 내용을
     `rtl/` 의 같은 이름 파일 내용으로 **통째로 교체**
   - Add Sources 로 `fault_manager_axi.v`, `fault_manager_core.v` 추가
3. Package IP 탭 → `File Groups` Merge → `Customization Parameters` Merge →
   **`Ports and Interfaces` Merge** (여기서 사용자 포트가 잡힌다) → `Review and Package` → Re-Package IP

`irq` 는 일반 1비트 출력 포트다. Block Design 에서 `xlconcat` 입력에 직접 연결한다.

`eval_tick_generator.v` 는 IP 로 패키징하지 않는다. Block Design 에 **Module Reference**
로 추가한다 (00 문서 5.2 — 네 번째 Custom IP 로 계산하지 않는다).

## 3. Block Design 연결표

| IP 포트 | 방향 | 연결 대상 |
|---|---|---|
| `timeout[2:0]` | in | `heartbeat_monitor_ip` 의 `timeout[2:0]` (00 문서 8.2) |
| `error_flag[2:0]` | in | AXI GPIO 또는 보드 스위치 (Fault Injection, 00 문서 8.3) |
| `critical_fault[2:0]` | in | AXI GPIO 또는 보드 스위치. **Device 2 가 기본 Critical 시연 입력** |
| `eval_tick` | in | **공통 `eval_tick_generator.v` 의 `eval_tick`** (00 문서 5.2) |
| `fault_level[1:0]` | out | `safety_controller_ip` 의 `fault_level` |
| `fault_device[1:0]` | out | `safety_controller_ip` 의 `fault_device` |
| `fault_code[7:0]` | out | `safety_controller_ip` (필요 시) |
| `fault_valid` | out | `safety_controller_ip` 의 `fault_valid` |
| `irq` | out | `xlconcat` → `AXI INTC` |
| `S00_AXI` | — | MicroBlaze Peripheral AXI (Connection Automation) |

```text
공통 eval_tick
├─ fault_manager_ip.eval_tick
└─ safety_controller_ip.eval_tick
```

- `eval_tick` 은 **Fault Manager 가 만들지 않는다.** B·C 가 같은 소스, 같은 포트명을 쓴다
  (00 문서 5.2, 04 체크리스트 1장).
- 금지 연결 : `heartbeat_monitor_ip.alive` → `fault_manager_ip` (00 문서 2장).
  Fault Manager 입력은 `timeout` 뿐이다.

### AXI INTC 설정

IRQ 는 Level 방식이므로 (00 문서 5.4) INTC 를 Level-High 로 둔다. Tcl Console:

```tcl
set_property CONFIG.C_KIND_OF_INTR {0x00000000} [get_bd_cells <intc_이름>]
set_property CONFIG.C_KIND_OF_LVL  {0xFFFFFFFF} [get_bd_cells <intc_이름>]
```

## 4. 레지스터 맵

00 문서 9.2 / 02 문서 6장의 Offset 을 **그대로** 구현했다.

| Offset | 이름 | 접근 | 리셋값 | 비고 |
|---:|---|---|---:|---|
| `0x00` | `CTRL` | RW/W1P | `0x0` | bit0 ENABLE, bit1 RESET_FAULT(W1P) |
| `0x04` | `FAULT_INPUT` | R | — | `[2:0]` timeout, `[10:8]` error_flag, `[18:16]` critical_fault |
| `0x08` | `CRITICAL_MASK` | RW | `0x4` | Device 2 가 Critical |
| `0x0C` | `PERSIST_LIMIT` | RW | `5` | Tick 기준 지속 횟수. 0 은 1 로 간주 |
| `0x10` | `FAULT_LEVEL` | R | `0` | `[1:0]` |
| `0x14` | `FAULT_DEVICE` | R | `3` | `[1:0]` |
| `0x18` | `FAULT_CODE` | R | `0x00` | `[7:0]` |
| `0x1C` | `FAULT_COUNT` | R | `0` | `[7:0]` cnt0, `[15:8]` cnt1, `[23:16]` cnt2 |
| `0x20` | `IRQ_EN` | RW | `0` | bit0 Fault Change |
| `0x24` | `IRQ_STATUS` | R/W1C | `0` | bit0 Fault Change Pending |
| `0x2C` | `ID` | R | `0x464D4752` | **추가분** — "FMGR", AXI 매핑 확인용 |

Read-only 레지스터에 대한 Write 는 무시한다 (00 문서 5.4).

### [CHANGE REQUEST] — 팀 승인 필요

```text
요청자      : 팀원 B
변경 항목   : fault_manager_ip 레지스터 1개 추가 (0x2C ID)
기존        : 0x00~0x24 만 정의
변경안      : 기존 Offset 은 전부 그대로 두고 0x2C 를 뒤에 추가
변경 이유   : 보드 브링업 시 "AXI 주소 매핑 문제인지 RTL 문제인지" 를
              즉시 구분하기 위한 읽기 전용 ID
영향 IP     : 없음 (IP 간 신호 인터페이스 무변경)
Vitis 영향  : mission_ip_regs.h 에 매크로 1개 추가
Testbench 영향 : tb_fault_manager_axi.v A01/A03 (이미 반영)
팀 승인     : [ ] A   [ ] C
```

승인 전까지 A·C 는 이 레지스터를 몰라도 동작에 영향이 없다.
승인이 나지 않으면 `R_ID` 항목만 지우면 되고 다른 코드는 손대지 않는다.

## 5. Fault 정책 요약 (00 문서 10장)

```verilog
device_fault       = timeout | error_flag | critical_fault;
critical_condition = |(device_fault & critical_mask);
```

| 순위 | 조건 | level | code | device |
|---:|---|---|---|---|
| P1 | `critical_condition != 0` | 3 | `FAULT_CRITICAL` | 해당 장치 1개면 그 ID, 2개 이상이면 `MULTIPLE_OR_NONE` |
| P2 | Critical 없음 + `device_fault` 2비트 이상 | 3 | `FAULT_MULTI_DEVICE` | `MULTIPLE_OR_NONE` |
| P3 | Mask 밖 단일 장치가 `PERSIST_LIMIT` 이상 지속 | 2 | `TIMEOUT`/`ERROR_CODE` | 해당 장치 |
| P4 | Mask 밖 단일 장치, 지속 미만 | 1 | `TIMEOUT`/`ERROR_CODE` | 해당 장치 |
| P5 | 오류 없음 | 0 | `FAULT_NONE` | `MULTIPLE_OR_NONE` |

**통합 시 오해하기 쉬운 3가지**

1. `CRITICAL_MASK` 는 `critical_fault` 전용 Mask 가 **아니다.** 기본값 `3'b100` 에서
   Device 2 의 **Timeout 이나 Error 만으로도** 지속 횟수 없이 Level 3 이다
   (00 문서 10장 마지막 문단, 04 체크리스트 1장 / Test 16·17·18).
2. 같은 단일 장치에 Timeout 과 Error 가 동시에 있으면 `FAULT_ERROR_CODE` 다
   (Timeout 이 아니다. 04 체크리스트 Test 20).
3. 지속 Count 는 공통 `eval_tick` 에서만 증가한다. Critical 조건과 다중 장치 Fault 는
   `eval_tick` 과 무관하게 매 100MHz 클럭에서 판정한다 (00 문서 5.2 / 10장).

Critical 입력부터 출력 차단까지의 목표 지연 (02 문서 4장):

```text
외부 입력 동기화 지연 + Fault Manager 최대 1 Clock + Safety Controller 최대 1 Clock
```

## 6. RESET_FAULT 와 Disable 동작

`RESET_FAULT` (02 문서 6.1):

```text
현재 device_fault 가 하나라도 있음 -> 명령 자체를 무시
현재 device_fault 가 모두 없음     -> Count, 과거 비교 정보, IRQ Pending Clear
```

활성 Fault 가 남아 있는데 Count 만 지워 Level 2 를 Level 1 로 낮추는 동작은 금지다.
그래서 Fault 가 살아 있는 동안 `RESET_FAULT` 를 눌러도 Level 과 Count 가 그대로다.

`ENABLE=0` 안전 출력 (00 문서 12.1 / 02 문서 6.2):

```text
fault_valid=0, fault_level=0, fault_device=MULTIPLE_OR_NONE,
fault_code=FAULT_NONE, fault_count0~2=0, fault_change_event=0
```

Disable 중에는 새로운 IRQ Pending 을 Set 하지 않는다.

## 7. 초기화 순서 (Vitis)

**`ENABLE` 리셋값은 0 이다.** MicroBlaze 가 켜기 전에는 출력이 안전값이고
`fault_valid` 도 0 이다 (00 문서 12장 "각 IP Enable" 은 MicroBlaze 담당).
"보드에 올렸는데 Level 이 안 변한다" 의 1순위 원인이므로 순서를 지킨다.

```c
#include "fault_manager_ip.h"

#define FM_BASE  XPAR_FAULT_MANAGER_IP_0_S00_AXI_BASEADDR

if (FM_SelfCheck(FM_BASE) != 0) { /* AXI 매핑/주소 문제 */ }

/* Device 2 만 Critical, 지속 판정 5 Tick (00 문서 10장 권장 초기값) */
FM_Init(FM_BASE, 0x4u, 5u);
FM_EnableIrq(FM_BASE, 1);
FM_Enable(FM_BASE, 1);          /* 반드시 마지막 */
```

`eval_tick` 주기는 이 IP 가 정하지 않는다. 공통 `eval_tick_generator.v` 의 `DIVISOR`
가 정한다 (기본 100,000 = 1ms @100MHz). 04 체크리스트 6장의 MicroBlaze 부팅 순서에서
Fault Manager 는 5번(`PERSIST_LIMIT`)·10번(Enable) 단계를 담당한다.

ISR 은 짧게 (00 문서 12장):

```c
void fm_isr(void *arg) {
    u32 st = FM_ReadIrqStatus(FM_BASE);
    g_fm_pending = st;           /* 전역 플래그만 */
    FM_ClearIrq(FM_BASE, st);    /* W1C */
    g_fm_flag = 1;
}
```

메인 루프에서 `FM_ReadStatus()` + `FM_LevelStr()/FM_CodeStr()/FM_DeviceStr()` 로 출력한다.
ISR 안에서 문자열 출력 금지.

## 8. 검증 상태

| TB | 항목 | 상태 |
|---|---|---|
| `tb_fault_manager_core.v` | 02 문서 8장 필수 21항목 + 전수 검증(B22) | **재실행 필요** |
| `tb_fault_manager_axi.v` | 레지스터 R/W, Read-only Write 무시, W1P 폭, W1C, IRQ Level, RESET_FAULT, Disable | **재실행 필요** |
| `tb_eval_tick_generator.v` | Reset 중 0, DIVISOR 뒤 첫 Pulse, 폭 1클럭, 주기 | **재실행 필요** |

> Fault 정책 수정(`critical_condition` 정의, ERROR_CODE 우선순위, `RESET_FAULT` 무시 조건,
> Disable 출력) 반영으로 TB 를 갱신했다. **xsim 또는 Icarus 로 다시 돌려 결과를 여기에
> 기록해야 한다.** 이전 버전의 "2076 checks / 0 errors" 는 옛 정책 기준이라 무효다.

전수 검증(B22)은 `timeout`·`error_flag`·`critical_fault` 512 조합 ×
`CRITICAL_MASK` 4종(`100`/`111`/`000`/`010`) × 지속 성립/미성립 2종을
Reference function 과 대조한다. `docs/fault_policy_table.md` 는 같은 규칙에서
생성했으므로 표와 RTL 이 일치한다.

실행 명령 (Icarus):

```bash
iverilog -g2005 -o /tmp/fm_core rtl/fault_manager_core.v sim/tb_fault_manager_core.v && vvp /tmp/fm_core
iverilog -g2005 -o /tmp/fm_axi  rtl/fault_manager_core.v rtl/fault_manager_axi.v sim/tb_fault_manager_axi.v && vvp /tmp/fm_axi
iverilog -g2005 -o /tmp/fm_tick rtl/eval_tick_generator.v sim/tb_eval_tick_generator.v && vvp /tmp/fm_tick
```

확인해야 할 주요 동작:

- Device 2 의 **Timeout / Error / Critical 전부** Tick 없이 1클럭 안에 Level 3
- Critical 조건이 다중 장치 오류보다 우선, Critical 장치 2개 이상이면 Device 3
- 같은 장치 Timeout+Error → `FAULT_ERROR_CODE`
- `CRITICAL_MASK` 밖의 `critical_fault` 는 일반 오류(`FAULT_ERROR_CODE`)로 취급
- 활성 Fault 가 있으면 `RESET_FAULT` 무시, 없을 때만 Count/Pending Clear
- `ENABLE=0` 에서 안전 출력, 새 Pending 없음
- 출력이 그대로면 변화 Event 를 반복 발생시키지 않음
- `IRQ` 는 W1C 전까지 High 유지 (Pulse 아님)

## 9. 발표용 Fault Injection 순서 (02 문서 0장, B 담당)

| 순서 | 조작 | `fault_level` | `fault_code` | 기대 시스템 상태 |
|---:|---|---:|---|---|
| 1 | 전원 ON, 모든 Heartbeat 정상 | 0 | `FAULT_NONE` | `NORMAL` |
| 2 | Device 0 Heartbeat 중단 (Timeout 직후) | 1 | `FAULT_TIMEOUT` | `WARNING` |
| 3 | 그대로 유지 (`eval_tick` × `PERSIST_LIMIT`) | 2 | `FAULT_TIMEOUT` | `DEGRADED`, Device 0 만 Disable |
| 4 | Device 0 Heartbeat 복구 | 0 | `FAULT_NONE` | Recovery Count 후 `NORMAL` |
| 5 | Device 1 Error 스위치 ON | 1 | `FAULT_ERROR_CODE` | `WARNING` |
| 6 | Device 0 Timeout 을 추가로 발생 | 3 | `FAULT_MULTI_DEVICE` | `SAFE_MODE` |
| 7 | 둘 다 해제 | 0 | `FAULT_NONE` | `SAFE_MODE` 유지 (자동 복귀 금지) |
| 8 | Manual Reset (`fault_valid=1`, Level 0) | 0 | `FAULT_NONE` | `NORMAL` |
| 9 | Device 2 Critical 스위치 ON | 3 | `FAULT_CRITICAL` | 확정 Clock 안에 `SAFE_MODE`, actuator off |
| 10 | Critical 해제 | 0 | `FAULT_NONE` | `SAFE_MODE` 유지 |
| 11 | Manual Reset | 0 | `FAULT_NONE` | `NORMAL` |

`DEGRADED → WARNING → NORMAL` 복귀를 보여주려면 04 문서 4장대로 Level 2 원인을 제거한 뒤
별도의 일시적 Level 1 Fault 를 유지해야 한다. Device 0 Timeout 하나만 제거하면
Level 2 → Level 0 이므로 `DEGRADED → NORMAL` 직접 복귀가 정상이다.

3번에서 `DEGRADED` 까지 걸리는 시간은 `eval_tick 주기 × PERSIST_LIMIT` 이다.
기본값(1 ms × 5)이면 5 ms 라 시연에서 눈에 안 보인다.
**시연용으로는 공통 `eval_tick_generator` 의 `DIVISOR` 를 키우거나 `PERSIST_LIMIT` 를
올려 1~2초로 늘린다.** 단 04 체크리스트 1장의 `RECOVERY_COUNT < PERSIST_LIMIT` 조건을
깨지 않도록 C 와 값을 같이 정한다.

## 10. 미확정 사항

- `error_flag` / `critical_fault` 를 무엇으로 주입할지 (보드 스위치 직결 vs AXI GPIO 경유)
  — C 의 Board I/O 초안과 함께 확정
- 시연용 `eval_tick` 주기와 `PERSIST_LIMIT` / `RECOVERY_COUNT` 최종값 — 통합 후 실측해서 확정
- `0x2C ID` 레지스터 CHANGE REQUEST 승인 여부 (A·C)
- `FAULT_RECOVERY_REQUIRED (0x05)` 는 현재 정책에서 사용처가 없다. 필요하면 공통 명세부터 정의
- `eval_tick_generator.v` / `tb_eval_tick_generator.v` 는 공동 산출물이라 B 가 초안만 올렸다.
  A·C 검토 후 확정한다.
