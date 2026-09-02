import Testing

@testable import XBotEngine

/// The SSE wire format.
///
/// These are the cases that actually happen against a container that restarts: a half-written
/// event, a keep-alive comment mid-stream, CRLF framing, and a `data:` split across lines.
struct ServerSentEventParserTests {
    private func events(from lines: [String]) -> [ServerSentEvent] {
        var parser = ServerSentEventParser()
        return lines.compactMap { parser.consume($0) }
    }

    @Test func aBlankLineDispatches() {
        let result = events(from: ["event: message", "data: hello", ""])
        #expect(result == [ServerSentEvent(name: "message", data: "hello")])
    }

    @Test func aTruncatedEventIsNeverDispatched() {
        // The case upstream warns about: the endpoint is redeployed mid-answer. Half an event
        // must not reach the decoder, because half a JSON object decodes to nothing useful and
        // would surface as a parse error rather than as a dropped connection.
        let result = events(from: ["event: message", "data: {\"type\":\"TEXT_MES"])
        #expect(result.isEmpty)
    }

    @Test func keepAliveCommentsDoNotDisturbTheBuffer() {
        // A comment arriving between the data line and the blank line must not lose the data.
        let result = events(from: ["data: hello", ": keep-alive", ""])
        #expect(result == [ServerSentEvent(data: "hello")])
    }

    @Test func multipleDataLinesJoinWithNewlines() {
        let result = events(from: ["data: one", "data: two", ""])
        #expect(result == [ServerSentEvent(data: "one\ntwo")])
    }

    @Test func crlfFramingDoesNotLeakIntoTheData() {
        // A stray CR ends up inside the JSON and breaks decoding in a way that is very hard to
        // see in a log, because it prints identically.
        let result = events(from: ["data: hello\r", "\r"])
        #expect(result == [ServerSentEvent(data: "hello")])
    }

    @Test func aFieldWithNoColonIsAcceptedAsEmpty() {
        let result = events(from: ["data", "data: real", ""])
        #expect(result == [ServerSentEvent(data: "\nreal")])
    }

    @Test func twoEventsInSequenceDoNotBleedIntoEachOther() {
        let result = events(from: [
            "event: a", "data: first", "",
            "data: second", "",
        ])
        #expect(result.count == 2)
        #expect(result[0] == ServerSentEvent(name: "a", data: "first"))
        // The name from the first event must not carry over.
        #expect(result[1] == ServerSentEvent(name: nil, data: "second"))
    }

    @Test func aBlankLineWithNoDataDispatchesNothing() {
        #expect(events(from: ["", "", ""]).isEmpty)
    }
}

/// AG-UI's events, narrowed to what the conversation draws.
struct AGUIDecoderTests {
    private func decode(_ json: String) -> TurnEvent? {
        AGUIDecoder.decode(ServerSentEvent(data: json))
    }

    @Test func textContentBecomesADelta() {
        let event = decode(#"{"type":"TEXT_MESSAGE_CONTENT","messageId":"m1","delta":"hel"}"#)
        guard case .textDelta(let id, let text) = event else {
            Issue.record("expected a delta, got \(String(describing: event))")
            return
        }
        #expect(id == "m1")
        #expect(text == "hel")
    }

    @Test func runErrorCarriesTheEnginesOwnSentence() {
        // Never replaced with a generic one. The engine's message is the only thing that tells
        // the user what to do next.
        let event = decode(#"{"type":"RUN_ERROR","runId":"r1","message":"Anthropic rejected the key"}"#)
        guard case .failed(_, let reason) = event else {
            Issue.record("expected a failure, got \(String(describing: event))")
            return
        }
        #expect(reason == "Anthropic rejected the key")
    }

    @Test func anEventTypeWeDoNotDrawIsIgnoredRatherThanFatal() {
        // AG-UI has more than thirty event types and this app renders a handful. A stream
        // carrying reasoning chunks is working correctly; failing on one would break a
        // conversation over something we simply do not show.
        #expect(decode(#"{"type":"REASONING_MESSAGE_CHUNK","delta":"thinking"}"#) == nil)
        #expect(decode(#"{"type":"STATE_DELTA","delta":[]}"#) == nil)
    }

    @Test func malformedJsonIsIgnoredRatherThanFatal() {
        #expect(decode("{not json") == nil)
        #expect(decode("") == nil)
    }

    @Test func anEmptyDeltaIsDroppedRatherThanAppended() {
        // Appending an empty string re-renders the message for no change, which on a long
        // conversation is a layout pass per keep-alive.
        #expect(decode(#"{"type":"TEXT_MESSAGE_CONTENT","messageId":"m1","delta":""}"#) == nil)
    }

    @Test func runLevelEventsFallBackToTheRunId() {
        // RUN_STARTED has no messageId. Without a key the conversation cannot place the event.
        let event = decode(#"{"type":"RUN_STARTED","runId":"r1","threadId":"t1"}"#)
        guard case .started(let id) = event else {
            Issue.record("expected started, got \(String(describing: event))")
            return
        }
        #expect(id == "r1")
    }

    @Test func aWholeStreamDecodesInOrder() {
        var parser = ServerSentEventParser()
        let lines = [
            #"data: {"type":"RUN_STARTED","runId":"r1"}"#, "",
            #"data: {"type":"TEXT_MESSAGE_CONTENT","messageId":"m1","delta":"he"}"#, "",
            ": keep-alive",
            #"data: {"type":"TEXT_MESSAGE_CONTENT","messageId":"m1","delta":"llo"}"#, "",
            #"data: {"type":"RUN_FINISHED","runId":"r1"}"#, "",
        ]
        let decoded = lines.compactMap { parser.consume($0) }.compactMap(AGUIDecoder.decode)

        #expect(decoded.count == 4)
        var text = ""
        for event in decoded {
            if case .textDelta(_, let delta) = event { text += delta }
        }
        #expect(text == "hello")
    }
}
