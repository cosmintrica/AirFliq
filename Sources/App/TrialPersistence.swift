import Foundation
import Security

/// Persists the full-access trial outside ordinary preferences so reinstalling
/// the app does not silently create a new trial. A last-seen timestamp also
/// prevents moving the system clock backwards from extending access.
enum TrialPersistence {
    struct State {
        let startedAt: Date
        let referenceDate: Date
    }

    private static let service = "com.cosmintrica.airfliq.trial.v1"
    private static let startedAccount = "started-at"
    private static let lastSeenAccount = "last-seen-at"
    private static let startedFallbackKey = "airfliq.trial.startedAt.v1"
    private static let lastSeenFallbackKey = "airfliq.trial.lastSeenAt.v1"

    static func currentState() -> State {
        let wallClock = Date()
        let startedAt = readDate(account: startedAccount,
                                 fallbackKey: startedFallbackKey) ?? wallClock
        let lastSeen = readDate(account: lastSeenAccount,
                                fallbackKey: lastSeenFallbackKey) ?? wallClock
        let referenceDate = max(max(wallClock, lastSeen), startedAt)

        writeDate(startedAt, account: startedAccount,
                  fallbackKey: startedFallbackKey)
        writeDate(referenceDate, account: lastSeenAccount,
                  fallbackKey: lastSeenFallbackKey)
        return State(startedAt: startedAt, referenceDate: referenceDate)
    }

    private static func readDate(account: String, fallbackKey: String) -> Date? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let raw = String(data: data, encoding: .utf8),
           let timestamp = TimeInterval(raw) {
            return Date(timeIntervalSince1970: timestamp)
        }

        let fallback = UserDefaults.standard.double(forKey: fallbackKey)
        return fallback > 0 ? Date(timeIntervalSince1970: fallback) : nil
    }

    private static func writeDate(_ date: Date,
                                  account: String,
                                  fallbackKey: String) {
        let data = Data(String(date.timeIntervalSince1970).utf8)
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(identity as CFDictionary,
                                   attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = identity
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            _ = SecItemAdd(item as CFDictionary, nil)
        }

        // UserDefaults is only a compatibility fallback for local builds whose
        // ad-hoc signature cannot access the production keychain item.
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: fallbackKey)
    }
}
