import AppKit
import Foundation
import Carbon

func wait(_ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
        if condition() { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    return condition()
}
func fixture(_ root: URL, _ name: String, type: String = "APPL") throws {
    let contents = root.appendingPathComponent("\(name).app/Contents")
    let macos = contents.appendingPathComponent("MacOS")
    try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
    let plist: [String: Any] = ["CFBundleName": name, "CFBundleIdentifier": "test.\(name)", "CFBundlePackageType": type, "CFBundleExecutable": "run"]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
    let executable = macos.appendingPathComponent("run")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
try fixture(root, "Google Chrome")
try fixture(root, "Not an App", type: "XPC!")
let index = Index(roots: [root.path])
precondition(wait { index.entries.count == 1 }, "Initial app discovery failed: \(index.entries.map(\.name))")
precondition(index.entries[0].name == "Google Chrome")
try fixture(root, "Notes")
precondition(wait { index.entries.count == 2 }, "New app not observed")
try FileManager.default.removeItem(at: root.appendingPathComponent("Notes.app"))
precondition(wait { index.entries.count == 1 }, "Removed app not observed")
let nestedRoot = root.appendingPathComponent("NestedTest")
try FileManager.default.createDirectory(at: nestedRoot, withIntermediateDirectories: true)
try fixture(nestedRoot, "First")
try FileManager.default.createSymbolicLink(at: nestedRoot.appendingPathComponent("Alias.app"), withDestinationURL: nestedRoot.appendingPathComponent("First.app"))
try fixture(nestedRoot.appendingPathComponent("Suite"), "Nested")
let nestedIndex = Index(roots: [nestedRoot.path])
precondition(wait { nestedIndex.entries.contains { $0.name == "Nested" } }, "An app nested in a regular folder was skipped")
let missingRoot = root.appendingPathComponent("Applications")
let missingIndex = Index(roots: [missingRoot.path])
try fixture(missingRoot, "Later")
precondition(wait { missingIndex.entries.contains { $0.name == "Later" } }, "Creation of a missing Applications folder not observed")
let installed = Index()
precondition(wait { !installed.entries.isEmpty }, "No installed apps discovered in the sandbox")
precondition(installed.entries.contains { $0.name == "Safari" }, "Safari not discovered in the sandbox")
if let expected = ProcessInfo.processInfo.environment["ROCKETUP_EXPECT_USER_APP"] {
    precondition(installed.entries.contains { $0.name == expected && $0.local }, "User Applications app not discovered without a bookmark")
}
if ProcessInfo.processInfo.environment["ROCKETUP_CHECK_KICAD"] != nil {
    precondition(installed.entries.contains { $0.url.path == "/Applications/KiCad/KiCad.app" }, "Installed KiCad was not discovered")
}
if ProcessInfo.processInfo.environment["ROCKETUP_CHECK_LAUNCH"] != nil,
   let calculator = installed.entries.first(where: { $0.url.lastPathComponent == "Calculator.app" }) {
    let wasRunning = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.calculator").contains { !$0.isTerminated }
    var completed = false
    var launchError: Error?
    var launched: NSRunningApplication?
    NSWorkspace.shared.openApplication(at: calculator.url, configuration: NSWorkspace.OpenConfiguration()) { app, error in
        DispatchQueue.main.async { launched = app; launchError = error; completed = true }
    }
    precondition(wait { completed }, "Launch did not complete")
    precondition(launchError == nil && launched != nil, "Sandboxed launch failed: \(String(describing: launchError))")
    if !wasRunning { launched?.terminate() }
    print("Sandboxed application launch passed")
}
var maxSearch: Double = 0
for query in ["s", "ch", "gc", "notes", "visualstudio"] {
    for _ in 0..<100 {
        let start = ProcessInfo.processInfo.systemUptime
        _ = results(installed.entries, query)
        maxSearch = max(maxSearch, (ProcessInfo.processInfo.systemUptime - start) * 1000)
    }
}
print("Search computation worst observed: \(String(format: "%.2f", maxSearch)) ms across \(installed.entries.count) apps")
let controller = Controller()
controller.startIndex()
controller.createPanel()
app.mainMenu = makeMainMenu(controller: controller)
let testShortcut = Shortcut(keyCode: UInt16(kVK_F19), modifiers: [.control, .option, .shift])!
precondition(controller.register(testShortcut), "Could not register global test shortcut")
let nextShortcut = Shortcut(keyCode: UInt16(kVK_F18), modifiers: [.control, .option, .shift])!
precondition(controller.register(nextShortcut), "Could not remap global test shortcut")
if let key = controller.hotKey { UnregisterEventHotKey(key); controller.hotKey = nil }
controller.field.stringValue = "test"
precondition(controller.command(#selector(NSResponder.cancelOperation(_:))))
precondition(controller.field.stringValue.isEmpty)
controller.show()
precondition(controller.panel.isVisible)
controller.field.stringValue = "sample"
controller.panel.makeFirstResponder(controller.field)
guard let editor = controller.field.currentEditor() as? NSTextView else { fatalError("Search editor unavailable") }
editor.setSelectedRange(NSRange(location: 0, length: 0))
let selectAll = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: controller.panel.windowNumber, context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: UInt16(kVK_ANSI_A))!
precondition(app.mainMenu!.performKeyEquivalent(with: selectAll), "Command-A was not handled")
precondition(editor.selectedRange() == NSRange(location: 0, length: 6), "Command-A did not select the search text")
precondition(wait { !controller.index.entries.isEmpty })
controller.field.stringValue = "s"
controller.refresh()
precondition(!controller.matches.isEmpty && controller.matches.count <= 5)
precondition(abs(controller.list.frame.maxY - (controller.panel.contentView!.bounds.height - controller.header + 10)) < 1, "Results must stay below the search field while the panel expands")
RunLoop.current.run(until: Date().addingTimeInterval(0.3))
precondition(abs(controller.list.frame.maxY - (controller.panel.contentView!.bounds.height - controller.header + 10)) < 1, "Results must remain anchored below the search field after resizing")
precondition(abs(controller.list.frame.minY - controller.list.frame.minX) < 1, "Bottom and side margins must match")
if let snapshot = ProcessInfo.processInfo.environment["ROCKETUP_SNAPSHOT"] {
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    let view = controller.panel.contentView!
    if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let path = snapshot == "auto" ? NSTemporaryDirectory() + "rocketup-preview.png" : snapshot
        if let data = bitmap.representation(using: .png, properties: [:]) { try data.write(to: URL(fileURLWithPath: path)); print("Preview: \(path)") }
    }
}
let first = controller.matches.first!.url
_ = controller.command(#selector(NSResponder.moveDown(_:)))
if controller.matches.count > 1 { precondition(controller.selection == 1) }
_ = controller.command(#selector(NSResponder.moveUp(_:)))
precondition(controller.selection == 0 && controller.matches.first?.url == first)
controller.field.stringValue = ""
controller.refresh()
precondition(controller.command(#selector(NSResponder.cancelOperation(_:))))
precondition(wait { !controller.panel.isVisible })
print("Sandbox discovery, filesystem events, and launcher interaction checks passed")
