# Mission SoC PPT 비교 검토 및 Canva 초안 반영 사항

검토 대상:

- `Mission_SoC_White_Keynote_Portfolio_v1.pptx`
- `Mission_SoC_White_Keynote_Portfolio_Canva_v2.pptx`

## 1. 두 PPTX 비교 결론

- 두 파일 모두 22장, 16:9이며 슬라이드별 텍스트, 도형 수, 위치, 크기, 폰트 크기가 동일하다.
- `Canva_v2`는 새 디자인 버전이라기보다 Canva를 거치며 Master/Layout/Thumbnail 메타데이터가 보강된 재저장본에 가깝다.
- 따라서 내용 또는 디자인 선택 기준으로는 두 파일을 따로 유지할 필요가 크지 않다.

## 2. 00~04 구조 적합성

| 구분 | 기존 슬라이드 | 평가 |
|---|---:|---|
| 00 표지·목차 | 1~2 | 표지는 좋지만 목차가 52개 텍스트 요소로 과밀 |
| 01 프로젝트 개요 | 3~6 | 배경·목표·대상·R&R 흐름이 자연스러움 |
| 02 시스템 설계 | 7~13 | Architecture, 3 IP, 시간 축, Safety/Recovery 정책이 잘 연결됨 |
| 03 구현 및 통합 | 14~17 | Vivado, MicroBlaze, AXI/IRQ, GUI를 모두 포함 |
| 04 검증 및 결과 | 18~22 | 구성은 맞지만 검증 수준과 Timing 수치가 현재 산출물보다 오래됨 |

전체 스토리는 적절하다. 가장 큰 수정 대상은 `목차 압축`, `글자 크기`, `최신 검증/구현 결과 반영`이다.

## 3. 디자인 수정 필요 사항

- 기존 본문 글자 크기는 주로 7~12pt이며, 여러 슬라이드에서 30~68개 텍스트 요소를 사용한다.
- 특히 GUI, Firmware, 검증, Troubleshooting 슬라이드는 발표 화면에서 읽기 어렵다.
- 한 슬라이드에 하나의 결론을 두고 본문을 3~5개 메시지로 제한하는 편이 좋다.
- 기존의 흰 배경, Noto Sans KR, Blue/Teal/Red 상태 색상은 유지 가치가 높다.
- 표지는 Dark Navy로 대비를 높이고, 본문은 White Keynote 스타일을 유지하면 섹션 구분이 명확하다.

## 4. 현재 산출물 기준으로 수정한 사실 정보

### 검증 결과

- Fault Manager Core: `checks=4146`, `errors=0`, `ALL PASS`
- Fault 정책 Reference Model 전수 비교: `4096 cases`
- Fault Manager AXI: 기본 46 checks + A11/A12/A13 14 checks = `60 checks`, `errors=0`
- eval_tick generator: `5 checks`, `errors=0`
- D0 UART/GUI E2E 로그: `mission_events_20260730_104707.csv`, 318 data rows
- Heartbeat/Safety self-checking TB와 D1/D2/Multi/Manual Reset 전체 GUI 캡처는 추가 권장

### Routed 구현 결과

- WNS: `+0.198 ns`
- TNS: `0.000 ns`
- WHS: `+0.033 ns`
- Slice LUT: `3,039 / 20,800 = 14.61%`
- Slice Register: `2,646 / 41,600 = 6.36%`
- BRAM Tile: `32 / 50 = 64.0%`
- DSP: `0 / 90`
- `multiple_clock = 0`
- 남은 항목: I/O delay 미지정 2 inputs / 17 outputs, Methodology 및 PDRC Warning 재검토

기존 21~22장의 `multiple_clock 2,730`, `WNS +1.118 ns`, `LUT 3,099`, `Register 2,778`은 현재 routed report와 일치하지 않아 교체했다.

## 5. Canva 초안 구성

새 초안은 20장으로 정리했다.

1. Cover
2. Compact Contents
3. Background
4. Goals
5. Target Devices & Requirements
6. R&R & Schedule
7. Architecture
8. Heartbeat Monitor
9. Fault Manager
10. Two Time Axes
11. Safety Output Policy
12. State & Recovery
13. Vivado Block Design
14. MicroBlaze Firmware
15. AXI & Interrupt
16. UART & GUI
17. Verification Strategy & Pass Metrics
18. Device 0 / Device 1 Scenario
19. Device 2 / Multi Fault / Manual Reset
20. Routed Result, Remaining Sign-off, Conclusion

최종 발표 전에는 Member A/B/C를 실제 이름으로 바꾸고, GUI 화면·Vivado Block Design·시연 영상 QR 또는 캡처를 필요한 슬라이드에 추가하는 것을 권장한다.
