import SwiftUI

struct MarketView: View {
    private static let goldDetailsURL = URL(string: "https://quote.eastmoney.com/globalfuture/AU9999.html")!
    private static let indexDetailsURL = URL(string: "https://quote.eastmoney.com/unify/r/1.000001")!

    let market: MarketSnapshot

    var body: some View {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 212)
        .background(glassBackground)
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
                Link(destination: destination) {
                    priceText(price)
                }
                .buttonStyle(.plain)
                .help("在东方财富查看\(label)行情")
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

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return prefix + (formatter.string(from: NSNumber(value: quote.price)) ?? "--")
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
