import AppKit
import SwiftUI

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum Layout {
        static let collapsedSize = NSSize(width: 360, height: 56)
        static let expandedSize = NSSize(width: 530, height: 290)
        static let screenMargin: CGFloat = 16
    }

    private var window: NSWindow!
    private var hostingView: NSHostingView<MarketView>!
    private var market = MarketSnapshot()
    private var funds = FundPortfolio.empty
    private let marketService = MarketService()
    private let fundService = FundService()
    private var marketTimer: Timer?
    private var fundTimer: Timer?
    private var isRefreshingMarket = false
    private var isRefreshingFunds = false
    private var areFundsExpanded = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadPortfolio()
        setupWindow()
        startFetching()
    }

    func applicationWillTerminate(_ notification: Notification) {
        marketTimer?.invalidate()
        fundTimer?.invalidate()
    }

    // MARK: - Portfolio Persistence

    private func loadPortfolio() {
        if FundStorage.hasExistingData {
            let holdings = FundStorage.load()
            funds = FundPortfolio(holdings: holdings, updatedAt: nil, isLoading: true)
        } else {
            funds = FundPortfolio.migrateDefaults()
            FundStorage.save(funds.holdings)
        }
    }

    private func savePortfolio() {
        FundStorage.save(funds.holdings)
    }

    // MARK: - Fund Management

    private func addFund(code: String, costBasis: Double) {
        guard !funds.holdings.contains(where: { $0.code == code }) else { return }
        let holding = FundHolding(code: code, name: "加载中...", costBasis: costBasis, shares: 0)
        funds.holdings.append(holding)
        savePortfolio()
        render()
        Task { await refreshFunds() }
    }

    private func adjustFund(code: String, amount: Double, isIncrease: Bool) {
        guard let index = funds.holdings.firstIndex(where: { $0.code == code }) else { return }
        let holding = funds.holdings[index]
        let nav = holding.estimatedNAV ?? holding.previousNAV

        if isIncrease {
            funds.holdings[index].costBasis += amount
            if let nav, nav > 0 {
                funds.holdings[index].shares += amount / nav
            }
        } else {
            guard let nav, nav > 0, holding.shares > 0 else { return }
            let sharesToSell = amount / nav
            guard sharesToSell <= holding.shares else { return }
            let proportionalCost = (sharesToSell / holding.shares) * holding.costBasis
            funds.holdings[index].costBasis -= proportionalCost
            funds.holdings[index].shares -= sharesToSell
        }

        savePortfolio()
        render()
    }

    private func deleteFund(code: String) {
        funds.holdings.removeAll { $0.code == code }
        savePortfolio()
        render()
    }

    // MARK: - Window

    private func setupWindow() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let size = Layout.collapsedSize

        window = NSWindow(
            contentRect: NSRect(
                x: screen.visibleFrame.maxX - size.width - Layout.screenMargin,
                y: screen.visibleFrame.maxY - size.height - Layout.screenMargin,
                width: size.width,
                height: size.height
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isMovableByWindowBackground = true

        hostingView = NSHostingView(rootView: makeRootView())
        hostingView.frame = NSRect(origin: .zero, size: size)
        window.contentView = hostingView
        window.orderFrontRegardless()
    }

    // MARK: - Data Fetching

    private func startFetching() {
        Task {
            async let marketRefresh: Void = refreshMarket()
            async let fundRefresh: Void = refreshFunds()
            _ = await (marketRefresh, fundRefresh)
        }

        marketTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshMarket()
            }
        }

        fundTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshFunds()
            }
        }
    }

    private func refreshMarket() async {
        guard !isRefreshingMarket else { return }
        isRefreshingMarket = true
        defer { isRefreshingMarket = false }

        market = await marketService.fetch(current: market)
        render()
    }

    private func refreshFunds() async {
        guard !isRefreshingFunds else { return }
        isRefreshingFunds = true
        defer { isRefreshingFunds = false }

        funds = await fundService.fetch(current: funds)
        savePortfolio()
        render()
    }

    private func toggleFunds() {
        areFundsExpanded.toggle()
        let newSize = areFundsExpanded ? Layout.expandedSize : Layout.collapsedSize
        let currentFrame = window.frame
        let newFrame = NSRect(
            x: currentFrame.maxX - newSize.width,
            y: currentFrame.maxY - newSize.height,
            width: newSize.width,
            height: newSize.height
        )

        render()
        hostingView.frame = NSRect(origin: .zero, size: newSize)
        window.setFrame(newFrame, display: true, animate: true)
    }

    private func render() {
        hostingView.rootView = makeRootView()
    }

    private func makeRootView() -> MarketView {
        MarketView(
            market: market,
            funds: funds,
            areFundsExpanded: areFundsExpanded,
            onToggleFunds: { [weak self] in self?.toggleFunds() },
            onAddFund: { [weak self] code, amount in self?.addFund(code: code, costBasis: amount) },
            onAdjustFund: { [weak self] code, amount, isIncrease in self?.adjustFund(code: code, amount: amount, isIncrease: isIncrease) },
            onDeleteFund: { [weak self] code in self?.deleteFund(code: code) }
        )
    }
}

@MainActor
public func runGoldPriceApp() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) {
        app.run()
    }
}
