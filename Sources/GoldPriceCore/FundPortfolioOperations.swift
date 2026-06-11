import Foundation

enum FundOperationError: Error, Equatable, LocalizedError, Sendable {
    case invalidCode
    case invalidAmount
    case duplicateFund
    case holdingNotFound
    case navUnavailable
    case exceedsHolding

    var errorDescription: String? {
        switch self {
        case .invalidCode:
            return "基金代码必须是 6 位数字"
        case .invalidAmount:
            return "金额必须是大于 0 的有效数字"
        case .duplicateFund:
            return "该基金已在持仓列表中"
        case .holdingNotFound:
            return "未找到对应的基金持仓"
        case .navUnavailable:
            return "暂无可用净值，暂时无法调仓"
        case .exceedsHolding:
            return "减仓金额超过当前持有市值"
        }
    }
}

extension FundPortfolio {
    @discardableResult
    mutating func addFund(code rawCode: String, costBasis: Double) throws -> String {
        let code = try Self.validatedCode(rawCode)
        try Self.validateAmount(costBasis)
        guard !holdings.contains(where: { $0.code == code }) else {
            throw FundOperationError.duplicateFund
        }

        holdings.append(
            FundHolding(
                code: code,
                name: "基金 \(code)",
                costBasis: costBasis,
                shares: 0
            )
        )
        return code
    }

    mutating func adjustFund(code rawCode: String, amount: Double, isIncrease: Bool) throws {
        let code = try Self.validatedCode(rawCode)
        try Self.validateAmount(amount)
        guard let index = holdings.firstIndex(where: { $0.code == code }) else {
            throw FundOperationError.holdingNotFound
        }

        let holding = holdings[index]
        guard let nav = holding.estimatedNAV ?? holding.previousNAV,
              nav.isFinite,
              nav > 0
        else {
            throw FundOperationError.navUnavailable
        }

        if isIncrease {
            holdings[index].costBasis += amount
            holdings[index].shares += amount / nav
            return
        }

        guard holding.shares.isFinite, holding.shares > 0 else {
            throw FundOperationError.navUnavailable
        }
        let sharesToSell = amount / nav
        guard sharesToSell <= holding.shares else {
            throw FundOperationError.exceedsHolding
        }

        let proportion = sharesToSell / holding.shares
        holdings[index].costBasis -= proportion * holding.costBasis
        holdings[index].shares -= sharesToSell

        if holdings[index].shares < 0.000_000_01 {
            holdings[index].costBasis = 0
            holdings[index].shares = 0
        }
    }

    mutating func deleteFund(code rawCode: String) throws {
        let code = try Self.validatedCode(rawCode)
        guard let index = holdings.firstIndex(where: { $0.code == code }) else {
            throw FundOperationError.holdingNotFound
        }
        holdings.remove(at: index)
    }

    private static func validatedCode(_ rawCode: String) throws -> String {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.utf8.count == 6,
              code.utf8.allSatisfy({ (48...57).contains($0) })
        else {
            throw FundOperationError.invalidCode
        }
        return code
    }

    private static func validateAmount(_ amount: Double) throws {
        guard amount.isFinite, amount > 0 else {
            throw FundOperationError.invalidAmount
        }
    }
}
