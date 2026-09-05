import WebKit

@MainActor
enum ContentBlocker {
    // Small native ruleset for the MVP. Larger community lists can be compiled later.
    static let rules = #"""
    [
      {"trigger":{"url-filter":".*doubleclick\\.net/.*"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*googlesyndication\\.com/.*"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*google-analytics\\.com/.*"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*facebook\\.com/tr/.*"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*","if-domain":["*doubleclick.net","*googlesyndication.com"]},"action":{"type":"block"}}
    ]
    """#

    static func install(completion: @escaping @MainActor () -> Void) {
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "MontclairBuiltinBlocker",
            encodedContentRuleList: rules
        ) { list, error in
            Task { @MainActor in
                if let list {
                    BrowserWindowController.compiledBlocker = list
                    completion()
                } else if let error {
                    NSLog("Content blocker compilation failed: \(error)")
                }
            }
        }
    }
}
