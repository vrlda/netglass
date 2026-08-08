import CryptoKit
import Foundation
import Security

/// One process's trust snapshot: signing, team, hash, origin flags.
public struct ProcessTrust: Equatable, Sendable {
    public let path: String
    public let signed: Bool
    public let teamID: String?
    public let authority: String?
    public let sha256: String
    public let isTemporary: Bool
    public let isDiskImage: Bool
    public let isSystemBinary: Bool
    public let changedSinceFirstSeen: Bool
    public let networkEntitlements: [String]

    public init(path: String, signed: Bool, teamID: String?, authority: String?,
                sha256: String, isTemporary: Bool, isDiskImage: Bool,
                isSystemBinary: Bool, changedSinceFirstSeen: Bool,
                networkEntitlements: [String]) {
        self.path = path
        self.signed = signed
        self.teamID = teamID
        self.authority = authority
        self.sha256 = sha256
        self.isTemporary = isTemporary
        self.isDiskImage = isDiskImage
        self.isSystemBinary = isSystemBinary
        self.changedSinceFirstSeen = changedSinceFirstSeen
        self.networkEntitlements = networkEntitlements
    }
}

/// Offline trust checks, run only when the inspector opens a flow (never per
/// tick). Notarization status is intentionally not checked: it requires an
/// online assessment and is unreliable offline.
public enum ProcessTrustInspector {
    private static let hashRegistryKey = "netglass.processHashes"
    private static let hashRegistryCap = 500

    public static func inspect(path: String) -> ProcessTrust {
        let hash = sha256(of: try? Data(contentsOf: URL(fileURLWithPath: path)))
        let signing = signingInfo(path: path)
        let entitlements = networkEntitlements(path: path)
        return ProcessTrust(
            path: path,
            signed: signing.signed,
            teamID: signing.teamID,
            authority: signing.authority,
            sha256: hash,
            isTemporary: isTemporary(path),
            isDiskImage: isDiskImage(path),
            isSystemBinary: isSystemBinary(path),
            changedSinceFirstSeen: noteHash(hash, for: path),
            networkEntitlements: entitlements)
    }

    public static func sha256(of data: Data?) -> String {
        guard let data else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// SecStaticCode offline signature check (no network, read-only).
    static func signingInfo(path: String) -> (signed: Bool, teamID: String?, authority: String?) {
        var staticCode: SecStaticCode?
        let url = URL(fileURLWithPath: path) as CFURL
        guard SecStaticCodeCreateWithPath(url, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return (false, nil, nil) }
        let signed = SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess
        guard signed else { return (signed, nil, nil) }
        var info: CFDictionary?
        let flags: SecCSFlags = [.init(rawValue: kSecCSSigningInformation)]
        guard SecCodeCopySigningInformation(code, flags, &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return (signed, nil, nil) }
        let teamID = dict[kSecCodeInfoTeamIdentifier as String] as? String
        var authority: String?
        if let certs = dict[kSecCodeInfoCertificates as String] as? [CFTypeRef] {
            authority = certs.lazy
                .filter { CFGetTypeID($0) == SecCertificateGetTypeID() }
                .map { unsafeDowncast($0, to: SecCertificate.self) }
                .compactMap { SecCertificateCopySubjectSummary($0) as String? }
                .first { $0.contains("Apple") }
        }
        return (signed, teamID, authority)
    }

    /// Network-related entitlements from the embedded signature (best-effort
    /// `codesign -d --entitlements` parse; subprocess runs only on inspector
    /// open, matching SnapshotService's drain-queue pattern).
    static func networkEntitlements(path: String) -> [String] {
        guard let output = runCodesignEntitlements(path: path) else { return [] }
        guard let data = output.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                  as? [String: Any] else { return [] }
        return plist.keys
            .filter { $0.hasPrefix("com.apple.security.network.") }
            .sorted()
    }

    private static func runCodesignEntitlements(path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-d", "--entitlements", ":-", path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        nonisolated(unsafe) var captured = Data()
        let queue = DispatchQueue(label: "netglass.codesign")
        let drain = DispatchGroup()
        drain.enter()
        queue.async {
            captured = output.fileHandleForReading.readDataToEndOfFile()
            drain.leave()
        }
        do {
            try process.run()
        } catch {
            output.fileHandleForWriting.closeFile()
            return nil
        }
        process.waitUntilExit()
        drain.wait()
        return String(data: captured, encoding: .utf8)
    }

    public static func isTemporary(_ path: String) -> Bool {
        path.hasPrefix(NSTemporaryDirectory()) || path.hasPrefix("/tmp/")
    }

    public static func isDiskImage(_ path: String) -> Bool {
        path.hasPrefix("/Volumes/")
    }

    public static func isSystemBinary(_ path: String) -> Bool {
        path.hasPrefix("/System/") || path.hasPrefix("/usr/bin/")
            || path.hasPrefix("/usr/sbin/") || path.hasPrefix("/bin/")
            || path.hasPrefix("/sbin/")
    }

    /// Records the hash and reports whether it differs from the first time
    /// this executable path was seen (registry persisted in UserDefaults).
    static func noteHash(_ hash: String, for path: String) -> Bool {
        guard !hash.isEmpty else { return false }
        let defaults = UserDefaults.standard
        var registry = defaults.dictionary(forKey: hashRegistryKey) as? [String: String] ?? [:]
        let changed = registry[path].map { $0 != hash } ?? false
        if registry[path] == nil {
            registry[path] = hash
            if registry.count > hashRegistryCap {
                let excess = registry.count - hashRegistryCap
                registry.keys.sorted().prefix(excess).forEach { registry.removeValue(forKey: $0) }
            }
            defaults.set(registry, forKey: hashRegistryKey)
        }
        return changed
    }
}
