import AppKit
import Carbon
import CoreServices
import ServiceManagement
import Darwin
import QuartzCore

func textShadow() -> NSShadow {
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.9)
    shadow.shadowBlurRadius = 3
    shadow.shadowOffset = NSSize(width: 0, height: -1)
    return shadow
}

let userHome = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()

struct AppEntry {
    let url: URL
    let name: String
    let names: [String]
    let local: Bool
    let icon: NSImage
    let searchNames: [SearchName]
    var duplicate = false
    init(url: URL, name: String, names: [String], local: Bool, icon: NSImage) {
        self.url = url; self.name = name; self.names = names; self.local = local; self.icon = icon
        self.searchNames = names.map(SearchName.init)
    }
}

struct SearchName {
    let name: String
    let words: [String]
    let initials: String
    let compact: String
    init(_ value: String) {
        name = normalized(value)
        words = value.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.map(normalized)
        initials = words.map { String($0.prefix(1)) }.joined()
        compact = words.joined()
    }
}

func normalized(_ s: String) -> String {
    s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
}
func words(_ s: String) -> [String] {
    normalized(s).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
}
func score(_ entry: AppEntry, _ query: String) -> Int? {
    let q = normalized(query).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return nil }
    var best: Int?
    for name in entry.searchNames {
        let n = name.name, w = name.words
        let value: Int?
        if n == q { value = 0 }
        else if n.hasPrefix(q) { value = 1 }
        else if w.contains(where: { $0.hasPrefix(q) }) { value = 2 }
        else if name.initials.hasPrefix(q) { value = 3 }
        else { value = nil }
        if let value { best = min(best ?? value, value) }
    }
    return best
}
func results(_ entries: [AppEntry], _ query: String) -> [AppEntry] {
    let q = normalized(query).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return [] }
    var matches = entries.compactMap { e -> (AppEntry, Int)? in score(e, q).map { (e, $0) } }
    if matches.isEmpty {
        let compact = words(q).joined()
        if !compact.isEmpty { matches = entries.compactMap { e in e.searchNames.contains(where: { $0.compact.contains(compact) }) ? (e, 4) : nil } }
    }
    return Array(matches.sorted { a, b in
        if a.1 != b.1 { return a.1 < b.1 }
        let order = a.0.name.localizedStandardCompare(b.0.name)
        if order != .orderedSame { return order == .orderedAscending }
        if a.0.local != b.0.local { return a.0.local }
        return a.0.url.path < b.0.url.path
    }.prefix(5).map(\.0))
}

final class Index {
    private(set) var entries: [AppEntry] = []
    private let roots: [String]
    private var stream: FSEventStreamRef?
    private var generation = 0
    var changed: (() -> Void)?
    init(roots: [String] = ["/Applications", userHome + "/Applications", "/System/Applications"]) {
        self.roots = roots.map { URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath().path }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let watchPaths = Set(self.roots.map { root -> String in
            var path = root
            while !FileManager.default.fileExists(atPath: path) && path != "/" { path = (path as NSString).deletingLastPathComponent }
            return path
        })
        let paths = Array(watchPaths) as CFArray
        stream = FSEventStreamCreate(nil, { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let index = Unmanaged<Index>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            if paths.contains(where: { path in index.roots.contains { path == $0 || path.hasPrefix($0 + "/") || $0.hasPrefix(path + "/") } }) { index.rebuild() }
        }, &context, paths, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.1, FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagFileEvents))
        if let stream { FSEventStreamSetDispatchQueue(stream, DispatchQueue.main); FSEventStreamStart(stream) }
        rebuild()
    }
    deinit { if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) } }
    func rebuild() {
        generation += 1
        let revision = generation, roots = self.roots
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var found: [AppEntry] = []
            for root in roots {
                var directories = [URL(fileURLWithPath: root)]
                while let directory = directories.popLast() {
                    guard let children = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { continue }
                    for url in children {
                        if url.pathExtension.lowercased() != "app" {
                            if let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]), values.isDirectory == true, values.isSymbolicLink != true { directories.append(url) }
                            continue
                        }
                        guard let bundle = Bundle(url: url), bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL", let executable = bundle.executableURL, FileManager.default.fileExists(atPath: executable.path) else { continue }
                        let display = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "", options: [.anchored, .backwards, .caseInsensitive])
                        let names = [display, bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String, bundle.localizedInfoDictionary?["CFBundleName"] as? String, bundle.infoDictionary?["CFBundleDisplayName"] as? String, bundle.infoDictionary?["CFBundleName"] as? String, url.deletingPathExtension().lastPathComponent].compactMap { $0 }.filter { !$0.isEmpty }
                        found.append(AppEntry(url: url, name: display, names: names, local: root == userHome + "/Applications", icon: NSWorkspace.shared.icon(forFile: url.path)))
                    }
                }
            }
            let counts = Dictionary(grouping: found, by: { normalized($0.name) }).mapValues(\.count)
            for i in found.indices { found[i].duplicate = (counts[normalized(found[i].name)] ?? 0) > 1 }
            DispatchQueue.main.async { guard let self, revision == self.generation else { return }; self.entries = found; self.changed?() }
        }
    }
}

private let launcherCornerRadius: CGFloat = 35

func menuBarRocketImage() -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
        let rocket = NSBezierPath()
        rocket.move(to: NSPoint(x: 9, y: 17))
        rocket.curve(to: NSPoint(x: 5, y: 7), controlPoint1: NSPoint(x: 6, y: 15), controlPoint2: NSPoint(x: 5, y: 11))
        rocket.line(to: NSPoint(x: 2, y: 5)); rocket.line(to: NSPoint(x: 2, y: 2.5)); rocket.line(to: NSPoint(x: 5.5, y: 4))
        rocket.line(to: NSPoint(x: 6.5, y: 2.5)); rocket.line(to: NSPoint(x: 11.5, y: 2.5)); rocket.line(to: NSPoint(x: 12.5, y: 4))
        rocket.line(to: NSPoint(x: 16, y: 2.5)); rocket.line(to: NSPoint(x: 16, y: 5)); rocket.line(to: NSPoint(x: 13, y: 7))
        rocket.curve(to: NSPoint(x: 9, y: 17), controlPoint1: NSPoint(x: 13, y: 11), controlPoint2: NSPoint(x: 12, y: 15))
        rocket.close()
        rocket.appendOval(in: NSRect(x: 7.5, y: 9, width: 3, height: 3))
        rocket.windingRule = .evenOdd
        NSColor.black.setFill(); rocket.fill()
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Rocket Up"
    return image
}

func resultHighlightPath(in bounds: CGRect, bottomRadius: CGFloat) -> CGPath {
    let topRadius: CGFloat = 12
    let x = bounds.minX, y = bounds.minY, right = bounds.maxX, top = bounds.maxY
    let path = CGMutablePath()
    path.move(to: CGPoint(x: x, y: y + bottomRadius))
    path.addLine(to: CGPoint(x: x, y: top - topRadius))
    path.addArc(tangent1End: CGPoint(x: x, y: top), tangent2End: CGPoint(x: x + topRadius, y: top), radius: topRadius)
    path.addLine(to: CGPoint(x: right - topRadius, y: top))
    path.addArc(tangent1End: CGPoint(x: right, y: top), tangent2End: CGPoint(x: right, y: top - topRadius), radius: topRadius)
    path.addLine(to: CGPoint(x: right, y: y + bottomRadius))
    path.addArc(tangent1End: CGPoint(x: right, y: y), tangent2End: CGPoint(x: right - bottomRadius, y: y), radius: bottomRadius)
    path.addLine(to: CGPoint(x: x + bottomRadius, y: y))
    path.addArc(tangent1End: CGPoint(x: x, y: y), tangent2End: CGPoint(x: x, y: y + bottomRadius), radius: bottomRadius)
    path.closeSubpath()
    return path
}

final class Highlights: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: launcherCornerRadius - 0.5, yRadius: launcherCornerRadius - 0.5)
        NSColor.white.withAlphaComponent(0.17).setStroke(); path.lineWidth = 1; path.stroke()
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSGradient(starting: NSColor.white.withAlphaComponent(0.14), ending: .clear)?.draw(in: NSRect(x: 12, y: bounds.height - 3, width: bounds.width - 24, height: 3), angle: 90)
        NSGraphicsContext.restoreGraphicsState()
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
final class ShadowImageView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        textShadow().set()
        NSColor.white.withAlphaComponent(0.7).setStroke()
        let circle = NSBezierPath(ovalIn: NSRect(x: 4, y: 10, width: 16, height: 16))
        circle.lineWidth = 2.5; circle.stroke()
        let handle = NSBezierPath(); handle.lineWidth = 2.5; handle.lineCapStyle = .round
        handle.move(to: NSPoint(x: 18, y: 12)); handle.line(to: NSPoint(x: 26, y: 4)); handle.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}
final class ShadowLayoutManager: NSLayoutManager {
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        NSGraphicsContext.saveGraphicsState()
        textShadow().set()
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        NSGraphicsContext.restoreGraphicsState()
    }
}
final class SearchField: NSTextField {
    var command: ((Selector) -> Bool)?
    override func doCommand(by selector: Selector) { if command?(selector) != true { super.doCommand(by: selector) } }
}
final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
final class Controller: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate {
    var index: Index!
    var panel: Panel!
    let field = SearchField(frame: .zero)
    let fieldEditor: NSTextView = {
        let storage = NSTextStorage()
        let layout = ShadowLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layout); layout.addTextContainer(container)
        let editor = NSTextView(frame: .zero, textContainer: container)
        editor.isFieldEditor = true
        return editor
    }()
    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        (client as AnyObject?) === field ? fieldEditor : nil
    }
    let list = NSView()
    var matches: [AppEntry] = []
    var selection = 0
    var hotKey: EventHotKeyRef?
    var handler: EventHandlerRef?
    var settings: NSWindow?
    var statusItem: NSStatusItem?
    var showLauncherItem: NSMenuItem?
    var shortcut = Shortcut.load(from: .standard)
    var monitor: Any?
    var hiding = false
    let width: CGFloat = 640, header: CGFloat = 70, row: CGFloat = 54
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        startIndex()
        createPanel()
        updateMenuBarIcon()
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, user in
            guard let user else { return noErr }
            DispatchQueue.main.async { Unmanaged<Controller>.fromOpaque(user).takeUnretainedValue().toggle() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        if !register(shortcut) {
            let alert = NSAlert(); alert.messageText = "Shortcut unavailable"; alert.informativeText = "The saved shortcut is in use. Choose another in Rocket Up settings."; alert.runModal()
            openSettings()
        }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in DispatchQueue.main.async { self?.hide() } }
    }
    func startIndex() {
        index = Index()
        index.changed = { [weak self] in self?.refresh() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { if !flag { show() }; return false }
    var menuBarIconVisible: Bool { UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true }
    func setMenuBarIconVisible(_ visible: Bool) {
        UserDefaults.standard.set(visible, forKey: "showMenuBarIcon")
        updateMenuBarIcon()
    }
    func updateMenuBarIcon() {
        guard menuBarIconVisible else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil; showLauncherItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = menuBarRocketImage()
        let menu = NSMenu(); menu.autoenablesItems = false
        let show = NSMenuItem(title: "Show Launcher", action: #selector(showLauncher(_:)), keyEquivalent: shortcut.keyEquivalent)
        show.keyEquivalentModifierMask = shortcut.modifiers; show.target = self; menu.addItem(show)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self; menu.addItem(settingsItem)
        item.menu = menu; statusItem = item; showLauncherItem = show
    }
    @objc func showLauncher(_ sender: Any?) { show() }
    @discardableResult func register(_ shortcut: Shortcut) -> Bool {
        var newKey: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers, EventHotKeyID(signature: 0x524f434b, id: 1), GetApplicationEventTarget(), 0, &newKey)
        guard status == noErr else { return false }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = newKey; self.shortcut = shortcut; shortcut.save(to: .standard)
        showLauncherItem?.keyEquivalent = shortcut.keyEquivalent
        showLauncherItem?.keyEquivalentModifierMask = shortcut.modifiers
        return true
    }
    func createPanel() {
        panel = Panel(contentRect: NSRect(x: 0, y: 0, width: width, height: header), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.delegate = self; panel.isReleasedWhenClosed = false
        let glass = NSGlassEffectView(frame: panel.contentView!.bounds); glass.autoresizingMask = [.width, .height]; glass.appearance = NSAppearance(named: .darkAqua); glass.style = .clear; glass.cornerRadius = launcherCornerRadius
        let content = NSView(frame: glass.bounds); content.autoresizingMask = [.width, .height]; glass.contentView = content
        panel.contentView!.addSubview(glass)
        let highlights = Highlights(frame: panel.contentView!.bounds); highlights.autoresizingMask = [.width, .height]; panel.contentView!.addSubview(highlights)
        let searchIcon = ShadowImageView(frame: NSRect(x: 25, y: 20, width: 30, height: 30)); searchIcon.autoresizingMask = [.minYMargin]; content.addSubview(searchIcon)
        field.frame = NSRect(x: 74, y: 13, width: width - 94, height: 36); field.autoresizingMask = [.minYMargin, .width]; field.font = .systemFont(ofSize: 24); field.placeholderAttributedString = NSAttributedString(string: "RocketUp Search", attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.7), .font: NSFont.systemFont(ofSize: 24), .shadow: textShadow()]); field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none; field.delegate = self
        field.command = { [weak self] selector in self?.command(selector) ?? false }; content.addSubview(field)
        list.frame = NSRect(x: 10, y: 10, width: width - 20, height: 0); list.autoresizingMask = [.width, .minYMargin]; content.addSubview(list)
    }
    func toggle() { if panel.isVisible && !hiding { hide() } else { show() } }
    func show() {
        hiding = false
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - width / 2, y: frame.maxY - frame.height * 0.22 - panel.frame.height))
        panel.alphaValue = 0; panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); panel.makeFirstResponder(field)
        if let editor = field.currentEditor() as? NSTextView {
            editor.allowsUndo = true
            var attributes = editor.typingAttributes
            attributes[.shadow] = textShadow()
            editor.typingAttributes = attributes
            editor.textStorage?.addAttribute(.shadow, value: textShadow(), range: NSRange(location: 0, length: editor.textStorage?.length ?? 0))
        }
        field.currentEditor()?.selectAll(nil)
        NSAnimationContext.runAnimationGroup { c in c.duration = 0.05; panel.animator().alphaValue = 1 }
    }
    func hide() {
        guard panel.isVisible, !hiding else { return }
        hiding = true
        NSAnimationContext.runAnimationGroup({ c in c.duration = 0.05; panel.animator().alphaValue = 0 }, completionHandler: { [weak self] in guard let self, self.hiding else { return }; self.panel.orderOut(nil); self.hiding = false })
    }
    func windowDidResignKey(_ notification: Notification) { if notification.object as? NSWindow === panel { hide() } }
    func controlTextDidChange(_ obj: Notification) { selection = 0; refresh() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        command(commandSelector)
    }
    func refresh() {
        matches = results(index.entries, field.stringValue); selection = min(selection, max(0, matches.count - 1)); render()
    }
    func render() {
        list.subviews.forEach { $0.removeFromSuperview() }
        let height = header + CGFloat(matches.count) * row
        var frame = panel.frame; frame.origin.y += frame.height - height; frame.size.height = height
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.2
            c.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
        let listHeight = CGFloat(matches.count) * row
        list.frame = NSRect(x: 10, y: panel.contentView!.bounds.height - header - listHeight + 10, width: width - 20, height: listHeight)
        for (i, app) in matches.enumerated() {
            let item = NSButton(frame: NSRect(x: 0, y: CGFloat(matches.count - i - 1) * row, width: width - 20, height: row))
            item.isBordered = false; item.title = ""; item.target = self; item.action = #selector(clicked(_:)); item.tag = i; item.wantsLayer = true; item.layer?.cornerRadius = 12; item.layer?.backgroundColor = (i == selection ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.35) : .clear).cgColor
            if i == matches.count - 1 {
                let mask = CAShapeLayer()
                var flip = CGAffineTransform(translationX: 0, y: item.bounds.height).scaledBy(x: 1, y: -1)
                mask.path = resultHighlightPath(in: item.bounds, bottomRadius: launcherCornerRadius - 10).copy(using: &flip)
                item.layer?.mask = mask
            }
            let icon = NSImageView(frame: NSRect(x: 7, y: 4, width: 46, height: 46)); icon.imageScaling = .scaleProportionallyUpOrDown; icon.image = app.icon; item.addSubview(icon)
            let label = NSTextField(labelWithString: app.name); label.font = .systemFont(ofSize: 18, weight: .medium); label.textColor = .white; label.attributedStringValue = NSAttributedString(string: app.name, attributes: [.font: label.font!, .foregroundColor: NSColor.white, .shadow: textShadow()]); label.frame = NSRect(x: 64, y: app.duplicate ? 25 : 16, width: width - 120, height: 24); item.addSubview(label)
            if app.duplicate { let path = NSTextField(labelWithString: app.url.deletingLastPathComponent().path); path.font = .systemFont(ofSize: 11); path.textColor = NSColor.white.withAlphaComponent(0.8); path.attributedStringValue = NSAttributedString(string: path.stringValue, attributes: [.font: path.font!, .foregroundColor: NSColor.white.withAlphaComponent(0.8), .shadow: textShadow()]); path.frame = NSRect(x: 64, y: 7, width: width - 120, height: 16); item.addSubview(path) }
            list.addSubview(item)
        }
    }
    func command(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)):
            if field.stringValue.isEmpty { hide() } else { field.stringValue = ""; selection = 0; refresh() }; return true
        case #selector(NSResponder.moveDown(_:)): if !matches.isEmpty { selection = (selection + 1) % matches.count; render() }; return true
        case #selector(NSResponder.moveUp(_:)): if !matches.isEmpty { selection = (selection + matches.count - 1) % matches.count; render() }; return true
        case #selector(NSResponder.insertNewline(_:)): launch(selection); return true
        default: return false
        }
    }
    @objc func clicked(_ sender: NSButton) { launch(sender.tag) }
    func launch(_ i: Int) { guard matches.indices.contains(i) else { return }; let url = matches[i].url; field.stringValue = ""; refresh(); hide(); NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) }
    @objc func openSettings() { hide(); if settings == nil { settings = SettingsWindow(controller: self) }; settings?.center(); settings?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
}
final class ShortcutRecorder: NSButton {
    var onRecord: ((NSEvent) -> Void)?
    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { if window?.makeFirstResponder(self) == true { onBegin?(); title = "Type shortcut…" } }
    override func keyDown(with event: NSEvent) { onRecord?(event) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { if window?.firstResponder === self { onRecord?(event); return true }; return super.performKeyEquivalent(with: event) }
    override func resignFirstResponder() -> Bool { onEnd?(); return super.resignFirstResponder() }
}
final class SettingsWindow: NSWindow {
    private let defaultButton = NSButton(title: "Use Default", target: nil, action: nil)
    private weak var recorder: ShortcutRecorder?
    init(controller: Controller) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 460, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = "Rocket Up Settings"; isReleasedWhenClosed = false
        let label = NSTextField(labelWithString: "Keyboard shortcut:"); label.frame = NSRect(x: 24, y: 143, width: 146, height: 22); contentView?.addSubview(label)
        let recorder = ShortcutRecorder(frame: NSRect(x: 172, y: 138, width: 150, height: 32)); recorder.title = controller.shortcut.displayString; recorder.bezelStyle = .rounded; contentView?.addSubview(recorder)
        self.recorder = recorder
        defaultButton.frame = NSRect(x: 328, y: 138, width: 112, height: 32); defaultButton.bezelStyle = .rounded; defaultButton.target = self; defaultButton.action = #selector(useDefault); defaultButton.isEnabled = controller.shortcut != .default; contentView?.addSubview(defaultButton)
        recorder.onBegin = { [weak controller] in if let key = controller?.hotKey { UnregisterEventHotKey(key); controller?.hotKey = nil } }
        recorder.onEnd = { [weak controller, weak recorder] in
            guard let controller else { return }
            if controller.hotKey == nil { _ = controller.register(controller.shortcut) }
            recorder?.title = controller.shortcut.displayString
            (recorder?.window as? SettingsWindow)?.defaultButton.isEnabled = controller.shortcut != .default
        }
        recorder.onRecord = { [weak recorder, weak controller] event in
            guard let recorder, let controller else { return }
            if event.keyCode == UInt16(kVK_Escape) { recorder.window?.makeFirstResponder(nil); return }
            guard let candidate = Shortcut(keyCode: event.keyCode, modifiers: event.modifierFlags) else { NSSound.beep(); return }
            if controller.register(candidate) { recorder.window?.makeFirstResponder(nil) } else { NSSound.beep(); recorder.title = "Unavailable" }
        }
        let login = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil); login.frame = NSRect(x: 24, y: 93, width: 250, height: 24); login.state = SMAppService.mainApp.status == .enabled ? .on : .off; login.target = self; login.action = #selector(toggleLogin(_:)); contentView?.addSubview(login)
        let icon = NSButton(checkboxWithTitle: "Show menu bar icon", target: self, action: #selector(toggleMenuBarIcon(_:))); icon.frame = NSRect(x: 24, y: 53, width: 250, height: 24); icon.state = controller.menuBarIconVisible ? .on : .off; contentView?.addSubview(icon)
        self.controller = controller
    }
    weak var controller: Controller?
    @objc func toggleMenuBarIcon(_ sender: NSButton) { controller?.setMenuBarIconVisible(sender.state == .on) }
    @objc func useDefault() {
        guard let controller else { return }
        if controller.shortcut == .default || controller.register(.default) {
            recorder?.title = controller.shortcut.displayString; defaultButton.isEnabled = false
        } else { NSSound.beep() }
    }
    @objc func toggleLogin(_ sender: NSButton) { do { if sender.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { sender.state = SMAppService.mainApp.status == .enabled ? .on : .off; NSAlert(error: error).runModal() } }
}
func makeMainMenu(controller: Controller) -> NSMenu {
let menu = NSMenu(); let appItem = NSMenuItem(); menu.addItem(appItem); let appMenu = NSMenu(); appMenu.addItem(withTitle: "Settings…", action: #selector(Controller.openSettings), keyEquivalent: ",").target = controller; appItem.submenu = appMenu
let editItem = NSMenuItem(); menu.addItem(editItem)
let editMenu = NSMenu(title: "Edit"); editItem.submenu = editMenu
editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"); redo.keyEquivalentModifierMask = [.command, .shift]
editMenu.addItem(.separator())
editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
return menu
}
let app = NSApplication.shared
let controller = Controller()
app.delegate = controller
app.mainMenu = makeMainMenu(controller: controller)
app.run()
