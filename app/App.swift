import SwiftUI


@main
struct App: SwiftUI.App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private var appModel = AppModel.shared
    
    var body: some Scene {
        WindowGroup(id: "browser") {
            Group {
                if let drives = appModel.drives {
                    // All windows/tabs use the same engine instance
                    ContentView(browser: BrowserViewModel(drives: drives))
                } else {
                    ProgressView("Starting Hyper Runtime...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .task { await appModel.boot() }
            .background(WindowConfigurator())
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

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.tabbingMode = .preferred
                // This ensures the window is treated as a tab if others exist
                window.isRestorable = true
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
