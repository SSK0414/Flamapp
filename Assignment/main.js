const svg = document.getElementById('svg');

// config
const PAD = 30;
const TANGENT_COUNT = 16;
const tStepSample = 0.01;
const tangentPixelLen = 28;

let L = { left:0, top:0, size:0 };

const clamp01 = v => Math.max(0, Math.min(1, v));
const lerp = (a,b,t) => a + (b-a)*t;

function bezierPoint(t, P0, P1, P2, P3){
  const it = 1 - t; const it2 = it*it; const t2 = t*t;
  const b0 = it2*it; const b1 = 3*it2*t; const b2 = 3*it*t2; const b3 = t*t2;
  return {
    x: b0*P0.x + b1*P1.x + b2*P2.x + b3*P3.x,
    y: b0*P0.y + b1*P1.y + b2*P2.y + b3*P3.y
  };
}
function bezierTangent(t, P0, P1, P2, P3){
  const it = 1 - t;
  return {
    x: 3*it*it*(P1.x-P0.x) + 6*it*t*(P2.x-P1.x) + 3*t*t*(P3.x-P2.x),
    y: 3*it*it*(P1.y-P0.y) + 6*it*t*(P2.y-P1.y) + 3*t*t*(P3.y-P2.y)
  };
}

function normToPx(n){ return { x: L.left + n.x * L.size, y: L.top + n.y * L.size }; }
function pxToNorm(px, py){ return { x: clamp01((px - L.left) / L.size), y: clamp01((py - L.top) / L.size) }; }

// DOM references
const box = document.getElementById('box');
const gridG = document.getElementById('grid');
const handleLineLeft = document.getElementById('handleLineLeft');
const handleLineRight = document.getElementById('handleLineRight');
const curvePath = document.getElementById('curvePath');
const labelP1 = document.getElementById('labelP1');
const labelP2 = document.getElementById('labelP2');
const circleP1 = document.getElementById('circleP1');
const circleP2 = document.getElementById('circleP2');

// tangents array (0 - 16) 
const tangentLines = [];
for (let i=0;i<=TANGENT_COUNT;i++) tangentLines.push(document.getElementById('t' + i));


const P0 = { x:0, y:0.5 }, P3 = { x:1, y:0.5 };

let pos1 = { x:0.25, y:0.2 }, pos2 = { x:0.75, y:0.8 };
let vel1 = { x:0, y:0 }, vel2 = { x:0, y:0 };
let target1 = {...pos1}, target2 = {...pos2};

let STIFF = 28.0, DAMP = 8.0;

function stepSpringNorm(pos, vel, target, k, damping, dt){
  const ax = -k * (pos.x - target.x) - damping * vel.x;
  const ay = -k * (pos.y - target.y) - damping * vel.y;
  vel.x += ax * dt; vel.y += ay * dt;
  pos.x += vel.x * dt; pos.y += vel.y * dt;
}

/* ---------- input: selection & dragging ---------- */
let selected = null;       // 'p1' | 'p2' | null
let dragging = null;       // 'p1' | 'p2' | null
let pointerId = null;

function setSelected(id){
  selected = id;
  const params = document.getElementById('params');
  if (params) {
    const selText = selected ? `selected: ${selected.toUpperCase()}` : 'selected: none';
    params.textContent = `stiff: ${STIFF.toFixed(1)}   damp: ${DAMP.toFixed(1)}   •   ${selText}`;
  }
}

// pointer events
svg.addEventListener('pointerdown', (e) => {
  const pt = svg.createSVGPoint(); pt.x = e.clientX; pt.y = e.clientY;
  const loc = pt.matrixTransform(svg.getScreenCTM().inverse());
  const n = pxToNorm(loc.x, loc.y);
  const p1px = normToPx(pos1), p2px = normToPx(pos2);
  const d1 = Math.hypot(loc.x - p1px.x, loc.y - p1px.y);
  const d2 = Math.hypot(loc.x - p2px.x, loc.y - p2px.y);
  const HIT = 14;
  if (d1 < HIT && (d1 <= d2 || d2 > HIT)) {
    dragging = 'p1'; pointerId = e.pointerId; svg.setPointerCapture(pointerId);
    target1 = n; pos1 = {...n}; vel1.x = vel1.y = 0;
  } else if (d2 < HIT) {
    dragging = 'p2'; pointerId = e.pointerId; svg.setPointerCapture(pointerId);
    target2 = n; pos2 = {...n}; vel2.x = vel2.y = 0;
  }
});

svg.addEventListener('pointermove', (e) => {
  const pt = svg.createSVGPoint(); pt.x = e.clientX; pt.y = e.clientY;
  const loc = pt.matrixTransform(svg.getScreenCTM().inverse());
  const n = pxToNorm(loc.x, loc.y);

  if (dragging && e.pointerId === pointerId) {
    if (dragging === 'p1') { pos1 = {...n}; target1 = {...n}; vel1.x = vel1.y = 0; }
    if (dragging === 'p2') { pos2 = {...n}; target2 = {...n}; vel2.x = vel2.y = 0; }
    return;
  }

  if (selected === 'p1') {
    const G = 0.26;
    target1.x = lerp(target1.x, clamp01(n.x), G);
    target1.y = lerp(target1.y, clamp01(n.y), G);
  } else if (selected === 'p2') {
    const G = 0.26;
    target2.x = lerp(target2.x, clamp01(n.x), G);
    target2.y = lerp(target2.y, clamp01(n.y), G);
  } else {
    // no selection
  }
});

svg.addEventListener('pointerup', (e)=> {
  if (dragging && e.pointerId === pointerId) {
    try{ svg.releasePointerCapture(pointerId); }catch(e){}
    dragging = null; pointerId = null;
  }
});
svg.addEventListener('pointercancel', (e)=> {
  if (dragging && e.pointerId === pointerId) {
    try{ svg.releasePointerCapture(pointerId); }catch(e){}
    dragging = null; pointerId = null;
  }
});

/* device orientation mapping */
function attachOrientation(){
  if (typeof DeviceOrientationEvent !== 'undefined' && typeof DeviceOrientationEvent.requestPermission === 'function') {
    DeviceOrientationEvent.requestPermission().then(resp => {
      if (resp === 'granted') window.addEventListener('deviceorientation', handleDevice);
    }).catch(() => {
        //ignore
    });
  } else {
    window.addEventListener('deviceorientation', handleDevice);
  }
}

function handleDevice(ev){
  const pitch = ev.beta || 0; const roll = ev.gamma || 0;
  const nx = clamp01(0.5 + roll / 90 * 0.45);
  const ny = clamp01(0.5 + pitch / 90 * 0.45);
  target1.x = lerp(target1.x, nx, 0.16); target1.y = lerp(target1.y, ny, 0.16);
  target2.x = lerp(target2.x, nx, 0.16); target2.y = lerp(target2.y, ny, 0.16);
}
svg.addEventListener('click', ()=> attachOrientation(), { once:true });

window.addEventListener('keydown', (e) => {
  const k = e.key.toLowerCase();
  if (k === '1') { setSelected('p1'); return; }
  if (k === '2') { setSelected('p2'); return; }
  if (k === '0') { setSelected(null); return; }
  if (k === 'w' || k === 'arrowup') STIFF = Math.min(140, STIFF + 1);
  if (k === 's' || k === 'arrowdown') STIFF = Math.max(1, STIFF - 1);
  if (k === 'd' || k === 'arrowright') DAMP = Math.min(80, DAMP + 0.5);
  if (k === 'a' || k === 'arrowleft') DAMP = Math.max(0, DAMP - 0.5);
  if (k === 'r') {
    pos1 = {x:0.25,y:0.2}; pos2 = {x:0.75,y:0.8};
    vel1 = {x:0,y:0}; vel2 = {x:0,y:0};
    target1 = {...pos1}; target2 = {...pos2};
    return;
  }

  const ARROW_STEP = e.shiftKey ? 0.05 : 0.01;
  if (['arrowup','arrowdown','arrowleft','arrowright'].includes(e.key.toLowerCase())) {
    if (!selected) return;
    let dx = 0, dy = 0;
    if (e.key === 'ArrowLeft') dx = -ARROW_STEP;
    if (e.key === 'ArrowRight') dx = ARROW_STEP;
    if (e.key === 'ArrowUp') dy = -ARROW_STEP;
    if (e.key === 'ArrowDown') dy = ARROW_STEP;
    if (selected === 'p1') { target1.x = clamp01(target1.x + dx); target1.y = clamp01(target1.y + dy); }
    if (selected === 'p2') { target2.x = clamp01(target2.x + dx); target2.y = clamp01(target2.y + dy); }
  }
});

// Animation loop
let last = performance.now();

function layout(){
  const W = window.innerWidth, H = window.innerHeight;
  const outer = Math.min(W,H) * 0.9;
  L.size = outer - 2*PAD;
  L.left = (W - outer) / 2 + PAD;
  L.top = (H - outer) / 2 + PAD;
  svg.setAttribute('viewBox', `0 0 ${W} ${H}`);
  box.setAttribute('x', L.left); box.setAttribute('y', L.top);
  box.setAttribute('width', L.size); box.setAttribute('height', L.size);
  buildGrid();
}
function buildGrid(){
  while (gridG.firstChild) gridG.removeChild(gridG.firstChild);
  const steps = 6;
  for (let i=0;i<=steps;i++){
    const x = L.left + i * (L.size / steps);
    const ln = document.createElementNS ? document.createElementNS('http://www.w3.org/2000/svg','line') : document.createElement('line');
    ln.setAttribute('x1', x); ln.setAttribute('x2', x); ln.setAttribute('y1', L.top); ln.setAttribute('y2', L.top+L.size);
    ln.setAttribute('class','grid-line'); gridG.appendChild(ln);
    const y = L.top + i * (L.size / steps);
    const ln2 = document.createElementNS ? document.createElementNS('http://www.w3.org/2000/svg','line') : document.createElement('line');
    ln2.setAttribute('x1', L.left); ln2.setAttribute('x2', L.left+L.size); ln2.setAttribute('y1', y); ln2.setAttribute('y2', y);
    ln2.setAttribute('class','grid-line'); gridG.appendChild(ln2);
  }
}

function render(){
  // sameple curve  
  const samples = [];
  for (let t=0; t<=1+1e-8; t+=tStepSample) {
    const p = bezierPoint(Math.min(1,t), P0, pos1, pos2, P3);
    samples.push(normToPx(p));
  }
  if (samples.length) {
    let d = `M ${samples[0].x} ${samples[0].y}`;
    for (let i=1;i<samples.length;i++) d += ` L ${samples[i].x} ${samples[i].y}`;
    curvePath.setAttribute('d', d);
  }

  // tangents
  for (let i=0;i<=TANGENT_COUNT;i++){
    const tt = i / TANGENT_COUNT;
    const p = bezierPoint(tt, P0, pos1, pos2, P3);
    const tan = bezierTangent(tt, P0, pos1, pos2, P3);
    const len = Math.hypot(tan.x, tan.y) || 1;
    const nx = tan.x / len, ny = tan.y / len;
    const ppx = normToPx(p);
    const x1 = ppx.x, y1 = ppx.y;
    const x2 = ppx.x + nx * tangentPixelLen;
    const y2 = ppx.y + ny * tangentPixelLen;
    const ln = tangentLines[i];
    ln.setAttribute('x1', x1); ln.setAttribute('y1', y1);
    ln.setAttribute('x2', x2); ln.setAttribute('y2', y2);
  }

  // helper lines & circles & labels
  const start = normToPx(P0), end = normToPx(P3);
  const p1px = normToPx(pos1), p2px = normToPx(pos2);
  handleLineLeft.setAttribute('d', `M ${start.x} ${start.y} L ${p1px.x} ${p1px.y}`);
  handleLineRight.setAttribute('d', `M ${end.x} ${end.y} L ${p2px.x} ${p2px.y}`);

  circleP1.setAttribute('cx', p1px.x); circleP1.setAttribute('cy', p1px.y);
  circleP2.setAttribute('cx', p2px.x); circleP2.setAttribute('cy', p2px.y);
  labelP1.setAttribute('x', p1px.x); labelP1.setAttribute('y', p1px.y - 18); labelP1.textContent = `P1: ${pos1.x.toFixed(2)}, ${pos1.y.toFixed(2)}`;
  labelP2.setAttribute('x', p2px.x); labelP2.setAttribute('y', p2px.y - 18); labelP2.textContent = `P2: ${pos2.x.toFixed(2)}, ${pos2.y.toFixed(2)}`;

  circleP1.setAttribute('stroke-width', selected === 'p1' ? '2.4' : '1.2');
  circleP2.setAttribute('stroke-width', selected === 'p2' ? '2.4' : '1.2');

  const params = document.getElementById('params');
  if (params) {
    const selText = selected ? `selected: ${selected.toUpperCase()}` : 'selected: none';
    params.textContent = `stiff: ${STIFF.toFixed(1)}   damp: ${DAMP.toFixed(1)}   •   ${selText}`;
  }
}

function frame(now){
  const rawDt = (now - last) / 1000;
  last = now;
  const dt = Math.min(0.033, rawDt);
  if (dragging !== 'p1') stepSpringNorm(pos1, vel1, target1, STIFF, DAMP, dt);
  if (dragging !== 'p2') stepSpringNorm(pos2, vel2, target2, STIFF, DAMP, dt);
  render();
  requestAnimationFrame(frame);
}

window.addEventListener('resize', layout);
layout();
last = performance.now();
requestAnimationFrame(frame);
