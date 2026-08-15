import React from 'react';
import {Composition} from 'remotion';
import {TOTAL_FRAMES} from './data';
import {MissionSocDemo} from './MissionSocDemo';
import {FPS, H, W} from './theme';

export const RemotionRoot: React.FC = () => {
  return (
    <Composition
      id="MissionSocDemo"
      component={MissionSocDemo}
      durationInFrames={TOTAL_FRAMES}
      fps={FPS}
      width={W}
      height={H}
    />
  );
};
