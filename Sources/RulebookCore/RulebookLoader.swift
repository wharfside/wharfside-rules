import Crypto
import Foundation

/// Loads rulebooks with mandatory signature verification for anything that
/// didn't ship inside the app bundle.
///
/// Trust model: the Ed25519 public key is pinned in the app binary. Rulebook
/// releases are signed offline (or in the rules repo's release CI) with the
/// private key. A downloaded document that fails verification is discarded
/// and the caller falls back to the bundled rulebook. Rule content is data
/// only — but prompt rules do reach the model's instructions, so an
/// attacker-controlled rulebook is a prompt-injection vector. That is why
/// verification is not optional on the download path.
public enum RulebookLoader {

    /// Loads the seed rulebook shipped as a package resource.
    public static func loadSeed() throws -> Rulebook {
        guard let url = Bundle.module.url(forResource: "Rulebook", withExtension: "json") else {
            throw RulebookError.malformedDocument
        }
        return try loadBundled(Data(contentsOf: url))
    }

    /// Bundled rulebooks are covered by the app's code signature and
    /// notarization; no separate signature needed.
    public static func loadBundled(_ data: Data) throws -> Rulebook {
        try JSONDecoder().decode(Rulebook.self, from: data)
    }

    /// Downloaded rulebooks: verify a detached Ed25519 signature over the
    /// exact document bytes before decoding.
    public static func loadVerified(
        document: Data,
        signature: Data,
        publicKey: Curve25519.Signing.PublicKey
    ) throws -> Rulebook {
        guard publicKey.isValidSignature(signature, for: document) else {
            throw RulebookError.invalidSignature
        }
        return try JSONDecoder().decode(Rulebook.self, from: document)
    }

    /// Semver-ish comparison sufficient for minAppVersion gating
    /// ("1.2.3" components compared numerically, missing components = 0).
    public static func appVersion(_ appVersion: String, satisfies minimum: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = parts(appVersion), m = parts(minimum)
        for i in 0..<max(a.count, m.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < m.count ? m[i] : 0
            if x != y { return x > y }
        }
        return true
    }
}
