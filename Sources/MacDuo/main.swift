import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = AppController()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // 菜单栏常驻，不进 Dock、不抢焦点
let delegate = AppDelegate()
app.delegate = delegate
app.run()
