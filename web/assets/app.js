// web/assets/app.js — 대시보드 동작.
// 파일 구성은 페이지에 실려 오고(boot), 곡선·SAR·선량-반응·모델은 api.php → R(run.R)에서 받는다.
// R은 데이터만 주고 그리기는 여기서 한다.
'use strict';

const B = JSON.parse(document.getElementById('boot').textContent);
const I = B.inspect;
const SG = I.single_grain;

const css = n => getComputedStyle(document.documentElement).getPropertyValue(n).trim();
const C = {
  ink: css('--forest-ink'), pass: css('--pass'), fail: css('--fail'), fit: css('--muted-sage'), data: css('--emerald'),
  natural: css('--indigo-accent'), muted: css('--slate-smoke'), line: css('--lichen'), moss: css('--moss'), font: css('--font'),
};
// 기본 도구 막대는 숨긴다. 조작: 드래그 = 상자 확대, 더블클릭 = 원래대로, 도구는 그래프 상자 오른쪽 위의 돋보기·크게 보기뿐.
const PC = { responsive: true, displaylogo: false, displayModeBar: false, doubleClick: 'reset', showTips: false };
const AX = { gridcolor: C.line, griddash: 'dot', zeroline: false, linecolor: C.ink, linewidth: 0.5 };
// 축 이름은 눈금 숫자에서 30px 띄운다(그 틈에 확대 가이드 선이 들어감). 왼쪽·아래 여백도 그만큼 넓다.
const ax = o => ({ ...AX, ...o, ...(typeof o.title === 'string' ? { title: { text: o.title, standoff: 30 } } : {}) });
const BASE = {
  margin: { l: 86, r: 18, t: 40, b: 70 }, font: { family: C.font, size: 12, color: C.ink },
  paper_bgcolor: 'rgba(0,0,0,0)', plot_bgcolor: 'rgba(0,0,0,0)', legend: { orientation: 'h', y: -0.22 },
};
const title = text => ({ text, font: { size: 14 }, x: 0, xanchor: 'left' });

const SIGMAB = { single_grain: 0.20, single_aliquot: 0.15 };  // 0.20: 문헌 근거, 0.15: 기존 기본값(미확인)
const MODE_LABEL = { single_grain: 'A · 알갱이별', single_aliquot: 'B · 디스크별' };

const fmt = (v, d = 1) => v == null ? '—' : Number(v).toFixed(d);
const arr = v => v == null ? [] : [].concat(v);
const $ = id => document.getElementById(id);
function el(tag, text, cls) { const e = document.createElement(tag); if (text != null) e.textContent = text; if (cls) e.className = cls; return e; }
const parseRange = s => { const m = /^\s*(\d+)\s*:\s*(\d+)\s*$/.exec(s || ''); return m ? [+m[1], +m[2]] : null; };

// ---- R 호출. 대기 중인 요청이 있으면 왼쪽 아래 칩에 표시한다.
let pending = 0;
function busy(d) { pending += d; $('chip').textContent = 'R 계산 중'; $('chip').classList.toggle('show', pending > 0); }
async function api(action, args) {
  busy(1);
  try {
    const res = await fetch('api.php', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ id: B.id, action, args }) });
    let j;
    try { j = await res.json(); } catch { throw new Error(`서버 응답을 읽지 못함(HTTP ${res.status})`); }
    if (!j.ok) throw new Error(j.error || '알 수 없는 오류');
    return j;
  } finally { busy(-1); }
}
// 곡선·선량-반응은 같은 조건이면 결과가 같으므로 한 번만 부른다(실패하면 다시 부를 수 있게 지움).
const cache = new Map();
function cached(action, args) {
  const k = action + JSON.stringify(args);
  if (!cache.has(k)) cache.set(k, api(action, args).catch(e => { cache.delete(k); throw e; }));
  return cache.get(k);
}
function plotMessage(div, msg) {
  const d = $(div); if (window.Plotly) Plotly.purge(d);   // purge는 이벤트도 지우므로 다음 plot()에서 다시 붙인다
  d._events = false; hideAxes(d); d.replaceChildren(el('div', msg, 'empty'));
}

// ---- 그래프 공통: 모든 그리기는 plot()을 거친다. 새로 그리면 확대가 풀리므로 그때의 범위를 '전체 범위'로 기억한다.
const ICON = {
  zin: '<svg viewBox="0 0 24 24"><circle cx="10.5" cy="10.5" r="6.5"/><path d="M15.5 15.5 21 21M10.5 7.5v6M7.5 10.5h6"/></svg>',
  zout: '<svg viewBox="0 0 24 24"><circle cx="10.5" cy="10.5" r="6.5"/><path d="M15.5 15.5 21 21M7.5 10.5h6"/></svg>',
  exp: '<svg viewBox="0 0 24 24"><path d="M15 3h6v6M9 21H3v-6M21 3l-7 7M3 21l7-7"/></svg>',   // ↗↙ 크게 보기
  shr: '<svg viewBox="0 0 24 24"><path d="M4 14h6v6M20 10h-6V4M14 10l7-7M3 21l7-7"/></svg>',    // ↙↗ 원래 크기
};
const gdOf = d => typeof d === 'string' ? $(d) : d;
const isSide = gd => !!gd.closest('.dash.expanded') && !gd.closest('.big');   // 크게 보기에서 오른쪽 작은 칸
// 범례는 x축 이름 아래(축에서 78px)에 둔다. Plotly의 범례 위치는 그래프 높이 비율이라 높이에 따라 다시 계산한다.
// 오른쪽 작은 칸에서는 범례가 축 이름과 겹쳐서 숨긴다.
function legendLayout(gd) {
  const on = gd._legend && !isSide(gd), b = on ? 124 : BASE.margin.b, h = Math.max(120, (gd.clientHeight || 380) - BASE.margin.t - b);
  return { showlegend: on, 'margin.b': b, 'legend.y': -78 / h, 'legend.yanchor': 'top' };
}
function plot(div, data, layout) {
  const gd = gdOf(div);
  gd._legend = layout.showlegend !== false;
  const L = legendLayout(gd);
  const p = Plotly.react(gd, data, { ...layout, showlegend: L.showlegend, margin: { ...BASE.margin, b: L['margin.b'] },
    legend: { ...BASE.legend, y: L['legend.y'], yanchor: 'top' } }, PC);
  gd._home = { x: [...gd._fullLayout.xaxis.range], y: [...gd._fullLayout.yaxis.range] };
  if (!gd._track) addTools(gd);
  if (!gd._events) {
    gd._events = true;
    gd.on('plotly_relayout', () => syncAxes(gd));
    gd.on('plotly_afterplot', () => { fitTitle(gd); syncAxes(gd); });   // 크기 변경 뒤에도 눈금·축 이름 위치를 다시 잰다
  }
  fitTitle(gd); syncAxes(gd);
  return p;
}
const rangeOf = (gd, a) => [...gd._fullLayout[a + 'axis'].range];
const isZoomed = (gd, a) => { const h = gd._home[a], c = rangeOf(gd, a), e = (h[1] - h[0]) * 1e-3; return c[0] > h[0] + e || c[1] < h[1] - e; };

// 도구 버튼(돋보기 −/+, 대시보드 네 칸에는 크게 보기)과 두 축의 확대 가이드를 그래프 상자에 한 번만 붙인다.
function addTools(gd) {
  const box = gd.parentElement, tools = el('div', null, 'ptools');
  const btn = (k, tip, fn) => { const b = el('button', null, k); b.type = 'button'; b.innerHTML = ICON[k]; b.title = tip; b.onclick = fn; tools.append(b); return b; };
  btn('zout', '축소', () => zoomBy(gd, 1.6));
  btn('zin', '확대(가운데 기준)', () => zoomBy(gd, 1 / 1.6));
  if (box.parentElement.classList.contains('dash')) btn('exp', '크게 보기', () => toggleBig(box));
  box.append(tools);
  gd._track = {};
  for (const a of ['x', 'y']) {
    const t = el('div', null, 'axtrack ' + a), th = el('div', null, 'axthumb'), tip = el('div', '끌어서 이동', 'axtip');
    t.append(th); box.append(t, tip);
    gd._track[a] = { t, th, tip };
    dragThumb(gd, a);
  }
}
// 제목이 오른쪽 위 도구 버튼과 가로로 겹치면(좁은 칸) 상자 위쪽을 넓혀 제목을 버튼 줄 아래로 내린다.
// 가로 위치만 비교하므로 위쪽 여백을 바꿔도 판정이 뒤집히지 않는다.
function fitTitle(gd) {
  const ttl = gd.querySelector('.gtitle'), tools = gd.parentElement.querySelector('.ptools');
  if (!ttl || !tools) return;
  gd.parentElement.classList.toggle('crowded', ttl.getBoundingClientRect().right > tools.getBoundingClientRect().left - 6);
}
function hideAxes(gd) { if (gd._track) Object.values(gd._track).forEach(({ t, tip }) => { t.classList.remove('show'); tip.classList.remove('show'); }); }

// 확대된 축에만 가이드(실선 + 점)를 띄운다. 점 = 전체 범위 중 지금 보이는 구간의 가운데.
// 선 위치 = 축 이름과 눈금 숫자 사이 틈의 가운데(그려진 글자 위치를 재서 정함).
function syncAxes(gd) {
  if (!gd._track) return;
  if (!gd._fullLayout || !gd._home || !gd.data) { hideAxes(gd); return; }
  const s = gd._fullLayout._size, ox = gd.offsetLeft, oy = gd.offsetTop, B = gd.parentElement.getBoundingClientRect();
  const rects = q => [...gd.querySelectorAll(q)].map(e => e.getBoundingClientRect()).filter(r => r.width);
  for (const a of ['x', 'y']) {
    const { t, th, tip } = gd._track[a], z = isZoomed(gd, a), was = t.classList.contains('show');
    t.classList.toggle('show', z);
    if (!z) { tip.classList.remove('show'); continue; }
    const h = gd._home[a], c = rangeOf(gd, a), span = h[1] - h[0];
    const mid = (Math.max(0, (c[0] - h[0]) / span) + Math.min(1, (c[1] - h[0]) / span)) / 2;
    if (a === 'y') {
      const ticks = rects('.ytick text'), ttl = rects('.g-ytitle text')[0];
      const tickL = ticks.length ? Math.min(...ticks.map(r => r.left)) - B.left : ox + s.l - 30;
      const cx = ((ttl ? ttl.right - B.left : tickL - 24) + tickL) / 2;
      Object.assign(t.style, { left: cx - 8 + 'px', top: oy + s.t + 'px', width: '16px', height: s.h + 'px' });
      Object.assign(th.style, { left: '8px', top: (1 - mid) * s.h + 'px' });
      Object.assign(tip.style, { left: cx + 14 + 'px', top: oy + s.t + (1 - mid) * s.h - 11 + 'px' });
    } else {
      const ticks = rects('.xtick text'), ttl = rects('.g-xtitle text')[0];
      const tickB = ticks.length ? Math.max(...ticks.map(r => r.bottom)) - B.top : oy + s.t + s.h + 22;
      const cy = (tickB + (ttl ? ttl.top - B.top : tickB + 24)) / 2;
      Object.assign(t.style, { left: ox + s.l + 'px', top: cy - 8 + 'px', width: s.w + 'px', height: '16px' });
      Object.assign(th.style, { left: mid * s.w + 'px', top: '8px' });
      Object.assign(tip.style, { left: ox + s.l + mid * s.w - 30 + 'px', top: cy - 36 + 'px' });
    }
    if (!was && !gd._tipShown) { gd._tipShown = true; tip.classList.add('show'); setTimeout(() => tip.classList.remove('show'), 2600); }   // 처음 한 번만
  }
}

// 점을 끌면 그 축의 보이는 범위가 같은 폭으로 이동. 선의 다른 곳을 누르면 그 자리가 가운데로 오게 이동.
function dragThumb(gd, a) {
  const { t, th } = gd._track[a];
  const len = () => a === 'y' ? t.clientHeight : t.clientWidth;
  const clampTo = (h, lo, w) => { lo = Math.min(Math.max(lo, h[0]), h[1] - w); return [lo, lo + w]; };
  let start = null, raf = 0;
  th.addEventListener('pointerdown', e => {
    e.preventDefault(); e.stopPropagation(); th.setPointerCapture(e.pointerId); th.classList.add('drag');
    start = { p: a === 'y' ? e.clientY : e.clientX, r: rangeOf(gd, a) };
  });
  th.addEventListener('pointermove', e => {
    if (!start) return;
    const h = gd._home[a], d = ((a === 'y' ? start.p - e.clientY : e.clientX - start.p) / len()) * (h[1] - h[0]);
    const next = clampTo(h, start.r[0] + d, start.r[1] - start.r[0]);
    cancelAnimationFrame(raf); raf = requestAnimationFrame(() => Plotly.relayout(gd, { [a + 'axis.range']: next }));
  });
  const end = () => { start = null; th.classList.remove('drag'); };
  th.addEventListener('pointerup', end); th.addEventListener('pointercancel', end);
  t.addEventListener('pointerdown', e => {
    if (e.target !== t) return;
    const r = t.getBoundingClientRect(), f = a === 'y' ? 1 - (e.clientY - r.top) / r.height : (e.clientX - r.left) / r.width;
    const h = gd._home[a], c = rangeOf(gd, a), w = c[1] - c[0];
    tween(gd, { [a]: clampTo(h, h[0] + f * (h[1] - h[0]) - w / 2, w) });
  });
}

// 범위를 부드럽게 바꾼다(ease-out 280ms).
function tween(gd, to) {
  const from = {}; for (const a in to) from[a] = rangeOf(gd, a);
  const t0 = performance.now(), ease = k => 1 - (1 - k) ** 3;
  const step = now => {
    const k = ease(Math.min(1, (now - t0) / 280)), u = {};
    for (const a in to) u[a + 'axis.range'] = [0, 1].map(i => from[a][i] + (to[a][i] - from[a][i]) * k);
    Plotly.relayout(gd, u);
    if (k < 1) requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
}

// 돋보기: 지금 보이는 영역의 가운데를 기준으로 f배. 전체 범위를 넘으면 전체 범위에서 멈춘다.
function zoomBy(gd, f) {
  if (!gd.data) return;
  const to = {};
  for (const a of ['x', 'y']) {
    const h = gd._home[a], c = rangeOf(gd, a), mid = (c[0] + c[1]) / 2, w = Math.min((c[1] - c[0]) * f, h[1] - h[0]);
    const lo = Math.min(Math.max(mid - w / 2, h[0]), h[1] - w);
    to[a] = [lo, lo + w];
  }
  tween(gd, to);
}

// 크게 보기: 하나는 왼쪽 큰 칸(세 칸 높이), 나머지 셋은 오른쪽 1열. 칸이 바뀌는 움직임은 FLIP으로 부드럽게.
function toggleBig(box) {
  const dash = box.parentElement, boxes = [...dash.querySelectorAll(':scope > .plotbox')];
  const first = boxes.map(b => b.getBoundingClientRect()), on = !box.classList.contains('big');
  boxes.forEach(b => b.classList.toggle('big', on && b === box));
  dash.classList.toggle('expanded', on);
  boxes.forEach(b => {
    const e = b.querySelector('.ptools .exp'), big = b.classList.contains('big');
    if (e) { e.innerHTML = ICON[big ? 'shr' : 'exp']; e.title = big ? '원래 크기' : '크게 보기'; }
    const gd = b.querySelector('.plot');
    if (gd.data) { Plotly.relayout(gd, legendLayout(gd)); Plotly.Plots.resize(gd); }
  });
  if (run) drawRadial(U()[sel]);   // 방사형 호는 영역 크기에 맞춰 다시 계산
  boxes.forEach((b, i) => {
    const l = b.getBoundingClientRect(), f = first[i], gd = b.querySelector('.plot');
    b.animate([{ transformOrigin: 'top left', transform: `translate(${f.left - l.left}px, ${f.top - l.top}px) scale(${f.width / l.width}, ${f.height / l.height})` },
               { transformOrigin: 'top left', transform: 'none' }], { duration: 480, easing: 'cubic-bezier(.34, 1.2, .64, 1)' });
    gd.animate([{ opacity: .35 }, { opacity: 1 }], { duration: 480, easing: 'ease-out' }).finished.then(() => syncAxes(gd));   // 움직이는 중에 잰 위치는 틀리므로 끝난 뒤 다시 잰다
  });
  if (on) box.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
}
document.addEventListener('keydown', e => { if (e.key === 'Escape') { const b = document.querySelector('.plotbox.big'); if (b) toggleBig(b); } });

// 그래프 사용법 안내(머리글과 그래프 사이)
document.querySelectorAll('.howto').forEach(h => h.innerHTML =
  '<span><b>드래그</b> 그 구간 확대</span>' +
  '<span>확대 중에는 축 이름과 눈금 사이의 <span class="dotdemo"></span> 점을 끌어 이동</span>' +
  '<span><b>더블클릭</b> 원래대로</span>' +
  `<span>${ICON.zout}${ICON.zin} 가운데 기준 축소·확대</span>` +
  (h.nextElementSibling.classList.contains('dash') ? `<span>${ICON.exp} 크게 보기(나머지는 오른쪽 1열 · Esc로 복귀)</span>` : ''));

// ---- 01 업로드: 다른 파일을 끌어다 놓거나 골라서 올린다(처리는 index.php)
{
  const drop = $('drop'), input = drop.querySelector('input'), form = $('upForm');
  input.onchange = () => { if (input.files.length) { drop.querySelector('b').textContent = input.files[0].name + ' 올리는 중…'; form.submit(); } };
  drop.addEventListener('dragover', e => { e.preventDefault(); drop.classList.add('over'); });
  drop.addEventListener('dragleave', () => drop.classList.remove('over'));
  drop.addEventListener('drop', e => { e.preventDefault(); drop.classList.remove('over'); input.files = e.dataTransfer.files; input.onchange(); });
}

// ---- 파일 구성에서 바로 얻는 것
const byDisc = {};
I.grains.forEach(g => (byDisc[g.position] ??= []).push(g.grain));
const recsOf = (p, g) => I.records.filter(r => r.position == p && r.grain == g);
const firstOsl = (p, g) => recsOf(p, g).find(r => r.ltype !== 'TL');   // SAR의 자연 신호(첫 OSL/IRSL 측정)
const NCH = Math.max(...I.records.filter(r => r.ltype !== 'TL').map(r => r.npoints));

let run = null;   // 마지막 SAR 실행: { mode, sig, bg, sar, age, meta }
let sel = 0, selToken = 0;

// ---- 탭: 주소의 #이름으로 동작(뒤로 가기·링크 공유 가능). 하위 항목(#file, #sigrun …)은 그 탭을 연 뒤 해당 위치로 스크롤.
const TABS = ['upload', 'signal', 'dash', 'model'], OLD = { file: 'upload', dist: 'dash' };   // 예전 주소(#file, #dist)도 받는다
const tabItems = [...document.querySelectorAll('#tree > li[data-v]')];
let tab = null;
function go(id) {
  const target = id && !TABS.includes(id) && !OLD[id] ? document.getElementById(id) : null;
  const v = TABS.includes(id) ? id : OLD[id] || target?.closest('.view')?.id || 'upload';
  const i = TABS.indexOf(v);
  tabItems.forEach((li, k) => { li.classList.toggle('on', k === i); li.classList.toggle('done', k !== i && (k === 0 || (k === 1 && !!run))); });
  // 선택 박스: 앞의 탭은 모두 접혀 있으므로 top = i × (탭 높이 + 간격), 높이 = 탭 + 펼친 하위 항목
  const step = tabItems[0].querySelector('.tab').offsetHeight + 10;
  $('pill').style.transform = `translateY(${i * step}px)`;
  $('pill').style.height = (tabItems[0].querySelector('.tab').offsetHeight + tabItems[i].querySelector('.sub > ul').scrollHeight) + 'px';
  document.querySelectorAll('.view').forEach(s => s.classList.toggle('on', s.id === v));
  document.querySelectorAll('.sub a').forEach(a => a.classList.toggle('cur', a.getAttribute('href') === '#' + id));
  if (v === 'signal') requestAnimationFrame(syncSeg);   // 숨겨져 있던 동안은 버튼 폭을 잴 수 없었다
  if (v !== tab) {
    tab = v;
    requestAnimationFrame(() => document.querySelectorAll('#' + v + ' .plot').forEach(p => { if (window.Plotly && p.data) Plotly.Plots.resize(p); }));
    if (v === 'dash' && run) drawRadial(U()[sel]);   // 방사형은 영역 크기에 맞춰 호를 다시 계산해야 한다
  }
  if (target) target.scrollIntoView({ behavior: 'smooth', block: 'start' });
}
window.addEventListener('hashchange', () => go(location.hash.slice(1)));

// ---- 상단 분석 조건(결과가 어떤 조건에서 나왔는지 항상 보이게)
function renderContext() {
  const m = run ? run.meta : B.meta, box = $('context'); box.replaceChildren();
  [['시료 파일', B.file], ['측정 방식', run ? MODE_LABEL[run.mode] : '분석 전'],
   ['신호 구간', run ? run.sig + '번 채널' : '—'], ['배경 구간', run ? run.bg + '번 채널' : '—'],
   ['sigmab', run ? SIGMAB[run.mode] : '—'], ['분석 소요', run ? run.secs + '초' : '—'], ['단위', '초(s) · 선량률 미입력'],
   ['분석 패키지', `Luminescence ${m.luminescence_version} · R ${m.r_version}`]]
    .forEach(([k, v]) => { const s = el('span', k + ' '); s.append(el('b', v)); box.append(s); });
}

// ---- 01 파일
function renderFile() {
  const facts = [[B.file, '파일'], [SG ? 'single-grain' : 'single-aliquot', '측정 방식'], [I.n_positions, '디스크'],
    [SG ? I.grains.length : '—', '알갱이'], [I.records.length, '레코드'], [arr(I.record_types).join(', '), '레코드 종류'], [NCH, '채널 수(OSL)']];
  if (I.object_name) facts.push([I.object_name, 'RDA 객체']);
  facts.forEach(([v, k]) => { const d = el('div'); d.append(el('span', k), el('b', v)); $('facts').append(d); });
  if (arr(I.ignored_objects).length) $('facts').append(el('p', `RDA 안의 다른 객체 ${arr(I.ignored_objects).join(', ')}는 사용하지 않음.`, 'note'));

  const t = $('discs'), h = el('tr'); ['디스크', '알갱이 수', '알갱이 번호'].forEach(x => h.append(el('th', x))); t.append(h);
  Object.entries(byDisc).forEach(([p, gs]) => {
    const r = el('tr');
    [p, SG ? gs.length : '—', SG ? gs.join(', ') : '디스크 단위 측정'].forEach(x => r.append(el('td', x)));
    t.append(r);
  });
}

// ---- 공통: 곡선 그리기(신호 구간은 모스 초록, 배경 구간은 회색 띠)
function drawCurve(div, c, text, sig, bg) {
  const x = c.x, dx = x.length > 1 ? (x[1] - x[0]) / 2 : 0.5, shapes = [], annotations = [];
  // 신호 띠 안쪽 위는 감쇠 곡선의 피크 자리라 글자가 곡선에 겹친다. 신호 라벨은 띠 오른쪽 바깥(곡선이 떨어진 곳)에 둔다.
  const band = (r, color, name, outside) => {
    if (!r || r[0] < 1 || r[1] > x.length || r[0] > r[1]) return;
    const x0 = x[r[0] - 1] - dx, x1 = x[r[1] - 1] + dx, font = { size: 11, color: C.ink };
    shapes.push({ type: 'rect', xref: 'x', yref: 'paper', x0, x1, y0: 0, y1: 1, fillcolor: color, opacity: 0.3, line: { width: 0 },
      ...(outside ? {} : { label: { text: name, textposition: 'top right', font } }) });   // 띠가 글자보다 좁아도 그래프 밖으로 잘리지 않게 오른쪽 끝에 맞춤
    if (outside) annotations.push({ xref: 'x', yref: 'paper', x: x1, y: 1, xanchor: 'left', yanchor: 'top', xshift: 4, text: name, showarrow: false, font });
  };
  band(sig, C.moss, '신호', true); band(bg, C.muted, '배경');
  const tl = /^TL/.test(c.record_type);
  plot(div, [{ x, y: c.y, customdata: x.map((_, i) => i + 1), mode: 'lines', line: { color: C.ink, width: 1.5 },
    hovertemplate: `채널 %{customdata} · %{x:.2f} ${tl ? '°C' : 's'}<br>%{y} counts<extra></extra>` }],
  { ...BASE, title: title(text), xaxis: ax({ title: tl ? '온도 (°C)' : '자극 시간 (s)' }), yaxis: ax({ title: '계수 (counts)' }), shapes, annotations, showlegend: false }, PC);
}

// ---- 02 신호: 레코드 곡선 보기
const selPos = $('selPos'), selGrain = $('selGrain'), selRec = $('selRec');
let sigCurve = null, sigToken = 0;
Object.keys(byDisc).forEach(p => selPos.append(new Option(p, p)));
$('grainLabel').hidden = !SG;
function fillGrains() { selGrain.replaceChildren(); byDisc[selPos.value].forEach(g => selGrain.append(new Option(g, g))); fillRecs(); }
function fillRecs() {
  selRec.replaceChildren();
  recsOf(selPos.value, selGrain.value).forEach(r => selRec.append(new Option(`#${r.record_index} ${r.ltype} · ${r.dtype} · 선량 ${r.irr_time} s`, r.record_index)));
  const f = firstOsl(selPos.value, selGrain.value); if (f) selRec.value = f.record_index;
  showSignal();
}
async function showSignal() {
  const token = ++sigToken, p = +selPos.value, g = +selGrain.value, i = +selRec.value;
  const rec = recsOf(p, g).find(r => r.record_index === i);
  try {
    const c = (await cached('curve', { position: p, record_index: i, ...(SG ? { grain: g } : {}) })).result;
    if (token !== sigToken) return;
    sigCurve = { c, text: `디스크 ${p}` + (SG ? ` · 알갱이 ${g}` : '') + ` · #${i} ${rec.ltype}` };
    drawSignal();
    $('curveInfo').textContent = `측정 온도 ${rec.temperature}°C · 재생 선량 ${rec.irr_time} s · 채널 ${c.x.length}개. 곡선에 마우스를 올리면 채널 번호 표시.`;
  } catch (e) { if (token === sigToken) plotMessage('curvePlot', '곡선을 불러오지 못함: ' + e.message); }
}
// 입력 중인 적분 구간을 곡선 위 색 띠로 바로 보여 준다.
function drawSignal() { if (sigCurve) drawCurve('curvePlot', sigCurve.c, sigCurve.text, parseRange($('sig').value), parseRange($('bg').value)); }
selPos.onchange = fillGrains; selGrain.onchange = fillRecs; selRec.onchange = showSignal;
$('sig').oninput = drawSignal; $('bg').oninput = drawSignal;

// ---- 02 분석 조건: 측정 방식 + 적분 구간 → SAR → 연령 모델
let formMode = SG ? 'single_grain' : 'single_aliquot';
Object.entries(MODE_LABEL).forEach(([m, label]) => {
  const b = el('button', label); b.type = 'button'; b.dataset.mode = m;
  if (m === 'single_grain' && !SG) { b.disabled = true; b.title = 'GRAIN 번호가 없는 파일이라 알갱이별 분석 불가'; }
  b.onclick = () => { formMode = m; syncSeg(); };
  $('modeSeg').append(b);
});
function syncSeg() {
  document.querySelectorAll('#modeSeg button').forEach(b => b.classList.toggle('on', b.dataset.mode === formMode));
  const b = document.querySelector('#modeSeg button.on'), t = document.querySelector('#modeSeg .thumb');
  if (b && b.offsetWidth) { t.style.width = b.offsetWidth + 'px'; t.style.transform = `translateX(${b.offsetLeft - 3}px)`; }
}
$('runHint').textContent = `채널 1–${NCH}, 형식 시작:끝(예: 6:10). 입력하면 위 곡선에 색 띠로 표시됨. `
  + 'A는 알갱이마다 De 하나, B는 디스크의 알갱이 신호를 합산해 디스크마다 De 하나.' + (SG ? '' : ' 이 파일은 B만 가능.');

$('runForm').onsubmit = async e => {
  e.preventDefault();
  const sig = $('sig').value.trim(), bg = $('bg').value.trim(), mode = formMode;
  const bad = [parseRange(sig), parseRange(bg)].some(r => !r || r[0] < 1 || r[1] > NCH || r[0] > r[1]);
  if (bad) { $('runStatus').textContent = `구간은 1–${NCH} 안의 시작:끝 형식이어야 함.`; return; }

  $('runBtn').disabled = true;
  const t0 = Date.now(), tick = setInterval(() => { $('runStatus').textContent = `SAR 계산 중 · ${Math.round((Date.now() - t0) / 1000)}초`; }, 500);
  try {
    const s = await api('sar', { positions: arr(I.positions), signal_integral: sig, background_integral: bg, mode });
    const acc = s.result.units.filter(u => u.rc_status === 'OK' && u.de != null);
    let age;
    try {
      age = { ok: true, ...(await api('age_model', { de: acc.map(u => u.de), de_error: acc.map(u => u.de_error), sigmab: SIGMAB[mode] })).result };
    } catch (err) { age = { ok: false, error: err.message }; }
    // 소요 시간: 버튼을 누른 때부터 SAR + 연령 모델 응답까지(서버의 R 기동 시간 포함, 사용자가 기다린 시간)
    run = { mode, sig, bg, sar: s.result, age, meta: s.meta, secs: ((Date.now() - t0) / 1000).toFixed(1) };
    $('runStatus').textContent = `완료 · ${s.result.n_success}/${s.result.n_requested} 분석, QC 통과 ${acc.length} · ${run.secs}초`;
    renderRun();
    location.hash = '#dash';
  } catch (err) {
    $('runStatus').textContent = 'SAR 실패: ' + err.message;
  } finally { clearInterval(tick); $('runBtn').disabled = false; }
};

// ---- 03 De 분포: 단위 하나를 고르면 네 그래프·지도·표가 함께 바뀐다
const U = () => run.sar.units;
const unitLabel = u => run.mode === 'single_grain' ? `디스크 ${u.position} · 알갱이 ${u.grain}` : `디스크 ${u.position}`;

function renderRun() {
  renderContext();
  $('distEmpty').hidden = true; $('distBody').hidden = false;
  const md = $('mapDisc'); md.replaceChildren();
  if (run.mode === 'single_grain') [...new Set(U().map(u => u.position))].forEach(p => md.append(new Option('디스크 ' + p, p)));
  md.hidden = run.mode !== 'single_grain';
  const f = arr(run.sar.failed);
  $('failedNote').textContent = f.length ? `분석 실패 ${f.length}개(표에 없음): ` + f.map(x => (run.mode === 'single_grain' ? `디스크 ${x.position} 알갱이 ${x.grain}` : `디스크 ${x.position}`) + ` — ${x.reason}`).join(' / ') : '';
  renderModel();
  const first = U().findIndex(u => u.rc_status === 'OK');
  sel = first >= 0 ? first : 0;
  renderTable();
  select(sel);
}

function select(i) {
  const units = U(); if (!units.length) return;
  sel = Math.max(0, Math.min(units.length - 1, i));
  const u = units[sel], pass = u.rc_status === 'OK', token = ++selToken;
  $('selTitle').textContent = unitLabel(u);
  $('selDetail').replaceChildren(el('span', `De ${fmt(u.de)} ± ${fmt(u.de_error)} s · `), el('span', pass ? '● 통과' : '✕ 탈락', pass ? 'ok' : 'no'),
    el('span', ` · Recycling ${fmt(u.recycling_ratio, 3)}` + (u.warning ? ' · 경고 있음' : '')));
  $('prevBtn').disabled = sel === 0;
  $('nextBtn').disabled = sel === units.length - 1;
  document.querySelectorAll('#units tr.pick').forEach(r => r.classList.toggle('sel', +r.dataset.i === sel));
  renderMap(); renderQC(u); drawHist(u); drawRadial(u);
  drawUnitCurve(u, token); drawDR(u, token);
}

async function drawUnitCurve(u, token) {
  const sgMode = run.mode === 'single_grain', g = sgMode ? u.grain : byDisc[u.position][0], rec = firstOsl(u.position, g);
  const args = sgMode ? { position: u.position, record_index: rec.record_index, grain: u.grain }
                      : { position: u.position, record_index: rec.record_index, mode: 'single_aliquot' };
  try {
    const c = (await cached('curve', args)).result;
    if (token !== selToken) return;
    drawCurve('dCurve', c, '신호 곡선 · ' + (!sgMode && SG ? '디스크 합산 · ' : '') + '자연 신호', parseRange(run.sig), parseRange(run.bg));
  } catch (e) { if (token === selToken) plotMessage('dCurve', '곡선을 불러오지 못함: ' + e.message); }
}

async function drawDR(u, token) {
  const args = { position: u.position, signal_integral: run.sig, background_integral: run.bg, mode: run.mode,
    ...(run.mode === 'single_grain' ? { grain: u.grain } : {}) };
  let d;
  try { d = (await cached('dose_response', args)).result; } catch (e) { if (token === selToken) plotMessage('dDR', '선량-반응 곡선을 불러오지 못함: ' + e.message); return; }
  if (token !== selToken) return;
  const P = d.points;
  const regen = P.filter(p => p.name !== 'Natural' && !p.repeated && p.dose > 0), rep = P.filter(p => p.repeated),
        zero = P.filter(p => p.name !== 'Natural' && p.dose === 0), nat = P.find(p => p.name === 'Natural');
  const pts = (a, name, marker) => ({ x: a.map(p => p.dose), y: a.map(p => p.lxtx), mode: 'markers', name, marker: { size: 8, ...marker },
    error_y: { type: 'data', array: a.map(p => p.lxtx_error), color: marker.line?.color || marker.color, thickness: 1 },
    hovertemplate: '선량 %{x} s<br>Lx/Tx %{y:.3f}<extra>' + name + '</extra>' });
  const traces = [{ x: arr(d.curve_x), y: arr(d.curve_y), mode: 'lines', name: '적합 곡선', line: { color: C.fit, width: 2 }, hoverinfo: 'skip' },
    pts(regen, '재생 선량', { color: C.data }),
    pts(rep, '반복', { symbol: 'diamond-open', color: C.ink, line: { color: C.ink, width: 1 } }),
    pts(zero, '0 선량', { symbol: 'square-open', color: C.muted, line: { color: C.muted, width: 1 } })];
  const shapes = [];
  if (nat && d.de != null) {
    traces.push({ x: [d.de], y: [nat.lxtx], mode: 'markers', name: '자연 신호 → De', marker: { color: C.natural, size: 13, symbol: 'star' },
      error_y: { type: 'data', array: [nat.lxtx_error], color: C.natural }, hovertemplate: `De ${fmt(d.de)} s<extra></extra>` });
    shapes.push({ type: 'line', x0: 0, x1: d.de, y0: nat.lxtx, y1: nat.lxtx, line: { color: C.natural, dash: 'dot', width: 1 } },
                { type: 'line', x0: d.de, x1: d.de, y0: 0, y1: nat.lxtx, line: { color: C.natural, dash: 'dot', width: 1 } });
  }
  plot('dDR', traces, { ...BASE, shapes, title: title('선량-반응 곡선' + (d.de == null ? ' · De 계산 불가' : '')),
    xaxis: ax({ title: '재생 선량 (s)', rangemode: 'tozero' }), yaxis: ax({ title: 'Lx/Tx', rangemode: 'tozero' }) }, PC);
}

function drawHist(u) {
  // 구간 개수는 직접 센다(Plotly 자동 히스토그램이 맨 끝 값을 화면 범위에서 빠뜨리는 경우가 있었다).
  const units = U(), all = units.filter(x => x.de != null).map(x => x.de);
  if (!all.length) { plotMessage('dHist', 'De가 계산된 단위 없음'); return; }
  const lo = Math.min(...all), hi = Math.max(...all);
  const NB = 15, size = (hi - lo) / NB || 1, edges = [...Array(NB)].map((_, k) => lo + k * size);
  const count = a => { const c = Array(NB).fill(0); a.forEach(x => c[Math.min(NB - 1, Math.floor((x.de - lo) / size))]++); return c; };
  const ok = units.filter(x => x.de != null && x.rc_status === 'OK'), no = units.filter(x => x.de != null && x.rc_status !== 'OK');
  const noDe = units.length - all.length;
  const bar = (a, name, color) => ({ type: 'bar', name, x: edges.map(e => e + size / 2), y: count(a), width: size,
    marker: { color, line: { color: '#fff', width: 1 } }, customdata: edges.map(e => `${e.toFixed(0)}–${(e + size).toFixed(0)}`),
    hovertemplate: '%{customdata} s: %{y}개<extra>' + name + '</extra>' });
  const shapes = u.de == null ? [] : [{ type: 'line', x0: u.de, x1: u.de, y0: 0, y1: 1, yref: 'paper', line: { color: C.ink, width: 1.5, dash: 'dash' } }];
  plot('dHist', [bar(no, `탈락 (${no.length})` + (noDe ? ` · De 계산 불가 ${noDe}개 제외` : ''), C.fail), bar(ok, `통과 (${ok.length})`, C.pass)],
    { ...BASE, barmode: 'stack', shapes, title: title('De 분포 · 점선 = 선택한 단위'), xaxis: ax({ title: 'De (s)' }), yaxis: ax({ title: '개수' }) }, PC);
}

// 방사형 그래프. 원점에서 뻗는 직선 하나가 De 값 하나다(기울기 = log De − log 중심값).
// 두 축의 단위가 달라서 호는 화면 픽셀 기준으로 원이어야 한다(R도 그렇게 그린다). 한 번 그려 영역 크기를 잰 뒤 다시 그린다.
function drawRadial(u) {
  const A = run.age, gd = $('dRadial');
  if (!A.ok) { plotMessage('dRadial', '방사형 그래프를 그릴 수 없음: ' + A.error); return; }
  if (!gd.data) gd.replaceChildren();
  const P = A.distribution.points, z0 = Math.log(A.distribution.central_de), des = P.map(p => p.de);
  const X = Math.max(...P.map(p => p.radial_x)) * 1.3;
  const lo = Math.min(...des), hi = Math.max(...des);
  const raw = (hi - lo) / 4 || lo / 4, mag = 10 ** Math.floor(Math.log10(raw)), step = [1, 2, 2.5, 5, 10].map(m => m * mag).find(m => m >= raw);
  const ticks = []; for (let v = Math.max(step, Math.floor(lo / step) * step); v <= Math.ceil(hi / step) * step + 1e-9; v += step) ticks.push(v);
  const selPt = u.rc_status === 'OK' ? P.findIndex(p => Math.abs(p.de - u.de) < 1e-6) : -1;
  const note = selPt < 0 ? ' · 선택한 단위는 탈락이라 없음' : '';
  const layout = Y => ({ ...BASE, title: title('방사형 그래프 (호: De 눈금, s)' + note),
    xaxis: ax({ title: '정밀도 (1/상대오차)', range: [0, X] }), yaxis: ax({ title: '표준화 거리', range: [-Y, Y] }) });
  const pts = { x: P.map(p => p.radial_x), y: P.map(p => p.radial_y), mode: 'markers', name: '통과한 De', marker: { color: C.pass, size: 9 },
    text: P.map(p => `De ${fmt(p.de)} ± ${fmt(p.de_error)} s`), hovertemplate: '%{text}<extra></extra>' };
  let Y = Math.max(3, ...P.map(p => Math.abs(p.radial_y))) * 1.15;
  plot(gd, [pts], layout(Y));
  const W = gd._fullLayout._size.w, H = gd._fullLayout._size.h, r = W * 0.78;
  const arcPt = (s, rad, Yv) => { const m = s * (H / (2 * Yv)) / (W / X), px = rad / Math.sqrt(1 + m * m); return [px * X / W, m * px * 2 * Yv / H]; };
  const sOf = v => Math.log(v) - z0, sMax = Math.max(...ticks.map(v => Math.abs(sOf(v))));
  for (let i = 0; i < 40 && Math.abs(arcPt(sMax, r * 1.1, Y)[1]) > Y * 0.95; i++) Y *= 1.1;
  const sLo = sOf(ticks[0]), sHi = sOf(ticks[ticks.length - 1]);
  const arc = [...Array(81)].map((_, i) => arcPt(sLo + (sHi - sLo) * i / 80, r, Y));
  const seg = f => ({ x: ticks.flatMap(v => [...f(v).map(q => q[0]), null]), y: ticks.flatMap(v => [...f(v).map(q => q[1]), null]) });
  const grey = { color: C.muted, width: 1 }, end0 = arcPt(0, r, Y)[0];
  const traces = [
    { x: [0, end0, end0, 0], y: [2, 2, -2, -2], mode: 'lines', fill: 'toself', fillcolor: 'rgba(108,122,121,0.15)', line: { width: 0 }, hoverinfo: 'skip', name: '±2' },
    { ...seg(v => [[0, 0], arcPt(sOf(v), r, Y)]), mode: 'lines', line: { color: C.line, width: 1 }, hoverinfo: 'skip', showlegend: false },
    { x: [0, end0], y: [0, 0], mode: 'lines', line: { color: C.fit, dash: 'dash' }, name: `중심값 ${fmt(A.distribution.central_de)} s`, hoverinfo: 'skip' },
    { x: arc.map(a => a[0]), y: arc.map(a => a[1]), mode: 'lines', line: grey, hoverinfo: 'skip', showlegend: false },
    { ...seg(v => [arcPt(sOf(v), r, Y), arcPt(sOf(v), r * 1.025, Y)]), mode: 'lines', line: grey, hoverinfo: 'skip', showlegend: false },
    { x: ticks.map(v => arcPt(sOf(v), r * 1.045, Y)[0]), y: ticks.map(v => arcPt(sOf(v), r * 1.045, Y)[1]), mode: 'text', text: ticks.map(String),
      textposition: 'middle right', textfont: { size: 11, color: C.muted }, hoverinfo: 'skip', showlegend: false },
    pts];
  if (selPt >= 0) traces.push({ x: [P[selPt].radial_x], y: [P[selPt].radial_y], mode: 'markers', name: '선택', hoverinfo: 'skip',
    marker: { size: 18, color: 'rgba(0,0,0,0)', line: { color: C.ink, width: 1.5 } } });
  plot(gd, traces, layout(Y));
}

// 디스크 지도. A: 선택한 디스크의 10×10 구멍(번호는 왼쪽 위부터 가로 순서로 가정). B: 디스크 전체.
function renderMap() {
  const units = U(), u = units[sel], map = $('map'); map.replaceChildren();
  const cell = (label, k) => {
    const c = el('div', label, 'cell');
    if (k >= 0) {
      const x = units[k];
      c.classList.add(x.rc_status === 'OK' ? 'pass' : 'fail');
      c.title = `${unitLabel(x)} · De ${fmt(x.de)} s`; c.onclick = () => select(k);
      if (k === sel) c.classList.add('cur');
    }
    map.append(c);
  };
  if (run.mode === 'single_grain') {
    map.className = 'map';
    $('mapDisc').value = u.position;
    $('mapTitle').textContent = '디스크 지도';
    $('mapNote').textContent = '구멍 번호는 왼쪽 위부터 가로 순서로 배치함(실제 디스크 배치와 같은지 확인 필요).';
    for (let g = 1; g <= 100; g++) cell(g, units.findIndex(x => x.position === u.position && x.grain === g));
  } else {
    map.className = 'map discs';
    $('mapTitle').textContent = '디스크 전체';
    $('mapNote').textContent = 'B 모드는 디스크 하나가 분석 단위임.';
    units.forEach((x, k) => cell(x.position, k));
  }
}
$('mapDisc').onchange = e => { const k = U().findIndex(x => x.position == e.target.value); if (k >= 0) select(k); };

// 선택한 단위의 QC 기준별 값(통과·탈락의 이유)
function renderQC(u) {
  const t = $('qc'); t.replaceChildren();
  const h = el('tr'); ['기준', '값', '임계값', '판정'].forEach(x => h.append(el('th', x))); t.append(h);
  arr(run.sar.qc).filter(q => q.position === u.position && (run.mode !== 'single_grain' || q.grain === u.grain)).forEach(q => {
    const r = el('tr'), ok = q.status === 'OK';
    r.append(el('td', q.criteria), el('td', fmt(q.value, 3), 'num'), el('td', q.threshold == null ? '—' : q.threshold, 'num'), el('td', ok ? '● 통과' : '✕ 탈락', ok ? 'ok' : 'no'));
    t.append(r);
  });
}

function renderTable() {
  const t = $('units'), only = $('onlyPass').checked; t.replaceChildren();
  const sgMode = run.mode === 'single_grain';
  const h = el('tr'); [...(sgMode ? ['디스크', '알갱이'] : ['디스크']), 'De (s)', '판정', 'Recycling', '적합', '경고'].forEach(x => h.append(el('th', x))); t.append(h);
  let n = 0;
  U().forEach((u, i) => {
    const pass = u.rc_status === 'OK'; if (only && !pass) return; n++;
    const r = el('tr', null, 'pick'); r.dataset.i = i;
    (sgMode ? [u.position, u.grain] : [u.position]).forEach(x => r.append(el('td', x, 'num')));
    const w = el('td', u.warning ? '있음' : ''); if (u.warning) w.title = u.warning;
    r.append(el('td', `${fmt(u.de)} ± ${fmt(u.de_error)}`, 'num'), el('td', pass ? '● 통과' : '✕ 탈락', pass ? 'ok' : 'no'),
             el('td', fmt(u.recycling_ratio, 3), 'num'), el('td', u.fit ?? ''), w);
    if (i === sel) r.classList.add('sel');
    r.onclick = () => select(i); t.append(r);
  });
  $('tableCount').textContent = `${n}개 표시 / 전체 ${U().length}개`;
}
$('onlyPass').onchange = renderTable;
$('prevBtn').onclick = () => select(sel - 1);
$('nextBtn').onclick = () => select(sel + 1);
document.addEventListener('keydown', e => {
  if (!run || tab !== 'dash' || /INPUT|SELECT/.test(document.activeElement.tagName)) return;
  if (e.key === 'ArrowLeft') select(sel - 1); else if (e.key === 'ArrowRight') select(sel + 1);
});

// ---- 04 모델
function renderModel() {
  const A = run.age, box = $('modelBox'); box.replaceChildren();
  if (!A.ok) { box.append(el('p', '계산할 수 없음: ' + A.error)); return; }
  const R = A.result, rec = A.recommendation;
  box.append(el('p', MODE_LABEL[run.mode] + ' · ' + (A.model_source === 'rule' ? '규칙 추천' : '사용자 지정'), 'axis'),
             el('div', `추천 모델: ${rec.model}`, 'big'));
  const ul = el('ul'); arr(rec.reasons).forEach(x => ul.append(el('li', x))); box.append(ul);
  if (R.model === 'FMM') {
    const tt = el('table'), h = el('tr'); ['성분', '선량 (s)', '비율'].forEach(x => h.append(el('th', x))); tt.append(h);
    arr(R.components).forEach((c, k) => { const r = el('tr'); [k + 1, `${fmt(c.dose)} ± ${fmt(c.dose_error)}`, `${fmt(100 * c.proportion, 0)}%`].forEach(x => r.append(el('td', x, 'num'))); tt.append(r); });
    box.append(el('p', 'FMM은 연대로 쓸 성분을 고르지 않음(연구자 판단).'), tt);
  } else {
    box.append(el('p', `대표 선량: ${fmt(R.dose)} ± ${fmt(R.dose_error)} s`, 'big'));
  }
  box.append(el('p', `사용한 De ${R.n}개 · 과분산 ${fmt(A.distribution.od_rel)}% · sigmab ${R.sigmab == null ? '미사용' : R.sigmab}. 최소 개수 기준은 연구자 확인 대기.`, 'note'),
             el('p', `${R.package} ${R.package_version} · R ${run.meta.r_version}`, 'note'));
}

// ---- 시작
if (!window.Plotly) document.querySelectorAll('.plot').forEach(p => p.replaceChildren(el('div', '그래프 라이브러리를 불러오지 못함. 표와 텍스트는 표시됨.', 'empty')));
renderContext();
renderFile();
fillGrains();
go(location.hash.slice(1));
document.fonts.ready.then(() => { syncSeg(); go(location.hash.slice(1)); });   // 글꼴이 바뀌면 탭·버튼 폭이 달라지므로 다시 맞춘다
let rt; window.addEventListener('resize', () => { clearTimeout(rt); rt = setTimeout(() => {
  syncSeg();
  document.querySelectorAll('.plot').forEach(gd => { if (gd.data) Plotly.relayout(gd, legendLayout(gd)); });   // 그래프 높이가 바뀌면 범례 위치도 다시 계산
  if (run && tab === 'dash') drawRadial(U()[sel]);
}, 150); });
