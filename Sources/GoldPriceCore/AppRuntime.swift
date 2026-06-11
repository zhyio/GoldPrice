import AppKit
import SwiftUI

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum Layout {
        static let collapsedSize = NSSize(width: 380, height: 62)
        static let expandedSize = NSSize(width: 530, height: 264)
        static let screenMargin: CGFloat = 16
    }

    private var window: NSWindow!
    private var hostingView: NSHostingView<MarketView>!
    private var market = MarketSnapshot()
    private var funds = FundPortfolio.initial
    private let marketService = MarketService()
    private let fundService = FundService()
    private var marketTimer: Timer?
    private var fundTimer: Timer?
    private var isRefreshingMarket = false
    private var isRefreshingFunds = false
    private var areFundsExpanded = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupWindow()
        startFetching()
    }

    func applicationWillTerminate(_ notification: Notification) {
        marketTimer?.invalidate()
        fundTimer?.invalidate()
    }

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
            onToggleFunds: { [weak self] in
                self?.toggleFunds()
            }
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
