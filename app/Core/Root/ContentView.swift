//
//  ContentView.swift
//  App
//
//  Created by joker on 2025-05-15.
//

import SwiftUI
import WebKit

struct ContentView: View {
    @State private var page: WebPage?
    @EnvironmentObject private var ipcViewModel: IPCViewModel
    
    var body: some View {
        NavigationStack {
            if let page = page {
                WebView(page)
                    .navigationTitle(page.title)
                    .onAppear {
                        if let url = URL(string: "hyper://0143faffb6927994c414ccb46f6b10e0ecc5e4dfe0301207a4b96239897eac4c") {
                            page.load(URLRequest(url: url))
                        }
                }
            } else {
                ProgressView("Loading...", value: page?.estimatedProgress)
                    .onAppear {
                        let scheme = URLScheme("hyper")!
                        let handler = HyperResourceSchemeHandler(ipc: ipcViewModel.ipc)
                        
                        var configuration = WebPage.Configuration()
                        configuration.urlSchemeHandlers[scheme] = handler
                        page = WebPage(configuration: configuration)
                        
                    }
            }
        }
    }
}
