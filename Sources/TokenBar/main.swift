import AppKit
import CommonCrypto
import Darwin
import Foundation
import QuartzCore
import Security

enum Provider: String, CaseIterable, Codable, Sendable {
    case codex = "Codex"
    case claude = "Claude"
    case gemini = "Gemini"
    case cursor = "Cursor"
    case antigravity = "Antigravity"
    case openrouter = "OpenRouter"
    case workbuddy = "WorkBuddy"

    var shortName: String {
        switch self {
        case .codex: "CX"
        case .claude: "CL"
        case .gemini: "GM"
        case .cursor: "CU"
        case .antigravity: "AG"
        case .openrouter: "OR"
        case .workbuddy: "WB"
        }
    }

    var accent: NSColor {
        switch self {
        case .codex: NSColor(calibratedRed: 0.06, green: 0.64, blue: 0.50, alpha: 1)
        case .claude: NSColor(calibratedRed: 0.85, green: 0.47, blue: 0.34, alpha: 1)
        case .gemini: NSColor(calibratedRed: 0.26, green: 0.52, blue: 0.96, alpha: 1)
        case .cursor: NSColor(calibratedWhite: 0.85, alpha: 1)
        case .antigravity: NSColor(calibratedRed: 0.72, green: 0.44, blue: 0.98, alpha: 1)
        case .openrouter: NSColor(calibratedRed: 0.96, green: 0.56, blue: 0.22, alpha: 1)
        case .workbuddy: NSColor(calibratedRed: 0.18, green: 0.67, blue: 0.95, alpha: 1)
        }
    }

    var appPath: String {
        switch self {
        case .codex: "/Applications/Codex.app"
        case .claude: "/Applications/Claude.app"
        case .gemini: "/Applications/Gemini.app"
        case .cursor: "/Applications/Cursor.app"
        case .antigravity: "/Applications/Antigravity.app"
        case .openrouter: "/Applications/OpenRouter.app"
        case .workbuddy: "/Applications/WorkBuddy.app"
        }
    }

    var primaryWindowLabel: String {
        switch self {
        case .codex, .claude: "5h"
        case .gemini: "5h"
        case .cursor: "All"
        case .antigravity: "5h"
        case .openrouter: "Spent"
        case .workbuddy: ""
        }
    }

    var secondaryWindowLabel: String? {
        switch self {
        case .codex, .claude: "Wk"
        case .gemini: "Wk"
        case .cursor: "API"
        case .antigravity: "Wk"
        case .openrouter, .workbuddy: nil
        }
    }

    var cardWidth: CGFloat {
        272
    }

    func cardWidth(compactLayout: Bool) -> CGFloat {
        if compactLayout { return 132 }
        return cardWidth
    }
}

struct ProviderDisplayConfig {
    private static let visibleKey = "VisibleProviders"
    private static let defaultProviders: [Provider] = [.codex, .claude]

    static var visibleProviders: [Provider] {
        get {
            guard let raw = UserDefaults.standard.array(forKey: visibleKey) as? [String] else {
                return defaultProviders
            }
            let providers = raw.compactMap(Provider.init(rawValue:))
            return providers.isEmpty ? defaultProviders : providers
        }
        set {
            let providers = newValue.isEmpty ? defaultProviders : newValue
            UserDefaults.standard.set(providers.map(\.rawValue), forKey: visibleKey)
        }
    }

    static func isVisible(_ provider: Provider) -> Bool {
        visibleProviders.contains(provider)
    }

    static func setVisible(_ provider: Provider, _ visible: Bool) {
        var providers = visibleProviders
        if visible {
            guard !providers.contains(provider) else { return }
            let order = Dictionary(uniqueKeysWithValues: Provider.allCases.enumerated().map { ($1, $0) })
            providers.append(provider)
            providers.sort { (order[$0] ?? 0) < (order[$1] ?? 0) }
        } else {
            guard providers.count > 1 else { return }
            providers.removeAll { $0 == provider }
        }
        visibleProviders = providers
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: visibleKey)
    }

    static func move(_ provider: Provider, by offset: Int) {
        var providers = visibleProviders
        guard let index = providers.firstIndex(of: provider) else { return }
        let nextIndex = max(0, min(providers.count - 1, index + offset))
        guard nextIndex != index else { return }
        providers.remove(at: index)
        providers.insert(provider, at: nextIndex)
        visibleProviders = providers
    }
}

@MainActor
enum ProviderIcon {
    private static var cache: [Provider: NSImage] = [:]

    static func image(for provider: Provider) -> NSImage {
        if let cached = cache[provider] {
            return cached
        }
        let icon: NSImage
        if let bundled = bundledIcon(for: provider) {
            icon = bundled
        } else if FileManager.default.fileExists(atPath: provider.appPath) {
            icon = NSWorkspace.shared.icon(forFile: provider.appPath)
        } else {
            icon = fallbackBadge(for: provider)
        }
        icon.size = NSSize(width: 26, height: 26)
        cache[provider] = icon
        return icon
    }

    private static func bundledIcon(for provider: Provider) -> NSImage? {
        switch provider {
        case .gemini:
            guard let url = Bundle.main.url(forResource: "GeminiIcon", withExtension: "svg"),
                  let image = NSImage(contentsOf: url) else { return nil }
            return image
        case .cursor:
            let path = "/Applications/Cursor.app/Contents/Resources/Cursor.icns"
            return NSImage(contentsOfFile: path)
        case .codex, .claude, .antigravity, .openrouter, .workbuddy:
            return nil
        }
    }

    private static func fallbackBadge(for provider: Provider) -> NSImage {
        let size = NSSize(width: 20, height: 20)
        let image = NSImage(size: size)
        image.lockFocus()
        provider.accent.setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 5, yRadius: 5).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let text = provider.shortName as NSString
        let textSize = text.size(withAttributes: attrs)
        text.draw(
            at: NSPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
            withAttributes: attrs
        )
        image.unlockFocus()
        return image
    }
}

struct LimitWindow: Codable, Sendable {
    let usedPercent: Double
    let resetAt: Date?
    let valueText: String?

    init(usedPercent: Double, resetAt: Date?, valueText: String? = nil) {
        self.usedPercent = usedPercent
        self.resetAt = resetAt
        self.valueText = valueText
    }

    var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }
}

struct UsageSnapshot: Codable, Sendable {
    let provider: Provider
    let primary: LimitWindow?
    let secondary: LimitWindow?
    /// Optional extra window only surfaced in the expanded card (e.g. Cursor's
    /// auto-model usage, shown when there is room to break down the combined
    /// headline). Smaller card states ignore it.
    let tertiary: LimitWindow?
    let plan: String?
    let updatedAt: Date
    let error: String?

    init(
        provider: Provider,
        primary: LimitWindow?,
        secondary: LimitWindow?,
        tertiary: LimitWindow? = nil,
        plan: String?,
        updatedAt: Date,
        error: String?
    ) {
        self.provider = provider
        self.primary = primary
        self.secondary = secondary
        self.tertiary = tertiary
        self.plan = plan
        self.updatedAt = updatedAt
        self.error = error
    }

    var isUsable: Bool { error == nil && (primary != nil || secondary != nil) }

    static func failure(_ provider: Provider, _ message: String) -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            primary: nil,
            secondary: nil,
            plan: nil,
            updatedAt: Date(),
            error: message
        )
    }
}

enum UsageFormat {
    static func percent(_ value: Double?) -> String {
        guard let value else { return "--%" }
        return "\(Int(value.rounded()))%"
    }

    static func windowValue(_ window: LimitWindow?) -> String {
        guard let window else { return "--%" }
        return window.valueText ?? percent(window.remainingPercent)
    }

    static func money(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    static func credits(_ value: Double) -> String {
        if value >= 10_000 {
            return String(format: "%.1fk", value / 1_000)
        }
        if value >= 1_000 {
            return String(format: value.truncatingRemainder(dividingBy: 1_000) == 0 ? "%.0fk" : "%.1fk", value / 1_000)
        }
        if value.rounded() == value {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }

    static func reset(_ date: Date?) -> String {
        guard let date else { return "--" }
        let seconds = max(0, Int(date.timeIntervalSinceNow))
        if seconds < 60 { return seconds == 0 ? "now" : "<1m" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h \(minutes % 60)m" }
        return "\(hours / 24)d \(hours % 24)h"
    }

    static func remainingColor(_ remaining: Double) -> NSColor {
        switch remaining {
        case 40...: NSColor.systemGreen
        case 15..<40: NSColor.systemOrange
        default: NSColor.systemRed
        }
    }

    static func parseDate(_ stamp: String?) -> Date? {
        guard let stamp else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: stamp) {
            return date
        }
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: stamp) {
            return date
        }
        // ISO8601DateFormatter rejects microsecond precision; strip the fraction.
        if let range = stamp.range(of: #"\.\d+"#, options: .regularExpression) {
            var trimmed = stamp
            trimmed.removeSubrange(range)
            return plain.date(from: trimmed)
        }
        return nil
    }

    static func parseLooseDate(_ stamp: String?) -> Date? {
        if let date = parseDate(stamp) {
            return date
        }
        guard let stamp else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: stamp) {
                return date
            }
        }
        return nil
    }
}

protocol UsageCollecting: Sendable {
    var provider: Provider { get }
    /// - Parameter force: when true, bypass any internal time-based cache and
    ///   fetch fresh data now. Used after the machine wakes from sleep and when
    ///   the user taps refresh, so a long idle period syncs immediately instead
    ///   of waiting out a throttle window.
    func collect(force: Bool) async -> UsageSnapshot
}

extension UsageCollecting {
    func collect() async -> UsageSnapshot { await collect(force: false) }
}

enum SecretStore {
    static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(service: String, account: String, value: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CollectorError.message("Keychain save failed: \(addStatus)")
        }
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum ChromeCookieStore {
    struct GoogleSession {
        let cookieHeader: String
        let authorization: String?
    }

    private struct Cookie {
        let host: String
        let name: String
        let value: String
    }

    private static let cookieNames = [
        "SID", "HSID", "SSID", "APISID", "SAPISID",
        "__Secure-1PSID", "__Secure-3PSID",
        "__Secure-1PAPISID", "__Secure-3PAPISID",
        "__Secure-1PSIDTS", "__Secure-3PSIDTS",
        "__Secure-1PSIDCC", "__Secure-3PSIDCC",
        "NID"
    ]

    static func googleCookieHeader() throws -> String {
        try googleSession().cookieHeader
    }

    static func googleSession() throws -> GoogleSession {
        guard let session = try googleSessions().first else {
            throw CollectorError.message("Gemini Google login not found in Chrome")
        }
        return session
    }

    static func googleSessions() throws -> [GoogleSession] {
        let key = try chromeSafeStorageKey()
        let sessions = try chromeProfiles().compactMap { profile -> GoogleSession? in
            var byName: [String: Cookie] = [:]
            for cookie in try readCookies(from: profile.appendingPathComponent("Cookies"), key: key) {
                byName[cookie.name] = cookie
            }
            guard byName["__Secure-1PSID"] != nil || byName["__Secure-3PSID"] != nil else {
                return nil
            }
            let cookieHeader = cookieNames.compactMap { name in
                byName[name].map { "\($0.name)=\($0.value)" }
            }.joined(separator: "; ")
            let sapisid = byName["SAPISID"]?.value
                ?? byName["__Secure-1PAPISID"]?.value
                ?? byName["__Secure-3PAPISID"]?.value
            return GoogleSession(
                cookieHeader: cookieHeader,
                authorization: sapisid.map { sapisidHash(cookie: $0, origin: "https://gemini.google.com") }
            )
        }
        guard !sessions.isEmpty else {
            throw CollectorError.message("Gemini Google login not found in Chrome")
        }
        return sessions
    }

    private static func chromeProfiles() -> [URL] {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return children
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("Cookies").path) }
            .sorted {
                if $0.lastPathComponent == "Default" { return true }
                if $1.lastPathComponent == "Default" { return false }
                return $0.lastPathComponent < $1.lastPathComponent
            }
    }

    private static func chromeSafeStorageKey() throws -> Data {
        let secret = try runProcess(
            "/usr/bin/security",
            ["find-generic-password", "-s", "Chrome Safe Storage", "-w"]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else {
            throw CollectorError.message("Chrome Safe Storage key not found")
        }

        let keyLength = kCCKeySizeAES128
        var key = Data(count: keyLength)
        let salt = Data("saltysalt".utf8)
        let status = key.withUnsafeMutableBytes { keyBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    secret,
                    secret.utf8.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                    1003,
                    keyBytes.bindMemory(to: UInt8.self).baseAddress,
                    keyLength
                )
            }
        }
        guard status == kCCSuccess else {
            throw CollectorError.message("Chrome cookie key derivation failed")
        }
        return key
    }

    private static func readCookies(from database: URL, key: Data) throws -> [Cookie] {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenbar-chrome-cookies-\(UUID().uuidString).sqlite")
        try FileManager.default.copyItem(at: database, to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }

        let quotedNames = cookieNames.map { "'\($0)'" }.joined(separator: ",")
        let sql = """
        SELECT host_key, name, value, hex(encrypted_value)
        FROM cookies
        WHERE host_key IN ('.google.com', 'gemini.google.com')
          AND name IN (\(quotedNames))
        ORDER BY host_key, name;
        """
        let output = try runProcess("/usr/bin/sqlite3", ["-separator", "\t", temp.path, sql])
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 4 else { return nil }
            let host = parts[0]
            let name = parts[1]
            let plain = parts[2]
            let encryptedHex = parts[3]
            let value = plain.isEmpty ? decryptCookie(hex: encryptedHex, host: host, key: key) : plain
            guard let value, !value.isEmpty else { return nil }
            return Cookie(host: host, name: name, value: value)
        }
    }

    private static func decryptCookie(hex: String, host: String, key: Data) -> String? {
        guard var encrypted = Data(hexString: hex), !encrypted.isEmpty else { return nil }
        if encrypted.starts(with: Data("v10".utf8)) || encrypted.starts(with: Data("v11".utf8)) {
            encrypted.removeFirst(3)
        }
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        let outputCapacity = encrypted.count + kCCBlockSizeAES128
        var output = Data(count: outputCapacity)
        var outputLength = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            encrypted.withUnsafeBytes { encryptedBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            encryptedBytes.baseAddress,
                            encrypted.count,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        output.removeSubrange(outputLength..<output.count)

        let hostDigest = sha256(Data(host.utf8))
        if output.count > hostDigest.count && output.prefix(hostDigest.count) == hostDigest {
            output.removeFirst(hostDigest.count)
        }
        return String(data: output, encoding: .utf8)
    }

    private static func sha256(_ data: Data) -> Data {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &digest)
        }
        return Data(digest)
    }

    private static func sapisidHash(cookie: String, origin: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let input = "\(timestamp) \(cookie) \(origin)"
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        Data(input.utf8).withUnsafeBytes { bytes in
            _ = CC_SHA1(bytes.baseAddress, CC_LONG(input.utf8.count), &digest)
        }
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "SAPISIDHASH \(timestamp)_\(hex)"
    }

    private static func runProcess(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CollectorError.message(
                "\(URL(fileURLWithPath: path).lastPathComponent) exited with \(process.terminationStatus)"
            )
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private extension Data {
    init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }
        var data = Data()
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}

final class UsageStore: @unchecked Sendable {
    private let collectors: [UsageCollecting]
    private let queue = DispatchQueue(label: "TokenBar.UsageStore")
    private var snapshots: [Provider: UsageSnapshot] = [:]

    init(collectors: [UsageCollecting]) {
        self.collectors = collectors
    }

    func current() -> [UsageSnapshot] {
        queue.sync {
            Provider.allCases.map { provider in
            snapshots[provider] ?? .failure(provider, "Loading")
            }
        }
    }

    func refresh(force: Bool = false) async -> [UsageSnapshot] {
        let results = await withTaskGroup(of: UsageSnapshot.self) { group in
            for collector in collectors {
                group.addTask { await collector.collect(force: force) }
            }
            var values: [UsageSnapshot] = []
            for await value in group {
                values.append(value)
            }
            return values
        }

        return queue.sync {
            for snapshot in results {
                if snapshot.isUsable {
                    snapshots[snapshot.provider] = snapshot
                } else if let existing = snapshots[snapshot.provider] {
                    // Keep last good data through transient failures, but surface the
                    // error once the data is too stale to trust.
                    if existing.isUsable && Date().timeIntervalSince(existing.updatedAt) > 600 {
                        snapshots[snapshot.provider] = snapshot
                    }
                } else {
                    snapshots[snapshot.provider] = snapshot
                }
            }
            return Provider.allCases.map { provider in
                snapshots[provider] ?? .failure(provider, "Loading")
            }
        }
    }
}

struct CodexAppServerCollector: UsageCollecting {
    let provider: Provider = .codex
    private let codexPath = "/Applications/Codex.app/Contents/Resources/codex"

    func collect(force _: Bool) async -> UsageSnapshot {
        await Task.detached(priority: .utility) {
            do {
                return try readRateLimits()
            } catch {
                return .failure(.codex, error.localizedDescription)
            }
        }.value
    }

    private func readRateLimits() throws -> UsageSnapshot {
        guard FileManager.default.isExecutableFile(atPath: codexPath) else {
            throw CollectorError.message("Codex CLI not found in /Applications/Codex.app")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server", "--listen", "stdio://"]

        let input = Pipe()
        let output = Pipe()
        let errorPipe = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errorPipe

        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
            }
        }

        // availableData blocks indefinitely; kill the helper at the deadline so a
        // hung app-server can't freeze the whole refresh pipeline.
        let killer = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 12, execute: killer)
        defer { killer.cancel() }

        let writer = input.fileHandleForWriting
        try writeJSON([
            "id": 1,
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "tokenbar",
                    "title": "TokenBar",
                    "version": "0.1.0"
                ],
                "capabilities": [
                    "experimentalApi": true,
                    "requestAttestation": false,
                    "optOutNotificationMethods": []
                ]
            ]
        ], to: writer)
        try writeJSON(["method": "initialized"], to: writer)
        try writeJSON(["id": 2, "method": "account/rateLimits/read"], to: writer)

        let deadline = Date().addingTimeInterval(12)
        var buffer = Data()
        let reader = output.fileHandleForReading

        while Date() < deadline {
            let data = reader.availableData
            if data.isEmpty { break }
            buffer.append(data)

            while let newline = buffer.firstIndex(of: 10) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                guard !line.isEmpty else { continue }
                guard
                    let object = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                    (object["id"] as? Int) == 2
                else { continue }

                if let error = object["error"] {
                    throw CollectorError.message("Codex app-server error: \(error)")
                }
                guard
                    let result = object["result"] as? [String: Any],
                    let snapshot = codexSnapshot(from: result)
                else {
                    throw CollectorError.message("Unexpected Codex rate limit response")
                }
                return snapshot
            }
        }

        let stderr = String(data: errorPipe.fileHandleForReading.availableData, encoding: .utf8) ?? ""
        if !stderr.isEmpty {
            throw CollectorError.message("Codex app-server timed out: \(stderr.prefix(180))")
        }
        throw CollectorError.message("Codex app-server timed out")
    }

    private func writeJSON(_ object: Any, to handle: FileHandle) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        handle.write(data)
        handle.write(Data([10]))
    }

    private func codexSnapshot(from result: [String: Any]) -> UsageSnapshot? {
        let byId = result["rateLimitsByLimitId"] as? [String: Any]
        let snapshot = byId?["codex"] as? [String: Any] ?? result["rateLimits"] as? [String: Any]
        guard let snapshot else { return nil }

        let plan = (snapshot["planType"] as? String)?.uppercased()
        return UsageSnapshot(
            provider: .codex,
            primary: parseWindow(snapshot["primary"]),
            secondary: parseWindow(snapshot["secondary"]),
            plan: plan,
            updatedAt: Date(),
            error: nil
        )
    }

    private func parseWindow(_ value: Any?) -> LimitWindow? {
        guard let dictionary = value as? [String: Any],
              let used = number(dictionary["usedPercent"]) else {
            return nil
        }
        let reset = number(dictionary["resetsAt"]).map { Date(timeIntervalSince1970: $0) }
        return LimitWindow(usedPercent: used, resetAt: reset)
    }

    private func number(_ value: Any?) -> Double? {
        switch value {
        case let value as Double: value
        case let value as Int: Double(value)
        case let value as NSNumber: value.doubleValue
        default: nil
        }
    }
}

/// Reads real Claude rate-limit usage through the same OAuth endpoint Claude Code uses.
/// Falls back to a local-log estimate when credentials or network are unavailable.
actor ClaudeUsageCollector: UsageCollecting {
    nonisolated let provider: Provider = .claude

    private static let keychainService = "Claude Code-credentials"
    /// Public OAuth client ID for Claude Code — the same value ships in every
    /// `claude` CLI binary, so it is an identifier, not a secret. An env var can
    /// override it, but we must have a working default: the app runs from a
    /// LaunchAgent with no custom environment, so requiring the env var meant
    /// token refresh always failed there and usage froze once the access token
    /// expired (~8h after login).
    private static let defaultOAuthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    private static func oauthClientID() throws -> String {
        if let id = ProcessInfo.processInfo.environment["CLAUDE_OAUTH_CLIENT_ID"],
           !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return id
        }
        return defaultOAuthClientID
    }
    private static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let userAgent = "claude-cli/2.1.119 (external, cli)"

    private var cached: UsageSnapshot?
    private var cachedAt = Date.distantPast
    private var nextFetchAt = Date.distantPast
    private var consecutiveFailures = 0
    private var restoredFromDisk = false

    private static let cacheDefaultsKey = "ClaudeUsageSnapshotCache"
    /// How long a cached/persisted reading is still treated as trustworthy. The
    /// 5h window moves slowly, so a couple of minutes of staleness is invisible,
    /// but beyond this we refuse to keep showing an old number as if it were live.
    private static let maxCacheAge: TimeInterval = 30 * 60
    /// Normal poll cadence. The endpoint tolerates a single user polling at this
    /// rate; the rate-limiting only triggers under rapid repeated calls.
    private static let pollInterval: TimeInterval = 120

    func collect(force: Bool) async -> UsageSnapshot {
        let now = Date()
        if !restoredFromDisk {
            restoredFromDisk = true
            if cached == nil,
               let data = UserDefaults.standard.data(forKey: Self.cacheDefaultsKey),
               let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data),
               now.timeIntervalSince(snapshot.updatedAt) < Self.maxCacheAge {
                cached = snapshot
                cachedAt = snapshot.updatedAt
            }
            // Drop the obsolete calibration key from the old interpolation scheme.
            UserDefaults.standard.removeObject(forKey: "ClaudeTokensPerPercent")
        }
        // Serve the last real reading until the next poll is due. We no longer
        // interpolate from local token logs: the server-side limit weights cache
        // reads (the bulk of logged tokens) very differently, so any local
        // token→percent estimate drifts away from the truth. Frequent polling of
        // the authoritative number is both simpler and accurate. nextFetchAt is
        // the single throttle, so failures back off instead of hammering. force
        // bypasses it (wake-from-sleep / manual refresh) for an immediate sync.
        if !force, now < nextFetchAt {
            if let cached { return cached }
            return .failure(.claude, "Loading")
        }
        do {
            let snapshot = try await readRealUsage()
            cached = snapshot
            cachedAt = now
            consecutiveFailures = 0
            nextFetchAt = now.addingTimeInterval(Self.pollInterval)
            if let data = try? JSONEncoder().encode(snapshot) {
                UserDefaults.standard.set(data, forKey: Self.cacheDefaultsKey)
            }
            return snapshot
        } catch {
            consecutiveFailures += 1
            let backoff = min(Self.pollInterval * pow(2, Double(consecutiveFailures - 1)), 1800)
            nextFetchAt = now.addingTimeInterval(backoff)
            // Recent real data beats a local guess; only estimate when the cached
            // number is too old to trust (or we never had one).
            if let cached, now.timeIntervalSince(cachedAt) < Self.maxCacheAge {
                return cached
            }
            let message = error.localizedDescription
            return await Task.detached(priority: .utility) {
                Self.estimatedSnapshot() ?? .failure(.claude, message)
            }.value
        }
    }

    // MARK: Real usage via OAuth

    private struct Credentials {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var subscriptionType: String?
    }

    private func readRealUsage() async throws -> UsageSnapshot {
        let stored = try loadKeychainObject()
        var credentials = try credentials(from: stored)
        if credentials.expiresAt.timeIntervalSinceNow < 120 {
            credentials = try await refreshTokens(credentials, mergingInto: stored)
        }
        do {
            return try await fetchUsage(credentials)
        } catch CollectorError.unauthorized {
            credentials = try await refreshTokens(credentials, mergingInto: stored)
            return try await fetchUsage(credentials)
        }
    }

    private func fetchUsage(_ credentials: Credentials) async throws -> UsageSnapshot {
        var request = URLRequest(url: Self.usageURL)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 {
            throw CollectorError.unauthorized
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CollectorError.message("Claude usage API: bad response (\(status))")
        }
        if let error = object["error"] as? [String: Any] {
            let message = error["message"] as? String ?? error["type"] as? String ?? "HTTP \(status)"
            throw CollectorError.message("Claude usage API: \(message)")
        }

        let primary = Self.usageWindow(object["five_hour"])
        let secondary = Self.usageWindow(object["seven_day"])
        guard primary != nil || secondary != nil else {
            throw CollectorError.message("Claude usage API: no rate limit data")
        }
        return UsageSnapshot(
            provider: .claude,
            primary: primary,
            secondary: secondary,
            plan: credentials.subscriptionType?.uppercased(),
            updatedAt: Date(),
            error: nil
        )
    }

    private static func usageWindow(_ value: Any?) -> LimitWindow? {
        guard let dictionary = value as? [String: Any],
              let used = (dictionary["utilization"] as? NSNumber)?.doubleValue else {
            return nil
        }
        return LimitWindow(usedPercent: used, resetAt: UsageFormat.parseDate(dictionary["resets_at"] as? String))
    }

    private func refreshTokens(
        _ credentials: Credentials,
        mergingInto stored: [String: Any]
    ) async throws -> Credentials {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": credentials.refreshToken,
            "client_id": try Self.oauthClientID()
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard
            (response as? HTTPURLResponse)?.statusCode == 200,
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let accessToken = object["access_token"] as? String
        else {
            throw CollectorError.message("Claude token refresh failed; run `claude` to re-login")
        }

        var updated = credentials
        updated.accessToken = accessToken
        if let refreshToken = object["refresh_token"] as? String {
            updated.refreshToken = refreshToken
        }
        let lifetime = (object["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        updated.expiresAt = Date().addingTimeInterval(lifetime)
        persist(updated, mergingInto: stored)
        return updated
    }

    // MARK: Keychain

    private func loadKeychainObject() throws -> [String: Any] {
        guard
            let output = try? Self.runProcess(
                "/usr/bin/security",
                ["find-generic-password", "-s", Self.keychainService, "-w"]
            ),
            let data = output.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw CollectorError.message("Claude credentials not found; run `claude` to login")
        }
        return object
    }

    private func credentials(from stored: [String: Any]) throws -> Credentials {
        let oauth = stored["claudeAiOauth"] as? [String: Any] ?? stored
        guard
            let accessToken = oauth["accessToken"] as? String,
            let refreshToken = oauth["refreshToken"] as? String
        else {
            throw CollectorError.message("Claude OAuth tokens missing; run `claude` to login")
        }
        let expiresMs = (oauth["expiresAt"] as? NSNumber)?.doubleValue ?? 0
        return Credentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date(timeIntervalSince1970: expiresMs / 1000),
            subscriptionType: oauth["subscriptionType"] as? String
        )
    }

    /// Writes rotated tokens back so the claude CLI keeps a valid refresh token.
    private func persist(_ credentials: Credentials, mergingInto stored: [String: Any]) {
        var root = stored
        var oauth = stored["claudeAiOauth"] as? [String: Any] ?? stored
        oauth["accessToken"] = credentials.accessToken
        oauth["refreshToken"] = credentials.refreshToken
        oauth["expiresAt"] = Int(credentials.expiresAt.timeIntervalSince1970 * 1000)
        if stored["claudeAiOauth"] != nil {
            root["claudeAiOauth"] = oauth
        } else {
            root = oauth
        }
        guard
            let data = try? JSONSerialization.data(withJSONObject: root),
            let json = String(data: data, encoding: .utf8)
        else { return }
        _ = try? Self.runProcess("/usr/bin/security", [
            "add-generic-password", "-U",
            "-s", Self.keychainService,
            "-a", NSUserName(),
            "-w", json
        ])
    }

    private static func runProcess(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CollectorError.message(
                "\(URL(fileURLWithPath: path).lastPathComponent) exited with \(process.terminationStatus)"
            )
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: Local-log fallback estimate

    private struct LocalUsage: Decodable {
        let input_tokens: Int?
        let output_tokens: Int?
        let cache_creation_input_tokens: Int?
        let cache_read_input_tokens: Int?
    }

    private struct LocalMessage: Decodable {
        let role: String?
        let usage: LocalUsage?
    }

    private struct LocalLine: Decodable {
        let type: String?
        let timestamp: String?
        let message: LocalMessage?
    }

    private static func estimatedSnapshot() -> UsageSnapshot? {
        let projects = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
        let now = Date()
        let fiveHoursAgo = now.addingTimeInterval(-5 * 3600)
        let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)
        let files = recentJSONLFiles(in: projects, modifiedAfter: weekAgo)
        guard !files.isEmpty else { return nil }

        let decoder = JSONDecoder()
        var fiveHourTokens = 0
        var weeklyTokens = 0
        var oldestFiveHour: Date?
        var oldestWeekly: Date?
        var latest = Date.distantPast

        for file in files {
            guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? handle.close() }
            var reader = LineReader(handle)
            while autoreleasepool(invoking: {
                guard let line = reader.next() else { return false }
                guard line.contains("\"usage\""),
                      let data = line.data(using: .utf8),
                      let parsed = try? decoder.decode(LocalLine.self, from: data),
                      (parsed.type == "assistant" || parsed.message?.role == "assistant"),
                      let usage = parsed.message?.usage,
                      let stamp = parsed.timestamp,
                      let date = UsageFormat.parseDate(stamp) else {
                    return true
                }

                let tokens = (usage.input_tokens ?? 0)
                    + (usage.output_tokens ?? 0)
                    + (usage.cache_creation_input_tokens ?? 0)
                    + (usage.cache_read_input_tokens ?? 0)
                guard tokens > 0 else { return true }

                if date >= weekAgo {
                    weeklyTokens += tokens
                    latest = max(latest, date)
                    if oldestWeekly == nil || date < oldestWeekly! {
                        oldestWeekly = date
                    }
                }
                if date >= fiveHoursAgo {
                    fiveHourTokens += tokens
                    if oldestFiveHour == nil || date < oldestFiveHour! {
                        oldestFiveHour = date
                    }
                }
                return true
            }) {}
        }

        guard weeklyTokens > 0 else { return nil }

        return UsageSnapshot(
            provider: .claude,
            primary: LimitWindow(
                usedPercent: min(100, Double(fiveHourTokens) / 90_000_000 * 100),
                resetAt: oldestFiveHour?.addingTimeInterval(5 * 3600)
            ),
            secondary: LimitWindow(
                usedPercent: min(100, Double(weeklyTokens) / 440_000_000 * 100),
                resetAt: oldestWeekly?.addingTimeInterval(7 * 24 * 3600)
            ),
            plan: "EST",
            updatedAt: latest == .distantPast ? now : latest,
            error: nil
        )
    }

    private static func recentJSONLFiles(in directory: URL, modifiedAfter cutoff: Date) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  (values.contentModificationDate ?? .distantPast) >= cutoff else {
                continue
            }
            files.append(url)
        }
        return files
    }

    struct LineReader {
        private let handle: FileHandle
        private var buffer = Data()
        private var finished = false

        init(_ handle: FileHandle) {
            self.handle = handle
        }

        mutating func next() -> String? {
            while true {
                if let newline = buffer.firstIndex(of: 10) {
                    let line = String(data: buffer[buffer.startIndex..<newline], encoding: .utf8)
                    buffer.removeSubrange(buffer.startIndex...newline)
                    return line
                }
                if finished {
                    guard !buffer.isEmpty else { return nil }
                    let line = String(data: buffer, encoding: .utf8)
                    buffer.removeAll()
                    return line
                }
                let chunk = handle.readData(ofLength: 1 << 16)
                if chunk.isEmpty {
                    finished = true
                } else {
                    buffer.append(chunk)
                }
            }
        }
    }
}

/// Reads Gemini Apps usage from the same authenticated web endpoint backing
/// gemini.google.com/usage. The request reuses the user's local Chrome Google
/// session cookies at runtime; TokenBar does not persist or log those cookies.
actor GeminiUsageCollector: UsageCollecting {
    let provider: Provider = .gemini

    private var cached: UsageSnapshot?
    private var cachedAt = Date.distantPast

    private struct Bootstrap {
        let buildLabel: String?
        let fSid: String?
        let at: String?
        let hl: String
    }

    func collect(force _: Bool) async -> UsageSnapshot {
        let now = Date()
        if let cached, now.timeIntervalSince(cachedAt) < 120 {
            return cached
        }
        do {
            let snapshot = try await fetchUsage()
            cached = snapshot
            cachedAt = now
            return snapshot
        } catch {
            if let cached, now.timeIntervalSince(cachedAt) < 10 * 60 {
                return cached
            }
            return .failure(.gemini, error.localizedDescription)
        }
    }

    private func fetchUsage() async throws -> UsageSnapshot {
        var lastError: Error?
        for session in try ChromeCookieStore.googleSessions() {
            do {
                let bootstrap = try await fetchBootstrap(session: session)
                return try await fetchUsage(session: session, bootstrap: bootstrap)
            } catch {
                lastError = error
                if !Self.isAuthenticationError(error) {
                    throw error
                }
            }
        }
        throw lastError ?? CollectorError.message("Gemini login required in Chrome")
    }

    private static func isAuthenticationError(_ error: Error) -> Bool {
        error.localizedDescription.contains("login required")
            || error.localizedDescription.contains("HTTP 401")
            || error.localizedDescription.contains("HTTP 403")
    }

    private func fetchBootstrap(session: ChromeCookieStore.GoogleSession) async throws -> Bootstrap {
        var request = URLRequest(url: URL(string: "https://gemini.google.com/usage")!)
        request.timeoutInterval = 12
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("https://gemini.google.com/usage", forHTTPHeaderField: "Referer")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let authorization = session.authorization {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        request.setValue(session.cookieHeader, forHTTPHeaderField: "Cookie")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw CollectorError.message("Gemini usage page: HTTP \(status)")
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw CollectorError.message("Gemini usage page: unreadable response")
        }
        return Bootstrap(
            buildLabel: Self.firstMatch(#"boq_assistant-bard-web-server_[A-Za-z0-9._-]+"#, in: html),
            fSid: Self.firstMatch(#""FdrFJe"\s*:\s*"(-?\d+)""#, in: html)
                ?? Self.firstMatch(#"\[\s*"FdrFJe"\s*,\s*"(-?\d+)""#, in: html)
                ?? Self.firstMatch(#"f\.sid=(-?\d+)"#, in: html),
            at: Self.firstMatch(#""SNlM0e"\s*:\s*"([^"]+)""#, in: html)
                ?? Self.firstMatch(#"\[\s*"SNlM0e"\s*,\s*"([^"]+)""#, in: html),
            hl: Locale.current.language.languageCode?.identifier ?? "en"
        )
    }

    private func fetchUsage(session: ChromeCookieStore.GoogleSession, bootstrap: Bootstrap) async throws -> UsageSnapshot {
        var components = URLComponents(string: "https://gemini.google.com/_/BardChatUi/data/batchexecute")!
        var queryItems = [
            URLQueryItem(name: "rpcids", value: "jSf9Qc"),
            URLQueryItem(name: "source-path", value: "/usage")
        ]
        if let buildLabel = bootstrap.buildLabel {
            queryItems.append(URLQueryItem(name: "bl", value: buildLabel))
        }
        if let fSid = bootstrap.fSid {
            queryItems.append(URLQueryItem(name: "f.sid", value: fSid))
        }
        queryItems.append(URLQueryItem(name: "hl", value: bootstrap.hl))
        queryItems.append(URLQueryItem(name: "_reqid", value: String(Int.random(in: 100_000...999_999))))
        queryItems.append(URLQueryItem(name: "rt", value: "c"))
        components.queryItems = queryItems
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://gemini.google.com", forHTTPHeaderField: "Origin")
        request.setValue("https://gemini.google.com/usage", forHTTPHeaderField: "Referer")
        request.setValue("1", forHTTPHeaderField: "X-Same-Domain")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let authorization = session.authorization {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        request.setValue(session.cookieHeader, forHTTPHeaderField: "Cookie")
        var fields = [
            "f.req": #"[[["jSf9Qc","[]",null,"generic"]]]"#
        ]
        if let at = bootstrap.at, !at.isEmpty {
            fields["at"] = at
        }
        request.httpBody = Self.formBody(fields)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw CollectorError.message("Gemini usage API: HTTP \(status)")
        }
        return try Self.parseUsageResponse(data)
    }

    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36"

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        let captureIndex = match.numberOfRanges > 1 ? 1 : 0
        guard let captureRange = Range(match.range(at: captureIndex), in: text) else { return nil }
        return String(text[captureRange])
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\\u003d"#, with: "=")
    }

    private static func formBody(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._* ")
        let body = fields.map { key, value in
            let escapedKey = key.addingPercentEncoding(withAllowedCharacters: allowed)?
                .replacingOccurrences(of: " ", with: "+") ?? key
            let escapedValue = value.addingPercentEncoding(withAllowedCharacters: allowed)?
                .replacingOccurrences(of: " ", with: "+") ?? value
            return "\(escapedKey)=\(escapedValue)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    private static func parseUsageResponse(_ data: Data) throws -> UsageSnapshot {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CollectorError.message("Gemini usage API: unreadable response")
        }
        let root = try batchedRows(from: text)
        guard !root.isEmpty else {
            throw CollectorError.message("Gemini usage API: bad response")
        }
        guard
            let rpc = root.first(where: {
                guard let row = $0 as? [Any], row.count > 2 else { return false }
                return row[0] as? String == "wrb.fr" && row[1] as? String == "jSf9Qc"
            }) as? [Any],
            let payload = rpc[2] as? String,
            !payload.isEmpty,
            payload != "null"
        else {
            throw CollectorError.message("Gemini login required in Chrome")
        }
        guard let usageObject = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [Any] else {
            throw CollectorError.message("Gemini usage API: bad payload")
        }

        var current: GeminiWindow?
        var weekly: GeminiWindow?
        collectWindows(in: usageObject, current: &current, weekly: &weekly)
        guard current != nil || weekly != nil else {
            throw CollectorError.message("Gemini usage API: no usage windows")
        }

        return UsageSnapshot(
            provider: .gemini,
            primary: current?.limitWindow,
            secondary: weekly?.limitWindow,
            plan: planName(from: usageObject),
            updatedAt: Date(),
            error: nil
        )
    }

    private static func batchedRows(from text: String) throws -> [Any] {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix(")]}'") }
        let joined = lines.joined(separator: "\n")
        if let root = try? JSONSerialization.jsonObject(with: Data(joined.utf8)) as? [Any] {
            return root
        }

        var rows: [Any] = []
        for line in lines where line.hasPrefix("[") {
            guard let parsed = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [Any] else {
                continue
            }
            if parsed.first is [Any] {
                rows.append(contentsOf: parsed)
            } else {
                rows.append(parsed)
            }
        }
        return rows
    }

    private struct GeminiWindow {
        let usedPercent: Double
        let resetAt: Date?

        var limitWindow: LimitWindow {
            LimitWindow(usedPercent: usedPercent, resetAt: resetAt)
        }
    }

    private static func collectWindows(in value: Any, current: inout GeminiWindow?, weekly: inout GeminiWindow?) {
        guard let array = value as? [Any] else { return }
        if let type = int(array[safe: 2]),
           (type == 1 || type == 2),
           let fraction = number(array[safe: 1]) {
            let window = GeminiWindow(
                usedPercent: max(0, min(100, fraction * 100)),
                resetAt: date(in: array[safe: 3] ?? array)
            )
            if type == 1 {
                current = window
            } else {
                weekly = window
            }
        }
        for child in array {
            collectWindows(in: child, current: &current, weekly: &weekly)
        }
    }

    private static func planName(from value: Any) -> String? {
        guard let array = value as? [Any], let plan = int(array[safe: 0]) else { return nil }
        switch plan {
        case 2: return "PRO"
        case 3, 6: return "ULTRA"
        case 4: return "PLUS"
        default: return nil
        }
    }

    private static func date(in value: Any) -> Date? {
        if let array = value as? [Any] {
            if let seconds = number(array[safe: 0]),
               seconds > 1_500_000_000,
               seconds < 2_200_000_000 {
                let nanos = number(array[safe: 1]) ?? 0
                return Date(timeIntervalSince1970: seconds + nanos / 1_000_000_000)
            }
            for child in array {
                if let date = date(in: child) {
                    return date
                }
            }
        }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        switch value {
        case let value as Int: value
        case let value as Double: Int(value)
        case let value as NSNumber: value.intValue
        case let value as String: Int(value)
        default: nil
        }
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let value as Double: value
        case let value as Int: Double(value)
        case let value as NSNumber: value.doubleValue
        case let value as String: Double(value)
        default: nil
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private final class SnapshotBox: @unchecked Sendable {
    var snapshot: UsageSnapshot?
}

private final class SingleInstanceLock {
    private let descriptor: Int32

    static func acquire(name: String) -> SingleInstanceLock? {
        SingleInstanceLock(name: name)
    }

    private init?(name: String) {
        let lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name).lock")
        let fd = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { return nil }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return nil
        }

        descriptor = fd
        let pid = "\(getpid())\n"
        _ = ftruncate(descriptor, 0)
        pid.withCString { pointer in
            _ = write(descriptor, pointer, strlen(pointer))
        }
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}

/// Reads Cursor usage through the dashboard API, authenticated with the
/// session token Cursor stores in its local state database.
actor CursorUsageCollector: UsageCollecting {
    nonisolated let provider: Provider = .cursor

    private var cached: UsageSnapshot?
    private var cachedAt = Date.distantPast

    func collect(force: Bool) async -> UsageSnapshot {
        let now = Date()
        if !force, let cached, now.timeIntervalSince(cachedAt) < 60 {
            return cached
        }
        do {
            let snapshot = try await fetchUsage()
            cached = snapshot
            cachedAt = now
            return snapshot
        } catch {
            if let cached, now.timeIntervalSince(cachedAt) < 2 * 3600 {
                return cached
            }
            return .failure(.cursor, error.localizedDescription)
        }
    }

    private func fetchUsage() async throws -> UsageSnapshot {
        let token = try readAccessToken()
        guard let userId = Self.subject(fromJWT: token)?.split(separator: "|").last else {
            throw CollectorError.message("Cursor token not readable")
        }
        let cookie = "WorkosCursorSessionToken=\(userId)%3A%3A\(token)"

        // Current Cursor plans bill against a dollar-denominated included
        // allowance, exposed via the dashboard's usage-summary endpoint. The old
        // /api/usage gpt-4 counters are vestigial and now report zeros, which is
        // why the card stopped reflecting real usage. Fall back to the legacy
        // counters only for older request-based plans.
        if let snapshot = try await loadUsageSummary(cookie: cookie) {
            return snapshot
        }
        return try await loadLegacyUsage(userId: String(userId), cookie: cookie)
    }

    private func readAccessToken() throws -> String {
        let database = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        guard FileManager.default.fileExists(atPath: database.path) else {
            throw CollectorError.message("Cursor not installed")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            database.path,
            "SELECT value FROM ItemTable WHERE key='cursorAuth/accessToken'"
        ]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let token = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty else {
            throw CollectorError.message("Cursor session token not found")
        }
        return token
    }

    /// Reads the modern dashboard usage summary. Returns nil (so the caller can
    /// fall back to the legacy endpoint) when the response lacks plan usage.
    private func loadUsageSummary(cookie: String) async throws -> UsageSnapshot? {
        var request = URLRequest(url: URL(string: "https://cursor.com/api/usage-summary")!)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")

        let (body, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let individual = object["individualUsage"] as? [String: Any],
              let plan = individual["plan"] as? [String: Any] else {
            return nil
        }

        // The percentage fields are unit-agnostic (work for both dollar- and
        // request-based allowances), so we render those directly. The dashboard
        // headline is the *combined* included usage (`totalPercentUsed`); the
        // auto-model figure is nearly always ~0% and misleading as a headline,
        // so we surface combined usage as primary and the named-model/API usage
        // as secondary — matching cursor.com's two summary lines.
        let totalUsed = Self.clampPercent(
            Self.number(plan["totalPercentUsed"]) ?? Self.number(plan["autoPercentUsed"]) ?? 0
        )
        let apiUsed = Self.clampPercent(Self.number(plan["apiPercentUsed"]) ?? 0)
        let autoUsed = Self.clampPercent(Self.number(plan["autoPercentUsed"]) ?? 0)
        let resetAt = UsageFormat.parseDate(object["billingCycleEnd"] as? String)
        let plan_ = (object["membershipType"] as? String)?.uppercased() ?? "MONTH"

        // Combined ("All") is the headline for small/collapsed states; the
        // expanded card drills into the Auto + API breakdown (tertiary = Auto).
        return UsageSnapshot(
            provider: .cursor,
            primary: LimitWindow(usedPercent: totalUsed, resetAt: resetAt),
            secondary: LimitWindow(usedPercent: apiUsed, resetAt: resetAt),
            tertiary: LimitWindow(usedPercent: autoUsed, resetAt: resetAt),
            plan: plan_,
            updatedAt: Date(),
            error: nil
        )
    }

    private func loadLegacyUsage(userId: String, cookie: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: URL(string: "https://cursor.com/api/usage?user=\(userId)")!)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")

        let (body, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard
            status == 200,
            let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let gpt4 = object["gpt-4"] as? [String: Any]
        else {
            throw CollectorError.message("Cursor usage API: HTTP \(status)")
        }

        let used = (gpt4["numRequests"] as? NSNumber)?.doubleValue ?? 0
        let limit = (gpt4["maxRequestUsage"] as? NSNumber)?.doubleValue
        let requestPercent: Double = if let limit, limit > 0 {
            min(100, used / limit * 100)
        } else {
            0
        }
        let tokens = (gpt4["numTokens"] as? NSNumber)?.doubleValue ?? 0
        let tokenLimit = (gpt4["maxTokenUsage"] as? NSNumber)?.doubleValue
        let tokenPercent: Double = if let tokenLimit, tokenLimit > 0 {
            min(100, tokens / tokenLimit * 100)
        } else {
            0
        }
        let advancedPercent = max(requestPercent, tokenPercent)

        var resetAt: Date?
        if let start = UsageFormat.parseDate(object["startOfMonth"] as? String) {
            resetAt = Calendar.current.date(byAdding: .month, value: 1, to: start)
        }

        return UsageSnapshot(
            provider: .cursor,
            primary: LimitWindow(usedPercent: requestPercent, resetAt: resetAt),
            secondary: LimitWindow(usedPercent: advancedPercent, resetAt: resetAt),
            plan: "MONTH",
            updatedAt: Date(),
            error: nil
        )
    }

    private static func clampPercent(_ value: Double) -> Double {
        max(0, min(100, value))
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let value as Double: value
        case let value as Int: Double(value)
        case let value as NSNumber: value.doubleValue
        case let value as String: Double(value)
        default: nil
        }
    }

    private static func subject(fromJWT token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard
            let data = Data(base64Encoded: payload),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["sub"] as? String
    }
}

actor OpenRouterUsageCollector: UsageCollecting {
    nonisolated let provider: Provider = .openrouter

    static let keychainService = "TokenBar.OpenRouter"
    static let keychainAccount = "apiKey"

    private var cached: UsageSnapshot?
    private var cachedAt = Date.distantPast

    func collect(force _: Bool) async -> UsageSnapshot {
        let now = Date()
        do {
            let snapshot = try await fetchUsage()
            cached = snapshot
            cachedAt = now
            return snapshot
        } catch {
            if let cached, now.timeIntervalSince(cachedAt) < 10 * 60 {
                return cached
            }
            return .failure(.openrouter, error.localizedDescription)
        }
    }

    private func fetchUsage() async throws -> UsageSnapshot {
        let key = SecretStore.read(service: Self.keychainService, account: Self.keychainAccount)
            ?? ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]
        guard let key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CollectorError.message("Set API key")
        }

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/credits")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (body, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let data = object["data"] as? [String: Any],
              let usage = number(data["total_usage"]) else {
            throw CollectorError.message("OpenRouter credits API: HTTP \(status)")
        }

        return UsageSnapshot(
            provider: .openrouter,
            primary: LimitWindow(usedPercent: 0, resetAt: nil, valueText: UsageFormat.money(usage)),
            secondary: nil,
            plan: "Spent",
            updatedAt: Date(),
            error: nil
        )
    }

    private func number(_ value: Any?) -> Double? {
        switch value {
        case let value as Double: value
        case let value as Int: Double(value)
        case let value as NSNumber: value.doubleValue
        case let value as String: Double(value)
        default: nil
        }
    }
}

actor WorkBuddyUsageCollector: UsageCollecting {
    nonisolated let provider: Provider = .workbuddy

    private var cached: UsageSnapshot?
    private var cachedAt = Date.distantPast

    func collect(force _: Bool) async -> UsageSnapshot {
        let now = Date()
        do {
            let snapshot = try await fetchUsage()
            cached = snapshot
            cachedAt = now
            return snapshot
        } catch {
            if let cached, now.timeIntervalSince(cachedAt) < 10 * 60 {
                return cached
            }
            return .failure(.workbuddy, error.localizedDescription)
        }
    }

    private struct Session {
        let accessToken: String
        let uid: String
        let enterpriseId: String?
    }

    private struct Resource {
        let packageCode: String
        let total: Double
        let left: Double
        let resetAt: Date?
    }

    private func fetchUsage() async throws -> UsageSnapshot {
        let session = try readSession()
        if let enterpriseId = session.enterpriseId, !enterpriseId.isEmpty {
            return try await fetchEnterpriseUsage(session: session, enterpriseId: enterpriseId)
        }
        return try await fetchPersonalUsage(session: session)
    }

    private func fetchEnterpriseUsage(session: Session, enterpriseId: String) async throws -> UsageSnapshot {
        let object = try await postJSON(
            url: URL(string: "https://copilot.tencent.com/billing/meter/get-enterprise-user-usage")!,
            body: [:],
            session: session,
            extraHeaders: ["X-Enterprise-Id": enterpriseId, "X-Tenant-Id": enterpriseId]
        )
        let payload = (object["data"] as? [String: Any]) ?? object
        let data = (payload["data"] as? [String: Any]) ?? payload
        guard let limit = number(data["limitNum"]), limit > 0 else {
            throw CollectorError.message("WorkBuddy enterprise usage missing")
        }
        let used = number(data["credit"]) ?? 0
        let left = max(0, limit - used)
        let resetAt = UsageFormat.parseLooseDate(data["cycleResetTime"] as? String)
        return snapshot(left: left, total: limit, resetAt: resetAt)
    }

    private func fetchPersonalUsage(session: Session) async throws -> UsageSnapshot {
        let now = Date()
        let futureDate = Calendar.current.date(byAdding: .year, value: 101, to: now) ?? now
        let body: [String: Any] = [
            "PageNumber": 1,
            "PageSize": 100,
            "ProductCode": "p_tcaca",
            "Status": [0, 3],
            "PackageEndTimeRangeBegin": Self.dateFormatter.string(from: now),
            "PackageEndTimeRangeEnd": Self.dateFormatter.string(from: futureDate)
        ]
        let object = try await postJSON(
            url: URL(string: "https://copilot.tencent.com/billing/meter/get-user-resource")!,
            body: body,
            session: session
        )
        let root = object["data"] as? [String: Any]
        let accounts = (((root?["Response"] as? [String: Any])?["Data"] as? [String: Any])?["Accounts"] as? [[String: Any]]) ?? []
        let resources = accounts.compactMap(resource)
        guard !resources.isEmpty else {
            throw CollectorError.message("WorkBuddy usage empty")
        }
        let total = resources.reduce(0) { $0 + $1.total }
        let left = resources.reduce(0) { $0 + $1.left }
        guard total > 0 else {
            throw CollectorError.message("WorkBuddy usage total missing")
        }
        let resetAt = resources.sorted { priority($0.packageCode) < priority($1.packageCode) }.first?.resetAt
        return snapshot(left: left, total: total, resetAt: resetAt)
    }

    private func snapshot(left: Double, total: Double, resetAt: Date?) -> UsageSnapshot {
        UsageSnapshot(
            provider: .workbuddy,
            primary: LimitWindow(
                usedPercent: max(0, min(100, (total - left) / total * 100)),
                resetAt: resetAt,
                valueText: UsageFormat.credits(left)
            ),
            secondary: nil,
            plan: "\(UsageFormat.credits(left))/\(UsageFormat.credits(total))",
            updatedAt: Date(),
            error: nil
        )
    }

    private func readSession() throws -> Session {
        guard let file = Self.authFile() else {
            throw CollectorError.message("WorkBuddy login not found")
        }
        let data = try Data(contentsOf: file)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = object["auth"] as? [String: Any],
              let account = object["account"] as? [String: Any],
              let token = auth["accessToken"] as? String,
              !token.isEmpty else {
            throw CollectorError.message("WorkBuddy auth unreadable")
        }
        return Session(
            accessToken: token,
            uid: account["uid"] as? String ?? "",
            enterpriseId: account["enterpriseId"] as? String
        )
    }

    private func postJSON(
        url: URL,
        body: [String: Any],
        session: Session,
        extraHeaders: [String: String] = [:]
    ) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        if !session.uid.isEmpty {
            request.setValue(session.uid, forHTTPHeaderField: "X-User-Id")
        }
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CollectorError.message("WorkBuddy API: HTTP \(status)")
        }
        return object
    }

    private func resource(from account: [String: Any]) -> Resource? {
        guard let packageCode = account["PackageCode"] as? String else { return nil }
        let total = number(account["CycleCapacitySizePrecise"]) ?? 0
        let left = number(account["CycleCapacityRemainPrecise"]) ?? 0
        return Resource(
            packageCode: packageCode,
            total: total,
            left: left,
            resetAt: UsageFormat.parseLooseDate(account["CycleEndTime"] as? String)
        )
    }

    private func priority(_ packageCode: String) -> Int {
        switch packageCode {
        case "TCACA_code_002_AkiJS3ZHF5", "TCACA_code_005_maRGyrHhw1", "TCACA_code_003_FAnt7lcmRT",
             "TCACA_code_008_cfWoLwvjU4", "TCACA_code_009_0XmEQc2xOf":
            1
        case "TCACA_code_006_DbXS0lrypC", "TCACA_code_007_nzdH5h4Nl0":
            2
        case "TCACA_code_001_PqouKr6QWV":
            3
        default:
            4
        }
    }

    private func number(_ value: Any?) -> Double? {
        switch value {
        case let value as Double: value
        case let value as Int: Double(value)
        case let value as NSNumber: value.doubleValue
        case let value as String: Double(value)
        default: nil
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static func authFile() -> URL? {
        let directories = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/CodeBuddyExtension/Data/Public/auth"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/WorkBuddyExtension/Data/Public/auth")
        ]
        for directory in directories {
            let preferred = directory.appendingPathComponent("workbuddy-desktop.info")
            if FileManager.default.fileExists(atPath: preferred.path) {
                return preferred
            }
            if let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil),
               let file = files.first(where: { $0.pathExtension == "info" }) {
                return file
            }
        }
        return nil
    }
}

/// Reads Antigravity's official runtime quota data from its local language
/// server. This mirrors the Antigravity Quota Watcher approach: detect the
/// language_server process, find its listening API port, and call GetUserStatus.
struct AntigravityUsageCollector: UsageCollecting {
    let provider: Provider = .antigravity

    func collect(force _: Bool) async -> UsageSnapshot {
        await Task.detached(priority: .utility) {
            do {
                return try Self.readUserStatus()
            } catch {
                return .failure(.antigravity, error.localizedDescription)
            }
        }.value
    }

    private struct ProcessInfo {
        let pid: Int32
        let csrfToken: String
    }

    private final class LocalHTTPSDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
        func urlSession(
            _ session: URLSession,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            guard challenge.protectionSpace.host == "127.0.0.1",
                  let trust = challenge.protectionSpace.serverTrust else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            completionHandler(.useCredential, URLCredential(trust: trust))
        }
    }

    private final class RequestResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Result<[String: Any], Error>?

        func set(_ value: Result<[String: Any], Error>) {
            lock.lock()
            self.value = value
            lock.unlock()
        }

        func get() -> Result<[String: Any], Error>? {
            lock.lock()
            let value = self.value
            lock.unlock()
            return value
        }
    }

    private static func readUserStatus() throws -> UsageSnapshot {
        let process = try detectProcess()
        let ports = try listeningPorts(for: process.pid)
        guard !ports.isEmpty else {
            throw CollectorError.message("Antigravity API port not found")
        }

        let session = URLSession(
            configuration: .ephemeral,
            delegate: LocalHTTPSDelegate(),
            delegateQueue: nil
        )

        var validPort: Int?
        for port in ports {
            if (try? request(
                path: "/exa.language_server_pb.LanguageServerService/GetUnleashData",
                port: port,
                csrfToken: process.csrfToken,
                body: ["wrapper_data": [:] as [String: Any]],
                session: session
            )) != nil {
                validPort = port
                break
            }
        }
        guard let validPort else {
            throw CollectorError.message("Antigravity API did not respond")
        }

        // RetrieveUserQuotaSummary returns the live, official rate-limit buckets
        // the IDE itself shows: a 5-hour window and a weekly window per model
        // group, each with a remaining fraction and reset time. This reflects
        // real throttling headroom and updates as models are used.
        let object = try request(
            path: "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary",
            port: validPort,
            csrfToken: process.csrfToken,
            body: [
                "metadata": [
                    "ideName": "antigravity",
                    "extensionName": "antigravity",
                    "locale": "en"
                ]
            ],
            session: session
        )
        return try snapshot(from: object)
    }

    private static func detectProcess() throws -> ProcessInfo {
        guard let output = try? runProcess("/usr/bin/env", ["LC_ALL=C", "pgrep", "-fl", "language_server"]) else {
            throw CollectorError.message("Antigravity not running")
        }
        for line in output.split(separator: "\n").map(String.init) {
            guard isAntigravityProcess(line),
                  let pid = Int32(line.split(separator: " ").first ?? ""),
                  let token = firstMatch(in: line, pattern: #"--csrf_token[=\s]+([A-Za-z0-9\-]+)"#) else {
                continue
            }
            return ProcessInfo(pid: pid, csrfToken: token)
        }
        throw CollectorError.message("Antigravity not running")
    }

    private static func isAntigravityProcess(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("--app_data_dir antigravity")
            || lower.contains("/antigravity.app/")
            || lower.contains("/.antigravity/")
    }

    private static func listeningPorts(for pid: Int32) throws -> [Int] {
        let output = try runProcess("/usr/sbin/lsof", ["-nP", "-a", "-iTCP", "-sTCP:LISTEN", "-p", "\(pid)"])
        var ports: [Int] = []
        for line in output.split(separator: "\n").map(String.init) {
            guard line.contains("(LISTEN)"),
                  let raw = firstMatch(in: line, pattern: #":(\d+)\s+\(LISTEN\)"#),
                  let port = Int(raw),
                  !ports.contains(port) else {
                continue
            }
            ports.append(port)
        }
        return ports.sorted()
    }

    private static func request(
        path: String,
        port: Int,
        csrfToken: String,
        body: [String: Any],
        session: URLSession
    ) throws -> [String: Any] {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = RequestResultBox()
        let finish: @Sendable (Result<[String: Any], Error>) -> Void = { value in
            resultBox.set(value)
            semaphore.signal()
        }

        let url = URL(string: "https://127.0.0.1:\(port)\(path)")!
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        session.dataTask(with: request) { data, response, error in
            if let error {
                finish(.failure(error))
            } else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200, let data else {
                    finish(.failure(CollectorError.message("Antigravity API HTTP \(status)")))
                    return
                }
                do {
                    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        throw CollectorError.message("Antigravity API returned non-object JSON")
                    }
                    finish(.success(object))
                } catch {
                    finish(.failure(error))
                }
            }
        }.resume()

        guard semaphore.wait(timeout: .now() + 6) == .success else {
            throw CollectorError.message("Antigravity API timed out")
        }
        guard let result = resultBox.get() else {
            throw CollectorError.message("Antigravity API returned no data")
        }
        return try result.get()
    }

    private struct Bucket {
        let remainingFraction: Double
        let resetAt: Date?
    }

    private static func snapshot(from object: [String: Any]) throws -> UsageSnapshot {
        guard let response = object["response"] as? [String: Any],
              let groups = response["groups"] as? [[String: Any]] else {
            throw CollectorError.message("Antigravity API: missing quota summary")
        }

        // Each model group exposes a 5-hour and a weekly bucket. We surface the
        // most-depleted group per window so the bar reflects the binding limit.
        var fiveHour: Bucket?
        var weekly: Bucket?
        for group in groups {
            guard let buckets = group["buckets"] as? [[String: Any]] else { continue }
            for bucket in buckets {
                let fraction = max(0, min(1, number(bucket["remainingFraction"]) ?? 1))
                let reset = UsageFormat.parseDate(bucket["resetTime"] as? String)
                let candidate = Bucket(remainingFraction: fraction, resetAt: reset)
                switch bucket["window"] as? String {
                case "5h":
                    if fiveHour == nil || fraction < fiveHour!.remainingFraction { fiveHour = candidate }
                case "weekly":
                    if weekly == nil || fraction < weekly!.remainingFraction { weekly = candidate }
                default:
                    continue
                }
            }
        }

        func window(_ bucket: Bucket?) -> LimitWindow? {
            guard let bucket else { return nil }
            return LimitWindow(
                usedPercent: max(0, min(100, (1 - bucket.remainingFraction) * 100)),
                resetAt: bucket.resetAt
            )
        }

        guard fiveHour != nil || weekly != nil else {
            throw CollectorError.message("Antigravity API: no quota data")
        }

        return UsageSnapshot(
            provider: .antigravity,
            primary: window(fiveHour),
            secondary: window(weekly),
            plan: nil,
            updatedAt: Date(),
            error: nil
        )
    }

    private static func firstMatch(in value: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return String(value[range])
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let value as Double: value
        case let value as Int: Double(value)
        case let value as NSNumber: value.doubleValue
        case let value as String: Double(value)
        default: nil
        }
    }

    private static func runProcess(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CollectorError.message("\(URL(fileURLWithPath: path).lastPathComponent) exited with \(process.terminationStatus)")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

enum CollectorError: LocalizedError {
    case message(String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .message(let message): message
        case .unauthorized: "Claude token rejected; run `claude` to re-login"
        }
    }
}

@MainActor
enum ControlStrip {
    private typealias PresenceFn = @convention(c) (NSString, Bool) -> Void
    private typealias CloseBoxFn = @convention(c) (Bool) -> Void

    private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/DFRFoundation.framework/Versions/A/DFRFoundation",
        RTLD_NOW
    )

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    static var isSupported: Bool {
        (NSTouchBarItem.self as AnyObject).responds(to: NSSelectorFromString("addSystemTrayItem:"))
    }

    static func add(_ item: NSTouchBarItem) {
        let selector = NSSelectorFromString("addSystemTrayItem:")
        guard (NSTouchBarItem.self as AnyObject).responds(to: selector) else { return }
        _ = (NSTouchBarItem.self as AnyObject).perform(selector, with: item)
        setPresent(item.identifier, true)
    }

    static func remove(_ item: NSTouchBarItem) {
        setPresent(item.identifier, false)
        let selector = NSSelectorFromString("removeSystemTrayItem:")
        guard (NSTouchBarItem.self as AnyObject).responds(to: selector) else { return }
        _ = (NSTouchBarItem.self as AnyObject).perform(selector, with: item)
    }

    static func presentModal(_ touchBar: NSTouchBar, trayIdentifier: NSTouchBarItem.Identifier) {
        symbol("DFRSystemModalShowsCloseBoxWhenFrontMost", as: CloseBoxFn.self)?(true)
        for name in [
            "presentSystemModalTouchBar:systemTrayItemIdentifier:",
            "presentSystemModalFunctionBar:systemTrayItemIdentifier:"
        ] {
            let selector = NSSelectorFromString(name)
            if (NSTouchBar.self as AnyObject).responds(to: selector) {
                _ = (NSTouchBar.self as AnyObject).perform(selector, with: touchBar, with: trayIdentifier.rawValue)
                return
            }
        }
    }

    static func dismissModal(_ touchBar: NSTouchBar) {
        for name in ["dismissSystemModalTouchBar:", "dismissSystemModalFunctionBar:"] {
            let selector = NSSelectorFromString(name)
            if (NSTouchBar.self as AnyObject).responds(to: selector) {
                _ = (NSTouchBar.self as AnyObject).perform(selector, with: touchBar)
                return
            }
        }
    }

    private static func setPresent(_ identifier: NSTouchBarItem.Identifier, _ present: Bool) {
        symbol("DFRElementSetControlStripPresenceForIdentifier", as: PresenceFn.self)?(
            identifier.rawValue as NSString,
            present
        )
    }
}

@MainActor
final class TouchBarController: NSObject, NSTouchBarDelegate {
    private static let detailIdentifier = NSTouchBarItem.Identifier("TokenBar.detail")
    private static let refreshIdentifier = NSTouchBarItem.Identifier("TokenBar.refresh")
    private static let trayIdentifier = NSTouchBarItem.Identifier("TokenBar.tray")

    private let store: UsageStore
    private let touchBar = NSTouchBar()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var trayItem: NSCustomTouchBarItem?
    private weak var detailItem: NSCustomTouchBarItem?
    private weak var trayButton: NSButton?
    private weak var refreshButton: NSButton?
    private var timer: Timer?
    private var didStop = false
    private var isRefreshing = false
    private var refreshAgain = false
    private var pendingForce = false
    private var expandedProvider: Provider?
    private var draggingProvider: Provider?
    private var suppressNextTapProvider: Provider?
    private weak var cardRow: NSStackView?
    private var dragGrid: DragGrid?
    private var visibleProviders: [Provider] {
        ProviderDisplayConfig.visibleProviders
    }

    /// Fixed slot geometry captured when a reorder drag begins. Because every
    /// card in compact mode has the same width, slot centers stay constant
    /// (`firstCenter + index * pitch`) even as cards shuffle, so we can map the
    /// finger position to a target index without recomputing frames mid-drag.
    private struct DragGrid {
        let firstCenter: CGFloat
        let pitch: CGFloat
        let startCenter: CGFloat
        let count: Int
    }

    init(store: UsageStore) {
        self.store = store
        super.init()
        configureStatusItem()
        configureTouchBar()
    }

    func start() {
        didStop = false
        NSApp.touchBar = touchBar
        installTrayItem()
        refresh(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 5
        // Sync immediately when the machine wakes, so data is never stale after
        // the Mac has been asleep (or shut) for hours or days.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    func stop() {
        guard !didStop else { return }
        didStop = true
        timer?.invalidate()
        timer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(
            self,
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        if let trayItem {
            ControlStrip.remove(trayItem)
        }
        ControlStrip.dismissModal(touchBar)
        statusItem.isVisible = false
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func systemDidWake() {
        // After sleep the periodic timer may not fire promptly, so pull fresh
        // data immediately and bypass each collector's throttle.
        refresh(force: true)
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case Self.detailIdentifier:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = makeDetailView()
            detailItem = item
            return item
        case Self.refreshIdentifier:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let button = NSButton(
                image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")!,
                target: self,
                action: #selector(refreshPressed)
            )
            // Default bordered style: in the Touch Bar this renders as the native
            // rounded button that flashes on press, giving tap feedback.
            button.toolTip = "Refresh"
            item.view = button
            refreshButton = button
            return item
        default:
            return nil
        }
    }

    private func configureStatusItem() {
        statusItem.button?.title = "CX/CL"
        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        let menu = NSMenu()

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshPressed), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let showItem = NSMenuItem(title: "Show Touch Bar", action: #selector(showTouchBar), keyEquivalent: "t")
        showItem.target = self
        menu.addItem(showItem)

        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem.submenu = settingsMenu()
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    private func settingsMenu() -> NSMenu {
        let menu = NSMenu()
        let visible = Set(visibleProviders)

        for provider in Provider.allCases {
            let item = NSMenuItem(
                title: "Show \(provider.rawValue)",
                action: #selector(toggleProvider(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = provider.rawValue
            item.state = visible.contains(provider) ? .on : .off
            if visible.count == 1 && visible.contains(provider) {
                item.isEnabled = false
            }
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let openRouterKey = NSMenuItem(title: "OpenRouter API Key...", action: #selector(configureOpenRouterKey), keyEquivalent: "")
        openRouterKey.target = self
        menu.addItem(openRouterKey)

        let openRouterLogin = NSMenuItem(title: "Open OpenRouter Keys Page", action: #selector(openOpenRouterKeysPage), keyEquivalent: "")
        openRouterLogin.target = self
        menu.addItem(openRouterLogin)

        let clearOpenRouter = NSMenuItem(title: "Clear OpenRouter API Key", action: #selector(clearOpenRouterKey), keyEquivalent: "")
        clearOpenRouter.target = self
        clearOpenRouter.isEnabled = SecretStore.read(
            service: OpenRouterUsageCollector.keychainService,
            account: OpenRouterUsageCollector.keychainAccount
        ) != nil
        menu.addItem(clearOpenRouter)

        menu.addItem(.separator())
        let reset = NSMenuItem(title: "Reset to Codex + Claude", action: #selector(resetLayout), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)

        return menu
    }

    private func configureTouchBar() {
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [Self.detailIdentifier, Self.refreshIdentifier]
        touchBar.principalItemIdentifier = Self.detailIdentifier
        touchBar.customizationAllowedItemIdentifiers = [Self.detailIdentifier, Self.refreshIdentifier]
        touchBar.customizationIdentifier = NSTouchBar.CustomizationIdentifier("TokenBar.default")
    }

    private func installTrayItem() {
        guard ControlStrip.isSupported else { return }
        let item = NSCustomTouchBarItem(identifier: Self.trayIdentifier)
        let button = NSButton(title: "", target: self, action: #selector(showTouchBar))
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.image = makeTrayImage()
        button.toolTip = "Codex / Claude usage"
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 56).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        item.view = button
        trayItem = item
        trayButton = button
        ControlStrip.add(item)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.showTouchBar()
        }
    }

    @objc private func showTouchBar() {
        ControlStrip.presentModal(touchBar, trayIdentifier: Self.trayIdentifier)
    }

    @objc private func refreshPressed() {
        refresh(force: true)
    }

    @objc private func quitApp() {
        stop()
        disableLaunchAgent()
        NSApp.terminate(nil)
    }

    private func disableLaunchAgent() {
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/local.tokenbar.plist")
        guard FileManager.default.fileExists(atPath: plist.path) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", plist.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }

    private func refresh(force: Bool = false) {
        if isRefreshing {
            refreshAgain = true
            // Don't let a queued forced refresh be downgraded by a plain tick.
            pendingForce = pendingForce || force
            return
        }
        isRefreshing = true
        refreshButton?.isEnabled = false
        refreshButton?.alphaValue = 0.4

        Task {
            _ = await store.refresh(force: force)
            await MainActor.run {
                self.updateViews()
                self.isRefreshing = false
                if self.refreshAgain {
                    self.refreshAgain = false
                    let nextForce = self.pendingForce
                    self.pendingForce = false
                    self.refresh(force: nextForce)
                }
            }
        }
    }

    private func updateViews() {
        detailItem?.view = makeDetailView()
        trayButton?.image = makeTrayImage()
        statusItem.button?.attributedTitle = makeMenuTitle()
        rebuildStatusMenu()
        refreshButton?.isEnabled = true
        refreshButton?.alphaValue = 1
    }

    private func makeDetailView() -> NSView {
        let snapshots = visibleSnapshots()
        if let expandedProvider, !snapshots.contains(where: { $0.provider == expandedProvider }) {
            self.expandedProvider = nil
        }
        let expandedProvider = self.expandedProvider
        let compactLayout = snapshots.count > 2
        let modes = snapshots.map { snapshot in
            ProviderUsageView.Mode(
                provider: snapshot.provider,
                visibleCount: snapshots.count,
                expandedProvider: expandedProvider
            )
        }
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = switch snapshots.count {
        case 1: 0
        case 2: 8
        case 3: 5
        default: 3
        }
        row.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        row.translatesAutoresizingMaskIntoConstraints = false
        cardRow = row

        for (snapshot, mode) in zip(snapshots, modes) {
            let button = ProviderCardButton(provider: snapshot.provider, target: self, action: #selector(providerCardPressed(_:)))
            button.translatesAutoresizingMaskIntoConstraints = false
            button.wantsLayer = true
            button.widthAnchor.constraint(equalToConstant: mode.width).isActive = true
            button.heightAnchor.constraint(equalToConstant: 30).isActive = true
            if snapshots.count > 2 {
                // A press recognizer is continuous: after `.began` it keeps
                // sending `.changed` with the live finger location, so a single
                // recognizer arms edit mode AND drives the drag. Touch Bar
                // recognizers receive nothing unless allowedTouchTypes includes
                // `.direct` and numberOfTouchesRequired is non-zero.
                let press = NSPressGestureRecognizer(target: self, action: #selector(providerCardLongPressed(_:)))
                press.minimumPressDuration = 0.4
                press.allowedTouchTypes = [.direct]
                press.numberOfTouchesRequired = 1
                button.addGestureRecognizer(press)
            }

            let view = ProviderUsageView(snapshot: snapshot, mode: mode)
            view.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                view.topAnchor.constraint(equalTo: button.topAnchor),
                view.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])
            row.addArrangedSubview(button)
        }

        let totalWidth = modes.reduce(CGFloat(max(0, modes.count - 1)) * row.spacing + 8) { $0 + $1.width }
        let viewportWidth: CGFloat = compactLayout ? min(592, totalWidth) : min(574, totalWidth)
        let needsScroll = totalWidth > viewportWidth

        let container = NSView(frame: NSRect(x: 0, y: 0, width: max(totalWidth, viewportWidth), height: 30))
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)

        var constraints: [NSLayoutConstraint] = [
            row.widthAnchor.constraint(equalToConstant: totalWidth),
            row.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: max(totalWidth, viewportWidth)),
            container.heightAnchor.constraint(equalToConstant: 30)
        ]
        if needsScroll {
            constraints.append(row.leadingAnchor.constraint(equalTo: container.leadingAnchor))
        } else {
            constraints.append(row.centerXAnchor.constraint(equalTo: container.centerXAnchor))
        }
        NSLayoutConstraint.activate(constraints)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: viewportWidth, height: 30))
        scrollView.documentView = container
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.allowsMagnification = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.widthAnchor.constraint(equalToConstant: viewportWidth).isActive = true
        scrollView.heightAnchor.constraint(equalToConstant: 30).isActive = true
        scrollView.postsBoundsChangedNotifications = true
        return scrollView
    }

    private func makeMenuTitle() -> NSAttributedString {
        let text = NSMutableAttributedString()
        for (index, snapshot) in visibleSnapshots().enumerated() {
            if index > 0 {
                text.append(NSAttributedString(string: "  "))
            }
            let remaining = snapshot.primary?.remainingPercent
            let value = UsageFormat.windowValue(snapshot.primary)
            text.append(NSAttributedString(
                string: "\(snapshot.provider.shortName) \(value)",
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: remaining.map(UsageFormat.remainingColor) ?? NSColor.secondaryLabelColor
                ]
            ))
        }
        return text
    }

    private func makeTrayImage() -> NSImage {
        let providers = visibleProviders
        let size = NSSize(width: max(28, CGFloat(providers.count) * 12 + 4), height: 24)
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSImage(size: size)
        }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        let snapshots = Dictionary(uniqueKeysWithValues: store.current().map { ($0.provider, $0) })
        for (index, provider) in providers.enumerated() {
            let remaining = snapshots[provider]?.primary?.remainingPercent
            let x = CGFloat(index) * 12 + 3
            let track = NSBezierPath(roundedRect: NSRect(x: x, y: 4, width: 6, height: 16), xRadius: 3, yRadius: 3)
            provider.accent.withAlphaComponent(0.22).setFill()
            track.fill()

            if let remaining {
                let fillHeight = max(2, 16 * CGFloat(remaining / 100))
                let fill = NSBezierPath(
                    roundedRect: NSRect(x: x, y: 4, width: 6, height: fillHeight),
                    xRadius: 3,
                    yRadius: 3
                )
                UsageFormat.remainingColor(remaining).setFill()
                fill.fill()
            }
        }

        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(rep)
        image.isTemplate = false
        return image
    }

    private func visibleSnapshots() -> [UsageSnapshot] {
        let snapshots = Dictionary(uniqueKeysWithValues: store.current().map { ($0.provider, $0) })
        return visibleProviders.map { provider in
            snapshots[provider] ?? .failure(provider, "Loading")
        }
    }

    @objc private func toggleProvider(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let provider = Provider(rawValue: raw) else {
            return
        }
        ProviderDisplayConfig.setVisible(provider, sender.state != .on)
        updateViews()
    }

    @objc private func resetLayout() {
        ProviderDisplayConfig.reset()
        expandedProvider = nil
        updateViews()
    }

    private func toggleExpandedProvider(_ provider: Provider) {
        expandedProvider = expandedProvider == provider ? nil : provider
        updateViews()
    }

    @objc private func providerCardPressed(_ sender: ProviderCardButton) {
        if suppressNextTapProvider == sender.provider {
            draggingProvider = nil
            suppressNextTapProvider = nil
            return
        }
        toggleExpandedProvider(sender.provider)
    }

    /// Press-and-hold arms "edit mode" (all cards jiggle, held card lifts) and
    /// the same continuous recognizer then drives the live reorder as the finger
    /// moves. Reorder needs a neutral, equal-width layout, so it only arms when
    /// nothing is expanded.
    @objc private func providerCardLongPressed(_ recognizer: NSPressGestureRecognizer) {
        guard let button = recognizer.view as? ProviderCardButton,
              let row = button.superview as? NSStackView else {
            return
        }
        switch recognizer.state {
        case .began:
            guard visibleProviders.count > 2, expandedProvider == nil else { return }
            draggingProvider = button.provider
            suppressNextTapProvider = button.provider
            beginCardDrag(for: button)
        case .changed:
            guard draggingProvider == button.provider, let grid = dragGrid else { return }
            let fingerX = recognizer.location(in: row).x
            let raw = (fingerX - grid.firstCenter) / grid.pitch
            let targetIndex = max(0, min(grid.count - 1, Int(raw.rounded())))
            guard let currentIndex = row.arrangedSubviews.firstIndex(of: button),
                  targetIndex != currentIndex else {
                return
            }
            row.removeArrangedSubview(button)
            row.insertArrangedSubview(button, at: targetIndex)
            row.layoutSubtreeIfNeeded()
            // Persist the exact on-screen order and keep the held card on top.
            ProviderDisplayConfig.visibleProviders = row.arrangedSubviews
                .compactMap { ($0 as? ProviderCardButton)?.provider }
            button.layer?.zPosition = 20
        case .ended, .cancelled, .failed:
            endProviderDrag()
        default:
            break
        }
    }

    private func beginCardDrag(for button: ProviderCardButton) {
        guard let row = button.superview as? NSStackView else { return }
        let cards = row.arrangedSubviews.compactMap { $0 as? ProviderCardButton }
        guard cards.count > 1, cards.contains(button) else { return }
        let pitch = cards[1].frame.midX - cards[0].frame.midX
        dragGrid = DragGrid(
            firstCenter: cards[0].frame.midX,
            pitch: pitch != 0 ? pitch : button.frame.width,
            startCenter: button.frame.midX,
            count: cards.count
        )
        startJiggle(cards: cards, lifted: button)
    }

    private func endProviderDrag() {
        guard draggingProvider != nil else { return }
        let provider = draggingProvider
        draggingProvider = nil
        dragGrid = nil
        if let row = cardRow {
            stopJiggle(cards: row.arrangedSubviews.compactMap { $0 as? ProviderCardButton })
        }
        expandedProvider = nil
        updateViews()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            if self?.suppressNextTapProvider == provider {
                self?.suppressNextTapProvider = nil
            }
        }
    }

    /// iPhone-style wobble. Every card except the lifted one rotates back and
    /// forth with a small per-card phase offset so they fall out of sync; the
    /// lifted card gets a steady "picked up" pop instead.
    private func startJiggle(cards: [ProviderCardButton], lifted: ProviderCardButton) {
        for (index, card) in cards.enumerated() {
            card.wantsLayer = true
            guard let layer = card.layer else { continue }
            layer.removeAnimation(forKey: "jiggle")
            layer.removeAnimation(forKey: "lift")
            if card === lifted {
                layer.zPosition = 20
                let pop = CABasicAnimation(keyPath: "transform.scale")
                pop.fromValue = 1.0
                pop.toValue = 1.08
                pop.duration = 0.16
                pop.timingFunction = CAMediaTimingFunction(name: .easeOut)
                pop.fillMode = .forwards
                pop.isRemovedOnCompletion = false
                layer.add(pop, forKey: "lift")
                continue
            }
            layer.zPosition = 0
            let amplitude = 0.032
            let wobble = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            wobble.values = [-amplitude, amplitude, -amplitude]
            wobble.keyTimes = [0, 0.5, 1]
            wobble.duration = 0.17 + Double(index % 3) * 0.013
            wobble.repeatCount = .infinity
            wobble.timeOffset = Double(index) * 0.04
            wobble.isRemovedOnCompletion = false
            layer.add(wobble, forKey: "jiggle")
        }
    }

    private func stopJiggle(cards: [ProviderCardButton]) {
        for card in cards {
            card.layer?.removeAnimation(forKey: "jiggle")
            card.layer?.removeAnimation(forKey: "lift")
            card.layer?.zPosition = 0
            card.layer?.transform = CATransform3DIdentity
        }
    }

    @objc private func configureOpenRouterKey() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "OpenRouter API Key"
        alert.informativeText = "Use a Management API key so the credits endpoint can return total usage."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        input.placeholderString = "sk-or-v1-..."
        if SecretStore.read(
            service: OpenRouterUsageCollector.keychainService,
            account: OpenRouterUsageCollector.keychainAccount
        ) != nil {
            input.placeholderString = "Saved. Paste a new key to replace it."
        }
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let key = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try SecretStore.write(
                service: OpenRouterUsageCollector.keychainService,
                account: OpenRouterUsageCollector.keychainAccount,
                value: key
            )
            refresh()
        } catch {
            showError(message: error.localizedDescription)
        }
    }

    @objc private func openOpenRouterKeysPage() {
        NSWorkspace.shared.open(URL(string: "https://openrouter.ai/settings/keys")!)
    }

    @objc private func clearOpenRouterKey() {
        SecretStore.delete(
            service: OpenRouterUsageCollector.keychainService,
            account: OpenRouterUsageCollector.keychainAccount
        )
        refresh()
    }

    private func showError(message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "TokenBar"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

@MainActor
final class ProviderCardButton: NSButton {
    let provider: Provider

    init(provider: Provider, target: AnyObject?, action: Selector?) {
        self.provider = provider
        super.init(frame: .zero)
        self.target = target
        self.action = action
        title = ""
        isBordered = false
        isTransparent = true
        focusRingType = .none
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

@MainActor
final class ProviderUsageView: NSView {
    enum Mode {
        case single
        case regular
        case medium
        case compact
        case expanded
        case collapsed

        init(provider: Provider, visibleCount: Int, expandedProvider: Provider?) {
            if let expandedProvider {
                self = expandedProvider == provider ? .expanded : .collapsed
            } else {
                self = switch visibleCount {
                case 1: .single
                case 2: .regular
                case 3: .medium
                default: .compact
                }
            }
        }

        var width: CGFloat {
            switch self {
            case .single: 420
            case .regular: 272
            case .medium: 188
            case .compact: 132
            case .expanded: 272
            case .collapsed: 86
            }
        }

        var cardBackgroundColor: NSColor {
            switch self {
            case .expanded: NSColor(calibratedWhite: 0.12, alpha: 0.96)
            default: NSColor(calibratedWhite: 0.08, alpha: 0.92)
            }
        }
    }

    private let snapshot: UsageSnapshot
    private let mode: Mode

    init(snapshot: UsageSnapshot, mode: Mode = .regular) {
        self.snapshot = snapshot
        self.mode = mode
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.backgroundColor = mode.cardBackgroundColor.cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let icon = ProviderIcon.image(for: snapshot.provider)
        let iconAlpha: CGFloat = snapshot.error == nil ? 1 : 0.45
        let iconRect: NSRect = switch mode {
        case .medium:
            NSRect(x: 3, y: 3, width: 24, height: 24)
        case .compact, .collapsed: NSRect(x: 3, y: 4, width: 22, height: 22)
        case .single, .regular, .expanded: NSRect(x: 3, y: 2, width: 26, height: 26)
        }
        icon.draw(
            in: iconRect,
            from: .zero,
            operation: .sourceOver,
            fraction: iconAlpha
        )

        if let error = snapshot.error, snapshot.primary == nil && snapshot.secondary == nil {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .regular),
                .foregroundColor: NSColor.systemOrange
            ]
            (error as NSString).draw(at: NSPoint(x: 34, y: 9), withAttributes: attrs)
            return
        }

        if snapshot.provider == .openrouter {
            drawAmountOnly()
            return
        }

        switch mode {
        case .compact:
            drawDenseWindow(
                label: snapshot.provider.primaryWindowLabel,
                window: snapshot.primary,
                y: 15,
                labelX: 29,
                barX: snapshot.provider == .cursor ? 63 : 55,
                barWidth: snapshot.provider == .cursor ? 27 : 34,
                segmentCount: 5,
                fontSize: 8
            )
            if let secondaryLabel = snapshot.provider.secondaryWindowLabel {
                drawDenseWindow(
                    label: secondaryLabel,
                    window: snapshot.secondary,
                    y: 3,
                    labelX: 29,
                    barX: snapshot.provider == .cursor ? 63 : 55,
                    barWidth: snapshot.provider == .cursor ? 27 : 34,
                    segmentCount: 5,
                    fontSize: 8
                )
            }
        case .medium:
            drawDenseWindow(
                label: snapshot.provider.primaryWindowLabel,
                window: snapshot.primary,
                y: 15,
                labelX: 31,
                barX: snapshot.provider == .cursor ? 65 : 58,
                barWidth: snapshot.provider == .cursor ? 67 : 74,
                segmentCount: 5,
                fontSize: 8.5
            )
            if let secondaryLabel = snapshot.provider.secondaryWindowLabel {
                drawDenseWindow(
                    label: secondaryLabel,
                    window: snapshot.secondary,
                    y: 3,
                    labelX: 31,
                    barX: snapshot.provider == .cursor ? 65 : 58,
                    barWidth: snapshot.provider == .cursor ? 67 : 74,
                    segmentCount: 5,
                    fontSize: 8.5
                )
            }
        case .collapsed:
            drawCollapsed()
        case .expanded:
            drawExpanded()
        case .single:
            drawSingle()
        case .regular:
            if let secondaryLabel = snapshot.provider.secondaryWindowLabel {
                let column = windowLabelColumnWidth(snapshot.provider.primaryWindowLabel, secondaryLabel)
                drawWindow(label: snapshot.provider.primaryWindowLabel, window: snapshot.primary, y: 15, labelColumnWidth: column)
                drawWindow(label: secondaryLabel, window: snapshot.secondary, y: 3, labelColumnWidth: column)
            } else {
                let column = windowLabelColumnWidth(snapshot.provider.primaryWindowLabel)
                drawWindow(label: snapshot.provider.primaryWindowLabel, window: snapshot.primary, y: 9, labelColumnWidth: column)
            }
        }
    }

    private func drawAmountOnly() {
        let value = UsageFormat.windowValue(snapshot.primary) as NSString
        switch mode {
        case .compact, .collapsed:
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 7.5, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            let valueAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
            ("OR" as NSString).draw(at: NSPoint(x: 30, y: 15), withAttributes: labelAttrs)
            value.draw(at: NSPoint(x: 30, y: 4), withAttributes: valueAttrs)
        case .medium:
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            let valueAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
            ("Spent" as NSString).draw(at: NSPoint(x: 34, y: 15), withAttributes: labelAttrs)
            let valueSize = value.size(withAttributes: valueAttrs)
            value.draw(at: NSPoint(x: bounds.width - 8 - valueSize.width, y: 7), withAttributes: valueAttrs)
        case .single, .regular, .expanded:
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8.5, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
            let metaAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            let valueAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
            (snapshot.provider.rawValue as NSString).draw(at: NSPoint(x: 34, y: 15), withAttributes: titleAttrs)
            ("Spent" as NSString).draw(at: NSPoint(x: 34, y: 4), withAttributes: metaAttrs)
            let valueSize = value.size(withAttributes: valueAttrs)
            value.draw(at: NSPoint(x: bounds.width - 8 - valueSize.width, y: 8), withAttributes: valueAttrs)
        }
    }

    private func drawSingle() {
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        (snapshot.provider.rawValue as NSString).draw(at: NSPoint(x: 34, y: 10), withAttributes: nameAttrs)

        let startX: CGFloat = 94
        let barWidth = max(120, bounds.width - 194)
        if let secondaryLabel = snapshot.provider.secondaryWindowLabel {
            let column = windowLabelColumnWidth(snapshot.provider.primaryWindowLabel, secondaryLabel)
            drawWindow(label: snapshot.provider.primaryWindowLabel, window: snapshot.primary, y: 15, startX: startX, barWidth: barWidth, labelColumnWidth: column)
            drawWindow(label: secondaryLabel, window: snapshot.secondary, y: 3, startX: startX, barWidth: barWidth, labelColumnWidth: column)
        } else {
            let column = windowLabelColumnWidth(snapshot.provider.primaryWindowLabel)
            drawWindow(label: snapshot.provider.primaryWindowLabel, window: snapshot.primary, y: 9, startX: startX, barWidth: barWidth, labelColumnWidth: column)
        }
    }

    private func drawExpanded() {
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8.5, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let metaAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 7.5, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let name = snapshot.provider.rawValue
        let meta = snapshot.plan?.isEmpty == false ? snapshot.plan! : "LIVE"

        // The name column grows to fit the longest header line but is capped so the
        // bars and the percent/reset columns always have room. Text is truncated to
        // the column width as a hard guard against ever overlapping the windows.
        let labelX: CGFloat = 34
        let measured = max(
            (name as NSString).size(withAttributes: nameAttrs).width,
            (meta as NSString).size(withAttributes: metaAttrs).width
        )
        let nameColumnWidth = min(96, max(34, ceil(measured)))

        let nameFont = nameAttrs[.font] as? NSFont ?? .systemFont(ofSize: 8.5, weight: .semibold)
        let metaFont = metaAttrs[.font] as? NSFont ?? .monospacedDigitSystemFont(ofSize: 7.5, weight: .medium)
        (Self.truncate(name, font: nameFont, maxWidth: nameColumnWidth) as NSString)
            .draw(at: NSPoint(x: labelX, y: 15), withAttributes: nameAttrs)
        (Self.truncate(meta, font: metaFont, maxWidth: nameColumnWidth) as NSString)
            .draw(at: NSPoint(x: labelX, y: 4), withAttributes: metaAttrs)

        let startX = labelX + nameColumnWidth + 6
        // Reserve the right edge for the right-aligned percent + reset columns.
        let barWidth = max(30, bounds.width - 104 - startX)

        // Expanded Cursor drills into the Auto + API breakdown; the combined
        // "All" headline is what the collapsed/compact states show instead.
        if snapshot.provider == .cursor, let auto = snapshot.tertiary {
            let column = windowLabelColumnWidth("Auto", "API")
            drawWindow(label: "Auto", window: auto, y: 15, startX: startX, barWidth: barWidth, labelColumnWidth: column)
            drawWindow(label: "API", window: snapshot.secondary, y: 3, startX: startX, barWidth: barWidth, labelColumnWidth: column)
            return
        }

        if let secondaryLabel = snapshot.provider.secondaryWindowLabel {
            let column = windowLabelColumnWidth(snapshot.provider.primaryWindowLabel, secondaryLabel)
            drawWindow(label: snapshot.provider.primaryWindowLabel, window: snapshot.primary, y: 15, startX: startX, barWidth: barWidth, labelColumnWidth: column)
            drawWindow(label: secondaryLabel, window: snapshot.secondary, y: 3, startX: startX, barWidth: barWidth, labelColumnWidth: column)
        } else {
            let column = windowLabelColumnWidth(snapshot.provider.primaryWindowLabel)
            drawWindow(label: snapshot.provider.primaryWindowLabel, window: snapshot.primary, y: 9, startX: startX, barWidth: barWidth, labelColumnWidth: column)
        }
    }

    private static func truncate(_ string: String, font: NSFont, maxWidth: CGFloat) -> String {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        if (string as NSString).size(withAttributes: attrs).width <= maxWidth {
            return string
        }
        var result = string
        while !result.isEmpty {
            result.removeLast()
            let candidate = result + "…"
            if (candidate as NSString).size(withAttributes: attrs).width <= maxWidth {
                return candidate
            }
        }
        return "…"
    }

    private func drawCollapsed() {
        let remaining = snapshot.primary?.remainingPercent
        let value = UsageFormat.windowValue(snapshot.primary)
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 7.5, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let percentAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .semibold),
            .foregroundColor: remaining.map(UsageFormat.remainingColor) ?? NSColor.secondaryLabelColor
        ]
        (snapshot.provider.shortName as NSString).draw(at: NSPoint(x: 30, y: 15), withAttributes: labelAttrs)
        (value as NSString).draw(at: NSPoint(x: 30, y: 4), withAttributes: percentAttrs)
    }

    private func drawDenseWindow(
        label: String,
        window: LimitWindow?,
        y: CGFloat,
        labelX: CGFloat,
        barX: CGFloat,
        barWidth: CGFloat,
        segmentCount: Int,
        fontSize: CGFloat
    ) {
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 7.5, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        (label as NSString).draw(at: NSPoint(x: labelX, y: y - 1), withAttributes: labelAttrs)

        let remaining = window?.remainingPercent
        drawSegmentedBar(
            rect: NSRect(x: barX, y: y + 1, width: barWidth, height: 6),
            remaining: remaining,
            accent: snapshot.provider.accent,
            segmentCount: segmentCount
        )

        let percentAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: remaining.map(UsageFormat.remainingColor) ?? NSColor.secondaryLabelColor
        ]
        let percent = UsageFormat.windowValue(window) as NSString
        let size = percent.size(withAttributes: percentAttrs)
        percent.draw(at: NSPoint(x: bounds.width - 6 - size.width, y: y - 1), withAttributes: percentAttrs)
    }

    /// Shared label-column width for a card's window rows. Computing it from the
    /// widest label (not each row's own label) keeps both bars starting at the
    /// same x so the two progress rows line up. Returns 0 when no labels.
    private func windowLabelColumnWidth(_ labels: String?...) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .medium)
        let widths = labels
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) }
        guard let maxWidth = widths.max() else { return 0 }
        return max(CGFloat(18), min(CGFloat(34), maxWidth + 5))
    }

    private func drawWindow(
        label: String,
        window: LimitWindow?,
        y: CGFloat,
        startX: CGFloat = 34,
        barWidth: CGFloat = 142,
        labelColumnWidth: CGFloat
    ) {
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        if !label.isEmpty {
            (label as NSString).draw(at: NSPoint(x: startX, y: y - 1), withAttributes: labelAttrs)
        }
        let adjustedBarWidth = max(CGFloat(28), barWidth - max(0, labelColumnWidth - 18))

        let remaining = window?.remainingPercent
        drawSegmentedBar(
            rect: NSRect(x: startX + labelColumnWidth, y: y + 1, width: adjustedBarWidth, height: 6),
            remaining: remaining,
            accent: snapshot.provider.accent
        )

        let font = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .semibold)
        let resetAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let percentAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: remaining.map(UsageFormat.remainingColor) ?? NSColor.secondaryLabelColor
        ]

        // Two fixed right-aligned columns so both rows line up.
        let resetColumnRight = bounds.width - 7
        let percentColumnRight = resetColumnRight - 42

        let reset = UsageFormat.reset(window?.resetAt) as NSString
        let percent = UsageFormat.windowValue(window) as NSString
        let resetSize = reset.size(withAttributes: resetAttrs)
        let percentSize = percent.size(withAttributes: percentAttrs)
        reset.draw(
            at: NSPoint(x: resetColumnRight - resetSize.width, y: y - 1),
            withAttributes: resetAttrs
        )
        percent.draw(
            at: NSPoint(x: percentColumnRight - percentSize.width, y: y - 1),
            withAttributes: percentAttrs
        )
    }

    private func drawSegmentedBar(rect: NSRect, remaining: Double?, accent: NSColor, segmentCount: Int? = nil) {
        let segments = segmentCount ?? max(4, Int(rect.width / 12))
        let gap: CGFloat = 1
        let width = (rect.width - CGFloat(segments - 1) * gap) / CGFloat(segments)
        let filled = Int(((remaining ?? 0) / 100 * Double(segments)).rounded(.down))
        // Brand color while healthy; switch to warning colors as the limit nears.
        let color: NSColor = switch remaining {
        case .some(let value) where value < 40: UsageFormat.remainingColor(value)
        case .some: accent
        case nil: NSColor.systemGray
        }

        for index in 0..<segments {
            let segmentRect = NSRect(
                x: rect.minX + CGFloat(index) * (width + gap),
                y: rect.minY,
                width: width,
                height: rect.height
            )
            let path = NSBezierPath(roundedRect: segmentRect, xRadius: 1.5, yRadius: 1.5)
            if index < filled {
                color.setFill()
            } else {
                accent.withAlphaComponent(0.18).setFill()
            }
            path.fill()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: TouchBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = UsageStore(collectors: [
            CodexAppServerCollector(),
            ClaudeUsageCollector(),
            GeminiUsageCollector(),
            CursorUsageCollector(),
            AntigravityUsageCollector(),
            OpenRouterUsageCollector(),
            WorkBuddyUsageCollector()
        ])
        controller = TouchBarController(store: store)
        controller?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@MainActor
private func renderSampleCards(to directory: String) {
    let fm = FileManager.default
    try? fm.createDirectory(atPath: directory, withIntermediateDirectories: true)

    func window(_ used: Double, reset: TimeInterval?, value: String? = nil) -> LimitWindow {
        LimitWindow(usedPercent: used, resetAt: reset.map { Date().addingTimeInterval($0) }, valueText: value)
    }

    let cases: [(String, UsageSnapshot, ProviderUsageView.Mode)] = [
        ("antigravity_expanded",
         UsageSnapshot(provider: .antigravity, primary: window(18, reset: 3600 * 4 + 120),
                       secondary: window(63, reset: 3600 * 9), plan: nil, updatedAt: Date(), error: nil),
         .expanded),
        ("antigravity_compact",
         UsageSnapshot(provider: .antigravity, primary: window(18, reset: 3600 * 4),
                       secondary: window(63, reset: 3600 * 9), plan: "Gemini 3 Pro", updatedAt: Date(), error: nil),
         .compact),
        ("antigravity_collapsed",
         UsageSnapshot(provider: .antigravity, primary: window(18, reset: 3600 * 4),
                       secondary: window(63, reset: 3600 * 9), plan: "Gemini 3 Pro", updatedAt: Date(), error: nil),
         .collapsed),
        ("workbuddy_regular",
         UsageSnapshot(provider: .workbuddy, primary: window(42, reset: 3600 * 24 * 6, value: "1.2k"),
                       secondary: nil, plan: "1.2k/5.0k", updatedAt: Date(), error: nil),
         .regular),
        ("workbuddy_expanded",
         UsageSnapshot(provider: .workbuddy, primary: window(42, reset: 3600 * 24 * 6, value: "1.2k"),
                       secondary: nil, plan: "1.2k/5.0k", updatedAt: Date(), error: nil),
         .expanded),
        ("workbuddy_compact",
         UsageSnapshot(provider: .workbuddy, primary: window(42, reset: 3600 * 24 * 6, value: "1.2k"),
                       secondary: nil, plan: "1.2k/5.0k", updatedAt: Date(), error: nil),
         .compact),
        ("codex_expanded",
         UsageSnapshot(provider: .codex, primary: window(35, reset: 3600 * 3 + 600),
                       secondary: window(70, reset: 3600 * 24 * 5), plan: "PLUS", updatedAt: Date(), error: nil),
         .expanded),
        ("gemini_expanded",
         UsageSnapshot(provider: .gemini, primary: window(12, reset: 3600 * 3),
                       secondary: window(44, reset: 3600 * 24 * 4), plan: "PRO", updatedAt: Date(), error: nil),
         .expanded),
        ("gemini_compact",
         UsageSnapshot(provider: .gemini, primary: window(12, reset: 3600 * 3),
                       secondary: window(44, reset: 3600 * 24 * 4), plan: "PRO", updatedAt: Date(), error: nil),
         .compact),
        ("cursor_regular",
         UsageSnapshot(provider: .cursor, primary: window(11, reset: 3600 * 24 * 1),
                       secondary: window(46, reset: 3600 * 24 * 1), plan: "PRO", updatedAt: Date(), error: nil),
         .regular),
        ("cursor_expanded",
         UsageSnapshot(provider: .cursor, primary: window(11, reset: 3600 * 24 * 1),
                       secondary: window(46, reset: 3600 * 24 * 1), tertiary: window(1, reset: 3600 * 24 * 1),
                       plan: "PRO", updatedAt: Date(), error: nil),
         .expanded),
        ("cursor_compact",
         UsageSnapshot(provider: .cursor, primary: window(11, reset: 3600 * 24 * 1),
                       secondary: window(46, reset: 3600 * 24 * 1), plan: "PRO", updatedAt: Date(), error: nil),
         .compact),
        ("claude_expanded",
         UsageSnapshot(provider: .claude, primary: window(22, reset: 3600 * 2),
                       secondary: window(58, reset: 3600 * 24 * 3), plan: "MAX", updatedAt: Date(), error: nil),
         .expanded)
    ]

    let scale: CGFloat = 4
    for (name, snapshot, mode) in cases {
        let card = ProviderUsageView(snapshot: snapshot, mode: mode)
        let size = NSSize(width: mode.width, height: 30)
        card.frame = NSRect(origin: .zero, size: size)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { continue }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = ctx
        NSAppearance.current = NSAppearance(named: .darkAqua)
        NSColor(calibratedWhite: 0.05, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        let cardBg = mode.cardBackgroundColor
        cardBg.setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 5, yRadius: 5).fill()
        card.draw(card.bounds)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
            try? data.write(to: url)
            FileHandle.standardError.write(Data("rendered \(url.path)\n".utf8))
        }
    }
}

if let index = CommandLine.arguments.firstIndex(of: "--render-cards") {
    let directory = CommandLine.arguments.indices.contains(index + 1)
        ? CommandLine.arguments[index + 1]
        : FileManager.default.currentDirectoryPath + "/card-preview"
    NSApplication.shared.setActivationPolicy(.prohibited)
    MainActor.assumeIsolated {
        renderSampleCards(to: directory)
    }
    exit(0)
}

if CommandLine.arguments.contains("--print-gemini-usage") {
    let semaphore = DispatchSemaphore(value: 0)
    let box = SnapshotBox()
    Task.detached {
        box.snapshot = await GeminiUsageCollector().collect()
        semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + 20) == .success else {
        FileHandle.standardError.write(Data("Gemini usage diagnostic timed out\n".utf8))
        exit(124)
    }
    if let snapshot = box.snapshot {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(snapshot),
           let json = String(data: data, encoding: .utf8) {
            print(json)
        }
    }
    exit(box.snapshot?.error == nil ? 0 : 1)
}

guard let singleInstanceLock = SingleInstanceLock.acquire(name: "local.tokenbar") else {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
