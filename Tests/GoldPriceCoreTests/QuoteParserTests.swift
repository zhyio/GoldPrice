import Testing
@testable import GoldPriceCore

@Suite("Quote response parsing")
struct QuoteParserTests {
    @Test("AU9999 uses previous settlement fields")
    func parsesAU9999Response() {
        let response = #"{"rc":0,"data":{"f43":88940,"f59":2,"f60":91563,"f169":-2623,"f170":-286}}"#

        let quote = QuoteParser.parseEastMoney(response)

        #expect(quote == MarketQuote(
            price: 889.40,
            comparisonBase: 915.63,
            changeAmount: -26.23,
            changePercent: -2.86
        ))
    }

    @Test("Shanghai index uses previous close fields")
    func parsesShanghaiIndexResponse() {
        let response = #"{"rc":0,"data":{"f43":397347,"f59":2,"f60":399323,"f169":-1976,"f170":-49}}"#

        let quote = QuoteParser.parseEastMoney(response)

        #expect(quote == MarketQuote(
            price: 3973.47,
            comparisonBase: 3993.23,
            changeAmount: -19.76,
            changePercent: -0.49
        ))
    }

    @Test("Missing quote data")
    func handlesMissingData() {
        #expect(QuoteParser.parseEastMoney(#"{"rc":1,"data":null}"#) == nil)
    }

    @Test("Missing authoritative change fields")
    func rejectsIncompleteData() {
        #expect(QuoteParser.parseEastMoney(#"{"data":{"f43":88940,"f59":2,"f60":91563}}"#) == nil)
    }

    @Test("Invalid comparison base")
    func rejectsInvalidComparisonBase() {
        let response = #"{"data":{"f43":88940,"f59":2,"f60":0,"f169":-2623,"f170":-286}}"#

        #expect(QuoteParser.parseEastMoney(response) == nil)
    }
}
