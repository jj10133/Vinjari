import SwiftUI
import Observation

@MainActor
@Observable
final class BrowserViewModel {
    let drives: DriveServiceProtocol
    var tabs: [BrowserTab] = []
    var activeTabIndex: Int = 0
    var addressBarText: String = ""

    var activeTab: BrowserTab? {
        guard tabs.indices.contains(activeTabIndex) else { return nil }
        return tabs[activeTabIndex]
    }

    init(drives: DriveServiceProtocol) {
        self.drives = drives
        openNewTab()
    }

    func openNewTab(url: String? = nil) {
        let tab = BrowserTab(drives: drives)
        tabs.append(tab)
        activeTabIndex = tabs.count - 1
        if let url { tab.load(url) }
        syncAddressBar()
    }

    func commitAddress() {
        activeTab?.load(addressBarText)
    }

    func syncAddressBar() {
        addressBarText = activeTab?.page.url?.absoluteString ?? ""
    }
}
