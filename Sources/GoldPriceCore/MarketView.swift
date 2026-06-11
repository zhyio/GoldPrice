import SwiftUI

struct MarketView: View {
    private static let goldDetailsURL = URL(string: "https://quote.eastmoney.com/globalfuture/AU9999.html")!
    private static let indexDetailsURL = URL(string: "https://quote.eastmoney.com/unify/r/1.000001")!

    @Environment(\.openURL) private var openURL

    let market: MarketSnapshot
    let funds: FundPortfolio
    let areFundsExpanded: Bool
    let onToggleFunds: () -> Void
    let onAddFund: (String, Double) -> Void
    let onAdjustFund: (String, Double, Bool) -> Void
    let onDeleteFund: (String) -> Void

    @State private var showAddSheet = false
    @State private var addCode = ""
    @State private var addAmount = ""
    @State private var adjustingFundCode: String? = nil
    @State private var adjustAmount = ""

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
            width: areFundsExpanded ? 530 : 320,
            height: areFundsExpanded ? 350 : 56
        )
        .background(glassBackground)
    }

    // MARK: - Header

    private var marketHeader: some View {
        HStack(spacing: 0) {
            goldColumn
            columnDivider
            indexColumn
            columnDivider
            earningsColumn

            Spacer(minLength: 0)

            Button(action: onToggleFunds) {
                Image(systemName: areFundsExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 22, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(areFundsExpanded ? "收起基金列表" : "展开基金列表")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: 56)
    }

    // MARK: - Metric Columns

    private var goldColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            metricLabel("金价", color: Color(hex: "FFD700"))
            if market.gold != nil {
                PriceLink(
                    price: formattedPrice(market.gold, prefix: "¥"),
                    label: "金价",
                    destination: Self.goldDetailsURL
                )
            } else {
                metricPlaceholder
            }
            if let gold = market.gold {
                metricChange(trend: gold.trend, text: gold.formattedChangePercent)
            } else {
                metricSubtitle("--")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var indexColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            metricLabel("上证", color: Color(hex: "60A5FA"))
            if market.shanghaiIndex != nil {
                PriceLink(
                    price: formattedPrice(market.shanghaiIndex),
                    label: "上证",
                    destination: Self.indexDetailsURL
                )
            } else {
                metricPlaceholder
            }
            if let index = market.shanghaiIndex {
                metricChange(trend: index.trend, text: index.formattedChangePercent)
            } else {
                metricSubtitle("--")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var earningsColumn: some View {
        let earnings = todayEstimatedEarnings
        let trend = earnings.map(Trend.init(value:)) ?? .flat
        let dotColor = earnings.map { trendColor(Trend(value: $0)) } ?? Color(hex: "9CA3AF")
        let valueColor: Color = earnings == nil ? .white.opacity(0.35) : trendColor(trend)
        return VStack(alignment: .leading, spacing: 2) {
            metricLabel("今日", color: dotColor)
            Text(formattedEarnings(earnings))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(valueColor)
            metricSubtitle("基金估算")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Metric Helpers

    private func metricLabel(_ text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func metricChange(trend: Trend, text: String) -> some View {
        HStack(spacing: 2) {
            Text(trendSymbol(trend))
                .font(.system(size: trend == .flat ? 8 : 6, weight: .bold))
            Text(text)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(trendColor(trend))
    }

    private func metricSubtitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.3))
    }

    private var metricPlaceholder: some View {
        Text("--")
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.35))
    }

    private var columnDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(width: 1, height: 28)
            .padding(.horizontal, 8)
    }

    // MARK: - Fund Table

    private var fundTable: some View {
        VStack(spacing: 0) {
            fundTableHeader

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(funds.holdings, id: \.code) { holding in
                        fundRow(holding)
                    }
                    addFundButton
                }
            }

            fundTableFooter
        }
        .padding(.top, 4)
    }

    private var fundTableHeader: some View {
        HStack(spacing: 0) {
            Text("名称").frame(width: 190, alignment: .leading)
            Text("本金").frame(width: 85, alignment: .trailing)
            Text("收益").frame(width: 85, alignment: .trailing)
            Text("今日").frame(width: 75, alignment: .trailing)
            Spacer().frame(width: 24)
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.white.opacity(0.4))
        .padding(.horizontal, 12)
        .frame(height: 20)
    }

    private func fundRow(_ holding: FundHolding) -> some View {
        HStack(spacing: 0) {
            Button(action: {
                if let url = URL(string: "https://fund.eastmoney.com/\(holding.code).html") {
                    openURL(url)
                }
            }) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(holding.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                    Text(holding.code)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .buttonStyle(.plain)
            .frame(width: 190, alignment: .leading)
            .help("点击查看 \(holding.name) 详情")

            Text(holding.formattedCostBasis)
                .frame(width: 85, alignment: .trailing)

            Text(holding.formattedProfit)
                .foregroundStyle(trendColor(holding.profitTrend))
                .frame(width: 85, alignment: .trailing)

            Text(holding.formattedTodayChange)
                .foregroundStyle(holding.todayTrend.map(trendColor) ?? Color.white.opacity(0.35))
                .frame(width: 75, alignment: .trailing)
                .help(holding.estimateTime.map { "估值时间：\($0)" } ?? "暂无盘中估值")

            Button(action: { adjustingFundCode = holding.code }) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(width: 24, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(
                isPresented: Binding(
                    get: { adjustingFundCode == holding.code },
                    set: { if !$0 { adjustingFundCode = nil; adjustAmount = "" } }
                ),
                arrowEdge: .trailing
            ) {
                adjustFundPopover(holding)
            }
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .padding(.horizontal, 12)
        .frame(height: 30)
    }

    private var addFundButton: some View {
        HStack {
            Button(action: { showAddSheet = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 10))
                    Text("添加基金")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 190, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showAddSheet, arrowEdge: .bottom) {
                addFundPopover
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
    }

    private var fundTableFooter: some View {
        HStack {
            Text("收益和今日盈亏基于盘中估算净值计算")
            Spacer()
            Text(fundUpdateText)
        }
        .font(.system(size: 8))
        .foregroundStyle(.white.opacity(0.35))
        .padding(.horizontal, 12)
        .frame(height: 20)
    }

    // MARK: - Popovers

    private var addFundPopover: some View {
        VStack(spacing: 10) {
            Text("添加基金")
                .font(.system(size: 13, weight: .semibold))

            TextField("基金代码（6位）", text: $addCode)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)

            TextField("本金金额", text: $addAmount)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)

            HStack(spacing: 12) {
                Button("取消") {
                    showAddSheet = false
                    addCode = ""
                    addAmount = ""
                }

                Button("添加") {
                    guard let amount = Double(addAmount), amount > 0,
                          !addCode.isEmpty else { return }
                    onAddFund(addCode.trimmingCharacters(in: .whitespaces), amount)
                    showAddSheet = false
                    addCode = ""
                    addAmount = ""
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "3B82F6"))
            }
        }
        .padding(14)
        .frame(width: 200)
    }

    private func adjustFundPopover(_ holding: FundHolding) -> some View {
        VStack(spacing: 10) {
            Text(holding.name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            HStack(spacing: 4) {
                Text("当前本金")
                    .foregroundStyle(.secondary)
                Text(holding.formattedCostBasis)
            }
            .font(.system(size: 10))

            TextField("调整金额", text: $adjustAmount)
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)

            HStack(spacing: 12) {
                Button("减仓") {
                    guard let amount = Double(adjustAmount), amount > 0 else { return }
                    onAdjustFund(holding.code, amount, false)
                    adjustingFundCode = nil
                    adjustAmount = ""
                }
                .foregroundStyle(Color(hex: "00A870"))

                Button("加仓") {
                    guard let amount = Double(adjustAmount), amount > 0 else { return }
                    onAdjustFund(holding.code, amount, true)
                    adjustingFundCode = nil
                    adjustAmount = ""
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "FF4D4F"))
            }

            Divider()

            Button(action: {
                onDeleteFund(holding.code)
                adjustingFundCode = nil
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 9))
                    Text("删除此基金")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 180)
    }

    // MARK: - Glass Background

    @ViewBuilder
    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(.black.opacity(0.75))
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
    }

    // MARK: - Formatting

    private func formattedPrice(_ quote: MarketQuote?, prefix: String = "") -> String {
        guard let quote, quote.price > 0 else { return "--" }
        return prefix + FundHolding.formatAmount(quote.price)
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

    private var todayEstimatedEarnings: Double? {
        guard !funds.isLoading else { return nil }
        let changes = funds.holdings.compactMap(\.todayChange)
        guard !changes.isEmpty else { return nil }
        return changes.reduce(0, +)
    }

    private func formattedEarnings(_ value: Double?) -> String {
        guard let value else { return "--" }
        return FundHolding.formatSigned(value)
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
