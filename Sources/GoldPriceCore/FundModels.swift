import Foundation

struct FundHolding: Equatable, Sendable {
    let code: String
    var name: String
    var costBasis: Double
    var shares: Double

    var estimatedNAV: Double?
    var previousNAV: Double?
    var todayChangePercent: Double?
    var estimateTime: String?

    var estimatedValue: Double? {
        guard let nav = estimatedNAV, nav > 0, shares > 0 else { return nil }
        return shares * nav
    }

    var profit: Double? {
        guard let value = estimatedValue else { return nil }
        return value - costBasis
    }

    var todayChange: Double? {
        guard let nav = estimatedNAV, let prevNav = previousNAV,
              prevNav > 0, shares > 0 else { return nil }
        return shares * (nav - prevNav)
    }

    var profitTrend: Trend {
        Trend(value: profit ?? 0)
    }

    var todayTrend: Trend? {
        todayChange.map(Trend.init(value:))
    }

    var formattedProfit: String {
        guard let profit else { return "--" }
        return Self.formatSigned(profit)
    }

    var formattedTodayChange: String {
        guard let change = todayChange else { return "--" }
        return Self.formatSigned(change)
    }

    var formattedCostBasis: String {
        Self.formatAmount(costBasis)
    }

    static func formatSigned(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let formatted = formatter.string(from: NSNumber(value: value)) ?? "0.00"
        return value > 0 ? "+\(formatted)" : formatted
    }

    static func formatAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "--"
    }
}

extension FundHolding: Codable {
    enum CodingKeys: String, CodingKey {
        case code, name, costBasis, shares
    }
}

struct FundPortfolio: Equatable, Sendable {
    var holdings: [FundHolding]
    var updatedAt: Date?
    var isLoading: Bool

    static let empty = FundPortfolio(holdings: [], updatedAt: nil, isLoading: true)

    static func migrateDefaults() -> FundPortfolio {
        let defaults: [(code: String, name: String, costBasis: Double)] = [
            ("008702", "华夏黄金ETF联接C", 500.00),
            ("013642", "博道成长智航股票C", 1_000.00),
            ("019594", "嘉实稳宁纯债债券A", 100_069.98),
            ("027300", "富国电子信息产业混合发起式C", 2_000.00),
            ("020341", "工银黄金ETF联接E", 1_000.00),
        ]
        return FundPortfolio(
            holdings: defaults.map {
                FundHolding(code: $0.code, name: $0.name, costBasis: $0.costBasis, shares: 0)
            },
            updatedAt: nil,
            isLoading: true
        )
    }
}

struct FundEstimateResponse: Decodable, Equatable, Sendable {
    let fundCode: String
    let name: String?
    let previousNAVString: String?
    let estimatedNAVString: String?
    let estimatedChangePercent: String
    let estimateTime: String

    enum CodingKeys: String, CodingKey {
        case fundCode = "fundcode"
        case name
        case previousNAVString = "dwjz"
        case estimatedNAVString = "gsz"
        case estimatedChangePercent = "gszzl"
        case estimateTime = "gztime"
    }

    var changePercent: Double? {
        guard let value = Double(estimatedChangePercent), value.isFinite else {
            return nil
        }
        return value
    }

    var navValue: Double? {
        guard let str = estimatedNAVString,
              let value = Double(str), value.isFinite, value > 0 else {
            return nil
        }
        return value
    }

    var prevNavValue: Double? {
        guard let str = previousNAVString,
              let value = Double(str), value.isFinite, value > 0 else {
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
