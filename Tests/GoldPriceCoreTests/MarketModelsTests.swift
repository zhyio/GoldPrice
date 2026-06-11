import Testing
@testable import GoldPriceCore

@Suite("Market quote calculations")
struct MarketModelsTests {
    @Test("Upward change")
    func upwardChange() {
        let quote = MarketQuote(
            price: 105,
            comparisonBase: 100,
            changeAmount: 5,
            changePercent: 5
        )

        #expect(quote.trend == .up)
        #expect(quote.formattedChangePercent == "+5.00%")
    }

    @Test("Downward change")
    func downwardChange() {
        let quote = MarketQuote(
            price: 95,
            comparisonBase: 100,
            changeAmount: -5,
            changePercent: -5
        )

        #expect(quote.trend == .down)
        #expect(quote.formattedChangePercent == "-5.00%")
    }

    @Test("Flat change")
    func flatChange() {
        let quote = MarketQuote(
            price: 100,
            comparisonBase: 100,
            changeAmount: 0,
            changePercent: 0
        )

        #expect(quote.trend == .flat)
        #expect(quote.formattedChangePercent == "0.00%")
    }

    @Test("Formatting uses the server percentage")
    func usesServerPercentage() {
        let quote = MarketQuote(
            price: 889.40,
            comparisonBase: 915.63,
            changeAmount: -26.23,
            changePercent: -2.86
        )

        #expect(quote.formattedChangePercent == "-2.86%")
    }
}
