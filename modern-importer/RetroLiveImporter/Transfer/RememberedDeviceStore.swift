import Foundation
import Security

struct RememberedDeviceRecord: Codable, Equatable, Sendable {
    let serviceName: String
    let deviceId: String
    let deviceName: String
    let session: PairingSession
    let lastConnectedAt: Date
}

protocol RememberedDeviceStoring: AnyObject {
    func record(for serviceName: String) -> RememberedDeviceRecord?
    func save(_ record: RememberedDeviceRecord) throws
    func remove(serviceName: String) throws
}

enum RememberedDeviceStoreError: Error, LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return L10n.format("device.remember_failed", Int(status))
        }
    }
}

final class KeychainRememberedDeviceStore: RememberedDeviceStoring {
    private let service = "com.retrolive.importer.remembered-device"

    func record(for serviceName: String) -> RememberedDeviceRecord? {
        var query = baseQuery(serviceName: serviceName)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let record = try? JSONDecoder().decode(RememberedDeviceRecord.self, from: data) else {
            return nil
        }
        guard record.session.isValid else {
            try? remove(serviceName: serviceName)
            return nil
        }
        return record
    }

    func save(_ record: RememberedDeviceRecord) throws {
        let data = try JSONEncoder().encode(record)
        let query = baseQuery(serviceName: record.serviceName)
        let updates = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw RememberedDeviceStoreError.keychain(addStatus)
            }
        } else if status != errSecSuccess {
            throw RememberedDeviceStoreError.keychain(status)
        }
    }

    func remove(serviceName: String) throws {
        let status = SecItemDelete(baseQuery(serviceName: serviceName) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw RememberedDeviceStoreError.keychain(status)
        }
    }

    private func baseQuery(serviceName: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serviceName
        ]
    }
}
