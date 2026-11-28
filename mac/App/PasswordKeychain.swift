// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Security

/// Where the app keeps the passwords it made for guest accounts: the Mac's Keychain, one entry for
/// each machine (by its folder name). They are never in the machine's files, in logs or in what
/// `--print-states` prints; the agent is given one for the answer files and holds it in memory.
enum PasswordKeychain {
    /// A run with its own support folder (a test run) keeps its passwords apart, so it never
    /// touches those of the real machines.
    private static let service = "com.ruxn.guesthouse.guest-account"
        + (ProcessInfo.processInfo.environment["GUESTHOUSE_SUPPORT_DIR"] == nil ? "" : ".test")

    private static func query(_ machine: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: machine]
    }

    /// Keeps `password` for `machine`, in place of one kept before.
    @discardableResult
    static func save(_ password: String, for machine: String, label: String) -> Bool {
        SecItemDelete(query(machine) as CFDictionary)
        var item = query(machine)
        item[kSecValueData as String] = Data(password.utf8)
        item[kSecAttrLabel as String] = "Guesthouse: \(label)"
        // Only this Mac, and only once it is unlocked.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func read(for machine: String) -> String? {
        var item = query(machine)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(item as CFDictionary, &found) == errSecSuccess, let data = found as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(for machine: String) {
        SecItemDelete(query(machine) as CFDictionary)
    }
}
