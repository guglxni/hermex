import Foundation

public enum WatchVoiceNoteValidationError: Error, Equatable, Sendable {
    case invalidFilename
    case audioTooLarge
    case audioEmpty
    case scopeMismatch
}

public struct WatchVoiceNoteRequest: Hashable, Codable, Sendable {
    /// Domain cap for a 5-minute AAC clip at the iPhone encoder. Clips over
    /// `WatchVoiceNoteWire.maximumInlineAudioBytes` use `WCSession.transferFile`.
    public static let maximumAudioBytes = WatchVoiceNoteAudioBudget.maximumAudioBytes

    public let scope: ServerScope
    public let expectedRevision: Revision
    public let session: SessionKey
    public let filename: String
    public let audio: Data

    public init(
        scope: ServerScope,
        expectedRevision: Revision,
        session: SessionKey,
        filename: String,
        audio: Data
    ) throws {
        try WatchVoiceNoteFilename.validate(filename)
        guard session.scope == scope else { throw WatchVoiceNoteValidationError.scopeMismatch }
        guard !audio.isEmpty else { throw WatchVoiceNoteValidationError.audioEmpty }
        guard audio.count <= Self.maximumAudioBytes else { throw WatchVoiceNoteValidationError.audioTooLarge }
        self.scope = scope
        self.expectedRevision = expectedRevision
        self.session = session
        self.filename = filename
        self.audio = audio
    }

    public func fileRef(transferID: UUID) throws -> WatchVoiceNoteFileRef {
        try WatchVoiceNoteFileRef(
            transferID: transferID,
            scope: scope,
            expectedRevision: expectedRevision,
            session: session,
            filename: filename,
            audioByteCount: audio.count
        )
    }
}

/// Header sent over `sendMessage` after the AAC bytes travel through `transferFile`.
public struct WatchVoiceNoteFileRef: Hashable, Codable, Sendable {
    public let transferID: UUID
    public let scope: ServerScope
    public let expectedRevision: Revision
    public let session: SessionKey
    public let filename: String
    public let audioByteCount: Int

    public init(
        transferID: UUID,
        scope: ServerScope,
        expectedRevision: Revision,
        session: SessionKey,
        filename: String,
        audioByteCount: Int
    ) throws {
        try WatchVoiceNoteFilename.validate(filename)
        guard session.scope == scope else { throw WatchVoiceNoteValidationError.scopeMismatch }
        guard audioByteCount > 0 else { throw WatchVoiceNoteValidationError.audioEmpty }
        guard audioByteCount <= WatchVoiceNoteRequest.maximumAudioBytes else {
            throw WatchVoiceNoteValidationError.audioTooLarge
        }
        self.transferID = transferID
        self.scope = scope
        self.expectedRevision = expectedRevision
        self.session = session
        self.filename = filename
        self.audioByteCount = audioByteCount
    }

    public func makeRequest(audio: Data) throws -> WatchVoiceNoteRequest {
        try WatchVoiceNoteRequest(
            scope: scope,
            expectedRevision: expectedRevision,
            session: session,
            filename: filename,
            audio: audio
        )
    }
}

enum WatchVoiceNoteFilename {
    static func validate(_ filename: String) throws {
        guard filename.hasSuffix(".m4a"),
              filename.utf8.count <= 128,
              !filename.contains(".."),
              !filename.contains("/")
        else {
            throw WatchVoiceNoteValidationError.invalidFilename
        }
    }
}

public enum WatchWireMessage: Hashable, Codable, Sendable {
    case registry
    case request(WatchRequestEnvelope)
    case mutation(WatchMutationRequest)
    case transcribe(WatchVoiceNoteRequest)
    case transcribeFile(WatchVoiceNoteFileRef)
    case sendPhoto(WatchPhotoSendRequest)
    case sendPhotoFile(WatchPhotoFileRef)
}

public enum WatchWireReply: Hashable, Codable, Sendable {
    case registry(RegistrySnapshot)
    case envelope(WatchResponseEnvelope)
    case failure(WatchTransportFailure)
    case transcript(String)
    case startedRun(CommandReceipt<RunKey>)
}

public protocol WatchWireTransporting: Sendable {
    func send(_ message: WatchWireMessage) async throws -> WatchWireReply
}
