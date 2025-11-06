// --- Spring integrator (semi-implicit Euler) ---
function stepSpring(pos, vel, target, k, damping, dt) {
    // pos, vel, target: objects {x,y}
    // modifies pos and vel in-place
    const ax = -k * (pos.x - target.x) - damping * vel.x;
    const ay = -k * (pos.y - target.y) - damping * vel.y;
    vel.x += ax * dt;
    vel.y += ay * dt;
    pos.x += vel.x * dt;
    pos.y += vel.y * dt;
    return { pos, vel };
}

// --- Canvas setup ---
const canvas = document.getElementById('c');
const ctx = canvas.getContext('2d');

function fitCanvas() {
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;
}
window.addEventListener('resize', fitCanvas);
fitCanvas();

// --- Test state ---
let point = { x: canvas.width * 0.5, y: canvas.height * 0.5 }; // mass position
let vel = { x: 0, y: 0 };
let target = { x: point.x, y: point.y }; // target follows mouse

// physics params (tweak with values below)
// Renamed for clearer HUD: STIFF = stiffness (k), FRICTION = damping (c)
let STIFF = 40.0;     // stiffness (k)
let FRICTION = 8.0;   // damping (c)

// update target from pointer
window.addEventListener('mousemove', (e) => {
    target.x = e.clientX;
    target.y = e.clientY;
});
window.addEventListener('touchmove', (e) => {
    if (!e.touches || !e.touches.length) return;
    target.x = e.touches[0].clientX;
    target.y = e.touches[0].clientY;
}, { passive: true });

// basic keyboard controls for quick tuning
window.addEventListener('keydown', (e) => {
    const key = e.key.toLowerCase();
    // Increase / decrease stiffness
    if (key === 'arrowup' || key === 'w') STIFF = Math.min(200, STIFF + 5);
    if (key === 'arrowdown' || key === 's') STIFF = Math.max(1, STIFF - 5);
    // Increase / decrease damping / friction
    if (key === 'arrowright' || key === 'd') FRICTION = Math.min(60, FRICTION + 1);
    if (key === 'arrowleft' || key === 'a') FRICTION = Math.max(0, FRICTION - 1);
    // Reset
    if (key === 'r') {
        point.x = canvas.width * 0.5; point.y = canvas.height * 0.5;
        vel.x = vel.y = 0;
        target.x = point.x; target.y = point.y;
    }
});

// --- Render helpers ---
function clear() {
    ctx.fillStyle = '#0b0f14';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
}

function drawCircle(p, r, color) {
    ctx.beginPath();
    ctx.arc(p.x, p.y, r, 0, Math.PI * 2);
    ctx.fillStyle = color || '#79c7ff';
    ctx.fill();
}

function drawLine(a, b, color, lw=1) {
    ctx.beginPath();
    ctx.moveTo(a.x, a.y);
    ctx.lineTo(b.x, b.y);
    ctx.strokeStyle = color || '#ffffff';
    ctx.lineWidth = lw;
    ctx.stroke();
}

// --- Animation loop ---
let last = performance.now();
function loop(now) {
    const rawDt = (now - last) / 1000; // seconds
    last = now;
    const dt = Math.min(0.033, rawDt); // clamp dt for stability

    // physics step: use STIFF and FRICTION
    stepSpring(point, vel, target, STIFF, FRICTION, dt);

    // draw
    clear();

    // draw target (small red)
    drawCircle(target, 6, '#ff6b6b');

    // draw mass (big circle)
    drawCircle(point, 12, '#9be7ff');

    // draw helper line
    drawLine(point, target, 'rgba(255,255,255,0.08)', 2);

    // HUD text
    ctx.fillStyle = '#e7eef7';
    ctx.font = '14px system-ui, Arial';
    ctx.fillText(`Stiffness = ${STIFF.toFixed(1)}    Friction = ${FRICTION.toFixed(1)}`, 12, 22);
    ctx.fillText('W/S or ↑/↓ -> stiffness, A/D or ←/→ -> friction, R -> reset', 12, 40);

    requestAnimationFrame(loop);
}

requestAnimationFrame(loop);
