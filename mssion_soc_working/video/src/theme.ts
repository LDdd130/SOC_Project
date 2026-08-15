export const FPS = 30;
export const W = 1920;
export const H = 1080;

/**
 * 재생 속도. 낮을수록 느리다. 0.6 이면 같은 내용을 5/3 배 길게 보여준다.
 * 세그먼트 길이·소스 배속·자막과 콜아웃 등장 타이밍이 전부 이 값을 따라간다.
 *
 * 카드와 시연을 나눠 둔 이유: 인트로/아웃트로는 읽는 속도가 이미 맞는데
 * 보드 화면은 값을 눈으로 좇아야 해서 더 느려야 한다.
 */
/** 인트로 · 아웃트로 카드 */
export const CARD_SPEED = 0.75;
/** 보드 화면이 나오는 컷 ①~⑥ 전부 */
export const DEMO_SPEED = 0.6;

/** 프레임 수를 재생 속도에 맞춰 늘린다. */
export const stretch = (frames: number, speed: number) => Math.round(frames / speed);

/** demo_cfr.mp4 의 실제 픽셀 크기. 모든 focus/callout 좌표는 이 좌표계다. */
export const SRC_W = 1918;
export const SRC_H = 944;

/** 화면 배치 */
export const TOPBAR_H = 84;
export const CAPTION_H = 148;
export const VP_X = 0;
export const VP_Y = TOPBAR_H;
export const VP_W = W;
export const VP_H = H - TOPBAR_H - CAPTION_H; // 848

export const C = {
  bg: '#080B11',
  panel: '#111825',
  panelEdge: '#1E2A3D',
  text: '#E9EEF6',
  dim: '#8494AA',
  faint: '#4A5769',

  normal: '#3DDC91',
  warn: '#F5B841',
  danger: '#FF5C5C',
  info: '#5AA9FF',
  violet: '#B78BFF',
} as const;

export const FONT_SANS =
  "'Noto Sans CJK KR', 'Noto Sans KR', 'Noto Sans', sans-serif";
export const FONT_MONO =
  "'DejaVu Sans Mono', 'Liberation Mono', 'Noto Sans CJK KR', monospace";
