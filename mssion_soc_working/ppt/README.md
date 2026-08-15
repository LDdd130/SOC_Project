# PPT 검증 자료 세트 — Mission SoC

발표 자료(PPT)에 들어갈 사실을 **저장소 실물(코드·BD·XDC·XCI)에서 직접 추출**해 정리한 문서 묶음이다.
슬라이드를 쓰거나 검토할 때 이 폴더의 값과 다르면 슬라이드가 틀린 것이다.

작성 기준일: 2026-08-07
검증 대상 커밋: `2194ee1` (Update verified Python test count)

---

## 파일 구성

| 파일 | 용도 | 언제 보나 |
|---|---|---|
| [`00_FACT_SHEET.md`](00_FACT_SHEET.md) | **한 장짜리 정본.** 슬라이드에 숫자·이름을 쓰기 직전에 대조하는 표 | 항상 먼저 |
| [`01_HW_BLOCK_DESIGN_AND_IP.md`](01_HW_BLOCK_DESIGN_AND_IP.md) | Vivado Block Design 실제 구성, 3개 Custom IP 레지스터 맵, XDC, LED/IRQ 매핑 | 아키텍처·IP·Vivado 슬라이드 |
| [`02_FW_AND_PROTOCOL.md`](02_FW_AND_PROTOCOL.md) | Vitis 펌웨어(부팅·ISR·Snapshot Ring), UART 프로토콜 전체, Python 앱과의 대응 | 펌웨어·AXI/IRQ·UART·GUI 슬라이드 |
| [`03_VERIFICATION_AND_RESULTS.md`](03_VERIFICATION_AND_RESULTS.md) | Testbench 결과, 구현 결과(Timing/Utilization), 보드 시연 증거 | 검증·결과 슬라이드 |
| [`04_CONTRADICTIONS.md`](04_CONTRADICTIONS.md) | 문서 간·문서와 코드 간 모순 25건 + 정본 판정 + 조치 (대부분 반영 완료) | 배경 확인용 |
| [`05_SLIDE_CHECKLIST.md`](05_SLIDE_CHECKLIST.md) | 20장 슬라이드별 "이 말은 해도 됨 / 이 말은 하면 안 됨" + 예상 질문 대응 | 최종 리허설 전 |
| [`06_PPT_AUDIT_v4.md`](06_PPT_AUDIT_v4.md) | **실제 PDF(34p) 대조 결과.** 고칠 항목 + 우선순위 | **가장 먼저** |
| [`07_MY_SLIDES_GUIDE.md`](07_MY_SLIDES_GUIDE.md) | **빈 슬라이드 채우기.** GUI · 트러블슈팅 · 검증환경 · 자원사용량 · Custom IP 1·2·3 | 슬라이드 작성 중 |

---

## 사용 순서

```text
1. 04_CONTRADICTIONS.md 의 [즉시 조치] 항목을 먼저 처리
   → 특히 C-01(Timing/Utilization 수치)과 C-02(Testbench check 수)는
     Vivado / 시뮬레이터 재실행 없이는 슬라이드에 쓸 수 없다.

2. 00_FACT_SHEET.md 를 옆에 띄워 두고 슬라이드 작성

3. 05_SLIDE_CHECKLIST.md 로 장별 검토

4. 01~03 은 근거가 필요할 때 참조 (모든 값에 파일 경로/줄 표기)
```

---

## 이 문서 묶음이 다루는 4개 축과 연결점

```text
[Vivado Block Design]                 01_HW
   mission_soc.bd
   ├ MicroBlaze V(RISC-V) + AXI Interconnect + INTC + UARTLite + GPIO×2
   ├ Custom IP ×3  (직접 연결 체인)                     ← 01_HW 3장
   ├ eval_tick_generator (Module Reference)             ← 01_HW 4장
   └ led_concat → led[15:0]                            ← 01_HW 6장
        │
        │ Address Map / IRQ ID
        ▼
[Vitis 펌웨어]                        02_FW
   mission_ip_regs.h  (Offset 정본)
   main.c             (부팅 13단계 + 메인 루프)
   mission_intr.c     (ISR + Snapshot Ring)
   uart_proto.c       (프로토콜 구현)
        │
        │ UART 9600 8N1 / ASCII CSV
        ▼
[Python 대시보드]                     02_FW 5~7장
   protocol.py        (수신 파서)
   command_builder.py (송신 명령 생성)
   constants.py       (기본값·범위)
        │
        ▼
[증거]                                03_VERIFY
   sim/ TB 8종 · verification/ 문서 · CSV 로그 · Vivado 리포트
```

**연결점이 깨지면 바로 발표 사고가 되는 지점 4곳**

1. `Address Map` ↔ `mission_ip_regs.h` — 주소가 다르면 `FM_SelfCheck()` 실패
2. `xlconcat In0~In3` ↔ `mission_intr.h` 의 `INTR_ID_*` — 순서가 다르면 엉뚱한 ISR
3. `uart_proto.c` 출력 형식 ↔ `protocol.py` 파서 — 필드 순서가 다르면 GUI가 안 읽음
4. `command_builder.py` 문자열 ↔ `uart_proto.c` 파서 — 이름이 다르면 `$ERR,UNKNOWN_COMMAND`

각각 01·02 문서에 실측 대조표가 있다.
