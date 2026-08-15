import React from 'react';
import {AbsoluteFill, Easing, interpolate, useCurrentFrame} from 'remotion';
import {CREDITS, VERIFICATION} from '../config';
import {C, CARD_SPEED, FONT_MONO, FONT_SANS} from '../theme';

/** 카드 애니메이션은 카드 속도를 따라간다. */
const a = (frames: number) => frames / CARD_SPEED;

const CLAIMS = [
  {
    n: '①',
    text: '하트비트로 장치 생존을 실제로 감시합니다',
    detail: 'TIMEOUT0 = 0.3초 초과를 heartbeat_monitor 가 스스로 판정',
    color: C.info,
  },
  {
    n: '②',
    text: '지속성과 우선순위로 고장 등급을 산출합니다',
    detail: 'PERSIST_LIMIT 지속 판정 · CRITICAL_MASK 는 판정을 건너뜀',
    color: C.warn,
  },
  {
    n: '③',
    text: '등급에 따라 출력을 차단하고 SAFE_MODE 는 래치됩니다',
    detail: 'DEGRADE_MASK 부분 차단 → Critical 시 20 ns 만에 전면 차단',
    color: C.danger,
  },
  {
    n: '④',
    text: '복구는 조건부 승인이며 아무 때나 풀리지 않습니다',
    detail: 'fault_level ≠ 0 이면 MANUAL_RESET 을 하드웨어가 거부',
    color: C.normal,
  },
];

/** 이 테이크에서 실제로 찍힌 시각. cues.json 과 같은 값이다. */
const MILESTONES = [
  {t: 11.0, label: 'HEARTBEAT_TIMEOUT → DEGRADED', color: C.warn},
  {t: 13.47, label: 'NORMAL 자동 복귀', color: C.normal},
  {t: 19.52, label: 'SAFE_MODE 즉시 전이', color: C.danger},
  {t: 26.16, label: '복구 요청 거부', color: C.danger},
  {t: 29.68, label: 'LEVEL 0 · 래치 유지', color: C.violet},
  {t: 35.64, label: 'NORMAL 승인', color: C.normal},
];

const T0 = 8.0;
const T1 = 37.4;
/** 눈금 위 라벨이 서로 닿지 않게 홀수 번째만 위로 올린다. */
const STAGGER = 26;

const Timeline: React.FC<{rise: number}> = ({rise}) => {
  const pos = (t: number) => ((t - T0) / (T1 - T0)) * 100;
  return (
    <div style={{opacity: rise, marginBottom: 10}}>
      <div style={{fontSize: 18, color: C.faint, letterSpacing: 0.5, marginBottom: 22}}>
        보드에서 실제로 기록된 순간 · 영상 재생 시각 기준
      </div>
      <div style={{position: 'relative', height: 112}}>
        <div style={{position: 'absolute', left: 0, right: 0, top: 60, height: 2, background: C.panelEdge}} />
        {MILESTONES.map((m, i) => {
          const up = i % 2 === 0 ? 0 : STAGGER;
          return (
            <div
              key={m.label}
              style={{
                position: 'absolute',
                left: `${pos(m.t)}%`,
                top: 0,
                transform: 'translateX(-50%)',
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                width: 260,
              }}
            >
              <div style={{height: 30 - up}} />
              <div style={{fontSize: 17, color: C.text, height: 22, whiteSpace: 'nowrap'}}>{m.label}</div>
              <div style={{width: 1, height: 8 + up, background: C.panelEdge}} />
              <div
                style={{
                  width: 13,
                  height: 13,
                  marginTop: -6,
                  borderRadius: 999,
                  background: m.color,
                  boxShadow: '0 0 0 5px #080B11',
                }}
              />
              <div style={{fontFamily: FONT_MONO, fontSize: 16, color: C.faint, marginTop: 10}}>
                {m.t.toFixed(2)}s
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};

export const Outro: React.FC<{dur: number}> = ({dur}) => {
  const f = useCurrentFrame();

  const rise = (delay: number) =>
    interpolate(f, [a(delay), a(delay + 18)], [0, 1], {
      easing: Easing.out(Easing.cubic),
      extrapolateLeft: 'clamp',
      extrapolateRight: 'clamp',
    });

  const inFade = interpolate(f, [0, a(12)], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const outFade = interpolate(f, [dur - a(20), dur], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});

  const members = CREDITS.members.filter((m) => m.name.trim() !== '');

  return (
    <AbsoluteFill
      style={{
        background: C.bg,
        fontFamily: FONT_SANS,
        padding: '78px 110px',
        opacity: Math.min(inFade, outFade),
      }}
    >
      <div style={{fontSize: 21, letterSpacing: 5, color: C.info, opacity: rise(0)}}>
        이 영상에서 확인한 내용
      </div>

      <div style={{marginTop: 34, display: 'flex', flexDirection: 'column', gap: 20}}>
        {CLAIMS.map((c, i) => {
          const p = rise(10 + i * 12);
          return (
            <div
              key={c.n}
              style={{
                display: 'flex',
                alignItems: 'baseline',
                gap: 20,
                opacity: p,
                transform: `translateX(${(1 - p) * -16}px)`,
              }}
            >
              <div style={{fontSize: 34, color: c.color, fontWeight: 700, width: 44}}>{c.n}</div>
              <div>
                <div style={{fontSize: 34, color: C.text, fontWeight: 700, letterSpacing: -0.6}}>{c.text}</div>
                <div style={{fontSize: 21, color: C.dim, marginTop: 5}}>{c.detail}</div>
              </div>
            </div>
          );
        })}
      </div>

      <div style={{flex: 1}} />

      <Timeline rise={rise(62)} />

      <div style={{flex: 1}} />

      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(4, 1fr)',
          gap: 18,
          opacity: rise(74),
        }}
      >
        {VERIFICATION.map((v) => (
          <div
            key={v.label}
            style={{
              background: C.panel,
              border: `1px solid ${C.panelEdge}`,
              borderRadius: 14,
              padding: '18px 22px',
            }}
          >
            <div style={{fontSize: 18, color: C.faint, letterSpacing: 0.5}}>{v.label}</div>
            <div style={{fontFamily: FONT_MONO, fontSize: 27, color: C.text, marginTop: 8, fontWeight: 700}}>
              {v.value}
            </div>
            {v.note ? (
              <div style={{fontFamily: FONT_MONO, fontSize: 15, color: C.dim, marginTop: 6, wordBreak: 'break-all'}}>
                {v.note}
              </div>
            ) : null}
          </div>
        ))}
      </div>

      <div
        style={{
          marginTop: 30,
          paddingTop: 22,
          borderTop: `1px solid ${C.panelEdge}`,
          display: 'flex',
          alignItems: 'center',
          gap: 30,
          opacity: rise(92),
          fontSize: 20,
          color: C.dim,
        }}
      >
        <div style={{fontWeight: 700, color: C.text, fontSize: 22}}>{CREDITS.title}</div>
        {members.map((m) => (
          <div key={m.role}>
            <span style={{color: C.text}}>{m.name}</span>
            <span style={{fontFamily: FONT_MONO, color: C.faint, marginLeft: 8, fontSize: 17}}>{m.role}</span>
          </div>
        ))}
        <div style={{flex: 1}} />
        {CREDITS.org ? <div style={{color: C.faint}}>{CREDITS.org}</div> : null}
        {CREDITS.date ? <div style={{color: C.faint}}>{CREDITS.date}</div> : null}
      </div>
    </AbsoluteFill>
  );
};
