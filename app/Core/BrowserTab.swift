import SwiftUI
import WebKit

@MainActor
@Observable
final class BrowserTab: Identifiable {
    let id = UUID()
    let page: WebPage
    
    // Tracks internal WebKit state changes that aren't naturally observable
    var navigationCounter: Int = 0

    init(drives: DriveServiceProtocol) {
        let scheme = URLScheme("hyper")!
        let handler = HyperSchemeHandler(drives: drives)
        let decider = HyperNavigationDecider()

        var config = WebPage.Configuration()
        config.urlSchemeHandlers[scheme] = handler

        self.page = WebPage(configuration: config, navigationDecider: decider)
    }

    // Computed properties now "depend" on navigationCounter
    var canGoBack: Bool {
        _ = navigationCounter
        return !page.backForwardList.backList.isEmpty
    }

    var canGoForward: Bool {
        _ = navigationCounter
        return !page.backForwardList.forwardList.isEmpty
    }

    func load(_ rawAddress: String) {
        var address = rawAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !address.contains("://") { address = "hyper://\(address)" }
        guard let url = URL(string: address) else { return }
        
        page.load(URLRequest(url: url))
        navigationCounter += 1
    }

    func goBack() {
        guard let item = page.backForwardList.backList.last else { return }
        page.load(item)
        navigationCounter += 1
    }

    func goForward() {
        guard let item = page.backForwardList.forwardList.first else { return }
        page.load(item)
        navigationCounter += 1
    }
}
