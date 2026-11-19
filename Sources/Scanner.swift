import Foundation
import Darwin

// A separate process group lets the window cancel Mole and its shell helpers together.
func spawnPreview(_ executable: String) throws -> pid_t {
    var actions: posix_spawn_file_actions_t?
    var attrs: posix_spawnattr_t?
    func check(_ code: Int32) throws {
        if code != 0 { throw DeskError(String(cString: strerror(code))) }
    }
    try check(posix_spawn_file_actions_init(&actions))
    defer { posix_spawn_file_actions_destroy(&actions) }
    try check(posix_spawnattr_init(&attrs))
    defer { posix_spawnattr_destroy(&attrs) }
    try check(posix_spawnattr_setflags(&attrs, Int16(POSIX_SPAWN_SETPGROUP)))
    try check(posix_spawnattr_setpgroup(&attrs, 0))
    for fd: Int32 in [0, 1, 2] {
        try check(posix_spawn_file_actions_addopen(&actions, fd, "/dev/null",
                                                  fd == 0 ? O_RDONLY : O_WRONLY, 0))
    }
    var env = ProcessInfo.processInfo.environment
    env["MOLE_DRY_RUN"] = "1"
    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    env["NO_COLOR"] = "1"
    let arguments: [String] = [executable, "clean", "--dry-run"]
    var argv = arguments.map { text in text.withCString { strdup($0) } } + [nil]
    var envp = env.map { strdup($0.key + "=" + $0.value) } + [nil]
    defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
    var pid: pid_t = 0
    try check(posix_spawn(&pid, executable, &actions, &attrs, &argv, &envp))
    return pid
}
