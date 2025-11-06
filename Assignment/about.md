# **Assignment: Interactive Bézier Curve with Physics & Sensor Control**

### **Objective**

Implement an **interactive cubic Bézier curve** that behaves like a rope reacting to motion input.

This project tests your understanding of **math, graphics programming, and real-time input handling**.

---

## **Problem Statement**

Create a visual simulation where a cubic Bézier curve dynamically responds to **device gyroscope data (iOS)** or **mouse movement (Web)**.

The curve should move smoothly, visualize its **tangents**, and behave like a springy rope when control points are displaced.

You must implement all logic — including Bézier math, tangent computation, and spring physics — from scratch.

---

## **Core Requirements**

### **1. Bézier Curve Math**

Implement a **cubic Bézier curve** using 4 control points:

B(t) = (1−t)³P₀ + 3(1−t)²tP₁ + 3(1−t)t²P₂ + t³P₃

- Use small t increments (e.g., 0.01) to sample the curve for rendering.

---

### **2. Control Points Behavior**

- **P₀** and **P₃**: fixed endpoints.
- **P₁** and **P₂**: dynamic — move in response to:
    - **iOS**: Gyroscope rotation (pitch, yaw, roll) via CoreMotion.
    - **Web**: Mouse position or drag input.

Add a simple **spring-damping model** for smooth, natural motion:

acceleration = -k * (position - target) - damping * velocity

---

### **3. Tangent Visualization**

Compute tangent vectors using the derivative:

B'(t) = 3(1−t)²(P₁−P₀) + 6(1−t)t(P₂−P₁) + 3t²(P₃−P₂)

- Normalize and draw short tangent lines at intervals along the curve.

---

### **4. Interaction & Rendering**

- Render:
    - The curve path.
    - Control points (visible as small circles).
    - Tangent lines at several points.
- **iOS:** Use Swift + CoreMotion + CADisplayLink.
- **Web:** Use plain HTML Canvas + JavaScript.
- Maintain at least **60 FPS**.

---

## **Rules**

1. **Do not** use prebuilt physics, animation, or Bézier APIs (UIBezierPath, D3.js, etc.).
2. The Bézier math and motion logic must be fully manual.
3. Organize code cleanly into math, rendering, and input sections.
4. The visualization must be **interactive and real-time**.

## **Submission**

- A short README explaining your math, physics model, and design choices.
- Source code files (.swift or .html/.js).
- **(Must)** screen recording (max 30s) showing interactivity.