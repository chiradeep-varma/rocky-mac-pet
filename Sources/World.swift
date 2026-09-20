import AppKit
import IOKit.ps

// Everything Rocky is allowed to notice about your machine. Strictly the things
// macOS hands over without a permission prompt -- no Accessibility, no Screen
// Recording. Window geometry and owner names are fair game; window *titles* and
// keystrokes are not, and aren't read here.

struct Win {
    let id: CGWindowID
    let owner: String
    let pid: pid_t
    let rect: NSRect      // already in Rocky's view coordinates
}

enum Cue: String {
    case chatter        // the ambient default
    case appLaunch, appSwitch, manyWindows, lateNight, morning
    case returned, woke, batteryLow, charging, petted, dragged, sitting
}

final class World {
    private(set) var windows: [Win] = []
    private(set) var frontApp = ""
    private(set) var frontPID: pid_t = 0
    private(set) var idle: TimeInterval = 0
    private(set) var batteryPct = 100
    private(set) var charging = true
    private(set) var asleep = false
    /// Bumped whenever the window list is replaced, so derived work can be cached.
    private(set) var generation = 0

    /// Fired for things worth reacting to. The payload fills a `%@` in a line.
    var onEvent: ((Cue, String, pid_t) -> Void)?

    private var originFrame = NSRect.zero    // the view's frame in screen coords
    private var lastWindowPoll = 0.0
    private var lastSlowPoll = 0.0
    private var lastIdlePoll = 0.0
    private var cachedMouse = CGPoint.zero
    private var wasIdle = false
    private var lastHour = -1
    private var warnedBattery = false
    private var obs: [NSObjectProtocol] = []

    // ── Lifecycle ────────────────────────────────────────────────────────
    func start(viewFrame: NSRect) {
        originFrame = viewFrame
        let nc = NSWorkspace.shared.notificationCenter
        func on(_ name: NSNotification.Name, _ body: @escaping (Notification) -> Void) {
            obs.append(nc.addObserver(forName: name, object: nil, queue: .main) { body($0) })
        }
        on(NSWorkspace.didLaunchApplicationNotification) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let name = app.localizedName, app.activationPolicy == .regular else { return }
            self?.onEvent?(.appLaunch, name, app.processIdentifier)
        }
        on(NSWorkspace.didActivateApplicationNotification) { [weak self] n in
            guard let self,
                  let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let name = app.localizedName else { return }
            let changed = name != self.frontApp && !self.frontApp.isEmpty
            self.frontApp = name
            self.frontPID = app.processIdentifier
            if changed { self.onEvent?(.appSwitch, name, app.processIdentifier) }
        }
        on(NSWorkspace.screensDidSleepNotification) { [weak self] _ in self?.asleep = true }
        on(NSWorkspace.screensDidWakeNotification) { [weak self] _ in
            self?.asleep = false
            self?.onEvent?(.woke, "", 0)
        }
        if let front = NSWorkspace.shared.frontmostApplication {
            frontApp = front.localizedName ?? ""
            frontPID = front.processIdentifier
        }
        pollWindows()
        pollSlow()
    }

    func viewFrameChanged(_ f: NSRect) { originFrame = f; pollWindows() }

    // ── Polling ──────────────────────────────────────────────────────────
    /// Called every tick, but nothing here actually runs at tick rate -- each
    /// job has its own much slower clock, and the pointer is read once per tick
    /// rather than once per caller.
    func poll(_ now: Double) {
        let m = NSEvent.mouseLocation
        cachedMouse = CGPoint(x: m.x - originFrame.minX, y: m.y - originFrame.minY)

        if now - lastIdlePoll > 0.25 {
            lastIdlePoll = now
            idle = CGEventSource.secondsSinceLastEventType(.hidSystemState,
                                                           eventType: CGEventType(rawValue: ~0)!)
            if idle < 2 && wasIdle {
                wasIdle = false
                onEvent?(.returned, "", 0)
            } else if idle > 120 {
                wasIdle = true
            }
        }
        if now - lastWindowPoll > 1.0 { lastWindowPoll = now; pollWindows() }
        if now - lastSlowPoll > 20.0 { lastSlowPoll = now; pollSlow() }
    }

    /// Mouse in view coordinates, sampled once per tick. Free — only *global
    /// event monitors* need a permission grant, reading the location does not.
    var mouse: CGPoint { cachedMouse }

    private func pollWindows() {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                   kCGNullWindowID) as? [[String: Any]] else { return }
        let me = getpid()
        let screenH = NSScreen.main?.frame.height ?? originFrame.height
        var out: [Win] = []
        for w in raw {
            guard (w[kCGWindowLayer as String] as? Int) == 0,                 // normal app windows only
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let id = w[kCGWindowNumber as String] as? CGWindowID,
                  let cgW = b["Width"], let cgH = b["Height"], cgW > 160, cgH > 80
            else { continue }
            // CG is y-down from the main display's top-left; we are y-up from the
            // view's bottom-left.
            let r = NSRect(x: b["X"]! - originFrame.minX,
                           y: screenH - b["Y"]! - cgH - originFrame.minY,
                           width: cgW, height: cgH)
            out.append(Win(id: id,
                           owner: w[kCGWindowOwnerName as String] as? String ?? "",
                           pid: pid, rect: r))
        }
        windows = out       // front-to-back, the order CGWindowList returns
        generation &+= 1
    }

    private func pollSlow() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let d = list.first.flatMap({
                  IOPSGetPowerSourceDescription(blob, $0)?.takeUnretainedValue() as? [String: Any]
              })
        else { return }
        let wasCharging = charging
        batteryPct = d[kIOPSCurrentCapacityKey] as? Int ?? 100
        charging = (d[kIOPSIsChargingKey] as? Bool ?? false)
            || (d[kIOPSPowerSourceStateKey] as? String) == (kIOPSACPowerValue as String)

        if !charging && batteryPct <= 20 && !warnedBattery {
            warnedBattery = true
            onEvent?(.batteryLow, "\(batteryPct)", 0)
        }
        if charging && !wasCharging {
            warnedBattery = false
            onEvent?(.charging, "", 0)
        }
        if let c = clockCue() { onEvent?(c, "", 0) }
    }

    /// A cue the clock implies, if any — checked once when the hour rolls over so
    /// "sun gone" can't fire at nine in the morning.
    func clockCue() -> Cue? {
        let h = Calendar.current.component(.hour, from: Date())
        defer { lastHour = h }
        guard h != lastHour, lastHour >= 0 else { return nil }
        if h >= 23 || h < 4 { return .lateNight }
        if h >= 6 && h < 10 { return .morning }
        return nil
    }

    /// The frontmost window of whatever app you're actually using.
    func focusedWindow() -> Win? {
        windows.first { $0.pid == frontPID } ?? windows.first
    }

    func window(_ id: CGWindowID) -> Win? { windows.first { $0.id == id } }

    /// Only for `--selftest`, which needs a window that is definitely there and
    /// then definitely isn't.
    func setWindowsForTest(_ w: [Win]) { windows = w; generation &+= 1 }
}
