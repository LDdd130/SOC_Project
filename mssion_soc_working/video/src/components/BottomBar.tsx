import React from 'react';
import {Easing, interpolate} from 'remotion';
import cues from '../cues.json';
import {C, CAPTION_H, DEMO_SPEED, FONT_MONO, FONT_SANS, H, W} from '../theme';

/** 자막 띠는 시연 세그먼트에만 나오므로 시연 속도를 따라간다. */
const a = (frames: number) => frames / DEMO_SPEED;

type Cue = (typeof cues)[number];

const CIRCLED = ['①', '②', '③', '④', '⑤', '⑥'];

const colorForCue = (c: Cue) => {
  if (c.type === 'TX') return C.info;
  if (c.type === 'ERR') return C.danger;
  if (c.type === 'ACK') return C.normal;
  if (c.raw.includes('SAFE_MODE')) return C.danger;
  if (c.raw.includes('DEGRADED') || c.raw.includes('WARNING')) return C.warn;
  if (c.raw.includes('NORMAL')) return C.normal;
  return C.violet;
};

/** 화면에 보이는 순간과 로그가 같은 것임을 보이려고, 실제 CSV 줄을 그대로 흘린다. */
const UartTicker: React.FC<{srcTime: number}> = ({srcTime}) => {
  const past = (cues as Cue[]).filter((c) => c.t <= srcTime);
  const shown = past.slice(-3);

  return (
    <div style={{width: 660, display: 'flex', flexDirection: 'column', justifyContent: 'flex-end'}}>
      <div
        style={{
          fontFamily: FONT_SANS,
          fontSize: 16,
          color: C.faint,
          letterSpacing: 1.2,
          marginBottom: 8,
        }}
      >
        UART · mission_events_20260810_113104.csv
      </div>
      <div style={{display: 'flex', flexDirection: 'column', gap: 5, minHeight: 78}}>
        {shown.map((c) => {
          const age = srcTime - c.t;
          const fresh = interpolate(age, [0, 0.35, 2.2], [0.25, 1, 0.42], {
            easing: Easing.out(Easing.quad),
            extrapolateLeft: 'clamp',
            extrapolateRight: 'clamp',
          });
          const col = colorForCue(c);
          return (
            <div key={`${c.t}-${c.raw}`} style={{display: 'flex', gap: 10, alignItems: 'baseline', opacity: fresh}}>
              <div style={{fontFamily: FONT_MONO, fontSize: 17, color: C.faint, width: 62}}>
                {c.t.toFixed(2)}s
              </div>
              <div
                style={{
                  fontFamily: FONT_MONO,
                  fontSize: 19,
                  color: col,
                  whiteSpace: 'nowrap',
                  overflow: 'hidden',
                  textOverflow: 'ellipsis',
                }}
              >
                {c.type === 'TX' ? `» ${c.raw}` : c.raw}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};

export const BottomBar: React.FC<{
  cut: number;
  chip: string;
  lines: string[];
  srcTime: number;
  local: number;
}> = ({cut, chip, lines, srcTime, local}) => {
  const enter = interpolate(local, [0, a(14)], [0, 1], {
    easing: Easing.out(Easing.cubic),
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  return (
    <div
      style={{
        position: 'absolute',
        left: 0,
        top: H - CAPTION_H,
        width: W,
        height: CAPTION_H,
        background: C.bg,
        borderTop: `1px solid ${C.panelEdge}`,
        display: 'flex',
        alignItems: 'stretch',
        padding: '16px 40px',
        gap: 40,
        fontFamily: FONT_SANS,
      }}
    >
      <div style={{flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'center', minWidth: 0}}>
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 12,
            opacity: enter,
            transform: `translateX(${(1 - enter) * -12}px)`,
          }}
        >
          <span style={{fontSize: 30, color: C.info, fontWeight: 700}}>{CIRCLED[cut - 1]}</span>
          <span style={{fontSize: 29, color: C.text, fontWeight: 700, letterSpacing: -0.3}}>{chip}</span>
        </div>
        <div style={{marginTop: 9, display: 'flex', flexDirection: 'column', gap: 4}}>
          {lines.map((l, i) => (
            <div
              key={i}
              style={{
                fontSize: 23,
                lineHeight: 1.35,
                color: i === 0 ? '#C6D2E2' : C.dim,
                opacity: interpolate(local, [a(8 + i * 6), a(22 + i * 6)], [0, 1], {
                  extrapolateLeft: 'clamp',
                  extrapolateRight: 'clamp',
                }),
              }}
            >
              {l}
            </div>
          ))}
        </div>
      </div>

      <div style={{width: 1, background: C.panelEdge}} />
      <UartTicker srcTime={srcTime} />
    </div>
  );
};
