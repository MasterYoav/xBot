import Foundation

/// A reply as the transcript draws it: text, runs of tools folded into one row, notices, failures.
public enum ReplySegment: Equatable, Sendable {
    case text(String)
    case tools([ToolPart])
    case notice(String)
    case failure(String)
    case image(ImagePart)
    case approval(ApprovalPart)
    case lesson(String)
}

public enum ReplyLayout {
    public static func segments(_ parts: [Part]) -> [ReplySegment] {
        var segments: [ReplySegment] = []
        for part in parts {
            switch part {
            case .text(let text): segments.append(.text(text))
            case .tool(let tool):
                if case .tools(var run) = segments.last {
                    run.append(tool)
                    segments[segments.count - 1] = .tools(run)
                } else {
                    segments.append(.tools([tool]))
                }
            case .notice(let text): segments.append(.notice(text))
            case .failure(let reason): segments.append(.failure(reason))
            case .plan: break
            case .image(let image): segments.append(.image(image))
            case .approval(let approval): segments.append(.approval(approval))
            case .lesson(let text): segments.append(.lesson(text))
            }
        }
        return segments
    }
}
