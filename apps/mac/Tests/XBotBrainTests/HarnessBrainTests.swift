import Foundation
import Testing
@testable import XBotBrain

/// A stand-in CLI. `body` is a shell script; `$OUT` is a folder it can write evidence into.
func fakeCLI(_ body: String) throws -> (url: URL, out: URL) {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let script = dir.appending(path: "cli")
    try "#!/bin/sh\nOUT='\(dir.path)'\n\(body)\n".write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    return (script, dir)
}

func collect(_ stream: AsyncStream<BrainEvent>) async -> [BrainEvent] {
    var events: [BrainEvent] = []
    for await event in stream { events.append(event) }
    return events
}

@Suite struct HarnessBrainTests {
    let tmp = URL(filePath: NSTemporaryDirectory())

    @Test func streamsEventsInOrderAndEndsOnce() async throws {
        let cli = try fakeCLI("""
        cat > /dev/null
        echo '{"type":"system","subtype":"init","session_id":"s1"}'
        echo 'a banner that is not json'
        echo '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"hi"}},"parent_tool_use_id":null}'
        echo '{"type":"result","subtype":"success","is_error":false}'
        echo '{"type":"result","subtype":"success","is_error":false}'
        """)
        let brain = HarnessBrain(kind: .claude, executable: cli.url, environment: [:])
        let events = await collect(brain.run(TurnRequest(prompt: "hello", directory: tmp, mode: .readOnly)))
        #expect(events == [.session("s1"), .textDelta("hi"), .done])
    }

    @Test func promptTravelsOnStdinEvenWhenItLooksLikeAFlag() async throws {
        let cli = try fakeCLI("""
        cat > "$OUT/stdin"
        printf '%s\\n' "$@" > "$OUT/args"
        echo '{"type":"result","subtype":"success","is_error":false}'
        """)
        let prompt = "--dangerously-skip-permissions " + String(repeating: "long ", count: 50_000)
        let brain = HarnessBrain(kind: .claude, executable: cli.url, environment: [:])
        _ = await collect(brain.run(TurnRequest(prompt: prompt, directory: tmp, mode: .readOnly)))
        #expect(try String(contentsOf: cli.out.appending(path: "stdin"), encoding: .utf8) == prompt)
        #expect(try !String(contentsOf: cli.out.appending(path: "args"), encoding: .utf8).contains("dangerously"))
    }

    @Test func exitWithoutAResultIsAFailure() async throws {
        let cli = try fakeCLI("cat > /dev/null; echo 'not logged in' >&2; exit 3")
        let brain = HarnessBrain(kind: .claude, executable: cli.url, environment: [:])
        let events = await collect(brain.run(TurnRequest(prompt: "x", directory: tmp, mode: .readOnly)))
        #expect(events.count == 1)
        guard case .failed(let reason) = events.first else { Issue.record("expected failure"); return }
        #expect(reason.contains("not logged in"))
    }

    /// Writing to a pipe nobody reads raises SIGPIPE, whose default action ends the whole app. A CLI
    /// that dies on startup without reading its prompt must cost a failed turn, not xBot.
    @Test func aCLIThatNeverReadsItsPromptDoesNotTakeTheAppDown() async throws {
        let cli = try fakeCLI("echo 'unknown option' >&2; exit 2")
        let brain = HarnessBrain(kind: .claude, executable: cli.url, environment: [:])
        let prompt = String(repeating: "x", count: 1_000_000)
        let events = await collect(brain.run(TurnRequest(prompt: prompt, directory: tmp, mode: .readOnly)))
        guard case .failed(let reason) = events.last else { Issue.record("expected failure"); return }
        #expect(reason.contains("unknown option"))
    }

    /// JSON may carry U+2028 and U+2029 raw inside a string (Node's JSON.stringify and serde both
    /// do), and Foundation's line splitter breaks lines at them. Only "\n" ends a JSON line.
    @Test func lineSeparatorsInsideJSONDoNotSplitTheLine() async throws {
        let cli = try fakeCLI("""
        cat > /dev/null
        printf '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"a\\342\\200\\250b"}},"parent_tool_use_id":null}\\n'
        echo '{"type":"result","subtype":"success","is_error":false}'
        """)
        let brain = HarnessBrain(kind: .claude, executable: cli.url, environment: [:])
        let events = await collect(brain.run(TurnRequest(prompt: "x", directory: tmp, mode: .readOnly)))
        #expect(events == [.textDelta("a\u{2028}b"), .done])
    }

    @Test func aLastLineWithoutANewlineStillCounts() async throws {
        let cli = try fakeCLI("""
        cat > /dev/null
        printf '{"type":"result","subtype":"success","is_error":false}'
        """)
        let brain = HarnessBrain(kind: .claude, executable: cli.url, environment: [:])
        #expect(await collect(brain.run(TurnRequest(prompt: "x", directory: tmp, mode: .readOnly))) == [.done])
    }

    /// Codex reads its schema from a file. The file holds the schema while the turn runs and is gone
    /// afterwards.
    @Test func codexGetsTheSchemaInAFileThatIsRemovedAfterwards() async throws {
        let cli = try fakeCLI("""
        cat > /dev/null
        while [ $# -gt 0 ]; do
          if [ "$1" = "--output-schema" ]; then cat "$2" > "$OUT/schema"; echo "$2" > "$OUT/path"; fi
          shift
        done
        echo '{"type":"turn.completed"}'
        """)
        let brain = HarnessBrain(kind: .codex, executable: cli.url, environment: [:])
        let request = TurnRequest(prompt: "x", directory: tmp, mode: .readOnly, schema: #"{"type":"object"}"#)
        #expect(await collect(brain.run(request)) == [.done])
        #expect(try String(contentsOf: cli.out.appending(path: "schema"), encoding: .utf8) == #"{"type":"object"}"#)
        let path = try String(contentsOf: cli.out.appending(path: "path"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func missingFolderFailsWithoutSpawning() async throws {
        let cli = try fakeCLI("touch \"$OUT/ran\"")
        let gone = tmp.appending(path: "xbot-missing-\(UUID().uuidString)")
        let brain = HarnessBrain(kind: .claude, executable: cli.url, environment: [:])
        let events = await collect(brain.run(TurnRequest(prompt: "x", directory: gone, mode: .readOnly)))
        guard case .failed(let reason) = events.first else { Issue.record("expected failure"); return }
        #expect(reason.contains(gone.path))
        #expect(!FileManager.default.fileExists(atPath: cli.out.appending(path: "ran").path))
    }

    @Test func runsInTheRequestedFolderWithTheGivenEnvironment() async throws {
        let cli = try fakeCLI("""
        cat > /dev/null
        pwd -P > "$OUT/pwd"; echo "$XBOT_MARK" > "$OUT/env"
        echo '{"type":"result","subtype":"success","is_error":false}'
        """)
        let folder = tmp.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let brain = HarnessBrain(kind: .claude, executable: cli.url, environment: ["XBOT_MARK": "yes"])
        _ = await collect(brain.run(TurnRequest(prompt: "x", directory: folder, mode: .readOnly)))
        let pwd = try String(contentsOf: cli.out.appending(path: "pwd"), encoding: .utf8)
        // `pwd -P` says /private/var/…; Foundation's own resolving drops the /private, so compare the tail.
        #expect(pwd.trimmingCharacters(in: .newlines).hasSuffix(folder.path))
        #expect(try String(contentsOf: cli.out.appending(path: "env"), encoding: .utf8) == "yes\n")
    }

    @Test func cancellingStopsTheProcess() async throws {
        let cli = try fakeCLI("""
        cat > /dev/null
        echo $$ > "$OUT/pid"
        echo '{"type":"system","subtype":"init","session_id":"s"}'
        while true; do sleep 0.05; done
        """)
        let brain = HarnessBrain(kind: .claude, executable: cli.url, environment: [:])
        let task = Task { await collect(brain.run(TurnRequest(prompt: "x", directory: tmp, mode: .readOnly))) }
        defer { task.cancel() }
        let pidFile = cli.out.appending(path: "pid")
        for _ in 0..<200 where !FileManager.default.fileExists(atPath: pidFile.path) {
            try await Task.sleep(for: .milliseconds(25))
        }
        let pid = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(kill(pid, 0) == 0)
        task.cancel()
        _ = await task.value
        for _ in 0..<80 where kill(pid, 0) == 0 {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(kill(pid, 0) != 0)
    }
}
