import Foundation

enum FundStorageError: Error, LocalizedError {
    case createDirectory(Error)
    case read(Error)
    case backup(Error)
    case write(Error)

    var errorDescription: String? {
        switch self {
        case .createDirectory:
            return "无法创建持仓数据目录"
        case .read:
            return "无法读取持仓数据"
        case .backup:
            return "无法备份损坏的持仓数据"
        case .write:
            return "无法保存持仓数据"
        }
    }
}

enum FundStorageLoadResult: Equatable {
    case missing
    case loaded([FundHolding])
    case recovered([FundHolding], backupURL: URL)
}

struct FundStorage {
    let directoryURL: URL

    var fileURL: URL {
        directoryURL.appendingPathComponent("portfolio.json")
    }

    static func live(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> FundStorage {
        if let override = environment["GOLDPRICE_DATA_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return FundStorage(directoryURL: URL(fileURLWithPath: override, isDirectory: true))
        }

        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return FundStorage(directoryURL: applicationSupport.appendingPathComponent("GoldPrice"))
    }

    func loadRecovering(defaults: [FundHolding]) throws -> FundStorageLoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .missing
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw FundStorageError.read(error)
        }

        do {
            return .loaded(try JSONDecoder().decode([FundHolding].self, from: data))
        } catch {
            let backupURL = try backupCorruptFile()
            try save(defaults)
            return .recovered(defaults, backupURL: backupURL)
        }
    }

    func save(_ holdings: [FundHolding]) throws {
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw FundStorageError.createDirectory(error)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(holdings)
        } catch {
            throw FundStorageError.write(error)
        }

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw FundStorageError.write(error)
        }
    }

    private func backupCorruptFile() throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backupURL = directoryURL.appendingPathComponent(
            "portfolio.corrupt-\(formatter.string(from: Date())).json"
        )

        do {
            try FileManager.default.moveItem(at: fileURL, to: backupURL)
            return backupURL
        } catch {
            throw FundStorageError.backup(error)
        }
    }
}
