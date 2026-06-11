import Foundation
import Testing
@testable import GoldPriceCore

@Suite("Fund portfolio operations")
struct FundPortfolioOperationsTests {
    @Test("Adds a normalized six-digit fund")
    func addsFund() throws {
        var portfolio = FundPortfolio.empty

        let code = try portfolio.addFund(code: " 008702\n", costBasis: 1_000)

        #expect(code == "008702")
        #expect(portfolio.holdings == [
            FundHolding(code: "008702", name: "基金 008702", costBasis: 1_000, shares: 0)
        ])
    }

    @Test("Rejects invalid fund codes")
    func rejectsInvalidCodes() {
        for code in ["", "12345", "1234567", "12A456", "１２３４５６"] {
            var portfolio = FundPortfolio.empty
            #expect(throws: FundOperationError.invalidCode) {
                try portfolio.addFund(code: code, costBasis: 100)
            }
        }
    }

    @Test("Rejects invalid amounts")
    func rejectsInvalidAmounts() {
        let invalidAmounts: [Double] = [0, -1, .nan, .infinity, -.infinity]
        for amount in invalidAmounts {
            var portfolio = FundPortfolio.empty
            #expect(throws: FundOperationError.invalidAmount) {
                try portfolio.addFund(code: "008702", costBasis: amount)
            }
        }
    }

    @Test("Rejects duplicate funds")
    func rejectsDuplicate() {
        var portfolio = FundPortfolio(
            holdings: [holding()],
            updatedAt: nil,
            isLoading: false
        )

        #expect(throws: FundOperationError.duplicateFund) {
            try portfolio.addFund(code: "008702", costBasis: 500)
        }
        #expect(portfolio.holdings.count == 1)
    }

    @Test("Increase uses estimated NAV and updates shares and cost basis")
    func increasesHolding() throws {
        var existing = holding(costBasis: 1_000, shares: 500)
        existing.estimatedNAV = 2
        existing.previousNAV = 1.9
        var portfolio = portfolio(existing)

        try portfolio.adjustFund(code: "008702", amount: 200, isIncrease: true)

        #expect(portfolio.holdings[0].costBasis == 1_200)
        #expect(portfolio.holdings[0].shares == 600)
    }

    @Test("Increase falls back to previous NAV")
    func increaseUsesPreviousNAV() throws {
        var existing = holding(costBasis: 1_000, shares: 500)
        existing.previousNAV = 2
        var portfolio = portfolio(existing)

        try portfolio.adjustFund(code: "008702", amount: 100, isIncrease: true)

        #expect(portfolio.holdings[0].costBasis == 1_100)
        #expect(portfolio.holdings[0].shares == 550)
    }

    @Test("Decrease removes shares and proportional cost")
    func decreasesHolding() throws {
        var existing = holding(costBasis: 1_000, shares: 500)
        existing.estimatedNAV = 2
        var portfolio = portfolio(existing)

        try portfolio.adjustFund(code: "008702", amount: 200, isIncrease: false)

        #expect(portfolio.holdings[0].shares == 400)
        #expect(portfolio.holdings[0].costBasis == 800)
    }

    @Test("Full decrease normalizes residual values to zero")
    func fullDecrease() throws {
        var existing = holding(costBasis: 1_000, shares: 500)
        existing.estimatedNAV = 2
        var portfolio = portfolio(existing)

        try portfolio.adjustFund(code: "008702", amount: 1_000, isIncrease: false)

        #expect(portfolio.holdings[0].shares == 0)
        #expect(portfolio.holdings[0].costBasis == 0)
    }

    @Test("Rejects adjustments without a usable NAV")
    func rejectsMissingNAV() {
        var portfolio = portfolio(holding())

        #expect(throws: FundOperationError.navUnavailable) {
            try portfolio.adjustFund(code: "008702", amount: 100, isIncrease: true)
        }
        #expect(portfolio.holdings[0].costBasis == 1_000)
    }

    @Test("Rejects a decrease above market value")
    func rejectsExcessiveDecrease() {
        var existing = holding(costBasis: 1_000, shares: 500)
        existing.estimatedNAV = 2
        var portfolio = portfolio(existing)

        #expect(throws: FundOperationError.exceedsHolding) {
            try portfolio.adjustFund(code: "008702", amount: 1_000.01, isIncrease: false)
        }
        #expect(portfolio.holdings[0].shares == 500)
    }

    @Test("Rejects invalid adjustment input and missing holdings")
    func rejectsInvalidAdjustment() {
        var portfolio = portfolio(holding())

        #expect(throws: FundOperationError.invalidAmount) {
            try portfolio.adjustFund(code: "008702", amount: .nan, isIncrease: true)
        }
        #expect(throws: FundOperationError.invalidCode) {
            try portfolio.adjustFund(code: "bad", amount: 100, isIncrease: true)
        }
        #expect(throws: FundOperationError.holdingNotFound) {
            try portfolio.adjustFund(code: "020341", amount: 100, isIncrease: true)
        }
    }

    @Test("Rejects a decrease when shares are unavailable")
    func rejectsDecreaseWithoutShares() {
        var existing = holding()
        existing.estimatedNAV = 2
        var portfolio = portfolio(existing)

        #expect(throws: FundOperationError.navUnavailable) {
            try portfolio.adjustFund(code: "008702", amount: 100, isIncrease: false)
        }
    }

    @Test("Deletes an existing holding and rejects a missing one")
    func deletesHolding() throws {
        var portfolio = portfolio(holding())

        try portfolio.deleteFund(code: "008702")

        #expect(portfolio.holdings.isEmpty)
        #expect(throws: FundOperationError.holdingNotFound) {
            try portfolio.deleteFund(code: "008702")
        }
        #expect(throws: FundOperationError.invalidCode) {
            try portfolio.deleteFund(code: "invalid")
        }
    }

    @Test("Every operation error has a user-facing message")
    func errorDescriptions() {
        let errors: [FundOperationError] = [
            .invalidCode,
            .invalidAmount,
            .duplicateFund,
            .holdingNotFound,
            .navUnavailable,
            .exceedsHolding
        ]

        #expect(errors.allSatisfy { !($0.errorDescription ?? "").isEmpty })
    }

    private func portfolio(_ holding: FundHolding) -> FundPortfolio {
        FundPortfolio(holdings: [holding], updatedAt: nil, isLoading: false)
    }

    private func holding(
        costBasis: Double = 1_000,
        shares: Double = 0
    ) -> FundHolding {
        FundHolding(
            code: "008702",
            name: "Test",
            costBasis: costBasis,
            shares: shares
        )
    }
}
