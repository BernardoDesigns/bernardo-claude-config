// Aurora HUD: a floating usage panel for the Claude desktop app.
//
// What it does: reads ~/Library/Application Support/Claude/plan-usage-history.json
// (a file the Claude desktop app writes itself, about every 5 minutes) and draws
// your 5-hour and weekly plan usage in an always-on-top panel.
//
// What it never does: no network calls, no Keychain or login token, no auto-update,
// no third-party code. Everything below is AppKit and Foundation from Apple.
//
// Build:  swiftc -O main.swift -o AuroraHUD      (needs Xcode Command Line Tools)
// Use:    click to collapse/expand, drag to move, right-click for themes and Quit.

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

// MARK: - Reading the desktop app's usage file

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
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
    static let fiveHours: TimeInterval = 5 * 3600
    static let sevenDays: TimeInterval = 7 * 24 * 3600
    static let resetDrop = 15.0 // a fall of 15+ points between samples means the window reset

    static func num(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }

    static func read(now: Date = Date()) -> Usage {
        guard let data = try? Data(contentsOf: url) else {
            return Usage(problem: "Open the Claude desktop app to start tracking")
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let all = root["samples"] as? [[String: Any]], let last = all.last else {
            return Usage(problem: "Usage file has an unexpected format")
        }
        // Only the current organization's samples, in case you switch accounts.
        let org = last["org"] as? String
        let samples = all.filter { ($0["org"] as? String) == org }

        func value(_ s: [String: Any], _ key: String) -> Double? { num((s["u"] as? [String: Any])?[key]) }
        func stamp(_ s: [String: Any]) -> Double? { num(s["t"]) }

        func countdown(_ key: String, _ window: TimeInterval) -> TimeInterval? {
            var lastReset: Double?
            if samples.count > 1 {
                for i in 1..<samples.count {
                    if let a = value(samples[i - 1], key), let b = value(samples[i], key), a - b >= resetDrop {
                        lastReset = stamp(samples[i])
                    }
                }
            }
            guard let ms = lastReset else { return nil }
            var left = ms / 1000 + window - now.timeIntervalSince1970
            while left < 0 { left += window }
            return left
        }

        let newest = samples.last ?? last
        return Usage(
            fiveHour: value(newest, "fh"),
            sevenDay: value(newest, "sd"),
            fiveHourReset: countdown("fh", fiveHours),
            sevenDayReset: countdown("sd", sevenDays),
            sampleAge: stamp(newest).map { now.timeIntervalSince1970 - $0 / 1000 },
            problem: nil
        )
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

enum Prefs {
    static let d = UserDefaults.standard
    static var theme: Theme {
        get { THEMES.first { $0.name == d.string(forKey: "theme") } ?? THEMES[0] }
        set { d.set(newValue.name, forKey: "theme") }
    }
    static var blockBars: Bool {
        get { d.bool(forKey: "blockBars") }
        set { d.set(newValue, forKey: "blockBars") }
    }
    static var collapsed: Bool {
        get { d.bool(forKey: "collapsed") }
        set { d.set(newValue, forKey: "collapsed") }
    }
}

// MARK: - The panel

let EXPANDED = NSSize(width: 312, height: 76)
let COLLAPSED = NSSize(width: 168, height: 30)

final class HUDView: NSView {
    var usage = Usage()
    private var dragged = false

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

        if let problem = usage.problem {
            text(problem, color(th.mute)).draw(at: NSPoint(x: 14, y: Prefs.collapsed ? 7 : 29))
            return
        }
        Prefs.collapsed ? drawCollapsed(th) : drawExpanded(th)
    }

    private func drawCollapsed(_ th: Theme) {
        var x: CGFloat = 14
        for (label, pct) in [("5h ", usage.fiveHour), ("  7d ", usage.sevenDay)] {
            let l = text(label, color(th.mute)); l.draw(at: NSPoint(x: x, y: 7)); x += l.size().width
            let p = text(pct.map { "\(Int($0.rounded()))%" } ?? "–", spectrum(th, CGFloat((pct ?? 0) / 100)), bold: true)
            p.draw(at: NSPoint(x: x, y: 7)); x += p.size().width
        }
    }

    private func drawExpanded(_ th: Theme) {
        drawRow(th, y: 14, label: "5h", pct: usage.fiveHour, reset: usage.fiveHourReset)
        drawRow(th, y: 36, label: "7d", pct: usage.sevenDay, reset: usage.sevenDayReset)
        let foot = usage.isStale ? "Last reading \(duration(usage.sampleAge)) ago" : "Plan usage · Claude desktop"
        text(foot, color(th.mute, 0.7)).draw(at: NSPoint(x: 14, y: 57))
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

    // Click toggles, drag moves.
    override func mouseDown(with e: NSEvent) { dragged = false }
    override func mouseDragged(with e: NSEvent) { dragged = true; window?.performDrag(with: e) }
    override func mouseUp(with e: NSEvent) {
        guard !dragged else { return }
        Prefs.collapsed.toggle()
        (window as? HUDPanel)?.applySize()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
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
}

// MARK: - App

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon
let panel = HUDPanel()
panel.refresh()
panel.orderFrontRegardless()

// The desktop app samples every ~5 minutes; checking every 30s keeps countdowns fresh.
let timer = Timer(timeInterval: 30, repeats: true) { _ in panel.refresh() }
RunLoop.main.add(timer, forMode: .common)

app.run()
