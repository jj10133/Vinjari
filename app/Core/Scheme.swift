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
                        print("Error: IPC object is nil, cannot read.")
                        return
                    }
                    
                    guard let url = request.url else {
                        continuation.finish(throwing: URLError(.badURL))
                        return
                    }
                    
                    let requestURLString = url.absoluteString
                    
                    try await ipc.write(data: requestURLString.data(using: .utf8)!)
                    
                    var receivedResponse = false
                    var responseMimeType = "application/octet-stream"
                    var contentLength = ""
                    
                    for try await dataChunck in ipc {
                        let dataString = String(data: dataChunck, encoding: .utf8) ?? ""
                        
                        // 2. Protocol Check: Look for the MIMETYPE header (sent first by Node.js)
                        if !receivedResponse, dataString.hasPrefix("MIMETYPE:") {
                            responseMimeType = String(dataString.dropFirst("MIMETYPE:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                            print("receive the correct mime type \(responseMimeType)")
                            
                            
                            contentLength = String(dataString.dropFirst("CONTENTLENGTH:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                          
                            // 3. Send the HTTP response with the correct MIME type
                            if let httpResponse = HTTPURLResponse(
                                url: url,
                                statusCode: 200,
                                httpVersion: nil,
                                headerFields: ["Content-Type": responseMimeType, "Content-Length": contentLength]
                            ) {
                                continuation.yield(URLSchemeTaskResult.response(httpResponse))
                                receivedResponse = true
                                continue
                            } else {
                                continuation.finish(throwing: URLError(.unsupportedURL))
                                return
                            }
                        }
                        
                        // 4. Check for End-Of-Resource marker
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
                        
                        // 6. Yield the data chunk if a response has been sent
                        if receivedResponse {
                            continuation.yield(.data(dataChunck))
                        } else {
                            // Protocol error: Received data before MIMETYPE header
                            print("HyperResourceSchemeHandler: Protocol error: Data received before MIME type response.")
                            continuation.finish(throwing: URLError(.cannotDecodeContentData))
                            return
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    print("HyperResourceSchemeHandler: Error during scheme handler for \(request.url?.absoluteString ?? "unknown URL"): \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                    ipc?.close()
                }
                
            }
        }
    }
}
