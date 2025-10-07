//
//  Scheme.swift
//  App
//
//  Created by joker on 2025-07-20.
//

import WebKit

struct HyperResourceSchemeHandler: URLSchemeHandler {
    
    var ipc: IPC?
    
    init(ipc: IPC?) {
        self.ipc = ipc
    }
    
    func reply(for request: URLRequest) -> some AsyncSequence<URLSchemeTaskResult, any Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let ipc = self.ipc else {
                        print("IPC is nil")
                        continuation.finish(throwing: URLError(.cannotConnectToHost))
                        return
                    }
                    
                    guard let url = request.url else {
                        continuation.finish(throwing: URLError(.badURL))
                        return
                    }
                    
                    
                    // Prepare full HTTP-like request to send over IPC
                    let headers = request.allHTTPHeaderFields ?? [:]
                    let method = request.httpMethod ?? "GET"
                    
                    let payload: [String: Any] = [
                        "url": url.absoluteString,
                        "method": method,
                        "headers": headers
                    ]
                    
                    let jsonData = try JSONSerialization.data(withJSONObject: payload)
                    try await ipc.write(data: jsonData)
                    
                    var responseReceived = false
                    
                    for try await dataChunk in ipc {
                        let dataString = String(data: dataChunk, encoding: .utf8) ?? ""
                        
                        if !responseReceived {
                            if let json = try? JSONSerialization.jsonObject(with: dataChunk, options: []) as? [String: Any],
                               let statusCode = json["statusCode"] as? Int,
                               let headers = json["headers"] as? [String: String] {
                                
                                let httpResponse = HTTPURLResponse(
                                    url: url,
                                    statusCode: statusCode,
                                    httpVersion: nil,
                                    headerFields: headers
                                )!
                                
                                print(httpResponse.allHeaderFields)
                                
                                continuation.yield(URLSchemeTaskResult.response(httpResponse))
                                responseReceived = true
                                continue
                            } else {
                                print("Malformed response metadata")
                                continuation.finish(throwing: URLError(.badServerResponse))
                                return
                            }
                        }
                        
                        if let range = dataString.range(of: "END_OF_RESOURCE") {
                            // Yield data before the EOF marker
                            let actualData = dataString[..<range.lowerBound].data(using: .utf8) ?? Data()
                            if !actualData.isEmpty {
                                continuation.yield(.data(actualData))
                            }
                            
                            continuation.finish()
                            print("HyperResourceSchemeHandler: Detected EOF, Finished streaming for \(url).")
                            return
                        }
                        
                        // 5. Check for Error marker
                        if dataString.hasPrefix("ERROR:") {
                            print("HyperResourceSchemeHandler: Backend error - \(dataString)")
                            continuation.finish(throwing: URLError(.resourceUnavailable))
                            return
                        }
                        
                        print("📦 Got data chunk:", dataChunk.count)
                        // Actual binary data
                        continuation.yield(.data(dataChunk))
                    }
                    
                    continuation.finish()
                } catch {
                    print("HyperResourceSchemeHandler: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                    ipc?.close()
                }
            }
        }
    }
}
