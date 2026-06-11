import Foundation
import Testing
@testable import GoldPriceCore

@Suite("Market service snapshots")
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
}
