import AppKit
import WebKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var browsers: [BrowserWindowController] = []

    private var activeBrowser: BrowserWindowController? {
        if let keyWindow = NSApp.keyWindow,
           let match = browsers.first(where: { $0.window === keyWindow }) { return match }
        return browsers.last
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "Montclair", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        let privacyTest = ProcessInfo.processInfo.arguments.contains("--privacy-test")
        let browser = makeBrowser(privateBrowsing: privacyTest)
        configureMenu()
        NSApp.activate(ignoringOtherApps: true)
        if ProcessInfo.processInfo.arguments.contains("--feature-test") {
            browser.runFeatureTest()
        }
        if privacyTest {
            browser.runPrivacyFeatureTest()
        }
        if ProcessInfo.processInfo.arguments.contains("--benchmark") {
            browser.runBenchmark()
        }
        if ProcessInfo.processInfo.arguments.contains("--self-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.activeBrowser?.runInteractionSmokeTest()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { browsers.forEach { $0.saveSession() } }

    @discardableResult
    private func makeBrowser(privateBrowsing: Bool) -> BrowserWindowController {
        let controller = BrowserWindowController(privateBrowsing: privateBrowsing)
        controller.onWindowClose = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.browsers.removeAll { $0 === controller }
        }
        browsers.append(controller)
        controller.showWindow(nil)
        return controller
    }

    private func configureMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Montclair", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem()
        main.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Tab", action: #selector(newTab), keyEquivalent: "t").target = self
        let privateWindow = fileMenu.addItem(withTitle: "New Private Window", action: #selector(newPrivateWindow), keyEquivalent: "n")
        privateWindow.target = self
        privateWindow.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(withTitle: "Close Tab", action: #selector(closeTab), keyEquivalent: "w").target = self
        fileItem.submenu = fileMenu

        let bookmarksItem = NSMenuItem()
        let bookmarksMenu = NSMenu(title: "Bookmarks")
        bookmarksMenu.addItem(withTitle: "Add / Remove Bookmark", action: #selector(toggleBookmark), keyEquivalent: "d").target = self
        bookmarksMenu.addItem(withTitle: "Show Bookmarks", action: #selector(showBookmarks), keyEquivalent: "").target = self
        bookmarksItem.submenu = bookmarksMenu
        main.addItem(bookmarksItem)

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Find on Page", action: #selector(findOnPage), keyEquivalent: "f").target = self
        editItem.submenu = editMenu

        let goItem = NSMenuItem()
        main.addItem(goItem)
        let goMenu = NSMenu(title: "Go")
        goMenu.addItem(withTitle: "Open Location", action: #selector(openLocation), keyEquivalent: "l").target = self
        goMenu.addItem(withTitle: "Reload Page", action: #selector(reloadPage), keyEquivalent: "r").target = self
        let back = goMenu.addItem(withTitle: "Back", action: #selector(goBack), keyEquivalent: "[")
        back.target = self; back.keyEquivalentModifierMask = [.command]
        let forward = goMenu.addItem(withTitle: "Forward", action: #selector(goForward), keyEquivalent: "]")
        forward.target = self; forward.keyEquivalentModifierMask = [.command]
        goMenu.addItem(.separator())
        for index in 0..<9 {
            let item = goMenu.addItem(withTitle: "Select Tab \(index + 1)", action: #selector(selectTabFromMenu(_:)), keyEquivalent: "\(index + 1)")
            item.target = self
            item.tag = index
        }
        goItem.submenu = goMenu
        NSApp.mainMenu = main
    }

    @objc private func newTab() { activeBrowser?.createNewTab() }
    @objc private func newPrivateWindow() { makeBrowser(privateBrowsing: true) }
    @objc private func toggleBookmark() { activeBrowser?.toggleCurrentBookmark() }
    @objc private func showBookmarks() { activeBrowser?.showBookmarks() }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleBookmark) {
            menuItem.title = activeBrowser?.currentPageIsBookmarked == true ? "Remove Bookmark" : "Bookmark This Page"
            return activeBrowser?.canBookmarkCurrentPage == true
        }
        if menuItem.action == #selector(showBookmarks) { return activeBrowser?.canShowBookmarks == true }
        return true
    }
    @objc private func closeTab() { activeBrowser?.closeCurrentTab() }
    @objc private func openLocation() { activeBrowser?.focusAddressBar() }
    @objc private func reloadPage() { activeBrowser?.reloadCurrentPage() }
    @objc private func goBack() { activeBrowser?.navigateBack() }
    @objc private func goForward() { activeBrowser?.navigateForward() }
    @objc private func findOnPage() { activeBrowser?.focusPageSearch() }
    @objc private func selectTabFromMenu(_ sender: NSMenuItem) { activeBrowser?.selectTab(at: sender.tag) }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
