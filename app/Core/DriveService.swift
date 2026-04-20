// DriveService.swift
import Foundation

protocol DriveServiceProtocol {
    func open(key: String) async throws
    func fetch(key: String, path: String, headers: [String: String]) async throws -> FetchResult
    func readdir(key: String, path: String) async throws -> [DriveEntry]
    func write(key: String, path: String, data: Data) async throws
    func info(key: String) async throws -> DriveInfo
}

final class DriveService: DriveServiceProtocol {

    private let rpc: RPCClient

    init(rpc: RPCClient) { self.rpc = rpc }

    func open(key: String) async throws {
        try await rpc.open(key: key)
    }

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
