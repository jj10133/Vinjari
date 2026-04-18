import SwiftUI
import Observation

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var runtime  = BareRuntime()
    private(set) var drives   : DriveService?
    private(set) var isBooted : Bool = false

    // One BrowserViewModel per window — keyed by window scene id.
    // WebPage/WKWebView cannot be in two view hierarchies simultaneously.
    private var browsers: [String: BrowserViewModel] = [:]

    func boot() async {
        guard !isBooted else { return }
        runtime.start()
        guard let ipc = runtime.ipc else { return }
        let rpc = RPCClient(ipc: ipc)
        drives      = DriveService(rpc: rpc)
        isBooted    = true
    }

    // Called from each WindowGroup scene — returns existing or creates new.
    func browser(for windowId: String) -> BrowserViewModel? {
        guard let drives else { return nil }
        if let existing = browsers[windowId] { return existing }
        let vm = BrowserViewModel(drives: drives)
        browsers[windowId] = vm
        return vm
    }

    func closeBrowser(for windowId: String) {
        browsers.removeValue(forKey: windowId)
    }
}
