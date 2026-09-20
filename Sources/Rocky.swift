import AppKit
import QuartzCore

// ── Spritesheet: 8×8 grid of 192px frames; rows 5-7 unused ───────────────
let COLS = 8

struct Anim { let row: Int; let fps: Double }
let ANIMS: [String: Anim] = [
    "idle":  Anim(row: 0, fps: 8),
    "run":   Anim(row: 2, fps: 16),
    "sleep": Anim(row: 3, fps: 4),
    "react": Anim(row: 4, fps: 14),
]

// ── Tuning ───────────────────────────────────────────────────────────────
let DSP: CGFloat = 96          // on-screen sprite size
let WALK_SPEED: CGFloat = 110
let RUN_SPEED: CGFloat  = 220
let ACCEL: CGFloat      = 9    // velocity ease factor (per second)
let MARGIN: CGFloat     = 4    // gap from screen edge
let BUBBLE_W: CGFloat   = 230
let TYPE_SEC            = 0.028
let HOLD_SEC            = 4.0
let FADE_SEC            = 0.2
let BUBBLE_PAD: CGFloat = 12   // room for the speech tail outside the bubble
let LEDGE_BITE: CGFloat = 3    // how far he sinks into a window's top edge
let HOP_REACH: CGFloat  = 380  // he walks closer than this before jumping
let IDLE_NAP            = 300.0  // 3 min napped while you were merely reading
let SIT_TOO_LONG        = 2700.0
let FILL = CGColor(srgbRed: 0.118, green: 0.118, blue: 0.118, alpha: 0.95)
let EDGE = CGColor(srgbRed: 0.494, green: 0.784, blue: 0.627, alpha: 1)

// ── Polyline tracks ──────────────────────────────────────────────────────
// Rocky always stands on a polyline of sprite-centre positions. The screen rim
// is a closed one; the top edge of a window is an open one. Rotation is just
// atan2 of the leg's direction, which puts his feet to the right of travel --
// so floor, walls, ceiling, and any future corner all fall out for free instead
// of being four hand-written cases.
func polyLength(_ p: [CGPoint], closed: Bool) -> CGFloat {
    guard p.count > 1 else { return 0 }
    var t: CGFloat = 0
    for i in 0..<(closed ? p.count : p.count - 1) {
        t += hypot(p[(i + 1) % p.count].x - p[i].x, p[(i + 1) % p.count].y - p[i].y)
    }
    return t
}

func polySample(_ p: [CGPoint], closed: Bool, _ d: CGFloat) -> (pos: CGPoint, rot: CGFloat) {
    guard p.count > 1 else { return (p.first ?? .zero, 0) }
    let legs = closed ? p.count : p.count - 1
    var rest = d
    for i in 0..<legs {
        let a = p[i], b = p[(i + 1) % p.count]
        let len = hypot(b.x - a.x, b.y - a.y)
        if rest <= len || i == legs - 1 {
            let t = len > 0 ? max(0, min(1, rest / len)) : 0
            return (CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t),
                    atan2(b.y - a.y, b.x - a.x))
        }
        rest -= len
    }
    return (p[0], 0)
}

/// Distance along the polyline of the point closest to `q`.
func polyNearest(_ p: [CGPoint], closed: Bool, to q: CGPoint) -> CGFloat {
    guard p.count > 1 else { return 0 }
    let legs = closed ? p.count : p.count - 1
    var best = CGFloat.greatestFiniteMagnitude, bestD: CGFloat = 0, acc: CGFloat = 0
    for i in 0..<legs {
        let a = p[i], b = p[(i + 1) % p.count]
        let vx = b.x - a.x, vy = b.y - a.y
        let len2 = vx * vx + vy * vy
        let t = len2 > 0 ? max(0, min(1, ((q.x - a.x) * vx + (q.y - a.y) * vy) / len2)) : 0
        let px = a.x + vx * t, py = a.y + vy * t
        let dist = hypot(q.x - px, q.y - py)
        if dist < best { best = dist; bestD = acc + sqrt(len2) * t }
        acc += sqrt(len2)
    }
    return bestD
}

/// The closed path around the inside of the screen, anticlockwise, so his feet
/// point outward at the edge.
func rimPath(in bounds: CGRect) -> [CGPoint] {
    let i = MARGIN + DSP / 2
    let w = max(bounds.width, i * 2 + 1), h = max(bounds.height, i * 2 + 1)
    return [CGPoint(x: i, y: i), CGPoint(x: w - i, y: i),
            CGPoint(x: w - i, y: h - i), CGPoint(x: i, y: h - i)]
}

/// The closed path around the outside of a window. Traversed clockwise, which
/// puts his feet on the inside -- so he walks the top, clings to both sides and
/// hangs underneath, the same way he does the screen rim inside out. Clipped to
/// what's actually on screen: a window hanging off an edge is crawled as far as
/// it is visible.
func windowPath(_ rect: CGRect, in bounds: CGRect) -> [CGPoint]? {
    let out = DSP / 2 - LEDGE_BITE
    let r = rect.insetBy(dx: -out, dy: -out).intersection(bounds.insetBy(dx: MARGIN, dy: MARGIN))
    guard r.width > DSP * 1.1, r.height > DSP * 1.1 else { return nil }
    return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.minX, y: r.maxY),
            CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.maxX, y: r.minY)]
}

enum Anchor: Equatable {
    case rim(CGFloat)
    case win(CGWindowID, CGFloat)

    var d: CGFloat { switch self { case .rim(let d): return d; case .win(_, let d): return d } }
    func at(_ d: CGFloat) -> Anchor {
        switch self { case .rim: return .rim(d); case .win(let id, _): return .win(id, d) }
    }
    var sameTrack: (Anchor) -> Bool {
        switch self {
        case .rim: return { if case .rim = $0 { return true }; return false }
        case .win(let id, _): return { if case .win(let o, _) = $0 { return o == id }; return false }
        }
    }
}

// ── The pet ──────────────────────────────────────────────────────────────
final class RockyView: NSView {
    let world = World()

    private var frames: [[CGImage]] = []   // [row][col]
    private let sprite = CALayer()
    private let bubble = CALayer()

    private var anchor = Anchor.rim(80)
    private var vel: CGFloat = 0
    private var targetVel: CGFloat = 0
    private var facingForward = true

    private struct Hop {
        let from: CGPoint, to: CGPoint
        let rot0: CGFloat, rot1: CGFloat
        let arc: CGFloat, dur: Double
        var t: Double
        let land: Anchor
    }
    private var hop: Hop?
    private var held: CGPoint?          // sprite centre while actually carried
    private var grabbing = false        // mouse is down on him, not yet a drag
    private var grabOffset = CGSize.zero
    private var grabStart = CGPoint.zero
    private var dragMoved = false

    private var anim = "idle"
    private var frameIdx = 0
    private var frameTimer = 0.0

    private var mood = "idle"              // idle | roam | sleep | excited | cursor
    private var moodUntil = 0.0
    private var nextDecision = 0.0
    private var goal: Anchor?
    private var goalUntil = 0.0
    private var lastCentre = CGPoint.zero
    private var lastNotice = 0.0
    private var ledgeCache: [(CGWindowID, [CGPoint])] = []
    private var ledgeGen = -1
    private var wantPID: pid_t = 0         // app we've been asked to go visit
    private var wantUntil = 0.0
    private var lastBreak = CACurrentMediaTime()

    private let lines = dialogueLines()
    private var speech: String?
    private var speechSize = NSSize.zero
    private var speechTail: CGFloat = 0    // rotation of the leg he spoke from
    private var speechStart = 0.0
    private var speechEnd = 0.0
    private var shownChars = -1
    private var shownTailAt: CGFloat = 0
    private var shownUp = CGPoint.zero
    private var nextSpeak = 0.0

    private var lastTime = CACurrentMediaTime()
    private var link: CADisplayLink?
    private var scale: CGFloat = 2
    private var clickable = false

    private let bubbleFont = NSFont(name: "Menlo", size: 12)
        ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    init(frame: NSRect, sheet: CGImage) {
        super.init(frame: frame)

        // Decode each frame once into its own bitmap. A CGImage that is merely
        // `cropping(to:)` a PNG-backed image re-decodes the source on every blit.
        let h = sheet.height / COLS
        let space = CGColorSpaceCreateDeviceRGB()
        frames = (0..<5).map { row in   // rows 5-7 of the sheet are empty
            (0..<COLS).compactMap { col -> CGImage? in
                guard let crop = sheet.cropping(to: CGRect(x: col * h, y: row * h, width: h, height: h)),
                      let c = CGContext(data: nil, width: h, height: h, bitsPerComponent: 8,
                                        bytesPerRow: 0, space: space,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return nil }
                c.interpolationQuality = .none
                c.draw(crop, in: CGRect(x: 0, y: 0, width: h, height: h))
                return c.makeImage()
            }
        }

        wantsLayer = true
        sprite.bounds = CGRect(x: 0, y: 0, width: DSP, height: DSP)
        sprite.magnificationFilter = .nearest
        sprite.minificationFilter = .nearest
        sprite.contents = frames[0][0]
        bubble.isHidden = true
        layer?.addSublayer(sprite)
        layer?.addSublayer(bubble)

        let now = CACurrentMediaTime()
        nextDecision = now + 0.6
        scheduleNextSpeak(now)
        world.onEvent = { [weak self] cue, arg, pid in self?.handle(cue, arg, pid) }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        scale = window?.backingScaleFactor ?? 2
        sprite.contentsScale = scale
        bubble.contentsScale = scale
        if let w = window { world.start(viewFrame: w.frame) }
    }

    func screenChanged(_ f: NSRect) { world.viewFrameChanged(f) }

    /// Rocky's silhouette as a template image, so the menu bar tints it for us.
    /// Smooth interpolation, not nearest-neighbour: 192px down to 36px by point
    /// sampling lands on his transparent gaps and yields confetti.
    func statusIcon() -> NSImage {
        let px = 36   // 18pt @2x
        let box = NSSize(width: 18, height: 18)
        guard let f = frames.first?.first,
              let c = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return NSImage(size: box) }

        let r = CGRect(x: 0, y: 0, width: px, height: px)
        c.interpolationQuality = .high
        c.setFillColor(CGColor(gray: 0, alpha: 1))
        c.fill(r)
        c.setBlendMode(.destinationIn)   // keep the black only where Rocky is
        c.draw(f, in: r)

        guard let cg = c.makeImage() else { return NSImage(size: box) }
        let img = NSImage(cgImage: cg, size: box)
        img.isTemplate = true
        return img
    }

    // ── Run loop ─────────────────────────────────────────────────────────
    // A display link, not a Timer: ticks land on the vsync, so a position set
    // here is exactly a frame the compositor is about to draw. A Timer drifts
    // against the refresh and that beat is the jitter you see.
    func start() {
        guard link == nil else { return }
        lastTime = CACurrentMediaTime()
        let l = displayLink(target: self, selector: #selector(tick))
        l.add(to: .main, forMode: .common)
        link = l
    }
    func stop() { link?.invalidate(); link = nil }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTime, 0.05)
        lastTime = now

        world.poll(now)
        if world.asleep { stop(); return }   // nothing to animate to a dark screen

        step(dt, now)
        advanceFrame(dt)
        maybeSpeak(now)
        if speech != nil && now > speechEnd { speech = nil }
        updateClickThrough()

        guard spriteNeedsSync() || speech != nil || !bubble.isHidden else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        syncSprite()
        syncBubble(now)
        CATransaction.commit()
    }

    // ── Tracks ───────────────────────────────────────────────────────────
    private func rimPoints() -> [CGPoint] { rimPath(in: bounds) }

    private func windowTrack(_ w: Win) -> [CGPoint]? { windowPath(w.rect, in: bounds) }
    /// Is this window's outline actually on show, or is something in front of it
    /// covering the edge? Rocky draws above every window, so clinging to a hidden
    /// border looks like clinging to nothing. If you can't see the edge, nor can he.
    private func outlineVisible(_ w: Win, under front: [Win]) -> Bool {
        guard !front.isEmpty else { return true }
        let r = w.rect
        let step: CGFloat = 12
        var seen = 0, total = 0
        func sample(_ p: CGPoint) {
            total += 1
            // 2pt of slack so a window flush against another doesn't read as covered
            if !front.contains(where: { $0.rect.insetBy(dx: 2, dy: 2).contains(p) }) { seen += 1 }
        }
        var x = r.minX
        while x <= r.maxX { sample(CGPoint(x: x, y: r.minY)); sample(CGPoint(x: x, y: r.maxY)); x += step }
        var y = r.minY
        while y <= r.maxY { sample(CGPoint(x: r.minX, y: y)); sample(CGPoint(x: r.maxX, y: y)); y += step }
        return total > 0 && CGFloat(seen) / CGFloat(total) > 0.85
    }

    /// Windows worth climbing: near the front, big enough to hold him, and not
    /// buried behind something else. Recomputed only when the window list
    /// changes -- once a second at most -- never per frame.
    private func ledges() -> [(CGWindowID, [CGPoint])] {
        if ledgeGen == world.generation { return ledgeCache }
        let front = Array(world.windows.prefix(8))
        var out: [(CGWindowID, [CGPoint])] = []
        for (i, w) in front.enumerated() {
            guard outlineVisible(w, under: Array(front.prefix(i))), let t = windowTrack(w) else { continue }
            out.append((w.id, t))
            if out.count == 6 { break }
        }
        ledgeCache = out
        ledgeGen = world.generation
        return out
    }

    private func track(_ a: Anchor) -> (pts: [CGPoint], closed: Bool)? {
        switch a {
        case .rim: return (rimPoints(), true)
        case .win(let id, _):
            // Deliberately via `ledges()`: if another window is raised over his,
            // the track disappears and he scrambles away, same as if it closed.
            guard let p = ledges().first(where: { $0.0 == id })?.1 else { return nil }
            return (p, true)
        }
    }

    private func place(_ a: Anchor) -> (pos: CGPoint, rot: CGFloat) {
        guard let t = track(a) else { return (CGPoint(x: bounds.midX, y: bounds.midY), 0) }
        return polySample(t.pts, closed: t.closed, a.d)
    }

    private func spriteCentre() -> CGPoint {
        if let h = held { return h }
        if let h = hop {
            let t = CGFloat(h.t / h.dur)
            return CGPoint(x: h.from.x + (h.to.x - h.from.x) * t,
                           y: h.from.y + (h.to.y - h.from.y) * t + h.arc * 4 * t * (1 - t))
        }
        return place(anchor).pos
    }

    private func spriteRotation() -> CGFloat {
        if held != nil { return 0 }
        if let h = hop {
            var delta = h.rot1 - h.rot0
            while delta > .pi { delta -= 2 * .pi }
            while delta < -.pi { delta += 2 * .pi }
            return h.rot0 + delta * CGFloat(h.t / h.dur)
        }
        return place(anchor).rot
    }

    private func spriteRect() -> NSRect {
        let c = spriteCentre()
        return NSRect(x: c.x - DSP / 2, y: c.y - DSP / 2, width: DSP, height: DSP)
    }

    // ── Movement ─────────────────────────────────────────────────────────
    private func setAnim(_ name: String) {
        guard ANIMS[name] != nil, anim != name else { return }
        anim = name; frameIdx = 0; frameTimer = 0
    }

    /// `origin` matters when he is not currently where his anchor says he is --
    /// dropped from your cursor, or standing on a window that just closed.
    private func startHop(to dest: Anchor, from origin: CGPoint? = nil, fromRot: CGFloat? = nil) {
        guard let t = track(dest) else { return }
        let from = origin ?? spriteCentre()
        let d = polyNearest(t.pts, closed: t.closed, to: from)
        let s = polySample(t.pts, closed: t.closed, d)
        let dist = hypot(s.pos.x - from.x, s.pos.y - from.y)
        guard dist > 2 else { anchor = dest.at(d); return }
        // Dropping is a scramble, not a leap: keep the arc low when he's falling.
        let falling = s.pos.y < from.y - 40
        hop = Hop(from: from, to: s.pos,
                  rot0: fromRot ?? spriteRotation(), rot1: s.rot,
                  arc: falling ? min(30, 8 + dist * 0.05) : min(90, 24 + dist * 0.18),
                  dur: Double(max(0.35, min(0.95, dist / 700))), t: 0,
                  land: dest.at(d))
        vel = 0
        setAnim("run")
    }

    private func nearestAnchor(to p: CGPoint) -> Anchor {
        var best = Anchor.rim(polyNearest(rimPoints(), closed: true, to: p))
        var bestDist = hypot(place(best).pos.x - p.x, place(best).pos.y - p.y)
        for (id, pts) in ledges() {
            let d = polyNearest(pts, closed: true, to: p)
            let q = polySample(pts, closed: true, d).pos
            let dist = hypot(q.x - p.x, q.y - p.y)
            if dist < bestDist { bestDist = dist; best = .win(id, d) }
        }
        return best
    }

    /// Shortest signed way from `d` to `to` along a track.
    private func delta(_ d: CGFloat, _ to: CGFloat, total: CGFloat, closed: Bool) -> CGFloat {
        var x = to - d
        if closed && total > 0 {
            while x > total / 2 { x -= total }
            while x < -total / 2 { x += total }
        }
        return x
    }

    private func step(_ dt: Double, _ now: Double) {
        // Dragged: he just hangs off the cursor.
        if held != nil {
            held = CGPoint(x: world.mouse.x + grabOffset.width, y: world.mouse.y + grabOffset.height)
            setAnim("react")
            return
        }

        // Mid-hop.
        if var h = hop {
            h.t += dt
            if h.t >= h.dur {
                hop = nil
                anchor = h.land
                setAnim("idle")
                nextDecision = now + 0.3
            } else {
                hop = h
                setAnim("run")
            }
            return
        }

        // The app we were told to go visit, once one of its windows shows up.
        if wantPID != 0 {
            if now > wantUntil { wantPID = 0 }
            else if let w = world.windows.first(where: { $0.pid == wantPID }),
                    ledges().contains(where: { $0.0 == w.id }) {
                wantPID = 0
                goal = .win(w.id, 0)
                goalUntil = now + 25      // long enough to walk there, not just jump
            }
        }

        guard let t = track(anchor) else {
            // His window closed under him. Scramble down from where he actually
            // was -- `spriteCentre()` can no longer tell us, the track is gone.
            let was = lastCentre
            startHop(to: nearestAnchor(to: was), from: was)
            if hop == nil { anchor = nearestAnchor(to: was) }
            return
        }
        let total = polyLength(t.pts, closed: t.closed)
        if now > goalUntil { goal = nil }

        // A goal on another track: walk to the closest point on this one first
        // and only jump the last stretch, so he arrives rather than teleports.
        var approach: CGFloat?
        if let g = goal, !anchor.sameTrack(g) {
            guard let gt = track(g) else { goal = nil; return }
            let me = spriteCentre()
            let landD = polyNearest(gt.pts, closed: gt.closed, to: me)
            let landing = polySample(gt.pts, closed: gt.closed, landD).pos
            if hypot(landing.x - me.x, landing.y - me.y) < HOP_REACH {
                startHop(to: g)
                return
            }
            approach = polyNearest(t.pts, closed: t.closed, to: landing)
        }

        if now >= nextDecision { pickAction(now) }

        // Steer toward the approach point, a goal on this track, or the cursor.
        var aim: CGFloat?
        if let ap = approach {
            // Arrived at the nearest point and still out of range? Jump anyway.
            if abs(delta(anchor.d, ap, total: total, closed: t.closed)) < 12, let g = goal {
                startHop(to: g); return
            }
            aim = ap
        }
        else if let g = goal { aim = g.d }
        else if mood == "cursor" { aim = polyNearest(t.pts, closed: t.closed, to: world.mouse) }
        if let target = aim {
            let dx = delta(anchor.d, target, total: total, closed: t.closed)
            if abs(dx) < 10 {
                targetVel = 0
                if approach == nil, goal != nil { goal = nil; nextDecision = now + 0.2 }
            } else {
                targetVel = (dx > 0 ? 1 : -1) * (abs(dx) > 260 ? RUN_SPEED : WALK_SPEED)
            }
        }

        let k = 1 - CGFloat(exp(-Double(ACCEL) * dt))
        vel += (targetVel - vel) * k
        var d = anchor.d + vel * CGFloat(dt)

        if t.closed {
            if total > 0 { d = d.truncatingRemainder(dividingBy: total); if d < 0 { d += total } }
        } else if d < 0 || d > total {
            d = max(0, min(total, d))
            targetVel = -targetVel      // reached the end of a window; turn around
            vel = -vel * 0.4
        }
        anchor = anchor.at(d)

        if abs(vel) > 2 { facingForward = vel > 0 }
        else { faceTheCursor(t.pts, t.closed) }

        if mood == "sleep" { setAnim("sleep") }
        else if mood == "excited" { setAnim("react") }
        else if abs(vel) > 8 { setAnim("run") }
        else { setAnim("idle") }

        lastCentre = spriteCentre()
    }

    /// Standing still, he turns to watch the pointer if it's nearby.
    private func faceTheCursor(_ pts: [CGPoint], _ closed: Bool) {
        let m = world.mouse, c = spriteCentre()
        guard hypot(m.x - c.x, m.y - c.y) < 420 else { return }
        let total = polyLength(pts, closed: closed)
        let dx = delta(anchor.d, polyNearest(pts, closed: closed, to: m), total: total, closed: closed)
        if abs(dx) > 12 { facingForward = dx > 0 }
    }

    private func pickAction(_ now: Double) {
        if mood == "sleep" || mood == "excited" || mood == "cursor" {
            if now < moodUntil { return }
            mood = "idle"
        }
        // Away long enough that he gives up on you and naps.
        if world.idle > IDLE_NAP {
            targetVel = 0; mood = "sleep"
            moodUntil = now + 20
            nextDecision = moodUntil
            setAnim("sleep")
            return
        }
        if goal != nil { nextDecision = now + 0.4; return }

        let r = Double.random(in: 0..<1)
        let dir: CGFloat = Bool.random() ? 1 : -1
        if r < 0.10, let pick = ledges().randomElement(), !anchor.sameTrack(.win(pick.0, 0)) {
            startHop(to: .win(pick.0, 0))          // go stand on one of your windows
            nextDecision = now + 2.0
        } else if r < 0.15, case .win = anchor {
            startHop(to: .rim(0))                  // back to the screen edge
            nextDecision = now + 2.0
        } else if r < 0.25 {
            mood = "cursor"                        // go see what the pointer is doing
            moodUntil = now + 3 + Double.random(in: 0..<5)
            nextDecision = moodUntil
        } else if r < 0.52 {
            targetVel = dir * WALK_SPEED; mood = "roam"
            nextDecision = now + 2.5 + Double.random(in: 0..<3.5)
        } else if r < 0.70 {
            targetVel = dir * RUN_SPEED; mood = "roam"
            nextDecision = now + 1.5 + Double.random(in: 0..<2.5)
        } else if r < 0.85 {
            targetVel = 0; mood = "idle"
            nextDecision = now + 1.5 + Double.random(in: 0..<3.0)
        } else if r < 0.94 {
            targetVel = 0; mood = "excited"
            moodUntil = now + 1.8 + Double.random(in: 0..<1.2)
            nextDecision = moodUntil + 0.4; setAnim("react")
        } else {
            targetVel = 0; mood = "sleep"
            moodUntil = now + 8 + Double.random(in: 0..<6)
            nextDecision = moodUntil + 0.4; setAnim("sleep")
        }
    }

    private func advanceFrame(_ dt: Double) {
        guard let a = ANIMS[anim] else { return }
        frameTimer += dt
        let dur = 1.0 / a.fps
        while frameTimer >= dur { frameTimer -= dur; frameIdx = (frameIdx + 1) % COLS }
    }

    // ── Events ───────────────────────────────────────────────────────────
    private func handle(_ cue: Cue, _ arg: String, _ pid: pid_t) {
        let now = CACurrentMediaTime()
        switch cue {
        case .appLaunch, .appSwitch:
            // Like a cat: now and then he wanders over to see what you opened,
            // but mostly he carries on with whatever he was doing.
            guard now - lastNotice > 45 else { return }
            lastNotice = now
            if Double.random(in: 0..<1) < (cue == .appLaunch ? 0.4 : 0.15) {
                wantPID = pid                   // its window may not exist yet
                wantUntil = now + 5
                excite(now)
            } else if Double.random(in: 0..<1) < 0.65 {
                return                          // noticed you. didn't get up.
            }
        case .returned, .woke:
            lastBreak = now
            if cue == .woke { start() }
            excite(now)
        default:
            break
        }
        say(cue, arg, now)
    }

    private func excite(_ now: Double) {
        mood = "excited"; moodUntil = now + 1.6; targetVel = 0
        nextDecision = moodUntil
        setAnim("react")
    }

    // ── Speech ───────────────────────────────────────────────────────────
    private func scheduleNextSpeak(_ now: Double) { nextSpeak = now + 25 + Double.random(in: 0..<155) }

    /// A cue the current state actually justifies, so "many many windows" can't
    /// fire at someone with one window open.
    private func ambientCue() -> Cue {
        if world.windows.count >= 7 && Double.random(in: 0..<1) < 0.35 { return .manyWindows }
        if CACurrentMediaTime() - lastBreak > SIT_TOO_LONG && world.idle < 90
            && Double.random(in: 0..<1) < 0.3 { return .sitting }
        return .chatter
    }

    private func say(_ cue: Cue, _ arg: String, _ now: Double) {
        var pool = lines.filter { $0.cue == cue }
        if pool.isEmpty { pool = lines.filter { $0.cue == .chatter } }
        guard let line = pool.randomElement() else { return }

        if line.anim == "sleep" {
            mood = "sleep"; moodUntil = now + 5.5; targetVel = 0; nextDecision = moodUntil + 0.4
        } else if line.anim == "react" {
            mood = "excited"; moodUntil = now + 3.0; targetVel = 0; nextDecision = moodUntil + 0.4
        }

        let text = arg.isEmpty ? line.text : line.text.replacingOccurrences(of: "%@", with: arg)
        speech = text
        speechStart = now
        speechEnd = now + Double(text.count) * TYPE_SEC + HOLD_SEC + FADE_SEC
        speechTail = spriteRotation()
        speechSize = bubbleSize(for: text)
        shownChars = -1

        let r = spriteRect()
        if line.fx == "sparkles" { spawnSparkles(r, now) }
        if line.fx == "zzz" { spawnZzz(r, now) }
        scheduleNextSpeak(now)
    }

    private func maybeSpeak(_ now: Double) {
        guard now >= nextSpeak, speech == nil, world.idle < IDLE_NAP else { return }
        say(ambientCue(), "", now)
    }

    private func bubbleSize(for text: String) -> NSSize {
        let inner = BUBBLE_W - 20
        let h = ceil(NSAttributedString(string: text, attributes: [.font: bubbleFont])
            .boundingRect(with: NSSize(width: inner, height: .greatestFiniteMagnitude),
                          options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 14
        return NSSize(width: BUBBLE_W, height: h)
    }

    /// Where the bubble sits *right now*, for wherever he is right now. It
    /// normally goes on the side he's facing away from, but near a screen edge
    /// there may be no room: clamping it back on screen would drag it straight
    /// over him, so in that case it flips to his other side instead.
    func bubbleLayout() -> (rect: NSRect, up: CGPoint) {
        let s = spriteRect(), gap: CGFloat = 10, pad: CGFloat = 6
        let w = speechSize.width, h = speechSize.height

        func place(_ dir: CGPoint) -> (NSRect, CGFloat) {
            let rawX = s.midX - w / 2 + dir.x * (w / 2 + gap + DSP / 2)
            let rawY = s.midY - h / 2 + dir.y * (h / 2 + gap + DSP / 2)
            let x = max(pad, min(bounds.width - w - pad, rawX))
            let y = max(pad, min(bounds.height - h - pad, rawY))
            return (NSRect(x: x, y: y, width: w, height: h), abs(x - rawX) + abs(y - rawY))
        }

        let up = CGPoint(x: -sin(speechTail), y: cos(speechTail))
        let first = place(up)
        if first.1 < 1 { return (first.0, up) }          // fits where it belongs
        let down = CGPoint(x: -up.x, y: -up.y)
        let second = place(down)
        return second.1 < first.1 ? (second.0, down) : (first.0, up)
    }

    /// How far the tail slides along the bubble edge to keep pointing at him.
    /// Zero unless the bubble has been clamped against a screen edge.
    private func tailOffset(_ r: NSRect, _ up: CGPoint) -> CGFloat {
        let s = spriteRect()
        // `up` vertical (floor/ceiling) => bubble sits on a horizontal edge =>
        // the tail slides in x. On a wall it is the other way round.
        let slidesInX = abs(up.y) > 0.5
        let slack = (slidesInX ? r.width : r.height) / 2 - 14
        let d = slidesInX ? s.midX - r.midX : s.midY - r.midY
        return max(-slack, min(slack, d))
    }

    private func syncBubble(_ now: Double) {
        guard let text = speech else {
            if !bubble.isHidden { bubble.isHidden = true; bubble.contents = nil }
            return
        }
        let elapsed = now - speechStart
        let typed = min(text.count, max(0, Int(elapsed / TYPE_SEC)))
        let turned = abs(spriteRotation() - speechTail) > 0.1
        if turned { speechTail = spriteRotation() }        // he rounded a corner mid-sentence
        let (r, up) = bubbleLayout()
        let flipped = abs(up.x - shownUp.x) + abs(up.y - shownUp.y) > 0.01
        let tail = tailOffset(r, up)

        // The image only changes when a character lands, he turns a corner, or
        // the tail slides far enough to notice. Following him is a position set.
        if typed != shownChars || turned || flipped || abs(tail - shownTailAt) > 2 {
            shownChars = typed
            shownTailAt = tail
            shownUp = up
            bubble.bounds = CGRect(x: 0, y: 0, width: speechSize.width + BUBBLE_PAD * 2,
                                   height: speechSize.height + BUBBLE_PAD * 2)
            bubble.contents = bubbleImage(String(text.prefix(typed)), tail: tail, up: up)
            bubble.isHidden = false
        }
        bubble.position = CGPoint(x: r.midX, y: r.midY)
        bubble.opacity = Float(min(min(1, elapsed / 0.18), max(0, (speechEnd - now) / FADE_SEC)))
    }

    private func bubbleImage(_ shown: String, tail: CGFloat, up: CGPoint) -> CGImage? {
        let w = Int((speechSize.width + BUBBLE_PAD * 2) * scale)
        let h = Int((speechSize.height + BUBBLE_PAD * 2) * scale)
        guard w > 0, h > 0,
              let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        c.scaleBy(x: scale, y: scale)

        let r = NSRect(x: BUBBLE_PAD, y: BUBBLE_PAD, width: speechSize.width, height: speechSize.height)
        let tip: CGFloat = 10, half: CGFloat = 5
        let tx = r.midX + tail, ty = r.midY + tail
        let tri = CGMutablePath()
        if abs(up.y) > 0.5 {      // the tail leaves from whichever edge faces him
            let edge = up.y > 0 ? r.minY : r.maxY, dir: CGFloat = up.y > 0 ? -1 : 1
            tri.move(to: CGPoint(x: tx - half, y: edge)); tri.addLine(to: CGPoint(x: tx + half, y: edge))
            tri.addLine(to: CGPoint(x: tx, y: edge + tip * dir))
        } else {
            let edge = up.x > 0 ? r.minX : r.maxX, dir: CGFloat = up.x > 0 ? -1 : 1
            tri.move(to: CGPoint(x: edge, y: ty - half)); tri.addLine(to: CGPoint(x: edge, y: ty + half))
            tri.addLine(to: CGPoint(x: edge + tip * dir, y: ty))
        }
        tri.closeSubpath()

        c.setFillColor(EDGE); c.addPath(tri); c.fillPath()
        c.setFillColor(FILL); c.setStrokeColor(EDGE); c.setLineWidth(2)
        c.addPath(CGPath(roundedRect: r, cornerWidth: 6, cornerHeight: 6, transform: nil))
        c.drawPath(using: .fillStroke)

        let prev = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
        NSAttributedString(string: shown, attributes: [
            .font: bubbleFont,
            .foregroundColor: NSColor(srgbRed: 0.831, green: 0.961, blue: 0.886, alpha: 1),
        ]).draw(with: r.insetBy(dx: 10, dy: 7), options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.current = prev

        return c.makeImage()
    }

    // ── Petting and dragging ─────────────────────────────────────────────
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Clicks pass through the whole screen except the patch he's standing on.
    private func updateClickThrough() {
        guard let win = window else { return }
        let hot = grabbing || held != nil || spriteRect().insetBy(dx: DSP * 0.18, dy: DSP * 0.18).contains(world.mouse)
        if hot != clickable {
            clickable = hot
            win.ignoresMouseEvents = !hot
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard spriteRect().insetBy(dx: DSP * 0.18, dy: DSP * 0.18).contains(p) else { return }
        // Deliberately does NOT set `held` yet: being carried forces him upright,
        // and a pet on the ceiling should leave him hanging where he is.
        grabbing = true
        grabStart = p
        grabOffset = CGSize(width: spriteCentre().x - p.x, height: spriteCentre().y - p.y)
        dragMoved = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard grabbing else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard hypot(p.x - grabStart.x, p.y - grabStart.y) > 5 else { return }
        if !dragMoved {
            dragMoved = true
            held = spriteCentre()          // now he really is being carried
            hop = nil
            say(.dragged, "", CACurrentMediaTime())
        }
    }

    override func mouseUp(with event: NSEvent) {
        let now = CACurrentMediaTime()
        if let landedAt = held {
            held = nil
            // Scramble to whatever surface is nearest where you let go, starting
            // from there -- not from wherever he happened to be standing before.
            startHop(to: nearestAnchor(to: landedAt), from: landedAt, fromRot: 0)
        } else if grabbing {
            excite(now)
            spawnSparkles(spriteRect(), now)
            say(.petted, "", now)
        }
        grabbing = false
        dragMoved = false
    }

    // ── Particles ────────────────────────────────────────────────────────
    // Fire-and-forget: Core Animation runs them, the tick loop never sees them.
    private func addParticle(_ l: CALayer, from: CGPoint, drift: CGPoint,
                             delay: Double, life: Double, shrink: Bool) {
        l.contentsScale = scale
        l.position = from
        l.opacity = 0
        layer?.addSublayer(l)

        let to = CGPoint(x: from.x + drift.x, y: from.y + drift.y)
        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = from; move.toValue = to
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0; fade.toValue = 0.0
        var anims = [move, fade]
        if shrink {
            let sc = CABasicAnimation(keyPath: "transform.scale")
            sc.fromValue = 1.0; sc.toValue = 0.01
            anims.append(sc)
        }
        let g = CAAnimationGroup()
        g.animations = anims
        g.duration = life
        g.beginTime = CACurrentMediaTime() + delay
        g.fillMode = .backwards
        g.timingFunction = CAMediaTimingFunction(name: .easeOut)
        l.add(g, forKey: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay + life) { l.removeFromSuperlayer() }
    }

    private func spawnSparkles(_ s: NSRect, _ now: Double) {
        for i in 0..<6 {
            let angle = CGFloat.random(in: 0..<(.pi * 2))
            let dist = CGFloat.random(in: 20..<60)
            let dot = CALayer()
            dot.bounds = CGRect(x: 0, y: 0, width: 6, height: 6)
            dot.cornerRadius = 3
            dot.backgroundColor = EDGE
            addParticle(dot,
                from: CGPoint(x: s.minX + DSP * 0.3 + CGFloat.random(in: 0..<(DSP * 0.4)),
                              y: s.minY + DSP * 0.5 + CGFloat.random(in: 0..<(DSP * 0.5))),
                drift: CGPoint(x: cos(angle) * dist, y: sin(angle) * dist + 20),
                delay: Double(i) * 0.08, life: 0.9, shrink: true)
        }
    }

    private func spawnZzz(_ s: NSRect, _ now: Double) {
        for (i, txt) in ["z", "zz", "zzz"].enumerated() {
            let size = 9 + CGFloat(i) * 3
            let t = CATextLayer()
            t.string = txt
            t.font = "Times New Roman" as CFString
            t.fontSize = size
            t.foregroundColor = CGColor(srgbRed: 0.667, green: 0.831, blue: 1, alpha: 1)
            t.bounds = CGRect(x: 0, y: 0, width: size * 3, height: size * 1.4)
            t.alignmentMode = .center
            addParticle(t,
                from: CGPoint(x: s.minX + DSP * 0.5 + CGFloat(i) * 8, y: s.maxY + 5 + CGFloat(i) * 10),
                drift: CGPoint(x: 14, y: 36),
                delay: Double(i) * 0.3, life: 2.0, shrink: false)
        }
    }

    // ── Layer sync ───────────────────────────────────────────────────────
    private func spriteTransform() -> CATransform3D {
        let t = CATransform3DMakeRotation(spriteRotation(), 0, 0, 1)
        return facingForward ? t : CATransform3DScale(t, -1, 1, 1)
    }
    private func spriteImage() -> CGImage? { frames[safe: ANIMS[anim]!.row]?[safe: frameIdx] }

    private func spriteNeedsSync() -> Bool {
        let p = spriteCentre()
        // Tolerance, not rounding: rounding quantised the walk into visible steps,
        // but an exact compare never settles because velocity decay is asymptotic.
        return abs(p.x - sprite.position.x) > 0.05 || abs(p.y - sprite.position.y) > 0.05
            || (sprite.contents as AnyObject?) !== (spriteImage() as AnyObject?)
            || !CATransform3DEqualToTransform(sprite.transform, spriteTransform())
    }

    private func syncSprite() {
        sprite.position = spriteCentre()
        if let img = spriteImage(), (sprite.contents as AnyObject?) !== (img as AnyObject) {
            sprite.contents = img
        }
        let t = spriteTransform()
        if !CATransform3DEqualToTransform(sprite.transform, t) { sprite.transform = t }
    }

    // ── Self test ────────────────────────────────────────────────────────
    /// `Rocky --selftest`. Covers the geometry that actually has edge cases:
    /// the polyline walker, the rim wrap, the rotations it derives, and the
    /// bubble staying on screen from anywhere he can stand.
    func selfTest() {
        let rim = rimPoints()
        let total = polyLength(rim, closed: true)
        precondition(total > 0, "empty rim")

        // Rotation per leg: floor 0, right wall +90, ceiling 180, left wall -90.
        for (frac, want) in [(0.1, 0.0), (0.35, Double.pi / 2), (0.6, Double.pi), (0.85, -Double.pi / 2)] {
            let got = Double(polySample(rim, closed: true, total * CGFloat(frac)).rot)
            precondition(abs(got - want) < 0.01, "leg at \(frac) rotates \(got), want \(want)")
        }

        // sample -> nearest round trip
        for i in 0..<200 {
            let d = total * CGFloat(i) / 200
            let back = polyNearest(rim, closed: true, to: polySample(rim, closed: true, d).pos)
            precondition(abs(back - d) < 1.0, "round trip \(d) -> \(back)")
        }

        // Lap the rim both ways; he must stay on screen and never lose the track.
        mood = "roam"; nextDecision = .infinity
        for direction in [RUN_SPEED, -RUN_SPEED] {
            targetVel = direction; vel = direction; anchor = .rim(80)
            for _ in 0..<1400 {
                step(1.0 / 60, 0)
                precondition(anchor.d >= 0 && anchor.d <= total, "rim d escaped: \(anchor.d)")
                precondition(bounds.contains(spriteRect()), "sprite \(spriteRect()) left \(bounds)")
            }
        }

        // A window is a closed loop crawled clockwise, so his feet always face
        // it: up the left side, across the top, down the right, under the bottom.
        let wrect = NSRect(x: 300, y: 250, width: 420, height: 260)
        let wt = windowTrack(Win(id: 1, owner: "t", pid: 1, rect: wrect))!
        precondition(wt.count == 4, "window track should be a rectangle")
        let wlen = polyLength(wt, closed: true)
        let out = DSP / 2 - LEDGE_BITE
        precondition(abs(wlen - 2 * ((wrect.width + out * 2) + (wrect.height + out * 2))) < 0.1,
                     "window perimeter \(wlen)")
        for (frac, want, side) in [(0.12, Double.pi / 2, "left side"),
                                   (0.38, 0.0, "top"),
                                   (0.62, -Double.pi / 2, "right side"),
                                   (0.88, Double.pi, "underside")] {
            let got = Double(polySample(wt, closed: true, wlen * CGFloat(frac)).rot)
            precondition(abs(got - want) < 0.01, "window \(side) rotates \(got), want \(want)")
        }

        // An open ledge must clamp at both ends rather than run off.
        let ledge = [CGPoint(x: 200, y: 400), CGPoint(x: 600, y: 400)]
        let llen = polyLength(ledge, closed: false)
        precondition(abs(llen - 400) < 0.01, "ledge length \(llen)")
        precondition(polySample(ledge, closed: false, -50).pos.x == 200, "ledge underrun")
        precondition(polySample(ledge, closed: false, 999).pos.x == 600, "ledge overrun")
        precondition(abs(polySample(ledge, closed: false, 200).rot) < 0.01, "ledge should be flat")

        // The bubble stays on screen from every position, on every leg.
        let longest = lines.max(by: { $0.text.count < $1.text.count })!.text
        speechSize = bubbleSize(for: longest)
        for i in 0..<400 {
            anchor = .rim(total * CGFloat(i) / 400)
            speechTail = place(anchor).rot
            let (r, _) = bubbleLayout()
            precondition(bounds.contains(r), "bubble \(r) escaped \(bounds) at d=\(anchor.d)")
            precondition(!r.insetBy(dx: 4, dy: 4).intersects(spriteRect().insetBy(dx: 18, dy: 18)),
                         "bubble \(r) sits on top of him at d=\(anchor.d)")
        }
        // Behaviour that has actually regressed before.
        let far = Win(id: 5, owner: "App", pid: 9, rect: NSRect(x: 1000, y: 430, width: 340, height: 250))
        world.setWindowsForTest([far])
        nextDecision = .infinity

        // A goal across the screen is walked to, not teleported to.
        anchor = .rim(120); vel = 0; targetVel = 0
        let from = anchor.d
        goal = .win(5, 0); goalUntil = 1e9
        var moved = false, hopTick = -1
        for i in 0..<600 {
            step(1.0 / 60, Double(i) / 60)
            if case .rim(let d) = anchor, abs(d - from) > 60 { moved = true }
            if hop != nil && hopTick < 0 { hopTick = i }
            if case .win = anchor { break }
        }
        precondition(moved, "he teleported instead of walking to the goal")
        precondition(hopTick > 30, "hopped immediately (tick \(hopTick)) instead of closing the gap first")

        // A window closing drops him from where he stood, not the screen centre.
        hop = nil; goal = nil
        anchor = .win(5, polyLength(windowTrack(far)!, closed: true) * 0.38)
        step(1.0 / 60, 0)
        let stood = lastCentre
        world.setWindowsForTest([])
        step(1.0 / 60, 1.0 / 60)
        precondition(hop != nil, "snapped instead of hopping off a closed window")
        precondition(hypot(hop!.from.x - stood.x, hop!.from.y - stood.y) < 2,
                     "hop began at \(hop!.from), he was at \(stood)")

        // A window buried behind another is not climbable.
        let buried = Win(id: 6, owner: "Back", pid: 1, rect: NSRect(x: 300, y: 250, width: 400, height: 300))
        let onTop = Win(id: 7, owner: "Front", pid: 2, rect: NSRect(x: 250, y: 200, width: 520, height: 420))
        world.setWindowsForTest([onTop, buried])
        precondition(ledges().contains { $0.0 == 7 }, "front window should be climbable")
        precondition(!ledges().contains { $0.0 == 6 }, "buried window must not be climbable")

        // Petting must not stand him up: `held` is what forces him upright, and
        // a click alone must never set it.
        hop = nil; anchor = .rim(polyLength(rimPoints(), closed: true) * 0.36)
        let pose = spriteRotation()
        precondition(abs(pose - .pi / 2) < 0.01, "expected him sideways, got \(pose)")
        grabbing = true
        precondition(abs(spriteRotation() - pose) < 0.01, "a pet stood him upright")
        grabbing = false

        world.setWindowsForTest([])
        anchor = .rim(80); speech = nil; mood = "idle"; targetVel = 0; vel = 0
        goal = nil; hop = nil; nextDecision = 0
        print("selftest ok — \(lines.count) dialogue lines")
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
