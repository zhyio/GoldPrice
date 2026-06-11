import Foundation

actor FundService {
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

    func fetch(current: FundPortfolio) async -> FundPortfolio {
        let loader = loadData
        let codes = current.holdings.map(\.code)
        var estimates: [String: FundEstimateResponse] = [:]

        await withTaskGroup(of: FundEstimateResponse?.self) { group in
            for code in codes {
                group.addTask {
                    guard let request = Self.makeRequest(code: code),
                          let data = await loader(request),
                          let estimate = FundEstimateParser.parse(data),
                          estimate.fundCode == code,
                          estimate.changePercent != nil
                    else {
                        return nil
                    }
                    return estimate
                }
            }

            for await estimate in group {
                if let estimate {
                    estimates[estimate.fundCode] = estimate
                }
            }
        }

        var portfolio = current
        for index in portfolio.holdings.indices {
            let code = portfolio.holdings[index].code
            guard let estimate = estimates[code],
                  let changePercent = estimate.changePercent
            else {
                continue
            }
            portfolio.holdings[index].todayChangePercent = changePercent
            portfolio.holdings[index].estimateTime = estimate.estimateTime
        }

        portfolio.isLoading = false
        if !estimates.isEmpty {
            portfolio.updatedAt = Date()
        }
        return portfolio
    }

    private static func makeRequest(code: String) -> URLRequest? {
        guard var components = URLComponents(
            string: "https://fundgz.1234567.com.cn/js/\(code).js"
        ) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "rt", value: String(Int(Date().timeIntervalSince1970)))
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://fund.eastmoney.com/", forHTTPHeaderField: "Referer")
        return request
    }
}
