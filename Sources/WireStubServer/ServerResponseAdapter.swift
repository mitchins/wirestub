import Foundation
import FlyingFox
import WireStubCore

enum ServerResponseAdapter {
    static func makeResponse(from result: StubResult, replayMode: ReplayMode) -> HTTPResponse {
        switch result {
        case .matched(let response, _):
            return makeResponse(from: response)
        case .unmatched(let diagnostic):
            let body = Data(diagnostic.render().utf8)
            switch replayMode {
            case .strict:
                return HTTPResponse(
                    statusCode: HTTPStatusCode(501, phrase: "Unmatched WireStub Request"),
                    headers: makeHeaders([
                        "Content-Type": "text/plain; charset=utf-8",
                    ]),
                    body: body
                )
            case .permissive(let status):
                return HTTPResponse(
                    statusCode: statusCode(for: status),
                    headers: makeHeaders([
                        "Content-Type": "text/plain; charset=utf-8",
                    ]),
                    body: body
                )
            }
        }
    }

    static func makeResponse(from response: StubResponse) -> HTTPResponse {
        HTTPResponse(
            statusCode: statusCode(for: response.status),
            headers: makeHeaders(response.headers),
            body: response.body
        )
    }

    static func responseDelay(for result: StubResult) -> Duration? {
        switch result {
        case .matched(let response, _):
            return response.delay
        case .unmatched:
            return nil
        }
    }

    static func makeHeaders(_ headers: WireStubCore.HTTPHeaders) -> FlyingFox.HTTPHeaders {
        var output = FlyingFox.HTTPHeaders()
        for (key, value) in headers {
            output[HTTPHeader(key)] = value
        }
        return output
    }

    static func statusCode(for status: Int) -> HTTPStatusCode {
        HTTPStatusCode(status, phrase: HTTPURLResponse.localizedString(forStatusCode: status).capitalized)
    }
}
