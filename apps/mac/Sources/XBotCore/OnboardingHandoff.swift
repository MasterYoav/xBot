import Foundation
import XBotEngine

/// What onboarding passes to the main app at Step 5.
public struct OnboardingHandoff: Sendable {
    public var firstAgentID: Agent.ID?
    public var modelSkipped: Bool

    public init(firstAgentID: Agent.ID? = nil, modelSkipped: Bool = false) {
        self.firstAgentID = firstAgentID
        self.modelSkipped = modelSkipped
    }
}
