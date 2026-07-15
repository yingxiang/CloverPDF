import Foundation
import Security

final class KeychainTrialQuotaStore: TrialQuotaStoring, @unchecked Sendable {
    private let service = "com.lingchen.cloverpdf.trial"
    private let account = "successful-conversions"
    private let trialLimit = 3
    private let lock = NSLock()

    func remainingConversions() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return max(0, trialLimit - readCount())
    }

    func consumeSuccessfulConversion() throws {
        lock.lock()
        defer { lock.unlock() }
        let count = min(trialLimit, readCount() + 1)
        let data = Data(String(count).utf8)
        let query = baseQuery()
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData] = data
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus)) }
        } else if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func readCount() -> Int {
        var query = baseQuery()
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8),
              let value = Int(string) else {
            return 0
        }
        return value
    }

    private func baseQuery() -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }
}
