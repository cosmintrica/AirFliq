import Foundation
import Security

/// Keeps the trusted App Store trial clock separate from the local development
/// fallback. The App Store path never creates a start date. Its start date must
/// always be supplied by a verified RevenueCat non-subscription transaction.
enum TrialPersistence {
    struct State {
        let startedAt: Date?
        let referenceDate: Date
    }

    private static let verifiedService = "com.cosmintrica.airfliq.trial.verified.v2"
    private static let lastSeenAccount = "last-seen-at"

#if !MAC_APP_STORE
    private static let developmentService = "com.cosmintrica.airfliq.trial.development.v2"
    private static let startedAccount = "started-at"
    private static let startedFallbackKey = "airfliq.trial.development.startedAt.v2"
    private static let lastSeenFallbackKey = "airfliq.trial.development.lastSeenAt.v2"

    /// Local, testable fallback for development builds. This preserves the
    /// existing developer experience by starting a local trial on first use.
    /// It is never called by a `MAC_APP_STORE` build.
    static func currentDevelopmentState() -> State {
        let wallClock = Date()
        let startedAt = readDate(service: developmentService,
                                 account: startedAccount,
                                 fallbackKey: startedFallbackKey) ?? wallClock
        let lastSeen = readDate(service: developmentService,
                                account: lastSeenAccount,
                                fallbackKey: lastSeenFallbackKey) ?? wallClock
        let referenceDate = max(max(wallClock, lastSeen), startedAt)

        writeDate(startedAt,
                  service: developmentService,
                  account: startedAccount,
                  fallbackKey: startedFallbackKey)
        writeDate(referenceDate,
                  service: developmentService,
                  account: lastSeenAccount,
                  fallbackKey: lastSeenFallbackKey)
        return State(startedAt: startedAt, referenceDate: referenceDate)
    }
#endif

    /// Advances the anti-clock-rollback reference for a trial whose start date
    /// came from RevenueCat. The verified start date is deliberately not saved
    /// locally, so preferences or Keychain data can never manufacture access.
    static func verifiedState(startedAt: Date?,
                              trustedReferenceDate: Date? = nil) -> State {
        let wallClock = Date()
        guard let startedAt else {
            return State(startedAt: nil, referenceDate: wallClock)
        }

        let lastSeen = readKeychainDate(service: verifiedService,
                                        account: lastSeenAccount) ?? wallClock
        let serverReference = trustedReferenceDate ?? startedAt
        let referenceDate = max(max(max(wallClock, lastSeen), startedAt),
                                serverReference)
        writeKeychainDate(referenceDate,
                          service: verifiedService,
                          account: lastSeenAccount)
        return State(startedAt: startedAt, referenceDate: referenceDate)
    }

#if !MAC_APP_STORE
    private static func readDate(service: String,
                                 account: String,
                                 fallbackKey: String) -> Date? {
        if let value = readKeychainDate(service: service, account: account) {
            return value
        }

        let fallback = UserDefaults.standard.double(forKey: fallbackKey)
        return fallback > 0 ? Date(timeIntervalSince1970: fallback) : nil
    }

    private static func writeDate(_ date: Date,
                                  service: String,
                                  account: String,
                                  fallbackKey: String) {
        writeKeychainDate(date, service: service, account: account)

        // UserDefaults is only a compatibility fallback for ad-hoc local
        // development builds. The App Store path does not call this method.
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: fallbackKey)
    }
#endif

    private static func readKeychainDate(service: String,
                                         account: String) -> Date? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let raw = String(data: data, encoding: .utf8),
              let timestamp = TimeInterval(raw) else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    private static func writeKeychainDate(_ date: Date,
                                          service: String,
                                          account: String) {
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
    }
}
