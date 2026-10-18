import Foundation
import Security
import XBotBrain
import XBotTools

/// The app's side of the xbot MCP server: `XBot --mcp` (started by the CLI each turn) forwards
/// every tool call here over a Unix socket, with the turn's token. Each call is checked against
/// `RiskRules` first; a risky one waits for the person's answer. Tools act through the same
/// `Workspace` methods the window uses, and on the Mac through `MacControlling`.
@MainActor
public final class ToolHost {
    /// One turn with tools: who is asking, and the elements its last `mac_ui` named.
    struct Session {
        var chatID: UUID
        var agentID: UUID?
        var elements: [String: UITree.Line] = [:]
    }

    weak var workspace: Workspace?
    let mac: any MacControlling
    public let socketPath: String
    /// The running XBot binary, which the CLIs start as `XBot --mcp`.
    public let executable: URL
    let imagesFolder: URL
    let appearance: Appearance
    public let antigravity: AntigravityMCP
    var sessions: [String: Session] = [:]
    private var listener: ToolSocketListener?

    /// Whether the phone will show an approval card; when not, the Mac is alerted too.
    public var phoneAttached: () -> Bool = { false }
    /// Brings an approval to the person's attention on the Mac (the app opens the chat).
    public var alertMac: (ApprovalPart, UUID) -> Void = { _, _ in }
    var approvalTimeout: Duration = ApprovalCenter.lifetime
    var questionTimeout: Duration = .seconds(600)

    public nonisolated static let notAllowed = "The person didn't allow this."
    /// The start of what a tool says when the Mac needs a permission; the phone shows a card for it.
    public nonisolated static let permissionSentencePrefix = "Allow xBot to see and use your Mac"

    public init(workspace: Workspace, mac: any MacControlling, socketPath: String = ToolEnvironment.defaultSocketPath,
                executable: URL, imagesFolder: URL = Store.supportDirectory.appending(path: "Images", directoryHint: .isDirectory),
                appearance: Appearance = .shared, antigravity: AntigravityMCP = AntigravityMCP()) {
        self.workspace = workspace
        self.mac = mac
        self.socketPath = socketPath
        self.executable = executable
        self.imagesFolder = imagesFolder
        self.appearance = appearance
        self.antigravity = antigravity
    }

    // MARK: The socket

    /// Starts listening on the socket (0600). The app calls it at launch.
    public func start() throws {
        let listener = ToolSocketListener(path: socketPath) { [weak self] call in
            guard let self else { return .error(ToolClient.notRunning) }
            return await self.handle(call)
        }
        try listener.start()
        self.listener = listener
    }

    /// Stops listening and removes the socket. The app calls it when it quits.
    public func stop() {
        listener?.stop()
        listener = nil
    }

    // MARK: Sessions

    /// A token for one turn in `chatID`, and the attachment the CLI needs.
    public func open(chatID: UUID, agentID: UUID?) -> ToolAttachment {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        sessions[token] = Session(chatID: chatID, agentID: agentID)
        return ToolAttachment(executable: executable, token: token, socketPath: socketPath)
    }

    /// The turn ended: its token is refused from now on.
    public func close(_ token: String) { sessions[token] = nil }

    // MARK: Calls

    public func handle(_ call: ToolCall) async -> ToolResult {
        guard let session = sessions[call.token], let workspace, workspace.chat(session.chatID) != nil else {
            return .error("This tool session isn't one xBot started, or its turn has ended.")
        }
        if call.hook == true { return await hook(call, session: session) }

        if let permission = Self.permission(for: call.tool), !mac.isAllowed(permission) {
            mac.showGuide(for: permission)
            return .error(Self.permissionSentence(permission))
        }
        let screen = call.tool.hasPrefix("mac_") ? screen(for: call, session: session) : RiskRules.Screen()
        if let risk = RiskRules.check(tool: call.tool, arguments: call.arguments, screen: screen) {
            guard await approve(risk, session: session) else { return .error(Self.notAllowed) }
        }
        if call.tool.hasPrefix("mac_") {
            return await mac(call.tool, call.arguments, token: call.token)
        }
        return await xbot(call.tool, call.arguments, session: session)
    }

    /// Claude Code's PreToolUse hook: an empty answer lets its tool run, an error blocks it.
    func hook(_ call: ToolCall, session: Session) async -> ToolResult {
        guard let risk = RiskRules.check(hookTool: call.tool, input: call.arguments) else { return .text("") }
        return await approve(risk, session: session) ? .text("") : .error(Self.notAllowed)
    }

    /// Asks the person, on the phone (a card) or the Mac, and waits. True only for Allow.
    func approve(_ risk: Risk, session: Session) async -> Bool {
        guard let workspace else { return false }
        let agent = workspace.agent(session.agentID)?.name
            ?? workspace.chat(session.chatID)?.harness.displayName
            ?? String(localized: "An agent")
        let approval = risk.approval(agent: agent)
        if !phoneAttached() { alertMac(approval, session.chatID) }
        return await workspace.approvals.ask(approval, in: session.chatID, timeout: approvalTimeout) == .allowed
    }

    /// What's on screen as an action happens: the frontmost app, its front window, and the element
    /// a click names.
    func screen(for call: ToolCall, session: Session) -> RiskRules.Screen {
        let front = mac.runningApps().first(where: \.isFrontmost)
        let element = call.arguments.string("element").flatMap { session.elements[$0] }
        return RiskRules.Screen(app: front?.name, bundleID: front?.bundleID,
                                windowTitle: front.flatMap { mac.frontWindowTitle(of: $0) },
                                elementTitle: element?.title)
    }

    static func permission(for tool: String) -> MacPermission? {
        switch tool {
        case "mac_screenshot": .screenRecording
        case "mac_ui", "mac_click", "mac_type", "mac_keys", "mac_scroll": .accessibility
        default: nil
        }
    }

    /// Said to the agent (and shown on the phone as a card) when the Mac needs a permission.
    static func permissionSentence(_ permission: MacPermission) -> String {
        let name = switch permission {
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen Recording"
        }
        return "\(permissionSentencePrefix): on the Mac, a guide is open. xBot needs \(name) in System Settings › Privacy & Security for this. Ask the person to allow it on the Mac, then try again."
    }

    /// The agent's picture or note in its chat, outside the reply.
    @discardableResult
    func post(_ parts: [Part], session: Session) -> Bool {
        workspace?.post(parts, in: session.chatID) != nil
    }
}
