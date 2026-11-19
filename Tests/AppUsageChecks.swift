import AppKit

@main struct AppUsageChecks {
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory); app.finishLaunching()
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("usage-check-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func makeApp(_ name: String) throws -> URL {
            let url = root.appendingPathComponent(name + ".app")
            let contents = url.appendingPathComponent("Contents")
            try fm.createDirectory(at: contents, withIntermediateDirectories: true)
            let plist: [String: Any] = ["CFBundleName": name, "CFBundlePackageType": "APPL",
                                       "CFBundleIdentifier": "test." + name]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            return url.resolvingSymlinksInPath()
        }
        let old = try makeApp("Old"), active = try makeApp("Active"), unknown = try makeApp("Unknown")
        let now = Date()
        let reader: (URL) -> Date? = { url in
            if url == old { return now.addingTimeInterval(-91 * 86400) }
            if url == active { return now.addingTimeInterval(-200 * 86400) }
            return nil
        }
        let scan = AppInventory.read(roots: [root, root], runningPaths: [active.path], lastUsed: reader)
        precondition(scan.apps.count == 3)
        precondition(scan.apps.first?.name == "Old")
        let running = scan.apps.first { $0.name == "Active" }!
        precondition(running.ageDescription() == "正在运行")
        let missing = scan.apps.first { $0.url == unknown }!
        precondition(missing.ageDescription() == "未记录")
        precondition(scan.apps.first { $0.url == old }!.daysSinceUse()! >= 90)
        let future = InstalledApp(url: old, name: "Future", lastUsed: now.addingTimeInterval(86400), running: false)
        precondition(future.ageDescription(now: now) == "时间异常")
        let window = AppUsageWindow()
        window.roots = [root]; window.metadata = reader
        window.inventory = scan
        window.filterMenu.selectItem(at: 2); window.applyFilter()
        precondition(window.visible.map(\.name) == ["Old"])
        window.filterMenu.selectItem(at: 5); window.applyFilter()
        precondition(window.visible.map(\.name) == ["Unknown"])
        window.filterMenu.selectItem(at: 6); window.applyFilter()
        precondition(window.visible.map(\.name) == ["Active"])
        window.filterMenu.selectItem(at: 0)
        window.search.stringValue = "Old.app"; window.applyFilter()
        precondition(window.visible.map(\.name) == ["Old"])
        window.search.stringValue = ""; window.applyFilter()
        window.window.contentView?.layoutSubtreeIfNeeded()
        if let output = CommandLine.arguments.dropFirst().first, let view = window.window.contentView,
           let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
        }
        print("App inventory, running status, missing and future dates, search and age filters passed.")
    }
}
