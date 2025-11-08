# Interactive Bézier Rope — iOS + Webapp

An interactive cubic Bézier curve that behaves like a springy rope.
This READme describes both the iOS app and the Web app implementations, their math and physics, design decisions, controls, and how to run each version.

---

## Concept

A cubic Bézier curve is rendered and sampled at small `t` increments. The two inner control points (`P1`, `P2`) are dynamic and driven by a simple spring-damping physics model so the curve reacts like an elastic rope. Tangents are computed and drawn along the curve to show local direction and motion.

---

## Math

### Cubic Bézier

For control points `P0`, `P1`, `P2`, `P3`:

$$
B(t) = (1 − t)^3 P0 + 3(1 − t)^2 t P1 + 3(1 − t) t^2 P2 + t^3 P3
$$

Sample `t` in small steps (for example `0.01`) to construct the path.

### Tangent (derivative)

$$
B'(t) = 3(1 − t)^2 (P1 − P0) + 6(1 − t) t (P2 − P1) + 3 t^2 (P3 − P2)
$$

Normalize `B'(t)` and draw short lines at intervals to visualize local direction.

---

## Physics Model

Each handle (`P1`, `P2`) uses a mass-spring-damper model with semi-implicit Euler integration:

$$
a = -k * (pos - target) - c * vel
vel += a * dt
pos += vel * dt
$$

* `k` = stiffness (spring strength)
* `c` = damping (friction)
* `target` = desired position (mouse, drag, or mapped device motion)
* Use a small, fixed physics timestep (e.g., 1/60 s) and accumulate frames for stability.

Tune `k` and `c` to get the desired softness/stretch behavior: lower `k` and moderate `c` => stretchier rope.

---

# iOS app

## Overview

* Native UIKit implementation (Swift).
* Uses CoreMotion for device motion input.
* Runs physics in a fixed-step loop driven by `CADisplayLink`.
* Renders to an offscreen image and updates a `CALayer.contents` to avoid flicker and produce atomic frame updates.
* `P0` and `P3` are fixed endpoints; `P1` and `P2` are handles controllable independently.

## Features

* Tap to select/deselect a handle. Selected handle gets gyroscope control (toggle).
* Drag a handle to move it directly (drag suspends spring physics for that handle).
* When a selected handle receives motion input, its target is nudged toward a motion-mapped point; physics makes it spring.
* `P1` uses inverted gyroscope mapping (moves opposite to device tilt). `P2` uses normal mapping.
* Adjustable parameters: stiffness, damping, gyro gains, stretch multiplier.
* Tangent visualization, small endpoint markers, monospaced coordinate labels.
* Offscreen rendering to `UIImage` then atomic `CALayer` update to eliminate flicker.

## Controls

* Tap a handle: select/deselect (toggles gyroscope control).
* Drag a handle: direct reposition (physics paused for that handle while dragging).
* Tap outside: clear selection.
* Optional runtime tuning: change `stiffness`, `damping`, `gyroGainX/Y`, `stretchMultiplier` in code or via a debug UI.

## How to run

1. Open the Xcode project (I used the suite for iOS 26 and above).
2. Connect a real iPhone for testing gyroscope features (Simulator has limited sensor emulation).
3. Build and run on the device.
4. On first tap you may request motion permission (iOS requires explicit activation for device motion).

## Implementation notes and tips

* Use a fixed-step physics accumulator (1/60 s) inside `CADisplayLink` to keep physics stable and deterministic.
* Render to `UIGraphicsImageRenderer` or similar and set `imageLayer.contents = img.cgImage` inside a `CATransaction` with actions disabled. This prevents ghosting/flicker.
* Clamp and constrain handle positions to an inner square within view bounds to avoid runaway values when device motion is aggressive.
* Keep integration semi-implicit: update velocity using acceleration first, then update position using new velocity.
* coalesce parameter was troublesome, resulting in visual artifacts and rendering issues. 

https://github.com/user-attachments/assets/c010ccd8-74f7-4172-9dfb-a087fa9527e7

---

# Web app

## Overview

* Plain HTML + SVG (or Canvas) implementation in JavaScript.
* `P0` and `P3` are fixed to left/right midpoints of a centered square.
* `P1` and `P2` are independent handles.
* Handles move with a spring-damped integrator toward targets set by drag/mouse/touch input.
* Optional deviceorientation support: map pitch/roll to target offsets for mobile tilt control.

## Features

* Interactive drag-and-drop for each handle.
* Labels showing normalized coordinates (0..1) or pixel coordinates above handles.
* Tangent lines drawn at regular intervals.
* Keyboard shortcuts for quick tuning (stiffness/damping, reset).
* DPI-aware canvas setup or SVG viewBox to keep visuals sharp across displays.
* Simple grid background and clean visual styling.

## Controls

* Drag handles to move them.
* Tap/click to select a handle for subtle pointer-based nudging.
* Keyboard: W/S or ArrowUp/ArrowDown to change stiffness; A/D or ArrowLeft/ArrowRight to change damping; R to reset.

## How to run

1. Save `index.html` (and optionally `main.js`) in a folder.
2. Open `index.html` in a modern web browser (Chrome, Safari, Firefox).
3. On mobile, tap to grant device orientation permissions if needed (iOS requires user interaction).

## Implementation notes and tips ( well, things that I had trouble figuring ouut )

* Use small `t` step (e.g., `0.01`) to sample the Bézier curve; for Canvas draw the sampled polyline or use `context.bezierCurveTo` if you only want rendering — the math must still be manual for sampling and tangents.
* For stable physics, use `requestAnimationFrame` and clamp `dt` to avoid large steps; consider a fixed-step accumulator similar to iOS.
* For high-resolution displays, set canvas width/height according to `devicePixelRatio` and scale the drawing context with `ctx.setTransform(ratio,0,0,ratio,0,0)`.

https://github.com/user-attachments/assets/3585794c-f642-40d9-a4af-21b3006a4545

---

## Differences and commonalities

### Common

* Same Bézier math and tangent derivative formula.
* Spring-damper physics and semi-implicit Euler integration.
* Both implementations provide independent control of `P1` and `P2` and tangent visualization.
* Both support device motion mapping (web via `deviceorientation`, iOS via CoreMotion).

### iOS-specific

* Uses CoreMotion and UIKit drawing APIs.
* Offscreen rendering to `UIImage` + `CALayer.contents` for atomic updates to avoid flicker.
* Fixed 60 Hz physics with `CADisplayLink` and capability to force preferredFramesPerSecond.

### Web-specific

* Plain HTML + SVG or Canvas approach.
* Easier to inspect and tweak parameters live via console.
* Device orientation permission and cross-browser considerations (permission prompts, different event ranges).


---

## Submission checklist

* README (this file) explaining math, physics, controls, and how to run both versions.
* Source code: Swift files for iOS (e.g., `BezierView.swift`, minimal `ViewController.swift`, Xcode project) and `index.html` / `main.js` for the web.
* Screen recordings (max 30s) demonstrating interactivity for both iOS (real device) and Web (desktop or mobile). Include a short clip showing gyroscope control on the device.

---

## Final remarks

This combined project demonstrates precise mathematical rendering and real-time physics. The iOS implementation focuses on rendering and sensor integration; the Web version offers easy experimentation and rapid iteration. Both are organized so the Bézier math, physics, and input handling are clearly separated and implemented from scratch. This was really fun, making this project. Thank you!
