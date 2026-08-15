# 시연 영상 편집본 (Remotion)

`demo.mp4` 원본 촬영분과 같은 테이크의 UART 로그
`mission_events_20260810_113104.csv` 를 붙여 1920x1080 / 30fps / **89.6초** 편집본을 만든다.
`06_DEMO_VIDEO_SCENARIO.md` 의 컷 ①~⑥ 구성을 그대로 따른다.

화면 전환은 **전부 컷**이다. 확대·이동이 움직이는 구간은 없다.

```bash
cd video
npm install
npm run studio     # 브라우저에서 미리보기 · 타임라인 스크럽
npm run render     # out/mission_soc_demo.mp4
```

> **렌더 전에 Vivado / Vitis 를 닫아라.** 이 머신은 RAM 이 15GB 이고 렌더는 Chrome 을
> 띄운다. `remotion.config.ts` 에서 `Config.setConcurrency(2)` 로 이미 제한해 뒀다.

---

## 1. 무엇을 어디서 가져오는가

| 산출물 | 출처 | 만드는 법 |
|---|---|---|
| `public/demo_cfr.mp4` | 루트 `demo.mp4` | 아래 ffmpeg 명령 |
| `public/stills/cut1..6.png` | `demo_cfr.mp4` | 아래 ffmpeg 명령 |
| `src/cues.json` | 루트 `mission_events_*.csv` | `npm run cues` |
| `public/arch.png` | `docs/mission_soc_system_architecture.png` | 복사 |

원본 `demo.mp4` 는 **가변 프레임률 화면 녹화**(평균 10.8fps, `r_frame_rate` 는 2000/1 로
의미 없는 값)라 그대로 쓰면 프레임 대응이 어긋난다. 고정 30fps 로 먼저 변환한다.

```bash
ffmpeg -i ../demo.mp4 -vf "fps=30,format=yuv420p" \
       -c:v libx264 -preset medium -crf 18 -movflags +faststart -an \
       public/demo_cfr.mp4
```

정지 홀드에 쓰는 스틸은 **각 모션 세그먼트의 마지막 프레임 시각**으로 뽑는다.
그래야 영상이 멈추는 순간 튀지 않고 그대로 얼어붙는다.

```bash
for spec in cut1:13.140 cut2:15.364 cut3:21.588 cut4:27.590 cut5:31.385 cut6:37.780; do
  n=${spec%%:*}; t=${spec##*:}
  ffmpeg -i public/demo_cfr.mp4 -ss $t -frames:v 1 public/stills/$n.png -y
done
```

`src/data.ts` 의 `srcStart` / `rate` / `dur`, 또는 `src/theme.ts` 의 `DEMO_SPEED` 를
고치면 이 시각도 같이 바뀐다. 공식은

```
srcTime = srcStart + (stretch(dur, DEMO_SPEED) - 1) / 30 * (rate * DEMO_SPEED)
stretch(n, speed) = round(n / speed)
```

`data.ts` 의 `RAW` 에 적는 `dur` / `rate` / `at` 은 전부 **속도 적용 전** 값이다.

---

## 2. 영상 시각 ↔ 로그 벽시계 정렬

`scripts/gen_cues.mjs` 의 `ANCHOR = 2026-08-10T11:30:19.320` 하나로 결정된다.

```
video_t = (CSV received_at) - ANCHOR
```

이 값은 화면에 실제로 변화가 일어난 프레임을 ffmpeg 로 찾아 맞춘 것이다.
`고장 등급` 줄만 잘라 장면 전환을 검출하면:

```bash
ffmpeg -i public/demo_cfr.mp4 \
  -vf "crop=560:34:120:250,select='gt(scene,0.02)',metadata=print:file=-" -an -f null -
```

| 화면이 바뀐 시각 | 대응 CSV 이벤트 | 벽시계 | 차이 |
|---|---|---|---|
| 11.100s | `STATE_CHANGE,DEGRADED` | 11:30:30.391 | +0.03 |
| 13.433s | `STATE_CHANGE,NORMAL` | 11:30:32.791 | −0.04 |
| 19.567s | `STATE_CHANGE,SAFE_MODE` | 11:30:38.838 | +0.05 |
| 29.633s | `FAULT_CHANGE,0,3,0` | 11:30:48.997 | −0.04 |
| 35.800s | `STATE_CHANGE,NORMAL` | 11:30:54.964 | +0.16 |

남는 오차는 GUI 가 큰 글씨 상태를 `$MISSION` 수신(약 550ms 주기)에 맞춰 다시 그리기
때문이다. 이벤트 구동인 `최근 전이` 줄과 Event Log 표는 더 빨리 갱신된다.

**다시 촬영하면** 새 CSV 를 루트에 놓고 `ANCHOR` 만 위 방법으로 다시 구한 뒤
`npm run cues` 를 돌린다. 화면 아래 UART 티커는 자동으로 따라온다.

---

## 3. 구성 파일

```
src/
  config.ts       ← 팀원 이름 · 소속 · 발표일. 인트로/아웃트로에 들어간다
  data.ts         ← 컷 구성 정본. 세그먼트 길이, 자막, 콜아웃 위치
  geometry.ts     ← demo_cfr.mp4(1918x944) 좌표계의 관심 영역과 확대 변환
  theme.ts        ← 색·폰트·화면 배치 상수
  cues.json       ← 생성물. 직접 고치지 말 것
  components/
    Viewport.tsx  ← 확대·이동 + 콜아웃 박스/라벨
    TopBar.tsx    ← 상단 컷 진행 표시
    BottomBar.tsx ← 자막 + 실제 CSV 줄을 흘리는 UART 티커
  scenes/
    Intro.tsx  Outro.tsx
```

### 자주 건드릴 것

- **속도** — `src/theme.ts` 의 `CARD_SPEED`(인트로·아웃트로)와 `DEMO_SPEED`(컷 ①~⑥).
  낮출수록 느리다. 세그먼트 길이·소스 배속·자막과 콜아웃 등장 타이밍이 한꺼번에
  따라간다. `DEMO_SPEED` 를 바꾸면 §1 의 스틸을 다시 뽑아야 한다
- **자막 문구** — `src/data.ts` 의 `chip`, `lines`
- **강조 위치** — `src/geometry.ts` 의 `R_*` 사각형 (모두 1918x944 원본 픽셀 기준)
- **강조가 뜨는 시점** — 각 콜아웃의 `at` (SPEED 적용 전 프레임 수)
- **라벨이 겹칠 때** — 콜아웃의 `side` 를 바꾸거나 `dx` / `dy` 로 밀어낸다
- **어디를 보여줄지** — 각 세그먼트의 `focus` 키. p 는 세그먼트 진행률 0..1 이고
  키를 지나는 순간 **컷으로** 갈아탄다. 보간하지 않는다

### 컷 지점을 정하는 기준

`focus` 키의 p 는 "그 순간 화면에서 무슨 일이 벌어지는가"로 잡았다.
클릭이 일어나는 p 와 상태가 바뀌는 p 를 `data.ts` 주석에 적어 뒀다.
컷은 그 사이에 둔다 — 클릭은 우측 패널에서 보고, 결과는 좌측 상태 패널에서 본다.

배속을 바꿔도 이 p 값들은 그대로 유효하다. 길이와 소스 배속이 같은 비율로
움직이므로 상대 위치가 변하지 않는다.

### 확대가 화면 밖으로 나가지 않는 이유

`geometry.ts` 의 `clampAxis` 가 확대된 소스를 뷰포트 가장자리에 붙잡는다.
이게 없으면 `F_LOG` 처럼 화면 맨 아래에 붙은 영역을 잡을 때 소스 바깥의
검은 띠가 절반쯤 들어온다.

---

## 4. 지금 구성

`CARD_SPEED = 0.75` · `DEMO_SPEED = 0.6` · 합계 **2,687 프레임 = 89.57초**
(시연 72.23초 + 카드 17.33초)

`RAW` 는 정의값, `실제` 는 속도 적용 후 값이다.

| 세그먼트 | RAW dur | 실제 프레임 | 소스 구간 | 실제 배속 | 내용 |
|---|---|---|---|---|---|
| intro | 150 | 200 | — | — | 타이틀 · IP 체인 · 팀 크레딧 |
| c1a | 130 | 217 | 9.900 → 13.140 | 0.450× | D0 Timeout 주입 → DEGRADED |
| c1b | 108 | 180 | 13.140 정지 | — | `LEVEL 2` · `oe=0b110` · D0 카드 |
| c2a | 84 | 140 | 13.140 → 15.364 | 0.480× | 주입 해제 |
| c2b | 92 | 153 | 15.364 정지 | — | `LEVEL 0` · `oe=0b111` 자동 복귀 |
| c3a | 116 | 193 | 18.900 → 21.588 | 0.420× | Device 2 Critical Demo |
| c3b | 112 | 187 | 21.588 정지 | — | `SAFE_MODE` · `oe=0b000` · alive 정상 |
| c4a | 88 | 147 | 25.400 → 27.590 | 0.450× | Manual Recovery (고장 살아있음) |
| c4b | 118 | 197 | 27.590 정지 | — | `$ERR,MANUAL_RESET,FAULT_ACTIVE` |
| c5a | 96 | 160 | 29.000 → 31.385 | 0.450× | Clear All Injection |
| c5b | 132 | 220 | 31.385 정지 | — | `LEVEL 0` 인데 `SAFE_MODE` 유지 |
| c6a | 116 | 193 | 34.900 → 37.780 | 0.450× | Manual Recovery (조건 충족) |
| c6b | 108 | 180 | 37.780 정지 | — | `$ACK` · `NORMAL` · `oe=0b111` |
| outro | 240 | 320 | — | — | 네 가지 주장 · 실측 타임라인 · 검증 수치 |

---

## 5. 나레이션을 넣을 때

지금은 **무음 + 한국어 자막**이다. 목소리를 얹으려면:

1. mp3/wav 를 `public/narration.mp3` 로 둔다
2. `src/MissionSocDemo.tsx` 최상단에 한 줄 추가

```tsx
<Audio src={staticFile('narration.mp3')} />
```

`remotion` 에서 `Audio` 를 import 한다. 자막 타이밍은 그대로 두고
녹음을 컷 길이에 맞추는 쪽이 쉽다. 컷별 길이는 §4 표에 있다.
