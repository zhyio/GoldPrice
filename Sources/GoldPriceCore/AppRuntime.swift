import AppKit
import SwiftUI

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var hostingView: NSHostingView<MarketView>!
    private var market = MarketSnapshot()
    private let service = MarketService()
    private var timer: Timer?
    private var isRefreshing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupWindow()
        startFetching()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    private func setupWindow() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let width: CGFloat = 212
        let height: CGFloat = 52
        let margin: CGFloat = 16

        window = NSWindow(
            contentRect: NSRect(
                x: screen.visibleFrame.maxX - width - margin,
                y: screen.visibleFrame.maxY - height - margin,
                width: width,
                height: height
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

        hostingView = NSHostingView(rootView: MarketView(market: market))
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        window.contentView = hostingView
        window.orderFrontRegardless()
    }

    private func startFetching() {
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        market = await service.fetch(current: market)
        hostingView.rootView = MarketView(market: market)
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
