import Foundation
import Testing
@testable import GoldPriceCore

@Suite("Fund estimate service")
struct FundServiceTests {
    @Test("Parses EastMoney JSONP estimate")
    func parsesEstimate() {
        let response = #"jsonpgz({"fundcode":"008702","name":"华夏黄金ETF联接C","jzrq":"2026-06-10","dwjz":"1.9782","gsz":"1.9196","gszzl":"-2.96","gztime":"2026-06-11 13:31"});"#

        let estimate = FundEstimateParser.parse(response)

        #expect(estimate?.fundCode == "008702")
        #expect(estimate?.changePercent == -2.96)
        #expect(estimate?.estimateTime == "2026-06-11 13:31")
    }

    @Test("Handles an unavailable estimate")
    func handlesUnavailableEstimate() {
        #expect(FundEstimateParser.parse("jsonpgz();") == nil)
    }

    @Test("Updates successful funds and preserves failed values")
    func preservesFailedFund() async {
        var current = FundPortfolio.initial
        current.holdings[3].todayChangePercent = 1.23
        current.holdings[3].estimateTime = "previous"

        let service = FundService { request in
            guard let filename = request.url?.lastPathComponent else { return nil }
            let responses = [
                "008702.js": #"jsonpgz({"fundcode":"008702","gszzl":"-2.96","gztime":"2026-06-11 13:31"});"#,
                "020341.js": #"jsonpgz({"fundcode":"020341","gszzl":"-2.95","gztime":"2026-06-11 13:30"});"#
            ]
            return responses[filename].map { Data($0.utf8) }
        }

        let updated = await service.fetch(current: current)

        #expect(updated.holdings[0].todayChangePercent == -2.96)
        #expect(updated.holdings[3].todayChangePercent == 1.23)
        #expect(updated.holdings[3].estimateTime == "previous")
        #expect(updated.holdings[4].todayChangePercent == -2.95)
        #expect(updated.isLoading == false)
        #expect(updated.updatedAt != nil)
    }
}
