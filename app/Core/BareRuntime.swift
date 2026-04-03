// BareRuntime.swift
// Owns the BareKit worklet lifecycle. Single responsibility.
// Exposes IPC — bare-rpc-swift wraps it via RPCDelegate.

import Foundation
import BareKit

final class BareRuntime: ObservableObject {

    enum State { case idle, running, suspended, terminated }

    @Published private(set) var state: State = .idle

    private var worklet          : Worklet?
    private(set) var ipc         : IPC?

    func start() {
        guard state == .idle else { return }
        let w   = Worklet()
        w.start(name: "app", ofType: "bundle")
        worklet = w
        ipc     = IPC(worklet: w)
        state   = .running
    }

    func suspend() {
        guard state == .running else { return }
        worklet?.suspend()
        state = .suspended
    }

    func resume() {
        guard state == .suspended else { return }
        worklet?.resume()
        state = .running
    }

    func terminate() {
        guard state == .running || state == .suspended else { return }
        ipc?.close()
        worklet?.terminate()
        state = .terminated
    }
}
