// Aurora HUD: a floating usage panel for the Claude desktop app.
//
// What it does: reads ~/.claude/aurora-usage.json (written by the aurora-billboard
// mod after every Claude Code response) and draws your 5-hour and weekly plan
// usage in an always-on-top panel. The limits are account-wide, so they include
// your Chat usage as of the last reading.
//
// What it never does: no network calls of its own, no Keychain or login token, no
// auto-update, no third-party code. Everything below is AppKit and Foundation.
// The one exception you trigger yourself: Refresh launches the claude CLI for a
// single tiny request, so a fresh reading lands in the file (see Refresher).
//
// Build:  swiftc -O main.swift -o AuroraHUD      (needs Xcode Command Line Tools)
// Use:    shows while the Claude desktop app is open, hides when it quits.
//         Click to collapse/expand, click ↻ to refresh, drag to move,
//         right-click for Refresh, themes and Quit.

import AppKit

// MARK: - Themes (same values as the aurora-billboard mod's themes.ts)

struct Theme {
    let name: String
    let label: String
    let ok: String, warn: String, hot: String, track: String, mute: String, accent: String
}

let THEMES: [Theme] = [
    Theme(name: "aurora", label: "Aurora", ok: "#8bc66b", warn: "#e5b454", hot: "#e0685c",
          track: "#4a4f5a", mute: "#8b8f98", accent: "#c99be8"),
    Theme(name: "ember", label: "Ember", ok: "#e3c08d", warn: "#d97757", hot: "#b8402f",
          track: "#4d4339", mute: "#9a8f80", accent: "#e3c08d"),
    Theme(name: "tide", label: "Tide", ok: "#5fd1c3", warn: "#5b8def", hot: "#b06ae8",
          track: "#3c4656", mute: "#8693a6", accent: "#8fb8ff"),
    Theme(name: "mono", label: "Mono", ok: "#7a7f88", warn: "#b3b7be", hot: "#ffffff",
          track: "#3d4048", mute: "#7a7f88", accent: "#b3b7be"),
]

func rgb(_ hex: String) -> (CGFloat, CGFloat, CGFloat) {
    let h = hex.replacingOccurrences(of: "#", with: "")
    let v = UInt32(h, radix: 16) ?? 0
    return (CGFloat((v >> 16) & 0xff) / 255, CGFloat((v >> 8) & 0xff) / 255, CGFloat(v & 0xff) / 255)
}

func color(_ hex: String, _ alpha: CGFloat = 1) -> NSColor {
    let (r, g, b) = rgb(hex)
    return NSColor(srgbRed: r, green: g, blue: b, alpha: alpha)
}

func mix(_ a: String, _ b: String, _ t: CGFloat) -> NSColor {
    let (r1, g1, b1) = rgb(a), (r2, g2, b2) = rgb(b)
    return NSColor(srgbRed: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: 1)
}

// Position 0...1 along ok -> warn -> hot. Same rule as the mod: a cell's color is
// fixed by where it sits, so a fuller bar reaches further into the hot end.
func spectrum(_ th: Theme, _ t: CGFloat) -> NSColor {
    let x = max(0, min(1, t))
    return x < 0.5 ? mix(th.ok, th.warn, x * 2) : mix(th.warn, th.hot, (x - 0.5) * 2)
}

// MARK: - The shared usage file

let SHARED_URL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".claude/aurora-usage.json")

// Same keys as Shared in aurora-billboard/types/index.d.ts.
enum SharedFile {
    static func read() -> [String: Any] {
        guard let data = try? Data(contentsOf: SHARED_URL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return root
    }

    // Merge one key in, keeping everything the mod wrote.
    static func set(_ key: String, _ value: Any) {
        var root = read()
        root[key] = value
        root["v"] = 1
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        else { return }
        try? FileManager.default.createDirectory(at: SHARED_URL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: SHARED_URL, options: .atomic)
    }
}

struct Usage {
    var fiveHour: Double?
    var sevenDay: Double?
    var fiveHourReset: TimeInterval?
    var sevenDayReset: TimeInterval?
    var sampleAge: TimeInterval?
    var problem: String?
    var isStale: Bool { (sampleAge ?? 0) > 15 * 60 }
}

enum UsageReader {
    static func num(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }

    static func date(_ s: String?) -> Date? {
        guard let s = s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    static func read(now: Date = Date()) -> Usage {
        let root = SharedFile.read()
        guard let stamp = num(root["updatedAt"]) else {
            return Usage(problem: "No reading yet · click ↻ to refresh")
        }

        // A window whose reset time has passed is back to zero (same rule as the band).
        func window(_ key: String) -> (Double?, TimeInterval?) {
            guard let w = root[key] as? [String: Any], let pct = num(w["percent"]) else { return (nil, nil) }
            guard let at = date(w["resetsAt"] as? String) else { return (pct, nil) }
            let left = at.timeIntervalSince(now)
            return left <= 0 ? (0, nil) : (pct, left)
        }

        let (fh, fhReset) = window("fiveHour")
        let (sd, sdReset) = window("sevenDay")
        return Usage(
            fiveHour: fh,
            sevenDay: sd,
            fiveHourReset: fhReset,
            sevenDayReset: sdReset,
            sampleAge: now.timeIntervalSince1970 - stamp / 1000,
            problem: nil
        )
    }
}

// MARK: - Refresh on click

// The HUD makes no network calls of its own. Refresh launches the claude CLI for
// one tiny Haiku turn (no tools, no MCP servers, nothing saved), and the
// aurora-billboard mod inside it writes the fresh limits to the shared file.
// That's one request toward your plan, so it only ever runs when you click.
enum Refresher {
    static var running: Process?

    static func claudePath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func run(done: @escaping (Bool) -> Void) -> Bool {
        guard running == nil, let bin = claudePath() else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["-p", "Reply with OK.", "--model", "haiku", "--tools", "",
                       "--strict-mcp-config", "--no-session-persistence"]
        p.currentDirectoryURL = FileManager.default.temporaryDirectory
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { proc in
            DispatchQueue.main.async {
                running = nil
                done(proc.terminationStatus == 0)
            }
        }
        do { try p.run() } catch { return false }
        running = p
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) { if p.isRunning { p.terminate() } }
        return true
    }
}

func duration(_ s: TimeInterval?) -> String {
    guard let s = s, s > 0 else { return "–" }
    let mins = Int(s) / 60
    let d = mins / 1440, h = (mins % 1440) / 60, m = mins % 60
    if d > 0 { return "\(d)d\(h)h" }
    if h > 0 { return String(format: "%dh%02dm", h, m) }
    return "\(m)m"
}

// MARK: - Preferences

// Theme and bar style live in the shared file, so the HUD and the band always
// match; UserDefaults is the fallback before the file exists.
enum Prefs {
    static let d = UserDefaults.standard
    static var theme: Theme {
        get {
            let name = (SharedFile.read()["theme"] as? String) ?? d.string(forKey: "theme")
            return THEMES.first { $0.name == name } ?? THEMES[0]
        }
        set {
            d.set(newValue.name, forKey: "theme")
            SharedFile.set("theme", newValue.name)
        }
    }
    static var blockBars: Bool {
        get {
            if let glyph = SharedFile.read()["glyph"] as? String { return glyph == "block" }
            return d.bool(forKey: "blockBars")
        }
        set {
            d.set(newValue, forKey: "blockBars")
            SharedFile.set("glyph", newValue ? "block" : "thin")
        }
    }
    static var collapsed: Bool {
        get { d.bool(forKey: "collapsed") }
        set { d.set(newValue, forKey: "collapsed") }
    }
}

// MARK: - The panel

let EXPANDED = NSSize(width: 312, height: 82)
let COLLAPSED = NSSize(width: 200, height: 30)

// The icon buttons, in both sizes: refresh and minimize/maximize.
enum Control { case refresh, toggle }

// Native tooltips don't show for a panel that never becomes key, so the HUD
// draws its own: a small label above the hovered button, after the usual delay.
final class Tooltip {
    private let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: true)
    private let label = NSTextField(labelWithString: "")
    private var pending: DispatchWorkItem?

    init() {
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = color("#2a2e36", 0.97).cgColor
        box.layer?.cornerRadius = 6
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        label.font = .systemFont(ofSize: 11)
        label.textColor = color("#d6d9de")
        box.addSubview(label)
        panel.contentView = box
    }

    // `anchor` is the button's rect in screen coordinates. Sits above it, or
    // below when the HUD is parked at the top of the screen.
    func show(_ text: String, at anchor: NSRect) {
        pending?.cancel()
        let work = DispatchWorkItem { [self] in
            label.stringValue = text
            label.sizeToFit()
            label.setFrameOrigin(NSPoint(x: 8, y: 4))
            let size = NSSize(width: label.frame.width + 16, height: label.frame.height + 8)
            var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + 6)
            if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) })?.visibleFrame {
                origin.x = min(max(origin.x, screen.minX + 4), screen.maxX - size.width - 4)
                if origin.y + size.height > screen.maxY { origin.y = anchor.minY - size.height - 6 }
            }
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
            panel.orderFrontRegardless()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func hide() {
        pending?.cancel()
        pending = nil
        panel.orderOut(nil)
    }
}

final class HUDView: NSView {
    var usage = Usage()
    var refreshing = false
    var refreshFailed = false
    private var dragged = false
    private var hovered: Control?
    let tooltip = Tooltip()

    private let controls: [Control] = [.refresh, .toggle]

    private func tip(_ c: Control) -> String {
        switch c {
        case .refresh: return refreshing ? "Refreshing…" : "Refresh now · uses one small request"
        case .toggle: return Prefs.collapsed ? "Expand" : "Minimize"
        }
    }

    private func showTip(_ c: Control) {
        guard let window = window else { return }
        tooltip.show(tip(c), at: window.convertToScreen(convert(rect(c), to: nil)))
    }

    // 24pt hit targets in the bottom-right corner, toggle outermost.
    private func rect(_ c: Control) -> NSRect {
        let size: CGFloat = 24
        let y = Prefs.collapsed ? (bounds.height - size) / 2 : bounds.height - size - 6
        let slot: CGFloat = c == .toggle ? 1 : 2
        return NSRect(x: bounds.width - slot * size - 6 - (slot - 1) * 2, y: y, width: size, height: size)
    }

    private func control(at p: NSPoint) -> Control? { controls.first { rect($0).contains(p) } }

    private let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private let monoBold = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func text(_ s: String, _ c: NSColor, bold: Bool = false) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: bold ? monoBold : mono, .foregroundColor: c])
    }

    override func draw(_ dirty: NSRect) {
        let th = Prefs.theme
        let card = bounds.insetBy(dx: 0.5, dy: 0.5)
        let shape = NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12)
        color("#1c1f25", 0.94).setFill()
        shape.fill()

        // The border warms up past 90% so the panel nudges you from your peripheral vision.
        let peak = max(usage.fiveHour ?? 0, usage.sevenDay ?? 0)
        (peak >= 90 ? color(th.hot, 0.7) : NSColor.white.withAlphaComponent(0.08)).setStroke()
        shape.lineWidth = 1
        shape.stroke()

        if Prefs.collapsed {
            drawCollapsed(th)
        } else {
            if let problem = usage.problem {
                text(problem, color(th.mute)).draw(at: NSPoint(x: 14, y: 25))
            } else {
                drawRow(th, y: 14, label: "5h", pct: usage.fiveHour, reset: usage.fiveHourReset)
                drawRow(th, y: 36, label: "7d", pct: usage.sevenDay, reset: usage.sevenDayReset)
            }
            drawFooter(th)
        }
        for c in controls { drawControl(c, th) }
    }

    private func drawControl(_ c: Control, _ th: Theme) {
        let r = rect(c)
        if hovered == c && !(c == .refresh && refreshing) {
            NSColor.white.withAlphaComponent(0.09).setFill()
            NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6).fill()
        }
        let name: String
        switch c {
        case .refresh: name = "arrow.clockwise"
        case .toggle: name = Prefs.collapsed ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left"
        }
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }

        // Refresh warms to the theme's warn color once the reading is stale, as a nudge.
        let tint: NSColor
        if c == .refresh && refreshing { tint = color(th.mute, 0.35) }
        else if hovered == c { tint = color(th.accent) }
        else if c == .refresh && usage.isStale { tint = color(th.warn) }
        else { tint = color(th.mute) }

        let s = symbol.size
        let tinted = NSImage(size: s, flipped: false) { box in
            symbol.draw(in: box)
            tint.set()
            box.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: NSRect(x: r.midX - s.width / 2, y: r.midY - s.height / 2, width: s.width, height: s.height),
                    from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private func drawFooter(_ th: Theme) {
        let foot: String
        if refreshing { foot = "Refreshing…" }
        else if refreshFailed { foot = "Refresh didn't finish · try again" }
        else if let age = usage.sampleAge { foot = age < 60 ? "Updated just now" : "Updated \(duration(age)) ago" }
        else { foot = "" }
        let stale = usage.isStale && !refreshing
        text(foot, stale ? color(th.warn, 0.9) : color(th.mute, 0.7)).draw(at: NSPoint(x: 14, y: 57))
    }

    private func drawCollapsed(_ th: Theme) {
        var x: CGFloat = 14
        for (label, pct) in [("5h ", usage.fiveHour), ("  7d ", usage.sevenDay)] {
            let l = text(label, color(th.mute)); l.draw(at: NSPoint(x: x, y: 7)); x += l.size().width
            let p = text(pct.map { "\(Int($0.rounded()))%" } ?? "–", spectrum(th, CGFloat((pct ?? 0) / 100)), bold: true)
            p.draw(at: NSPoint(x: x, y: 7)); x += p.size().width
        }
    }

    private func drawRow(_ th: Theme, y: CGFloat, label: String, pct: Double?, reset: TimeInterval?) {
        text(label, color(th.mute)).draw(at: NSPoint(x: 14, y: y))

        let barX: CGFloat = 40, barW: CGFloat = 150, mid = y + 8
        let fill = CGFloat(max(0, min(100, pct ?? 0)) / 100)

        if Prefs.blockBars {
            let cells = 15, gap: CGFloat = 2
            let w = (barW - gap * CGFloat(cells - 1)) / CGFloat(cells)
            let filled = Int((fill * CGFloat(cells)).rounded())
            for i in 0..<cells {
                (i < filled ? spectrum(th, (CGFloat(i) + 0.5) / CGFloat(cells)) : color(th.track)).setFill()
                NSBezierPath(roundedRect: NSRect(x: barX + CGFloat(i) * (w + gap), y: mid - 4, width: w, height: 8),
                             xRadius: 1.5, yRadius: 1.5).fill()
            }
        } else {
            let track = NSRect(x: barX, y: mid - 1.5, width: barW, height: 3)
            color(th.track).setFill()
            NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()
            if fill > 0 {
                // Gradient spans the whole track; we only reveal the filled part.
                let gradient = NSGradient(colors: [color(th.ok), color(th.warn), color(th.hot)])
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: NSRect(x: barX, y: track.minY, width: barW * fill, height: 3),
                             xRadius: 1.5, yRadius: 1.5).addClip()
                gradient?.draw(in: track, angle: 0)
                NSGraphicsContext.restoreGraphicsState()
            }
        }

        let p = text(pct.map { "\(Int($0.rounded()))%" } ?? "–", spectrum(th, fill), bold: true)
        p.draw(at: NSPoint(x: barX + barW + 10, y: y))
        text("⏰\(duration(reset))", color(th.mute)).draw(at: NSPoint(x: barX + barW + 50, y: y))
    }

    // Buttons act, a click elsewhere toggles too, drag moves.
    override func mouseDown(with e: NSEvent) { dragged = false }
    override func mouseUp(with e: NSEvent) {
        guard !dragged else { return }
        tooltip.hide()
        if control(at: convert(e.locationInWindow, from: nil)) == .refresh {
            (window as? HUDPanel)?.refreshNow()
            return
        }
        hovered = nil
        Prefs.collapsed.toggle()
        (window as? HUDPanel)?.applySize()
    }

    // Hover highlights a button. activeAlways, since the panel never becomes key.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with e: NSEvent) {
        let now = control(at: convert(e.locationInWindow, from: nil))
        guard now != hovered else { return }
        hovered = now
        needsDisplay = true
        if let c = now { showTip(c) } else { tooltip.hide() }
    }

    override func mouseExited(with e: NSEvent) {
        tooltip.hide()
        if hovered != nil { hovered = nil; needsDisplay = true }
    }

    override func mouseDragged(with e: NSEvent) { tooltip.hide(); dragged = true; window?.performDrag(with: e) }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let refresh = NSMenuItem(title: refreshing ? "Refreshing…" : "Refresh now",
                                 action: refreshing ? nil : #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(.separator())

        let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for th in THEMES {
            let item = NSMenuItem(title: th.label, action: #selector(pickTheme(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = th.name
            item.state = th.name == Prefs.theme.name ? .on : .off
            sub.addItem(item)
        }
        themeItem.submenu = sub
        menu.addItem(themeItem)

        let bars = NSMenuItem(title: "Block bars", action: #selector(toggleBars), keyEquivalent: "")
        bars.target = self
        bars.state = Prefs.blockBars ? .on : .off
        menu.addItem(bars)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Aurora HUD", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    @objc private func pickTheme(_ sender: NSMenuItem) {
        if let name = sender.representedObject as? String, let th = THEMES.first(where: { $0.name == name }) {
            Prefs.theme = th
            needsDisplay = true
        }
    }

    @objc private func refreshNow() { (window as? HUDPanel)?.refreshNow() }

    @objc private func toggleBars() {
        Prefs.blockBars.toggle()
        needsDisplay = true
    }
}

final class HUDPanel: NSPanel {
    let hud = HUDView()

    init() {
        let size = Prefs.collapsed ? COLLAPSED : EXPANDED
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: screen.maxX - size.width - 24, y: screen.minY + 24)
        super.init(contentRect: NSRect(origin: origin, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        contentView = hud
        setFrameAutosaveName("AuroraHUD") // remembers where you parked it
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var canBecomeKey: Bool { false }

    func applySize() {
        let size = Prefs.collapsed ? COLLAPSED : EXPANDED
        // Keep the top-right corner pinned so it grows down and left.
        let f = frame
        setFrame(NSRect(x: f.maxX - size.width, y: f.maxY - size.height, width: size.width, height: size.height),
                 display: true, animate: true)
        hud.needsDisplay = true
    }

    func refresh() {
        hud.usage = UsageReader.read()
        hud.needsDisplay = true
    }

    func refreshNow() {
        guard !hud.refreshing else { return }
        hud.refreshing = true
        hud.refreshFailed = false
        hud.needsDisplay = true
        let started = Refresher.run { ok in
            self.hud.refreshing = false
            self.hud.refreshFailed = !ok
            self.refresh()
        }
        if !started {
            hud.refreshing = false
            hud.refreshFailed = true
            hud.needsDisplay = true
        }
    }
}

// MARK: - App

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon
let panel = HUDPanel()
panel.refresh()

// The panel shows only while the Claude desktop app is running. macOS posts
// launch and quit notifications, so there's no polling; while hidden the HUD
// just sits idle.
let CLAUDE_APP = "com.anthropic.claudefordesktop"

func followClaude() {
    let running = !NSRunningApplication.runningApplications(withBundleIdentifier: CLAUDE_APP).isEmpty
    if running {
        panel.refresh()
        panel.orderFrontRegardless()
    } else {
        panel.hud.tooltip.hide()
        panel.orderOut(nil)
    }
}

for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
    NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { note in
        let changed = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if changed?.bundleIdentifier == CLAUDE_APP { followClaude() }
    }
}
followClaude()

// The mod writes after every Claude Code response; checking every 30s keeps
// countdowns and the "Updated" age fresh.
let timer = Timer(timeInterval: 30, repeats: true) { _ in panel.refresh() }
RunLoop.main.add(timer, forMode: .common)

app.run()
