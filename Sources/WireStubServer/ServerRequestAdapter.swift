import Foundation
import FlyingFox
import WireStubCore

enum ServerRequestAdapter {
    static func makeSnapshot(from request: HTTPRequest, baseURL: URL) async -> RequestSnapshot {
        let body = try? await request.bodyData
        let headers = HTTPHeaderUtilities.dictionary(from: request.headers.map { header, value in
            (header.rawValue, value)
        })
        let path = request.path.removingPercentEncoding ?? request.path

        return RequestSnapshot(
            method: request.method.rawValue,
            path: path.isEmpty ? "/" : path,
            target: RequestTarget(scheme: baseURL.scheme, host: baseURL.host, port: baseURL.port),
            queryItems: request.query.map { WireStubCore.QueryItem(name: $0.name, value: $0.value) },
            headers: headers,
            body: body,
            receivedAt: Date()
        )
    }
}
