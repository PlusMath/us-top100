// 공통 캔들차트 렌더러 — 기간 전환(1개월/3개월/6개월/1년) + 마우스 호버 툴팁
// data: [{d:'YYYY-MM-DD', o,h,l,c}, ...] (오름차순, USD 단위), 외부 CDN 없이 순수 SVG로 렌더링
function renderCandleChart(cfg) {
  const svg = document.getElementById(cfg.svgId);
  if (!svg) return;
  const data = cfg.data;
  const W = 720, H = 240, pL = 64, pR = 12, pT = 14, pB = 24;
  const cW = W - pL - pR, cH = H - pT - pB;

  function cssVar(name) { return getComputedStyle(document.documentElement).getPropertyValue(name).trim(); }
  function svgEl(tag, attrs) {
    const e = document.createElementNS('http://www.w3.org/2000/svg', tag);
    for (const k in attrs) e.setAttribute(k, attrs[k]);
    return e;
  }
  function calcMA(arr, n) {
    return arr.map((_, i) => i < n - 1 ? null : arr.slice(i - n + 1, i + 1).reduce((s, x) => s + x.c, 0) / n);
  }
  function fmtMD(dateStr) { const p = dateStr.split('-'); return p[1] + '/' + p[2]; }
  function usd(v) { return '$' + v.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); }

  const ma5Full = calcMA(data, 5), ma20Full = calcMA(data, 20), ma60Full = calcMA(data, 60), ma120Full = calcMA(data, 120);

  // 차트를 감싸는 wrap(툴팁 절대위치 기준) 준비
  let wrap = svg.closest('.kc-chart-wrap');
  if (!wrap) {
    wrap = document.createElement('div');
    wrap.className = 'kc-chart-wrap';
    svg.parentNode.insertBefore(wrap, svg);
    wrap.appendChild(svg);
  }
  let tip = wrap.querySelector('.kc-tooltip');
  if (!tip) {
    tip = document.createElement('div');
    tip.className = 'kc-tooltip';
    wrap.appendChild(tip);
  }

  function render(periodDays) {
    const n = data.length;
    const startIdx = periodDays >= n ? 0 : n - periodDays;
    const slice = data.slice(startIdx);
    const ma5 = ma5Full.slice(startIdx), ma20 = ma20Full.slice(startIdx), ma60 = ma60Full.slice(startIdx), ma120 = ma120Full.slice(startIdx);

    while (svg.firstChild) svg.removeChild(svg.firstChild);

    const prices = slice.flatMap(d => [d.h, d.l]);
    const maxP = Math.max(...prices) * 1.02, minP = Math.min(...prices) * 0.98;
    const rng = (maxP - minP) || 1;
    function py(v) { return pT + cH * (1 - (v - minP) / rng); }
    const colW = cW / slice.length, cw = Math.max(colW * 0.62, 1.2);
    const gridCol = cssVar('--color-text-tertiary');

    for (let i = 0; i <= 4; i++) {
      const v = minP + rng * i / 4;
      const y = py(v);
      svg.appendChild(svgEl('line', { x1: pL, x2: pL + cW, y1: y, y2: y, stroke: gridCol, opacity: 0.15, 'stroke-width': 1 }));
      const t = svgEl('text', { x: pL - 4, y: y + 3, 'text-anchor': 'end', 'font-size': 9, fill: gridCol, opacity: 0.85 });
      t.textContent = usd(v);
      svg.appendChild(t);
    }

    function drawLine(arr, col, w) {
      let pts = [];
      arr.forEach((v, i) => { if (v === null) return; pts.push(`${pL + (i + 0.5) * colW},${py(v)}`); });
      if (pts.length < 2) return;
      svg.appendChild(svgEl('polyline', { points: pts.join(' '), fill: 'none', stroke: col, 'stroke-width': w || 1.3 }));
    }

    slice.forEach((d, i) => {
      const cx = pL + (i + 0.5) * colW, isUp = d.c >= d.o, col = isUp ? '#A6811A' : '#0B2545';
      svg.appendChild(svgEl('line', { x1: cx, x2: cx, y1: py(d.h), y2: py(d.l), stroke: col, 'stroke-width': 1 }));
      const bT = py(Math.max(d.o, d.c)), bB = py(Math.min(d.o, d.c));
      svg.appendChild(svgEl('rect', { x: cx - cw / 2, y: bT, width: cw, height: Math.max(bB - bT, 1), fill: col, rx: 0 }));
    });

    drawLine(ma5, '#B8571F', 1.3);
    drawLine(ma20, '#5B7A99', 1.3);
    drawLine(ma60, '#7A5A16', 1.6);
    drawLine(ma120, '#2F5233', 1.6);

    let hiIdx = 0, loIdx = 0;
    slice.forEach((d, i) => { if (d.h > slice[hiIdx].h) hiIdx = i; if (d.l < slice[loIdx].l) loIdx = i; });
    const hi = slice[hiIdx], lo = slice[loIdx];
    const mkLabel = (idx, val, dateStr, isLow, col) => {
      const cx = pL + (idx + 0.5) * colW, cy = isLow ? py(val) + 12 : py(val) - 8;
      const t = svgEl('text', { x: cx, y: cy, 'text-anchor': 'middle', 'font-size': 9, fill: col, 'font-weight': 600 });
      t.textContent = (isLow ? '저 ' : '고 ') + usd(val) + ' (' + fmtMD(dateStr) + ')';
      svg.appendChild(t);
    };
    mkLabel(hiIdx, hi.h, hi.d, false, '#8C2F26');
    mkLabel(loIdx, lo.l, lo.d, true, '#0B2545');

    const lastIdx = slice.length - 1, last = slice[lastIdx];
    const curCx = pL + (lastIdx + 0.5) * colW, curCy = py(last.h) - 8;
    const curT = svgEl('text', { x: curCx - 4, y: curCy, 'text-anchor': 'end', 'font-size': 9, fill: cssVar('--color-text-primary'), 'font-weight': 600 });
    curT.textContent = '현재 ' + usd(last.c);
    svg.appendChild(curT);

    const tickCount = Math.min(7, slice.length);
    for (let k = 0; k < tickCount; k++) {
      const idx = Math.round(k * (slice.length - 1) / (tickCount - 1 || 1));
      const cx = pL + (idx + 0.5) * colW;
      const t = svgEl('text', { x: cx, y: H - 4, 'text-anchor': 'middle', 'font-size': 9, fill: gridCol });
      t.textContent = fmtMD(slice[idx].d);
      svg.appendChild(t);
    }

    const legend = [['#A6811A', '상승'], ['#0B2545', '하락'], ['#B8571F', 'MA5'], ['#5B7A99', 'MA20'], ['#7A5A16', 'MA60'], ['#2F5233', 'MA120']];
    legend.forEach((l, i) => {
      const gx = pL + i * 74;
      svg.appendChild(svgEl('rect', { x: gx, y: 2, width: 9, height: 9, fill: l[0], rx: 2 }));
      const t = svgEl('text', { x: gx + 12, y: 10, 'font-size': 8.5, fill: gridCol });
      t.textContent = l[1]; svg.appendChild(t);
    });

    // 호버 오버레이 + 크로스헤어
    const overlay = svgEl('rect', { x: pL, y: pT, width: cW, height: cH, fill: 'transparent', style: 'cursor:crosshair;' });
    svg.appendChild(overlay);
    const crosshair = svgEl('line', { y1: pT, y2: pT + cH, stroke: gridCol, 'stroke-width': 1, 'stroke-dasharray': '3,3', visibility: 'hidden' });
    svg.appendChild(crosshair);

    overlay.addEventListener('mousemove', function (evt) {
      const rect = svg.getBoundingClientRect();
      const scale = rect.width / W;
      const mx = (evt.clientX - rect.left) / scale;
      let idx = Math.floor((mx - pL) / colW);
      idx = Math.max(0, Math.min(slice.length - 1, idx));
      const d = slice[idx];
      const cx = pL + (idx + 0.5) * colW;
      crosshair.setAttribute('x1', cx); crosshair.setAttribute('x2', cx);
      crosshair.setAttribute('visibility', 'visible');
      const prev = idx > 0 ? slice[idx - 1] : null;
      const chg = prev ? (d.c - prev.c) / prev.c * 100 : null;
      let chgHtml = '';
      if (chg !== null) {
        const chgCol = chg >= 0 ? '#A6811A' : '#0B2545';
        chgHtml = ' <span style="color:' + chgCol + ';font-weight:600;">' + (chg >= 0 ? '▲' : '▼') + Math.abs(chg).toFixed(2) + '%</span>';
      }
      tip.innerHTML =
        '<b>' + d.d + '</b><br>' +
        '시가 ' + usd(d.o) + ' · 고가 ' + usd(d.h) + '<br>' +
        '저가 ' + usd(d.l) + ' · 종가 ' + usd(d.c) + chgHtml;
      tip.style.visibility = 'visible';
      const wrapRect = wrap.getBoundingClientRect();
      let left = (evt.clientX - wrapRect.left) + 14;
      let top = (evt.clientY - wrapRect.top) - 12;
      if (left + 165 > wrapRect.width) left = (evt.clientX - wrapRect.left) - 175;
      tip.style.left = Math.max(0, left) + 'px';
      tip.style.top = Math.max(0, top) + 'px';
    });
    overlay.addEventListener('mouseleave', function () {
      crosshair.setAttribute('visibility', 'hidden');
      tip.style.visibility = 'hidden';
    });
  }

  const controls = cfg.controlsId ? document.getElementById(cfg.controlsId) : null;
  if (controls) {
    const periods = [['1개월', 21], ['3개월', 63], ['6개월', 126], ['1년', 9999]];
    controls.innerHTML = '';
    periods.forEach(([label, days]) => {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.textContent = label;
      btn.className = 'kc-period-btn' + (days === 9999 ? ' active' : '');
      btn.addEventListener('click', function () {
        Array.from(controls.children).forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        render(days);
      });
      controls.appendChild(btn);
    });
  }

  render(9999);
}

// 더미(랜덤워크) OHLC 데이터 생성기 — 실 데이터 연동 전 프레임 시연용
// seed: 종목코드 등 문자열, basePrice: 시작가(USD), days: 거래일수
function genDummyOHLC(seed, basePrice, days) {
  days = days || 252;
  let h = 0;
  for (let i = 0; i < seed.length; i++) h = (h * 31 + seed.charCodeAt(i)) >>> 0;
  function rand() {
    h ^= h << 13; h >>>= 0;
    h ^= h >> 17;
    h ^= h << 5; h >>>= 0;
    return (h >>> 0) / 4294967296;
  }
  const out = [];
  let price = basePrice;
  const start = new Date();
  start.setDate(start.getDate() - Math.round(days * 1.45));
  let d = new Date(start);
  let count = 0;
  while (count < days) {
    d.setDate(d.getDate() + 1);
    const dow = d.getDay();
    if (dow === 0 || dow === 6) continue;
    const drift = (rand() - 0.485) * 0.028;
    const open = price;
    price = Math.max(price * (1 + drift), basePrice * 0.15);
    const close = price;
    const hi = Math.max(open, close) * (1 + rand() * 0.012);
    const lo = Math.min(open, close) * (1 - rand() * 0.012);
    out.push({ d: d.toISOString().slice(0, 10), o: +open.toFixed(2), h: +hi.toFixed(2), l: +lo.toFixed(2), c: +close.toFixed(2) });
    count++;
  }
  return out;
}
