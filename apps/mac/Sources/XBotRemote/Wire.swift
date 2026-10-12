import Foundation

/// The wire between xBot on the Mac and xBot on an iPhone or iPad. Foundation only, so both build
/// it. Plain value types, not the Mac's storage models: the protocol is versioned on its own and the
/// phone never depends on how the Mac keeps things. See docs/superpowers/specs/2026-10-11-mobile-remote-design.md.
public enum Wire {
    /// Bumped when a message changes meaning. Unknown messages are skipped, so adding one isn't.
    public static let version = 1
    public static let bonjourType = "_xbot._tcp"

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
}

// MARK: - What the phone shows

public struct RemoteProject: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    /// The folder on the Mac (shown under the name; absent from older Macs).
    public var path: String?
    public init(id: UUID, name: String, path: String? = nil) { self.id = id; self.name = name; self.path = path }
}

public struct RemoteChat: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var projectID: UUID?
    /// HarnessKind's raw value ("claude", "codex", …) and its product name.
    public var agent: String
    public var agentName: String
    public var model: String?
    /// PermissionMode's raw value.
    public var mode: String
    public var effort: String?
    public var planMode: Bool
    /// The crew member it's with, if any.
    public var crewName: String?
    public var updatedAt: Date
    public var isRunning: Bool
    /// Why it can't send right now ("Codex isn't installed…"), if it can't.
    public var blocked: String?

    public init(id: UUID, title: String, projectID: UUID?, agent: String, agentName: String, model: String?,
                mode: String, effort: String?, planMode: Bool, crewName: String?, updatedAt: Date,
                isRunning: Bool, blocked: String?) {
        self.id = id; self.title = title; self.projectID = projectID; self.agent = agent
        self.agentName = agentName; self.model = model; self.mode = mode; self.effort = effort
        self.planMode = planMode; self.crewName = crewName; self.updatedAt = updatedAt
        self.isRunning = isRunning; self.blocked = blocked
    }
}

public struct RemoteTool: Codable, Equatable, Sendable {
    public var id: String
    /// As the Mac words it: "Read", "Ran", "Used node_repl: js".
    public var label: String
    public var summary: String
    public var isDone: Bool
    public var isError: Bool
    public var size: String?

    public init(id: String, label: String, summary: String, isDone: Bool, isError: Bool, size: String?) {
        self.id = id; self.label = label; self.summary = summary; self.isDone = isDone
        self.isError = isError; self.size = size
    }
}

public struct RemotePlanStep: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    /// PlanStep.Status's raw value: pending, running, done, failed, stopped.
    public var status: String
    public init(id: UUID, title: String, status: String) { self.id = id; self.title = title; self.status = status }
}

public struct RemotePlan: Codable, Equatable, Sendable {
    /// Plan.Status's raw value: drafting, review, running, finished, stopped.
    public var status: String
    public var summary: String
    public var note: String
    public var steps: [RemotePlanStep]
    public var problem: String?
    public var closing: String?

    public init(status: String, summary: String, note: String, steps: [RemotePlanStep], problem: String?, closing: String?) {
        self.status = status; self.summary = summary; self.note = note; self.steps = steps
        self.problem = problem; self.closing = closing
    }
}

public enum RemotePart: Codable, Equatable, Sendable {
    case text(String)
    case tool(RemoteTool)
    case notice(String)
    case failure(String)
    case plan(RemotePlan)
}

public struct RemoteMessage: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// "user" or "assistant".
    public var role: String
    public var parts: [RemotePart]
    public var createdAt: Date
    public init(id: UUID, role: String, parts: [RemotePart], createdAt: Date) {
        self.id = id; self.role = role; self.parts = parts; self.createdAt = createdAt
    }
}

/// What the composer can offer: the agents installed on the Mac and their models.
public struct RemoteAgent: Codable, Equatable, Sendable, Identifiable {
    public struct Model: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var efforts: [String]
        public init(id: String, name: String, efforts: [String]) { self.id = id; self.name = name; self.efforts = efforts }
    }

    public var id: String
    public var name: String
    public var models: [Model]
    public var makesPlans: Bool
    public var editingNeedsFullAccess: Bool

    public init(id: String, name: String, models: [Model], makesPlans: Bool, editingNeedsFullAccess: Bool) {
        self.id = id; self.name = name; self.models = models; self.makesPlans = makesPlans
        self.editingNeedsFullAccess = editingNeedsFullAccess
    }
}

/// A setting that can be cleared: `Choice(nil)` means "the agent's default", while a nil
/// `Choice?` means "leave it alone". (A plain `String??` loses that difference in JSON.)
public struct Choice: Codable, Equatable, Sendable {
    public var value: String?
    public init(_ value: String?) { self.value = value }
}

/// A chat's settings, as the phone changes them. Nil fields are left alone.
public struct RemoteChatSettings: Codable, Equatable, Sendable {
    public var agent: String?
    public var model: Choice?
    public var mode: String?
    public var effort: Choice?
    public var planMode: Bool?

    public init(agent: String? = nil, model: Choice? = nil, mode: String? = nil, effort: Choice? = nil, planMode: Bool? = nil) {
        self.agent = agent; self.model = model; self.mode = mode; self.effort = effort; self.planMode = planMode
    }
}

// MARK: - Messages

/// Mac → phone.
public enum HostMessage: Codable, Equatable, Sendable {
    case hello(version: Int, macName: String, macID: UUID)
    /// Everything the chat list needs; sent once on connect, then `chat` / `chatRemoved` diffs.
    case workspace(projects: [RemoteProject], chats: [RemoteChat], agents: [RemoteAgent])
    case chat(RemoteChat)
    case chatRemoved(UUID)
    case agents([RemoteAgent])
    /// An opened chat's saved messages; later ones arrive as `message`.
    case transcript(chatID: UUID, messages: [RemoteMessage])
    case message(chatID: UUID, message: RemoteMessage)
    case messageRemoved(chatID: UUID, messageID: UUID)
    /// The reply being written, whole (coalesced, so a few times a second at most). Empty: none.
    case live(chatID: UUID, parts: [RemotePart])
    /// The answer to a phone's request.
    case reply(requestID: UUID, ok: Bool, reason: String?, chatID: UUID?)
    // Answers that carry data (each to one request; a refusal comes as `reply` instead).
    case folder(requestID: UUID, entries: [RemoteFileEntry])
    case file(requestID: UUID, file: RemoteFile)
    case git(requestID: UUID, status: RemoteGit)
    case diff(requestID: UUID, lines: [RemoteDiffLine])
    /// Folders on the Mac, to pick a new project from; `path` is the one listed.
    case macFolders(requestID: UUID, path: String, folders: [RemoteFolder])
    /// A project's notes, newest first; `saved` is the file a save wrote (it's renamed after its title).
    case notes(requestID: UUID, notes: [RemoteNote], saved: String?)
    /// Every automation, in order, with the step palette and whether the helper runs them while
    /// xBot is closed.
    case automations(requestID: UUID, automations: [RemoteAutomation], apps: [RemoteApp], runsWhileClosed: Bool)
    /// The crew, in order, and the parts of a look.
    case crew(requestID: UUID, members: [RemoteCrewMember], parts: [RemoteAvatarPart])
    /// A look drawn by the Mac (PNG), for the editor's preview.
    case avatarImage(requestID: UUID, image: Data?)
    /// Every ability (`missing`: agents with no CLI on the Mac), and the marketplace once asked for.
    case abilities(requestID: UUID, items: [RemoteAbility], missing: [String], plugins: [RemotePlugin]?)
    /// A shell on the Mac started (`openShell`'s answer).
    case shellOpened(requestID: UUID, shellID: UUID, directory: String)
    /// What the shell wrote, as bytes for the terminal.
    case shellOutput(shellID: UUID, data: Data)
    case shellEnded(shellID: UUID)
}

/// Phone → Mac.
public enum ClientMessage: Codable, Equatable, Sendable {
    /// `deviceID`: the pairing key's identity (only a device holding that key gets this far).
    case hello(version: Int, deviceID: String, deviceName: String)
    /// Start receiving this chat's transcript and live reply; `close` stops it.
    case open(chatID: UUID)
    case close(chatID: UUID)
    case send(requestID: UUID, chatID: UUID, text: String)
    /// A new chat (in a project, or none) with its first message.
    case newChat(requestID: UUID, projectID: UUID?, text: String, settings: RemoteChatSettings)
    case stop(requestID: UUID, chatID: UUID)
    case edit(requestID: UUID, chatID: UUID, messageID: UUID, text: String)
    case runPlan(requestID: UUID, chatID: UUID, messageID: UUID)
    case cancelPlan(requestID: UUID, chatID: UUID, messageID: UUID)
    case setChat(requestID: UUID, chatID: UUID, settings: RemoteChatSettings)
    case rename(requestID: UUID, chatID: UUID, title: String)
    /// Ask the last question again.
    case retry(requestID: UUID, chatID: UUID)
    /// Deletes the chat; `undoDelete` brings it back (the Mac keeps the last few deleted chats).
    case delete(requestID: UUID, chatID: UUID)
    case undoDelete(requestID: UUID, chatID: UUID)
    // Projects. Paths are relative to the project's folder and can't leave it.
    case listFolder(requestID: UUID, projectID: UUID, path: String)
    case readFile(requestID: UUID, projectID: UUID, path: String)
    case gitStatus(requestID: UUID, projectID: UUID)
    case gitDiff(requestID: UUID, projectID: UUID, path: String)
    /// Answered with the new `git` status.
    case gitAction(requestID: UUID, projectID: UUID, action: RemoteGitAction)
    /// Answered with `reply` (ok, or why not).
    case fileAction(requestID: UUID, projectID: UUID, action: RemoteFileAction)
    /// Folders in a folder on the Mac (nil: the home folder); for adding a project.
    case browseMac(requestID: UUID, path: String?)
    case addProject(requestID: UUID, path: String)
    case removeProject(requestID: UUID, projectID: UUID)
    // Notes (read one with `readFile` at "notes/<name>").
    case listNotes(requestID: UUID, projectID: UUID)
    /// Writes a note (`name` nil: a new one) and names its file after its first line. Answered with `notes`.
    case saveNote(requestID: UUID, projectID: UUID, name: String?, text: String)
    /// To the Mac's Trash; `undoDeleteNote` puts the last one deleted from a phone back.
    case deleteNote(requestID: UUID, projectID: UUID, name: String)
    case undoDeleteNote(requestID: UUID, projectID: UUID)
    // Automations: each answered with `automations`, except `runAutomation` (a `reply` with the run's chat).
    case listAutomations(requestID: UUID)
    /// Creates or updates (by id).
    case saveAutomation(requestID: UUID, automation: RemoteAutomation)
    case deleteAutomation(requestID: UUID, automationID: UUID)
    case runAutomation(requestID: UUID, automationID: UUID)
    /// Installs or removes the background helper that runs automations while xBot is closed.
    case setAutomationHelper(requestID: UUID, on: Bool)
    // The crew: each answered with `crew`, except `talkTo` (a `reply` with the new chat) and
    // `drawAvatar` (an `avatarImage`).
    case listCrew(requestID: UUID)
    /// Hires (new id) or updates.
    case saveCrew(requestID: UUID, member: RemoteCrewMember)
    case deleteCrew(requestID: UUID, memberID: UUID)
    /// Brings back the last member deleted from a phone, with their chats.
    case undoDeleteCrew(requestID: UUID)
    /// A new chat with the member (in its home project), starting with `text`.
    case talkTo(requestID: UUID, memberID: UUID, text: String)
    case drawAvatar(requestID: UUID, avatar: RemoteAvatar)
    // Abilities: each answered with `abilities`.
    case listAbilities(requestID: UUID, refresh: Bool)
    case setAbility(requestID: UUID, abilityID: String, enabled: Bool)
    case removeAbility(requestID: UUID, abilityID: String)
    case listPlugins(requestID: UUID)
    case installPlugin(requestID: UUID, pluginID: String)
    /// A server run by a command (`command` + `arguments`) or reached at `url`, for each agent in `agents`.
    case addMCP(requestID: UUID, name: String, command: String?, arguments: [String], url: String?, agents: [String])
    // Terminal: a login shell on the Mac, in a project's folder (or home), while this device stays connected.
    case openShell(requestID: UUID, projectID: UUID?, cols: Int, rows: Int)
    case shellInput(shellID: UUID, data: Data)
    case shellResize(shellID: UUID, cols: Int, rows: Int)
    case closeShell(shellID: UUID)
    /// The phone is away from the Mac's network and reading through iCloud (a heartbeat).
    case away
}

/// One frame on the wire. Messages a side doesn't know (a newer peer's) fail to decode and are
/// skipped by `Frame.decode`, never fatal.
public enum Frame {
    /// A 4-byte big-endian length, then that much JSON.
    public static func encode<M: Encodable>(_ message: M) throws -> Data {
        let body = try Wire.encoder.encode(message)
        var length = UInt32(body.count).bigEndian
        return Data(bytes: &length, count: 4) + body
    }

    public struct TooLarge: Error {}

    /// Takes every whole frame off the front of `buffer`, leaving any partial one. Throws on a
    /// frame longer than `maximumLength`: the connection is then closed, not buffered forever.
    public static func decode<M: Decodable>(_ type: M.Type, from buffer: inout Data) throws(TooLarge) -> [M] {
        var out: [M] = []
        while buffer.count >= 4 {
            let start = buffer.startIndex
            let length = Int(buffer[start..<start + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
            guard length <= maximumLength else { throw TooLarge() }
            guard buffer.count >= 4 + length else { break }
            let body = buffer[start + 4..<start + 4 + length]
            buffer = Data(buffer[(start + 4 + length)...])
            if let message = try? Wire.decoder.decode(M.self, from: body) { out.append(message) }
        }
        return out
    }

    /// The largest frame either side accepts (a long transcript is well under it).
    public static let maximumLength = 16 << 20
}
