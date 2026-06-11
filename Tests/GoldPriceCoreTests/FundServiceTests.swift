import Foundation
import Testing
@testable import GoldPriceCore

@Suite("Fund estimate service")
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
}
