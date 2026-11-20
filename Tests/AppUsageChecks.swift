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
        let questionableDate = now.addingTimeInterval(-400 * 86400)
        let questionable = AppInventory.read(roots: [root], runningPaths: [],
            lastUsed: { $0 == old ? questionableDate : nil },
            fileDates: { $0 == old ? (questionableDate, nil) : (nil, nil) })
        let flagged = questionable.apps.first { $0.url == old }!
        precondition(flagged.suspiciousRecord && flagged.lastUsed == nil)
        precondition(flagged.ageDescription() == "记录存疑" && flagged.daysSinceUse() == nil)
        precondition(suspiciousUsageDate(questionableDate, creation: questionableDate.addingTimeInterval(-3600), modification: questionableDate.addingTimeInterval(0.5)))
        precondition(suspiciousUsageDate(questionableDate, creation: nil, modification: nil))
        precondition(!suspiciousUsageDate(questionableDate, creation: questionableDate.addingTimeInterval(-86400), modification: questionableDate.addingTimeInterval(-3600)))
        let dataHome = root.appendingPathComponent("fixture-home")
        let support = dataHome.appendingPathComponent("Library/Application Support/Old")
        let preference = dataHome.appendingPathComponent("Library/Preferences/test.Old.plist")
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        try fm.createDirectory(at: preference.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: preference)
        let dataDate = now.addingTimeInterval(-200 * 86400)
        try fm.setAttributes([.modificationDate: dataDate], ofItemAtPath: support.path)
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-300 * 86400)], ofItemAtPath: preference.path)
        let evidence = AppInventory.read(roots: [root], runningPaths: [], lastUsed: { _ in nil }, dataHome: dataHome)
        let estimated = evidence.apps.first { $0.url == old }!
        precondition(estimated.lastUsed == nil && estimated.daysSinceUse() == nil)
        precondition(estimated.dataActivity?.source == "同名应用支持目录")
        precondition(estimated.ageDescription(now: now).hasPrefix("数据 "))
        precondition(appDataActivity(home: dataHome, bundleID: "test.Old", bundleName: "Old", isProtected: { _ in true }) == nil)
        try fm.removeItem(at: support)
        try fm.createSymbolicLink(at: support, withDestinationURL: preference)
        let linkResult = appDataActivity(home: dataHome, bundleID: nil, bundleName: "Old", isProtected: { _ in false })
        precondition(linkResult == nil)
        try fm.removeItem(at: support)
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        try fm.setAttributes([.modificationDate: dataDate], ofItemAtPath: support.path)
        let window = AppUsageWindow()
        window.roots = [root]; window.metadata = reader
        window.inventory = scan
        window.filterMenu.selectItem(at: 2); window.applyFilter()
        precondition(window.visible.map(\.name) == ["Old"])
        window.filterMenu.selectItem(at: 5); window.applyFilter()
        precondition(window.visible.map(\.name) == ["Unknown"])
        window.filterMenu.selectItem(at: 6); window.applyFilter()
        precondition(window.visible.map(\.name) == ["Active"])
        window.inventory = questionable
        window.filterMenu.selectItem(at: 2); window.applyFilter()
        precondition(!window.visible.contains { $0.url == old })
        window.filterMenu.selectItem(at: 5); window.applyFilter()
        precondition(window.visible.contains { $0.url == old && $0.suspiciousRecord })
        window.inventory = evidence
        window.filterMenu.selectItem(at: 2); window.applyFilter()
        precondition(!window.visible.contains { $0.url == old })
        window.filterMenu.selectItem(at: 7); window.applyFilter()
        precondition(window.visible.contains { $0.url == old })
        window.inventory = scan
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
