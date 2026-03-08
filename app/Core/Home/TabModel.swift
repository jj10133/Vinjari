//
//  Tab.swift
//  App
//
//  Created by joker on 2025-10-08.
//

import WebKit


class TabModel: Identifiable, ObservableObject {
    let id = UUID()
    @Published var title: String
    @Published var urlString: String
    let page: WebPage
    
    init(title: String, urlString: String, page: WebPage) {
        self.title = title
        self.urlString = urlString
        self.page = page
    }
}

