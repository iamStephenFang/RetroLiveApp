import Foundation

enum ImportedAssetKind: String, Codable, Sendable {
    case photo
    case livePhoto
}

struct ImportRecord: Codable, Equatable, Sendable {
    let assetId: String
    let localIdentifier: String
    let kind: ImportedAssetKind
    let importedAt: Date
}

actor ImportHistoryStore {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.fileURL = fileURL ?? applicationSupport
            .appendingPathComponent("RetroLive/import-history.json")
        self.fileManager = fileManager
    }

    func record(for assetId: String) throws -> ImportRecord? {
        try recordsByAssetId()[assetId]
    }

    func allRecords() throws -> [ImportRecord] {
        try recordsByAssetId().values.sorted { $0.importedAt > $1.importedAt }
    }

    func save(_ record: ImportRecord) throws {
        var records = try recordsByAssetId()
        records[record.assetId] = record
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(
            records.values.sorted { $0.importedAt < $1.importedAt }
        )
        try data.write(to: fileURL, options: .atomic)
    }

    private func recordsByAssetId() throws -> [String: ImportRecord] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [:] }
        let records = try JSONDecoder().decode(
            [ImportRecord].self,
            from: Data(contentsOf: fileURL)
        )
        return Dictionary(records.map { ($0.assetId, $0) }, uniquingKeysWith: { _, latest in latest })
    }
}
