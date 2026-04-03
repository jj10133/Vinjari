// RPCClient.swift
// bare-rpc-swift over BareKit IPC.
//
// Wire protocol (confirmed from PeerDrop):
//   RPC(delegate:)                              — init
//   rpc.request(UInt, data: Data) async throws -> Data?   — one reply
//   rpc.receive(Data)                           — feed inbound IPC bytes
//   delegate.rpc(_:send:)                       — transmit encoded frame
//
// fetch wire format (JS → Swift, success):
//   [4 bytes big-endian UInt32: header JSON length][header JSON][binary body]
//
// error wire format (JS → Swift, any command):
//   { "error": "<message>" }   — plain JSON, checked before length-prefix decode

import Foundation
import BareKit
import BareRPC

// ─── Command IDs — shared with app.js ────────────────────────────────────────

enum Command {
    static let fetch  : UInt = 0
    static let readdir: UInt = 1
    static let write  : UInt = 2
    static let info   : UInt = 3
}

// ─── Domain types ─────────────────────────────────────────────────────────────

struct DriveEntry: Decodable, Identifiable {
    var id: String { path }
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
}

// ─── Errors ───────────────────────────────────────────────────────────────────

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

// ─── IPC → RPC bridge ────────────────────────────────────────────────────────

private final class IPCBridge: RPCDelegate {

    private let ipc: IPC
    unowned var rpc: RPC!

    init(ipc: IPC) { self.ipc = ipc }

    func rpc(_ rpc: RPC, send data: Data) {
        Task { try? await ipc.write(data: data) }
    }

    func readLoop() async {
        do {
            for try await chunk in ipc { rpc.receive(chunk) }
        } catch {
            print("[RPCClient] IPC read error: \(error)")
        }
    }
}

// ─── RPCClient ────────────────────────────────────────────────────────────────

final class RPCClient {

    private let rpc   : RPC
    private let bridge: IPCBridge

    init(ipc: IPC) {
        let bridge = IPCBridge(ipc: ipc)
        let rpc    = RPC(delegate: bridge)
        bridge.rpc = rpc
        self.rpc    = rpc
        self.bridge = bridge
        Task { await bridge.readLoop() }
    }

    // MARK: - fetch

    func fetch(key: String, path: String, headers: [String: String] = [:]) async throws -> FetchResult {
        let payload = try encode(["key": key, "path": path, "headers": headers])
        let reply   = try await request(Command.fetch, payload: payload)
        return try decodeFetch(reply)
    }

    // MARK: - readdir

    func readdir(key: String, path: String = "/") async throws -> [DriveEntry] {
        let payload = try encode(["key": key, "path": path])
        let reply   = try await request(Command.readdir, payload: payload)
        try checkError(reply)
        struct R: Decodable { let entries: [DriveEntry] }
        return try JSONDecoder().decode(R.self, from: reply).entries
    }

    // MARK: - write

    func write(key: String, path: String, data fileData: Data) async throws {
        let payload = try encode(["key": key, "path": path, "data": fileData.base64EncodedString()])
        let reply   = try await request(Command.write, payload: payload)
        try checkError(reply)
    }

    // MARK: - driveInfo

    func driveInfo(key: String) async throws -> DriveInfo {
        let payload = try encode(["key": key])
        let reply   = try await request(Command.info, payload: payload)
        try checkError(reply)
        return try JSONDecoder().decode(DriveInfo.self, from: reply)
    }

    // MARK: - Helpers

    private func request(_ cmd: UInt, payload: Data) async throws -> Data {
        let data = try await rpc.request(cmd, data: payload)
        // nil means channel closed without data — often due to Task cancellation
        try Task.checkCancellation()
        guard let data else { throw RPCError.noResponse }
        return data
    }

    /// Check if JS replied with { "error": "..." } — happens when handler catches an exception.
    private func checkError(_ data: Data) throws {
        struct ErrorReply: Decodable { let error: String }
        if let e = try? JSONDecoder().decode(ErrorReply.self, from: data) {
            throw RPCError.remoteError(e.error)
        }
    }

    /// Decode fetch wire format: [UInt32 header-len][header JSON][body]
    /// Checks for error reply first since error JSON won't start with 4 valid length bytes.
    private func decodeFetch(_ data: Data) throws -> FetchResult {
        // Check for error reply first
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

        let headerData = data[4 ..< 4 + headerLen]
        let body       = data[(4 + headerLen)...]
        let meta       = try JSONDecoder().decode(FetchMeta.self, from: headerData)
        return FetchResult(meta: meta, body: Data(body))
    }

    private func encode(_ dict: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: dict)
    }
}

// MARK: - FetchResult remote error accessor

extension FetchResult {
    /// Returns the remote error message if JS replied with { "error": "..." }
    var remoteError: String? {
        struct E: Decodable { let error: String }
        return try? JSONDecoder().decode(E.self, from: body).error
    }
}
