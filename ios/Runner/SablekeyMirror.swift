import CryptoKit
import Foundation
import Security

/// The login mirror shared between the app and the AutoFill extension.
///
/// # Why this exists, and what it costs
///
/// On Android, Sablekey's autofill provider never reads a credential: it hands
/// the system an authentication intent, the app opens, the user unlocks, and
/// the vault is decrypted only inside the app process.
///
/// iOS does not allow that shape. An `ASCredentialProviderViewController` must
/// produce credentials from inside the extension's own process, and an
/// extension cannot reach into the host app for a key. Opening the real vault
/// there would mean running Argon2id and XChaCha20-Poly1305 in Swift — Argon2
/// is not in CryptoKit, and XChaCha20 (24-byte nonce) is not either.
///
/// So iOS gets a *mirror*: logins only — domain, username, password, TOTP
/// secret — encrypted with AES-256-GCM under a key that lives in the Keychain
/// behind `.biometryCurrentSet`. Reading it requires Face ID or Touch ID at the
/// hardware level, and re-enrolling a face or finger invalidates the key and
/// the mirror with it.
///
/// The honest accounting:
///
///   - It is a second copy of the login subset of the vault, protected by the
///     Secure Enclave rather than by the master password.
///   - Anyone who can defeat the device biometric can read those logins without
///     ever knowing the master password.
///   - Notes, cards, documents, attachments and everything else are never
///     mirrored.
///
/// Because of that it is **off by default**, it is described in these terms in
/// the app's own settings screen rather than as "enable autofill", and turning
/// it off deletes both the key and the file.
enum SablekeyMirror {

    /// Must match the App Group configured on both targets.
    static let appGroup = "group.com.sablekey.app"

    private static let keychainTag = "com.sablekey.app.mirrorkey"
    private static let fileName = "autofill-mirror.bin"

    struct Entry: Codable {
        let id: String
        let name: String
        let uris: [String]
        let username: String
        let password: String
        let totpSecret: String?
    }

    enum MirrorError: Error {
        case noAppGroup
        case noKey
        case biometricsUnavailable
        case keychainFailure(OSStatus)
    }

    // MARK: - Location

    private static func mirrorURL() throws -> URL {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            throw MirrorError.noAppGroup
        }
        return container.appendingPathComponent(fileName)
    }

    // MARK: - Key management

    /// Creates the mirror key, replacing any existing one.
    ///
    /// `.biometryCurrentSet` rather than `.biometryAny` is deliberate: if
    /// someone adds their own fingerprint to a device they have taken, the key
    /// is destroyed rather than becoming usable by the new enrolment.
    private static func createKey() throws -> SymmetricKey {
        deleteKey()

        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &error
        ) else {
            throw MirrorError.biometricsUnavailable
        }

        let key = SymmetricKey(size: .bits256)
        let bytes = key.withUnsafeBytes { Data($0) }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainTag,
            kSecAttrAccessControl as String: access,
            kSecValueData as String: bytes,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw MirrorError.keychainFailure(status)
        }
        return key
    }

    /// Reads the mirror key. Triggers the system biometric prompt.
    static func loadKey(reason: String) throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainTag,
            kSecReturnData as String: true,
            kSecUseOperationPrompt as String: reason,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw status == errSecItemNotFound
                ? MirrorError.noKey
                : MirrorError.keychainFailure(status)
        }
        return SymmetricKey(data: data)
    }

    static func deleteKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainTag,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Writing (host app only)

    /// Replaces the mirror with [entries].
    ///
    /// Called by the app whenever the vault changes while autofill is enabled.
    /// Writing does not need the biometric prompt — a fresh key is generated
    /// each time, so the app never reads back what it wrote.
    static func write(entries: [Entry]) throws {
        let key = try createKey()
        let plaintext = try JSONEncoder().encode(entries)
        let sealed = try AES.GCM.seal(plaintext, using: key)

        guard let combined = sealed.combined else {
            throw MirrorError.noKey
        }

        let url = try mirrorURL()
        try combined.write(to: url, options: [.atomic, .completeFileProtection])
    }

    /// Removes the mirror and its key. Called when autofill is switched off,
    /// when the vault is erased, and on master password change.
    static func clear() {
        deleteKey()
        if let url = try? mirrorURL() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static var exists: Bool {
        guard let url = try? mirrorURL() else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Reading (extension only)

    /// Decrypts the mirror after a successful biometric check.
    static func read(reason: String) throws -> [Entry] {
        let key = try loadKey(reason: reason)
        let url = try mirrorURL()
        let combined = try Data(contentsOf: url)
        let box = try AES.GCM.SealedBox(combined: combined)
        let plaintext = try AES.GCM.open(box, using: key)
        return try JSONDecoder().decode([Entry].self, from: plaintext)
    }

    // MARK: - Matching

    /// Whether a stored URI should be offered for [target].
    ///
    /// Mirrors the Dart `UriMatcher`: exact host, or the same registrable
    /// domain. Anything looser would offer a credential across unrelated sites.
    static func matches(uri: String, target: String) -> Bool {
        let storedHost = host(of: uri)
        let targetHost = host(of: target)
        if storedHost.isEmpty || targetHost.isEmpty { return false }
        if storedHost == targetHost { return true }
        return registrableDomain(storedHost) == registrableDomain(targetHost)
    }

    static func host(of raw: String) -> String {
        var value = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if let range = value.range(of: "://") {
            value = String(value[range.upperBound...])
        }
        if let slash = value.firstIndex(of: "/") {
            value = String(value[..<slash])
        }
        if let at = value.lastIndex(of: "@") {
            value = String(value[value.index(after: at)...])
        }
        if let colon = value.firstIndex(of: ":") {
            value = String(value[..<colon])
        }
        return value.hasPrefix("www.") ? String(value.dropFirst(4)) : value
    }

    private static let multiPartSuffixes: Set<String> = [
        "co.uk", "org.uk", "ac.uk", "gov.uk", "me.uk",
        "com.au", "net.au", "org.au", "co.nz", "co.za",
        "com.br", "com.mx", "com.tr", "com.cn", "co.jp",
        "co.kr", "co.in", "com.sg", "com.hk", "com.pk",
    ]

    static func registrableDomain(_ host: String) -> String {
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count > 2 else { return host }
        let lastTwo = labels.suffix(2).joined(separator: ".")
        if multiPartSuffixes.contains(lastTwo) && labels.count >= 3 {
            return labels.suffix(3).joined(separator: ".")
        }
        return lastTwo
    }
}
