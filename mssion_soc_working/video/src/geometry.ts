import {SRC_W, SRC_H, VP_W, VP_H} from './theme';

/** demo_cfr.mp4 좌표계(1918x944) 위의 사각형 */
export type Rect = {x: number; y: number; w: number; h: number};

export type FocusKey = {p: number; rect: Rect};

/** 프레임 전체 */
export const F_FULL: Rect = {x: 0, y: 0, w: SRC_W, h: SRC_H};
/** 좌측 상태 패널 전체 */
export const F_LEFT: Rect = {x: 0, y: 105, w: 1330, h: 530};
/** 큰 상태 글씨 + 최근 전이 + 고장 등급/코드/OE 줄 */
export const F_STATUS: Rect = {x: 0, y: 118, w: 1330, h: 272};
/** 고장 등급 ~ Output Enable 네 줄만 */
export const F_ROWS: Rect = {x: 0, y: 240, w: 1330, h: 142};
/** 장치 카드 3개 */
export const F_DEVICES: Rect = {x: 0, y: 398, w: 1310, h: 224};
/** Event Log 표 */
export const F_LOG: Rect = {x: 0, y: 700, w: 1310, h: 244};
/** 우측 Fault Injection 패널 */
export const F_INJECT: Rect = {x: 1288, y: 168, w: 630, h: 420};
/** 우측 설정·제어 하단 버튼 (Manual Recovery 포함) */
export const F_CTRL: Rect = {x: 1288, y: 552, w: 630, h: 128};

// ── 콜아웃이 가리키는 UI 요소들 (native px) ──────────────────
export const R_BIG: Rect = {x: 372, y: 126, w: 574, h: 76};
export const R_TRAIL: Rect = {x: 398, y: 208, w: 902, h: 32};
export const R_LEVEL: Rect = {x: 22, y: 250, w: 624, h: 32};
export const R_CODE: Rect = {x: 22, y: 280, w: 624, h: 32};
export const R_ACT: Rect = {x: 22, y: 310, w: 624, h: 32};
export const R_OE: Rect = {x: 22, y: 338, w: 624, h: 34};
export const R_DEVICE: Rect = {x: 638, y: 250, w: 662, h: 32};
export const R_CTRLVALID: Rect = {x: 638, y: 310, w: 662, h: 32};
export const R_CARD_D0: Rect = {x: 8, y: 404, w: 428, h: 212};
export const R_CARD_D2: Rect = {x: 872, y: 404, w: 428, h: 212};
/** cut4 스틸(src 27.575s)에서 $ERR / REJECTED 두 줄 */
export const R_LOG_REJECT: Rect = {x: 8, y: 758, w: 1294, h: 62};
/** DEVICE 0 카드의 Alive / Timeout 두 줄 */
export const R_D0_ALIVE: Rect = {x: 24, y: 482, w: 404, h: 56};
/** 창 맨 아래 상태 표시줄 */
export const R_STATUSBAR: Rect = {x: 0, y: 916, w: 920, h: 28};
/** Manual Recovery 버튼 */
export const R_BTN_RECOVERY: Rect = {x: 1306, y: 600, w: 292, h: 30};
/** Clear All Injection 프리셋 버튼 */
export const R_BTN_CLEAR: Rect = {x: 1306, y: 540, w: 592, h: 30};
/** Device 2 Critical Demo 프리셋 버튼 */
export const R_BTN_CRITICAL: Rect = {x: 1306, y: 468, w: 592, h: 30};
/** DEVICE 0 Timeout 체크박스 */
export const R_CHK_D0_TIMEOUT: Rect = {x: 1300, y: 192, w: 200, h: 30};

/** 최대 확대율. 이 이상 키우면 원본 픽셀이 뭉갠다. */
const MAX_SCALE = 2.35;
/** 확대해도 사각형 둘레에 남겨둘 여백 (native px) */
const PAD = 26;

export type Transform = {scale: number; tx: number; ty: number};

/**
 * 한 축에서 확대된 소스가 뷰포트보다 크면 가장자리를 넘지 않게 붙잡고,
 * 작으면 가운데 놓는다. 이걸 안 하면 F_LOG 처럼 화면 끝에 붙은 영역을 잡을 때
 * 소스 바깥의 검은 띠가 절반쯤 들어온다.
 */
const clampAxis = (want: number, scaled: number, view: number) => {
  if (scaled < view) return (view - scaled) / 2;
  return Math.min(0, Math.max(view - scaled, want));
};

export const transformFor = (r: Rect): Transform => {
  const w = r.w + PAD * 2;
  const h = r.h + PAD * 2;
  const raw = Math.min(VP_W / w, VP_H / h);
  const scale = Math.min(raw, MAX_SCALE);
  const cx = r.x + r.w / 2;
  const cy = r.y + r.h / 2;
  return {
    scale,
    tx: clampAxis(VP_W / 2 - cx * scale, SRC_W * scale, VP_W),
    ty: clampAxis(VP_H / 2 - cy * scale, SRC_H * scale, VP_H),
  };
};

/**
 * 진행률 p(0..1) 에 해당하는 키프레임을 고른다. **보간하지 않는다** —
 * 키를 지나는 순간 곧바로 갈아탄다. 즉 모든 화면 전환은 컷이고,
 * 확대·이동이 움직이는 구간은 없다.
 */
export const focusAt = (keys: readonly FocusKey[], p: number): Transform => {
  if (keys.length === 0) return transformFor(F_FULL);

  const clamped = Math.max(0, Math.min(1, p));
  let chosen = keys[0].rect;
  for (const key of keys) {
    if (clamped < key.p) break;
    chosen = key.rect;
  }
  return transformFor(chosen);
};

/** native 좌표의 사각형을 뷰포트 화면 좌표로 옮긴다. */
export const project = (r: Rect, t: Transform) => ({
  left: t.tx + r.x * t.scale,
  top: t.ty + r.y * t.scale,
  width: r.w * t.scale,
  height: r.h * t.scale,
});
