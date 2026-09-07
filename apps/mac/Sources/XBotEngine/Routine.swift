import Foundation

/// A standing instruction an agent carries out on a schedule.
///
/// The app shows these and stops them; it never composes one. That is upstream's design, stated in
/// `server/src/routines/routes.ts`: there is deliberately no create and no edit endpoint, because
/// making a routine and changing one are conversational — the hard part of both is turning a
/// sentence into a cron expression and a channel, which is what a conversation is for. A Bot creates
/// it mid-chat through its own tools. This surface answers the narrower question the person actually
/// has: what is standing, and does it stay standing.
public struct Routine: Identifiable, Hashable, Sendable {
    public let id: String
    public let agentId: String
    /// Display text, never parsed.
    ///
    /// The engine renders "Weekdays at 09:00" where it can and hands back the raw five-field cron
    /// where it cannot — its own comment says a consumer must show this and never compute a time
    /// from it, because the library that decides when a routine really fires lives there. A second
    /// cron reader over here is a second answer to when something happens.
    public let schedule: String
    public let timezone: String
    public let instruction: String
    public let channelName: String?
    /// The channel the routine posts into is gone. It will still run and have nowhere to speak.
    public let channelIsGone: Bool
    public let enabled: Bool
    /// Authoritative, because the engine computed it from the expression itself.
    public let nextRunAt: Date?
    public let lastRunStatus: String?
    public let lastRunAt: Date?

    public init(
        id: String,
        agentId: String,
        schedule: String,
        timezone: String,
        instruction: String,
        channelName: String? = nil,
        channelIsGone: Bool = false,
        enabled: Bool = true,
        nextRunAt: Date? = nil,
        lastRunStatus: String? = nil,
        lastRunAt: Date? = nil
    ) {
        self.id = id
        self.agentId = agentId
        self.schedule = schedule
        self.timezone = timezone
        self.instruction = instruction
        self.channelName = channelName
        self.channelIsGone = channelIsGone
        self.enabled = enabled
        self.nextRunAt = nextRunAt
        self.lastRunStatus = lastRunStatus
        self.lastRunAt = lastRunAt
    }
}
