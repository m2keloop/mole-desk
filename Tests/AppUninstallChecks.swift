import AppKit

@main struct AppUninstallChecks {
    static func main() throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory); application.finishLaunching()
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("uninstall-check-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let apps = root.appendingPathComponent("Applications")
        let cache = root.appendingPathComponent("Library/Caches/test.example")
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        func makeApp(_ name: String, id: String = "test.example") throws -> InstalledApp {
            let url = apps.appendingPathComponent(name + ".app")
            let contents = url.appendingPathComponent("Contents")
            try fm.createDirectory(at: contents, withIntermediateDirectories: true)
            let plist: [String: Any] = ["CFBundleName": name, "CFBundlePackageType": "APPL", "CFBundleIdentifier": id]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            return InstalledApp(url: url, name: name, lastUsed: nil, running: false)
        }
        let example = try makeApp("Example")
        func prepare(_ app: InstalledApp, inventory: [InstalledApp]? = nil, complete: Bool = true,
                     running: Set<String> = [], protected: Bool = false) throws -> AppRemovalPlan {
            try AppRemovalPlan.prepare(app: app, home: root, allowedRoots: [apps],
                                       inventory: inventory ?? [app], inventoryComplete: complete,
                                       running: running, isProtected: { _ in protected })
        }
        func rejects(_ action: () throws -> Void) {
            do { try action(); preconditionFailure("Expected rejection") } catch { }
        }
        let plan = try prepare(example)
        precondition(plan.cache?.path == cache.path)
        try plan.verify(running: [], isProtected: { _ in false })
        try plan.verifyCache(isProtected: { _ in false })
        rejects { _ = try prepare(example, running: [example.url.path]) }
        rejects { _ = try prepare(example, protected: true) }
        rejects { try plan.verify(running: [example.url.path], isProtected: { _ in false }) }
        rejects { try plan.verifyCache(isProtected: { _ in true }) }
        let duplicate = try makeApp("Duplicate")
        let sharedPlan = try prepare(example, inventory: [example, duplicate])
        let incompletePlan = try prepare(example, complete: false)
        precondition(sharedPlan.cache == nil)
        precondition(incompletePlan.cache == nil)
        let apple = try makeApp("Apple", id: "com.apple.Test")
        let selfApp = try makeApp("Self", id: "local.lan.MoleDesk")
        rejects { _ = try prepare(apple) }
        rejects { _ = try prepare(selfApp) }
        let info = example.url.appendingPathComponent("Contents/Info.plist")
        let originalInfo = try Data(contentsOf: info)
        try (originalInfo + Data(" ".utf8)).write(to: info)
        rejects { try plan.verify(running: [], isProtected: { _ in false }) }
        try originalInfo.write(to: info)
        let window = AppUsageWindow()
        window.home = root; window.uninstallRoots = [apps]
        window.inventory = AppInventory(apps: [example], unreadableRoots: [])
        let shownPath = "~/Applications/Example.app"
        let preview = "Matched 1 app(s):\nFiles to be removed:\n  ✓ " + shownPath + "  3MB\n"
        precondition(MoleUninstall.cleanOutput("\u{1b}[2J\u{1b}[Hok") == "ok")
        precondition(MoleUninstall.verifiedPreview(preview, app: example.url, home: root))
        precondition(!MoleUninstall.verifiedPreview(preview.replacingOccurrences(of: "Matched 1", with: "Matched 2"), app: example.url, home: root))
        precondition(!MoleUninstall.verifiedPreview(preview.replacingOccurrences(of: shownPath, with: shownPath + ".Other"), app: example.url, home: root))
        precondition(!MoleUninstall.verifiedPreview("Matched 1 app(s):", app: example.url, home: root))
        let fakeMo = root.appendingPathComponent("mo")
        let fixture = """
        #!/bin/sh
        test "$#" = 3 && test "$1" = uninstall && test "$2" = --dry-run && test "$3" = Example && test "$MOLE_DRY_RUN" = 1 || exit 1
        cat <<'PREVIEW'
        \(preview)
        PREVIEW
        """
        try Data(fixture.utf8).write(to: fakeMo)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fakeMo.path)
        window.moleExecutables = [fakeMo.path]
        window.applyFilter(); window.window.makeKeyAndOrderFront(nil)
        window.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        window.uninstallSelection()
        let deadline = Date().addingTimeInterval(10)
        while window.window.attachedSheet == nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        guard let sheet = window.window.attachedSheet else { throw DeskError("Missing Mole preview") }
        window.window.endSheet(sheet, returnCode: .alertFirstButtonReturn)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        precondition(fm.fileExists(atPath: example.url.path) && fm.fileExists(atPath: cache.path))
        let script = try MoleUninstall.commandScript(executable: "/tmp/mo", appName: "App'Name")
        defer { try? fm.removeItem(at: script.deletingLastPathComponent()) }
        let body = try String(contentsOf: script, encoding: .utf8)
        precondition(body.contains("exec '/tmp/mo' uninstall 'App'\\''Name'"))
        rejects { _ = try MoleUninstall.commandScript(executable: "/tmp/mo", appName: "-unsafe") }
        print("App uninstall safeguards, Mole preview matching and safe command quoting passed.")
    }
}
