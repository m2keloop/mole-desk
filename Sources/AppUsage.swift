import AppKit
import CoreServices

struct InstalledApp {
    let url: URL
    let name: String
    let lastUsed: Date?
    let running: Bool

    func daysSinceUse(now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let lastUsed, lastUsed <= now else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: lastUsed),
                                       to: calendar.startOfDay(for: now)).day
    }
    func ageDescription(now: Date = Date()) -> String {
        if running { return "正在运行" }
        guard lastUsed != nil else { return "未记录" }
        guard let days = daysSinceUse(now: now) else { return "时间异常" }
        if days == 0 { return "今天" }
        if days == 1 { return "1 天前" }
        return "\(days) 天前"
    }
}

struct AppInventory {
    let apps: [InstalledApp]
    let unreadableRoots: [String]

    static func read(roots: [URL], runningPaths: Set<String>,
                     lastUsed: (URL) -> Date? = spotlightLastUsed) -> AppInventory {
        let fm = FileManager.default
        var seen = Set<String>(), apps: [InstalledApp] = [], failures: [String] = []
        for root in roots {
            guard fm.fileExists(atPath: root.path) else { continue }
            var failed = false
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in failed = true; return true }) else {
                failures.append(root.path); continue
            }
            for case let url as URL in enumerator {
                if url.pathExtension.lowercased() != "app" { continue }
                enumerator.skipDescendants()
                guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      values.isDirectory == true, values.isSymbolicLink != true else { continue }
                let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
                guard seen.insert(canonical.path).inserted,
                      let bundle = Bundle(url: canonical),
                      let info = bundle.infoDictionary,
                      info["CFBundlePackageType"] as? String == "APPL" else { continue }
                let localized = bundle.localizedInfoDictionary
                let name = localized?["CFBundleDisplayName"] as? String
                    ?? localized?["CFBundleName"] as? String
                    ?? info["CFBundleDisplayName"] as? String
                    ?? info["CFBundleName"] as? String
                    ?? canonical.deletingPathExtension().lastPathComponent
                apps.append(InstalledApp(url: canonical, name: name, lastUsed: lastUsed(canonical),
                                         running: runningPaths.contains(canonical.path)))
            }
            if failed { failures.append(root.path) }
        }
        apps.sort {
            switch ($0.running, $1.running, $0.lastUsed, $1.lastUsed) {
            case (true, false, _, _): return false
            case (false, true, _, _): return true
            case (_, _, let a?, let b?) where a != b: return a < b
            case (_, _, nil, .some): return false
            case (_, _, .some, nil): return true
            default: return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
        return AppInventory(apps: apps, unreadableRoots: failures)
    }
}

func spotlightLastUsed(_ url: URL) -> Date? {
    guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
    return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
}

final class AppUsageWindow: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
    let table = NSTableView(), search = NSSearchField(), filterMenu = NSPopUpButton()
    let status = NSTextField(labelWithString: "")
    private let refresh = NSButton(title: "刷新", target: nil, action: nil)
    private let reveal = NSButton(title: "在 Finder 中显示", target: nil, action: nil)
    let uninstall = NSButton(title: "Mole 卸载…", target: nil, action: nil)
    var isProtected: (String) -> Bool = { _ in false }
    var moleExecutables = ["/opt/homebrew/bin/mo", "/usr/local/bin/mo", NSHomeDirectory() + "/.local/bin/mo"]
    private var uninstallTask: Process?
    var home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    lazy var uninstallRoots = [URL(fileURLWithPath: "/Applications", isDirectory: true),
                               home.appendingPathComponent("Applications", isDirectory: true)]
    var inventory: AppInventory?
    var visible: [InstalledApp] = []
    var roots: [URL] = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true)
    ]
    var metadata: (URL) -> Date? = spotlightLastUsed
    var isLoading = false
    private var generation = 0
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    override init() {
        super.init()
        window.title = "应用使用情况"; window.delegate = self; window.minSize = NSSize(width: 630, height: 410)
        let root = WindowBackground(); window.contentView = root
        let hero = HeroBackground()
        let heading = NSTextField(labelWithString: "应用使用情况")
        heading.font = .systemFont(ofSize: 21, weight: .semibold); heading.textColor = .white
        let subtitle = NSTextField(labelWithString: "最近打开时间来自系统记录，可能缺失或滞后")
        subtitle.textColor = NSColor.white.withAlphaComponent(0.7)
        filterMenu.addItems(withTitles: ["全部应用", "30 天及以上", "90 天及以上", "180 天及以上", "1 年及以上", "未记录", "正在运行"])
        filterMenu.target = self; filterMenu.action = #selector(applyFilter)
        search.placeholderString = "搜索应用名称或路径"; search.delegate = self
        refresh.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        refresh.imagePosition = .imageLeading; refresh.target = self; refresh.action = #selector(reload)
        reveal.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        reveal.imagePosition = .imageLeading; reveal.target = self; reveal.action = #selector(revealSelection)
        reveal.isEnabled = false
        uninstall.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        uninstall.imagePosition = .imageLeading; uninstall.target = self; uninstall.action = #selector(uninstallSelection)
        uninstall.toolTip = "使用 Mole 预览关联文件，再在终端中确认卸载。"
        uninstall.isEnabled = false
        let actions = NSStackView(views: [reveal, uninstall]); actions.spacing = 8
        status.textColor = .secondaryLabelColor
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.documentView = table; table.dataSource = self; table.delegate = self
        table.rowHeight = 40; table.style = .inset
        table.target = self; table.doubleAction = #selector(revealSelection)
        for (id, title, width) in [("name", "应用", 350), ("date", "最近记录", 150), ("age", "距离上次记录", 130)] {
            let col = NSTableColumn(identifier: .init(id)); col.title = title; col.width = CGFloat(width)
            col.minWidth = id == "name" ? 180 : 105
            table.addTableColumn(col)
        }
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        for view in [hero, filterMenu, search, refresh, scroll, status, actions] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view)
        }
        for view in [heading, subtitle] as [NSView] { view.translatesAutoresizingMaskIntoConstraints = false; hero.addSubview(view) }
        NSLayoutConstraint.activate([
            hero.topAnchor.constraint(equalTo: root.topAnchor), hero.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            hero.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            heading.topAnchor.constraint(equalTo: hero.topAnchor, constant: 20), heading.leadingAnchor.constraint(equalTo: hero.leadingAnchor, constant: 24),
            subtitle.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 5), subtitle.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            subtitle.bottomAnchor.constraint(equalTo: hero.bottomAnchor, constant: -20),
            filterMenu.topAnchor.constraint(equalTo: hero.bottomAnchor, constant: 14), filterMenu.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            refresh.centerYAnchor.constraint(equalTo: filterMenu.centerYAnchor), refresh.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            search.centerYAnchor.constraint(equalTo: filterMenu.centerYAnchor), search.trailingAnchor.constraint(equalTo: refresh.leadingAnchor, constant: -10),
            search.widthAnchor.constraint(equalToConstant: 230), search.leadingAnchor.constraint(greaterThanOrEqualTo: filterMenu.trailingAnchor, constant: 10),
            scroll.topAnchor.constraint(equalTo: filterMenu.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            scroll.bottomAnchor.constraint(equalTo: actions.topAnchor, constant: -12),
            actions.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20), actions.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -13),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24), status.centerYAnchor.constraint(equalTo: actions.centerYAnchor),
            status.trailingAnchor.constraint(lessThanOrEqualTo: actions.leadingAnchor, constant: -10)
        ])
    }

    func show() {
        window.center(); window.makeKeyAndOrderFront(nil)
        if !isLoading { reload() }
    }
    func windowWillClose(_ notification: Notification) {
        generation += 1; isLoading = false; refresh.isEnabled = true
        if let task = uninstallTask, task.isRunning { task.terminate() }
        uninstallTask = nil
    }

    @objc func reload() {
        generation += 1
        let run = generation, locations = roots, reader = metadata
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path })
        isLoading = true; refresh.isEnabled = false; uninstall.isEnabled = false
        status.stringValue = "正在读取应用和系统记录…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = AppInventory.read(roots: locations, runningPaths: running, lastUsed: reader)
            DispatchQueue.main.async {
                guard self.generation == run else { return }
                self.isLoading = false; self.refresh.isEnabled = true; self.inventory = result
                self.applyFilter()
            }
        }
    }
    @objc func applyFilter() {
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = filterMenu.indexOfSelectedItem
        visible = (inventory?.apps ?? []).filter { app in
            let matches = query.isEmpty || app.name.localizedCaseInsensitiveContains(query) ||
                app.url.path.localizedCaseInsensitiveContains(query)
            let days = app.daysSinceUse()
            switch selected {
            case 1...4:
                let limits = [1:30, 2:90, 3:180, 4:365]
                return matches && !app.running && (days.map { $0 >= limits[selected]! } ?? false)
            case 5: return matches && app.lastUsed == nil
            case 6: return matches && app.running
            default: return matches
            }
        }
        table.deselectAll(nil); table.reloadData(); reveal.isEnabled = false; uninstall.isEnabled = false
        let missing = inventory?.apps.filter { $0.lastUsed == nil }.count ?? 0
        let incomplete = inventory?.unreadableRoots.isEmpty == false ? " · 部分目录无法读取" : ""
        status.stringValue = "显示 \(visible.count) 项 · \(missing) 项无记录" + incomplete
        status.toolTip = "时间来自 macOS Spotlight，记录可能缺失或滞后。正在运行的应用不计入未使用天数。"
    }
    func controlTextDidChange(_ note: Notification) { applyFilter() }
    func numberOfRows(in tableView: NSTableView) -> Int { visible.count }
    func tableViewSelectionDidChange(_ notification: Notification) {
        let selected = visible.indices.contains(table.selectedRow)
        reveal.isEnabled = selected
        uninstall.isEnabled = selected && !isLoading && uninstallTask == nil
    }
    @objc func revealSelection() {
        guard visible.indices.contains(table.selectedRow) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([visible[table.selectedRow].url])
    }
    private func runningPaths() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path })
    }

    @objc func uninstallSelection() {
        guard visible.indices.contains(table.selectedRow), !isLoading, uninstallTask == nil, let inventory else { return }
        let app = visible[table.selectedRow]
        guard let executable = moleExecutables.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            showMessage("找不到 Mole", "请先安装 Mole。")
            return
        }
        let name = app.url.deletingPathExtension().lastPathComponent
        guard !name.isEmpty, !name.hasPrefix("-"), name.rangeOfCharacter(from: .controlCharacters) == nil else {
            showMessage("无法预览", "此应用名称无法安全传给 Mole。")
            return
        }
        let plan: AppRemovalPlan
        do {
            plan = try AppRemovalPlan.prepare(app: app, home: home, allowedRoots: uninstallRoots,
                                              inventory: inventory.apps, inventoryComplete: inventory.unreadableRoots.isEmpty,
                                              running: runningPaths(), isProtected: isProtected)
        } catch {
            showMessage("无法卸载", error.localizedDescription); return
        }
        let task = Process(), out = Pipe(), errors = Pipe()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = ["uninstall", "--dry-run", name]
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = out; task.standardError = errors
        var environment = ProcessInfo.processInfo.environment
        environment["MOLE_DRY_RUN"] = "1"; environment["NO_COLOR"] = "1"; environment["TERM"] = "dumb"
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        task.environment = environment
        do { try task.run() } catch { showMessage("无法启动 Mole", error.localizedDescription); return }
        uninstallTask = task; uninstall.isEnabled = false; status.stringValue = "Mole 正在预览卸载和关联文件…"
        DispatchQueue.global(qos: .userInitiated).async {
            let group = DispatchGroup(); group.enter()
            DispatchQueue.global(qos: .utility).async { _ = errors.fileHandleForReading.readDataToEndOfFile(); group.leave() }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit(); group.wait()
            let output = MoleUninstall.cleanOutput(String(decoding: data, as: UTF8.self))
            DispatchQueue.main.async {
                guard self.uninstallTask === task else { return }
                self.uninstallTask = nil; self.applyFilter()
                guard task.terminationStatus == 0,
                      MoleUninstall.verifiedPreview(output, app: plan.app, home: self.home) else {
                    self.showMessage("Mole 未能确认应用", "Mole 没有返回与所选路径一致的单个应用，或预览未完成。没有执行卸载。\n\n" + String(output.suffix(2000)))
                    return
                }
                do { try plan.verify(running: self.runningPaths(), isProtected: self.isProtected) }
                catch { self.showMessage("应用已变化", error.localizedDescription); return }
                self.showUninstallPreview(output, app: app, plan: plan, executable: executable, name: name)
            }
        }
    }

    private func showUninstallPreview(_ output: String, app: InstalledApp, plan: AppRemovalPlan,
                                      executable: String, name: String) {
        let alert = NSAlert()
        alert.messageText = "Mole 卸载预览：" + app.name
        alert.informativeText = "以下为 Mole 的预览。继续将在终端重新扫描，需你再次核对应用路径和每个文件后确认。Mole 不读取盘览的自定义保护范围；不要确认包含受保护文件的清单。个人数据默认保留。"
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 560, height: 260))
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        let text = NSTextView(frame: scroll.bounds); text.isEditable = false; text.isSelectable = true
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        text.string = output; text.isVerticallyResizable = true; text.textContainer?.widthTracksTextView = true
        scroll.documentView = text; alert.accessoryView = scroll
        alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "在终端继续…")
        alert.beginSheetModal(for: window) { result in
            guard result == .alertSecondButtonReturn else { return }
            do {
                try plan.verify(running: self.runningPaths(), isProtected: self.isProtected)
                let script = try MoleUninstall.commandScript(executable: executable, appName: name)
                let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
                NSWorkspace.shared.open([script], withApplicationAt: terminal,
                                        configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    if let error {
                        try? FileManager.default.removeItem(at: script.deletingLastPathComponent())
                        DispatchQueue.main.async { self.showMessage("无法打开终端", error.localizedDescription) }
                    }
                }
            } catch { self.showMessage("无法继续", error.localizedDescription) }
        }
    }

    private func showMessage(_ title: String, _ text: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = text
        alert.addButton(withTitle: "好"); alert.beginSheetModal(for: window)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier, visible.indices.contains(row) else { return nil }
        let app = visible[row]
        if id.rawValue == "name" {
            let cell = tableView.makeView(withIdentifier: id, owner: nil) as? AppUsageCell ?? AppUsageCell()
            cell.identifier = id; cell.text.stringValue = app.name
            cell.icon.image = NSWorkspace.shared.icon(forFile: app.url.path)
            cell.toolTip = app.url.path
            return cell
        }
        let field = tableView.makeView(withIdentifier: id, owner: nil) as? NSTextField ?? NSTextField(labelWithString: "")
        field.identifier = id; field.textColor = .secondaryLabelColor
        field.font = .systemFont(ofSize: 12)
        field.stringValue = id.rawValue == "date" ? app.lastUsed.map { dateFormatter.string(from: $0) } ?? "未记录" : app.ageDescription()
        field.toolTip = app.running ? "应用当前正在运行；最近记录可能未及时更新" : nil
        return field
    }
}

private final class AppUsageCell: NSView {
    let icon = NSImageView(), text = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        icon.imageScaling = .scaleProportionallyUpOrDown
        text.font = .systemFont(ofSize: 13, weight: .medium); text.lineBreakMode = .byTruncatingTail
        for view in [icon, text] as [NSView] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10), icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 27), icon.heightAnchor.constraint(equalToConstant: 27),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10), text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}
