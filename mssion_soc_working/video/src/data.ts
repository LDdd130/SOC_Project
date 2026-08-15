import {
  F_CTRL,
  F_FULL,
  F_INJECT,
  F_LEFT,
  F_LOG,
  F_STATUS,
  R_BIG,
  R_CARD_D2,
  R_D0_ALIVE,
  R_LOG_REJECT,
  R_TRAIL,
  type FocusKey,
  type Rect,
} from './geometry';
import {C, CARD_SPEED, DEMO_SPEED, stretch} from './theme';

/** 값 칸만 좁게 감싸는 박스들. 라벨 놓을 여백을 남기려고 줄 전체를 쓰지 않는다. */
const R_LEVEL_V: Rect = {x: 126, y: 250, w: 262, h: 30};
const R_OE_V: Rect = {x: 126, y: 338, w: 204, h: 32};

export type Side = 'left' | 'right' | 'above' | 'below';

export type Callout = {
  rect: Rect;
  /** 짧은 강조. 화면에 찍힌 값이나 프로토콜 문자열은 그대로 쓴다. */
  label: string;
  /** 라벨 아래 한 줄 설명. 없으면 생략. */
  sub?: string;
  color: string;
  side: Side;
  /** 세그먼트 시작 후 몇 프레임에 나타나는가 (DEMO_SPEED 적용 전 기준) */
  at: number;
  /** 등폭으로 찍을 값인가 (헥사·프로토콜 문자열) */
  mono?: boolean;
  /** 라벨끼리 겹칠 때 쓰는 미세 조정 (뷰포트 화면 px) */
  dx?: number;
  dy?: number;
};

type Common = {
  id: string;
  cut: number;
  dur: number;
  chip: string;
  lines: string[];
  /**
   * 이 세그먼트 안에서 화면이 어디를 보는가. 보간하지 않고 컷으로 갈아탄다.
   * p 는 세그먼트 진행률 0..1 이다.
   */
  focus: FocusKey[];
  callouts?: Callout[];
};

export type Segment =
  | {kind: 'intro'; id: string; dur: number}
  | {kind: 'outro'; id: string; dur: number}
  | (Common & {kind: 'motion'; srcStart: number; rate: number})
  | (Common & {kind: 'still'; still: string; srcTime: number});

const k = (...keys: FocusKey[]): FocusKey[] => keys;

/**
 * 배속 적용 전 정본.
 *
 * `focus` 의 p 값은 "그 순간 무슨 일이 벌어지는가"로 정했다. 배속을 바꿔도
 * 클릭·상태 전이의 상대 위치(p)는 변하지 않으므로 이 값들은 그대로 유효하다.
 *
 * still 의 `srcTime` 은 직전 모션 세그먼트의 마지막 프레임 시각이다.
 *     srcTime = srcStart + (stretch(dur, DEMO_SPEED) - 1) / 30 * (rate * DEMO_SPEED)
 * 이 값이 바뀌면 `public/stills/*.png` 도 다시 뽑아야 한다 (README §1).
 *
 * 자막 말투는 발표용 존댓말로 통일한다. 자기 설계를 단정하거나 과시하는 표현
 * (`~라는 증명이다`, `~할 뿐이다`) 대신 화면에 보이는 사실만 서술한다.
 */
const RAW: Segment[] = [
  {kind: 'intro', id: 'intro', dur: 150},

  // ── 컷 ① 하트비트 끊김 → 등급 상승 → 부분 차단 ───────────────
  {
    kind: 'motion',
    id: 'c1a',
    cut: 1,
    dur: 130,
    // 체크박스를 누르는 순간(src 10.465s)이 화면에 잡히도록 앞을 조금 더 뒀다.
    srcStart: 9.9,
    rate: 0.75,
    chip: '하트비트로 장치 생존을 감시합니다',
    lines: [
      'Error 주입이 아니라 DEVICE 0 의 하트비트를 실제로 끊습니다.',
      'heartbeat_monitor 가 TIMEOUT0 = 30,000,000 clk (0.3초) 초과를 스스로 판정합니다.',
    ],
    // 0.175 에 체크박스 클릭, 0.363 에 DEGRADED 전이.
    focus: k({p: 0, rect: F_FULL}, {p: 0.14, rect: F_INJECT}, {p: 0.3, rect: F_LEFT}),
  },
  {
    kind: 'still',
    id: 'c1b',
    cut: 1,
    dur: 108,
    still: 'cut1',
    srcTime: 13.14,
    chip: '고장 난 장치만 차단합니다',
    lines: [
      '지속시간 판정을 거쳐 WARNING → DEGRADED 로 등급이 올라갔습니다.',
      '전면 차단이 아니라 DEGRADE_MASK = 0x01 이 지정한 DEVICE 0 만 차단됐습니다.',
    ],
    focus: k({p: 0, rect: F_LEFT}),
    callouts: [
      {
        rect: R_TRAIL,
        label: 'NORMAL → WARNING → DEGRADED',
        sub: '두 단계를 실제로 거쳤습니다',
        color: C.info,
        side: 'left',
        at: 8,
        dy: -44,
      },
      {rect: R_LEVEL_V, label: 'LEVEL 2 — DEGRADED', color: C.warn, side: 'right', at: 22},
      {rect: R_OE_V, label: 'oe = 0b110', sub: 'DEVICE 0 만 차단, 나머지는 유지', color: C.danger, side: 'right', at: 36, mono: true},
      {rect: R_D0_ALIVE, label: 'Alive: DOWN · Timeout: TIMEOUT', sub: '하트비트가 실제로 멈췄습니다', color: C.danger, side: 'below', at: 52},
    ],
  },

  // ── 컷 ② 원인이 사라지면 자동 복귀 ───────────────────────────
  {
    kind: 'motion',
    id: 'c2a',
    cut: 2,
    dur: 84,
    srcStart: 13.14,
    rate: 0.8,
    chip: '원인이 사라지면 스스로 복귀합니다',
    lines: ['주입을 해제하면 하트비트가 다시 뛰기 시작합니다.'],
    // 0.156 에 NORMAL 복귀. 넓게 본 뒤 상태 패널로 컷.
    focus: k({p: 0, rect: F_LEFT}, {p: 0.45, rect: F_STATUS}),
  },
  {
    kind: 'still',
    id: 'c2b',
    cut: 2,
    dur: 92,
    still: 'cut2',
    srcTime: 15.364,
    chip: 'DEGRADED 는 자동으로 복귀합니다',
    lines: [
      'RECOVERY_COUNT = 2 × eval_tick(1ms) 만에 NORMAL 로 복귀했습니다.',
      '사람 개입 없이 스스로 돌아옵니다. SAFE_MODE 는 다음 컷에서 비교해 보겠습니다.',
    ],
    focus: k({p: 0, rect: F_STATUS}),
    callouts: [
      {rect: R_LEVEL_V, label: 'LEVEL 0 자동 복귀', color: C.normal, side: 'right', at: 10},
      {rect: R_OE_V, label: 'oe = 0b111', sub: '출력 전부 복구', color: C.normal, side: 'right', at: 26, mono: true},
    ],
  },

  // ── 컷 ③ Critical 은 지속시간을 안 따진다 ────────────────────
  {
    kind: 'motion',
    id: 'c3a',
    cut: 3,
    dur: 116,
    srcStart: 18.9,
    rate: 0.7,
    chip: '임무 필수 장치는 다르게 처리합니다',
    lines: [
      'CRITICAL_MASK = 0x04 로 DEVICE 2 를 임무 필수 장치로 지정했습니다.',
      '이 장치의 Critical 고장은 PERSIST_LIMIT 지속 판정을 건너뜁니다.',
    ],
    // 0.129 에 프리셋 클릭, 0.23 에 SAFE_MODE 전이.
    focus: k({p: 0, rect: F_INJECT}, {p: 0.2, rect: F_LEFT}),
  },
  {
    kind: 'still',
    id: 'c3b',
    cut: 3,
    dur: 112,
    still: 'cut3',
    srcTime: 21.588,
    chip: '20 ns 만에 전면 차단합니다',
    lines: [
      '중간 등급 없이 곧바로 SAFE_MODE 입니다. fault_manager 1클럭 + safety_controller 1클럭.',
      '100 MHz 기준 2클럭, 20 ns 입니다. eval_tick 도 기다리지 않습니다.',
    ],
    focus: k({p: 0, rect: F_LEFT}),
    callouts: [
      {rect: R_BIG, label: 'SAFE_MODE', sub: 'WARNING · DEGRADED 를 건너뛰었습니다', color: C.danger, side: 'right', at: 8},
      {rect: R_OE_V, label: 'oe = 0b000', sub: '액추에이터 전면 차단', color: C.danger, side: 'right', at: 26, mono: true},
      {rect: R_CARD_D2, label: '하트비트는 정상입니다 (alive = 0x07)', sub: 'Critical 하나로 전체가 멈췄습니다', color: C.info, side: 'above', at: 44},
    ],
  },

  // ── 컷 ④ 복구 거부 ───────────────────────────────────────────
  {
    kind: 'motion',
    id: 'c4a',
    cut: 4,
    dur: 88,
    srcStart: 25.4,
    rate: 0.75,
    chip: '고장이 남아있는 상태에서 복구를 시도합니다',
    lines: ['Critical 주입을 끄지 않은 채로 Manual Recovery 를 눌러 봅니다.'],
    // 0.277 에 버튼 클릭, 0.348 에 $ERR 수신.
    focus: k({p: 0, rect: F_CTRL}, {p: 0.32, rect: F_LOG}),
  },
  {
    kind: 'still',
    id: 'c4b',
    cut: 4,
    dur: 118,
    still: 'cut4',
    srcTime: 27.59,
    chip: '하드웨어가 요청을 거부합니다',
    lines: [
      '운용자가 눌러도 fault_level ≠ 0 이면 safety_controller 가 명령을 받지 않습니다.',
      '앱이 막은 것이 아니라 거부 판단이 FPGA 안에 있습니다.',
    ],
    focus: k({p: 0, rect: F_LOG}),
    callouts: [
      {
        rect: R_LOG_REJECT,
        label: '$ERR,MANUAL_RESET,FAULT_ACTIVE',
        sub: '상태는 SAFE_MODE 그대로입니다',
        color: C.danger,
        side: 'below',
        at: 14,
        mono: true,
      },
    ],
  },

  // ── 컷 ⑤ 원인을 없애도 안 풀린다 (Latch) ─────────────────────
  {
    kind: 'motion',
    id: 'c5a',
    cut: 5,
    dur: 96,
    srcStart: 29.0,
    rate: 0.75,
    chip: '고장 원인을 전부 제거합니다',
    lines: ['Clear All Injection 으로 주입한 고장을 모두 지웁니다.'],
    // 0.21 에 프리셋 클릭, 0.285 에 fault_level 이 0 으로.
    focus: k({p: 0, rect: F_INJECT}, {p: 0.26, rect: F_STATUS}),
  },
  {
    kind: 'still',
    id: 'c5b',
    cut: 5,
    dur: 132,
    still: 'cut5',
    srcTime: 31.385,
    chip: 'SAFE_MODE 는 래치로 유지됩니다',
    lines: [
      '고장 등급은 LEVEL 0 이지만 상태는 SAFE_MODE 그대로입니다. STATE_CHANGE 가 나오지 않습니다.',
      '원인이 사라진 것과 안전이 확인된 것은 다르기 때문에 스스로 풀리지 않도록 설계했습니다.',
    ],
    focus: k({p: 0, rect: F_STATUS}),
    callouts: [
      {rect: R_LEVEL_V, label: 'LEVEL 0 — 고장 없음', color: C.normal, side: 'right', at: 8},
      {rect: R_BIG, label: '그래도 SAFE_MODE', color: C.danger, side: 'right', at: 26},
      {rect: R_OE_V, label: 'oe = 0b000 유지', color: C.danger, side: 'right', at: 44, mono: true},
      {
        rect: R_TRAIL,
        label: '마지막 전이 11:30:38.838',
        sub: 'Clear 이후 새 STATE_CHANGE 가 없습니다',
        color: C.violet,
        side: 'left',
        at: 62,
      },
    ],
  },

  // ── 컷 ⑥ 조건이 갖춰지면 그때 승인 ───────────────────────────
  {
    kind: 'motion',
    id: 'c6a',
    cut: 6,
    dur: 116,
    srcStart: 34.9,
    rate: 0.75,
    chip: '같은 버튼, 같은 명령입니다',
    lines: [
      '컷 ④ 와 같은 Manual Recovery 이고, 명령 문자열도 CMD,MANUAL_RESET 로 같습니다.',
      '달라진 것은 fault_level 하나뿐입니다.',
    ],
    // 0.20 에 버튼 클릭, 0.259 에 $ACK 와 NORMAL 복귀.
    focus: k({p: 0, rect: F_CTRL}, {p: 0.24, rect: F_STATUS}),
  },
  {
    kind: 'still',
    id: 'c6b',
    cut: 6,
    dur: 108,
    still: 'cut6',
    srcTime: 37.78,
    chip: '조건이 갖춰지면 승인합니다',
    lines: [
      '이번에는 $ACK 가 돌아오고 NORMAL 로 복귀합니다. 출력도 다시 열립니다.',
      '승인 조건이 소프트웨어가 아니라 하드웨어에 있다는 것을 확인할 수 있습니다.',
    ],
    focus: k({p: 0, rect: F_STATUS}),
    callouts: [
      {rect: R_BIG, label: 'NORMAL 복귀', color: C.normal, side: 'right', at: 10},
      {rect: R_OE_V, label: 'oe = 0b111', color: C.normal, side: 'right', at: 28, mono: true},
    ],
  },

  {kind: 'outro', id: 'outro', dur: 240},
];

/** 길이는 늘리고 소스 재생은 그만큼 느리게 해서, 덮는 소스 구간을 그대로 유지한다. */
const applySpeed = (s: Segment): Segment => {
  if (s.kind === 'intro' || s.kind === 'outro') {
    return {...s, dur: stretch(s.dur, CARD_SPEED)};
  }
  const callouts = s.callouts?.map((c) => ({...c, at: stretch(c.at, DEMO_SPEED)}));
  if (s.kind === 'motion') {
    return {...s, dur: stretch(s.dur, DEMO_SPEED), rate: s.rate * DEMO_SPEED, callouts};
  }
  return {...s, dur: stretch(s.dur, DEMO_SPEED), callouts};
};

export const SEGMENTS: Segment[] = RAW.map(applySpeed);

export const TOTAL_FRAMES = SEGMENTS.reduce((a, s) => a + s.dur, 0);

/** 세그먼트별 시작 프레임 */
export const STARTS = (() => {
  const out: number[] = [];
  let acc = 0;
  for (const s of SEGMENTS) {
    out.push(acc);
    acc += s.dur;
  }
  return out;
})();

export const CUT_TITLES = [
  '하트비트 감시',
  '자동 복귀',
  'Critical 즉시 차단',
  '복구 거부',
  'SAFE_MODE 래치',
  '조건부 승인',
];
