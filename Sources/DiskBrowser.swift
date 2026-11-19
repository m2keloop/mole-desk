import AppKit
import Darwin

final class DiskBrowser: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    struct Item { let path: String; let bytes: Int64; let isDirectory: Bool }
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 530),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
    private let table = NSTableView(), pathLabel = NSTextField(labelWithString: "")
    let state = NSTextField(labelWithString: "")
    private let up = NSButton(title: "上一级", target: nil, action: nil)
    private let disk = NSButton(title: "启动磁盘", target: nil, action: nil)
    private let choose = NSButton(title: "选择目录…", target: nil, action: nil)
    private let reveal = NSButton(title: "在 Finder 显示", target: nil, action: nil)
    var items: [Item] = []
    private var current = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    var task: Process?
    private var generation = 0

    override init() {
        super.init()
        window.title = "磁盘分析"; window.delegate = self; window.minSize = NSSize(width: 600, height: 360)
        let root = WindowBackground()
        window.contentView = root
        let hero = HeroBackground()
        let heading = NSTextField(labelWithString: "磁盘分析")
        heading.font = .systemFont(ofSize: 21, weight: .semibold); heading.textColor = .white
        pathLabel.lineBreakMode = .byTruncatingMiddle; pathLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        state.textColor = .secondaryLabelColor
        up.target = self; up.action = #selector(goUp)
        choose.target = self; choose.action = #selector(chooseFolder)
        disk.target = self; disk.action = #selector(showDiskRoot)
        reveal.target = self; reveal.action = #selector(showItem)
        for (button, name) in [(up,"chevron.up"), (disk,"internaldrive"), (choose,"folder"), (reveal,"arrow.up.forward")] {
            button.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            button.imagePosition = .imageLeading
        }
        let buttons = NSStackView(views: [up, disk, choose, reveal]); buttons.spacing = 8
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.documentView = table
        table.dataSource = self; table.delegate = self; table.rowHeight = 40
        table.target = self; table.doubleAction = #selector(openItem)
        for (id, title, width) in [("name", "项目", 470), ("size", "占用", 130)] {
            let col = NSTableColumn(identifier: .init(id)); col.title = title; col.width = CGFloat(width)
            table.addTableColumn(col)
        }
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        for view in [hero, buttons, scroll, state] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view)
        }
        for view in [heading, pathLabel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false; hero.addSubview(view)
        }
        NSLayoutConstraint.activate([
            hero.topAnchor.constraint(equalTo: root.topAnchor), hero.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            hero.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            heading.topAnchor.constraint(equalTo: hero.topAnchor, constant: 20),
            heading.leadingAnchor.constraint(equalTo: hero.leadingAnchor, constant: 24),
            pathLabel.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 5),
            pathLabel.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            pathLabel.trailingAnchor.constraint(equalTo: hero.trailingAnchor, constant: -24),
            pathLabel.bottomAnchor.constraint(equalTo: hero.bottomAnchor, constant: -20),
            buttons.topAnchor.constraint(equalTo: hero.bottomAnchor, constant: 14),
            buttons.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            scroll.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            scroll.bottomAnchor.constraint(equalTo: state.topAnchor, constant: -8),
            state.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            state.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            state.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14)
        ])
    }

    func show() {
        window.center(); window.makeKeyAndOrderFront(nil)
        if items.isEmpty && task == nil { scan(current) }
    }
    func windowWillClose(_ notification: Notification) { generation += 1; task?.terminate(); task = nil }
    @objc private func chooseFolder() {
        let picker = NSOpenPanel()
        picker.canChooseFiles = false; picker.canChooseDirectories = true
        picker.canCreateDirectories = false; picker.allowsMultipleSelection = false
        picker.directoryURL = current
        picker.beginSheetModal(for: window) { [weak self] result in
            if result == .OK, let url = picker.url { self?.scan(url) }
        }
    }
    @objc private func showDiskRoot() {
        scan(URL(fileURLWithPath: "/System/Volumes/Data", isDirectory: true))
    }
    @objc private func goUp() {
        let parent = current.deletingLastPathComponent()
        if parent.path != current.path { scan(parent) }
    }
    @objc private func openItem() {
        guard table.selectedRow >= 0, table.selectedRow < items.count else { return }
        let url = URL(fileURLWithPath: items[table.selectedRow].path)
        var directory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue {
            scan(url)
        } else { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
    @objc private func showItem() {
        guard table.selectedRow >= 0, table.selectedRow < items.count else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: items[table.selectedRow].path)])
    }

    func scan(_ url: URL) {
        generation += 1
        let run = generation
        if let task, task.isRunning { task.terminate() }
        task = nil
        current = url.standardizedFileURL
        pathLabel.stringValue = current.path
        items = []; table.reloadData()
        state.stringValue = "正在统计…"
        let path = current.path
        let process = Process(), out = Pipe(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-kx", "-d", "1", path]
        process.standardOutput = out; process.standardError = errors
        do { try process.run(); task = process } catch {
            state.stringValue = "无法启动统计：" + error.localizedDescription
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let group = DispatchGroup()
            group.enter()
            var errorData = Data()
            DispatchQueue.global(qos: .utility).async { errorData = errors.fileHandleForReading.readDataToEndOfFile(); group.leave() }
            let output = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            group.wait()
            var found = [Item]()
            for line in String(decoding: output, as: UTF8.self).split(separator: "\n") {
                guard let tab = line.firstIndex(of: "\t"), let kb = Int64(line[..<tab]) else { continue }
                let item = String(line[line.index(after: tab)...])
                if item != path { found.append(Item(path: item, bytes: kb * 1024, isDirectory: true)) }
            }
            var listingFailed = false
            do {
                let children = try FileManager.default.contentsOfDirectory(atPath: path)
                for name in children {
                    let child = URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent(name).path
                    var details = stat()
                    guard lstat(child, &details) == 0 else { listingFailed = true; continue }
                    if (details.st_mode & S_IFMT) != S_IFDIR {
                        found.append(Item(path: child, bytes: Int64(details.st_blocks) * 512, isDirectory: false))
                    }
                }
            } catch { listingFailed = true }
            found.sort { $0.bytes > $1.bytes }
            let status = process.terminationStatus
            let hadErrors = !errorData.isEmpty || listingFailed
            DispatchQueue.main.async {
                guard run == self.generation else { return }
                self.task = nil
                self.items = found; self.table.reloadData()
                self.state.stringValue = status == 0 && !hadErrors
                    ? "共 \(found.count) 项 · 双击目录查看下一级"
                    : "部分目录无法读取，结果可能不完整 · 共 \(found.count) 项"
            }
        }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { items.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier, items.indices.contains(row) else { return nil }
        let item = items[row]
        if id.rawValue == "name" {
            let cell = tableView.makeView(withIdentifier: id, owner: nil) as? DiskItemCell ?? DiskItemCell()
            cell.identifier = id; cell.text.stringValue = (item.path as NSString).lastPathComponent
            cell.icon.image = NSImage(systemSymbolName: item.isDirectory ? "folder.fill" : "doc", accessibilityDescription: nil)
            cell.toolTip = item.path
            return cell
        }
        let field = tableView.makeView(withIdentifier: id, owner: nil) as? NSTextField ?? NSTextField(labelWithString: "")
        field.identifier = id; field.stringValue = displaySize(Double(item.bytes))
        field.textColor = .secondaryLabelColor; field.alignment = .right
        field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        return field
    }
}

private final class DiskItemCell: NSView {
    let icon = NSImageView(), text = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        icon.contentTintColor = NSColor(calibratedRed: 0.19, green: 0.55, blue: 0.53, alpha: 1)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        text.font = .systemFont(ofSize: 13, weight: .medium); text.lineBreakMode = .byTruncatingMiddle
        for view in [icon, text] as [NSView] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18), icon.heightAnchor.constraint(equalToConstant: 18),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 11),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}
