// 고른 배치(공통 UI ① + 공방 ①, 사용자가 고친 판)의 확정 배치도를 SVG로 만드는 도구.
// 제품 코드가 아니다. design/layouts/final/ 아래의 파일만 만든다.
// 실행: node design/layouts/_tools/build_final.mjs   (저장소 루트에서)
// 좌표의 근거는 docs/roles/designer/outputs/16_화면_명세.md 다. 값을 바꾸면 두 곳을 함께 고친다.
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const OUT = join(dirname(fileURLToPath(import.meta.url)), '..', 'final');
const CW = 2760, CH = 1700, MX = 40, MY = 130, GW = 1920, GH = 1080, RX = 2000, RW = 720;
const FONT = "'Malgun Gothic','맑은 고딕','Noto Sans KR',sans-serif";

// 명세 5절의 회색 값과 같다.
const STYLE = {
  done:    { fill: '#CFCFCF', stroke: '#222222', sw: 4, dash: '', text: '#111111' },
  slot:    { fill: '#FFFFFF', stroke: '#6E6E6E', sw: 3, dash: '14 8', text: '#6E6E6E' },
  scenery: { fill: '#E3E3E3', stroke: '#8A8A8A', sw: 2, dash: '', text: '#444444' },
  plate:   { fill: '#F4F4F4', stroke: '#222222', sw: 2, dash: '', text: '#111111' },
  area:    { fill: 'none',    stroke: '#999999', sw: 2, dash: '4 6', text: '#666666' },
};

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const tw = (s, fs) => [...s].reduce((a, c) => a + (c.charCodeAt(0) > 0x2000 ? fs : fs * 0.56), 0);
const text = (x, y, s, fs = 26, anchor = 'middle', fill = '#111', weight = 'normal') =>
  `<text x="${x}" y="${y}" font-size="${fs}" text-anchor="${anchor}" fill="${fill}" font-weight="${weight}">${esc(s)}</text>`;
const box = (x, y, w, h, st) => {
  const s = STYLE[st];
  return `<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${s.fill}" stroke="${s.stroke}" stroke-width="${s.sw}"${s.dash ? ` stroke-dasharray="${s.dash}"` : ''}/>`;
};
const warnings = [];

// 요소: 이름표의 각 줄은 [글, 크기]. 자리만인 것은 둘째 줄에 "준비 중"이 붙는다.
const E = (id, lines, x, y, w, h, st, ax = 'C', ay = 'C') => ({ id, lines, x, y, w, h, st, ax, ay });
const SLOT = (id, name, x, y, w, h) => E(id, [[name, 28], ['준비 중', 24]], x, y, w, h, 'slot');

const ROOM = [
  E('door', [['문', 28]], 80, 240, 260, 660, 'scenery'),
  E('plate', [['명패 닫기', 28]], 130, 320, 160, 96, 'done'),
  SLOT('req', '의뢰 게시판', 400, 190, 300, 230),
  SLOT('pick', '원작 화집 선반', 750, 150, 430, 200),
  SLOT('upg', '도구장', 1230, 150, 300, 230),
  SLOT('bench', '이젤', 640, 420, 620, 500),
  SLOT('store', '완성작 선반', 1320, 430, 520, 260),
  SLOT('sell', '판매 창구', 1320, 720, 520, 200),
];
const UI = [
  E('daytime', [['1일차    남은 시간 9분 59초', 28]], 24, 16, 460, 72, 'plate', 'L', 'T'),
  E('rep', [['평판  -', 28]], 1356, 16, 220, 72, 'slot', 'R', 'T'),
  E('money', [['보유 금액  -', 28]], 1588, 16, 308, 72, 'slot', 'R', 'T'),
  E('menu', [['메뉴', 28]], 24, 992, 132, 72, 'done', 'L', 'B'),
];
// 알림: 오른쪽 위 공통 UI 바로 아래에서 시작해 아래로 쌓인다.
const N = { x: 1540, y: 100, w: 356, h: 88, gap: 8 };
const notice = (k, note = '') => E(`n${k}`, [[`알림 ${k}`, 24], [note || '(내용 두 줄까지)', 24]], N.x, N.y + (k - 1) * (N.h + N.gap), N.w, N.h, 'slot', 'R', 'T');

function draw(e, file) {
  const o = [box(e.x, e.y, e.w, e.h, e.st)];
  const lh = (fs) => Math.round(fs * 1.35);
  const total = e.lines.reduce((a, [, fs]) => a + lh(fs), 0);
  let y = e.y + e.h / 2 - total / 2;
  for (const [s, fs] of e.lines) {
    if (tw(s, fs) > e.w - 8) warnings.push(`${file}: "${s}" 가 상자 너비(${e.w})를 넘는다`);
    y += lh(fs);
    o.push(text(e.x + e.w / 2, y - lh(fs) * 0.28, s, fs, 'middle', STYLE[e.st].text));
  }
  if (total > e.h) warnings.push(`${file}: "${e.lines[0][0]}" 가 상자 높이(${e.h})를 넘는다`);
  return o.join('');
}

function place(e, vw, vh) {
  const dx = (vw - GW) / 2, dy = (vh - GH) / 2;
  let { x, y, w, h } = e;
  if (e.ax === 'C') x += dx; else if (e.ax === 'R') x += 2 * dx;
  if (e.ay === 'C') y += dy; else if (e.ay === 'B') y += 2 * dy;
  return { x, y, w, h };
}

function thumb(els, ox, oy, vw, vh, s, caption) {
  const dx = (vw - GW) / 2, dy = (vh - GH) / 2;
  const o = [text(ox, oy - 14, caption, 24, 'start')];
  o.push(`<rect x="${ox}" y="${oy}" width="${vw * s}" height="${vh * s}" fill="#F2F2F2" stroke="#222" stroke-width="3"/>`);
  o.push(`<rect x="${ox + dx * s}" y="${oy + dy * s}" width="${GW * s}" height="${GH * s}" fill="#F2F2F2" stroke="#222" stroke-width="2" stroke-dasharray="10 6"/>`);
  for (const e of els) {
    const p = place(e, vw, vh), st = STYLE[e.st];
    const fill = e.st === 'done' ? '#8C8C8C' : st.fill;
    o.push(`<rect x="${(ox + p.x * s).toFixed(1)}" y="${(oy + p.y * s).toFixed(1)}" width="${(p.w * s).toFixed(1)}" height="${(p.h * s).toFixed(1)}" fill="${fill}" stroke="${st.stroke}" stroke-width="2"${st.dash ? ' stroke-dasharray="6 4"' : ''}/>`);
  }
  return o.join('');
}

function wrap(s, fs, maxw) {
  const lines = []; let cur = '';
  for (const word of s.split(' ')) {
    const t = cur ? cur + ' ' + word : word;
    if (tw(t, fs) > maxw && cur) { lines.push(cur); cur = word; } else cur = t;
  }
  if (cur) lines.push(cur);
  return lines;
}

function legend(x, y) {
  const rows = [
    ['done', '누를 수 있다 (구현됨)'],
    ['slot', '자리만 (눌러도 동작하지 않는다)'],
    ['plate', '읽기만 하는 정보 (구현됨)'],
    ['scenery', '방의 일부 (누르지 않는다)'],
    ['area', '자리의 범위를 보이는 선 (화면에는 없다)'],
  ];
  const o = [text(x, y, '표시', 28, 'start', '#111', 'bold')];
  rows.forEach(([st, label], i) => {
    const yy = y + 20 + i * 54;
    o.push(box(x, yy, 84, 40, st));
    o.push(text(x + 100, yy + 29, label, 24, 'start'));
  });
  return o.join('');
}

function sheet({ file, title, sub, els, guides = [], notes }) {
  const o = [];
  o.push(text(MX, 62, title, 44, 'start', '#111', 'bold'));
  o.push(text(MX, 104, sub, 26, 'start', '#444'));
  o.push(`<g transform="translate(${MX},${MY})">`);
  o.push(`<rect x="0" y="0" width="${GW}" height="${GH}" fill="#F2F2F2"/>`);
  for (const e of els) o.push(draw(e, file));
  for (const g of guides) o.push(g);
  o.push(`<rect x="0" y="0" width="${GW}" height="${GH}" fill="none" stroke="#000" stroke-width="4"/>`);
  o.push(`</g>`);
  o.push(text(MX + GW, MY + GH + 34, '굵은 테두리 = 보장 영역 1920×1080 (16:9에서는 화면 전체)', 24, 'end', '#444'));
  const ty = MY + GH + 110;
  o.push(thumb(els, MX, ty, 2520, 1080, 0.3, '21:9 (2520×1080) — 점선이 보장 영역, 바깥은 배경'));
  o.push(thumb(els, MX + 900, ty, 1920, 1200, 0.3, '16:10 (1920×1200) — 위아래로 60씩 넓어진다'));
  o.push(legend(RX, MY + 24));
  let ny = MY + 340;
  o.push(text(RX, ny + 24, '메모', 28, 'start', '#111', 'bold'));
  ny += 66;
  for (const n of notes) {
    for (const ln of wrap('· ' + n, 24, RW - 10)) { o.push(text(RX, ny, ln, 24, 'start')); ny += 34; }
    ny += 10;
  }
  const ch = Math.max(CH, Math.ceil(ny) + 20);
  o.unshift(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${CW} ${ch}" width="${CW}" height="${ch}" font-family="${FONT}">`, `<rect width="${CW}" height="${ch}" fill="#ffffff"/>`);
  o.push('</svg>');
  mkdirSync(OUT, { recursive: true });
  writeFileSync(join(OUT, file), o.join('\n'), 'utf8');
}

// ---- 1. 공통 UI와 공방을 겹친 한 장 -------------------------------------------
const areaGuide = `<rect x="${N.x}" y="${N.y}" width="${N.w}" height="${GH - N.y - 28}" fill="none" stroke="#999" stroke-width="2" stroke-dasharray="4 6"/>`
  + text(N.x + N.w / 2, N.y + 34, '알림이 뜨는 자리', 24, 'middle', '#666')
  + text(N.x + N.w / 2, N.y + 66, '(아래로 쌓인다)', 24, 'middle', '#666');
sheet({
  file: 'layout.svg',
  title: '확정 배치 — 공통 UI ① 네 모서리 + 공방 화면 ① 한 장의 방',
  sub: '사용자가 고친 판: 메뉴는 왼쪽 아래, 알림은 오른쪽 위 공통 UI 바로 아래. 회색조 배치도이며 숫자와 글자는 예시다.',
  els: [...ROOM, ...UI],
  guides: [areaGuide],
  notes: [
    '좌표와 크기, 상태는 docs/roles/designer/outputs/16_화면_명세.md 에 표로 있다. 이 그림은 그 표와 같은 값으로 그렸다.',
    '왼쪽 위: 몇 일차와 남은 시간. 오른쪽 위: 평판과 보유 금액(자리만, 값을 정하지 않아 "-"로 둔다). 왼쪽 아래: 메뉴. 오른쪽 아래: 비운다.',
    '방의 물건 일곱 가운데 누를 수 있는 것은 명패뿐이다. 나머지 여섯은 자리만이며 점선과 옅은 글자, "준비 중"으로 구분한다.',
    '물건의 상자가 곧 누르는 범위다. 그림을 입혀도 이 범위는 바뀌지 않는다.',
    '메뉴(24,992 132×72)와 문(80,240 260×660)은 세로로 92 떨어져 있어 겹치지 않는다.',
    '화면비: 공통 UI의 네 덩어리는 실제 화면의 모서리를 따라가고, 방의 물건은 가운데에 고정된다. 넓어진 곳은 배경이 채운다.',
  ],
});

// ---- 2. 알림이 여러 건 쌓인 모습 -----------------------------------------------
const hit = (a, b) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
const SHOWN = 7; // 그림에 그린 건수. 한 번에 보이는 건수의 확정값이 아니다.
const stack = [];
for (let k = 1; k <= SHOWN; k++) {
  const n = notice(k);
  const over = ROOM.filter((r) => r.st !== 'scenery' && hit(n, r)).map((r) => r.lines[0][0]);
  if (over.length) n.lines = [[`알림 ${k} — 가린다`, 24], [over.join(' · '), 24]];
  stack.push(n);
}
sheet({
  file: 'notifications.svg',
  title: '확정 배치 — 알림이 여러 건 쌓인 모습',
  sub: `알림 ${SHOWN}건을 그린 예시다. 한 번에 몇 건까지 보이는지는 정해지지 않았다(알림 기능을 만들 때 정한다).`,
  els: [...ROOM, ...UI, ...stack],
  notes: [
    `알림 한 건은 ${N.w}×${N.h}, 사이는 ${N.gap}. 첫 건의 왼쪽 위는 (${N.x}, ${N.y}). k번째 건의 위쪽은 ${N.y} + ${N.h + N.gap} × (k − 1).`,
    '오른쪽 끝을 보유 금액의 오른쪽 끝(1896)에 맞췄다. 왼쪽 끝 1540은 도구장의 오른쪽 끝(1530)보다 오른쪽이라 도구장을 가리지 않는다.',
    '16:9: 3건까지는 어느 물건도 가리지 않는다. 4건째부터 완성작 선반의 오른쪽을, 7건째부터 판매 창구의 오른쪽을 가린다.',
    '16:10: 알림은 위쪽 끝을 따라가고 물건은 60 내려가므로 한 건 늦다. 5건째부터 완성작 선반, 8건째부터 판매 창구.',
    '21:9: 알림이 오른쪽 끝을 따라 300 더 나가므로 어느 물건도 가리지 않는다.',
    '가리는 것은 물건의 오른쪽 300 너비뿐이다. 완성작 선반과 판매 창구의 왼쪽 220은 늘 보인다.',
    '새 알림은 첫 자리(맨 위)에 뜨고 먼저 온 알림이 아래로 밀린다. 그림의 번호는 자리의 번호다.',
  ],
});

// ---- 계산 확인 -----------------------------------------------------------------
console.log('알림이 가리는 물건 (k번째 건)');
for (const [name, vw, vh] of [['16:9', 1920, 1080], ['16:10', 1920, 1200], ['21:9', 2520, 1080]]) {
  const first = {};
  for (let k = 1; k <= 14; k++) {
    const n = place(notice(k), vw, vh);
    for (const r of ROOM) {
      if (r.st === 'scenery') continue;
      if (hit(n, place(r, vw, vh)) && !(r.id in first)) first[r.id] = k;
    }
    if (n.y + n.h > vh && !('화면 아래' in first)) first['화면 아래'] = k;
  }
  console.log(` ${name}: ${JSON.stringify(first)}`);
}
const menu = UI.find((e) => e.id === 'menu'), door = ROOM[0];
console.log(`메뉴와 문: 겹침 ${hit(menu, door)}, 세로 간격 ${menu.y - (door.y + door.h)}`);
if (warnings.length) { console.log('경고'); warnings.forEach((w) => console.log(' - ' + w)); }
