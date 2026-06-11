import Foundation

enum Trend: Equatable, Sendable {
    case up
    case down
    case flat
}

struct MarketQuote: Equatable, Sendable {
    let price: Double
    let comparisonBase: Double
    let changeAmount: Double
    let changePercent: Double

    var trend: Trend {
        if changePercent > 0 { return .up }
        if changePercent < 0 { return .down }
        return .flat
    }

    var formattedChangePercent: String {
        switch trend {
        case .up:
            return String(format: "+%.2f%%", locale: Locale(identifier: "en_US_POSIX"), changePercent)
        case .down:
            return String(format: "%.2f%%", locale: Locale(identifier: "en_US_POSIX"), changePercent)
        case .flat:
            return "0.00%"
        }
    }
}

struct MarketSnapshot: Sendable {
    var gold: MarketQuote?
    var shanghaiIndex: MarketQuote?
    var updatedAt: Date?
    var isLoading = true
}

struct EastMoneyResponse: Decodable, Equatable, Sendable {
    let data: EastMoneyQuote?
}

struct EastMoneyQuote: Decodable, Equatable, Sendable {
    let current: Double
    let precision: Int
    let comparisonBase: Double
    let changeAmount: Double
    let changePercent: Double

    enum CodingKeys: String, CodingKey {
        case current = "f43"
        case precision = "f59"
        case comparisonBase = "f60"
        case changeAmount = "f169"
        case changePercent = "f170"
    }

    var marketQuote: MarketQuote? {
        guard precision >= 0,
              precision <= 8,
              current.isFinite,
              comparisonBase.isFinite,
              comparisonBase > 0,
              changeAmount.isFinite,
              changePercent.isFinite
        else {
            return nil
        }

        let priceDivisor = pow(10, Double(precision))
        return MarketQuote(
            price: current / priceDivisor,
            comparisonBase: comparisonBase / priceDivisor,
            changeAmount: changeAmount / priceDivisor,
            changePercent: changePercent / 100
        )
    }
}

enum QuoteParser {
    static func parseEastMoney(_ data: Data, decoder: JSONDecoder = JSONDecoder()) -> MarketQuote? {
        try? decoder.decode(EastMoneyResponse.self, from: data).data?.marketQuote
    }

    static func parseEastMoney(_ response: String) -> MarketQuote? {
        parseEastMoney(Data(response.utf8))
    }
}
