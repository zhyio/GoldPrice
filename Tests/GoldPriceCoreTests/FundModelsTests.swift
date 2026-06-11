import Testing
@testable import GoldPriceCore

@Suite("Fund holdings")
struct FundModelsTests {
    @Test("Initial holdings match the supplied screenshots")
    func initialHoldings() {
        let holdings = FundPortfolio.initial.holdings

        #expect(holdings.map(\.code) == [
            "008702", "013642", "019594", "027300", "020341"
        ])
        #expect(holdings.map(\.amount) == [
            500.01, 972.83, 101_781.48, 2_000, 1_000
        ])
        #expect(holdings.map(\.profit) == [
            0.01, -27.17, 1_711.50, 0, 0
        ])
    }

    @Test("Profit and daily change use signed formatting")
    func signedFormatting() {
        var holding = FundPortfolio.initial.holdings[0]
        holding.todayChangePercent = -2.96

        #expect(holding.formattedProfit == "+0.01")
        #expect(holding.formattedTodayChange == "-2.96%")
        #expect(holding.profitTrend == .up)
        #expect(holding.todayTrend == .down)

        let largeProfit = FundPortfolio.initial.holdings[2]
        #expect(largeProfit.formattedProfit == "+1,711.50")
    }

    @Test("Missing daily estimate is displayed as unavailable")
    func missingEstimate() {
        let holding = FundPortfolio.initial.holdings[3]

        #expect(holding.formattedTodayChange == "--")
        #expect(holding.todayTrend == nil)
    }
}
