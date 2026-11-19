import AppKit

let app = NSApplication.shared
let delegate = Desk()
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
