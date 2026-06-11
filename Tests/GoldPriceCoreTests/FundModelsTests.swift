import Foundation
import Testing
@testable import GoldPriceCore

@Suite("Fund holdings")
struct FundModelsTests {
    @Test("Migration defaults have correct cost bases")
    func migrationDefaults() {
        let holdings = FundPortfolio.migrateDefaults().holdings

        #expect(holdings.map(\.code) == [
            "008702", "013642", "019594", "027300", "020341"
        ])
        #expect(holdings.map(\.costBasis) == [
            500.00, 1_000.00, 100_069.98, 2_000.00, 1_000.00
        ])
        #expect(holdings.allSatisfy { $0.shares == 0 })
    }

    @Test("Profit calculation: estimatedValue - costBasis")
    func profitCalculation() {
        var holding = FundHolding(code: "008702", name: "Test", costBasis: 1000, shares: 500)
        holding.estimatedNAV = 2.2
        holding.previousNAV = 2.0

        #expect(holding.estimatedValue == 1100)
        #expect(holding.profit == 100)
        #expect(holding.formattedProfit == "+100.00")
        #expect(holding.profitTrend == .up)
    }

    @Test("Today change: shares × (estimatedNAV - previousNAV)")
    func todayChangeCalculation() {
        var holding = FundHolding(code: "008702", name: "Test", costBasis: 1000, shares: 500)
        holding.estimatedNAV = 2.2
        holding.previousNAV = 2.0

        #expect(abs(holding.todayChange! - 100) < 0.001)
        #expect(holding.formattedTodayChange == "+100.00")
        #expect(holding.todayTrend == .up)
    }

    @Test("Missing NAV shows placeholders")
    func missingNAV() {
        let holding = FundHolding(code: "008702", name: "Test", costBasis: 1000, shares: 500)

        #expect(holding.estimatedValue == nil)
        #expect(holding.profit == nil)
        #expect(holding.todayChange == nil)
        #expect(holding.formattedProfit == "--")
        #expect(holding.formattedTodayChange == "--")
    }

    @Test("Negative profit displays correctly")
    func negativeProfit() {
        var holding = FundHolding(code: "013642", name: "Test", costBasis: 1000, shares: 500)
        holding.estimatedNAV = 1.8
        holding.previousNAV = 2.0

        #expect(holding.profit == -100)
        #expect(holding.formattedProfit == "-100.00")
        #expect(holding.profitTrend == .down)
        #expect(abs(holding.todayChange! - (-100)) < 0.001)
        #expect(holding.todayTrend == .down)
    }

    @Test("Codable only persists code, name, costBasis, shares")
    func codableRoundTrip() throws {
        var holding = FundHolding(code: "008702", name: "Test Fund", costBasis: 1000, shares: 500)
        holding.estimatedNAV = 2.0
        holding.previousNAV = 1.9
        holding.todayChangePercent = 5.26
        holding.estimateTime = "2026-06-11 13:30"

        let data = try JSONEncoder().encode(holding)
        let decoded = try JSONDecoder().decode(FundHolding.self, from: data)

        #expect(decoded.code == "008702")
        #expect(decoded.name == "Test Fund")
        #expect(decoded.costBasis == 1000)
        #expect(decoded.shares == 500)
        #expect(decoded.estimatedNAV == nil)
        #expect(decoded.previousNAV == nil)
        #expect(decoded.todayChangePercent == nil)
        #expect(decoded.estimateTime == nil)
    }

    @Test("Formatting handles grouping, zero, and negative values")
    func amountFormatting() {
        #expect(FundHolding.formatAmount(123_456.789) == "123,456.79")
        #expect(FundHolding.formatSigned(0) == "0.00")
        #expect(FundHolding.formatSigned(-12.5) == "-12.50")
    }

    @Test("Today change needs positive shares and previous NAV")
    func todayChangeRequirements() {
        var holding = FundHolding(code: "008702", name: "Test", costBasis: 100, shares: 0)
        holding.estimatedNAV = 2
        holding.previousNAV = 1
        #expect(holding.todayChange == nil)

        holding.shares = 10
        holding.previousNAV = 0
        #expect(holding.todayChange == nil)
    }

    @Test("Estimate numeric fields reject invalid and non-positive values")
    func estimateValidation() throws {
        let invalid = try JSONDecoder().decode(
            FundEstimateResponse.self,
            from: Data(#"{"fundcode":"008702","dwjz":"0","gsz":"-1","gszzl":"not-a-number","gztime":"now"}"#.utf8)
        )

        #expect(invalid.changePercent == nil)
        #expect(invalid.navValue == nil)
        #expect(invalid.prevNavValue == nil)
    }
}
