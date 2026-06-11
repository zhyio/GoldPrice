import Foundation

/// Pure-Swift Supabase REST client for syncing portfolio data.
/// Zero third-party dependencies — uses only URLSession.
///
/// Dedicated table for GoldPrice:
///   Table: `goldprice_data`, user_id: `goldprice_web`
///   Field: `holdings` — JSON-encoded `[FundHolding]`
actor SupabaseSync {
    private let baseURL = "https://owqhouyafggdzgcqwlji.supabase.co/rest/v1"
    private let apiKey = "sb_publishable_QgsSE7ZoIfcaPsJLlkfS5w_tGvRz_I6"
    private let userID = "goldprice_web"

    private let session: URLSession

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

    /// Fetches holdings from Supabase `goldprice_data.holdings`. Returns nil on any failure.
    func fetchHoldings() async -> [FundHolding]? {
        guard let url = URL(
            string: "\(baseURL)/goldprice_data?user_id=eq.\(userID)&select=holdings&limit=1"
        ) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { return nil }

            let rows = try JSONDecoder().decode([HoldingsRow].self, from: data)
            guard let row = rows.first, let holdings = row.holdings else { return nil }

            // holdings might be a string (if sent as serialized json) or array
            let holdingsString: String
            switch holdings {
            case .string(let s):
                holdingsString = s
            case .unknown(let raw):
                holdingsString = raw
            }

            guard let holdingsData = holdingsString.data(using: .utf8) else { return nil }
            return try JSONDecoder().decode([FundHolding].self, from: holdingsData)
        } catch {
            return nil
        }
    }

    // MARK: - Upload

    /// Uploads holdings to Supabase using upsert.
    func uploadHoldings(_ holdings: [FundHolding]) async {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let holdingsData = try? encoder.encode(holdings),
              let holdingsString = String(data: holdingsData, encoding: .utf8)
        else { return }

        // We can just pass the string to jsonb since Supabase expects json/jsonb,
        // but to ensure it's not double-stringified, we decode it back to a struct or dictionary.
        // Actually, upserting a JSON payload: {"user_id": "...", "holdings": <parsed json array>}
        guard let parsedHoldings = try? JSONSerialization.jsonObject(with: holdingsData) else { return }

        let payload: [String: Any] = [
            "user_id": userID,
            "holdings": parsedHoldings,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        guard let upsertURL = URL(
            string: "\(baseURL)/goldprice_data?on_conflict=user_id"
        ) else { return }

        var upsertRequest = URLRequest(url: upsertURL)
        upsertRequest.httpMethod = "POST"
        upsertRequest.httpBody = body
        applyHeaders(to: &upsertRequest)
        upsertRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        upsertRequest.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        upsertRequest.setValue("merge-duplicates", forHTTPHeaderField: "Resolution") // For on_conflict

        _ = try? await session.data(for: upsertRequest)
    }

    // MARK: - Helpers

    private func applyHeaders(to request: inout URLRequest) {
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }
}

// MARK: - Codable models for parsing

private enum FlexibleValue: Decodable {
    case string(String)
    case unknown(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .string(s)
        } else {
            // Fallback: re-encode whatever is there
            let raw = try container.decode(AnyCodable.self)
            if let data = try? JSONEncoder().encode(raw),
               let str = String(data: data, encoding: .utf8) {
                self = .unknown(str)
            } else {
                self = .string("[]")
            }
        }
    }
}

private struct AnyCodable: Codable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let arr = try? container.decode([AnyCodable].self) {
            value = arr.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else if let s = try? container.decode(String.self) {
            value = s
        } else if let d = try? container.decode(Double.self) {
            value = d
        } else if let b = try? container.decode(Bool.self) {
            value = b
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let s as String: try container.encode(s)
        case let d as Double: try container.encode(d)
        case let b as Bool: try container.encode(b)
        case let arr as [Any]:
            try container.encode(arr.map { AnyCodable(value: $0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable(value: $0) })
        default: try container.encodeNil()
        }
    }

    init(value: Any) { self.value = value }
}

private struct HoldingsRow: Decodable {
    let holdings: FlexibleValue?
}
