// RPCClient.swift
//
// Thread safety strategy:
//
// bare-rpc-swift's RPC class is not thread-safe. rpc.request() and
// rpc.receive() both mutate the internal pending dictionary and must
// never run concurrently.
//
// The public API no longer exposes Messages, so we cannot bypass
// rpc.request(). Instead we use a serial request channel:
//
//   All callers enqueue a (command, payload, continuation) tuple.
//   A single consumer Task dequeues one at a time:
//     1. Calls rpc.request() — suspends waiting for reply
//     2. Reply arrives via readLoop → rpc.receive() — same Task context
//     3. rpc.request() resumes — consumer resumes caller continuation
//     4. Consumer moves to next queued request
//
// This guarantees rpc.request() and rpc.receive() are always on the
// same cooperative Task — never concurrent.
//
// Throughput: JS handles all requests concurrently on its event loop.
// Swift serialises sends but JS doesn't wait for one to finish before
// starting the next — it processes all received frames immediately.
// Replies come back in any order; bare-rpc matches by id.

import Foundation
import BareKit
import BareRPC

// MARK: - Command IDs

enum Command {
    static let fetch  : UInt = 0
    static let readdir: UInt = 1
    static let write  : UInt = 2
    static let info   : UInt = 3
    static let open   : UInt = 4
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

// MARK: - Pending request

private struct PendingRequest {
    let command     : UInt
    let payload     : Data
    let continuation: CheckedContinuation<Data, Error>
}

// MARK: - IPC Bridge

private final class IPCBridge: RPCDelegate, @unchecked Sendable {

    private let ipc: IPC
    weak var rpc   : RPC?

    init(ipc: IPC) { self.ipc = ipc }

    // Send — fire and forget, ipc.write is non-blocking
    func rpc(_ rpc: RPC, send data: Data) {
        Task { try? await self.ipc.write(data: data) }
    }

    func rpc(_ rpc: RPC, didFailWith error: any Error) {
        print("[RPCClient] RPC error: \(error)")
    }

    func readLoop() async {
        do {
            for try await chunk in ipc {
                rpc?.receive(chunk)
            }
        } catch {
            print("[RPCClient] read loop ended: \(error)")
        }
    }
}

// MARK: - RPCClient

final class RPCClient: @unchecked Sendable {

    private let rpc        : RPC
    private let bridge     : IPCBridge
    private let readTask   : Task<Void, Never>
    private let workerTask : Task<Void, Never>

    // Serial channel — all requests enqueued here, one consumer processes them
    private let (stream, continuation) = AsyncStream<PendingRequest>.makeStream()

    init(ipc: IPC) {
        let bridge = IPCBridge(ipc: ipc)
        let rpc    = RPC(delegate: bridge)
        bridge.rpc = rpc
        self.rpc    = rpc
        self.bridge = bridge

        // Capture rpc locally before Tasks so we don't capture self
        // before all stored properties are initialised
        let capturedRPC    = rpc
        let capturedStream = stream

        // Read loop — feeds IPC bytes to rpc.receive()
        self.readTask = Task { await bridge.readLoop() }

        // Worker — single consumer, processes one request at a time
        self.workerTask = Task {
            for await pending in capturedStream {
                do {
                    guard let data = try await capturedRPC.request(
                        pending.command,
                        data: pending.payload
                    ) else {
                        pending.continuation.resume(throwing: RPCError.noResponse)
                        continue
                    }
                    pending.continuation.resume(returning: data)
                } catch {
                    pending.continuation.resume(throwing: error)
                }
            }
        }
    }

    deinit {
        readTask.cancel()
        workerTask.cancel()
        continuation.finish()
    }

    // MARK: - Commands

    func fetch(key: String, path: String, headers: [String: String] = [:]) async throws -> FetchResult {
        let payload = try encode(["key": key, "path": path, "headers": headers])
        return try decodeFetch(try await enqueue(Command.fetch, payload: payload))
    }

    func readdir(key: String, path: String = "/") async throws -> [DriveEntry] {
        let payload = try encode(["key": key, "path": path])
        let reply   = try await enqueue(Command.readdir, payload: payload)
        try checkError(reply)
        struct R: Decodable { let entries: [DriveEntry] }
        return try JSONDecoder().decode(R.self, from: reply).entries
    }

    func write(key: String, path: String, data fileData: Data) async throws {
        let payload = try encode(["key": key, "path": path, "data": fileData.base64EncodedString()])
        try checkError(try await enqueue(Command.write, payload: payload))
    }

    func open(key: String) async throws {
        let payload = try encode(["key": key])
        let reply   = try await enqueue(Command.open, payload: payload)
        try checkError(reply)
    }

    func driveInfo(key: String) async throws -> DriveInfo {
        let payload = try encode(["key": key])
        let reply   = try await enqueue(Command.info, payload: payload)
        try checkError(reply)
        return try JSONDecoder().decode(DriveInfo.self, from: reply)
    }

    // MARK: - Enqueue
    // Suspends the calling Task and puts the request into the serial channel.
    // The worker Task picks it up, calls rpc.request(), and resumes us.

    private func enqueue(_ command: UInt, payload: Data) async throws -> Data {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { cont in
            continuation.yield(PendingRequest(
                command     : command,
                payload     : payload,
                continuation: cont
            ))
        }
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
