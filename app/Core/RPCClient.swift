// RPCClient.swift
// bare-rpc-swift over BareKit IPC.
//
// Thread safety:
// bare-rpc's RPC class is NOT thread-safe — its pending [UInt: Continuation]
// dict is mutated by both request() and receive(). When multiple assets load
// concurrently (fonts, CSS, JS), these race and corrupt the dictionary.
//
// Fix: @MainActor on RPCClient and IPCBridge ensures all calls to
// rpc.request() and rpc.receive() run on the same serial executor.

import Foundation
import BareKit
import BareRPC

// MARK: - Command IDs

enum Command {
    static let fetch  : UInt = 0
    static let readdir: UInt = 1
    static let write  : UInt = 2
    static let info   : UInt = 3
}

// MARK: - Domain types

struct DriveEntry: Decodable, Identifiable {
    var id         : String { path }
    let name       : String
    let path       : String
    let isDirectory: Bool
    let size       : Int
    let mtime      : Double?
}

struct DriveInfo: Decodable {
    let key     : String
    let version : Int
    let writable: Bool
    let peers   : Int
}

struct FetchMeta: Decodable {
    let statusCode: Int
    let headers   : [String: String]
}

struct FetchResult {
    let meta: FetchMeta
    let body: Data

    var remoteError: String? {
        struct E: Decodable { let error: String }
        return try? JSONDecoder().decode(E.self, from: body).error
    }
}

// MARK: - Errors

enum RPCError: LocalizedError {
    case noResponse
    case malformedResponse(String)
    case remoteError(String)

    var errorDescription: String? {
        switch self {
        case .noResponse:               return "RPC returned no data"
        case .malformedResponse(let d): return "Malformed RPC response: \(d)"
        case .remoteError(let m):       return "Remote error: \(m)"
        }
    }
}

// MARK: - IPC Bridge

@MainActor
private final class IPCBridge: RPCDelegate {

    private let ipc: IPC
    weak var rpc: RPC?

    init(ipc: IPC) { self.ipc = ipc }

    // nonisolated — RPCDelegate is called by bare-rpc internally.
    // Hops to MainActor before writing so concurrent sends are serialised.
    // BareIPC.write is not thread-safe — concurrent calls corrupt its buffer.
    nonisolated func rpc(_ rpc: RPC, send data: Data) {
        Task { @MainActor in
            try? await self.ipc.write(data: data)
        }
    }

    func readLoop() async {
        do {
            for try await chunk in ipc {
                // Hop to MainActor before receive() so it never
                // races with request() which also runs on MainActor
                await MainActor.run { [weak self] in
                    self?.rpc?.receive(chunk)
                }
            }
        } catch {
            print("[RPCClient] IPC read loop ended: \(error)")
        }
    }
}

// MARK: - RPCClient

@MainActor
final class RPCClient {

    private let rpc     : RPC
    private let bridge  : IPCBridge
    private let readTask: Task<Void, Never>

    init(ipc: IPC) {
        let bridge = IPCBridge(ipc: ipc)
        let rpc    = RPC(delegate: bridge)
        bridge.rpc = rpc
        self.rpc      = rpc
        self.bridge   = bridge
        self.readTask = Task { await bridge.readLoop() }
    }

    deinit { readTask.cancel() }

    // MARK: - Commands

    func fetch(key: String, path: String, headers: [String: String] = [:]) async throws -> FetchResult {
        let payload = try encode(["key": key, "path": path, "headers": headers])
        return try decodeFetch(try await request(Command.fetch, payload: payload))
    }

    func readdir(key: String, path: String = "/") async throws -> [DriveEntry] {
        let payload = try encode(["key": key, "path": path])
        let reply   = try await request(Command.readdir, payload: payload)
        try checkError(reply)
        struct R: Decodable { let entries: [DriveEntry] }
        return try JSONDecoder().decode(R.self, from: reply).entries
    }

    func write(key: String, path: String, data fileData: Data) async throws {
        let payload = try encode(["key": key, "path": path, "data": fileData.base64EncodedString()])
        try checkError(try await request(Command.write, payload: payload))
    }

    func driveInfo(key: String) async throws -> DriveInfo {
        let payload = try encode(["key": key])
        let reply   = try await request(Command.info, payload: payload)
        try checkError(reply)
        return try JSONDecoder().decode(DriveInfo.self, from: reply)
    }

    // MARK: - Core request
    // Runs on @MainActor — sequential, never concurrent with receive()

    private func request(_ cmd: UInt, payload: Data) async throws -> Data {
        try Task.checkCancellation()
        guard let data = try await rpc.request(cmd, data: payload) else {
            throw RPCError.noResponse
        }
        return data
    }

    // MARK: - Helpers

    private func checkError(_ data: Data) throws {
        struct E: Decodable { let error: String }
        if let e = try? JSONDecoder().decode(E.self, from: data) {
            throw RPCError.remoteError(e.error)
        }
    }

    private func decodeFetch(_ data: Data) throws -> FetchResult {
        try checkError(data)
        guard data.count >= 4 else {
            throw RPCError.malformedResponse("reply too short")
        }
        let headerLen = Int(
            data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        )
        guard data.count >= 4 + headerLen else {
            throw RPCError.malformedResponse("header truncated")
        }
        let meta = try JSONDecoder().decode(FetchMeta.self, from: data[4 ..< 4 + headerLen])
        return FetchResult(meta: meta, body: Data(data[(4 + headerLen)...]))
    }

    private func encode(_ dict: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: dict)
    }
}
