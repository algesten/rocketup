import AppKit
func entry(_ name: String, local: Bool = false, path: String = "/Applications") -> AppEntry {
    AppEntry(url: URL(fileURLWithPath: "\(path)/\(name).app"), name: name, names: [name], local: local, icon: NSImage())
}
let apps = [entry("Google Chrome"), entry("Chrome Helper"), entry("Notes Helper"), entry("Notes"), entry("Café"), entry("Visual Studio Code"), entry("Google Chrome", local: true, path: "/Users/me/Applications")]
func names(_ q: String) -> [String] { results(apps, q).map(\.name) }
precondition(names("gc").first == "Google Chrome")
precondition(names("chr").prefix(2).elementsEqual(["Chrome Helper", "Google Chrome"]))
precondition(names("notes").first == "Notes")
precondition(names("cafe") == ["Café"])
precondition(names("visualstudio") == ["Visual Studio Code"])
precondition(results(apps, "gc").first?.local == true)
precondition(names("").isEmpty)
print("Search checks passed")
