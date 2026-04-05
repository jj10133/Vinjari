import SwiftUI
import WebKit

struct ContentView: View {
    @EnvironmentObject private var ipcViewModel: IPCViewModel
    @State private var page: WebPage = WebPage()
    @State private var addressBarText: String = ""
    
    
    var body: some View {
        NavigationStack {
            VStack {
                WebView(page)
            }
            .searchable(text: $addressBarText, placement: .toolbarPrincipal, prompt: "Enter URL or Search")
            .onSubmit(of: .search) { load() }
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button {
                    } label: {
                        Label("Toggle Sidebar", systemImage: "sidebar.left")
                    }
                    .help("Toggle Sidebar")
                    
                    Group {
                        Button {
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(true)
                        .help("Back")
                        
                        Button {
                            addNewTab()
                        } label: {
                            Image(systemName: "chevron.right")
                        }
//                        .disabled(true)
                        .help("Forward")
                    }
                    
                }
                
//                ToolbarItemGroup(placement: .primaryAction) {
//                    Button(action: { addTab() }) {
//                        Image(systemName: "plus.app.fill")
//                    }
//                    .help("Open a New Tab")
//                    
//                    Button(action: {  }) {
//                        Image(systemName: "square.on.square")
//                    }
//                    .help("Show tab overview")
//                }
            }
            .onAppear {
                configureScheme()
            }
        }
    }
    
    // MARK: - Native AppKit Actions
    
    private func addNewTab() {
        NSApp.sendAction(#selector(NSWindow.newWindowForTab(_:)), to: nil, from: nil)
    }
    
    private func toggleTabOverview() {
        // Triggers the native macOS Tab Grid/Exposé view
        NSApp.sendAction(#selector(NSWindow.toggleTabOverview(_:)), to: nil, from: nil)
    }
    
    private func toggleSidebar() {
        NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
    }
    
    // MARK: - Logic
    
    private func configureScheme() {
        let scheme = URLScheme("hyper")!
        let handler = HyperResourceSchemeHandler(ipc: ipcViewModel.ipc)
        
        var configuration = WebPage.Configuration()
        configuration.urlSchemeHandlers[scheme] = handler
        configuration.allowsAirPlayForMediaPlayback = true
        page = WebPage(configuration: configuration)
    }
    
    private func load() {
        guard !addressBarText.isEmpty else { return }
        
        let finalURLString: String
        if addressBarText.contains("://") || addressBarText.contains(".") {
            finalURLString = addressBarText
        } else {
            let query = addressBarText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            finalURLString = "https://www.google.com/search?q=\(query)"
        }
        
        guard let url = URL(string: finalURLString) else { return }
        page.load(URLRequest(url: url))
        
    }
}
