//
//  Keychain.swift
//  RollCall
//
//  Keeps the sign-in token in the iPhone's Keychain: the encrypted storage
//  iOS provides for passwords and keys. (UserDefaults would be readable by
//  anyone with a backup of the phone; the Keychain isn't.)
//

import Foundation
import Security

enum Keychain {
    private static let service = "com.sujansankar.RollCall"
    private static let account = "signInToken"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func loadToken() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func saveToken(_ token: String) {
        deleteToken()
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    static func deleteToken() {
        SecItemDelete(query as CFDictionary)
    }
}
