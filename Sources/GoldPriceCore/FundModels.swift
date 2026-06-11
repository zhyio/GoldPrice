import Foundation

struct FundHolding: Equatable, Sendable {
    let code: String
    let name: String
    let amount: Double
    let profit: Double
    var todayChangePercent: Double?
    var estimateTime: String?

    var profitTrend: Trend {
        Trend(value: profit)
    }

    var todayTrend: Trend? {
        todayChangePercent.map(Trend.init(value:))
    }

    var formattedProfit: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let formatted = formatter.string(from: NSNumber(value: profit)) ?? "0.00"
        return profit > 0 ? "+\(formatted)" : formatted
    }

    var formattedTodayChange: String {
        guard let todayChangePercent else { return "--" }
        return Self.formatSigned(todayChangePercent, suffix: "%")
    }

    private static func formatSigned(_ value: Double, suffix: String) -> String {
        let format = value > 0 ? "+%.2f%@" : "%.2f%@"
        return String(
            format: format,
            locale: Locale(identifier: "en_US_POSIX"),
            value,
            suffix
        )
    }
}

struct FundPortfolio: Equatable, Sendable {
    var holdings: [FundHolding]
    var updatedAt: Date?
    var isLoading: Bool

    static let initial = FundPortfolio(
        holdings: [
            FundHolding(
                code: "008702",
                name: "华夏黄金ETF联接C",
                amount: 500.01,
                profit: 0.01
            ),
            FundHolding(
                code: "013642",
                name: "博道成长智航股票C",
                amount: 972.83,
                profit: -27.17
            ),
            FundHolding(
                code: "019594",
                name: "嘉实稳宁纯债债券A",
                amount: 101_781.48,
                profit: 1_711.50
            ),
            FundHolding(
                code: "027300",
                name: "富国电子信息产业混合发起式C",
                amount: 2_000,
                profit: 0
            ),
            FundHolding(
                code: "020341",
                name: "工银黄金ETF联接E",
                amount: 1_000,
                profit: 0
            )
        ],
        updatedAt: nil,
        isLoading: true
    )
}

struct FundEstimateResponse: Decodable, Equatable, Sendable {
    let fundCode: String
    let estimatedChangePercent: String
    let estimateTime: String

    enum CodingKeys: String, CodingKey {
        case fundCode = "fundcode"
        case estimatedChangePercent = "gszzl"
        case estimateTime = "gztime"
    }

    var changePercent: Double? {
        guard let value = Double(estimatedChangePercent), value.isFinite else {
            return nil
        }
        return value
    }
}

enum FundEstimateParser {
    static func parse(_ data: Data, decoder: JSONDecoder = JSONDecoder()) -> FundEstimateResponse? {
        guard let response = String(data: data, encoding: .utf8) else { return nil }
        return parse(response, decoder: decoder)
    }

    static func parse(_ response: String, decoder: JSONDecoder = JSONDecoder()) -> FundEstimateResponse? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("jsonpgz("),
              let closingParenthesis = trimmed.lastIndex(of: ")")
        else {
            return nil
        }

        let jsonStart = trimmed.index(trimmed.startIndex, offsetBy: "jsonpgz(".count)
        guard jsonStart < closingParenthesis else { return nil }

        let json = trimmed[jsonStart..<closingParenthesis]
        guard !json.isEmpty else { return nil }
        return try? decoder.decode(FundEstimateResponse.self, from: Data(json.utf8))
    }
}
