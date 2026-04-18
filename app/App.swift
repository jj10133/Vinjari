import SwiftUI
import AppKit

@main
struct VinjariApp: SwiftUI.App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var appModel = AppModel.shared

    var body: some Scene {
        WindowGroup(id: "browser") {
            // Each window scene gets its own stable id
            WindowView(appModel: appModel)
                .background(WindowConfigurator())
        }
//        .windowRestorationBehavior(.disabled)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background: appModel.runtime.suspend()
            case .active:     appModel.runtime.resume()
            default:          break
            }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    NSApp.sendAction(Selector(("newWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut("t", modifiers: .command)
            }
        }
    }
}

// Separate view so each window scene has its own @State windowId
// and its own stable BrowserViewModel reference.
private struct WindowView: View {
    let appModel: AppModel

    // UUID generated once per window instantiation — stable across re-renders
    @State private var windowId = UUID().uuidString
    @State private var browser  : BrowserViewModel? = nil

    var body: some View {
        Group {
            if let browser {
                ContentView(browser: browser)
            } else {
                ProgressView("Starting Hyper…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await appModel.boot()
            // Assign after boot so drives exists
            if browser == nil {
                browser = appModel.browser(for: windowId)
            }
        }
        .onDisappear {
            // Window closed — release the BrowserViewModel
            appModel.closeBrowser(for: windowId)
        }
    }
}

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.tabbingMode = .preferred
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
