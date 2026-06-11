import Foundation
import Testing
@testable import GoldPriceCore

@Suite("Fund storage", .serialized)
struct FundStorageTests {
    @Test("Uses GOLDPRICE_DATA_DIR when provided")
    func environmentOverride() {
        let storage = FundStorage.live(environment: [
            "GOLDPRICE_DATA_DIR": "/tmp/goldprice-qa"
        ])

        #expect(storage.directoryURL.path == "/tmp/goldprice-qa")
    }

    @Test("Falls back to the GoldPrice application support directory")
    func liveDefaultDirectory() {
        let storage = FundStorage.live(environment: [:])

        #expect(storage.directoryURL.lastPathComponent == "GoldPrice")
        #expect(storage.directoryURL.path.contains("Application Support"))
    }

    @Test("Reports a missing portfolio")
    func missingPortfolio() throws {
        try withTemporaryStorage { storage in
            let result = try storage.loadRecovering(defaults: [])
            #expect(result == .missing)
        }
    }

    @Test("Saves and loads persistent holding fields")
    func roundTrip() throws {
        try withTemporaryStorage { storage in
            var holding = sampleHolding()
            holding.estimatedNAV = 2.1
            holding.previousNAV = 2
            holding.todayChangePercent = 5
            holding.estimateTime = "2026-06-11 15:00"

            try storage.save([holding])
            let result = try storage.loadRecovering(defaults: [])

            guard case let .loaded(loaded) = result else {
                Issue.record("Expected a loaded portfolio")
                return
            }
            #expect(loaded.count == 1)
            #expect(loaded[0].code == "008702")
            #expect(loaded[0].costBasis == 1_000)
            #expect(loaded[0].shares == 500)
            #expect(loaded[0].estimatedNAV == nil)
            #expect(loaded[0].estimateTime == nil)
        }
    }

    @Test("Corrupt data is backed up before defaults are restored")
    func recoversCorruptData() throws {
        try withTemporaryStorage { storage in
            try FileManager.default.createDirectory(
                at: storage.directoryURL,
                withIntermediateDirectories: true
            )
            let corruptData = Data("{not-json".utf8)
            try corruptData.write(to: storage.fileURL)
            let defaults = [sampleHolding()]

            let result = try storage.loadRecovering(defaults: defaults)

            guard case let .recovered(holdings, backupURL) = result else {
                Issue.record("Expected recovery from corrupt data")
                return
            }
            #expect(holdings == defaults)
            #expect(FileManager.default.fileExists(atPath: backupURL.path))
            #expect(try Data(contentsOf: backupURL) == corruptData)

            let reloaded = try storage.loadRecovering(defaults: [])
            #expect(reloaded == .loaded(defaults))
        }
    }

    @Test("Atomic save leaves only the portfolio file")
    func atomicSave() throws {
        try withTemporaryStorage { storage in
            try storage.save([sampleHolding()])

            let contents = try FileManager.default.contentsOfDirectory(
                at: storage.directoryURL,
                includingPropertiesForKeys: nil
            )
            #expect(contents.map(\.lastPathComponent) == ["portfolio.json"])
        }
    }

    @Test("Read errors are reported")
    func reportsReadError() throws {
        try withTemporaryStorage { storage in
            try FileManager.default.createDirectory(
                at: storage.fileURL,
                withIntermediateDirectories: true
            )

            #expect(throws: FundStorageError.self) {
                try storage.loadRecovering(defaults: [])
            }
        }
    }

    @Test("Directory creation errors are reported")
    func reportsDirectoryError() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GoldPriceStorageTests-\(UUID().uuidString)")
        try Data("blocking-file".utf8).write(to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = FundStorage(directoryURL: root)

        #expect(throws: FundStorageError.self) {
            try storage.save([sampleHolding()])
        }
    }

    @Test("Write errors are reported")
    func reportsWriteError() throws {
        try withTemporaryStorage { storage in
            try FileManager.default.createDirectory(
                at: storage.fileURL,
                withIntermediateDirectories: true
            )

            #expect(throws: FundStorageError.self) {
                try storage.save([sampleHolding()])
            }
        }
    }

    @Test("Backup errors are reported without replacing corrupt data")
    func reportsBackupError() throws {
        try withTemporaryStorage { storage in
            try FileManager.default.createDirectory(
                at: storage.directoryURL,
                withIntermediateDirectories: true
            )
            let corruptData = Data("{not-json".utf8)
            try corruptData.write(to: storage.fileURL)

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let blockingBackup = storage.directoryURL.appendingPathComponent(
                "portfolio.corrupt-\(formatter.string(from: Date())).json"
            )
            try FileManager.default.createDirectory(
                at: blockingBackup,
                withIntermediateDirectories: true
            )

            #expect(throws: FundStorageError.self) {
                try storage.loadRecovering(defaults: [sampleHolding()])
            }
            #expect(try Data(contentsOf: storage.fileURL) == corruptData)
        }
    }

    @Test("Every storage error has a user-facing message")
    func errorDescriptions() {
        let underlying = CocoaError(.fileReadUnknown)
        let errors: [FundStorageError] = [
            .createDirectory(underlying),
            .read(underlying),
            .backup(underlying),
            .write(underlying)
        ]

        #expect(errors.allSatisfy { !($0.errorDescription ?? "").isEmpty })
    }

    private func withTemporaryStorage(
        _ body: (FundStorage) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GoldPriceStorageTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(FundStorage(directoryURL: directory))
    }

    private func sampleHolding() -> FundHolding {
        FundHolding(
            code: "008702",
            name: "华夏黄金ETF联接C",
            costBasis: 1_000,
            shares: 500
        )
    }
}
