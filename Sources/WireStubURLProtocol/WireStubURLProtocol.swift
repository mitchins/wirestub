import Foundation
import WireStubCore

private final class URLProtocolClientProxy: @unchecked Sendable {
    weak var client: URLProtocolClient?
    weak var urlProtocol: URLProtocol?

    init(client: URLProtocolClient?, urlProtocol: URLProtocol) {
        self.client = client
        self.urlProtocol = urlProtocol
    }

    func didReceive(_ response: URLResponse) {
        guard let client, let urlProtocol else { return }
        client.urlProtocol(urlProtocol, didReceive: response, cacheStoragePolicy: .notAllowed)
    }

    func didLoad(_ data: Data) {
        guard let client, let urlProtocol else { return }
        client.urlProtocol(urlProtocol, didLoad: data)
    }

    func didFail(_ error: Error) {
        guard let client, let urlProtocol else { return }
        client.urlProtocol(urlProtocol, didFailWithError: error)
    }

    func didFinish() {
        guard let client, let urlProtocol else { return }
        client.urlProtocolDidFinishLoading(urlProtocol)
    }
}

enum URLProtocolResponseAdapter {
    static func makeResponse(
        from result: StubResult,
        requestURL: URL,
        replayMode: ReplayMode
    ) throws -> (HTTPURLResponse, Data, Duration?) {
        switch result {
        case .matched(let response, _):
            return try makeResponse(from: response, requestURL: requestURL)

        case .unmatched(let diagnostic):
            let status: Int
            switch replayMode {
            case .strict:
                status = 501
            case .permissive(let permissiveStatus):
                status = permissiveStatus
            }

            let body = Data(diagnostic.render().utf8)
            let response = HTTPURLResponse(
                url: requestURL,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/plain; charset=utf-8"]
            )
            guard let response else {
                throw URLError(.badServerResponse)
            }
            return (response, body, nil)
        }
    }

    private static func makeResponse(
        from response: StubResponse,
        requestURL: URL
    ) throws -> (HTTPURLResponse, Data, Duration?) {
        let urlResponse = HTTPURLResponse(
            url: requestURL,
            statusCode: response.status,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        )
        guard let urlResponse else {
            throw URLError(.badServerResponse)
        }
        return (urlResponse, response.body, response.delay)
    }
}

/// `URLProtocol` adapter that forwards requests into `StubEngine`.
public final class WireStubURLProtocol: URLProtocol {
    private var loadingTask: Task<Void, Never>?

    /// Returns whether the request carries a WireStub session token and should be intercepted.
    public override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: URLProtocolInternal.tokenHeader) != nil
    }

    /// Returns the canonical request unchanged.
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    /// Starts replay for the intercepted request.
    public override func startLoading() {
        guard let token = request.value(forHTTPHeaderField: URLProtocolInternal.tokenHeader),
              let entry = URLProtocolEngineRegistry.shared.entry(for: token) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }

        let proxy = URLProtocolClientProxy(client: client, urlProtocol: self)
        let request = self.request

        loadingTask = Task {
            do {
                let snapshot = URLRequestAdapter.makeSnapshot(from: request)
                let result = await entry.engine.handle(snapshot)
                if Task.isCancelled {
                    return
                }

                let responseURL = request.url ?? URL(string: "https://wirestub.invalid")!
                let response = try URLProtocolResponseAdapter.makeResponse(
                    from: result,
                    requestURL: responseURL,
                    replayMode: entry.replayMode
                )

                if let delay = response.2 {
                    try await Task.sleep(for: delay)
                }
                if Task.isCancelled {
                    return
                }

                proxy.didReceive(response.0)
                proxy.didLoad(response.1)
                proxy.didFinish()
            } catch is CancellationError {
                return
            } catch {
                proxy.didFail(error)
            }
        }
    }

    /// Cancels any in-flight replay task for this protocol instance.
    public override func stopLoading() {
        loadingTask?.cancel()
        loadingTask = nil
    }
}
