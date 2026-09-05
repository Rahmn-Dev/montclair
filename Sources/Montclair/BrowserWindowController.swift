import AppKit
import WebKit

@MainActor
private func glassSurface(content: NSView, radius: CGFloat, tint: NSColor) -> NSView {
    if #available(macOS 26.0, *) {
        let glass = NSGlassEffectView()
        glass.cornerRadius = radius
        glass.tintColor = tint
        glass.contentView = content
        return glass
    }
    let effect = NSVisualEffectView()
    effect.material = .hudWindow
    effect.blendingMode = .withinWindow
    effect.state = .active
    effect.wantsLayer = true
    effect.layer?.cornerRadius = radius
    effect.layer?.masksToBounds = true
    content.frame = effect.bounds
    content.autoresizingMask = [.width, .height]
    effect.addSubview(content)
    return effect
}

@MainActor
final class BrowserWindowController: NSWindowController, NSTextFieldDelegate, NSWindowDelegate {
    static var compiledBlocker: WKContentRuleList?

    private let root = WindowRootView(), content = NSView(), toolbarContent = NSView(), dockContent = HoverView(), trafficContent = NSView(), rightContent = NSView()
    private lazy var toolbar = toolbarContent
    private lazy var dock = glassSurface(
        content: dockContent,
        radius: 30,
        tint: isPrivateBrowsing ? NSColor(hex: 0x101722, alpha: 0.86) : NSColor(hex: 0xF6F1E7, alpha: 0.62)
    )
    private lazy var traffic = glassSurface(
        content: trafficContent,
        radius: 23,
        tint: isPrivateBrowsing ? NSColor(hex: 0x111823, alpha: 0.88) : NSColor.white.withAlphaComponent(0.25)
    )
    private let header = NSVisualEffectView()
    private var chromeSurfaces: [NSView] = []
    private let navigationDivider = NSView()
    private var addressSurface: NSView!
    private lazy var rightControls = glassSurface(
        content: rightContent,
        radius: 23,
        tint: isPrivateBrowsing ? NSColor(hex: 0x111823, alpha: 0.88) : NSColor(hex: 0xF6F1E7, alpha: 0.72)
    )
    private let address = AddressField(), back = HoverIconButton(), forward = HoverIconButton(), reload = HoverIconButton()
    private let history = HoverIconButton(), downloads = HoverIconButton(), customize = HoverIconButton()
    private let newTab = HoverIconButton(), closeTab = HoverIconButton(), dockPlus = NSButton(), dockPlusHost = NSView()
    private let loadingRing = AddressLoadingRing()
    let isPrivateBrowsing: Bool
    private let websiteDataStore: WKWebsiteDataStore
    var onWindowClose: (() -> Void)?
    private var addressIsEditing = false
    private var addressTargetFrame = NSRect.zero
    private let dockPlusIcon = NSImageView()
    private var tabButtons: [NSButton] = []
    private var tabs: [BrowserTab] = []
    private var selectedIndex = 0
    private var isDockCollapsed = false
    private var toolbarPreferredWidth: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: "MontclairToolbarWidth")
        return saved > 0 ? CGFloat(saved) : 1080
    }()
    private var suspensionTimer: Timer?
    private var restoringSession = false
    private var libraryPanel: LibraryPanel?
    private let testing = ProcessInfo.processInfo.arguments.contains("--self-test") || ProcessInfo.processInfo.arguments.contains("--benchmark") || ProcessInfo.processInfo.arguments.contains("--feature-test") || ProcessInfo.processInfo.arguments.contains("--privacy-test")
    private lazy var library: BrowserLibrary = {
        let base = testing
            ? FileManager.default.temporaryDirectory.appendingPathComponent("Montclair-tests-\(ProcessInfo.processInfo.processIdentifier)")
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Montclair")
        return BrowserLibrary(file: base.appendingPathComponent("library.json"))
    }()
    private var restoresTabs: Bool { testing || !UserDefaults.standard.bool(forKey: "MontclairDisableRestore") }
    private var recordsHistory: Bool { testing || !UserDefaults.standard.bool(forKey: "MontclairDisableHistory") }
    private var bookmarksEnabled: Bool { !UserDefaults.standard.bool(forKey: "MontclairDisableBookmarks") }

    convenience init(privateBrowsing: Bool = false) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = privateBrowsing ? "Private Browsing — Montclair" : "Montclair"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        if privateBrowsing { window.appearance = NSAppearance(named: .darkAqua) }
        window.backgroundColor = privateBrowsing ? NSColor(hex: 0x090C12) : NSColor(hex: 0xEDE7DC)
        window.minSize = NSSize(width: 760, height: 500)
        window.center()
        self.init(window: window, privateBrowsing: privateBrowsing)
    }

    private init(window: NSWindow, privateBrowsing: Bool) {
        isPrivateBrowsing = privateBrowsing
        websiteDataStore = privateBrowsing ? .nonPersistent() : .default()
        super.init(window: window)
        window.delegate = self
        root.onTitlebarDoubleClick = { [weak self] in self?.window?.zoom(nil) }
        configureUI()
        restoreSession()
        ContentBlocker.install { [weak self] in self?.installBlockerOnExistingTabs() }
        suspensionTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.suspendBackgroundTabs() }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configureUI() {
        guard let window else { return }
        window.contentView = root
        root.wantsLayer = true
        root.layer?.backgroundColor = (isPrivateBrowsing ? NSColor(hex: 0x090C12) : NSColor(hex: 0xEDE7DC)).cgColor
        content.wantsLayer = true
        content.layer?.backgroundColor = (isPrivateBrowsing ? NSColor(hex: 0x11151C) : NSColor(hex: 0xF3F0E9)).cgColor
        content.layer?.cornerRadius = 26
        content.layer?.masksToBounds = true
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { window.standardWindowButton($0)?.isHidden = true }
        let trafficColors = [0xFF5F57, 0xFEBB2E, 0x28C840]
        let trafficSymbols = ["xmark", "minus", "arrow.up.left.and.arrow.down.right"]
        let trafficActions = [#selector(closeWindow), #selector(minimizeWindow), #selector(zoomWindow)]
        for index in 0..<3 {
            let button = TrafficLightButton(color: NSColor(hex: trafficColors[index]), symbol: trafficSymbols[index])
            button.target = self
            button.action = trafficActions[index]
            button.frame = NSRect(x: 15 + CGFloat(index) * 27, y: 16, width: 14, height: 14)
            trafficContent.addSubview(button)
        }

        [back, forward, reload].enumerated().forEach { index, button in
            let symbols = ["chevron.left", "chevron.right", "arrow.clockwise"]
            let help = ["Back", "Forward", "Reload"]
            let actions = [#selector(goBack), #selector(goForward), #selector(reloadPage)]
            configureButton(button, symbol: symbols[index], help: help[index], action: actions[index])
        }
        configureButton(newTab, symbol: "plus", help: "New Tab", action: #selector(newTabButton))
        configureButton(closeTab, symbol: "xmark", help: "Close Tab", action: #selector(closeTabToolbarButton))
        configureButton(dockPlus, symbol: "plus", help: "New Tab", action: #selector(newTabButton))
        configureButton(history, symbol: "clock.arrow.circlepath", help: "History", action: #selector(showHistory))
        configureButton(downloads, symbol: "arrow.down.circle", help: "Downloads", action: #selector(showDownloads))
        configureButton(customize, symbol: "slider.horizontal.3", help: "Customize Toolbar", action: #selector(showToolbarCustomization))

        address.placeholderAttributedString = NSAttributedString(
            string: isPrivateBrowsing ? "Search privately or enter an address" : "Search or enter an address",
            attributes: [.foregroundColor: isPrivateBrowsing ? NSColor(hex: 0xAFA99F) : NSColor(hex: 0x777066)]
        )
        address.isBezeled = false
        address.drawsBackground = false
        address.focusRingType = .none
        address.textColor = isPrivateBrowsing ? NSColor(hex: 0xF4EBDD) : NSColor(hex: 0x211D19)
        address.font = .systemFont(ofSize: 14, weight: .medium)
        address.delegate = self
        address.onFocus = { [weak self] in
            guard let self, !self.addressIsEditing else { return }
            self.addressIsEditing = true
            self.address.stringValue = self.current?.displayAddress ?? ""
        }
        address.target = self
        address.action = #selector(submitAddress)
        address.translatesAutoresizingMaskIntoConstraints = false

        let shieldSymbol = isPrivateBrowsing ? "eye.slash.fill" : "shield.lefthalf.filled"
        let shieldDescription = isPrivateBrowsing ? "Private browsing active" : "Protection active"
        let shield = NSImageView(image: NSImage(systemSymbolName: shieldSymbol, accessibilityDescription: shieldDescription)!)
        shield.contentTintColor = isPrivateBrowsing ? .white : NSColor(hex: 0xD0B378)
        shield.translatesAutoresizingMaskIntoConstraints = false
        let addressHost = HoverView()
        addressHost.wantsLayer = true
        addressHost.layer?.backgroundColor = NSColor.white.withAlphaComponent(isPrivateBrowsing ? 0.10 : 0.34).cgColor
        addressHost.layer?.cornerRadius = 17
        addressHost.translatesAutoresizingMaskIntoConstraints = false
        addressHost.addSubview(shield)
        addressHost.addSubview(address)
        addressHost.onHover = { [weak self] hovering in
            let alpha: CGFloat = self?.isPrivateBrowsing == true ? (hovering ? 0.18 : 0.10) : (hovering ? 0.58 : 0.34)
            addressHost.layer?.backgroundColor = NSColor.white.withAlphaComponent(alpha).cgColor
        }
        NSLayoutConstraint.activate([
            shield.leadingAnchor.constraint(equalTo: addressHost.leadingAnchor, constant: 14),
            shield.centerYAnchor.constraint(equalTo: addressHost.centerYAnchor),
            shield.widthAnchor.constraint(equalToConstant: 15), shield.heightAnchor.constraint(equalToConstant: 15),
            address.leadingAnchor.constraint(equalTo: shield.trailingAnchor, constant: 9),
            address.trailingAnchor.constraint(equalTo: addressHost.trailingAnchor, constant: -14),
            address.centerYAnchor.constraint(equalTo: addressHost.centerYAnchor)
        ])

        for button in [back, forward, reload, newTab, closeTab, customize, history, downloads] {
            let host = NSView()
            button.translatesAutoresizingMaskIntoConstraints = true
            host.addSubview(button)
            let tint = isPrivateBrowsing ? NSColor(hex: 0x111823, alpha: 0.82) : NSColor.white.withAlphaComponent(0.22)
            let surface = glassSurface(content: host, radius: 24, tint: tint)
            toolbarContent.addSubview(surface)
            chromeSurfaces.append(surface)
        }
        back.superview?.addSubview(forward)
        navigationDivider.wantsLayer = true
        navigationDivider.layer?.backgroundColor = NSColor.separatorColor.cgColor
        back.superview?.addSubview(navigationDivider)
        addressSurface = glassSurface(
            content: addressHost,
            radius: 24,
            tint: isPrivateBrowsing ? NSColor(hex: 0x111823, alpha: 0.88) : NSColor.white.withAlphaComponent(0.30)
        )
        toolbarContent.addSubview(addressSurface)
        toolbarContent.addSubview(loadingRing)
        history.isHidden = isPrivateBrowsing || UserDefaults.standard.bool(forKey: "MontclairHideHistory")
        downloads.isHidden = UserDefaults.standard.bool(forKey: "MontclairHideDownloads")
        header.material = .headerView
        header.blendingMode = .withinWindow
        header.state = .active

        dockPlusHost.wantsLayer = true
        dockPlusHost.layer?.backgroundColor = (isPrivateBrowsing ? NSColor(hex: 0xD0B378, alpha: 0.90) : NSColor(hex: 0xB89B68, alpha: 0.92)).cgColor
        dockPlusHost.layer?.cornerRadius = 22
        dockPlus.contentTintColor = NSColor(hex: 0x211D19)
        dockPlus.imagePosition = .imageOnly
        dockPlus.alignment = .center
        dockPlus.image = nil
        dockPlus.frame = NSRect(x: 0, y: 0, width: 44, height: 44)
        dockPlus.autoresizingMask = [.width, .height]
        dockPlus.translatesAutoresizingMaskIntoConstraints = true
        dockPlusIcon.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")?.withSymbolConfiguration(.init(pointSize: 18, weight: .semibold))
        dockPlusIcon.contentTintColor = NSColor(hex: 0x211D19)
        dockPlusIcon.imageScaling = .scaleNone
        dockPlusIcon.frame = NSRect(x: 12, y: 12, width: 20, height: 20)
        dockPlusHost.addSubview(dockPlusIcon)
        dockPlusHost.addSubview(dockPlus)
        dockContent.addSubview(dockPlusHost)
        dockContent.onHover = { [weak self] hovering in
            self?.setDockCollapsed(!hovering)
        }

        root.addSubview(content)
        root.addSubview(header)
        root.addSubview(traffic)
        root.addSubview(toolbar)

        root.addSubview(dock)
        layoutShell()
    }

    private func configureButton(_ button: NSButton, symbol: String, help: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)?.withSymbolConfiguration(.init(pointSize: 15, weight: .medium))
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.alignment = .center
        button.toolTip = help
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 12
        button.contentTintColor = isPrivateBrowsing ? NSColor(hex: 0xF2E9DA) : NSColor(hex: 0x211D19)
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func layoutShell(animated: Bool = false) {
        let size = root.bounds.size
        header.frame = NSRect(x: 0, y: size.height - 72, width: size.width, height: 72)
        content.frame = NSRect(x: 10, y: 10, width: max(0, size.width - 20), height: max(0, size.height - 86))
        content.layer?.cornerRadius = 26
        let trafficFrame = NSRect(x: 8, y: size.height - 59, width: 104, height: 46)
        let toolbarFrame = NSRect(x: 120, y: size.height - 60, width: max(0, size.width - 136), height: 48)
        let rightFrame = NSRect.zero
        let expandedWidth = min(660, max(118, CGFloat(tabs.count) * 49 + 70))
        let dockWidth: CGFloat = isDockCollapsed ? 68 : expandedWidth
        let dockFrame = NSRect(x: (size.width - dockWidth) / 2, y: 22, width: dockWidth, height: 60)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                traffic.animator().frame = trafficFrame
                toolbar.animator().frame = toolbarFrame
                rightControls.animator().frame = rightFrame
                dock.animator().frame = dockFrame
            }
        } else {
            traffic.frame = trafficFrame
            toolbar.frame = toolbarFrame
            rightControls.frame = rightFrame
            dock.frame = dockFrame
        }
        dockContent.frame = NSRect(origin: .zero, size: dockFrame.size)
        trafficContent.frame = NSRect(origin: .zero, size: trafficFrame.size)
        rightContent.frame = NSRect(origin: .zero, size: rightFrame.size)
        layoutChrome(width: toolbarFrame.width)
        layoutDockButtons(animated: animated, containerWidth: dockWidth)
    }

    private func layoutChrome(width: CGFloat) {
        let buttons = [back, forward, reload, newTab, closeTab, customize, history, downloads]
        let side: CGFloat = width < 800 ? 36 : 48
        let gap: CGFloat = width < 800 ? 6 : 10
        let rightCount = 1 + (history.isHidden ? 0 : 1) + (downloads.isHidden ? 0 : 1)
        let rightWidth = CGFloat(rightCount) * (side + gap)
        let available = width - rightWidth - 18
        let groupWidth = min(available, max(380, toolbarPreferredWidth - 260))
        let groupX = max(0, (available - groupWidth) / 2)
        let addressWidth = max(90, groupWidth - 5 * (side + gap))
        var x = groupX
        for (index, button) in buttons.enumerated() {
            if index == 1 { continue }
            if index == 3 {
                let target = NSRect(x: x, y: 0, width: addressWidth, height: 48)
                if target != addressTargetFrame {
                    let animate = addressTargetFrame != .zero && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                    addressTargetFrame = target
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = animate ? 0.28 : 0
                        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                        addressSurface.animator().frame = target
                        loadingRing.animator().frame = target
                    }
                }
                x += addressWidth + gap
            }
            if index == 5 { x = width - rightWidth + gap }
            let surface = chromeSurfaces[index]
            let hidden = (button === history || button === downloads) && button.isHidden
            surface.isHidden = hidden
            guard !hidden else { continue }
            surface.frame = NSRect(x: x, y: (48 - side) / 2, width: side, height: side)
            button.superview?.frame = NSRect(x: 0, y: 0, width: side, height: side)
            button.frame = NSRect(x: 0, y: 0, width: side, height: side)
            x += side + gap
            if index == 0 {
                let combinedWidth = side * 2 + gap
                surface.frame.size.width = combinedWidth
                button.superview?.frame.size.width = combinedWidth
                forward.frame = NSRect(x: side + gap, y: 0, width: side, height: side)
                navigationDivider.frame = NSRect(x: combinedWidth / 2 - 0.5, y: side * 0.25, width: 1, height: side * 0.5)
                chromeSurfaces[1].isHidden = true
                x += side + gap
            }
        }
    }

    func windowDidResize(_ notification: Notification) { layoutShell() }

    private var current: BrowserTab? { tabs.indices.contains(selectedIndex) ? tabs[selectedIndex] : nil }

    private func addTab(url: URL?, lazy: Bool = false) {
        let tab = BrowserTab(url: url, lazy: lazy, websiteDataStore: websiteDataStore, isPrivate: isPrivateBrowsing)
        tab.onChange = { [weak self, weak tab] in
            guard let self else { return }
            self.saveSession()
            if tab === self.current { self.refreshChrome() }
        }
        tab.onVisit = { [weak self] title, url in
            guard let self else { return }
            if !self.isPrivateBrowsing && self.recordsHistory { self.library.visit(title: title, url: url) }
            self.saveSession()
            self.libraryPanel?.reload()
        }
        tab.onOpenNewTab = { [weak self] url in self?.addTab(url: url) }
        tab.onScrollDirection = { [weak self, weak tab] scrollingDown in
            guard let self, tab === self.current else { return }
            if scrollingDown { self.setDockCollapsed(true) }
        }
        tabs.append(tab)
        selectedIndex = tabs.count - 1
        if let blocker = Self.compiledBlocker { tab.webView?.configuration.userContentController.add(blocker) }
        if !restoringSession {
            rebuildTabs()
            showCurrentTab()
            saveSession()
        }
    }

    private func restoreSession(force: Bool = false) {
        let saved = library.data.session
        if !isPrivateBrowsing, (!testing || force), restoresTabs, !saved.urls.isEmpty {
            restoringSession = true
            for value in saved.urls { addTab(url: value.isEmpty ? nil : URL(string: value), lazy: true) }
            selectedIndex = min(max(0, saved.selected), tabs.count - 1)
            restoringSession = false
            showCurrentTab()
        } else { addTab(url: nil) }
    }

    func saveSession() {
        guard !isPrivateBrowsing, !restoringSession else { return }
        library.saveSession(restoresTabs ? SavedSession(urls: tabs.map { $0.sessionAddress }, selected: selectedIndex) : SavedSession())
    }

    func windowWillClose(_ notification: Notification) {
        saveSession()
        tabs.forEach { $0.dispose() }
        tabs.removeAll()
        suspensionTimer?.invalidate()
        onWindowClose?()
    }

    func toggleCurrentBookmark() {
        guard !isPrivateBrowsing, bookmarksEnabled, let tab = current, BrowserLibrary.isWebURL(tab.displayAddress) else { return }
        library.toggleBookmark(title: tab.title, url: tab.displayAddress)
        libraryPanel?.reload()
    }

    var canBookmarkCurrentPage: Bool { !isPrivateBrowsing && bookmarksEnabled && BrowserLibrary.isWebURL(current?.displayAddress ?? "") }
    var canShowBookmarks: Bool { !isPrivateBrowsing && bookmarksEnabled }
    var currentPageIsBookmarked: Bool { library.data.bookmarks.contains { $0.url == current?.displayAddress } }

    func showBookmarks() {
        guard bookmarksEnabled else { return }
        libraryPanel = LibraryPanel(library: library, bookmarks: true) { [weak self] url in self?.addTab(url: URL(string: url)) }
        libraryPanel?.showWindow(nil)
    }

    private func rebuildTabs() {
        tabButtons.forEach { $0.removeFromSuperview() }
        tabButtons = tabs.enumerated().map { index, tab in
            let button = NSButton(title: "", target: self, action: #selector(selectTabButton(_:)))
            button.tag = index
            button.toolTip = tab.title
            button.isBordered = false
            button.image = tab.favicon ?? NSImage(systemSymbolName: tab.title == "New Tab" ? "sparkles" : "globe", accessibilityDescription: tab.title)
            button.imageScaling = .scaleProportionallyDown
            button.contentTintColor = isPrivateBrowsing ? NSColor(hex: 0xF2E9DA) : NSColor(hex: 0x211D19)
            button.wantsLayer = true
            button.alignment = .center
            button.layer?.cornerRadius = 17
            let selectedColor = isPrivateBrowsing ? NSColor(hex: 0xB89B68) : NSColor(hex: 0xD0B378)
            let idleColor = isPrivateBrowsing ? NSColor(hex: 0xFFFFFF, alpha: 0.10) : NSColor(hex: 0xFFFFFF, alpha: 0.30)
            button.layer?.backgroundColor = (index == selectedIndex ? selectedColor : idleColor).cgColor
            dockContent.addSubview(button)
            return button
        }
        layoutShell()
    }

    private func layoutDockButtons(animated: Bool, containerWidth: CGFloat) {
        let itemWidth: CGFloat = 44
        let gap: CGFloat = 7
        let step = itemWidth + gap
        let visible: [Int]
        var x: CGFloat
        if isDockCollapsed {
            visible = [selectedIndex]
            x = (containerWidth - itemWidth) / 2
        } else {
            let available = max(itemWidth, containerWidth - 70)
            let capacity = max(1, Int((available + gap) / step))
            let count = min(capacity, tabs.count)
            let first = min(max(0, selectedIndex - count / 2), max(0, tabs.count - count))
            visible = Array(first..<(first + count))
            let clusterWidth = CGFloat(count) * itemWidth + CGFloat(max(0, count - 1)) * gap + 51
            x = max(8, (containerWidth - clusterWidth) / 2)
        }
        for (index, button) in tabButtons.enumerated() {
            let shouldShow = visible.contains(index)
            button.isHidden = !shouldShow
            if shouldShow {
                let frame = NSRect(x: x, y: 8, width: itemWidth, height: 44)
                if animated { button.animator().frame = frame } else { button.frame = frame }
                x += itemWidth + gap
            }
        }
        dockPlusHost.isHidden = isDockCollapsed
        if !isDockCollapsed { dockPlusHost.frame = NSRect(x: x, y: 8, width: 44, height: 44) }
    }

    private func setDockCollapsed(_ collapsed: Bool) {
        guard collapsed != isDockCollapsed else { return }
        isDockCollapsed = collapsed
        layoutShell(animated: true)
    }

    func createNewTab() { setDockCollapsed(false); addTab(url: nil) }
    func closeCurrentTab() {
        guard tabs.indices.contains(selectedIndex) else { return }
        let removed = tabs.remove(at: selectedIndex)
        removed.dispose()
        if tabs.isEmpty { addTab(url: nil); return }
        selectedIndex = min(selectedIndex, tabs.count - 1)
        rebuildTabs()
        showCurrentTab()
        saveSession()
    }
    private func closeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        let removed = tabs.remove(at: index)
        removed.dispose()
        if tabs.isEmpty { selectedIndex = 0; addTab(url: nil); return }
        if index < selectedIndex { selectedIndex -= 1 }
        selectedIndex = min(selectedIndex, tabs.count - 1)
        rebuildTabs()
        showCurrentTab()
    }
    func focusAddressBar() {
        setDockCollapsed(false)
        addressIsEditing = true
        address.stringValue = current?.displayAddress ?? ""
        window?.makeFirstResponder(address)
        address.currentEditor()?.selectAll(nil)
    }

    private func updateAddressDisplay() {
        guard !addressIsEditing else { return }
        let full = current?.displayAddress ?? ""
        address.stringValue = URL(string: full)?.host ?? full
        address.toolTip = full.isEmpty ? "Search or enter an address" : full
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        guard !addressIsEditing else { return }
        addressIsEditing = true
        let full = current?.displayAddress ?? ""
        address.stringValue = full
        address.currentEditor()?.string = full
        address.currentEditor()?.selectAll(nil)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        addressIsEditing = false
        updateAddressDisplay()
    }
    func reloadCurrentPage() { reloadPage() }
    func navigateBack() { current?.webView?.goBack() }
    func navigateForward() { current?.webView?.goForward() }
    func selectTab(at index: Int) { guard tabs.indices.contains(index) else { return }; selectedIndex = index; setDockCollapsed(false); showCurrentTab(); saveSession() }

    func focusPageSearch() {
        guard let webView = current?.webView else { return }
        let alert = NSAlert(); alert.messageText = "Find on Page"; alert.informativeText = "Enter text to find on the current page."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24)); alert.accessoryView = field
        alert.addButton(withTitle: "Find"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { Task { _ = try? await webView.find(field.stringValue, configuration: WKFindConfiguration()) } }
    }

    func runInteractionSmokeTest() {
        NSApp.sendAction(#selector(newTabButton), to: self, from: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard self?.current?.displayAddress.isEmpty == true else {
                print("MONCLAIR_NEW_TAB_ADDRESS_LEAK \(self?.current?.displayAddress ?? "nil")")
                NSApp.terminate(nil)
                return
            }
            self?.current?.onNavigationResult = { success, detail in
                print(success ? "MONCLAIR_NAVIGATION_OK \(detail)" : "MONCLAIR_NAVIGATION_FAILED \(detail)")
                NSApp.terminate(nil)
            }
            self?.current?.load("Montclair browser test")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            print("MONCLAIR_NAVIGATION_TIMEOUT url=\(self?.current?.webView?.url?.absoluteString ?? "nil")")
            NSApp.terminate(nil)
        }
    }

    func runBenchmark() {
        let fixture = "<html><head><title>Benchmark</title><style>body{font:16px system-ui;background:#f3f0e9}article{padding:16px;margin:8px;background:white;border-radius:16px}</style></head><body>" +
            (0..<500).map { "<article><h3>Reading card \($0)</h3><p>Montclair deterministic rendering and tab lifecycle workload.</p></article>" }.joined() + "</body></html>"
        func loadFixture() { current?.webView?.loadHTMLString(fixture, baseURL: nil) }
        func mark(_ phase: String) {
            print("BENCH \(phase) tabs=\(tabs.count) live=\(tabs.filter { $0.webView != nil }.count)")
            fflush(stdout)
        }
        loadFixture()
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [self] in
            mark("one_tab")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [self] in
                for _ in 0..<9 { addTab(url: nil); loadFixture() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [self] in
                    mark("ten_tabs")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [self] in
                        for _ in 0..<9 { closeCurrentTab() }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [self] in
                            mark("after_closing")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                                print("BENCH done")
                                fflush(stdout)
                                NSApp.terminate(nil)
                            }
                        }
                    }
                }
            }
        }
    }

    func runFeatureTest() {
        tabs.forEach { $0.dispose() }
        tabs = []
        library.saveSession(SavedSession(urls: ["https://example.com", "", "https://example.org"], selected: 1))
        restoreSession(force: true)
        precondition(tabs.count == 3 && selectedIndex == 1)
        precondition(tabs.filter { $0.webView != nil }.count == 1, "Restored background tabs must stay unloaded")
        saveSession()
        precondition(library.data.session.urls == ["https://example.com", "", "https://example.org"])
        precondition(library.data.session.selected == 1)
        weak var closedTab = current
        closeCurrentTab()
        precondition(closedTab == nil, "Closed tabs must be released")
        precondition(tabs.count == 2)
        print("PASS: session order, blank tab, selected index, lazy restore, closed-tab release.")
        NSApp.terminate(nil)
    }

    func runPrivacyFeatureTest() {
        precondition(isPrivateBrowsing, "Privacy test requires a private window")
        precondition(tabs.count == 1 && current?.isPrivate == true)
        precondition(current?.webView?.configuration.websiteDataStore.isPersistent == false,
                     "Private tabs must use a non-persistent website data store")
        let sessionBefore = library.data.session
        saveSession()
        precondition(library.data.session == sessionBefore, "Private windows must not write session restore data")
        precondition(!canBookmarkCurrentPage && !canShowBookmarks,
                     "Private windows must not persist bookmarks")
        print("PASS: isolated non-persistent data store, no session restore, no bookmark persistence.")
        NSApp.terminate(nil)
    }

    private func showCurrentTab() {
        content.subviews.forEach { $0.removeFromSuperview() }
        current?.markActive()
        guard let webView = current?.webView else { return }
        if let blocker = Self.compiledBlocker {
            webView.configuration.userContentController.removeAllContentRuleLists()
            webView.configuration.userContentController.add(blocker)
        }
        webView.frame = content.bounds
        webView.autoresizingMask = [.width, .height]
        content.addSubview(webView)
        refreshChrome()
    }

    private func refreshChrome() {
        guard let webView = current?.webView else { return }
        updateAddressDisplay()
        back.isEnabled = webView.canGoBack
        forward.isEnabled = webView.canGoForward
        reload.image = NSImage(systemSymbolName: webView.isLoading ? "xmark" : "arrow.clockwise", accessibilityDescription: nil)
        loadingRing.setLoading(webView.isLoading)
        window?.title = isPrivateBrowsing ? "Private — \(current?.title ?? "Montclair")" : (current?.title ?? "Montclair")
        rebuildTabs()
    }

    private func installBlockerOnExistingTabs() {
        guard let blocker = Self.compiledBlocker else { return }
        for tab in tabs { tab.webView?.configuration.userContentController.add(blocker) }
    }
    private func suspendBackgroundTabs() {
        for (index, tab) in tabs.enumerated() where index != selectedIndex { tab.suspendIfIdle() }
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
        submitAddress(); return true
    }

    @objc private func goBack() { current?.webView?.goBack() }
    @objc private func goForward() { current?.webView?.goForward() }
    @objc private func reloadPage() {
        guard let webView = current?.webView else { return }
        if webView.isLoading { webView.stopLoading() } else { webView.reload() }
    }
    @objc private func submitAddress() { current?.load(address.stringValue); window?.makeFirstResponder(content) }
    @objc private func newTabButton() { createNewTab() }
    @objc private func selectTabButton(_ sender: NSButton) { selectTab(at: sender.tag) }
    @objc private func closeTabToolbarButton() { closeCurrentTab() }
    @objc private func closeWindow() { window?.performClose(nil) }
    @objc private func minimizeWindow() { window?.miniaturize(nil) }
    @objc private func zoomWindow() { window?.zoom(nil) }
    @objc private func showHistory() {
        guard !isPrivateBrowsing else { return }
        libraryPanel = LibraryPanel(library: library, bookmarks: false) { [weak self] url in self?.addTab(url: URL(string: url)) }
        libraryPanel?.showWindow(nil)
    }
    @objc private func showDownloads() {
        let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        NSWorkspace.shared.open(url)
    }
    @objc private func showToolbarCustomization() {
        let alert = NSAlert()
        alert.messageText = "Customize Toolbar"
        alert.informativeText = "Choose the width and the tools shown on the right."
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Reset")

        let panel = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 128))
        let widthLabel = NSTextField(labelWithString: "Toolbar width")
        widthLabel.frame = NSRect(x: 0, y: 100, width: 150, height: 20)
        let widthValue = NSTextField(labelWithString: "\(Int(toolbarPreferredWidth)) pt")
        widthValue.alignment = .right
        widthValue.frame = NSRect(x: 250, y: 100, width: 110, height: 20)
        let slider = NSSlider(value: Double(toolbarPreferredWidth), minValue: 620, maxValue: 1400, target: nil, action: nil)
        slider.frame = NSRect(x: 0, y: 68, width: 360, height: 24)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(previewToolbarWidth(_:))
        slider.identifier = NSUserInterfaceItemIdentifier("toolbarWidth")
        let historyToggle = NSButton(checkboxWithTitle: "History", target: nil, action: nil)
        historyToggle.state = history.isHidden ? .off : .on
        historyToggle.frame = NSRect(x: 0, y: 34, width: 150, height: 24)
        let downloadsToggle = NSButton(checkboxWithTitle: "Downloads", target: nil, action: nil)
        downloadsToggle.state = downloads.isHidden ? .off : .on
        downloadsToggle.frame = NSRect(x: 180, y: 34, width: 160, height: 24)
        let note = NSTextField(labelWithString: "Essential navigation, search, new-tab and close controls stay centered.")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 11)
        note.frame = NSRect(x: 0, y: 4, width: 360, height: 18)
        [widthLabel, widthValue, slider, historyToggle, downloadsToggle, note].forEach(panel.addSubview)
        for view in panel.subviews { view.frame.origin.y += 112 }
        panel.frame.size.height += 112
        let restoreToggle = NSButton(checkboxWithTitle: "Restore tabs when Montclair opens", target: nil, action: nil)
        restoreToggle.state = restoresTabs ? .on : .off
        restoreToggle.frame = NSRect(x: 0, y: 78, width: 360, height: 24)
        let recordToggle = NSButton(checkboxWithTitle: "Save browsing history", target: nil, action: nil)
        recordToggle.state = recordsHistory ? .on : .off
        recordToggle.frame = NSRect(x: 0, y: 50, width: 360, height: 24)
        let bookmarkToggle = NSButton(checkboxWithTitle: "Enable bookmarks (⌘D)", target: nil, action: nil)
        bookmarkToggle.state = bookmarksEnabled ? .on : .off
        bookmarkToggle.frame = NSRect(x: 0, y: 22, width: 360, height: 24)
        [restoreToggle, recordToggle, bookmarkToggle].forEach(panel.addSubview)
        alert.accessoryView = panel

        let originalWidth = toolbarPreferredWidth
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            UserDefaults.standard.set(restoreToggle.state == .off, forKey: "MontclairDisableRestore")
            UserDefaults.standard.set(recordToggle.state == .off, forKey: "MontclairDisableHistory")
            UserDefaults.standard.set(bookmarkToggle.state == .off, forKey: "MontclairDisableBookmarks")
            saveSession()
            toolbarPreferredWidth = CGFloat(slider.doubleValue)
            history.isHidden = historyToggle.state == .off
            downloads.isHidden = downloadsToggle.state == .off
            UserDefaults.standard.set(Double(toolbarPreferredWidth), forKey: "MontclairToolbarWidth")
            UserDefaults.standard.set(history.isHidden, forKey: "MontclairHideHistory")
            UserDefaults.standard.set(downloads.isHidden, forKey: "MontclairHideDownloads")
        } else if response == .alertThirdButtonReturn {
            for key in ["MontclairDisableRestore", "MontclairDisableHistory", "MontclairDisableBookmarks"] { UserDefaults.standard.removeObject(forKey: key) }
            saveSession()
            toolbarPreferredWidth = 1080
            history.isHidden = false
            downloads.isHidden = false
            UserDefaults.standard.removeObject(forKey: "MontclairToolbarWidth")
            UserDefaults.standard.removeObject(forKey: "MontclairHideHistory")
            UserDefaults.standard.removeObject(forKey: "MontclairHideDownloads")
        } else {
            toolbarPreferredWidth = originalWidth
        }
        layoutShell(animated: true)
    }

    @objc private func previewToolbarWidth(_ sender: NSSlider) {
        toolbarPreferredWidth = CGFloat(sender.doubleValue)
        if let panel = sender.superview,
           let value = panel.subviews.compactMap({ $0 as? NSTextField }).first(where: { $0.alignment == .right }) {
            value.stringValue = "\(Int(sender.doubleValue)) pt"
        }
        layoutShell(animated: false)
    }
}

@MainActor
final class AddressField: NSTextField {
    var onFocus: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        onFocus?()
        super.mouseDown(with: event)
    }
}

extension NSColor {
    convenience init(hex: Int, alpha: CGFloat = 1) {
        self.init(calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

@MainActor
final class HoverView: NSView {
    var onHover: ((Bool) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

@MainActor
final class WindowRootView: NSView {
    var onTitlebarDoubleClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, convert(event.locationInWindow, from: nil).y > bounds.height - 22 {
            onTitlebarDoubleClick?()
        } else {
            super.mouseDown(with: event)
        }
    }
}

@MainActor
final class TrafficLightButton: NSButton {
    private let normalColor: NSColor
    private let symbolImage: NSImage?
    private var hoverArea: NSTrackingArea?
    private var hovering = false

    init(color: NSColor, symbol: String) {
        normalColor = color
        symbolImage = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 7, weight: .bold))
        super.init(frame: .zero)
        title = ""
        isBordered = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        (hovering ? normalColor.blended(withFraction: 0.14, of: .white) ?? normalColor : normalColor).setFill()
        NSBezierPath(ovalIn: bounds).fill()
        guard hovering, let symbolImage else { return }
        symbolImage.draw(in: NSRect(x: bounds.midX - 4, y: bounds.midY - 4, width: 8, height: 8), from: .zero, operation: .sourceOver, fraction: 0.9, respectFlipped: true, hints: nil)
    }
}

@MainActor
final class HoverIconButton: NSButton {
    private var hoverArea: NSTrackingArea?
    private var hovering = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        if hovering && isEnabled {
            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            (dark ? NSColor.white.withAlphaComponent(0.20) : NSColor(hex: 0x775B31, alpha: 0.17)).setFill()
            let hoverBounds = bounds.insetBy(dx: 2, dy: 2)
            let shape = NSBezierPath(roundedRect: hoverBounds, xRadius: hoverBounds.height / 2, yRadius: hoverBounds.height / 2)
            shape.fill()
            (dark ? NSColor.white.withAlphaComponent(0.26) : NSColor(hex: 0x775B31, alpha: 0.28)).setStroke()
            shape.lineWidth = 0.75
            shape.stroke()
        }
        guard let image else { return }
        let side: CGFloat = 21
        let imageRect = NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        let alpha: CGFloat = isEnabled ? 0.96 : 0.34
        NSGraphicsContext.saveGraphicsState()
        image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
        (contentTintColor ?? .labelColor).setFill()
        imageRect.fill(using: .sourceIn)
        NSGraphicsContext.restoreGraphicsState()
    }
}
