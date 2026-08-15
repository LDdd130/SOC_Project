// mission_events CSV -> src/cues.json
//
// 촬영 로그의 벽시계 시각을 demo.mp4 의 재생 시각으로 옮긴다.
// ANCHOR 는 영상 t=0 에 해당하는 벽시계 시각이다. 값의 근거는 README_VIDEO.md 참조.
//
//   video_t = (수신 벽시계) - ANCHOR
//
// 검증: 화면상 `고장 등급` 줄이 실제로 바뀐 프레임(ffmpeg scene detect)과
//       아래 STATE_CHANGE/FAULT_CHANGE 이벤트가 ±0.16초 안에서 일치한다.

import {readFileSync, writeFileSync} from 'node:fs';
import {dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const CSV = resolve(here, '../../mission_events_20260810_113104.csv');
const OUT = resolve(here, '../src/cues.json');

const ANCHOR = '2026-08-10T11:30:19.320';

// 영상에 남길 메시지 종류. MISSION 은 550ms 주기라 너무 잦아서 뺀다.
const KEEP = new Set(['TX', 'ACK', 'ERR', 'EVENT']);

const parseCsv = (text) => {
  const rows = [];
  let row = [];
  let field = '';
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i++;
        } else {
          quoted = false;
        }
      } else {
        field += c;
      }
      continue;
    }
    if (c === '"') {
      quoted = true;
    } else if (c === ',') {
      row.push(field);
      field = '';
    } else if (c === '\n') {
      row.push(field);
      rows.push(row);
      row = [];
      field = '';
    } else if (c !== '\r') {
      field += c;
    }
  }
  if (field.length > 0 || row.length > 0) {
    row.push(field);
    rows.push(row);
  }
  return rows;
};

const text = readFileSync(CSV, 'utf8');
const rows = parseCsv(text);
const header = rows[0];
const idx = Object.fromEntries(header.map((h, i) => [h, i]));

const anchorMs = Date.parse(ANCHOR);
if (Number.isNaN(anchorMs)) {
  throw new Error(`ANCHOR 파싱 실패: ${ANCHOR}`);
}

const cues = [];
for (const r of rows.slice(1)) {
  if (r.length < header.length) continue;
  const type = r[idx.message_type];
  if (!KEEP.has(type)) continue;

  const received = r[idx.received_at];
  const ms = Date.parse(received);
  if (Number.isNaN(ms)) continue;

  const t = (ms - anchorMs) / 1000;
  if (t < 0) continue;

  cues.push({
    t: Number(t.toFixed(3)),
    type,
    event: r[idx.event_type] || '',
    desc: r[idx.description] || '',
    raw: r[idx.raw_line] || '',
    state: r[idx.state] || '',
    level: r[idx.fault_level] || '',
  });
}

cues.sort((a, b) => a.t - b.t);
writeFileSync(OUT, `${JSON.stringify(cues, null, 2)}\n`);

console.log(`${cues.length} cues -> ${OUT}`);
console.log(`t 범위: ${cues[0].t}s ~ ${cues[cues.length - 1].t}s`);
for (const c of cues) {
  console.log(`  ${String(c.t).padStart(7)}  ${c.type.padEnd(6)} ${c.raw}`);
}
