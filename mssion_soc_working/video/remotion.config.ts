import {Config} from '@remotion/cli/config';

Config.setVideoImageFormat('jpeg');
Config.setCodec('h264');
Config.setCrf(18);
// 이 머신은 RAM 이 15GB 이고 Vivado 가 크게 잡아먹는다. 동시 실행 브라우저 탭을 제한한다.
Config.setConcurrency(2);
Config.setChromiumOpenGlRenderer('angle');
