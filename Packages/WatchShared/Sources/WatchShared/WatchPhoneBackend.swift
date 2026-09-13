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
        public let id: String
        public let role: WatchMessageRole
        public let text: String

        public init(id: String, role: WatchMessageRole, text: String) {
            self.id = id
            self.role = role
            self.text = text
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
}
