import Testing

@testable import XBotRuntime

/// The test the spec asks for by name: it fails if a known secret shape survives redaction.
///
/// "Do not rely on care." Diagnostics leave the machine — that is the entire point of the button —
/// so this is the one place in the app where a regression is not a bug report, it is a disclosure.
/// Each case here is a real shape that has appeared in a log somewhere.
struct RedactionTests {
    /// Every one of these must be gone. Add a row whenever a new secret shape enters the codebase.
    ///
    /// `mustNotSurvive` is the sensitive substring itself, carried per row. An earlier version of
    /// this test asserted the same hardcoded strings for every case, which meant nine of the ten
    /// rows asserted nothing at all — it would have passed while leaking.
    static let secrets: [(name: String, text: String, mustNotSurvive: String)] = [
        (
            "anthropic key",
            "ANTHROPIC_API_KEY=sk-ant-api03-AbCdEfGhIjKlMnOpQrStUvWxYz0123456789",
            "sk-ant-api03-AbCdEfGhIjKlMnOpQrStUvWxYz0123456789"
        ),
        (
            "openai key",
            "using sk-proj0123456789abcdefghijklmnop for the call",
            "sk-proj0123456789abcdefghijklmnop"
        ),
        ("xai key", "xai-abcdefghijklmnop0123456789", "xai-abcdefghijklmnop0123456789"),
        (
            "google key",
            "AIzaSyA1B2C3D4E5F6G7H8I9J0KlMnOpQrStUv",
            "AIzaSyA1B2C3D4E5F6G7H8I9J0KlMnOpQrStUv"
        ),
        (
            "github token",
            "ghp_0123456789abcdefghijklmnopqrstuvwx",
            "ghp_0123456789abcdefghijklmnopqrstuvwx"
        ),
        (
            "bearer jwt",
            "authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.dBjftJeZ4CVPmB92K27uhbUJU1p1r",
            "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.dBjftJeZ4CVPmB92K27uhbUJU1p1r"
        ),
        (
            "database url password",
            "DATABASE_URL=postgres://openbot:hunter2@127.0.0.1:5432/openbot",
            "hunter2"
        ),
        (
            "encryption key",
            "KEY_ENCRYPTION_KEY=Zm9vYmFyYmF6cXV4MDEyMzQ1Njc4OWFiY2RlZmdoaWo=",
            "Zm9vYmFyYmF6cXV4MDEyMzQ1Njc4OWFiY2RlZmdoaWo="
        ),
        ("computer token", "COMPUTER_TOKEN: 8f2c41aa9be34d17b0c5", "8f2c41aa9be34d17b0c5"),
        (
            "license token",
            "COPILOTKIT_LICENSE_TOKEN=ck_live_9f8e7d6c5b4a39281706",
            "ck_live_9f8e7d6c5b4a39281706"
        ),
    ]

    @Test(arguments: secrets)
    func aKnownSecretNeverSurvives(secret: (name: String, text: String, mustNotSurvive: String)) {
        let scrubbed = Redaction.scrub(secret.text)

        #expect(
            !scrubbed.contains(secret.mustNotSurvive),
            "\(secret.name) survived redaction: \(scrubbed)"
        )
        // And something was actually removed, so a function that returned its input unchanged
        // cannot pass by matching nothing.
        #expect(scrubbed.contains(Redaction.placeholder), "\(secret.name) was not redacted")
    }

    @Test func ordinaryDiagnosticsSurviveIntact() {
        // Redaction that eats the useful content is a different failure with the same outcome:
        // nobody can debug anything, so nobody sends diagnostics, so the button is decoration.
        let text = """
            xBot 1.0.0
            runtime Docker 27.0.0
            arm64 · macOS 15.0
            port 49152
            container running
            docker run -d --name xbot-engine
            """
        let scrubbed = Redaction.scrub(text)

        #expect(scrubbed.contains("xBot 1.0.0"))
        #expect(scrubbed.contains("Docker 27.0.0"))
        #expect(scrubbed.contains("port 49152"))
        #expect(scrubbed.contains("xbot-engine"))
    }

    @Test func environmentKeepsItsKeysAndLosesItsValues() {
        let environment = EngineEnvironment.compose(
            EngineEnvironment.Inputs(
                port: 49_152,
                keyEncryptionKey: "Zm9vYmFyYmF6cXV4MDEyMzQ1Njc4OWFiY2RlZmdoaWo=",
                hostGateway: "host.docker.internal",
                appOrigin: "xbot://app",
                intelligence: EngineEnvironment.Intelligence(
                    apiURL: "https://api.intelligence.copilotkit.ai",
                    gatewayWsURL: "wss://realtime.intelligence.copilotkit.ai",
                    apiKey: "sk-live-abcdefghijklmnopqrstuvwx",
                    licenseToken: "ck_live_9f8e7d6c5b4a39281706"
                ),
                engineToken: "engine-bearer-secret"
            )
        )
        let scrubbed = Redaction.scrub(environment: environment)

        // Which variables were set is useful. What they were set to never is.
        #expect(scrubbed["KEY_ENCRYPTION_KEY"] == Redaction.placeholder)
        #expect(scrubbed["INTELLIGENCE_API_KEY"] == Redaction.placeholder)
        #expect(scrubbed["COPILOTKIT_LICENSE_TOKEN"] == Redaction.placeholder)
        #expect(scrubbed["XBOT_ENGINE_TOKEN"] == Redaction.placeholder)
        #expect(scrubbed["PORT"] == "49152")
        #expect(scrubbed["OPENBOT_SINGLE_USER"] == "true")

        let rendered = scrubbed.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
        #expect(!rendered.contains("Zm9vYmFyYmF6cXV4MDEyMzQ1Njc4OWFiY2RlZmdoaWo="))
        #expect(!rendered.contains("ck_live_9f8e7d6c5b4a39281706"))
    }
}
