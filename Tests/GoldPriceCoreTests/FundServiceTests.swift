import Foundation
import Testing
@testable import GoldPriceCore

@Suite("Fund estimate service", .serialized)
struct FundServiceTests {
    @Test("Parses EastMoney JSONP estimate with NAV fields")
    func parsesEstimate() {
        let response = #"jsonpgz({"fundcode":"008702","name":"华夏黄金ETF联接C","jzrq":"2026-06-10","dwjz":"1.9782","gsz":"1.9196","gszzl":"-2.96","gztime":"2026-06-11 13:31"});"#

        let estimate = FundEstimateParser.parse(response)

        #expect(estimate?.fundCode == "008702")
        #expect(estimate?.name == "华夏黄金ETF联接C")
        #expect(estimate?.changePercent == -2.96)
        #expect(estimate?.navValue == 1.9196)
        #expect(estimate?.prevNavValue == 1.9782)
        #expect(estimate?.estimateTime == "2026-06-11 13:31")
    }

    @Test("Parses response without optional NAV fields")
    func parsesMinimalResponse() {
        let response = #"jsonpgz({"fundcode":"020341","gszzl":"-2.95","gztime":"2026-06-11 13:30"});"#

        let estimate = FundEstimateParser.parse(response)

        #expect(estimate?.fundCode == "020341")
        #expect(estimate?.name == nil)
        #expect(estimate?.navValue == nil)
        #expect(estimate?.prevNavValue == nil)
        #expect(estimate?.changePercent == -2.95)
    }

    @Test("Handles an unavailable estimate")
    func handlesUnavailableEstimate() {
        #expect(FundEstimateParser.parse("jsonpgz();") == nil)
    }

    @Test("Updates NAV data and auto-initializes shares")
    func updatesNAVAndShares() async {
        let portfolio = FundPortfolio(
            holdings: [
                FundHolding(code: "008702", name: "Test", costBasis: 1000, shares: 0),
                FundHolding(code: "020341", name: "Test2", costBasis: 500, shares: 100),
            ],
            updatedAt: nil,
            isLoading: true
        )

        let service = FundService { request in
            guard let filename = request.url?.lastPathComponent else { return nil }
            let responses = [
                "008702.js": #"jsonpgz({"fundcode":"008702","name":"华夏黄金ETF联接C","dwjz":"2.0","gsz":"2.1","gszzl":"5.00","gztime":"2026-06-11 13:31"});"#,
                "020341.js": #"jsonpgz({"fundcode":"020341","name":"工银黄金ETF联接E","dwjz":"1.0","gsz":"1.05","gszzl":"5.00","gztime":"2026-06-11 13:30"});"#,
            ]
            return responses[filename].map { Data($0.utf8) }
        }

        let updated = await service.fetch(current: portfolio)

        // Fund with shares == 0 should auto-initialize: 1000 / 2.1 ≈ 476.19
        #expect(updated.holdings[0].shares > 0)
        #expect(abs(updated.holdings[0].shares - 1000.0 / 2.1) < 0.01)
        #expect(updated.holdings[0].estimatedNAV == 2.1)
        #expect(updated.holdings[0].previousNAV == 2.0)
        #expect(updated.holdings[0].name == "华夏黄金ETF联接C")

        // Fund with existing shares should keep them
        #expect(updated.holdings[1].shares == 100)
        #expect(updated.holdings[1].estimatedNAV == 1.05)
        #expect(updated.holdings[1].name == "工银黄金ETF联接E")

        #expect(updated.isLoading == false)
        #expect(updated.updatedAt != nil)
    }

    @Test("Code mismatches and unavailable estimates preserve existing values")
    func rejectsMismatchedAndUnavailableEstimates() async {
        var first = FundHolding(code: "008702", name: "Existing", costBasis: 1_000, shares: 500)
        first.estimatedNAV = 2
        first.previousNAV = 1.9
        let portfolio = FundPortfolio(
            holdings: [
                first,
                FundHolding(code: "027300", name: "No estimate", costBasis: 2_000, shares: 0)
            ],
            updatedAt: Date(timeIntervalSince1970: 1_000),
            isLoading: true
        )
        let service = FundService { request in
            switch request.url?.lastPathComponent {
            case "008702.js":
                return Data(#"jsonpgz({"fundcode":"999999","name":"Wrong","dwjz":"2","gsz":"3","gszzl":"50","gztime":"now"});"#.utf8)
            case "027300.js":
                return Data("jsonpgz();".utf8)
            default:
                return nil
            }
        }

        let updated = await service.fetch(current: portfolio)

        #expect(updated.holdings == portfolio.holdings)
        #expect(updated.updatedAt == portfolio.updatedAt)
        #expect(updated.isLoading == false)
    }

    @Test("Updates all independently returned estimates")
    func updatesConcurrentResponses() async {
        let portfolio = FundPortfolio(
            holdings: [
                FundHolding(code: "008702", name: "One", costBasis: 100, shares: 10),
                FundHolding(code: "020341", name: "Two", costBasis: 200, shares: 20),
                FundHolding(code: "019594", name: "Three", costBasis: 300, shares: 30)
            ],
            updatedAt: nil,
            isLoading: true
        )
        let service = FundService { request in
            guard let code = request.url?.deletingPathExtension().lastPathComponent else {
                return nil
            }
            try? await Task.sleep(for: .milliseconds(Int.random(in: 1...10)))
            return Data(
                #"jsonpgz({"fundcode":"\#(code)","name":"Fund \#(code)","dwjz":"1","gsz":"1.1","gszzl":"10","gztime":"15:00"});"#.utf8
            )
        }

        let updated = await service.fetch(current: portfolio)

        #expect(updated.holdings.map(\.name) == [
            "Fund 008702", "Fund 020341", "Fund 019594"
        ])
        #expect(updated.holdings.allSatisfy { $0.estimatedNAV == 1.1 })
        #expect(updated.updatedAt != nil)
    }

    @Test("Requests contain the expected URL, cache buster, and headers")
    func requestShape() async {
        let recorder = FundRequestRecorder()
        let portfolio = FundPortfolio(
            holdings: [
                FundHolding(code: "008702", name: "Test", costBasis: 100, shares: 0)
            ],
            updatedAt: nil,
            isLoading: true
        )
        let service = FundService { request in
            await recorder.append(request)
            return nil
        }

        _ = await service.fetch(current: portfolio)
        let requests = await recorder.requests
        let request = requests.first
        let components = request.flatMap {
            URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)
        }

        #expect(requests.count == 1)
        #expect(request?.url?.lastPathComponent == "008702.js")
        #expect(components?.queryItems?.contains(where: { $0.name == "rt" }) == true)
        #expect(request?.value(forHTTPHeaderField: "User-Agent") == "Mozilla/5.0")
        #expect(request?.value(forHTTPHeaderField: "Referer") == "https://fund.eastmoney.com/")
    }

    @Test("URLSession transport accepts 2xx responses")
    func urlSessionSuccess() async {
        let session = makeStubSession {
            .response(
                status: 200,
                data: Data(
                    #"jsonpgz({"fundcode":"008702","name":"Live","dwjz":"2","gsz":"2.1","gszzl":"5","gztime":"15:00"});"#.utf8
                )
            )
        }
        let service = FundService(session: session)
        let portfolio = FundPortfolio(
            holdings: [
                FundHolding(code: "008702", name: "Old", costBasis: 100, shares: 50)
            ],
            updatedAt: nil,
            isLoading: true
        )

        let updated = await service.fetch(current: portfolio)

        #expect(updated.holdings[0].name == "Live")
        #expect(updated.holdings[0].estimatedNAV == 2.1)
    }

    @Test("URLSession transport rejects non-2xx and request errors")
    func urlSessionFailures() async {
        let portfolio = FundPortfolio(
            holdings: [
                FundHolding(code: "008702", name: "Old", costBasis: 100, shares: 50)
            ],
            updatedAt: nil,
            isLoading: true
        )
        var session = makeStubSession {
            .response(status: 500, data: Data())
        }
        var updated = await FundService(session: session).fetch(current: portfolio)
        #expect(updated.holdings == portfolio.holdings)

        session = makeStubSession {
            .failure(URLError(.timedOut))
        }
        updated = await FundService(session: session).fetch(current: portfolio)
        #expect(updated.holdings == portfolio.holdings)
    }

    @Test("Default transport can be constructed")
    func defaultTransportConstruction() {
        _ = FundService()
    }

    private func makeStubSession(
        handler: @escaping @Sendable () -> FundStubResult
    ) -> URLSession {
        FundURLProtocolStub.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FundURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }
}

private actor FundRequestRecorder {
    private(set) var requests: [URLRequest] = []

    func append(_ request: URLRequest) {
        requests.append(request)
    }
}

private enum FundStubResult: Sendable {
    case response(status: Int, data: Data)
    case failure(URLError)
}

private final class FundURLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable () -> FundStubResult)?

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

        switch handler() {
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
