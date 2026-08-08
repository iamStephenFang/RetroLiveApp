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

private enum ImportJournalState: String, Codable {
    case submitting
    case imported
}

private struct ImportJournalEntry: Codable {
    let assetId: String
    var state: ImportJournalState
    var localIdentifier: String?
    let kind: ImportedAssetKind
    let startedAt: Date
    var importedAt: Date?
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
        guard let entry = try entriesByAssetId()[assetId],
              entry.state == .imported,
              let localIdentifier = entry.localIdentifier,
              let importedAt = entry.importedAt else {
            return nil
        }
        return ImportRecord(
            assetId: entry.assetId,
            localIdentifier: localIdentifier,
            kind: entry.kind,
            importedAt: importedAt
        )
    }

    func allRecords() throws -> [ImportRecord] {
        try entriesByAssetId().values.compactMap { entry in
            guard entry.state == .imported,
                  let localIdentifier = entry.localIdentifier,
                  let importedAt = entry.importedAt else {
                return nil
            }
            return ImportRecord(
                assetId: entry.assetId,
                localIdentifier: localIdentifier,
                kind: entry.kind,
                importedAt: importedAt
            )
        }.sorted { $0.importedAt > $1.importedAt }
    }

    func save(_ record: ImportRecord) throws {
        var entries = try entriesByAssetId()
        entries[record.assetId] = ImportJournalEntry(
            assetId: record.assetId,
            state: .imported,
            localIdentifier: record.localIdentifier,
            kind: record.kind,
            startedAt: record.importedAt,
            importedAt: record.importedAt
        )
        try persist(entries)
    }

    func beginSubmission(assetId: String, kind: ImportedAssetKind, at date: Date = Date()) throws -> Bool {
        var entries = try entriesByAssetId()
        guard entries[assetId] == nil else { return false }
        entries[assetId] = ImportJournalEntry(
            assetId: assetId,
            state: .submitting,
            localIdentifier: nil,
            kind: kind,
            startedAt: date,
            importedAt: nil
        )
        try persist(entries)
        return true
    }

    func hasUnconfirmedSubmission(for assetId: String) throws -> Bool {
        try entriesByAssetId()[assetId]?.state == .submitting
    }

    func cancelSubmission(for assetId: String) throws {
        var entries = try entriesByAssetId()
        guard entries[assetId]?.state == .submitting else { return }
        entries.removeValue(forKey: assetId)
        try persist(entries)
    }

    private func persist(_ entries: [String: ImportJournalEntry]) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(
            entries.values.sorted { $0.startedAt < $1.startedAt }
        )
        try data.write(to: fileURL, options: .atomic)
    }

    private func entriesByAssetId() throws -> [String: ImportJournalEntry] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [:] }
        let data = try Data(contentsOf: fileURL)
        if let entries = try? JSONDecoder().decode([ImportJournalEntry].self, from: data) {
            return Dictionary(
                entries.map { ($0.assetId, $0) },
                uniquingKeysWith: { _, latest in latest }
            )
        }
        let legacyRecords = try JSONDecoder().decode([ImportRecord].self, from: data)
        return Dictionary(
            legacyRecords.map { record in
                (
                    record.assetId,
                    ImportJournalEntry(
                        assetId: record.assetId,
                        state: .imported,
                        localIdentifier: record.localIdentifier,
                        kind: record.kind,
                        startedAt: record.importedAt,
                        importedAt: record.importedAt
                    )
                )
            },
            uniquingKeysWith: { _, latest in latest }
        )
    }
}
