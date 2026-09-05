import Foundation

struct SavedPage: Codable, Equatable {
    var title: String
    var url: String
    var date: Date
}

struct SavedSession: Codable, Equatable {
    var urls: [String] = []
    var selected: Int = 0
}

struct LibraryData: Codable {
    var history: [SavedPage] = []
    var bookmarks: [SavedPage] = []
    var session = SavedSession()
}

/// One atomic local file, bounded history, and no browsing data sent to a service.
final class BrowserLibrary {
    let file: URL
    private(set) var data: LibraryData
    private(set) var lastError: String?

    init(file: URL) {
        self.file = file
        if let bytes = try? Data(contentsOf: file), let decoded = try? JSONDecoder().decode(LibraryData.self, from: bytes) {
            data = decoded
        } else {
            data = LibraryData()
        }
    }

    static func isWebURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host != nil else { return false }
        return true
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(data).write(to: file, options: .atomic)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func visit(title: String, url: String) {
        guard Self.isWebURL(url) else { return }
        data.history.removeAll { $0.url == url }
        data.history.insert(SavedPage(title: title.isEmpty ? url : title, url: url, date: Date()), at: 0)
        data.history = Array(data.history.prefix(2000))
        save()
    }

    func toggleBookmark(title: String, url: String) {
        guard Self.isWebURL(url) else { return }
        if data.bookmarks.contains(where: { $0.url == url }) {
            data.bookmarks.removeAll { $0.url == url }
        } else {
            data.bookmarks.insert(SavedPage(title: title.isEmpty ? url : title, url: url, date: Date()), at: 0)
        }
        save()
    }

    func removeBookmark(url: String) { data.bookmarks.removeAll { $0.url == url }; save() }
    func clearHistory() { data.history = []; save() }
    func saveSession(_ session: SavedSession) {
        let clean = SavedSession(urls: session.urls.map { Self.isWebURL($0) ? $0 : "" },
                                 selected: max(0, min(session.selected, max(0, session.urls.count - 1))))
        guard data.session != clean else { return }
        data.session = clean
        save()
    }
}
