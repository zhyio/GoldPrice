import SwiftUI

struct MarketView: View {
    private static let goldDetailsURL = URL(string: "https://quote.eastmoney.com/globalfuture/AU9999.html")!
    private static let indexDetailsURL = URL(string: "https://quote.eastmoney.com/unify/r/1.000001")!

    let market: MarketSnapshot
    let funds: FundPortfolio
    let areFundsExpanded: Bool
    let onToggleFunds: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            marketHeader

            if areFundsExpanded {
                Divider()
                    .overlay(.white.opacity(0.08))
                fundTable
            }
        }
        .frame(
            width: areFundsExpanded ? 530 : 232,
            height: areFundsExpanded ? 254 : 52
        )
        .background(glassBackground)
    }

    private var marketHeader: some View {
        HStack(spacing: 8) {
            Button(action: onToggleFunds) {
                Image(systemName: areFundsExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 18, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(areFundsExpanded ? "收起基金列表" : "展开基金列表")

            VStack(spacing: 6) {
                row(
                    label: "金价",
                    labelColor: Color(hex: "FFD700"),
                    price: formattedPrice(market.gold, prefix: "¥"),
                    quote: market.gold,
                    destination: Self.goldDetailsURL
                )

                row(
                    label: "上证",
                    labelColor: Color(hex: "60A5FA"),
                    price: formattedPrice(market.shanghaiIndex),
                    quote: market.shanghaiIndex,
                    destination: Self.indexDetailsURL
                )
            }
            .frame(width: 190)

            if areFundsExpanded {
                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("基金持仓")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("每小时更新今日涨跌")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.42))
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 52)
    }

    private var fundTable: some View {
        VStack(spacing: 0) {
            fundTableHeader

            ForEach(funds.holdings, id: \.code) { holding in
                fundRow(holding)
            }

            Spacer(minLength: 0)

            HStack {
                Text("金额和收益来自持仓截图；今日涨跌为东方财富盘中估值")
                Spacer()
                Text(fundUpdateText)
            }
            .font(.system(size: 8))
            .foregroundStyle(.white.opacity(0.35))
            .padding(.horizontal, 12)
            .frame(height: 22)
        }
        .padding(.top, 4)
    }

    private var fundTableHeader: some View {
        HStack(spacing: 0) {
            Text("名称").frame(width: 250, alignment: .leading)
            Text("金额").frame(width: 92, alignment: .trailing)
            Text("收益").frame(width: 82, alignment: .trailing)
            Text("今日涨跌").frame(width: 82, alignment: .trailing)
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.white.opacity(0.4))
        .padding(.horizontal, 12)
        .frame(height: 22)
    }

    private func fundRow(_ holding: FundHolding) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(holding.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                Text(holding.code)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .frame(width: 250, alignment: .leading)
            .help("\(holding.name)（\(holding.code)）")

            Text(formattedAmount(holding.amount))
                .frame(width: 92, alignment: .trailing)

            Text(holding.formattedProfit)
                .foregroundStyle(trendColor(holding.profitTrend))
                .frame(width: 82, alignment: .trailing)

            Text(holding.formattedTodayChange)
                .foregroundStyle(holding.todayTrend.map(trendColor) ?? Color.white.opacity(0.35))
                .frame(width: 82, alignment: .trailing)
                .help(holding.estimateTime.map { "估值时间：\($0)" } ?? "暂无盘中估值")
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .padding(.horizontal, 12)
        .frame(height: 30)
    }

    @ViewBuilder
    private func row(
        label: String,
        labelColor: Color,
        price: String,
        quote: MarketQuote?,
        destination: URL
    ) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(labelColor)
                .frame(width: 5, height: 5)

            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))

            if quote != nil {
                PriceLink(
                    price: price,
                    label: label,
                    destination: destination
                )
            } else {
                priceText(price)
            }

            Spacer(minLength: 0)

            if let quote {
                HStack(spacing: 2) {
                    Text(trendSymbol(quote.trend))
                        .font(.system(size: quote.trend == .flat ? 9 : 7, weight: .bold))
                    Text(quote.formattedChangePercent)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(trendColor(quote.trend))
            }
        }
    }

    private func priceText(_ price: String) -> some View {
        Text(price)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.92))
    }

    @ViewBuilder
    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(.black.opacity(0.45))
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
    }

    private func formattedPrice(_ quote: MarketQuote?, prefix: String = "") -> String {
        guard let quote, quote.price > 0 else { return "--" }
        return prefix + formattedAmount(quote.price)
    }

    private func formattedAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "--"
    }

    private var fundUpdateText: String {
        if funds.isLoading {
            return "正在更新"
        }
        guard let updatedAt = funds.updatedAt else {
            return "暂无估值"
        }
        return "更新 " + updatedAt.formatted(
            .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        )
    }

    private func trendSymbol(_ trend: Trend) -> String {
        switch trend {
        case .up: return "▲"
        case .down: return "▼"
        case .flat: return "—"
        }
    }

    private func trendColor(_ trend: Trend) -> Color {
        switch trend {
        case .up: return Color(hex: "FF4D4F")
        case .down: return Color(hex: "00A870")
        case .flat: return Color(hex: "9CA3AF")
        }
    }
}

private struct PriceLink: View {
    private static let longPressDuration = 0.45

    @Environment(\.openURL) private var openURL

    let price: String
    let label: String
    let destination: URL

    var body: some View {
        Text(price)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.92))
            .contentShape(Rectangle())
            .gesture(clickGesture)
            .help("单击在东方财富查看\(label)行情")
    }

    private var clickGesture: some Gesture {
        LongPressGesture(minimumDuration: Self.longPressDuration)
            .exclusively(before: TapGesture())
            .onEnded { result in
                guard case .second = result else { return }
                openURL(destination)
            }
    }
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
