import AppKit
import Darwin

private func label(_ text: String, _ size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.lineBreakMode = .byTruncatingTail
    return field
}

final class Desk: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    var home = NSHomeDirectory()
    lazy var file = URL(fileURLWithPath: home).appendingPathComponent(".config/mole/clean-list.txt")
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    let table = NSTableView(), search = NSSearchField(), groups = NSPopUpButton()
    let eligible = NSButton(checkboxWithTitle: "仅可移入废纸篓", target: nil, action: nil)
    let headline = label("—", 38, weight: .semibold), info = label("", 12), status = label("", 12)
    let scan = NSButton(), reveal = NSButton(), trash = NSButton(), disk = NSButton(), protection = NSButton(), apps = NSButton()
    lazy var diskBrowser = DiskBrowser()
    lazy var appUsage: AppUsageWindow = {
        let result = AppUsageWindow()
        result.isProtected = { [weak self] path in self?.isProtected(path) ?? true }
        return result
    }()
    let spin = NSProgressIndicator(), distribution = Distribution()
    lazy var backup = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("local.lan.MoleDesk/last-preview.txt")
    var report: Report?, visible = [Entry](), moved = Set<String>()
    lazy var scanExecutables = ["/opt/homebrew/bin/mo", "/usr/local/bin/mo", home + "/.local/bin/mo"]
    var scanPID: pid_t = 0, loading = false, loadID = 0
    var loadedDate: Date?
    var lastError: String?
    var quitAfterScan = false
    var protectedPaths: [String] {
        get {
            UserDefaults.standard.stringArray(forKey: "protectedPaths") ?? [
                home + "/Library/Containers/com.tencent.xinWeChat",
                home + "/Documents",
                home + "/go/pkg/mod"
            ]
        }
        set { UserDefaults.standard.set(newValue, forKey: "protectedPaths") }
    }
    func isProtected(_ path: String) -> Bool {
        let target = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        return protectedPaths.contains { value in
            let protected = URL(fileURLWithPath: value).standardizedFileURL.resolvingSymlinksInPath().path
            return target == protected || protected == "/" || target == "/" ||
                target.hasPrefix(protected + "/") || protected.hasPrefix(target + "/")
        }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        let appMenu = NSMenu(), menu = NSMenu()
        let root = menu.addItem(withTitle: "盘览", action: nil, keyEquivalent: "")
        root.submenu = appMenu
        appMenu.addItem(withTitle: "退出盘览", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenu(title: "编辑")
        for (title, sel, key) in [("剪切","cut:","x"),("复制","copy:","c"),("粘贴","paste:","v"),("全选","selectAll:","a")] {
            edit.addItem(withTitle: title, action: NSSelectorFromString(sel), keyEquivalent: key)
        }
        menu.addItem(withTitle: "编辑", action: nil, keyEquivalent: "").submenu = edit
        NSApp.mainMenu = menu
        buildWindow()
        loadReport()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func button(_ b: NSButton, title: String, symbol: String, action: Selector) {
        b.title = title
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        b.imagePosition = .imageLeading
        b.bezelStyle = .rounded
        b.target = self; b.action = action
    }

    func buildWindow() {
        window.title = "盘览"; window.delegate = self
        window.minSize = NSSize(width: 770, height: 480)
        window.setFrameAutosaveName("DiskReviewWindow")
        let root = WindowBackground()
        window.contentView = root

        let hero = HeroBackground()
        let brandIcon = NSImageView()
        brandIcon.image = NSImage(named: NSImage.Name("AppBadge"))
        brandIcon.imageScaling = .scaleProportionallyUpOrDown
        let brand = label("盘览", 14, weight: .semibold)
        brand.textColor = NSColor.white.withAlphaComponent(0.93)
        let kicker = label("MOLE · 清理预览", 11, weight: .medium)
        kicker.textColor = NSColor.white.withAlphaComponent(0.62)
        headline.font = .monospacedDigitSystemFont(ofSize: 38, weight: .semibold)
        headline.textColor = .white
        info.textColor = NSColor.white.withAlphaComponent(0.70)
        let brandLine = NSStackView(views: [brandIcon, brand, kicker])
        brandLine.orientation = .horizontal; brandLine.alignment = .centerY; brandLine.spacing = 9
        brandIcon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        brandIcon.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let title = NSStackView(views: [brandLine, headline, info])
        title.orientation = .vertical; title.alignment = .leading; title.spacing = 5

        button(scan, title: "重新扫描", symbol: "arrow.clockwise", action: #selector(scanClicked))
        scan.bezelColor = NSColor(calibratedRed: 0.31, green: 0.73, blue: 0.69, alpha: 1)
        scan.controlSize = .large
        button(disk, title: "磁盘分析", symbol: "chart.bar.xaxis", action: #selector(showDisk))
        button(protection, title: "保护范围", symbol: "shield", action: #selector(editProtection))
        button(apps, title: "应用使用", symbol: "app.badge.clock", action: #selector(showApps))
        spin.style = .spinning; spin.controlSize = .small; spin.isDisplayedWhenStopped = false

        search.placeholderString = "搜索名称或路径"; search.delegate = self
        search.setAccessibilityLabel("搜索候选项目")
        groups.addItem(withTitle: "全部分类"); groups.target = self; groups.action = #selector(filter)
        eligible.target = self; eligible.action = #selector(filter)
        let tools = NSStackView(views: [groups, eligible]); tools.spacing = 14
        let sectionTitle = label("清理项目", 15, weight: .semibold)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.borderType = .noBorder; scroll.documentView = table
        table.dataSource = self; table.delegate = self; table.rowHeight = 52
        table.style = .inset; table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.allowsMultipleSelection = true
        table.intercellSpacing = NSSize(width: 8, height: 2)
        table.doubleAction = #selector(showInFinder); table.target = self
        for (key, text, width) in [("name","项目与位置",520),("group","分类",160),("size","预估占用",100)] {
            let col = NSTableColumn(identifier: .init(key))
            col.title = text; col.width = CGFloat(width)
            col.minWidth = key == "name" ? 220 : 85
            col.resizingMask = key == "name" ? [.autoresizingMask,.userResizingMask] : .userResizingMask
            if key == "size" { col.headerCell.alignment = .right }
            table.addTableColumn(col)
        }
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        button(reveal, title: "在 Finder 中显示", symbol: "folder", action: #selector(showInFinder))
        button(trash, title: "移到废纸篓…", symbol: "trash", action: #selector(trashClicked))
        let actions = NSStackView(views: [disk, apps, protection, reveal, trash]); actions.spacing = 8
        status.textColor = .secondaryLabelColor
        distribution.setAccessibilityLabel("按分类查看已测量的空间占比")
        distribution.choose = { [weak self] key in
            guard let self else { return }
            self.groups.selectItem(at: self.groups.indexOfItem(withRepresentedObject: key))
            self.filter()
        }

        for view in [hero, tools, search, sectionTitle, scroll, status, actions] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view)
        }
        for view in [title, scan, spin, distribution] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false; hero.addSubview(view)
        }
        NSLayoutConstraint.activate([
            hero.topAnchor.constraint(equalTo: root.topAnchor),
            hero.leadingAnchor.constraint(equalTo: root.leadingAnchor), hero.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            title.topAnchor.constraint(equalTo: hero.topAnchor, constant: 19),
            title.leadingAnchor.constraint(equalTo: hero.leadingAnchor, constant: 26),
            scan.trailingAnchor.constraint(equalTo: hero.trailingAnchor, constant: -26),
            scan.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            spin.trailingAnchor.constraint(equalTo: scan.leadingAnchor, constant: -10),
            spin.centerYAnchor.constraint(equalTo: scan.centerYAnchor),
            distribution.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 18),
            distribution.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            distribution.trailingAnchor.constraint(equalTo: scan.trailingAnchor),
            distribution.heightAnchor.constraint(equalToConstant: 7),
            distribution.bottomAnchor.constraint(equalTo: hero.bottomAnchor, constant: -21),
            sectionTitle.topAnchor.constraint(equalTo: hero.bottomAnchor, constant: 21),
            sectionTitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 26),
            tools.topAnchor.constraint(equalTo: sectionTitle.bottomAnchor, constant: 13),
            tools.leadingAnchor.constraint(equalTo: sectionTitle.leadingAnchor),
            search.centerYAnchor.constraint(equalTo: tools.centerYAnchor),
            search.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -26),
            search.widthAnchor.constraint(equalToConstant: 245),
            scroll.topAnchor.constraint(equalTo: tools.bottomAnchor, constant: 13),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            scroll.bottomAnchor.constraint(equalTo: actions.topAnchor, constant: -13),
            actions.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            actions.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 26),
            status.centerYAnchor.constraint(equalTo: actions.centerYAnchor),
            status.trailingAnchor.constraint(lessThanOrEqualTo: actions.leadingAnchor, constant: -8)
        ])
    }

    func windowDidResize(_ notification: Notification) { fitColumns() }
    func fitColumns() {
        guard let scroll = table.enclosingScrollView, table.tableColumns.count == 3 else { return }
        let columns = table.tableColumns
        let available = scroll.contentSize.width - columns[1].width - columns[2].width - 4 * table.intercellSpacing.width - 30
        if available > columns[0].minWidth { columns[0].width = available }
    }

    func loadReport(finishedScan: Bool = false) {
        loading = true; loadID += 1
        let job = loadID, url = file, base = home, fallback = backup
        refreshActions()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { () -> (Report,Date?) in
                do {
                    let stamp = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                    let text = try String(contentsOf: url, encoding: .utf8)
                    let parsed = try Report.parse(text, home: base, completedScan: finishedScan)
                    // Mole writes its report in place. Preserve a completed preview across interrupted scans.
                    try? FileManager.default.createDirectory(at: fallback.deletingLastPathComponent(),
                        withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    let snapshot = Data(text.utf8)
                    if (try? Data(contentsOf: fallback)) != snapshot { try? snapshot.write(to: fallback, options: .atomic) }
                    return (parsed,stamp)
                } catch {
                    let previous = try? String(contentsOf: fallback, encoding: .utf8)
                    guard let previous, let parsed = try? Report.parse(previous, home: base, completedScan: true) else { throw error }
                    return (parsed,nil)
                }
            }
            DispatchQueue.main.async {
                guard job == self.loadID else { return }
                self.loading = false
                switch result {
                case .success(let value):
                    self.report = value.0; self.loadedDate = value.1
                    self.moved.removeAll(); self.lastError = nil
                    self.headline.stringValue = value.0.total
                    self.info.stringValue = "预计可清理  ·  " + String(value.0.count) + " 项  ·  " + value.0.date
                    self.groups.removeAllItems(); self.groups.addItem(withTitle: "全部分类")
                    var sizes = [String: Double]()
                    for row in value.0.entries { sizes[row.group, default: 0] += row.bytes ?? 0 }
                    let ordered = sizes.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
                    self.distribution.groups = ordered.map { ($0.key,$0.value) }
                    for (key,size) in ordered {
                        self.groups.addItem(withTitle: (categoryNames[key] ?? key) + " · " + displaySize(size))
                        self.groups.lastItem?.representedObject = key
                    }
                    if value.1 == nil { self.lastError = "上次完整预览 · 请重新扫描以执行操作。" }
                case .failure(let error):
                    self.lastError = FileManager.default.fileExists(atPath: url.path) ? error.localizedDescription : "点击「重新扫描」生成第一份预览。"
                    self.loadedDate = nil
                }
                self.window.contentView?.layoutSubtreeIfNeeded()
                self.fitColumns()
                self.filter()
            }
        }
    }

    @objc func filter() {
        let group = groups.selectedItem?.representedObject as? String
        let query = search.stringValue.trimmingCharacters(in: .whitespaces)
        visible = (report?.entries ?? []).filter {
            !moved.contains($0.path) && (group == nil || $0.group == group)
              && (eligible.state != .on || ($0.canReviewForTrash && !isProtected($0.path)))
              && (query.isEmpty || $0.path.localizedCaseInsensitiveContains(query) || $0.name.localizedCaseInsensitiveContains(query))
        }
        table.deselectAll(nil); table.reloadData(); refreshActions()
    }
    func controlTextDidChange(_ note: Notification) { filter() }
    func numberOfRows(in tableView: NSTableView) -> Int { visible.count }
    func tableViewSelectionDidChange(_ notification: Notification) { refreshActions() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier, visible.indices.contains(row) else { return nil }
        let e = visible[row]
        if id.rawValue == "name" {
            let cell = tableView.makeView(withIdentifier: id, owner: nil) as? EntryCell ?? EntryCell()
            cell.identifier = id
            cell.name.stringValue = e.name; cell.location.stringValue = (e.path as NSString).abbreviatingWithTildeInPath
            cell.configure(group: e.group)
            cell.toolTip = e.path; return cell
        }
        let field = tableView.makeView(withIdentifier: id, owner: nil) as? NSTextField ?? label("",12)
        field.identifier = id
        field.stringValue = id.rawValue == "group" ? categoryNames[e.group] ?? e.group : e.size
        field.textColor = .secondaryLabelColor
        if id.rawValue == "size" { field.alignment = .right; field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium) }
        return field
    }
    var selected: [Entry] { table.selectedRowIndexes.compactMap { visible.indices.contains($0) ? visible[$0] : nil } }

    func refreshActions() {
        let sel = selected
        let busy = scanPID > 0 || loading
        reveal.isEnabled = !sel.isEmpty
        trash.isEnabled = !busy && loadedDate != nil && !sel.isEmpty && sel.allSatisfy { $0.canReviewForTrash && !isProtected($0.path) }
        trash.toolTip = "Mole 负责扫描；盘览直接将所选项目移入废纸篓，操作前会再次核验。"
        scan.isEnabled = !loading && scan.title != "正在停止…"
        status.stringValue = scanPID > 0 ? "Mole 正在扫描，可继续查看上次结果…" :
            loading ? "正在读取预览…" : lastError ??
            (sel.isEmpty ? "显示 " + String(visible.count) + " 个路径" : "已选 " + String(sel.count) + " 个路径" +
             (sel.allSatisfy(\.canReviewForTrash) ? "" : "  ·  可在 Finder 中检查"))
        status.toolTip = status.stringValue
    }

    @objc func showDisk() { diskBrowser.show() }
    @objc func showApps() { appUsage.show() }

    @objc func editProtection() {
        let alert = NSAlert()
        alert.messageText = "保护范围"
        alert.informativeText = "每行填写一个绝对路径，保护目录及其内容。"
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 150))
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        let editor = NSTextView(frame: scroll.bounds)
        editor.string = protectedPaths.joined(separator: "\n")
        editor.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        editor.isVerticallyResizable = true
        editor.textContainer?.widthTracksTextView = true
        scroll.documentView = editor; alert.accessoryView = scroll
        alert.addButton(withTitle: "保存"); alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { result in
            guard result == .alertFirstButtonReturn else { return }
            let paths = editor.string.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard paths.allSatisfy({ $0.hasPrefix("/") && !$0.contains("\0") }) else {
                self.message("路径无效", "请为每个保护目录填写绝对路径。")
                return
            }
            self.protectedPaths = paths
            self.filter()
        }
    }

    @objc func showInFinder() {
        let urls = selected.map { URL(fileURLWithPath: $0.path) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        if urls.isEmpty { message("项目已不存在", "重新扫描可以更新清单。"); return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    @objc func scanClicked() {
        if scanPID > 0 { stopScan(); return }
        guard let exe = scanExecutables.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            message("找不到 Mole", "请先通过 Homebrew 安装 mole。"); return
        }
        do {
            let pid = try spawnPreview(exe)
            scanPID = pid; scan.title = "停止扫描"; spin.startAnimation(nil); lastError = nil; refreshActions()
            DispatchQueue.global(qos: .utility).async {
                var result: Int32 = 0, waited: pid_t = -1
                repeat { waited = waitpid(pid, &result, 0) } while waited == -1 && errno == EINTR
                let ok = waited == pid && result == 0
                DispatchQueue.main.async {
                    let stopped = self.scan.title == "正在停止…"
                    if stopped { kill(-pid, SIGKILL) }
                    self.scanPID = 0; self.scan.title = "重新扫描"; self.spin.stopAnimation(nil)
                    if self.quitAfterScan { NSApp.reply(toApplicationShouldTerminate: true); return }
                    if ok && !stopped { self.loadReport(finishedScan: true) }
                    else {
                        self.lastError = stopped ? "扫描已停止，显示上次结果。" : "Mole 扫描失败，请检查目录访问权限。"
                        self.refreshActions()
                    }
                }
            }
        } catch { message("无法启动扫描", error.localizedDescription) }
    }
    func stopScan() {
        let pid = scanPID
        guard pid > 0 else { return }
        scan.title = "正在停止…"; scan.isEnabled = false
        kill(-pid, SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now()+1) {
            if self.scanPID == pid { kill(-pid, SIGKILL) }
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if scanPID > 0 { quitAfterScan = true; stopScan(); return .terminateLater }
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func message(_ title: String, _ text: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = text
        alert.addButton(withTitle: "好"); alert.beginSheetModal(for: window)
    }

    static func availableSpace() -> Int64? {
        guard let value = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())[.systemFreeSize] as? NSNumber else { return nil }
        return value.int64Value
    }
    static func resultText(items: [Entry], finished: [Entry], before: Int64?, after: Int64?) -> String {
        let selectedBytes = items.reduce(0) { $0 + ($1.bytes ?? 0) }
        let movedBytes = finished.reduce(0) { $0 + ($1.bytes ?? 0) }
        let unknown = items.contains { $0.bytes == nil } ? "（部分未计量）" : ""
        var text = "所选预估 " + displaySize(selectedBytes) + unknown
        text += "\n已移到废纸篓 " + String(finished.count) + " 项，预估 " + displaySize(movedBytes)
        if let before, let after {
            let delta = after - before
            text += "\n磁盘可用空间变化 " + (delta >= 0 ? "+" : "−") + displaySize(Double(abs(delta)))
        } else { text += "\n磁盘可用空间变化未能测量" }
        text += "\n废纸篓中的文件仍占用磁盘空间。"
        return text
    }

    static func identity(_ path: String) throws -> String {
        var details = stat()
        guard lstat(path, &details) == 0 else { throw DeskError("项目已不存在：\n" + path) }
        return "\(details.st_dev):\(details.st_ino)"
    }

    @objc func trashClicked() {
        let items = selected
        guard trash.isEnabled, !items.isEmpty else { return }
        let identities: [String]
        do {
            identities = try items.map { try Self.identity($0.path) }
        } catch { message("无法读取项目", error.localizedDescription); return }
        let alert = NSAlert()
        alert.messageText = "将所选 " + String(items.count) + " 项移到废纸篓？"
        alert.informativeText = "目录将连同其内容一起移动。建议先退出相关应用，缓存可能需要重新下载。清空废纸篓后才会释放空间。"
        let scroll = NSScrollView(frame: NSRect(x: 0,y: 0,width: 420,height: CGFloat(min(6,items.count))*32+12))
        scroll.hasVerticalScroller = true
        let paths = NSTextView(frame: scroll.bounds); paths.isEditable = false
        paths.string = items.map(\.path).joined(separator: "\n")
        paths.textContainer?.widthTracksTextView = true; paths.isVerticallyResizable = true
        scroll.documentView = paths; alert.accessoryView = scroll
        alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "移到废纸篓")
        alert.beginSheetModal(for: window) { result in
            guard result == .alertSecondButtonReturn else { return }
            var finished = [Entry]()
            let before = Self.availableSpace()
            do {
                let fm = FileManager.default
                let stamp = try self.file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                guard let stamp, stamp == self.loadedDate else { throw DeskError("预览清单已变化，请重新扫描。") }
                let whitelist = self.file.deletingLastPathComponent().appendingPathComponent("whitelist")
                if fm.fileExists(atPath: whitelist.path),
                   let change = try whitelist.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, change >= stamp {
                    throw DeskError("Mole 保护规则已更新，请重新扫描。")
                }
                for (index, e) in items.enumerated() {
                    guard !self.isProtected(e.path) else { throw DeskError("项目属于保护范围：\n" + e.path) }
                    try TrashPolicy.validate(e.path, home: self.home)
                    guard try Self.identity(e.path) == identities[index] else {
                        throw DeskError("项目已变化，请重新扫描：\n" + e.path)
                    }
                }
                for (index, e) in items.enumerated() {
                    guard !self.isProtected(e.path) else { throw DeskError("项目属于保护范围：\n" + e.path) }
                    try TrashPolicy.validate(e.path, home: self.home)
                    guard try Self.identity(e.path) == identities[index] else {
                        throw DeskError("项目已变化，请重新扫描：\n" + e.path)
                    }
                    try fm.trashItem(at: URL(fileURLWithPath: e.path), resultingItemURL: nil)
                    self.moved.insert(e.path)
                    finished.append(e)
                }
                self.lastError = "已移到废纸篓 " + String(finished.count) + " 项，可重新扫描更新预估。"
                self.message("处理完成", Self.resultText(items: items, finished: finished, before: before, after: Self.availableSpace()))
            } catch {
                self.lastError = "操作已停止，已处理 " + String(finished.count) + " 项。"
                self.message("操作已停止", Self.resultText(items: items, finished: finished, before: before, after: Self.availableSpace()) + "\n\n" + error.localizedDescription)
            }
            self.filter()
        }
    }
}

final class WindowBackground: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) { NSColor.windowBackgroundColor.setFill(); dirtyRect.fill() }
}

final class HeroBackground: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let start = NSColor(calibratedRed: 0.08, green: 0.14, blue: 0.20, alpha: 1)
        let end = NSColor(calibratedRed: 0.10, green: 0.26, blue: 0.28, alpha: 1)
        NSGradient(starting: start, ending: end)?.draw(in: bounds, angle: 0)
    }
}

final class EntryCell: NSView {
    let name = label("", 13, weight: .medium), location = label("", 11)
    private let iconPlate = NSView(), icon = NSImageView()
    override init(frame: NSRect) {
        super.init(frame: frame)
        location.textColor = .secondaryLabelColor; location.lineBreakMode = .byTruncatingMiddle
        iconPlate.wantsLayer = true; iconPlate.layer?.cornerRadius = 9
        iconPlate.layer?.backgroundColor = NSColor(calibratedRed: 0.19, green: 0.55, blue: 0.53, alpha: 0.11).cgColor
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        icon.contentTintColor = NSColor(calibratedRed: 0.19, green: 0.55, blue: 0.53, alpha: 1)
        for v in [iconPlate, name, location] as [NSView] { addSubview(v); v.translatesAutoresizingMaskIntoConstraints = false }
        icon.translatesAutoresizingMaskIntoConstraints = false; iconPlate.addSubview(icon)
        NSLayoutConstraint.activate([
            iconPlate.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconPlate.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconPlate.widthAnchor.constraint(equalToConstant: 34), iconPlate.heightAnchor.constraint(equalToConstant: 34),
            icon.centerXAnchor.constraint(equalTo: iconPlate.centerXAnchor), icon.centerYAnchor.constraint(equalTo: iconPlate.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18), icon.heightAnchor.constraint(equalToConstant: 18),
            name.leadingAnchor.constraint(equalTo: iconPlate.trailingAnchor, constant: 11),
            name.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            name.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -8),
            location.leadingAnchor.constraint(equalTo: name.leadingAnchor), location.trailingAnchor.constraint(equalTo: name.trailingAnchor),
            location.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 9)
        ])
    }
    func configure(group: String) {
        let symbols = ["User essentials": "tray.full", "App caches": "app", "Browsers": "globe",
                       "Developer tools": "hammer", "Apps & utilities": "square.grid.2x2",
                       "Application Support": "folder", "App leftovers": "archivebox"]
        icon.image = NSImage(systemSymbolName: symbols[group] ?? "doc", accessibilityDescription: group)
    }
    required init?(coder: NSCoder) { fatalError() }
}
