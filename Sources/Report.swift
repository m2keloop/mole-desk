import Foundation

let categoryNames = [
    "User essentials": "用户缓存与日志", "App caches": "应用缓存", "Browsers": "浏览器",
    "Developer tools": "开发工具", "Apps & utilities": "软件与实用工具",
    "Application Support": "应用支持文件", "App leftovers": "卸载残留"
]

struct Entry {
    let path: String
    let group: String
    let size: String
    let bytes: Double?
    let canReviewForTrash: Bool
    var name: String {
        if path.contains("/Chrome/") && path.contains("/Service Worker/CacheStorage/") { return "Chrome 网站离线缓存" }
        if path.contains("/Notion/") && path.contains("/Service Worker/CacheStorage/") { return "Notion 离线缓存" }
        if path.contains("/GoogleUpdater/crx_cache/") { return "Google 更新包" }
        let leaf = (path as NSString).lastPathComponent
        switch leaf {
        case "LarkShell": return "飞书 · LarkShell"
        case "com.tencent.workbuddy.mac.BundleMigration": return "WorkBuddy 更新备份"
        case "videoCache" where path.contains("/Quark/"): return "夸克视频缓存"
        default: return leaf
        }
    }
}

struct Report {
    let entries: [Entry]
    let total: String
    let count: Int
    let date: String

    static func parse(_ text: String, home: String, completedScan: Bool = false) throws -> Report {
        var entries = [Entry]()
        var group = "", total = "", date = ""
        var count: Int?
        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("# Mole Cleanup Preview - ") {
                date = String(line.dropFirst("# Mole Cleanup Preview - ".count))
            } else if line.hasPrefix("# Potential cleanup: ") {
                total = String(line.dropFirst("# Potential cleanup: ".count))
            } else if line.hasPrefix("# Items: ") {
                count = Int(line.dropFirst("# Items: ".count))
            } else if line.hasPrefix("=== "), line.hasSuffix(" ===") {
                group = String(line.dropFirst(4).dropLast(4))
            } else if !group.isEmpty, line.hasPrefix("/"), let split = line.range(of: "  # ", options: .backwards) {
                let note = line[split.upperBound...]
                if note.contains(", counted under ") { continue }
                let size = String(note.prefix { $0 != "," })
                let path = String(line[..<split.lowerBound])
                entries.append(Entry(path: path, group: group, size: size == "size unknown" ? "待测量" : size,
                                     bytes: parseBytes(size), canReviewForTrash: TrashPolicy.kind(path, home: home) != nil))
            }
        }
        if completedScan, !date.isEmpty, group.isEmpty, entries.isEmpty, count == nil, total.isEmpty {
            return Report(entries: [], total: "0 B", count: 0, date: date)
        }
        guard !date.isEmpty, let count, !total.isEmpty else {
            throw DeskError("预览清单尚未写完，或当前 Mole 的清单格式有变化。")
        }
        entries.sort {
            if $0.bytes != $1.bytes { return ($0.bytes ?? -1) > ($1.bytes ?? -1) }
            return $0.path < $1.path
        }
        return Report(entries: entries, total: total, count: count, date: date)
    }

    private static func parseBytes(_ s: String) -> Double? {
        for (suffix, multiplier) in [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("KB", 1e3), ("B", 1.0)] {
            if s.hasSuffix(suffix) { return Double(s.dropLast(suffix.count)).map { $0 * multiplier } }
        }
        return nil
    }
}

struct DeskError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum TrashPolicy {
    enum Kind { case cache, cursor, vscode }

    static func kind(_ path: String, home: String) -> Kind? {
        guard path.hasPrefix(home + "/"), !path.contains("//"), !path.hasSuffix("/"),
              !path.components(separatedBy: "/").contains(where: { $0 == "." || $0 == ".." }),
              path.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        let rel = String(path.dropFirst(home.count + 1))
        let parts = rel.components(separatedBy: "/")
        if parts.count == 3 && parts[1] == "extensions" && !parts[2].hasPrefix(".") {
            if parts[0] == ".cursor" { return .cursor }
            if parts[0] == ".vscode" { return .vscode }
        }
        if parts.count >= 3 && parts[0] == "Library" && parts[1] == "Caches" { return .cache }
        if parts.count >= 3 && parts[0] == ".npm" && parts[1] == "_cacache" { return .cache }
        if parts.count >= 5 && parts[0] == "Library" && parts[1] == "Application Support" {
            let names = Set(["Cache", "Cache_Data", "videoCache", "Service Worker", "CachedData", "Code Cache", "crx_cache"])
            if parts.dropFirst(3).contains(where: { names.contains($0) }) { return .cache }
        }
        if parts.count >= 6 && parts[0] == "Library" && parts[1] == "Containers" &&
            parts[3] == "Data" &&
            (parts[4] == "tmp" || (parts[4] == "Library" && parts[5] == "Caches")) { return .cache }
        return nil
    }

    static func validate(_ path: String, home: String) throws {
        let url = URL(fileURLWithPath: path)
        guard let kind = kind(path, home: home),
              url.resolvingSymlinksInPath().path == path,
              FileManager.default.fileExists(atPath: path) else {
            throw DeskError("路径已变化或超出可处理范围。\n" + path)
        }
        if kind == .cache { return }
        let parent = url.deletingLastPathComponent(), name = url.lastPathComponent
        let flags = try JSONDecoder().decode([String: Bool].self,
            from: Data(contentsOf: parent.appendingPathComponent(".obsolete")))
        struct Installed: Decodable { let relativeLocation: String }
        let installed = try JSONDecoder().decode([Installed].self,
            from: Data(contentsOf: parent.appendingPathComponent("extensions.json")))
        guard flags[name] == true, !installed.contains(where: { $0.relativeLocation == name }) else {
            throw DeskError("编辑器当前未将此版本标为可移除。\n" + path)
        }
    }
}
