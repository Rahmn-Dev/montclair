import Foundation

@main
struct LibraryTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Montclair-library-test-" + UUID().uuidString)
        let file = directory.appendingPathComponent("library.json")
        let library = BrowserLibrary(file: file)
        library.visit(title: "Search", url: "https://example.com/search?q=hello")
        library.visit(title: "Updated", url: "https://example.com/search?q=hello")
        library.visit(title: "Internal", url: "file:///private/internal")
        assert(library.data.history.count == 1)
        library.toggleBookmark(title: "Example", url: "https://example.com")
        let session = SavedSession(urls: ["https://example.com", "", "https://example.org"], selected: 2)
        library.saveSession(session)
        let reopened = BrowserLibrary(file: file)
        assert(reopened.data.session == session)
        assert(reopened.data.bookmarks.count == 1)
        assert(reopened.data.history.first?.title == "Updated")
        reopened.clearHistory()
        assert(reopened.data.bookmarks.count == 1 && reopened.data.session == session)
        reopened.toggleBookmark(title: "", url: "https://example.com")
        assert(reopened.data.bookmarks.isEmpty)
        reopened.saveSession(SavedSession())
        let again = BrowserLibrary(file: file)
        assert(again.data.session.urls.isEmpty)
        assert(again.data.history.isEmpty && again.data.bookmarks.isEmpty)
        assert(again.lastError == nil)
        print("PASS: persistence, duplicate history, internal URL exclusion, bookmarks toggle, clear history isolation, restore off.")
    }
}
