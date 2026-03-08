//
//  ContentView.swift
//  App
//
//  Created by joker on 2025-05-15.
//

import SwiftUI
import WebKit

struct ContentView: View {
    @EnvironmentObject private var ipcViewModel: IPCViewModel
    
    @State private var page: WebPage
    @State private var addressBarText: String = ""
    
    
    init() {
        _page = State(initialValue: WebPage())
    }
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
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(true)
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
