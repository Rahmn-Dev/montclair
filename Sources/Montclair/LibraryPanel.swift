import AppKit

@MainActor
final class LibraryPanel: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let search = NSSearchField()
    private let table = NSTableView()
    private let status = NSTextField(labelWithString: "")
    private let remove = NSButton(title: "Remove", target: nil, action: nil)
    private let library: BrowserLibrary
    private let bookmarks: Bool
    private let openPage: (String) -> Void
    private var rows: [SavedPage] = []

    init(library: BrowserLibrary, bookmarks: Bool, open: @escaping (String) -> Void) {
        self.library = library
        self.bookmarks = bookmarks
        openPage = open
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 460),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = bookmarks ? "Bookmarks" : "History"
        window.minSize = NSSize(width: 500, height: 340)
        window.center()
        guard let root = window.contentView else { return }
        search.placeholderString = "Search by title or address"
        search.delegate = self
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        let titleColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        titleColumn.title = "Page"; titleColumn.width = 250
        let urlColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("url"))
        urlColumn.title = "Address"; urlColumn.width = 310
        table.addTableColumn(titleColumn); table.addTableColumn(urlColumn)
        table.delegate = self; table.dataSource = self
        table.rowHeight = 30
        table.usesAlternatingRowBackgroundColors = true
        table.target = self; table.doubleAction = #selector(openSelected)
        scroll.documentView = table
        let open = NSButton(title: "Open", target: self, action: #selector(openSelected))
        remove.title = bookmarks ? "Remove Bookmark" : "Clear History…"
        remove.target = self; remove.action = #selector(removeSelected)
        let footer = NSStackView(views: [status, remove, open])
        footer.spacing = 12
        for view in [search, scroll, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            search.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            search.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            search.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: search.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: search.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
            footer.leadingAnchor.constraint(equalTo: search.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: search.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        ])
        reload()
    }
    required init?(coder: NSCoder) { fatalError() }
    func reload() {
        let all = bookmarks ? library.data.bookmarks : library.data.history
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        rows = all.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.url.localizedCaseInsensitiveContains(query) }
        status.stringValue = "\(rows.count) pages"
        table.reloadData()
    }
    func controlTextDidChange(_ obj: Notification) { reload() }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard rows.indices.contains(row) else { return nil }
        return tableColumn?.identifier.rawValue == "title" ? rows[row].title : rows[row].url
    }
    @objc private func openSelected() {
        guard rows.indices.contains(table.selectedRow) else { return }
        openPage(rows[table.selectedRow].url)
    }
    @objc private func removeSelected() {
        if bookmarks {
            guard rows.indices.contains(table.selectedRow) else { return }
            library.removeBookmark(url: rows[table.selectedRow].url)
        } else {
            let alert = NSAlert()
            alert.messageText = "Clear saved history?"
            alert.informativeText = "Bookmarks and open tabs will be kept."
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Clear History")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
            library.clearHistory()
        }
        reload()
    }
}
