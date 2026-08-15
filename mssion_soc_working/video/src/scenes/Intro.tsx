import React from 'react';
import {AbsoluteFill, Easing, Img, interpolate, staticFile, useCurrentFrame} from 'remotion';
import {CREDITS} from '../config';
import {C, CARD_SPEED, FONT_MONO, FONT_SANS} from '../theme';

const CHAIN = ['heartbeat_monitor', 'fault_manager', 'safety_controller'];

/** 카드 애니메이션은 카드 속도를 따라간다. */
const a = (frames: number) => frames / CARD_SPEED;

export const Intro: React.FC<{dur: number}> = ({dur}) => {
  const f = useCurrentFrame();

  const rise = (delay: number) =>
    interpolate(f, [a(delay), a(delay + 20)], [0, 1], {
      easing: Easing.out(Easing.cubic),
      extrapolateLeft: 'clamp',
      extrapolateRight: 'clamp',
    });

  const out = interpolate(f, [dur - a(14), dur], [1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  const members = CREDITS.members.filter((m) => m.name.trim() !== '');

  return (
    <AbsoluteFill style={{background: C.bg, fontFamily: FONT_SANS, opacity: out}}>
      <Img
        src={staticFile('arch.png')}
        style={{
          position: 'absolute',
          inset: 0,
          width: '100%',
          height: '100%',
          objectFit: 'cover',
          opacity: 0.085 * rise(0),
          filter: 'grayscale(1) contrast(0.75) blur(2.5px)',
        }}
      />
      <AbsoluteFill
        style={{
          background: 'radial-gradient(120% 90% at 50% 40%, rgba(8,11,17,0.55) 0%, rgba(8,11,17,0.97) 70%)',
        }}
      />

      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center', padding: 100}}>
        <div
          style={{
            fontSize: 22,
            letterSpacing: 6,
            color: C.info,
            opacity: rise(4),
            transform: `translateY(${(1 - rise(4)) * 14}px)`,
          }}
        >
          MISSION SoC · DEMONSTRATION
        </div>

        <div
          style={{
            marginTop: 26,
            fontSize: 74,
            fontWeight: 800,
            color: C.text,
            letterSpacing: -2,
            textAlign: 'center',
            opacity: rise(12),
            transform: `translateY(${(1 - rise(12)) * 18}px)`,
          }}
        >
          {CREDITS.title}
        </div>

        <div
          style={{
            marginTop: 16,
            fontSize: 28,
            color: C.dim,
            opacity: rise(20),
          }}
        >
          {CREDITS.subtitle}
        </div>

        <div
          style={{
            marginTop: 54,
            display: 'flex',
            alignItems: 'center',
            gap: 20,
          }}
        >
          {CHAIN.map((name, i) => (
            <React.Fragment key={name}>
              {i > 0 ? (
                <div style={{fontSize: 32, color: C.faint, opacity: rise(34 + i * 10)}}>→</div>
              ) : null}
              <div
                style={{
                  fontFamily: FONT_MONO,
                  fontSize: 26,
                  color: C.text,
                  padding: '14px 26px',
                  borderRadius: 12,
                  background: C.panel,
                  border: `1px solid ${C.panelEdge}`,
                  opacity: rise(30 + i * 10),
                  transform: `translateY(${(1 - rise(30 + i * 10)) * 12}px)`,
                }}
              >
                {name}
              </div>
            </React.Fragment>
          ))}
        </div>

        <div style={{marginTop: 22, fontSize: 22, color: C.faint, opacity: rise(58)}}>
          안전 판단과 출력 차단은 모두 FPGA 안에서 이루어집니다
        </div>

        {members.length > 0 || CREDITS.org || CREDITS.date ? (
          <div
            style={{
              marginTop: 60,
              display: 'flex',
              alignItems: 'center',
              gap: 28,
              opacity: rise(70),
              fontSize: 21,
              color: C.dim,
            }}
          >
            {members.map((m) => (
              <div key={m.role} style={{textAlign: 'center'}}>
                <div style={{color: C.text, fontWeight: 700}}>{m.name}</div>
                <div style={{fontFamily: FONT_MONO, fontSize: 17, color: C.faint, marginTop: 3}}>{m.role}</div>
              </div>
            ))}
            {CREDITS.org ? <div style={{color: C.faint}}>{CREDITS.org}</div> : null}
            {CREDITS.date ? <div style={{color: C.faint}}>{CREDITS.date}</div> : null}
          </div>
        ) : null}
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
