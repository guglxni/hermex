import Foundation

public struct WatchPhoneServerAccount: Sendable, Equatable {
    public let urlString: String
    public let displayName: String

    public init(urlString: String, displayName: String) {
        self.urlString = urlString
        self.displayName = displayName
    }
}

public struct WatchPhoneSessionRow: Sendable, Equatable {
    public let sessionID: String
    public let title: String
    public let profile: String?
    public let workspaceLabel: String?
    public let updatedAt: Date?
    public let isPinned: Bool
    public let isArchived: Bool
    public let attention: Bool
    public let runState: WatchRunPhase?

    public init(
        sessionID: String,
        title: String,
        profile: String?,
        workspaceLabel: String?,
        updatedAt: Date?,
        isPinned: Bool,
        isArchived: Bool,
        attention: Bool,
        runState: WatchRunPhase?
    ) {
        self.sessionID = sessionID
        self.title = title
        self.profile = profile
        self.workspaceLabel = workspaceLabel
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.attention = attention
        self.runState = runState
    }
}

public struct WatchPhoneTranscriptPage: Sendable, Equatable {
    public struct Block: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            case text(role: WatchMessageRole, text: String)
            case code(language: String?, text: String, isTruncated: Bool)
            case tool(title: String, state: String, summary: String?)
            case image(path: String?, mime: String?, alt: String?)
            case unsupported(kind: String, summary: String)
        }

        public let id: String
        public let kind: Kind

        public init(id: String, kind: Kind) {
            self.id = id
            self.kind = kind
        }

        public init(id: String, role: WatchMessageRole, text: String) {
            self.init(id: id, kind: .text(role: role, text: text))
        }
    }

    public let blocks: [Block]
    public let nextBefore: Int?
    public let isTruncated: Bool

    public init(blocks: [Block], nextBefore: Int?, isTruncated: Bool) {
        self.blocks = blocks
        self.nextBefore = nextBefore
        self.isTruncated = isTruncated
    }
}

public struct WatchPhoneAttachmentHint: Sendable, Equatable {
    public let name: String
    public let path: String?
    public let mime: String?
    public let isImage: Bool

    public init(name: String, path: String?, mime: String?, isImage: Bool) {
        self.name = name
        self.path = path
        self.mime = mime
        self.isImage = isImage
    }
}

public struct WatchPhoneToolHint: Sendable, Equatable {
    public let title: String
    public let state: String
    public let summary: String?

    public init(title: String, state: String, summary: String?) {
        self.title = title
        self.state = state
        self.summary = summary
    }
}

public struct WatchPhoneMessageHint: Sendable, Equatable {
    public let id: String
    public let role: WatchMessageRole
    public let text: String
    public let attachments: [WatchPhoneAttachmentHint]
    public let tools: [WatchPhoneToolHint]
    public let isToolResult: Bool

    public init(
        id: String,
        role: WatchMessageRole,
        text: String,
        attachments: [WatchPhoneAttachmentHint] = [],
        tools: [WatchPhoneToolHint] = [],
        isToolResult: Bool = false
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.attachments = attachments
        self.tools = tools
        self.isToolResult = isToolResult
    }
}

/// Display attachment the iPhone already uploaded. Same fields `startChat`
/// sends for an iOS voice note (`PendingAttachment.toJSONValue`).
public struct WatchChatAttachment: Sendable, Equatable {
    public let name: String
    public let path: String
    public let mime: String
    public let size: Int?
    public let isImage: Bool

    public init(name: String, path: String, mime: String, size: Int?, isImage: Bool) {
        self.name = name
        self.path = path
        self.mime = mime
        self.size = size
        self.isImage = isImage
    }
}

/// Phone-owned execution. The broker never talks to `hermes-webui` itself.
public protocol WatchPhoneBackend: Sendable {
    func servers() async -> [WatchPhoneServerAccount]
    func listSessions(urlString: String, archived: Bool, query: String?, limit: Int) async throws -> [WatchPhoneSessionRow]
    func createSession(urlString: String, profileID: String?, workspace: String?) async throws -> String
    func startChat(urlString: String, sessionID: String, message: String) async throws -> String
    func startChat(
        urlString: String,
        sessionID: String,
        message: String,
        attachments: [WatchChatAttachment]?
    ) async throws -> String
    func uploadFile(
        urlString: String,
        sessionID: String,
        data: Data,
        filename: String
    ) async throws -> WatchChatAttachment
    func cancelChat(urlString: String, streamID: String) async throws
    func transcript(urlString: String, sessionID: String, before: Int?, limit: Int) async throws -> WatchPhoneTranscriptPage
    func runPhase(urlString: String, sessionID: String, streamID: String) async throws -> (phase: WatchRunPhase, isTerminal: Bool)
    func transcribeAudio(urlString: String, data: Data, filename: String) async throws -> String
    func mediaData(urlString: String, sessionID: String, path: String) async throws -> Data
}

public extension WatchPhoneBackend {
    func startChat(
        urlString: String,
        sessionID: String,
        message: String,
        attachments: [WatchChatAttachment]?
    ) async throws -> String {
        try await startChat(urlString: urlString, sessionID: sessionID, message: message)
    }

    func uploadFile(
        urlString: String,
        sessionID: String,
        data: Data,
        filename: String
    ) async throws -> WatchChatAttachment {
        throw WatchCompanionError.backend(.invalidResponse)
    }

    func mediaData(urlString: String, sessionID: String, path: String) async throws -> Data {
        throw WatchCompanionError.unsupported(.media)
    }
}
