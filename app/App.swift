import SwiftUI

extension Notification.Name {
    static let addNewTab = Notification.Name("addNewTab")
}

@main
struct App: SwiftUI.App {
    
    @StateObject private var worker = Worker()
    @StateObject private var ipcViewModel = IPCViewModel()
    @State private var isWorkletStarted = false
    
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        NSWindow.allowsAutomaticWindowTabbing = true
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ipcViewModel)
                .onAppear {
                    worker.start()
                    isWorkletStarted = true
                    ipcViewModel.configure(with: worker.ipc)
//                    Task {
//                        await ipcViewModel.readFromIPC()
//                    }
                    let _ = NSApplication.shared.windows.map { $0.tabbingMode = .preferred }
                }
                .onDisappear {
                    worker.terminate()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    openNewWindow()
                }
                .keyboardShortcut("t", modifiers: .command)
            }
        }
        .onChange(of: scenePhase) { phase in
            guard isWorkletStarted else { return }
            
            switch phase {
            case .background:
                worker.suspend()
            case .active:
                worker.resume()
            default:
                break
            }
        }
    }
    
    private func openNewWindow() {
        NSApp.sendAction(#selector(NSWindow.newWindowForTab(_:)), to: nil, from: nil)
    }
}
