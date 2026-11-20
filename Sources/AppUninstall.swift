import Foundation
import Darwin

struct AppIdentity: Equatable {
    let device: dev_t
    let inode: ino_t

    static func read(_ url: URL) throws -> AppIdentity {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw DeskError("项目已不存在：\n" + url.path) }
        return AppIdentity(device: info.st_dev, inode: info.st_ino)
    }
}

struct AppRemovalPlan {
    let app: URL
    let identifier: String?
    let appIdentity: AppIdentity
    let infoIdentity: AppIdentity
    let infoData: Data
    let cache: URL?
    let cacheIdentity: AppIdentity?

    static func prepare(app: InstalledApp, home: URL, allowedRoots: [URL],
                        inventory: [InstalledApp], inventoryComplete: Bool, running: Set<String>,
                        isProtected: (String) -> Bool) throws -> AppRemovalPlan {
        let url = app.url.standardizedFileURL
        let path = url.path
        guard url.pathExtension.lowercased() == "app", url.resolvingSymlinksInPath().path == path,
              allowedRoots.contains(where: { root in
                  let prefix = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
                  guard path.hasPrefix(prefix) else { return false }
                  let parents = path.dropFirst(prefix.count).split(separator: "/").dropLast()
                  return !parents.contains(where: { $0.lowercased().hasSuffix(".app") })
              }),
              !isProtected(path), !running.contains(path) else {
            throw DeskError("此应用不在可卸载的应用目录中、处于保护范围或正在运行。")
        }
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true,
              let bundle = Bundle(url: url),
              let info = bundle.infoDictionary, info["CFBundlePackageType"] as? String == "APPL" else {
            throw DeskError("应用已变化或无法读取。请刷新列表。")
        }
        let id = bundle.bundleIdentifier
        if id?.lowercased().hasPrefix("com.apple.") == true || id == "local.lan.MoleDesk" {
            throw DeskError("系统应用和盘览本身无法从此处卸载。")
        }
        let appID = try AppIdentity.read(url)
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        let infoID = try AppIdentity.read(infoURL)
        guard infoURL.resolvingSymlinksInPath().path == infoURL.path else {
            throw DeskError("应用信息文件不是普通文件，请在 Finder 中检查。")
        }
        let infoData = try Data(contentsOf: infoURL)
        var cache: URL?, cacheID: AppIdentity?
        if inventoryComplete, let id, !id.isEmpty,
           id.range(of: "^[A-Za-z0-9][A-Za-z0-9.-]*$", options: .regularExpression) != nil,
           inventory.filter({ Bundle(url: $0.url)?.bundleIdentifier?.caseInsensitiveCompare(id) == .orderedSame }).count == 1 {
            let candidate = home.appendingPathComponent("Library/Caches", isDirectory: true).appendingPathComponent(id)
            if FileManager.default.fileExists(atPath: candidate.path),
               candidate.standardizedFileURL.resolvingSymlinksInPath().path == candidate.path,
               !isProtected(candidate.path) {
                cache = candidate; cacheID = try AppIdentity.read(candidate)
            }
        }
        return AppRemovalPlan(app: url, identifier: id, appIdentity: appID, infoIdentity: infoID, infoData: infoData,
                              cache: cache, cacheIdentity: cacheID)
    }

    func verify(running: Set<String>, isProtected: (String) -> Bool) throws {
        guard !running.contains(app.path), !isProtected(app.path),
              app.resolvingSymlinksInPath().path == app.path,
              try AppIdentity.read(app) == appIdentity,
              try AppIdentity.read(app.appendingPathComponent("Contents/Info.plist")) == infoIdentity,
              try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")) == infoData,
              Bundle(url: app)?.bundleIdentifier == identifier else {
            throw DeskError("应用状态已变化或正在运行，请刷新列表。")
        }
    }

    func verifyCache(isProtected: (String) -> Bool) throws {
        guard let cache, let cacheIdentity, !isProtected(cache.path),
              cache.resolvingSymlinksInPath().path == cache.path,
              try AppIdentity.read(cache) == cacheIdentity else {
            throw DeskError("缓存目录已变化或属于保护范围。")
        }
    }
}

// Mole 1.72 exposes a text preview; do not proceed if its selected app cannot be verified.
enum MoleUninstall {
    static func cleanOutput(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{1b}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
    }

    static func verifiedPreview(_ text: String, app: URL, home: URL) -> Bool {
        let clean = cleanOutput(text)
        guard clean.contains("Matched 1 app(s):"), clean.contains("Files to be removed:") else { return false }
        let path = app.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        let shown = path.hasPrefix(homePath + "/") ? "~" + path.dropFirst(homePath.count) : path
        return clean.components(separatedBy: .newlines).contains { line in
            guard let range = line.range(of: shown) else { return false }
            let before = line[..<range.lowerBound]
            let after = line[range.upperBound...]
            return (before.isEmpty || before.last?.isWhitespace == true) &&
                   (after.isEmpty || after.first?.isWhitespace == true || after.first == ",")
        }
    }

    static func commandScript(executable: String, appName: String) throws -> URL {
        guard !appName.isEmpty, !appName.hasPrefix("-"), appName.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw DeskError("此应用名称无法安全传给 Mole。")
        }
        func quote(_ string: String) -> String { "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("moledesk-uninstall-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        let script = folder.appendingPathComponent("Mole-Uninstall.command")
        let body = "#!/bin/bash\n/bin/rm -f -- \"$0\"\n/bin/rmdir -- \"$(dirname \"$0\")\" 2>/dev/null || true\nexec " + quote(executable) + " uninstall " + quote(appName) + "\n"
        do {
            try Data(body.utf8).write(to: script, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            return script
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }
}
