import Foundation

actor MarketService {
    private let goldURL = URL(string: "https://push2delay.eastmoney.com/api/qt/stock/get?secid=118.AU9999&fields=f43,f59,f60,f169,f170")!
    private let indexURL = URL(string: "https://push2delay.eastmoney.com/api/qt/stock/get?secid=1.000001&fields=f43,f59,f60,f169,f170")!
    private let loadData: @Sendable (URLRequest) async -> Data?

    init(session: URLSession? = nil) {
        let resolvedSession: URLSession
        if let session {
            resolvedSession = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 12
            resolvedSession = URLSession(configuration: configuration)
        }

        loadData = { request in
            do {
                let (data, response) = try await resolvedSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode)
                else {
                    return nil
                }
                return data
            } catch {
                return nil
            }
        }
    }

    init(loadData: @escaping @Sendable (URLRequest) async -> Data?) {
        self.loadData = loadData
    }

    func fetch(current: MarketSnapshot) async -> MarketSnapshot {
        async let goldData = fetchData(from: goldURL, referer: "https://quote.eastmoney.com/")
        async let indexData = fetchData(from: indexURL, referer: "https://quote.eastmoney.com/")

        let (goldResult, indexResult) = await (goldData, indexData)
        var snapshot = current
        var receivedUpdate = false

        if let goldResult,
           let gold = QuoteParser.parseEastMoney(goldResult) {
            snapshot.gold = gold
            receivedUpdate = true
        }

        if let indexResult,
           let index = QuoteParser.parseEastMoney(indexResult) {
            snapshot.shanghaiIndex = index
            receivedUpdate = true
        }

        snapshot.isLoading = false
        if receivedUpdate {
            snapshot.updatedAt = Date()
        }
        return snapshot
    }

    private func fetchData(from url: URL, referer: String? = nil) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        if let referer {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }

        return await loadData(request)
    }
}
