import Foundation

/**
 The agent's computer, as the client tools OpenBot's agents expect.

 Upstream never offers these from the engine. Its web app registers them with `useFrontendTool`
 (`engine/app/src/lib/copilot/computer-tools.tsx`): the client puts them in every run's `tools`, runs
 each call against `/api/computers/:botId/…`, and continues the run with the result. The Mac app is
 xBot's client and sent `tools: []`, so no xBot agent was ever offered a browser, its files or a shell.
 See `docs/plans/computer-client-tools.md`.

 The descriptions are upstream's, word for word. They are the Bot's only instructions for these tools,
 and the Bot's prompting was written against exactly this wording.
 */
public enum ComputerTools {
    /// One tool, as the run offers it.
    public struct Definition: Sendable, Equatable {
        public let name: String
        public let description: String
        /// JSON Schema for the arguments, as JSON text.
        public let parametersJSON: String
    }

    /// Every client tool, in upstream's order.
    public static let definitions: [Definition] = [
        Definition(
            name: "computer_navigate",
            description: "Open a web page on your own computer so the person can watch. Use this when asked to look at, visit, open or check a website. Returns the page title and its readable text, so answer from what comes back rather than telling the person to go and look.",
            parametersJSON: #"{"type":"object","properties":{"url":{"type":"string","description":"Full web address to open, including https://"}},"required":["url"]}"#
        ),
        Definition(
            name: "computer_read",
            description: "Read the page currently open on your computer, without opening anything. Use this after you click something that changes the page, such as submitting a form, to find out what it now says.",
            parametersJSON: #"{"type":"object","properties":{}}"#
        ),
        Definition(
            name: "computer_snapshot",
            description: "List the things on the current page you can act on: fields, buttons, links and checkboxes, each with a ref, its label and its current value. Call this BEFORE clicking or typing, and use the refs it returns. Always send back the snapshotId it gives you. If an action reports that your refs are stale, the page changed: call this again and use the new refs.",
            parametersJSON: #"{"type":"object","properties":{}}"#
        ),
        Definition(
            name: "computer_type",
            description: "Enter text into a field on the page. Give the ref of the field from your most recent snapshot and the snapshotId it came from. This replaces whatever the field already contains. Set submit to true to press Enter afterwards.",
            parametersJSON: #"{"type":"object","properties":{"ref":{"type":"string","description":"Ref of the field, from your most recent snapshot"},"snapshotId":{"type":"number","description":"The snapshotId that ref came from"},"text":{"type":"string","description":"The text to enter"},"submit":{"type":"boolean","description":"Press Enter after typing, to submit a single-field form"}},"required":["ref","snapshotId","text"]}"#
        ),
        Definition(
            name: "computer_click",
            description: "Click something on the page: a button, a link, a checkbox or a radio option. Give the ref from your most recent snapshot and the snapshotId it came from.",
            parametersJSON: #"{"type":"object","properties":{"ref":{"type":"string","description":"Ref of the element to click, from your most recent snapshot"},"snapshotId":{"type":"number","description":"The snapshotId that ref came from"}},"required":["ref","snapshotId"]}"#
        ),
        Definition(
            name: "computer_key",
            description: "Press a key, such as Enter, Tab or Escape. Give a ref to press it while a particular field is focused, or omit the ref to press it on the page.",
            parametersJSON: #"{"type":"object","properties":{"key":{"type":"string","description":"Key name, such as Enter, Tab or Escape"},"ref":{"type":"string","description":"Optional ref to press the key on"},"snapshotId":{"type":"number","description":"The snapshotId the ref came from, required if ref is given"}},"required":["key"]}"#
        ),
        Definition(
            name: "computer_request_secret",
            description: "Ask the person for ONE value you must not be told: a password, a one-time code, a card number. Focus the field first with computer_click, then call this with the ref of that field and a short label for what you need. They type it into a masked box that goes straight to the page. You will never see the value, and you must not ask for it any other way. Prefer this over a full takeover when you only need one field filled in. The value is only TYPED into the field: if the form needs submitting, do that yourself afterwards with computer_click.",
            parametersJSON: #"{"type":"object","properties":{"label":{"type":"string","description":"What you need, in a few words, e.g. 'the code sent to your phone'"},"ref":{"type":"string","description":"Ref of the field it goes in, from your most recent snapshot"},"snapshotId":{"type":"number","description":"The snapshotId that ref came from"}},"required":["label","ref","snapshotId"]}"#
        ),
        Definition(
            name: "report_refusal",
            description: "Record that you DECLINED something you were asked to do, because it looked unsafe, was outside what you are for, or you judged you should not. Call this whenever you say no to a request, in addition to telling the person. It changes nothing about your answer; it exists so an administrator can see what this Bot is being asked to do. Do not call it when you simply could not do something, only when you chose not to.",
            parametersJSON: #"{"type":"object","properties":{"reason":{"type":"string","description":"Why you declined, in one sentence and in your own words"},"request":{"type":"string","description":"What you were asked to do, in a few words"}},"required":["reason"]}"#
        ),
        Definition(
            name: "computer_request_help",
            description: "Ask the person to take control of your computer and do something you cannot: sign in, enter a password or a one-time code, or clear a CAPTCHA. Say specifically what you need done. They will drive the browser themselves and hand it back, and you carry on in the same session. Use this INSTEAD of giving up, and instead of ever asking them to type a password to you. This call is the only thing that reaches them: until you make it they are not looking at the page and have no way to help, so saying you need them to sign in, or asking whether they would like to proceed, hands over nothing and leaves the page where it is.",
            parametersJSON: #"{"type":"object","properties":{"reason":{"type":"string","description":"What you need the person to do, in one sentence, e.g. 'This page is asking for a code sent to your phone.'"}},"required":["reason"]}"#
        ),
        Definition(
            name: "computer_list_files",
            description: "List what is in your workspace: every file and folder you have saved, with sizes. Call this FIRST when you are asked what files you have, or before reading a file whose exact name you are not sure of. Never guess a filename.",
            parametersJSON: #"{"type":"object","properties":{"path":{"type":"string","description":"Optional folder to list. Omit for the whole workspace."}}}"#
        ),
        Definition(
            name: "computer_read_file",
            description: "Read a file you saved earlier in your own workspace. Paths are relative to your workspace, such as notes.md or reports/august.csv. Your workspace survives between conversations, so use this to pick up notes you made before.",
            parametersJSON: #"{"type":"object","properties":{"path":{"type":"string","description":"Path relative to your workspace, such as notes.md"}},"required":["path"]}"#
        ),
        Definition(
            name: "computer_run_command",
            description: "Run a shell command on your own computer. Use this for anything the browser cannot do: installing a tool you need, processing a file you saved, running a script. The working directory is your workspace, so paths are relative to it and files you write here are the same ones the file tools see. Commands run in bash, so pipes and && work. Long output is truncated from the start, and a command that runs too long is stopped. You are not the root user, so anything that writes outside your workspace needs sudo, which asks for no password: installing a package is `sudo apt-get update && sudo apt-get install -y <package>`. If sudo is refused, this computer does not grant it, so say so rather than retrying.",
            parametersJSON: #"{"type":"object","properties":{"command":{"type":"string","description":"The command to run, such as: sudo apt-get install -y jq"}},"required":["command"]}"#
        ),
        Definition(
            name: "computer_write_file",
            description: "Save a file in your own workspace so you still have it later. Paths are relative to your workspace and folders are created as needed. Set append to true to add to the end of an existing file rather than replacing it. Text only.",
            parametersJSON: #"{"type":"object","properties":{"path":{"type":"string","description":"Path relative to your workspace, such as reports/august.csv"},"contents":{"type":"string","description":"The text to save"},"append":{"type":"boolean","description":"Add to the end of the file instead of replacing it"}},"required":["path","contents"]}"#
        ),
        Definition(
            name: "computer_scroll",
            description: "Scroll the page down, or up with a negative amount, to bring more of a long page into view.",
            parametersJSON: #"{"type":"object","properties":{"deltaY":{"type":"number","description":"Pixels to scroll; positive is down. Defaults to 600."}}}"#
        ),
    ]

    public static let names: Set<String> = Set(definitions.map(\.name))

    /// A run's `tools` array, as AG-UI expects it.
    public static var wireTools: [[String: Any]] {
        definitions.map { definition in
            [
                "name": definition.name,
                "description": definition.description,
                "parameters": (try? JSONSerialization.jsonObject(with: Data(definition.parametersJSON.utf8))) ?? [:],
            ]
        }
    }

    /// How one call reaches the engine: a plain request, or one that then waits on a person.
    public enum Route: Equatable, Sendable {
        /// Relative to `/api/computers/:botId`. A nil body is a GET.
        case computer(path: String, body: String?)
        /// POST, then wait until the person has answered. See `ComputerToolExecutor`.
        case waitForPerson(path: String, body: String, until: PersonWait)
        /// `report_refusal`, which is recorded against the agent rather than its computer.
        case declined(body: String)
    }

    public enum PersonWait: Equatable, Sendable {
        /// `computer_request_secret`: done when `secretWanted` has cleared.
        case secretEntered(label: String)
        /// `computer_request_help`: done when the wheel is back with the Bot and nothing is requested.
        case controlReturned
    }

    /// Which engine call a tool call becomes, or nil for a tool that is not one of these.
    public static func route(name: String, argumentsJSON: String) -> Route? {
        let args = (try? JSONSerialization.jsonObject(with: Data(argumentsJSON.utf8)) as? [String: Any]) ?? [:]
        let body = String(decoding: (try? JSONSerialization.data(withJSONObject: args)) ?? Data("{}".utf8), as: UTF8.self)
        switch name {
        case "computer_navigate": return .computer(path: "/navigate", body: body)
        case "computer_read": return .computer(path: "/read", body: nil)
        case "computer_snapshot": return .computer(path: "/snapshot", body: "{}")
        case "computer_type": return .computer(path: "/type", body: body)
        case "computer_click": return .computer(path: "/click", body: body)
        case "computer_key": return .computer(path: "/key", body: body)
        case "computer_scroll": return .computer(path: "/scroll", body: body)
        case "computer_list_files": return .computer(path: "/files/list", body: body)
        case "computer_read_file": return .computer(path: "/files/read", body: body)
        case "computer_write_file": return .computer(path: "/files/write", body: body)
        case "computer_run_command": return .computer(path: "/exec", body: body)
        case "computer_request_secret":
            return .waitForPerson(
                path: "/control/secret", body: body,
                until: .secretEntered(label: args["label"] as? String ?? "the value")
            )
        case "computer_request_help":
            return .waitForPerson(path: "/control/request", body: body, until: .controlReturned)
        case "report_refusal": return .declined(body: body)
        default: return nil
        }
    }

    /**
     A computer response, shaped exactly as upstream's `callComputer` shapes it.

     The model reads these, and the distinctions decide its next step: a 403 is a policy refusal
     (`refused`, with the rule) and nothing it does differently will help; a 409 is either a person
     holding the browser (`humanHasControl`) or a page that changed under it (`staleRefs`, so take a
     new snapshot). Everything else that is not OK carries the engine's own sentence.
     */
    public static func outcome(status: Int, body: Data?) -> [String: Any] {
        let parsed = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        guard (200..<300).contains(status) else {
            var result: [String: Any] = [
                "ok": false,
                "reason": parsed["error"] as? String ?? "That did not work.",
            ]
            if status == 403 {
                result["refused"] = true
                result["rule"] = parsed["rule"] ?? NSNull()
            }
            if status == 409 {
                if parsed["humanHasControl"] as? Bool == true {
                    result["humanHasControl"] = true
                } else {
                    result["staleRefs"] = true
                }
            }
            return result
        }
        return parsed.merging(["ok": true]) { _, new in new }
    }

    /// The navigate result narrowed to what upstream hands the model: the page, not the whole body.
    public static func navigateOutcome(_ outcome: [String: Any]) -> [String: Any] {
        guard outcome["ok"] as? Bool == true else { return outcome }
        var narrowed: [String: Any] = ["ok": true]
        for key in ["title", "url", "text", "truncated"] where outcome[key] != nil {
            narrowed[key] = outcome[key]
        }
        return narrowed
    }

    /// A tool result's content string, as CopilotKit's client writes it: JSON text.
    public static func content(_ outcome: [String: Any]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: outcome, options: [.sortedKeys])) ?? Data("{}".utf8), as: UTF8.self)
    }
}
