import Foundation

enum ImportQueueItemStatus: String, Codable, Equatable, Sendable {
    case queued
    case downloading
    case verifying
    case cached
    case assembling
    case authorizing
    case importing
    case imported
    case needsConfirmation
    case failed
    case paused
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .imported, .needsConfirmation, .failed, .cancelled:
            true
        default:
            false
        }
    }

    var isSafelyRestartable: Bool {
        switch self {
        case .queued, .downloading, .verifying, .cached, .assembling, .authorizing, .paused:
            true
        default:
            false
        }
    }
}

struct ImportQueueItem: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let deviceId: String
    let summary: CameraAssetSummary
    var status: ImportQueueItemStatus
    var progress: Double
    var errorMessage: String?
    let enqueuedAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        deviceId: String,
        summary: CameraAssetSummary,
        status: ImportQueueItemStatus = .queued,
        progress: Double = 0,
        errorMessage: String? = nil,
        enqueuedAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.deviceId = deviceId
        self.summary = summary
        self.status = status
        self.progress = progress
        self.errorMessage = errorMessage
        self.enqueuedAt = enqueuedAt
        self.updatedAt = updatedAt
    }
}

actor ImportQueueStore {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.fileURL = fileURL ?? applicationSupport
            .appendingPathComponent("RetroLive/import-queue.json")
        self.fileManager = fileManager
    }

    func loadRecoveringInterruptedItems() throws -> [ImportQueueItem] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        var items = try JSONDecoder().decode([ImportQueueItem].self, from: data)
        let now = Date()
        for index in items.indices {
            if items[index].status == .importing {
                items[index].status = .needsConfirmation
                items[index].errorMessage = nil
                items[index].updatedAt = now
            } else if items[index].status.isSafelyRestartable {
                items[index].status = .queued
                items[index].progress = 0
                items[index].errorMessage = nil
                items[index].updatedAt = now
            }
        }
        try persist(items)
        return items
    }

    func save(_ items: [ImportQueueItem]) throws {
        try persist(items)
    }

    private func persist(_ items: [ImportQueueItem]) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(items).write(to: fileURL, options: .atomic)
    }
}

struct ImportStorageOverview: Equatable, Sendable {
    let managedBytes: Int64
}

struct ImportStoragePreflight: Equatable, Sendable {
    static let safetyMarginBytes: Int64 = 256 * 1_024 * 1_024

    let requiredAdditionalBytes: Int64
    let availableBytes: Int64

    var isSufficient: Bool {
        requiredAdditionalBytes <= max(0, availableBytes - Self.safetyMarginBytes)
    }

    static func clampedAdd(_ values: Int64...) -> Int64 {
        values.reduce(0) { partial, value in
            guard value > 0 else { return partial }
            let (result, overflow) = partial.addingReportingOverflow(value)
            return overflow ? Int64.max : result
        }
    }

    static func clampedMultiply(_ value: Int64, by multiplier: Int64) -> Int64 {
        guard value > 0, multiplier > 0 else { return 0 }
        let (result, overflow) = value.multipliedReportingOverflow(by: multiplier)
        return overflow ? Int64.max : result
    }
}
