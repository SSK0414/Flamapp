import UIKit
import CoreMotion

final class BezierView: UIView {
    // MARK: - Geometry / state
    private var P0 = CGPoint.zero
    private var P3 = CGPoint.zero
    private var P1 = CGPoint.zero
    private var P2 = CGPoint.zero
    // add this property with other state vars
    private var isReady = false   // becomes true after first stable layout

    // targets (where handles are being pulled towards)
    private var T1 = CGPoint.zero
    private var T2 = CGPoint.zero
    
    // velocities for semi-implicit Euler
    private var V1 = CGPoint.zero
    private var V2 = CGPoint.zero
    
    // physics params (pixels and pixel/sec)
    var stiffness: CGFloat = 2000  // spring constant (tweak)
    var damping: CGFloat = 120     // damping coefficient (tweak)
    
    // sampling resolution
    private let tStep: CGFloat = 0.01
    private let tangentLength: CGFloat = 40
    
    // CADisplayLink
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    
    // Input
    private var draggingHandle: Int? = nil // 1 or 2
    private var selectedHandle: Int? = nil // optional selection
    // convenience for touches: touch -> handle when dragging
    private let hitRadius: CGFloat = 24
    
    // CoreMotion optional
    private let motion = CMMotionManager()
    
    // MARK: - Init / layout
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        backgroundColor = UIColor(red: 0.04, green: 0.06, blue: 0.08, alpha: 1)
        isMultipleTouchEnabled = false
        // do NOT start display link here — wait until we have valid bounds
        // initial layout will be performed in layoutSubviews where we have correct bounds
        addGestureRecognizers() // stub; no-op
    }

    
    override func layoutSubviews() {
        super.layoutSubviews()
        // compute layout and initialize handles if needed
        setupDefaultLayoutIfNeeded()

        // now we have stable geometry — start display link once
        setupDisplayLinkIfNeeded()

        // ensure a redraw now that geometry and displayLink are set
        setNeedsDisplay()
    }


    private func setupDefaultLayoutIfNeeded() {
        // compute geometry using safeAreaInsets
        let safe = self.safeAreaInsets
        let availWidth  = bounds.width  - safe.left - safe.right
        let availHeight = bounds.height - safe.top  - safe.bottom

        // if bounds are not yet set, bail — layoutSubviews will call again
        if availWidth <= 0 || availHeight <= 0 { return }

        // Outer square occupies 90% of the smaller available dimension
        let outer = min(availWidth, availHeight) * 0.9
        let innerPadding: CGFloat = 24.0
        let innerSize = max(60, outer - 2.0 * innerPadding) // ensure > 0

        // center the inner square inside the full bounds (including safe area)
        let left = (bounds.width  - innerSize) * 0.5
        let top  = (bounds.height - innerSize) * 0.5

        // endpoints (left-middle and right-middle inside the inner square)
        P0 = CGPoint(x: left,                 y: top + innerSize * 0.5)
        P3 = CGPoint(x: left + innerSize,     y: top + innerSize * 0.5)

        // Initialize handles if they are unset OR outside the inner square
        func inside(_ p: CGPoint) -> Bool {
            return p.x >= left && p.x <= left + innerSize && p.y >= top && p.y <= top + innerSize
        }
        if !inside(P1) || !inside(P2) {
            P1 = CGPoint(x: left + innerSize * 0.25, y: top + innerSize * 0.25)
            P2 = CGPoint(x: left + innerSize * 0.75, y: top + innerSize * 0.75)
            T1 = P1; T2 = P2
        }

        // debug log
        print("[BezierView] layout left:\(left) top:\(top) size:\(innerSize) P1:\(P1) P2:\(P2) safe:\(safe)")
    }


    // MARK: - Display link & physics
    private func setupDisplayLinkIfNeeded() {
        // Only start once and only when bounds are valid & we consider the view ready
        if isReady { return }
        // require that bounds are reasonably sized before starting
        if bounds.width <= 0 || bounds.height <= 0 { return }
        displayLink?.invalidate()
        displayLink = CADisplayLink(target: self, selector: #selector(step(_:)))
        lastTimestamp = CACurrentMediaTime()
        displayLink?.add(to: .main, forMode: .common)
        isReady = true
        print("[BezierView] displayLink started")
    }

    @objc private func step(_ link: CADisplayLink) {
        guard isReady else { return }
        if lastTimestamp == 0 { lastTimestamp = link.timestamp; return }

        let now = link.timestamp
        var dt = now - lastTimestamp
        lastTimestamp = now
        // Prevent first-frame or lag spikes
        if dt > 0.033 { dt = 0.033 }
        dt = min(dt, 1.0/30.0) // clamp for stability
        
        // physics step in pixel coordinates
        if draggingHandle != 1 {
            stepSpring(pos: &P1, vel: &V1, target: T1, k: stiffness, damping: damping, dt: dt)
        } else {
            // if dragging we still set T1 to current P1 (so physics picks up when released)
            T1 = P1; V1 = .zero
        }
        if draggingHandle != 2 {
            stepSpring(pos: &P2, vel: &V2, target: T2, k: stiffness, damping: damping, dt: dt)
        } else {
            T2 = P2; V2 = .zero
        }
        let maxX = bounds.width * 1.5
        let maxY = bounds.height * 1.5
        if P1.x < -100 || P1.x > maxX || P1.y < -100 || P1.y > maxY {
            P1 = CGPoint(x: bounds.midX - 100, y: bounds.midY - 50)
            V1 = .zero; T1 = P1
        }
        if P2.x < -100 || P2.x > maxX || P2.y < -100 || P2.y > maxY {
            P2 = CGPoint(x: bounds.midX + 100, y: bounds.midY + 50)
            V2 = .zero; T2 = P2
        }
        setNeedsDisplay()
    }
    func stepSpring(pos: inout CGPoint, vel: inout CGPoint, target: CGPoint, k: CGFloat, damping: CGFloat, dt: CGFloat) {
        let ax = -k * (pos.x - target.x) - damping * vel.x
        let ay = -k * (pos.y - target.y) - damping * vel.y
        vel.x += ax * dt
        vel.y += ay * dt
        pos.x += vel.x * dt
        pos.y += vel.y * dt

        // Prevent runaway velocities
        let maxVel: CGFloat = 1000
        if abs(vel.x) > maxVel {
            vel.x = maxVel * (vel.x >= 0 ? 1 : -1)
        }
        if abs(vel.y) > maxVel {
            vel.y = maxVel * (vel.y >= 0 ? 1 : -1)
        }
    }

    
    // MARK: - Drawing
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        // background handled by view
        // grid (subtle)
        ctx.saveGState()
        ctx.setLineWidth(1)
        ctx.setStrokeColor(UIColor(white: 1, alpha: 0.03).cgColor)
        let gridStep = max(24, min(bounds.width, bounds.height)/12)
        var x: CGFloat = 0
        while x <= bounds.width {
            ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: bounds.height))
            x += gridStep
        }
        var y: CGFloat = 0
        while y <= bounds.height {
            ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: bounds.width, y: y))
            y += gridStep
        }
        ctx.strokePath()
        ctx.restoreGState()
        
        // draw bezier by sampling
        ctx.saveGState()
        ctx.setLineWidth(3)
        ctx.setStrokeColor(UIColor(red: 0.47, green: 0.78, blue: 1.0, alpha: 1).cgColor)
        let samples = sampleBezier(P0: P0, P1: P1, P2: P2, P3: P3, step: tStep)
        if let first = samples.first {
            ctx.move(to: first)
            for pt in samples.dropFirst() { ctx.addLine(to: pt) }
            ctx.strokePath()
        }
        ctx.restoreGState()
        
        // tangents
        ctx.saveGState()
        ctx.setLineWidth(1.2)
        ctx.setStrokeColor(UIColor(red: 1.0, green: 0.82, blue: 0.55, alpha: 1).cgColor)
        for i in 0...16 {
            let t = CGFloat(i) / 16.0
            let p = bezierPoint(t: t, P0:P0, P1:P1, P2:P2, P3:P3)
            var tan = bezierTangent(t: t, P0:P0, P1:P1, P2:P2, P3:P3)
            let len = hypot(tan.x, tan.y)
            if len > 0.0001 { tan.x /= len; tan.y /= len }
            let p2 = CGPoint(x: p.x + tan.x * tangentLength, y: p.y + tan.y * tangentLength)
            ctx.move(to: p); ctx.addLine(to: p2)
            ctx.strokePath()
        }
        ctx.restoreGState()
        
        // control helper lines
        ctx.saveGState()
        ctx.setLineWidth(1)
        ctx.setStrokeColor(UIColor(white: 1, alpha: 0.12).cgColor)
        ctx.move(to: P0); ctx.addLine(to: P1); ctx.strokePath()
        ctx.move(to: P3); ctx.addLine(to: P2); ctx.strokePath()
        ctx.restoreGState()
        
        // draw handles
        func drawHandle(_ p: CGPoint, color: UIColor, highlight: Bool) {
            ctx.saveGState()
            ctx.setFillColor(color.cgColor)
            ctx.addArc(center: p, radius: highlight ? 12 : 9, startAngle: 0, endAngle: .pi*2, clockwise: false)
            ctx.fillPath()
            ctx.setStrokeColor(UIColor(white: 0, alpha: 0.15).cgColor)
            ctx.setLineWidth(1)
            ctx.addArc(center: p, radius: highlight ? 12 : 9, startAngle: 0, endAngle: .pi*2, clockwise: false)
            ctx.strokePath()
            ctx.restoreGState()
        }
        drawHandle(P1, color: UIColor(red: 0.47, green: 0.78, blue: 1.0, alpha: 1), highlight: selectedHandle == 1)
        drawHandle(P2, color: UIColor(red: 1.0, green: 0.83, blue: 0.55, alpha: 1), highlight: selectedHandle == 2)
        
        // labels above handles
        let attr: [NSAttributedString.Key:Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: UIColor.white
        ]
        // Show pixel coords (easier to debug on iOS)
        let s1 = String(format: "P1: %.0f, %.0f", P1.x, P1.y)
        let s2 = String(format: "P2: %.0f, %.0f", P2.x, P2.y)
        let ns1 = NSAttributedString(string: s1, attributes: attr)
        let ns2 = NSAttributedString(string: s2, attributes: attr)
        let p1Label = CGPoint(x: P1.x, y: P1.y - 28)
        let p2Label = CGPoint(x: P2.x, y: P2.y - 28)
        ns1.draw(at: CGPoint(x: p1Label.x - ns1.size().width/2, y: p1Label.y - ns1.size().height/2))
        ns2.draw(at: CGPoint(x: p2Label.x - ns2.size().width/2, y: p2Label.y - ns2.size().height/2))
    }
    
    // MARK: - Bézier math (pixel coordinates)
    private func bezierPoint(t: CGFloat, P0:CGPoint, P1:CGPoint, P2:CGPoint, P3:CGPoint) -> CGPoint {
        let it = 1 - t
        let it2 = it*it, t2 = t*t
        let b0 = it2 * it
        let b1 = 3 * it2 * t
        let b2 = 3 * it * t2
        let b3 = t * t2
        return CGPoint(
            x: b0*P0.x + b1*P1.x + b2*P2.x + b3*P3.x,
            y: b0*P0.y + b1*P1.y + b2*P2.y + b3*P3.y
        )
    }
    private func bezierTangent(t: CGFloat, P0:CGPoint, P1:CGPoint, P2:CGPoint, P3:CGPoint) -> CGPoint {
        let it = 1 - t
        return CGPoint(
            x: 3 * it * it * (P1.x - P0.x) + 6 * it * t * (P2.x - P1.x) + 3 * t * t * (P3.x - P2.x),
            y: 3 * it * it * (P1.y - P0.y) + 6 * it * t * (P2.y - P1.y) + 3 * t * t * (P3.y - P2.y)
        )
    }
    private func sampleBezier(P0:CGPoint,P1:CGPoint,P2:CGPoint,P3:CGPoint, step: CGFloat) -> [CGPoint] {
        var pts: [CGPoint] = []
        var t: CGFloat = 0
        while t <= 1.00001 {
            pts.append(bezierPoint(t: t, P0:P0, P1:P1, P2:P2, P3:P3))
            t += step
        }
        return pts
    }
    
    // MARK: - Touches & selection
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        // check near handles
        if distance(p, P1) <= hitRadius { draggingHandle = 1; selectedHandle = 1; return }
        if distance(p, P2) <= hitRadius { draggingHandle = 2; selectedHandle = 2; return }
        // otherwise: tap to select nearest handle for independent control
        let d1 = distance(p, P1), d2 = distance(p, P2)
        selectedHandle = (d1 < d2) ? 1 : 2
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        if draggingHandle == 1 { P1 = p; T1 = p; V1 = .zero; return }
        if draggingHandle == 2 { P2 = p; T2 = p; V2 = .zero; return }
        // if not dragging but have a selection, update that selection's target gently
        if selectedHandle == 1 { T1 = lerpPoint(a: T1, b: p, t: 0.25) }
        if selectedHandle == 2 { T2 = lerpPoint(a: T2, b: p, t: 0.25) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        draggingHandle = nil
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        draggingHandle = nil
    }
    
    // MARK: - device motion
    func attachDeviceMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0/60.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] (dm, err) in
            guard let s = self, let dm = dm else { return }
            // Use attitude (radians). pitch & roll are in radians here.
            let pitch = dm.attitude.pitch
            let roll  = dm.attitude.roll
            // Map roll -> x offset, pitch -> y offset with scaling around center
            let cx = s.bounds.midX, cy = s.bounds.midY
            let ox = CGFloat(roll) * 80.0
            let oy = CGFloat(pitch) * 60.0
            let targetPoint = CGPoint(x: cx + ox, y: cy + oy)
            // move both targets gently (you can change to only selected if you prefer)
            s.T1 = s.lerpPoint(a: s.T1, b: targetPoint, t: 0.12)
            s.T2 = s.lerpPoint(a: s.T2, b: targetPoint, t: 0.12)
        }
    }
    
    // MARK: - small helpers
    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        return hypot(a.x - b.x, a.y - b.y)
    }
    private func lerpPoint(a: CGPoint, b: CGPoint, t: CGFloat) -> CGPoint {
        return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        return a + (b - a) * t
    }
    // empty stub so commonInit's call is safe (no gesture recognizers needed here)
    private func addGestureRecognizers() { /* intentionally empty */ }
}
