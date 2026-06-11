import AppKit
import SwiftUI

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum Layout {
        static let collapsedSize = NSSize(width: 320, height: 56)
        static let expandedWidth: CGFloat = 485
        static let screenMargin: CGFloat = 16
    }


    private var window: NSWindow!
    private var hostingView: NSHostingView<MarketView>!
    private var statusItem: NSStatusItem!
    private var market = MarketSnapshot()
    private var funds = FundPortfolio.empty
    private let marketService = MarketService()
    private let fundService = FundService()
    private let fundStorage = FundStorage.live()
    private var marketTimer: Timer?
    private var fundTimer: Timer?
    private var isRefreshingMarket = false
    private var isRefreshingFunds = false
    private var areFundsExpanded = false
    private var storageNotice: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadPortfolio()
        setupWindow()
        setupStatusBar()
        startFetching()
    }

    func applicationWillTerminate(_ notification: Notification) {
        marketTimer?.invalidate()
        fundTimer?.invalidate()
    }

    // MARK: - Portfolio Persistence

    private func loadPortfolio() {
        let defaults = FundPortfolio.migrateDefaults().holdings
        do {
            switch try fundStorage.loadRecovering(defaults: defaults) {
            case .missing:
                funds = FundPortfolio(holdings: defaults, updatedAt: nil, isLoading: true)
                try fundStorage.save(defaults)
            case let .loaded(holdings):
                funds = FundPortfolio(holdings: holdings, updatedAt: nil, isLoading: true)
            case let .recovered(holdings, backupURL):
                funds = FundPortfolio(holdings: holdings, updatedAt: nil, isLoading: true)
                storageNotice = "持仓文件损坏，已备份为 \(backupURL.lastPathComponent)"
            }
        } catch {
            funds = FundPortfolio(holdings: defaults, updatedAt: nil, isLoading: true)
            storageNotice = error.localizedDescription
        }
    }

    private func savePortfolio() throws {
        try fundStorage.save(funds.holdings)
    }

    // MARK: - Fund Management

    private func addFund(code: String, costBasis: Double) -> String? {
        var updated = funds
        do {
            try updated.addFund(code: code, costBasis: costBasis)
            try fundStorage.save(updated.holdings)
        } catch {
            return error.localizedDescription
        }

        funds = updated
        updateWindowFrame(animate: true)
        Task { await refreshFunds() }
        return nil
    }

    private func adjustFund(code: String, amount: Double, isIncrease: Bool) -> String? {
        var updated = funds
        do {
            try updated.adjustFund(code: code, amount: amount, isIncrease: isIncrease)
            try fundStorage.save(updated.holdings)
        } catch {
            return error.localizedDescription
        }

        funds = updated
        render()
        return nil
    }

    private func deleteFund(code: String) -> String? {
        var updated = funds
        do {
            try updated.deleteFund(code: code)
            try fundStorage.save(updated.holdings)
        } catch {
            return error.localizedDescription
        }

        funds = updated
        updateWindowFrame(animate: true)
        return nil
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

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "chart.xyaxis.line", accessibilityDescription: "GoldPrice")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示/隐藏", action: #selector(toggleVisibility), keyEquivalent: "h"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出应用", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    @objc private func toggleVisibility() {
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
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
        do {
            try savePortfolio()
        } catch {
            storageNotice = error.localizedDescription
        }
        render()
    }

    private var currentSize: NSSize {
        if !areFundsExpanded {
            return Layout.collapsedSize
        }
        let height = 56 + 1 + 4 + 20 + CGFloat(funds.holdings.count) * 30 + 28 + 20
        return NSSize(width: Layout.expandedWidth, height: min(height, NSScreen.main?.visibleFrame.height ?? 800 - 32))
    }

    private func toggleFunds() {
        areFundsExpanded.toggle()
        updateWindowFrame(animate: true)
    }

    private func updateWindowFrame(animate: Bool) {
        let newSize = currentSize
        let currentFrame = window.frame
        let newFrame = NSRect(
            x: currentFrame.maxX - newSize.width,
            y: currentFrame.maxY - newSize.height,
            width: newSize.width,
            height: newSize.height
        )

        render()
        hostingView.frame = NSRect(origin: .zero, size: newSize)
        window.setFrame(newFrame, display: true, animate: animate)
    }



    private func render() {
        hostingView.rootView = makeRootView()
    }

    private func makeRootView() -> MarketView {
        MarketView(
            market: market,
            funds: funds,
            areFundsExpanded: areFundsExpanded,
            portfolioStatusMessage: storageNotice,
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
