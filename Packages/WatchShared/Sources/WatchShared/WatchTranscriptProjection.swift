import Foundation

/// Maps one server message into watch transcript kinds. Wrist views stay dumb;
/// this is the phone-side projection of chat content the broker already owns.
public enum WatchTranscriptProjection: Sendable {
    public static let maximumCodeCharacters = 1_200
    public static let maximumToolSummaryCharacters = 240

    public static func blocks(for message: WatchPhoneMessageHint) -> [WatchPhoneTranscriptPage.Block] {
        var result: [WatchPhoneTranscriptPage.Block] = []
        var index = 0

        func nextID() -> String {
            defer { index += 1 }
            return index == 0 ? message.id : "\(message.id)-\(index)"
        }

        if message.isToolResult {
            result.append(
                WatchPhoneTranscriptPage.Block(
                    id: nextID(),
                    kind: .tool(
                        title: message.tools.first?.title ?? "Tool",
                        state: message.tools.first?.state ?? "done",
                        summary: truncated(message.text, max: maximumToolSummaryCharacters)
                    )
                )
            )
            return result
        }

        for tool in message.tools {
            result.append(
                WatchPhoneTranscriptPage.Block(
                    id: nextID(),
                    kind: .tool(
                        title: tool.title,
                        state: tool.state,
                        summary: tool.summary.flatMap { truncated($0, max: maximumToolSummaryCharacters) }
                    )
                )
            )
        }

        let displayText = Self.contentWithoutAttachedFilesMarker(in: message.text)
        var seenImagePaths = Set<String>()

        for segment in segments(in: displayText) {
            switch segment {
            case .text(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                result.append(
                    WatchPhoneTranscriptPage.Block(
                        id: nextID(),
                        kind: .text(role: message.role, text: trimmed)
                    )
                )
            case .code(let language, let text):
                let clipped = truncated(text, max: maximumCodeCharacters)
                result.append(
                    WatchPhoneTranscriptPage.Block(
                        id: nextID(),
                        kind: .code(
                            language: language,
                            text: clipped ?? "",
                            isTruncated: (text.count > maximumCodeCharacters)
                        )
                    )
                )
            case .image(let path, let alt):
                let key = normalizedPath(path) ?? path
                seenImagePaths.insert(key)
                result.append(
                    WatchPhoneTranscriptPage.Block(
                        id: nextID(),
                        kind: .image(path: path, mime: mimeForPath(path), alt: nonEmpty(alt))
                    )
                )
            }
        }

        for attachment in message.attachments {
            let key = normalizedPath(attachment.path) ?? normalizedPath(attachment.name)
            if let key, seenImagePaths.contains(key) { continue }
            if attachment.isImage {
                result.append(
                    WatchPhoneTranscriptPage.Block(
                        id: nextID(),
                        kind: .image(
                            path: attachment.path,
                            mime: attachment.mime ?? mimeForPath(attachment.path ?? attachment.name),
                            alt: nonEmpty(attachment.name)
                        )
                    )
                )
            } else {
                let kind = audioKind(attachment) ? "audio" : "file"
                result.append(
                    WatchPhoneTranscriptPage.Block(
                        id: nextID(),
                        kind: .unsupported(
                            kind: kind,
                            summary: nonEmpty(attachment.name) ?? "Open on iPhone"
                        )
                    )
                )
            }
        }

        return result
    }

    public static func contentWithoutAttachedFilesMarker(in content: String) -> String {
        guard let range = content.range(of: "[Attached files:", options: .backwards) else {
            return content
        }
        let afterMarker = content[range.upperBound...]
        guard let close = afterMarker.firstIndex(of: "]") else { return content }
        let afterBracket = afterMarker[afterMarker.index(after: close)...]
        guard afterBracket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return content
        }
        var prefix = content[..<range.lowerBound]
        while let last = prefix.last, last.isWhitespace {
            prefix = prefix.dropLast()
        }
        return String(prefix)
    }

    public static func chatMessageText(draft: String, attachments: [WatchChatAttachment]) -> String {
        let references = attachments
            .map { $0.path.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !references.isEmpty else { return draft }
        let base = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty {
            return "I've uploaded \(references.count) file(s): \(references.joined(separator: ", "))"
        }
        return "\(draft)\n\n[Attached files: \(references.joined(separator: ", "))]"
    }

    private enum Segment {
        case text(String)
        case code(language: String?, text: String)
        case image(path: String, alt: String)
    }

    private static func segments(in text: String) -> [Segment] {
        guard !text.isEmpty else { return [] }
        var result: [Segment] = []
        var remainder = text[...]

        while !remainder.isEmpty {
            if let fence = firstFence(in: remainder) {
                appendText(String(remainder[..<fence.markerStart]), to: &result)
                result.append(.code(language: fence.language, text: fence.body))
                remainder = remainder[fence.end...]
                continue
            }
            if let image = firstMarkdownImage(in: remainder) {
                appendText(String(remainder[..<image.start]), to: &result)
                result.append(.image(path: image.path, alt: image.alt))
                remainder = remainder[image.end...]
                continue
            }
            if let media = firstMediaToken(in: remainder) {
                appendText(String(remainder[..<media.start]), to: &result)
                result.append(.image(path: media.path, alt: ""))
                remainder = remainder[media.end...]
                continue
            }
            appendText(String(remainder), to: &result)
            break
        }

        return result
    }

    private static func appendText(_ text: String, to segments: inout [Segment]) {
        guard !text.isEmpty else { return }
        if case .text(let existing) = segments.last {
            segments[segments.count - 1] = .text(existing + text)
        } else {
            segments.append(.text(text))
        }
    }

    private static func firstFence(in text: Substring) -> (markerStart: String.Index, language: String?, body: String, end: String.Index)? {
        guard let start = text.range(of: "```") ?? text.range(of: "~~~") else { return nil }
        let marker = text[start]
        let afterOpen = start.upperBound
        let lineEnd = text[afterOpen...].firstIndex(of: "\n") ?? text.endIndex
        let languageRaw = text[afterOpen..<lineEnd].trimmingCharacters(in: .whitespacesAndNewlines)
        let language = languageRaw.isEmpty ? nil : languageRaw
        let bodyStart = lineEnd == text.endIndex ? text.endIndex : text.index(after: lineEnd)
        let closeSearch = text[bodyStart...]
        guard let close = closeSearch.range(of: String(marker)) else {
            return (start.lowerBound, language, String(text[bodyStart...]), text.endIndex)
        }
        var body = String(text[bodyStart..<close.lowerBound])
        if body.hasSuffix("\n") { body.removeLast() }
        return (start.lowerBound, language, body, close.upperBound)
    }

    private static func firstMarkdownImage(in text: Substring) -> (start: String.Index, path: String, alt: String, end: String.Index)? {
        guard let bang = text.range(of: "![") else { return nil }
        guard let altClose = text[bang.upperBound...].firstIndex(of: "]") else { return nil }
        let afterAlt = text.index(after: altClose)
        guard afterAlt < text.endIndex, text[afterAlt] == "(" else { return nil }
        let pathStart = text.index(after: afterAlt)
        guard let pathEnd = text[pathStart...].firstIndex(of: ")") else { return nil }
        let alt = String(text[bang.upperBound..<altClose])
        var destination = String(text[pathStart..<pathEnd])
        if let space = destination.firstIndex(of: " ") {
            destination = String(destination[..<space])
        }
        destination = destination.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard !destination.isEmpty else { return nil }
        return (bang.lowerBound, destination, alt, text.index(after: pathEnd))
    }

    private static func firstMediaToken(in text: Substring) -> (start: String.Index, path: String, end: String.Index)? {
        guard let marker = text.range(of: "MEDIA:") else { return nil }
        let pathStart = marker.upperBound
        var end = pathStart
        while end < text.endIndex, !text[end].isWhitespace {
            end = text.index(after: end)
        }
        let path = String(text[pathStart..<end])
        guard !path.isEmpty else { return nil }
        return (marker.lowerBound, path, end)
    }

    private static func truncated(_ text: String, max: Int) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= max { return trimmed }
        return String(trimmed.prefix(max - 1)) + "…"
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    private static func normalizedPath(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return URL(fileURLWithPath: value).lastPathComponent.lowercased()
    }

    private static func mimeForPath(_ path: String?) -> String? {
        guard let path else { return nil }
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        default: return nil
        }
    }

    private static func audioKind(_ attachment: WatchPhoneAttachmentHint) -> Bool {
        let mime = attachment.mime?.lowercased() ?? ""
        if mime.hasPrefix("audio/") { return true }
        let ext = URL(fileURLWithPath: attachment.path ?? attachment.name).pathExtension.lowercased()
        return ["m4a", "aac", "mp3", "wav", "caf"].contains(ext)
    }
}
