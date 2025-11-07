# Interactive Bézier Rope

An **interactive cubic Bézier curve** that behaves like a **springy rope** — responding smoothly to mouse or touch input (and device tilt, if available).
You can control the two inner control points independently, and the curve reacts with natural motion using a spring-damping physics model.

---

## Concept

This project visualizes a **cubic Bézier curve** while simulating physical spring behavior on its control points.

The main goal was to merge **mathematical precision** (Bézier geometry) with **dynamic motion** (simple physics integration).

---

## Math Behind the Curve

A **cubic Bézier** is defined by 4 points:
`P0`, `P1`, `P2`, and `P3`.

$$
B(t) = (1 - t)^3P_0 + 3(1 - t)^2tP_1 + 3(1 - t)t^2P_2 + t^3P_3
$$

where `t` ranges from `0 → 1`.

* `P0` and `P3` are **fixed endpoints** (left and right midpoints of the canvas).
* `P1` and `P2` are **control handles** that define the curvature.

To compute tangents (the rope’s direction at a point), we use the derivative:

$$
B'(t) = 3(1 - t)^2(P_1 - P_0) + 6(1 - t)t(P_2 - P_1) + 3t^2(P_3 - P_2)
$$

These tangent vectors are normalized and drawn as short lines along the curve to visualize slope and motion.

---

## Physics Model

Each handle (`P1` and `P2`) moves under a **spring-damping system**, using **semi-implicit Euler integration**.

The model:

$$
a = -k(x - x_{target}) - c v
$$

where:

* `k` = stiffness → how strong the spring pulls toward its target
* `c` = damping → friction that reduces oscillation
* `v` = velocity of the handle
* `x_target` = target position (from mouse, key, or sensor input)

Then the simulation updates every frame:

$$
v += a \cdot \Delta t
$$
$$
x += v \cdot \Delta t
$$

This produces smooth, physically plausible motion — like an elastic rope returning to rest.

---

## Design Choices

### Interaction

* You can **select which handle** to control:

  * `1` → select **P1**
  * `2` → select **P2**
  * `0` → deselect
* Drag handles directly to reposition them.
* Use **arrow keys** to nudge the selected handle.
* Use **W/S** and **A/D** to adjust stiffness and damping.
* Press **R** to reset to defaults.
* On mobile, tap once to allow **device motion** (tilt control).

### Visuals

* A centered, clean layout using **SVG**.
* Blue curve (`#79c7ff`) and amber tangents (`#ffd28c`).
* Subtle grid and soft glow background for visual contrast.
* Labels show the normalized coordinates of control points.

### Implementation

* Written in **vanilla JavaScript + SVG**, no external libraries.
* Mathematical and physics logic done manually — no prebuilt animation or Bézier APIs.
* Simplified DOM (all SVG elements declared directly in HTML, no runtime creation).

---

## How to Run

1. Save `index.html`, `main.js`, and this `README.md` in one folder.
2. Open `index.html` in a modern browser.
3. Drag or nudge handles to shape the rope — enjoy the motion.
