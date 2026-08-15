import React from 'react';
import {CREDITS} from '../config';
import {CUT_TITLES} from '../data';
import {C, FONT_SANS, TOPBAR_H, W} from '../theme';

export const TopBar: React.FC<{cut: number | null}> = ({cut}) => {
  return (
    <div
      style={{
        position: 'absolute',
        left: 0,
        top: 0,
        width: W,
        height: TOPBAR_H,
        background: C.bg,
        borderBottom: `1px solid ${C.panelEdge}`,
        display: 'flex',
        alignItems: 'center',
        padding: '0 40px',
        gap: 24,
        fontFamily: FONT_SANS,
      }}
    >
      <div style={{fontSize: 25, fontWeight: 700, color: C.text, letterSpacing: -0.2}}>
        {CREDITS.subtitle}
      </div>
      <div style={{fontSize: 19, color: C.faint}}>보드 시연 · UART 9600 8-N-1</div>

      <div style={{flex: 1}} />

      <div style={{display: 'flex', alignItems: 'center', gap: 10}}>
        {CUT_TITLES.map((title, i) => {
          const n = i + 1;
          const active = cut === n;
          const done = cut !== null && cut > n;
          return (
            <div
              key={n}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 8,
                padding: active ? '7px 16px' : '7px 11px',
                borderRadius: 999,
                background: active ? 'rgba(90,169,255,0.14)' : 'transparent',
                border: `1px solid ${active ? C.info : done ? C.faint : '#1A2434'}`,
              }}
            >
              <div
                style={{
                  width: 9,
                  height: 9,
                  borderRadius: 999,
                  background: active ? C.info : done ? C.faint : '#25324A',
                }}
              />
              <div
                style={{
                  fontSize: 19,
                  fontWeight: active ? 700 : 500,
                  color: active ? C.text : done ? C.dim : C.faint,
                }}
              >
                {active ? `${n}. ${title}` : n}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};
