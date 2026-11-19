import AppKit

@main struct WindowChecks {
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let desk = Desk()
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        desk.home = temp.path
        desk.backup = temp.appendingPathComponent("preview.txt")
        desk.file = temp.appendingPathComponent("source-preview.txt")
        let cache = temp.appendingPathComponent("Library/Caches/goimports")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let preview = """
        # Mole Cleanup Preview - 2026-01-01 12:00:00
        === User essentials ===
        \(cache.path)  # 1MB
        === Browsers ===
        \(temp.path)/Library/Caches/example  # 2MB
        # Potential cleanup: 3MB
        # Items: 2
        # Categories: 2
        """
        try Data(preview.utf8).write(to: desk.file)
        desk.buildWindow()
        desk.loadReport()
        let timeout = Date().addingTimeInterval(20)
        while desk.loading && Date() < timeout { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        guard let report = desk.report, report.count > 0 else { throw DeskError("A completed Mole report is required") }
        desk.window.displayIfNeeded()
        guard let view = desk.window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw DeskError("Window render failed") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let output = CommandLine.arguments.dropFirst().first {
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
        }
        if CommandLine.arguments.count > 2 {
            desk.window.setContentSize(NSSize(width: 770, height: 480))
            desk.window.contentView?.layoutSubtreeIfNeeded()
            guard let content = desk.window.contentView,
                  let image = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
                throw DeskError("Minimum window render failed")
            }
            content.cacheDisplay(in: content.bounds, to: image)
            try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
            precondition(desk.scan.frame.minX >= desk.headline.frame.maxX)
        }
        precondition(desk.visible.count == report.entries.count)
        precondition(desk.groups.numberOfItems > 1 && !desk.distribution.groups.isEmpty)
        desk.groups.selectItem(at: 1); desk.filter()
        precondition(Set(desk.visible.map(\.group)).count == 1)
        desk.groups.selectItem(at: 0)
        desk.search.stringValue = "/goimports"; desk.filter()
        precondition(desk.visible.count == 1 && desk.visible[0].path.contains("/goimports"))
        desk.search.stringValue = ""; desk.eligible.state = .on; desk.filter()
        precondition(!desk.visible.isEmpty && desk.visible.allSatisfy(\.canReviewForTrash))
        desk.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        desk.refreshActions()
        precondition(desk.trash.isEnabled && desk.reveal.isEnabled)
        desk.trashClicked()
        guard let sheet = desk.window.attachedSheet else { throw DeskError("Missing confirmation sheet") }
        desk.window.endSheet(sheet, returnCode: .alertFirstButtonReturn)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        precondition(desk.moved.isEmpty)
        let result = Desk.resultText(items: [Entry(path: "/tmp/item", group: "x", size: "1KB", bytes: 1000, canReviewForTrash: true)],
                                     finished: [], before: 10000, after: 9000)
        precondition(result.contains("已移到废纸篓 0 项") && result.contains("−"))
        precondition(!desk.isProtected(cache.path))
        precondition(desk.isProtected(desk.home + "/Documents/example"))
        precondition(desk.isProtected(desk.home + "/Documents"))
        let diskRoot = temp.appendingPathComponent("disk")
        try FileManager.default.createDirectory(at: diskRoot.appendingPathComponent("folder"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 8192).write(to: diskRoot.appendingPathComponent("file"))
        let browser = DiskBrowser()
        browser.scan(diskRoot)
        let diskTimeout = Date().addingTimeInterval(10)
        while browser.task != nil && Date() < diskTimeout { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        precondition(browser.task == nil && browser.items.count == 2)
        precondition(browser.items.contains { $0.path.hasSuffix("/file") && $0.bytes > 0 })
        precondition(browser.state.stringValue.contains("共 2 项"))
        if CommandLine.arguments.count > 3, let content = browser.window.contentView,
           let image = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.layoutSubtreeIfNeeded()
            content.cacheDisplay(in: content.bounds, to: image)
            try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
        }
        let reviewable = desk.visible.count
        let fakeMo = temp.appendingPathComponent("mo")
        desk.file = temp.appendingPathComponent("clean-list.txt")
        desk.scanExecutables = [fakeMo.path]
        let fixtureScript = """
        #!/bin/sh
        test "$#" = 2 && test "$1" = clean && test "$2" = --dry-run && test "$MOLE_DRY_RUN" = 1 || exit 1
        cat > "$(dirname "$0")/clean-list.txt" <<'REPORT'
        # Mole Cleanup Preview - unit fixture
        === User essentials ===
        /tmp/example  # 1KB
        # Potential cleanup: 1KB
        # Items: 1
        REPORT
        """
        try Data(fixtureScript.utf8).write(to: fakeMo)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fakeMo.path)
        func waitForScan() {
            let deadline = Date().addingTimeInterval(10)
            while (desk.scanPID > 0 || desk.loading) && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
            precondition(desk.scanPID == 0 && !desk.loading)
        }
        desk.scanClicked(); waitForScan()
        precondition(desk.report?.count == 1 && desk.report?.total == "1KB")
        try Data("#!/bin/sh\nsleep 60\n".utf8).write(to: fakeMo)
        desk.scanClicked(); let pid = desk.scanPID
        precondition(pid > 0); desk.stopScan(); waitForScan()
        precondition(kill(-pid,0) != 0)
        print("Window rendered with",report.count,"items;",reviewable,"reviewable paths; filters, confirmation cancel, dry-run reload and process cancellation passed.")
    }
}
