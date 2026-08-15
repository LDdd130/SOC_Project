import React from 'react';
import {AbsoluteFill, Img, OffthreadVideo, Sequence, staticFile, useCurrentFrame} from 'remotion';
import {BottomBar} from './components/BottomBar';
import {TopBar} from './components/TopBar';
import {Viewport} from './components/Viewport';
import {SEGMENTS, STARTS, type Segment} from './data';
import {focusAt} from './geometry';
import {Intro} from './scenes/Intro';
import {Outro} from './scenes/Outro';
import {C, FPS, SRC_H, SRC_W} from './theme';

const SegmentView: React.FC<{seg: Segment}> = ({seg}) => {
  const local = useCurrentFrame();

  if (seg.kind === 'intro') return <Intro dur={seg.dur} />;
  if (seg.kind === 'outro') return <Outro dur={seg.dur} />;

  const p = seg.dur <= 1 ? 1 : local / (seg.dur - 1);
  const transform = focusAt(seg.focus, p);

  const srcTime =
    seg.kind === 'motion' ? seg.srcStart + (local / FPS) * seg.rate : seg.srcTime;

  const media =
    seg.kind === 'motion' ? (
      <OffthreadVideo
        src={staticFile('demo_cfr.mp4')}
        trimBefore={Math.round(seg.srcStart * FPS)}
        playbackRate={seg.rate}
        muted
        style={{width: SRC_W, height: SRC_H}}
      />
    ) : (
      <Img src={staticFile(`stills/${seg.still}.png`)} style={{width: SRC_W, height: SRC_H}} />
    );

  return (
    <AbsoluteFill style={{background: C.bg}}>
      <TopBar cut={seg.cut} />
      <Viewport transform={transform} callouts={seg.callouts} local={local}>
        {media}
      </Viewport>
      <BottomBar cut={seg.cut} chip={seg.chip} lines={seg.lines} srcTime={srcTime} local={local} />
    </AbsoluteFill>
  );
};

export const MissionSocDemo: React.FC = () => {
  return (
    <AbsoluteFill style={{background: C.bg}}>
      {SEGMENTS.map((seg, i) => (
        <Sequence key={seg.id} from={STARTS[i]} durationInFrames={seg.dur} name={seg.id}>
          <SegmentView seg={seg} />
        </Sequence>
      ))}
    </AbsoluteFill>
  );
};
