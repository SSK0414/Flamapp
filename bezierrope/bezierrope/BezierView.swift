import UIKit
import CoreMotion


final class BezierView: UIView {
    
    private let imageLayer: CALayer = {
        let l = CALayer()
        l.contentsGravity = .resize
        l.masksToBounds = true
        return l
    }()
    
    // MARK: - Geometry / State
    private var P0 = CGPoint.zero
    private var P3 = CGPoint.zero
    private var P1 = CGPoint.zero
    private var P2 = CGPoint.zero

    private var isReady = false

    // Targets to which handles are springing
    private var T1 = CGPoint.zero
    private var T2 = CGPoint.zero

    // velocities for semi-implicit Euler
    private var V1 = CGPoint.zero
    private var V2 = CGPoint.zero

    // softened defaults
    private let defaultStiffness: CGFloat = 120.0
    private let defaultDamping: CGFloat = 20.0

    // live physics params
    var stiffness: CGFloat
    var damping: CGFloat
    
    // gyro mapping gains (tweak to increase mapped offset from device rotation)
    // Larger values -> the same roll/pitch moves the target farther on screen
    var gyroGainX: CGFloat = 140.0 // previously ~80
    var gyroGainY: CGFloat = 110.0 // previously ~60

    // extra multiplier to make the rope "stretch" more when mapping the gyro target.
    // This multiplies the offset vector from center — values >1 cause longer stretch.
    var stretchMultiplier: CGFloat = 1.35
    
    // visuals
    private let tStep: CGFloat = 0.01
    private let tangentLength: CGFloat = 28

    // display link / timing
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var lastDt: CGFloat? = nil

    // fixed-step physics accumulator
    private var physicsAccumulator: CFTimeInterval = 0.0
    private let physicsFixedDt: CFTimeInterval = 1.0 / 60.0
    private let maxPhysicsStepsPerFrame = 5

    // input
    private var draggingHandle: Int? = nil   // 1 or 2 while dragging
    private var selectedHandle: Int? = nil   // selection toggles gyroscope
    private let hitRadius: CGFloat = 24

    // motion
    private let motion = CMMotionManager()

    // draw coalescing
    private var lastDrawTimestamp: CFTimeInterval = 0.0
    private let drawCoalesceThreshold: CFTimeInterval = 1.0 / 60.0 // 16.6ms

    // fps debug
    private var fpsFrameCount = 0
    private var fpsAccumTime: CGFloat = 0.0
    private var measuredFPS: CGFloat = 0.0

    // Anti-flicker: cached rendered frame image (rendered once per display tick)
    private var lastFrameImage: UIImage?

    // MARK: - Init
    override init(frame: CGRect) {
        self.stiffness = defaultStiffness
        self.damping = defaultDamping
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        self.stiffness = defaultStiffness
        self.damping = defaultDamping
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = UIColor(red: 0.04, green: 0.06, blue: 0.08, alpha: 1)
        isOpaque = true
        isMultipleTouchEnabled = false

        layer.contentsScale = traitCollection.displayScale
        
        // add imageLayer as backing layer for fast blit
        imageLayer.frame = bounds
        imageLayer.contentsScale = layer.contentsScale
        imageLayer.isOpaque = true
        layer.addSublayer(imageLayer)

        setupTraitObservers()
        // note: we don't call any addGestureRecognizers — touches are handled by touches* methods
    }

    private func setupTraitObservers() {
        if #available(iOS 17.0, *) {
            // observe display scale changes
            registerForTraitChanges([UITraitDisplayScale.self]) { (selfRef: Self, _: UITraitCollection) in
                DispatchQueue.main.async {
                    selfRef.layer.contentsScale = selfRef.traitCollection.displayScale
                }
            }
        }
    }

    deinit {
        displayLink?.invalidate()
        motion.stopDeviceMotionUpdates()
        print("[BezierView] deinit — displayLink invalidated, motion stopped")
    }

    // MARK: - Layout
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.contentsScale = traitCollection.displayScale
        imageLayer.frame = bounds
        imageLayer.contentsScale = layer.contentsScale
        setupDefaultLayoutIfNeeded()
        setupDisplayLinkIfNeeded()
        // do NOT call setNeedsDisplay here — display link will drive rendering
    }

    private func setupDefaultLayoutIfNeeded() {
        let safe = safeAreaInsets
        let availWidth  = bounds.width  - safe.left - safe.right
        let availHeight = bounds.height - safe.top  - safe.bottom
        guard availWidth > 0, availHeight > 0 else { return }

        let outer = min(availWidth, availHeight) * 0.9
        let innerPadding: CGFloat = 24.0
        let innerSize = max(60, outer - 2.0 * innerPadding)

        let left = (bounds.width - innerSize) * 0.5
        let top  = (bounds.height - innerSize) * 0.5

        P0 = CGPoint(x: left, y: top + innerSize * 0.5)
        P3 = CGPoint(x: left + innerSize, y: top + innerSize * 0.5)

        func inside(_ p: CGPoint) -> Bool {
            return p.x >= left && p.x <= left + innerSize && p.y >= top && p.y <= top + innerSize
        }

        if !inside(P1) || !inside(P2) {
            P1 = CGPoint(x: left + innerSize * 0.25, y: top + innerSize * 0.25)
            P2 = CGPoint(x: left + innerSize * 0.75, y: top + innerSize * 0.75)
            T1 = P1; T2 = P2
            V1 = .zero; V2 = .zero
        }
    }

    // MARK: - DisplayLink + accumulator (force 60fps)
    private func setupDisplayLinkIfNeeded() {
        guard displayLink == nil, bounds.width > 0, bounds.height > 0 else { return }

        displayLink = CADisplayLink(target: self, selector: #selector(step(_:)))
        if #available(iOS 10.0, *) {
            displayLink?.preferredFramesPerSecond = 60
        }
        lastTimestamp = CACurrentMediaTime()
        displayLink?.add(to: .main, forMode: .common)
        print("[BezierView] displayLink started @ forced 60 FPS")
    }

    @objc private func step(_ link: CADisplayLink) {
        // accumulate time
        var frameDt = link.timestamp - lastTimestamp
        lastTimestamp = link.timestamp
        if frameDt > 0.1 { frameDt = 0.1 }

        physicsAccumulator += frameDt
        let maxAccum = physicsFixedDt * Double(maxPhysicsStepsPerFrame)
        if physicsAccumulator > maxAccum { physicsAccumulator = maxAccum }

        var steps = 0
        while physicsAccumulator >= physicsFixedDt && steps < maxPhysicsStepsPerFrame {
            let fdt = CGFloat(physicsFixedDt)

            if draggingHandle != 1 {
                stepSpring(pos: &P1, vel: &V1, target: T1, k: stiffness, damping: damping, dt: fdt)
            } else {
                T1 = P1; V1 = .zero
            }
            if draggingHandle != 2 {
                stepSpring(pos: &P2, vel: &V2, target: T2, k: stiffness, damping: damping, dt: fdt)
            } else {
                T2 = P2; V2 = .zero
            }

            P1 = clampPointToInnerSquare(P1)
            P2 = clampPointToInnerSquare(P2)

            physicsAccumulator -= physicsFixedDt
            steps += 1
        }

        lastDt = CGFloat(frameDt)

        fpsFrameCount += 1
        fpsAccumTime += CGFloat(frameDt)
        if fpsAccumTime >= 1.0 {
            measuredFPS = CGFloat(fpsFrameCount) / fpsAccumTime
            fpsFrameCount = 0
            fpsAccumTime = 0
        }

        // Render to an offscreen image once per display tick (this reduces flicker)
        renderFrameToImage()
        // request a blit in draw (very cheap)
        setNeedsDisplay()
    }

    // MARK: - Render to image (anti-flicker)
    private func renderFrameToImage() {
        // ensure bounds are valid
        guard bounds.width > 0, bounds.height > 0 else { return }

        // use UIGraphicsImageRenderer with correct scale
        let format = UIGraphicsImageRendererFormat()
        format.scale = layer.contentsScale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        let img = renderer.image { ctx in
            let cg = ctx.cgContext
            // replicate the draw logic but into this context

            // clear
            cg.saveGState()
            cg.setBlendMode(.copy)
            cg.setFillColor(UIColor(red: 0.04, green: 0.06, blue: 0.08, alpha: 1).cgColor)
            cg.fill(bounds)
            cg.restoreGState()

            // grid
            cg.saveGState()
            cg.setLineWidth(1)
            cg.setStrokeColor(UIColor(white: 1, alpha: 0.03).cgColor)
            let gridStep = max(24, min(bounds.width, bounds.height)/12)
            var gx: CGFloat = 0
            while gx <= bounds.width {
                cg.move(to: CGPoint(x: gx, y: 0)); cg.addLine(to: CGPoint(x: gx, y: bounds.height))
                gx += gridStep
            }
            var gy: CGFloat = 0
            while gy <= bounds.height {
                cg.move(to: CGPoint(x: 0, y: gy)); cg.addLine(to: CGPoint(x: bounds.width, y: gy))
                gy += gridStep
            }
            cg.strokePath()
            cg.restoreGState()

            // bezier curve
            cg.saveGState()
            cg.setLineWidth(3)
            cg.setStrokeColor(UIColor(red: 0.47, green: 0.78, blue: 1.0, alpha: 1).cgColor)
            let samples = sampleBezier(P0: P0, P1: P1, P2: P2, P3: P3, step: tStep)
            if let first = samples.first {
                cg.move(to: first)
                for pt in samples.dropFirst() { cg.addLine(to: pt) }
                cg.strokePath()
            }
            cg.restoreGState()

            // tangents
            cg.saveGState()
            cg.setLineWidth(1.2)
            cg.setStrokeColor(UIColor(red: 1.0, green: 0.82, blue: 0.55, alpha: 1).cgColor)
            for i in 0...12 {
                let t = CGFloat(i) / 12.0
                let p = bezierPoint(t: t, P0: P0, P1: P1, P2: P2, P3: P3)
                var tan = bezierTangent(t: t, P0: P0, P1: P1, P2: P2, P3: P3)
                let len = hypot(tan.x, tan.y)
                if len > 0.0001 { tan.x /= len; tan.y /= len }
                let p2 = CGPoint(x: p.x + tan.x * tangentLength, y: p.y + tan.y * tangentLength)
                cg.move(to: p); cg.addLine(to: p2)
            }
            cg.strokePath()
            cg.restoreGState()

            // helper lines
            cg.saveGState()
            cg.setLineWidth(1)
            cg.setStrokeColor(UIColor(white: 1, alpha: 0.12).cgColor)
            cg.move(to: P0); cg.addLine(to: P1)
            cg.move(to: P3); cg.addLine(to: P2)
            cg.strokePath()
            cg.restoreGState()

            // endpoints
            cg.saveGState()
            cg.setFillColor(UIColor(white: 1, alpha: 0.9).cgColor)
            cg.addArc(center: P0, radius: 4, startAngle: 0, endAngle: .pi*2, clockwise: false); cg.fillPath()
            cg.addArc(center: P3, radius: 4, startAngle: 0, endAngle: .pi*2, clockwise: false); cg.fillPath()
            cg.restoreGState()

            // handles
            drawHandleInContext(cg, p: P1, color: UIColor(red: 0.47, green: 0.78, blue: 1.0, alpha: 1), highlight: selectedHandle == 1)
            drawHandleInContext(cg, p: P2, color: UIColor(red: 1.0, green: 0.83, blue: 0.55, alpha: 1), highlight: selectedHandle == 2)

            // labels
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: UIColor(white: 0.95, alpha: 1.0)
            ]
            let s1 = String(format: "P1: %.0f, %.0f", P1.x, P1.y)
            let s2 = String(format: "P2: %.0f, %.0f", P2.x, P2.y)
            let ns1 = NSAttributedString(string: s1, attributes: labelAttrs)
            let ns2 = NSAttributedString(string: s2, attributes: labelAttrs)
            drawLabelInContext(ns1, at: P1)
            drawLabelInContext(ns2, at: P2)

            // "GYRO ON" badge for selected handle
            if let sel = selectedHandle {
                let badge = NSAttributedString(string: "GYRO ON", attributes: [
                    .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: UIColor.white
                ])
                let pos = (sel == 1) ? P1 : P2
                drawBadgeInContext(badge, near: pos)
            }

            // debug overlay
            if let dt = lastDt {
                let debugText = String(format: "fps: %.0f  dt: %.4f  v1:%.0f,%.0f  v2:%.0f,%.0f",
                                       measuredFPS, dt, V1.x, V1.y, V2.x, V2.y)
                let dbgAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11),
                    .foregroundColor: UIColor(white: 0.85, alpha: 1)
                ]
                let ns = NSAttributedString(string: debugText, attributes: dbgAttr)
                ns.draw(at: CGPoint(x: 12, y: 12))
            }
        }

        // swap in the rendered image (main-thread; we're already on main)
        lastFrameImage = img
        
        // atomic update to layer.contents — disable implicit animations
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = img.cgImage
        CATransaction.commit()
    }

    // MARK: - draw(_:)
    override func draw(_ rect: CGRect) {
        // no-op — imageLayer handles all rendering
        // leave fallback in case layer has no image (first frame)
        if lastFrameImage == nil {
            guard let ctx = UIGraphicsGetCurrentContext() else { return }
            ctx.setFillColor(UIColor(red: 0.04, green: 0.06, blue: 0.08, alpha: 1).cgColor)
            ctx.fill(rect)
        }
    }

    // helpers used by renderFrameToImage
    private func drawHandleInContext(_ cg: CGContext, p: CGPoint, color: UIColor, highlight: Bool) {
        cg.saveGState()
        let radius: CGFloat = highlight ? 12 : 9
        cg.setFillColor(color.cgColor)
        cg.addArc(center: p, radius: radius, startAngle: 0, endAngle: .pi*2, clockwise: false)
        cg.fillPath()
        cg.setStrokeColor(UIColor(white: 0, alpha: 0.15).cgColor)
        cg.setLineWidth(1)
        cg.addArc(center: p, radius: radius, startAngle: 0, endAngle: .pi*2, clockwise: false)
        cg.strokePath()
        cg.restoreGState()
    }

    private func drawLabelInContext(_ ns: NSAttributedString, at point: CGPoint) {
        let size = ns.size()
        var x = point.x - size.width * 0.5
        var y = point.y - 28 - size.height * 0.5
        x = max(8, min(bounds.width - size.width - 8, x))
        y = max(8, min(bounds.height - size.height - 8, y))
        ns.draw(at: CGPoint(x: x, y: y))
    }

    private func drawBadgeInContext(_ ns: NSAttributedString, near point: CGPoint) {
        let size = ns.size()
        let padH: CGFloat = 8
        let padV: CGFloat = 4
        var x = point.x + 14
        var y = point.y - size.height * 0.5
        if x + size.width + padH > bounds.width - 8 { x = bounds.width - size.width - padH - 8 }
        if y < 8 { y = 8 }
        let rect = CGRect(x: x, y: y, width: size.width + padH, height: size.height + padV)
        let bgPath = UIBezierPath(roundedRect: rect, cornerRadius: 6)
        UIColor(white: 0.06, alpha: 0.6).setFill()
        bgPath.fill()
        ns.draw(at: CGPoint(x: rect.minX + padH*0.5, y: rect.minY + padV*0.5))
    }

    // MARK: - Bézier math
    private func bezierPoint(t: CGFloat, P0:CGPoint, P1:CGPoint, P2:CGPoint, P3:CGPoint) -> CGPoint {
        let it = 1 - t
        let it2 = it*it, t2 = t*t
        let b0 = it2 * it
        let b1 = 3 * it2 * t
        let b2 = 3 * it * t2
        let b3 = t * t2
        return CGPoint(x: b0*P0.x + b1*P1.x + b2*P2.x + b3*P3.x,
                       y: b0*P0.y + b1*P1.y + b2*P2.y + b3*P3.y)
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

    // MARK: - Physics integrator (semi-implicit Euler)
    private func stepSpring(pos: inout CGPoint, vel: inout CGPoint, target: CGPoint, k: CGFloat, damping: CGFloat, dt: CGFloat) {
        let ax = -k * (pos.x - target.x) - damping * vel.x
        let ay = -k * (pos.y - target.y) - damping * vel.y
        vel.x += ax * dt
        vel.y += ay * dt
        pos.x += vel.x * dt
        pos.y += vel.y * dt

        let maxVel: CGFloat = 1400
        if abs(vel.x) > maxVel { vel.x = maxVel * (vel.x >= 0 ? 1 : -1) }
        if abs(vel.y) > maxVel { vel.y = maxVel * (vel.y >= 0 ? 1 : -1) }
    }

    private func clampPointToInnerSquare(_ p: CGPoint) -> CGPoint {
        let safe = safeAreaInsets
        let availW = bounds.width - safe.left - safe.right
        let availH = bounds.height - safe.top - safe.bottom
        let outer = min(availW, availH) * 0.9
        let innerPadding: CGFloat = 24.0
        let innerSize = max(60, outer - 2.0 * innerPadding)
        let left = (bounds.width - innerSize) * 0.5
        let top  = (bounds.height - innerSize) * 0.5

        var nx = p.x; var ny = p.y
        nx = max(left + 8, min(left + innerSize - 8, nx))
        ny = max(top + 8, min(top + innerSize - 8, ny))
        return CGPoint(x: nx, y: ny)
    }

    // MARK: - Touch Handling (tap toggles selection)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let p = t.location(in: self)

        if distance(p, P1) <= hitRadius {
            // toggle selection for P1
            if selectedHandle == 1 { selectedHandle = nil } else { selectedHandle = 1 }
            draggingHandle = 1
            return
        }
        if distance(p, P2) <= hitRadius {
            if selectedHandle == 2 { selectedHandle = nil } else { selectedHandle = 2 }
            draggingHandle = 2
            return
        }

        // tap outside clears selection if far away
        let d1 = distance(p, P1), d2 = distance(p, P2)
        let nearest = (d1 < d2) ? 1 : 2
        let nearestDist = min(d1, d2)
        if nearestDist <= hitRadius * 2.0 {
            selectedHandle = nearest
        } else {
            selectedHandle = nil
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        if draggingHandle == 1 { P1 = p; T1 = p; V1 = .zero; return }
        if draggingHandle == 2 { P2 = p; T2 = p; V2 = .zero; return }
        if selectedHandle == 1 { T1 = lerpPoint(a: T1, b: p, t: 0.25) }
        if selectedHandle == 2 { T2 = lerpPoint(a: T2, b: p, t: 0.25) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        draggingHandle = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        draggingHandle = nil
    }

    // MARK: - Device motion (P1 inverted, P2 normal)
    func attachDeviceMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] dm, _ in
            guard let self = self, let dm = dm else { return }

            // attitude in radians
            let pitch = dm.attitude.pitch
            let roll  = dm.attitude.roll

            // center of view
            let cx = self.bounds.midX
            let cy = self.bounds.midY

            // map device rotation -> screen offsets using adjustable gains
            let ox = CGFloat(roll)  * self.gyroGainX
            let oy = CGFloat(pitch) * self.gyroGainY

            // apply stretch multiplier to make the target travel farther from center
            // compute offset vector, scale it, then add to center
            let offset = CGPoint(x: ox, y: oy)
            let stretched = CGPoint(x: offset.x * self.stretchMultiplier, y: offset.y * self.stretchMultiplier)
            let mappedTarget = CGPoint(x: cx + stretched.x, y: cy + stretched.y)

            // P1: inverted mapping (as you requested) — apply stretch and then invert signs
            if self.selectedHandle == 1 {
                let inverted = CGPoint(x: cx - stretched.x, y: cy - stretched.y)
                self.T1 = self.lerpPoint(a: self.T1, b: inverted, t: 0.12)
                return
            }

            // P2: normal mapping
            if self.selectedHandle == 2 {
                self.T2 = self.lerpPoint(a: self.T2, b: mappedTarget, t: 0.12)
            }
        }
    }


    // MARK: - Helpers
    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    private func lerpPoint(a: CGPoint, b: CGPoint, t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}
