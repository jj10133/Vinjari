//
//  AppModel.swift
//  App
//
//  Created by Janardhan on 2026-04-03.
//


import SwiftUI
import Observation

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()
    
    private(set) var runtime = BareRuntime()
    private(set) var drives: DriveService?
    var browser: BrowserViewModel?
    private(set) var isBooted = false

    func boot() async {
        guard !isBooted else { return }
        
        // Start the single background engine
        runtime.start()
        
        if let ipc = runtime.ipc {
            let rpc = RPCClient(ipc: ipc)
            let driveService = DriveService(rpc: rpc)
            self.drives = driveService
            self.browser = BrowserViewModel(drives: driveService)
            self.isBooted = true
        }
    }
}
