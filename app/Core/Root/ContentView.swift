import SwiftUI
import WebKit

struct ContentView: View {
    @State var browser: BrowserViewModel
    
    var body: some View {
        NavigationStack {
            webContent
            // Attach modifiers to the content inside the Stack
                .searchable(text: $browser.addressBarText, placement: .toolbarPrincipal)
                .onSubmit(of: .search) {
                    browser.commitAddress()
                }
                .toolbar {
                    // LEFT SIDE: Navigation
                    ToolbarItemGroup(placement: .navigation) {
                        Button {
                            browser.activeTab?.goBack()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(!(browser.activeTab?.canGoBack ?? false))
                        
                        Button {
                            browser.activeTab?.goForward()
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(!(browser.activeTab?.canGoForward ?? false))
                    }
                    
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            toggleShowAllTabs()
                        } label: {
                            Image(systemName: "square.on.square")
                        }
                    }
                    
                }
        }
    }
    
    private func toggleShowAllTabs() {
        NSApp.sendAction(#selector(NSWindow.toggleTabOverview(_:)), to: nil, from: nil)
    }
    
    @ViewBuilder
    private var webContent: some View {
        if let tab = browser.activeTab {
            VStack(spacing: 0) {
                WebView(tab.page)
                    .ignoresSafeArea()
                    .onChange(of: tab.page.url) { _, _ in
                        tab.navigationCounter += 1
                        browser.syncAddressBar()
                    }
                    .onChange(of: tab.page.isLoading) { _, isLoading in
                        if !isLoading { tab.navigationCounter += 1 }
                    }
            }
            .id(tab.id)
            .navigationTitle(tab.page.title.isEmpty ? "New Tab" : tab.page.title)
        } else {
            // A non-empty view prevents the "buildExpression" error
            Color.clear
        }
    }
}
