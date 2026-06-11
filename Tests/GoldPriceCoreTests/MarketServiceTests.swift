import Foundation
import Testing
@testable import GoldPriceCore

@Suite("Market service snapshots", .serialized)
struct MarketServiceTests {
    @Test("Fetches AU9999 and Shanghai index independently")
    func fetchesBothQuotes() async {
        let service = makeService(responses: [
            "118.AU9999": #"{"data":{"f43":88940,"f59":2,"f60":91563,"f169":-2623,"f170":-286}}"#,
            "1.000001": #"{"data":{"f43":397347,"f59":2,"f60":399323,"f169":-1976,"f170":-49}}"#
        ])

        let snapshot = await service.fetch(current: MarketSnapshot())

        #expect(snapshot.gold == MarketQuote(
            price: 889.40,
            comparisonBase: 915.63,
            changeAmount: -26.23,
            changePercent: -2.86
        ))
        #expect(snapshot.shanghaiIndex == MarketQuote(
            price: 3973.47,
            comparisonBase: 3993.23,
            changeAmount: -19.76,
            changePercent: -0.49
        ))
        #expect(snapshot.isLoading == false)
        #expect(snapshot.updatedAt != nil)
    }

    @Test("Failed source preserves its last valid quote")
    func failedSourcePreservesLastQuote() async {
        let previousGold = MarketQuote(
            price: 900,
            comparisonBase: 880,
            changeAmount: 20,
            changePercent: 2.27
        )
        let previousIndex = MarketQuote(
            price: 3900,
            comparisonBase: 3950,
            changeAmount: -50,
            changePercent: -1.27
        )
        let current = MarketSnapshot(
            gold: previousGold,
            shanghaiIndex: previousIndex,
            updatedAt: nil,
            isLoading: true
        )
        let service = makeService(responses: [
            "1.000001": #"{"data":{"f43":400000,"f59":2,"f60":390000,"f169":10000,"f170":256}}"#
        ])

        let snapshot = await service.fetch(current: current)

        #expect(snapshot.gold == previousGold)
        #expect(snapshot.shanghaiIndex == MarketQuote(
            price: 4000,
            comparisonBase: 3900,
            changeAmount: 100,
            changePercent: 2.56
        ))
        #expect(snapshot.isLoading == false)
        #expect(snapshot.updatedAt != nil)
    }

    @Test("All failures preserve quotes and the previous update timestamp")
    func allFailuresPreserveSnapshot() async {
        let updatedAt = Date(timeIntervalSince1970: 1_000)
        let current = MarketSnapshot(
            gold: MarketQuote(
                price: 900,
                comparisonBase: 880,
                changeAmount: 20,
                changePercent: 2.27
            ),
            shanghaiIndex: nil,
            updatedAt: updatedAt,
            isLoading: true
        )
        let service = makeService(responses: [:])

        let snapshot = await service.fetch(current: current)

        #expect(snapshot.gold == current.gold)
        #expect(snapshot.shanghaiIndex == nil)
        #expect(snapshot.updatedAt == updatedAt)
        #expect(snapshot.isLoading == false)
    }

    @Test("Requests include browser-compatible headers")
    func requestHeaders() async {
        let recorder = RequestRecorder()
        let service = MarketService { request in
            await recorder.append(request)
            return nil
        }

        _ = await service.fetch(current: MarketSnapshot())
        let requests = await recorder.requests

        #expect(requests.count == 2)
        #expect(requests.allSatisfy {
            $0.value(forHTTPHeaderField: "User-Agent") == "Mozilla/5.0"
        })
        #expect(requests.allSatisfy {
            $0.value(forHTTPHeaderField: "Referer") == "https://quote.eastmoney.com/"
        })
    }

    @Test("URLSession transport accepts 2xx and rejects non-2xx responses")
    func urlSessionStatusHandling() async {
        let session = makeStubSession { request in
            if request.url?.absoluteString.contains("118.AU9999") == true {
                return .response(
                    status: 200,
                    data: Data(
                        #"{"data":{"f43":88940,"f59":2,"f60":91563,"f169":-2623,"f170":-286}}"#.utf8
                    )
                )
            }
            return .response(status: 503, data: Data())
        }
        let service = MarketService(session: session)

        let snapshot = await service.fetch(current: MarketSnapshot())

        #expect(snapshot.gold?.price == 889.4)
        #expect(snapshot.shanghaiIndex == nil)
        #expect(snapshot.updatedAt != nil)
    }

    @Test("URLSession transport converts request errors to missing data")
    func urlSessionErrorHandling() async {
        let session = makeStubSession { _ in
            .failure(URLError(.notConnectedToInternet))
        }
        let service = MarketService(session: session)

        let snapshot = await service.fetch(current: MarketSnapshot())

        #expect(snapshot.gold == nil)
        #expect(snapshot.shanghaiIndex == nil)
        #expect(snapshot.isLoading == false)
        #expect(snapshot.updatedAt == nil)
    }

    @Test("Default transport can be constructed")
    func defaultTransportConstruction() {
        _ = MarketService()
    }

    private func makeService(responses: [String: String]) -> MarketService {
        MarketService { request in
            guard let url = request.url,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let securityID = components.queryItems?.first(where: { $0.name == "secid" })?.value,
                  let response = responses[securityID]
            else {
                return nil
            }
            return Data(response.utf8)
        }
    }

    private func makeStubSession(
        handler: @escaping @Sendable (URLRequest) -> MarketStubResult
    ) -> URLSession {
        MarketURLProtocolStub.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MarketURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }
}

private actor RequestRecorder {
    private(set) var requests: [URLRequest] = []

    func append(_ request: URLRequest) {
        requests.append(request)
    }
}

private enum MarketStubResult: Sendable {
    case response(status: Int, data: Data)
    case failure(URLError)
}

private final class MarketURLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler:
        (@Sendable (URLRequest) -> MarketStubResult)?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        switch handler(request) {
        case let .response(status, data):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
