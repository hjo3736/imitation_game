// 화면 구성 시안(회색조 배치도)을 SVG로 만드는 도구.
// 제품 코드가 아니다. design/layouts/ 아래의 시안 파일만 만든다.
// 실행: node design/layouts/_tools/build.mjs   (저장소 루트에서)
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const OUT = join(dirname(fileURLToPath(import.meta.url)), '..');

// ---- 시트의 틀 -------------------------------------------------------------
const CW = 2760, CH = 1700;      // 시트 전체
const MX = 40, MY = 130;         // 1920x1080 본 그림의 왼쪽 위
const GW = 1920, GH = 1080;      // 보장 영역
const RX = 2000, RW = 720;       // 오른쪽 설명 칸
const FONT = "'Malgun Gothic','맑은 고딕','Noto Sans KR',sans-serif";

const STYLE = {
  done:  { fill: '#cfcfcf', stroke: '#222', sw: 4, dash: '' },
  slot:  { fill: '#ffffff', stroke: '#555', sw: 3, dash: '14 8' },
  new:   { fill: '#cfcfcf', stroke: '#222', sw: 3, dash: '14 8' },
  bar:   { fill: '#f2f2f2', stroke: '#888', sw: 2, dash: '' },
  frame: { fill: 'none',    stroke: '#888', sw: 2, dash: '' },
  ui:    { fill: '#f2f2f2', stroke: '#999', sw: 2, dash: '4 6' },
};

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const textWidth = (s, fs) => [...s].reduce((a, c) => a + (c.charCodeAt(0) > 0x2000 ? fs : fs * 0.56), 0);

function rect(x, y, w, h, st, extra = '') {
  const s = STYLE[st];
  const dash = s.dash ? ` stroke-dasharray="${s.dash}"` : '';
  return `<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${s.fill}" stroke="${s.stroke}" stroke-width="${s.sw}"${dash}${extra}/>`;
}

function text(x, y, s, fs = 26, anchor = 'middle', fill = '#111', weight = 'normal') {
  return `<text x="${x}" y="${y}" font-size="${fs}" text-anchor="${anchor}" fill="${fill}" font-weight="${weight}">${esc(s)}</text>`;
}

const warnings = [];

// 요소 하나를 본 그림(1920x1080 좌표)에 그린다.
function drawElement(e, sheetName) {
  const out = [rect(e.x, e.y, e.w, e.h, e.st)];
  if (!e.label) return out.join('');
  const fs = e.fs || 26;
  const lh = Math.round(fs * 1.3);
  const lines = e.label.split('\n');
  if (e.head) {
    lines.forEach((ln, i) => out.push(text(e.x + 16, e.y + 14 + fs + i * lh, ln, fs, 'start', '#444')));
  } else {
    const top = e.y + e.h / 2 - (lines.length * lh) / 2 + fs * 0.95;
    lines.forEach((ln, i) => {
      if (textWidth(ln, fs) > e.w - 8) warnings.push(`${sheetName}: "${ln}" 가 상자 너비(${e.w})를 넘는다`);
      out.push(text(e.x + e.w / 2, top + i * lh, ln, fs));
    });
    if (lines.length * lh > e.h) warnings.push(`${sheetName}: "${lines[0]}" 가 상자 높이(${e.h})를 넘는다`);
  }
  return out.join('');
}

// 화면비가 달라졌을 때 요소가 놓이는 자리. ax: L/C/R/S, ay: T/C/B/S
function place(e, vw, vh) {
  const dx = (vw - GW) / 2, dy = (vh - GH) / 2;
  let { x, y, w, h } = e;
  const ax = e.ax || 'C', ay = e.ay || 'C';
  if (ax === 'C') x += dx; else if (ax === 'R') x += 2 * dx; else if (ax === 'S') w += 2 * dx;
  if (ay === 'C') y += dy; else if (ay === 'B') y += 2 * dy; else if (ay === 'S') h += 2 * dy;
  return { x, y, w, h };
}

// 작은 그림(다른 화면비). 선 굵기는 시트 좌표로 2 이상.
function thumb(els, ox, oy, vw, vh, s, caption) {
  const dx = (vw - GW) / 2, dy = (vh - GH) / 2;
  const o = [text(ox, oy - 14, caption, 24, 'start')];
  o.push(`<rect x="${ox}" y="${oy}" width="${vw * s}" height="${vh * s}" fill="#e4e4e4" stroke="#222" stroke-width="3"/>`);
  o.push(`<rect x="${ox + dx * s}" y="${oy + dy * s}" width="${GW * s}" height="${GH * s}" fill="#fafafa" stroke="#222" stroke-width="2" stroke-dasharray="10 6"/>`);
  for (const e of els) {
    const p = place(e, vw, vh);
    const st = STYLE[e.st];
    const fill = e.st === 'frame' ? 'none' : (e.st === 'done' || e.st === 'new') ? '#8c8c8c' : st.fill;
    const dash = st.dash ? ' stroke-dasharray="6 4"' : '';
    o.push(`<rect x="${(ox + p.x * s).toFixed(1)}" y="${(oy + p.y * s).toFixed(1)}" width="${(p.w * s).toFixed(1)}" height="${(p.h * s).toFixed(1)}" fill="${fill}" stroke="${st.stroke}" stroke-width="2"${dash}/>`);
  }
  return o.join('');
}

// 다른 면(시안 5)처럼 본 그림을 줄여서 이름표와 함께 그린다.
function mini(els, ox, oy, s, caption) {
  const o = [text(ox, oy - 14, caption, 24, 'start')];
  o.push(`<rect x="${ox}" y="${oy}" width="${GW * s}" height="${GH * s}" fill="#fafafa" stroke="#222" stroke-width="3"/>`);
  for (const e of els) {
    const st = STYLE[e.st];
    const dash = st.dash ? ' stroke-dasharray="8 5"' : '';
    const x = ox + e.x * s, y = oy + e.y * s, w = e.w * s, h = e.h * s;
    o.push(`<rect x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${w.toFixed(1)}" height="${h.toFixed(1)}" fill="${st.fill}" stroke="${st.stroke}" stroke-width="2"${dash}/>`);
    if (e.mini) e.mini.split('\n').forEach((ln, i, a) => o.push(text(x + w / 2, y + h / 2 - (a.length * 28) / 2 + 22 + i * 28, ln, 22)));
  }
  return o.join('');
}

function wrap(s, fs, maxw) {
  const lines = []; let cur = '';
  for (const word of s.split(' ')) {
    const t = cur ? cur + ' ' + word : word;
    if (textWidth(t, fs) > maxw && cur) { lines.push(cur); cur = word; } else cur = t;
  }
  if (cur) lines.push(cur);
  return lines;
}

function legend(x, y) {
  const rows = [
    ['done', '구현됨 (지금 동작한다)'],
    ['slot', '자리만 (눌러도 동작하지 않는다)'],
    ['new', '기능은 구현됨, 화면의 버튼은 새로 만든다'],
    ['ui', '공통 UI가 놓일 자리 (공방 시트)'],
    ['frame', '묶음의 테두리 (요소가 아니다)'],
  ];
  const o = [text(x, y, '표시', 28, 'start', '#111', 'bold')];
  rows.forEach(([st, label], i) => {
    const yy = y + 20 + i * 54;
    o.push(rect(x, yy, 84, 40, st));
    o.push(text(x + 100, yy + 29, label, 24, 'start'));
  });
  return o.join('');
}

function sheet({ file, title, sub, els, notes, faces }) {
  const o = [];
    o.push(text(MX, 62, title, 44, 'start', '#111', 'bold'));
  o.push(text(MX, 104, sub, 26, 'start', '#444'));
  // 본 그림
  o.push(`<g transform="translate(${MX},${MY})">`);
  o.push(`<rect x="0" y="0" width="${GW}" height="${GH}" fill="#fafafa"/>`);
  for (const e of els) o.push(drawElement(e, file));
  o.push(`<rect x="0" y="0" width="${GW}" height="${GH}" fill="none" stroke="#000" stroke-width="4"/>`);
  o.push(`</g>`);
  o.push(text(MX + GW, MY + GH + 34, '굵은 테두리 = 보장 영역 1920×1080 (16:9에서는 화면 전체)', 24, 'end', '#444'));
  // 다른 화면비
  const ty = MY + GH + 110;
  o.push(thumb(els, MX, ty, 2520, 1080, 0.3, '21:9 (2520×1080) — 점선이 보장 영역, 바깥은 배경'));
  o.push(thumb(els, MX + 900, ty, 1920, 1200, 0.3, '16:10 (1920×1200) — 위아래로 60씩 넓어진다'));
  // 오른쪽 칸
  o.push(legend(RX, MY + 24));
  let ny = MY + 340;
  if (faces) {
    for (const f of faces) { o.push(mini(f.els, RX, ny + 30, 0.33, f.caption)); ny += GH * 0.33 + 70; }
    ny += 10;
  }
  o.push(text(RX, ny + 24, '메모', 28, 'start', '#111', 'bold'));
  ny += 66;
  for (const n of notes) {
    const lines = wrap('· ' + n, 24, RW - 10);
    lines.forEach((ln) => { o.push(text(RX, ny, ln, 24, 'start')); ny += 34; });
    ny += 10;
  }
  const ch = Math.max(CH, Math.ceil(ny) + 20); // 메모가 길면 시트를 아래로 늘린다
  o.unshift(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${CW} ${ch}" width="${CW}" height="${ch}" font-family="${FONT}">`, `<rect width="${CW}" height="${ch}" fill="#ffffff"/>`);
  o.push('</svg>');
  const path = join(OUT, file);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, o.join('\n'), 'utf8');
}

// ---- 공통 UI 다섯 가지 -------------------------------------------------------
// 숫자와 글자는 자리를 보여 주는 예시다.
const E = (id, label, x, y, w, h, st, ax = 'C', ay = 'C', more = {}) => ({ id, label, x, y, w, h, st, ax, ay, ...more });
const HINT = E('hint', '공방 화면 (공방 시트에서 고른다)', 560, 480, 800, 120, 'frame', 'C', 'C', { fs: 30, hint: true });

const UI = {
  1: {
    name: '네 모서리', els: [
      E('time', '1일차 · 남은 시간 9분 59초', 24, 16, 420, 72, 'done', 'L', 'T'),
      E('rep', '평판 00', 1356, 16, 220, 72, 'slot', 'R', 'T'),
      E('money', '보유 금액 0,000 G', 1588, 16, 308, 72, 'slot', 'R', 'T'),
      E('notice', '알림 (예: 판매 완료)', 24, 996, 480, 72, 'slot', 'L', 'B'),
      E('menu', '메뉴', 1764, 996, 132, 72, 'new', 'R', 'B'),
    ],
    notes: [
      '생각: 화면 가운데를 비우고 정보를 네 모서리에 작게 나눠 둔다. 왼쪽 위는 시간, 오른쪽 위는 돈과 평판, 왼쪽 아래는 알림, 오른쪽 아래는 메뉴.',
      '화면비: 네 덩어리가 각자의 모서리를 따라간다. 21:9에서는 좌우로 300씩, 16:10에서는 위아래로 60씩 벌어진다.',
      '요소가 빠지거나 더해지면: 모서리의 덩어리 안에서 옆으로 줄이거나 늘린다. 한 모서리에 셋을 넘기면 좁아진다.',
      '알림이 몇 건까지 쌓여 보이는지는 정해지지 않았다. 한 건의 자리만 그렸다.',
    ],
  },
  2: {
    name: '상단 띠', els: [
      E('bar', '', 0, 0, 1920, 80, 'bar', 'S', 'T'),
      E('day', '1일차', 24, 8, 150, 64, 'done', 'L', 'T'),
      E('time', '남은 시간 9분 59초 ▬▬▬▬', 186, 8, 440, 64, 'done', 'L', 'T'),
      E('notice', '알림 한 줄 (예: 판매 완료)', 660, 8, 600, 64, 'slot', 'C', 'T'),
      E('rep', '평판 00', 1300, 8, 200, 64, 'slot', 'R', 'T'),
      E('money', '보유 금액 0,000 G', 1512, 8, 280, 64, 'slot', 'R', 'T'),
      E('menu', '메뉴', 1804, 8, 92, 64, 'new', 'R', 'T'),
    ],
    notes: [
      '생각: 모든 정보를 위쪽 띠 하나에 한 줄로 모은다. 눈이 갈 곳이 한 군데다.',
      '화면비: 띠는 실제 화면의 위쪽 끝에 붙어 좌우로 늘어난다. 왼쪽 묶음은 왼쪽 끝, 오른쪽 묶음은 오른쪽 끝, 알림은 가운데를 따라간다.',
      '요소가 빠지거나 더해지면: 띠 안의 칸을 하나 빼거나 끼운다. 가운데 알림 칸이 줄어들며 받아 준다.',
      '알림이 띠 안에 있어 공방 화면을 가리지 않는다. 긴 알림은 한 줄로 줄여야 한다.',
    ],
  },
  3: {
    name: '하단 띠', els: [
      E('bar', '', 0, 992, 1920, 88, 'bar', 'S', 'B'),
      E('day', '1일차', 24, 1004, 150, 64, 'done', 'L', 'B'),
      E('time', '남은 시간 9분 59초 ▬▬▬▬▬▬▬▬', 186, 1004, 560, 64, 'done', 'L', 'B'),
      E('notice', '알림이 한 줄씩 지나간다', 770, 1004, 520, 64, 'slot', 'C', 'B'),
      E('rep', '평판 00', 1314, 1004, 200, 64, 'slot', 'R', 'B'),
      E('money', '보유 금액 0,000 G', 1526, 1004, 266, 64, 'slot', 'R', 'B'),
      E('menu', '메뉴', 1804, 1004, 92, 64, 'new', 'R', 'B'),
    ],
    notes: [
      '생각: 정보를 아래쪽 띠에 두고 위쪽을 통째로 비운다. 남은 시간을 긴 막대로 그려 하루가 줄어드는 것이 보이게 한다.',
      '화면비: 띠는 실제 화면의 아래쪽 끝에 붙어 좌우로 늘어난다. 16:10에서는 60만큼 내려간다.',
      '요소가 빠지거나 더해지면: 띠 안의 칸을 하나 빼거나 끼운다. 시간 막대와 알림 칸이 줄어들며 받아 준다.',
      '마우스가 주로 아래쪽에 머무는 화면(아래에 버튼이 많은 공방)과 함께 쓰면 손이 덜 움직인다.',
    ],
  },
  4: {
    name: '왼쪽 레일', els: [
      E('bar', '', 0, 0, 200, 1080, 'bar', 'L', 'S'),
      E('day', '1일차', 16, 16, 168, 72, 'done', 'L', 'T'),
      E('time', '남은 시간\n9분 59초\n(세로 막대)', 16, 104, 168, 380, 'done', 'L', 'T'),
      E('money', '보유 금액\n0,000 G', 16, 500, 168, 88, 'slot', 'L', 'T'),
      E('rep', '평판\n00', 16, 604, 168, 88, 'slot', 'L', 'T'),
      E('notice', '알림 (0)', 16, 708, 168, 88, 'slot', 'L', 'T'),
      E('fly', '알림 내용이 옆으로 펼쳐진다\n(뜰 때만 보인다)', 216, 708, 440, 88, 'slot', 'L', 'T', { transient: true }),
      E('menu', '메뉴', 16, 976, 168, 88, 'new', 'L', 'B'),
    ],
    notes: [
      '생각: 왼쪽에 세로 기둥을 세워 정보를 위에서 아래로 쌓는다. 남은 시간은 세로 막대로 줄어든다. 공방은 그 오른쪽 전부를 쓴다.',
      '화면비: 기둥은 실제 화면의 왼쪽 끝에 붙어 위아래로 늘어난다. 21:9에서는 기둥과 공방 사이가 벌어진다.',
      '요소가 빠지거나 더해지면: 기둥에 칸을 하나 빼거나 쌓는다. 시간 막대의 길이가 줄어들며 받아 준다.',
      '알림은 기둥의 칸에서 오른쪽으로 펼쳐지므로, 뜨는 동안 공방의 왼쪽 일부를 가린다.',
      '공방이 쓸 수 있는 너비가 200 줄어든다. 공방 시트 ④는 이 기둥을 전제로 그렸다.',
    ],
  },
  5: {
    name: '가운데 시계', els: [
      E('bar', '', 548, 8, 824, 88, 'bar', 'C', 'T'),
      E('rep', '평판 00', 560, 20, 210, 64, 'slot', 'C', 'T'),
      E('time', '1일차 · 9분 59초', 782, 12, 356, 80, 'done', 'C', 'T', { fs: 30 }),
      E('money', '0,000 G', 1150, 20, 210, 64, 'slot', 'C', 'T'),
      E('banner', '알림이 시계 아래로 내려온다 (뜰 때만)', 660, 104, 600, 64, 'slot', 'C', 'T', { transient: true }),
      E('menu', '메뉴', 1804, 16, 92, 64, 'new', 'R', 'T'),
    ],
    notes: [
      '생각: 하루의 시계를 화면 위쪽 가운데에 가장 크게 두고, 돈과 평판을 그 양옆에 붙인다. 시간에 쫓기는 느낌을 앞세운다.',
      '화면비: 뭉치는 항상 가운데에 있어 화면이 넓어져도 자리가 변하지 않는다. 메뉴만 오른쪽 위 끝을 따라간다.',
      '요소가 빠지거나 더해지면: 뭉치의 양옆에 칸을 붙이거나 뗀다. 좌우 균형이 맞아야 해서 홀수 개가 되면 어색하다.',
      '알림은 시계 아래로 내려왔다가 사라지므로, 뜨는 동안 공방의 위쪽 가운데를 가린다.',
      '좌우 가장자리와 아래쪽이 모두 비어, 가장자리를 쓰는 공방(시트 ⑤)과 잘 맞는다.',
    ],
  },
};

// ---- 공방 화면 다섯 가지 -----------------------------------------------------
const BANDS = [
  E('uitop', '공통 UI가 놓일 자리 (위 104)', 0, 0, 1920, 104, 'ui', 'S', 'T', { fs: 24 }),
  E('uibot', '공통 UI가 놓일 자리 (아래 96)   ·   공통 UI ④(왼쪽 레일)를 고르면 왼쪽 200도 쓴다', 0, 984, 1920, 96, 'ui', 'S', 'B', { fs: 24 }),
];

const WS = {
  1: {
    name: '한 장의 방', els: [
      E('door', '문\n(하루 끝내기)', 80, 240, 260, 660, 'done'),
      E('plate', '명패', 130, 320, 160, 96, 'done'),
      E('req', '의뢰 게시판\n새 의뢰 표시\n의뢰 목록으로', 400, 190, 300, 230, 'slot'),
      E('pick', '원작 화집 선반\n원작 선택으로', 750, 150, 430, 200, 'slot'),
      E('upg', '도구장\n업그레이드로', 1230, 150, 300, 230, 'slot'),
      E('bench', '작업대 (이젤)\n진행 중인 작품\n공정 진행 표시', 640, 420, 620, 500, 'slot'),
      E('store', '완성작 보관함 (선반)', 1320, 430, 520, 260, 'slot'),
      E('sell', '판매 창구\n판매 경로 선택으로 · 판매 현황으로', 1320, 720, 520, 200, 'slot'),
    ],
    notes: [
      '생각: 공방을 한 장의 방으로 보고, 방 안의 물건을 눌러 들어간다. 문, 게시판, 선반, 이젤, 도구장이 곧 입구다.',
      '하루의 움직임: 왼쪽 문 옆 게시판에서 의뢰를 보고, 가운데 이젤에서 만들고, 오른쪽 선반과 창구로 넘긴다. 하루가 끝나면 다시 왼쪽 문으로 간다.',
      '화면비: 물건은 모두 보장 영역 안에 있고 가운데에 고정된다. 넓어진 곳은 방의 벽과 바닥(배경)이 채운다.',
      '요소가 빠지거나 더해지면: 물건 하나를 치우거나 놓는다. 방에 빈 벽이 남아 있어 두세 개까지는 받는다. 그 이상이면 방이 비좁다.',
      '물건의 상자는 누를 수 있는 범위다. 그림을 입힐 때 그림이 이 범위를 따라야 한다.',
    ],
  },
  2: {
    name: '목록과 패널', els: [
      E('req', '의뢰\n새 의뢰 표시 · 대기 중인 의뢰 요약\n[ 의뢰 목록으로 ]', 40, 112, 560, 560, 'slot'),
      E('pick', '원작 선택\n[ 원작 선택으로 ]', 40, 696, 560, 280, 'slot'),
      E('bench', '작업대\n진행 중인 작품 · 공정 진행 표시\n[ 작업 이어 하기 ]', 624, 112, 672, 864, 'slot'),
      E('store', '완성작 보관함\n완성작 목록 (줄 수는 미정)', 1320, 112, 560, 400, 'slot'),
      E('sell', '판매\n[ 판매 경로 선택으로 ]\n[ 판매 현황으로 ]', 1320, 536, 560, 248, 'slot'),
      E('upg', '업그레이드로', 1320, 808, 268, 168, 'slot'),
      E('door', '문 · 명패\n(하루 끝내기)', 1612, 808, 268, 168, 'done'),
    ],
    notes: [
      '생각: 공방을 그림이 아니라 상황판으로 본다. 요소마다 패널 하나를 주고, 패널 안에 지금 상태를 글과 목록으로 적는다.',
      '하루의 움직임: 눈은 세 단을 훑어 상태를 읽고, 마우스는 필요한 패널의 버튼으로 바로 간다. 다른 화면에 들어가지 않고도 대부분의 상태가 보인다.',
      '화면비: 세 단은 가운데에 고정된다. 넓어진 곳은 배경이 채운다.',
      '요소가 빠지거나 더해지면: 패널을 하나 빼면 같은 단의 패널이 늘어나 메우고, 더하면 단을 나눈다. 다섯 가운데 가장 잘 받는다.',
      '패널 안에 몇 줄을 보일지는 정해지지 않았다. 목록의 자리만 그렸다.',
    ],
  },
  3: {
    name: '흐름 구역', els: [
      E('z1', '① 받기', 40, 112, 380, 864, 'frame', 'C', 'C', { head: true, fs: 28 }),
      E('z2', '② 만들기', 445, 112, 520, 864, 'frame', 'C', 'C', { head: true, fs: 28 }),
      E('z3', '③ 보관', 990, 112, 300, 864, 'frame', 'C', 'C', { head: true, fs: 28 }),
      E('z4', '④ 팔기', 1315, 112, 300, 864, 'frame', 'C', 'C', { head: true, fs: 28 }),
      E('z5', '그 밖', 1640, 112, 240, 864, 'frame', 'C', 'C', { head: true, fs: 28 }),
      E('req', '의뢰\n새 의뢰 표시\n의뢰 목록으로', 60, 180, 340, 380, 'slot'),
      E('pick', '원작 선택으로', 60, 580, 340, 376, 'slot'),
      E('bench', '작업대\n진행 중인 작품\n공정 진행 표시', 465, 180, 480, 776, 'slot'),
      E('store', '완성작\n보관함', 1010, 180, 260, 776, 'slot'),
      E('sell', '판매\n경로 선택으로\n판매 현황으로', 1335, 180, 260, 776, 'slot'),
      E('upg', '업그레이드로', 1660, 180, 200, 380, 'slot'),
      E('door', '문 · 명패\n(하루 끝내기)', 1660, 580, 200, 376, 'done'),
    ],
    notes: [
      '생각: 화면을 작품 하나가 지나가는 순서대로 왼쪽에서 오른쪽으로 나눈다. 받기 → 만들기 → 보관 → 팔기. 화면이 곧 게임의 순환을 설명한다.',
      '하루의 움직임: 눈과 마우스가 왼쪽에서 오른쪽으로 한 번 흐르고, 다음 작품에서 다시 왼쪽으로 돌아온다. 하루 끝내기는 오른쪽 끝에 있다.',
      '화면비: 다섯 구역은 가운데에 고정된다. 넓어진 곳은 배경이 채운다.',
      '요소가 빠지거나 더해지면: 흐름의 한 단계에 속하는 것은 그 구역에 쌓으면 된다. 흐름에 속하지 않는 것은 ‘그 밖’ 구역에 몰려 그 구역이 먼저 찬다.',
      '구역의 너비가 고정이라, 한 구역의 내용이 많아지면(예: 보관함) 세로로 길어진다.',
    ],
  },
  4: {
    name: '작업대 중심', els: [
      E('bench', '작업대 — 진행 중인 작품을 크게 보여 준다\n공정 진행 표시\n[ 작업 이어 하기 ]', 224, 112, 1340, 660, 'slot', 'C', 'C', { fs: 30 }),
      E('door', '문 · 명패\n(하루 끝내기)', 1588, 112, 292, 660, 'done'),
      E('req', '의뢰\n(새 의뢰 표시)', 224, 800, 312, 176, 'slot'),
      E('pick', '원작 선택', 560, 800, 312, 176, 'slot'),
      E('store', '완성작 보관함', 896, 800, 312, 176, 'slot'),
      E('sell', '판매', 1232, 800, 312, 176, 'slot'),
      E('upg', '업그레이드', 1568, 800, 312, 176, 'slot'),
    ],
    notes: [
      '생각: 공방의 주인공은 지금 만들고 있는 작품 하나다. 작업대를 화면의 대부분으로 키우고, 나머지는 아래에 한 줄의 큰 버튼으로 모은다.',
      '하루의 움직임: 눈은 가운데 작품에 머물고, 마우스는 아래 줄에서 좌우로만 움직인다. 버튼의 순서가 곧 작업의 순서다.',
      '화면비: 작업대와 버튼 줄은 가운데에 고정된다. 넓어진 곳은 배경이 채운다.',
      '요소가 빠지거나 더해지면: 아래 줄의 버튼을 하나 빼거나 끼우고 너비를 다시 나눈다. 일곱 개까지는 한 줄에 들어간다.',
      '왼쪽 200을 비워 두었다(공통 UI ④의 자리). 다른 공통 UI와 쓸 때는 전체를 왼쪽으로 100 옮겨 가운데에 맞춘다.',
      '아래 줄의 버튼에는 상태를 한두 마디밖에 적지 못한다. 자세한 것은 들어가서 본다.',
    ],
  },
  5: {
    name: '넘기는 방', els: [
      E('left', '◀\n응접 면\n새 의뢰\n표시', 40, 420, 124, 240, 'slot', 'L', 'C'),
      E('pick', '원작 화집 선반\n원작 선택으로', 220, 200, 300, 660, 'slot'),
      E('bench', '작업대 (이젤)\n진행 중인 작품\n공정 진행 표시', 580, 150, 760, 760, 'slot'),
      E('upg', '도구장\n업그레이드로', 1400, 200, 300, 660, 'slot'),
      E('right', '▶\n창고 면\n판매\n현황', 1756, 420, 124, 240, 'slot', 'R', 'C'),
      E('dots', '면 표시  ○ ● ○', 840, 924, 240, 48, 'slot', 'C', 'C', { fs: 24 }),
    ],
    faces: [
      {
        caption: '왼쪽 면 — 응접 면', els: [
          E('door', '', 260, 200, 320, 720, 'done', 'C', 'C', { mini: '문\n명패' }),
          E('req', '', 700, 200, 760, 500, 'slot', 'C', 'C', { mini: '의뢰 게시판\n의뢰 목록으로' }),
          E('right', '', 1756, 420, 124, 240, 'slot', 'R', 'C', { mini: '▶' }),
        ],
      },
      {
        caption: '오른쪽 면 — 창고 면', els: [
          E('left', '', 40, 420, 124, 240, 'slot', 'L', 'C', { mini: '◀' }),
          E('store', '', 240, 180, 820, 740, 'slot', 'C', 'C', { mini: '완성작 보관함' }),
          E('sell', '', 1120, 180, 560, 740, 'slot', 'C', 'C', { mini: '판매 창구\n경로 선택 · 현황' }),
        ],
      },
    ],
    notes: [
      '생각: 공방을 화면 세 장 너비의 방으로 보고, 좌우 화살표로 면을 넘긴다. 한 면에 물건이 적어 크게 놓인다. 큰 그림은 가운데 면(작업 면)이다.',
      '하루의 움직임: 가운데 면에서 만들고, 왼쪽 면에서 의뢰를 받고 하루를 끝내며, 오른쪽 면에서 보관하고 판다. 면을 넘기는 클릭이 한 번씩 더 든다.',
      '화면비: 화살표는 실제 화면의 좌우 끝을 따라가고, 물건은 가운데에 고정된다.',
      '요소가 빠지거나 더해지면: 면에 빈 곳이 많아 잘 받는다. 많아지면 면을 하나 더 늘릴 수 있다.',
      '보이지 않는 면의 소식(새 의뢰, 판매 현황)은 화살표에 표시해야 놓치지 않는다. 문이 다른 면에 있어 하루 끝내기가 한 걸음 멀다.',
    ],
  },
};

const DIR = { 1: '01_room', 2: '02_panels', 3: '03_flow', 4: '04_bench', 5: '05_faces' };
const NUM = ['', '①', '②', '③', '④', '⑤'];

for (const n of [1, 2, 3, 4, 5]) {
  const u = UI[n], w = WS[n];
  const hint = { ...HINT, y: n === 3 ? 440 : 480 };
  sheet({
    file: `${DIR[n]}/ui.svg`,
    title: `시안 ${n} — 공통 UI ${NUM[n]} ${u.name}`,
    sub: '여러 화면에 걸쳐 늘 보이는 요소의 배치. 회색조 배치도이며 숫자와 글자는 자리를 보여 주는 예시다.',
    els: [hint, ...u.els], notes: u.notes,
  });
  sheet({
    file: `${DIR[n]}/workshop.svg`,
    title: `시안 ${n} — 공방 화면 ${NUM[n]} ${w.name}`,
    sub: '공방 화면 고유의 배치. 공통 UI의 자리는 비워 두고 윤곽만 그렸다. 숫자와 글자는 자리를 보여 주는 예시다.',
    els: [...BANDS, ...w.els], notes: w.notes, faces: w.faces,
  });
}

// ---- 한꺼번에 보는 쪽 ---------------------------------------------------------
const rows = [1, 2, 3, 4, 5].map((n) => `
<h2>시안 ${n} — 공통 UI ${NUM[n]} ${UI[n].name} / 공방 화면 ${NUM[n]} ${WS[n].name}</h2>
<p><a href="${DIR[n]}/ui.svg">ui.svg</a> · <a href="${DIR[n]}/workshop.svg">workshop.svg</a></p>
<img src="${DIR[n]}/ui.svg" alt="시안 ${n} 공통 UI"><img src="${DIR[n]}/workshop.svg" alt="시안 ${n} 공방 화면">`).join('\n');
writeFileSync(join(OUT, 'index.html'), `<!doctype html>
<html lang="ko"><head><meta charset="utf-8"><title>화면 구성 시안 5가지</title>
<style>body{font-family:'Malgun Gothic',sans-serif;margin:24px;background:#fff;color:#111}
img{width:100%;max-width:1800px;display:block;border:2px solid #888;margin:12px 0 32px}
h2{margin-top:48px}</style></head><body>
<h1>화면 구성 시안 5가지 (회색조 배치도)</h1>
<p>공통 UI와 공방 화면은 서로 다른 시안에서 골라 조합할 수 있다. 조합표와 설명은 docs/roles/designer/outputs/15_화면구성_시안.md에 있다.</p>
${rows}
</body></html>
`, 'utf8');

// ---- 조합 확인: 공통 UI의 자리와 공방 요소가 겹치는가 ---------------------------
const hit = (a, b) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
console.log('조합 (공통 UI × 공방 화면): 겹치는 요소');
for (const un of [1, 2, 3, 4, 5]) for (const wn of [1, 2, 3, 4, 5]) {
  const hits = [];
  for (const a of UI[un].els) for (const b of WS[wn].els) {
    if (b.st === 'frame') continue;
    if (hit(a, b)) hits.push(`${a.id}${a.transient ? '(뜰 때만)' : ''}×${b.id}`);
  }
  console.log(`UI${un} × W${wn}: ${hits.length ? hits.join(', ') : '겹침 없음'}`);
}
if (warnings.length) { console.log('\n경고'); warnings.forEach((w) => console.log(' - ' + w)); }
