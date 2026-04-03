// DriveService.swift
// Domain-level drive operations. Protocol allows mocking in tests.
// All methods are async throws — callers use await.

import Foundation

protocol DriveServiceProtocol {
    func fetch(key: String, path: String, headers: [String: String]) async throws -> FetchResult
    func readdir(key: String, path: String) async throws -> [DriveEntry]
    func write(key: String, path: String, data: Data) async throws
    func info(key: String) async throws -> DriveInfo
}

final class DriveService: DriveServiceProtocol {

    private let rpc: RPCClient

    init(rpc: RPCClient) { self.rpc = rpc }

    func fetch(key: String, path: String, headers: [String: String] = [:]) async throws -> FetchResult {
        try await rpc.fetch(key: key, path: path, headers: headers)
    }

    func readdir(key: String, path: String = "/") async throws -> [DriveEntry] {
        try await rpc.readdir(key: key, path: path)
    }

    func write(key: String, path: String, data: Data) async throws {
        try await rpc.write(key: key, path: path, data: data)
    }

    func info(key: String) async throws -> DriveInfo {
        try await rpc.driveInfo(key: key)
    }
}
