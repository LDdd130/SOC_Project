import React from 'react';
import {Easing, interpolate} from 'remotion';
import type {Callout} from '../data';
import {project, type Transform} from '../geometry';
import {C, DEMO_SPEED, FONT_MONO, FONT_SANS, SRC_H, SRC_W, VP_H, VP_W, VP_X, VP_Y} from '../theme';

const GAP = 16;
/** 콜아웃은 시연 세그먼트에만 붙으므로 시연 속도를 따라간다. */
const a = (frames: number) => frames / DEMO_SPEED;

const CalloutBox: React.FC<{c: Callout; t: Transform; local: number}> = ({c, t, local}) => {
  const age = local - c.at;
  if (age < 0) return null;

  const appear = interpolate(age, [0, a(12)], [0, 1], {
    easing: Easing.out(Easing.cubic),
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const box = project(c.rect, t);

  // 박스 둘레를 그리는 진행률. 짧게 스치듯 그린다.
  const draw = interpolate(age, [0, a(14)], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const perimeter = 2 * (box.width + box.height);

  const labelBase: React.CSSProperties = {
    position: 'absolute',
    // 안쪽 글자가 nowrap 이라 폭을 고정하면 배경이 글자보다 좁아진다.
    // 내용 길이에 맞춰 늘어나게 두고 뷰포트 폭만 상한으로 건다.
    width: 'max-content',
    maxWidth: VP_W - GAP * 2,
    padding: '10px 16px',
    borderRadius: 10,
    background: 'rgba(8, 11, 17, 0.92)',
    border: `1px solid ${c.color}`,
    boxShadow: `0 10px 30px rgba(0,0,0,0.55)`,
    opacity: appear,
    transform: `translateY(${(1 - appear) * 8}px)`,
  };

  const cx = box.left + box.width / 2 + (c.dx ?? 0);
  const cy = box.top + box.height / 2 + (c.dy ?? 0);
  const dx = c.dx ?? 0;
  const dy = c.dy ?? 0;
  const pos: React.CSSProperties = {};
  if (c.side === 'right') {
    pos.left = box.left + box.width + GAP + dx;
    pos.top = cy;
    pos.transform = `translateY(calc(-50% + ${(1 - appear) * 8}px))`;
  } else if (c.side === 'left') {
    pos.right = VP_W - box.left + GAP - dx;
    pos.top = cy;
    pos.transform = `translateY(calc(-50% + ${(1 - appear) * 8}px))`;
  } else if (c.side === 'above') {
    pos.bottom = VP_H - box.top + GAP - dy;
    pos.left = Math.max(GAP, Math.min(cx - 200, VP_W - 420));
  } else {
    pos.top = box.top + box.height + GAP + dy;
    pos.left = Math.max(GAP, Math.min(cx - 200, VP_W - 420));
  }

  return (
    <>
      <svg
        style={{position: 'absolute', left: 0, top: 0, width: VP_W, height: VP_H, pointerEvents: 'none'}}
      >
        <rect
          x={box.left}
          y={box.top}
          width={box.width}
          height={box.height}
          rx={6}
          fill={`${c.color}14`}
          stroke={c.color}
          strokeWidth={3}
          strokeDasharray={perimeter}
          strokeDashoffset={perimeter * (1 - draw)}
        />
      </svg>
      <div style={{...labelBase, ...pos}}>
        <div
          style={{
            fontFamily: c.mono ? FONT_MONO : FONT_SANS,
            fontSize: c.mono ? 30 : 28,
            fontWeight: 700,
            color: c.color,
            letterSpacing: c.mono ? 0.5 : 0,
            whiteSpace: 'nowrap',
          }}
        >
          {c.label}
        </div>
        {c.sub ? (
          <div style={{fontFamily: FONT_SANS, fontSize: 20, color: C.dim, marginTop: 4, whiteSpace: 'nowrap'}}>
            {c.sub}
          </div>
        ) : null}
      </div>
    </>
  );
};

export const Viewport: React.FC<{
  transform: Transform;
  callouts?: Callout[];
  local: number;
  children: React.ReactNode;
}> = ({transform, callouts, local, children}) => {
  return (
    <div
      style={{
        position: 'absolute',
        left: VP_X,
        top: VP_Y,
        width: VP_W,
        height: VP_H,
        overflow: 'hidden',
        background: '#000',
      }}
    >
      <div
        style={{
          position: 'absolute',
          left: 0,
          top: 0,
          width: SRC_W,
          height: SRC_H,
          transformOrigin: '0 0',
          transform: `translate(${transform.tx}px, ${transform.ty}px) scale(${transform.scale})`,
        }}
      >
        {children}
      </div>
      {(callouts ?? []).map((c, i) => (
        <CalloutBox key={i} c={c} t={transform} local={local} />
      ))}
    </div>
  );
};
