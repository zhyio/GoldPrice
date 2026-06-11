import Foundation

/// Pure-Swift Supabase REST client for syncing portfolio data.
/// Zero third-party dependencies — uses only URLSession.
///
/// Shares the same database row as the GoldPriceWeb frontend:
///   Table: `fitness_data`, user_id: `goldprice_web`
///   Field: `exercises.holdings` — JSON-encoded `[FundHolding]`
actor SupabaseSync {
    private let baseURL = "https://owqhouyafggdzgcqwlji.supabase.co/rest/v1"
    private let apiKey = "sb_publishable_QgsSE7ZoIfcaPsJLlkfS5w_tGvRz_I6"
    private let userID = "goldprice_web"

    private let session: URLSession
    private var remoteID: Int?

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 15
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - Fetch

    /// Fetches holdings from Supabase. Returns nil on any failure (offline, etc.)
    func fetchHoldings() async -> [FundHolding]? {
        guard let url = URL(
            string: "\(baseURL)/fitness_data?user_id=eq.\(userID)&select=id,exercises,updated_at&limit=1"
        ) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { return nil }

            let rows = try JSONDecoder().decode([SupabaseRow].self, from: data)
            guard let row = rows.first else { return nil }

            remoteID = row.id

            // exercises.holdings is a JSON *string* of [FundHolding]
            guard let holdingsString = row.exercises?["holdings"] else { return nil }
            guard let holdingsData = holdingsString.data(using: .utf8) else { return nil }

            return try JSONDecoder().decode([FundHolding].self, from: holdingsData)
        } catch {
            return nil
        }
    }

    // MARK: - Upload

    /// Uploads holdings to Supabase. Fire-and-forget; errors are silently logged.
    func uploadHoldings(_ holdings: [FundHolding]) async {
        // Encode holdings to JSON string (same format as web app's portfolio.serialize())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let holdingsData = try? encoder.encode(holdings),
              let holdingsString = String(data: holdingsData, encoding: .utf8)
        else { return }

        let payload = SupabasePayload(
            user_id: userID,
            exercises: ["holdings": holdingsString],
            updated_at: ISO8601DateFormatter().string(from: Date())
        )

        guard let body = try? JSONEncoder().encode(payload) else { return }

        if let id = remoteID {
            // UPDATE existing row
            await performRequest(
                method: "PATCH",
                path: "/fitness_data?id=eq.\(id)",
                body: body
            )
        } else {
            // INSERT new row (first time)
            if let data = await performRequest(
                method: "POST",
                path: "/fitness_data",
                body: body,
                returnData: true
            ) {
                if let rows = try? JSONDecoder().decode([SupabaseRow].self, from: data),
                   let row = rows.first {
                    remoteID = row.id
                }
            }
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func performRequest(
        method: String,
        path: String,
        body: Data,
        returnData: Bool = false
    ) async -> Data? {
        guard let url = URL(string: "\(baseURL)\(path)") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        applyHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if returnData {
            request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private func applyHeaders(to request: inout URLRequest) {
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }
}

// MARK: - Codable Models (private, for REST serialization only)

private struct SupabaseRow: Decodable {
    let id: Int
    let exercises: [String: String]?
    let updated_at: String?
}

private struct SupabasePayload: Encodable {
    let user_id: String
    let exercises: [String: String]
    let updated_at: String
}
