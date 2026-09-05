import Foundation

/// Where Sparkle is allowed to take its appcast URL and its EdDSA public key from.
///
/// **The public key is the root of trust for updates.** docs/11-packaging-and-updates.md: an update
/// channel is a code-execution channel, and EdDSA verification is not optional. Sparkle will install
/// anything the configured key signs, so whoever controls the key controls what the app runs.
///
/// Both values are injected into the bundled `Info.plist` at build time by
/// `scripts/inject-sparkle-plist.sh`, which puts them inside the code-signed bundle where they
/// cannot be changed without breaking the signature. That is the only source a shipped build may
/// trust.
///
/// The controller also read both from the environment. That let anything able to influence the
/// app's launch environment supply its own feed *and its own key* — a signed update from an
/// attacker, accepted as genuine. The environment is honoured in debug builds only, where it is how
/// an appcast gets tested without a signed bundle.
public enum AppUpdateTrust: Sendable {
    /// Whether an environment-supplied appcast may be trusted at all.
    ///
    /// False in release. The check is on the build, not on the value, because no value from an
    /// untrusted source is safe here.
    public static var allowsEnvironmentOverride: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// Whether a feed URL is one Sparkle may be pointed at.
    ///
    /// HTTPS only. An appcast over plain HTTP can be rewritten in transit by anyone on the path,
    /// and while the EdDSA signature still has to check out, the feed also carries the version and
    /// the download URL — enough to stage a downgrade to a build with a known hole.
    public static func isAcceptableFeed(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(),
              let host = url.host, !host.isEmpty
        else { return false }
        return scheme == "https"
    }
}
