import Foundation
import Darwin

@main struct Checks {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("moledesk-check-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let base = root.resolvingSymlinksInPath().path
        let header = "# Mole Cleanup Preview - 2026-11-19 12:00:00"
        let fixture = """
        \(header)
        === User essentials ===
        \(base)/Library/Caches/pip  # 123.4MB
        \(base)/Library/Caches/pip/http  # 12MB, counted under \(base)/Library/Caches/pip
        \(base)/Documents/example  # size unknown
        # Potential cleanup: 123.4MB+
        # Items: 2
        # Categories: 1
        """
        let report = try Report.parse(fixture, home: base)
        precondition(report.entries.count == 2 && report.count == 2 && report.total == "123.4MB+")
        precondition(report.entries[0].canReviewForTrash && !report.entries[1].canReviewForTrash)
        precondition(report.entries[0].bytes == 123_400_000 && report.entries[1].bytes == nil)
        precondition((try? Report.parse(header, home: base)) == nil)
        let empty = try Report.parse(header, home: base, completedScan: true)
        precondition(empty.count == 0)
        for path in ["/", "/tmp", base+"/go/pkg/mod", base+"/Library/Containers/com.tencent.xinWeChat",
                     base+"/Documents/example", base+"/Library/Caches/../Caches/pip"] {
            precondition(TrashPolicy.kind(path, home: base) == nil)
        }
        let ext = URL(fileURLWithPath: base + "/.cursor/extensions/example.extension-1.0")
        let registry = ext.deletingLastPathComponent()
        try fm.createDirectory(at: ext, withIntermediateDirectories: true)
        try Data(#"{"example.extension-1.0":true}"#.utf8).write(to: registry.appendingPathComponent(".obsolete"))
        try Data("[]".utf8).write(to: registry.appendingPathComponent("extensions.json"))
        try TrashPolicy.validate(ext.path, home: base)
        try Data(#"[{"relativeLocation":"example.extension-1.0"}]"#.utf8).write(to: registry.appendingPathComponent("extensions.json"))
        precondition((try? TrashPolicy.validate(ext.path, home: base)) == nil)
        let dir = URL(fileURLWithPath: base+"/Library/Caches")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: dir.appendingPathComponent("pip"), withDestinationURL: ext)
        precondition((try? TrashPolicy.validate(dir.appendingPathComponent("pip").path, home: base)) == nil)
        let exe = root.appendingPathComponent("mo-test")
        try Data("#!/bin/sh\ntest \"$#\" = 2 && test \"$1\" = clean && test \"$2\" = --dry-run && test \"$MOLE_DRY_RUN\" = 1\n".utf8).write(to: exe)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: exe.path)
        let pid = try spawnPreview(exe.path)
        precondition(getpgid(pid) == pid)
        var status: Int32 = 0
        precondition(waitpid(pid,&status,0) == pid && status == 0)
        print("Report, protected paths, obsolete extension checks and dry-run process passed.")
    }
}
