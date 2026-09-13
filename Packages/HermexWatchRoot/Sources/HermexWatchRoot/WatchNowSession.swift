import Foundation
import WatchShared

/// Picks the session the wrist should operate on, and the complication activity.
public enum WatchNowSession {
    public static func isRunning(_ phase: WatchRunPhase?) -> Bool {
        switch phase {
        case .starting, .thinking, .tool, .searching, .files, .command, .responding:
            return true
        case .attention, .completed, .failed, .stopped, .unknown, nil:
            return false
        }
    }

    public static func needsAttention(_ session: WatchSessionSummary) -> Bool {
        session.attention || session.runState == .attention
    }

    public static func preferred(from sessions: [WatchSessionSummary]) -> WatchSessionSummary? {
        let active = sessions.filter { !$0.isArchived }
        if let running = active.first(where: { isRunning($0.runState) }) {
            return running
        }
        if let attention = active.first(where: needsAttention) {
            return attention
        }
        if let pinned = active.first(where: \.isPinned) {
            return pinned
        }
        return active.max { lhs, rhs in
            (lhs.updatedAt ?? .distantPast) < (rhs.updatedAt ?? .distantPast)
        } ?? sessions.first
    }

    public static func widgetActivity(from sessions: [WatchSessionSummary]) -> RedactedWidgetSnapshot.Activity {
        if sessions.contains(where: { isRunning($0.runState) }) {
            return .running
        }
        if sessions.contains(where: needsAttention) {
            return .needsAttention
        }
        if sessions.isEmpty {
            return .unknown
        }
        return .idle
    }
}

public enum WatchTranscriptPreview {
    public static func lastAssistantText(in blocks: [WatchTranscriptBlock], maxCharacters: Int = 160) -> String? {
        for block in blocks.reversed() {
            if case .text(_, let role, let text) = block, role == .assistant {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if trimmed.count <= maxCharacters { return trimmed }
                return String(trimmed.prefix(maxCharacters - 1)) + "…"
            }
        }
        return nil
    }
}
