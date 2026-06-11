import Foundation

enum FundStorage {
    private static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GoldPrice")
    }

    private static var fileURL: URL {
        directoryURL.appendingPathComponent("portfolio.json")
    }

    static func load() -> [FundHolding] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([FundHolding].self, from: data)) ?? []
    }

    static func save(_ holdings: [FundHolding]) {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(holdings) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static var hasExistingData: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }
}
