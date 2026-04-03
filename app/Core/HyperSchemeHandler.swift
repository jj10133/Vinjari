// HyperSchemeHandler.swift

import WebKit

struct HyperSchemeHandler: URLSchemeHandler {

    private let drives: DriveServiceProtocol

    init(drives: DriveServiceProtocol) {
        self.drives = drives
    }

    func reply(for request: URLRequest) -> some AsyncSequence<URLSchemeTaskResult, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = request.url else {
                        print("[scheme] ❌ bad URL")
                        continuation.finish(throwing: URLError(.badURL))
                        return
                    }

                    print("[scheme] → \(url.absoluteString)")

                    guard let key = url.host, !key.isEmpty else {
                        print("[scheme] ❌ no host in URL")
                        continuation.finish(throwing: URLError(.badURL))
                        return
                    }

                    let path = Self.resolvePath(url.path)
                    print("[scheme] path resolved: \(url.path) → \(path)")

                    let forwarded = ["Range", "Accept", "If-None-Match", "If-Modified-Since"]
                    var headers   = [String: String]()
                    for field in forwarded {
                        if let value = request.value(forHTTPHeaderField: field) {
                            headers[field] = value
                        }
                    }

                    try Task.checkCancellation()
                    print("[scheme] calling drives.fetch for \(path)")

                    let result = try await drives.fetch(key: key, path: path, headers: headers)
                    print("[scheme] ✓ fetch returned \(result.body.count) bytes for \(path)")

                    if let errMsg = result.remoteError {
                        print("[scheme] ❌ remote error: \(errMsg)")
                        continuation.finish(throwing: HyperError.notFound(errMsg))
                        return
                    }

                    let httpResponse = HTTPURLResponse(
                        url         : url,
                        statusCode  : result.meta.statusCode,
                        httpVersion : "HTTP/1.1",
                        headerFields: result.meta.headers
                    )!

                    continuation.yield(.response(httpResponse))
                    continuation.yield(.data(result.body))
                    continuation.finish()
                    print("[scheme] ✓ done \(path)")

                } catch is CancellationError {
                    print("[scheme] cancelled")
                    continuation.finish()
                } catch {
                    print("[scheme] ❌ error: \(error)")
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func resolvePath(_ raw: String) -> String {
        let path = raw.isEmpty ? "/" : raw
        if path == "/" || path.hasSuffix("/") {
            return path == "/" ? "/index.html" : path + "index.html"
        }
        if let last = path.split(separator: "/").last, last.contains(".") {
            return path
        }
        return path
    }
}

enum HyperError: LocalizedError {
    case notFound(String)
    var errorDescription: String? {
        if case .notFound(let m) = self { return "Not found: \(m)" }
        return nil
    }
}
