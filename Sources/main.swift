import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private var rocky: RockyView!
    private let showItem = NSMenuItem(title: "Hide Rocky", action: #selector(toggleShow), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")

    private var visible: Bool {
        get { UserDefaults.standard.object(forKey: "visible") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "visible") }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        guard let url = Bundle.main.url(forResource: "spritesheet", withExtension: "png"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sheet = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            NSApp.terminate(nil); return
        }

        let frame = walkFrame()
        rocky = RockyView(frame: NSRect(origin: .zero, size: frame.size), sheet: sheet)

        window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        window.contentView = rocky
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true          // toggled off only over his sprite
        // Above the Dock (20), below the menu bar (24), so he can walk the real
        // bottom edge of the screen and stay visible crossing the Dock.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.isReleasedWhenClosed = false

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = rocky.statusIcon()
        let menu = NSMenu()
        menu.delegate = self
        for item in [showItem, loginItem] { item.target = self; menu.addItem(item) }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Rocky", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let f = self.walkFrame()
            self.window.setFrame(f, display: true)
            self.rocky.screenChanged(f)
        }

        apply(visible)
    }

    /// The screen minus the menu bar, and nothing else. Deliberately not
    /// `visibleFrame`: that also subtracts the Dock's full height across the whole
    /// width, so wherever the Dock isn't, Rocky ends up walking on thin air. The
    /// menu bar is the only strip he genuinely can't be drawn over, and measuring
    /// it this way costs nothing and adapts on its own -- autohidden menu bar,
    /// notch, Dock on any edge at any size, all fall out of it.
    private func walkFrame() -> NSRect {
        guard let screen = NSScreen.main else { return NSRect(x: 0, y: 0, width: 1440, height: 900) }
        var f = screen.frame
        f.size.height -= max(0, f.maxY - screen.visibleFrame.maxY)
        return f
    }

    private func apply(_ show: Bool) {
        if show { window.orderFrontRegardless(); rocky.start() }
        else { rocky.stop(); window.orderOut(nil) }
    }

    @objc private func toggleShow() { visible.toggle(); apply(visible) }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            NSApp.activate(ignoringOtherApps: true)   // accessory apps aren't frontmost
            let a = NSAlert(error: error)
            a.messageText = "Couldn't change the login item"
            a.runModal()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        showItem.title = visible ? "Hide Rocky" : "Show Rocky"
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}

let app = NSApplication.shared

if CommandLine.arguments.contains("--selftest") {
    let url = Bundle.main.url(forResource: "spritesheet", withExtension: "png")!
    let sheet = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL, nil)!, 0, nil)!
    RockyView(frame: NSRect(x: 0, y: 0, width: 1440, height: 900), sheet: sheet).selfTest()
    exit(0)
}

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
