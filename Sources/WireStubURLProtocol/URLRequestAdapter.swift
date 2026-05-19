import Foundation
import WireStubCore

enum URLRequestAdapter {
    static func makeSnapshot(from request: URLRequest) -> RequestSnapshot {
        let url = request.url
        let components = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        let path: String
        if let components, !components.path.isEmpty {
            path = components.path
        } else if let urlPath = url?.path, !urlPath.isEmpty {
            path = urlPath
        } else {
            path = PathUtilities.rootPath
        }

        var headers = request.allHTTPHeaderFields ?? [:]
        removeHeader(named: URLProtocolInternal.tokenHeader, from: &headers)
        injectHostHeaderIfMissing(url: url, headers: &headers)

        return RequestSnapshot(
            method: request.httpMethod ?? "GET",
            path: path,
            target: RequestTarget(scheme: url?.scheme, host: url?.host, port: url?.port),
            queryItems: (components?.queryItems ?? []).map { QueryItem(name: $0.name, value: $0.value) },
            headers: headers,
            body: request.httpBody ?? bodyData(from: request.httpBodyStream),
            receivedAt: Date()
        )
    }

    private static func removeHeader(named name: String, from headers: inout HTTPHeaders) {
        if let key = headers.keys.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            headers.removeValue(forKey: key)
        }
    }

    private static func injectHostHeaderIfMissing(url: URL?, headers: inout HTTPHeaders) {
        guard headers.keys.contains(where: { $0.caseInsensitiveCompare("Host") == .orderedSame }) == false,
              let host = url?.host else {
            return
        }

        if let port = url?.port {
            headers["Host"] = "\(host):\(port)"
        } else {
            headers["Host"] = host
        }
    }

    private static func bodyData(from stream: InputStream?) -> Data? {
        guard let stream else { return nil }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4_096
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while true {
            let count = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
                guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return 0
                }
                return stream.read(baseAddress, maxLength: bufferSize)
            }
            if count < 0 {
                return nil
            }
            if count == 0 {
                break
            }
            data.append(contentsOf: buffer.prefix(count))
        }

        return data.isEmpty ? nil : data
    }
}
