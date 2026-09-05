import Foundation
import XBotEngine

/// Plain-language deny rules mapped to CEL. See engine admin boundaries presets.
public enum ComputerPolicyPreset: String, CaseIterable, Identifiable, Sendable {
    case submitForms
    case passwordFields
    case socialMedia

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .submitForms:
            String(localized: "Submitting a form or pressing Enter to confirm")
        case .passwordFields:
            String(localized: "Typing into a password field")
        case .socialMedia:
            String(localized: "Visiting Facebook or X")
        }
    }

    public var rule: String {
        switch self {
        case .submitForms:
            #"(intent == "activate" && contains(element.name, "submit")) || ((tool.name == "computer_key" || tool.name == "computer_type") && key == "Enter")"#
        case .passwordFields:
            #"intent == "type" && contains(element.name, "password")"#
        case .socialMedia:
            #"intent == "navigate" && (contains(page.host, "facebook.com") || contains(page.host, "x.com"))"#
        }
    }
}
