import Foundation
@main struct TrashCheck {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("moledesk-trash-test-" + UUID().uuidString).resolvingSymlinksInPath()
        let cache = root.appendingPathComponent("Library/Caches/pip")
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let testFile = cache.appendingPathComponent("test.txt")
        try Data("test".utf8).write(to: testFile)
        try TrashPolicy.validate(cache.path, home: root.path)
        var moved: NSURL?
        try fm.trashItem(at: cache, resultingItemURL: &moved)
        guard let moved = moved as URL? else { throw DeskError("未获得废纸篓路径") }
        guard !fm.fileExists(atPath: cache.path), fm.fileExists(atPath: moved.appendingPathComponent("test.txt").path) else {
            throw DeskError("废纸篓移动验证失败")
        }
        try fm.moveItem(at: moved, to: cache)
        let contents = try String(contentsOf: testFile, encoding: .utf8)
        precondition(contents == "test")
        print("Temporary cache moved to Trash and restored successfully.")
    }
}
