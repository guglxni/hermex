import Foundation

public enum PrivateExchangeValidationError: Error, Equatable, Sendable { case unsupportedSchema, invalidDates, scopeMismatch, incompatiblePurpose, incompatiblePayload, identityMismatch, blankPayload, tooLarge }
public enum PrivateExchangeKind: String, Hashable, Codable, Sendable { case consumeDraft, resolveDirectPath }
public enum PrivateExchangePurpose: String, Hashable, Codable, Sendable { case newSessionDraft, clarificationDraft, directPathHandoff }
public enum PrivateExchangeIdentity: Hashable, Codable, Sendable {
    case draft(scope: ServerScope, handle: DraftHandle)
    case directPath(session: SessionKey, handle: PathHandle)
    public var scope: ServerScope { switch self { case .draft(let scope, _): return scope; case .directPath(let session, _): return session.scope } }
}

public struct PrivateExchangeRequest: Hashable, Codable, Sendable {
    public let schemaVersion: UInt16; public let requestID: UUID; public let scope: ServerScope; public let kind: PrivateExchangeKind; public let purpose: PrivateExchangePurpose; public let identity: PrivateExchangeIdentity; public let createdAt: Date; public let expiresAt: Date
    public init(requestID: UUID, scope: ServerScope, kind: PrivateExchangeKind, purpose: PrivateExchangePurpose, identity: PrivateExchangeIdentity, createdAt: Date, expiresAt: Date) throws {
        guard scope == identity.scope else { throw PrivateExchangeValidationError.scopeMismatch }
        guard createdAt.timeIntervalSinceReferenceDate.isFinite, expiresAt.timeIntervalSinceReferenceDate.isFinite, createdAt < expiresAt, expiresAt.timeIntervalSince(createdAt) <= 300 else { throw PrivateExchangeValidationError.invalidDates }
        switch (kind, purpose, identity) { case (.consumeDraft, .newSessionDraft, .draft), (.consumeDraft, .clarificationDraft, .draft), (.resolveDirectPath, .directPathHandoff, .directPath): break; default: throw PrivateExchangeValidationError.incompatiblePurpose }
        schemaVersion = 1; self.requestID = requestID; self.scope = scope; self.kind = kind; self.purpose = purpose; self.identity = identity; self.createdAt = createdAt; self.expiresAt = expiresAt
    }
    private enum CodingKeys: String, CodingKey { case schemaVersion, requestID, scope, kind, purpose, identity, createdAt, expiresAt }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(UInt16.self, forKey: .schemaVersion) == 1 else { throw PrivateExchangeValidationError.unsupportedSchema }
        try self.init(requestID: c.decode(UUID.self, forKey: .requestID), scope: c.decode(ServerScope.self, forKey: .scope), kind: c.decode(PrivateExchangeKind.self, forKey: .kind), purpose: c.decode(PrivateExchangePurpose.self, forKey: .purpose), identity: c.decode(PrivateExchangeIdentity.self, forKey: .identity), createdAt: c.decode(Date.self, forKey: .createdAt), expiresAt: c.decode(Date.self, forKey: .expiresAt))
    }
}

public enum PrivateExchangePayload: Hashable, Codable, Sendable { case draft(handle: DraftHandle, text: String); case canonicalPath(session: SessionKey, handle: PathHandle, path: String); case failure(identity: PrivateExchangeIdentity, code: String) }

public struct PrivateExchangeResult: Hashable, Codable, Sendable {
    public let schemaVersion: UInt16; public let requestID: UUID; public let scope: ServerScope; public let requestKind: PrivateExchangeKind; public let requestPurpose: PrivateExchangePurpose; public let requestIdentity: PrivateExchangeIdentity; public let requestCreatedAt: Date; public let requestExpiresAt: Date; public let payload: PrivateExchangePayload
    public init(request: PrivateExchangeRequest, payload: PrivateExchangePayload) throws {
        try Self.validate(request: request, payload: payload)
        schemaVersion = 1; requestID = request.requestID; scope = request.scope; requestKind = request.kind; requestPurpose = request.purpose; requestIdentity = request.identity; requestCreatedAt = request.createdAt; requestExpiresAt = request.expiresAt; self.payload = payload
    }
    private static func validate(request: PrivateExchangeRequest, payload: PrivateExchangePayload) throws {
        switch (request.kind, request.identity, payload) {
        case (.consumeDraft, .draft(_, let expected), .draft(let actual, let text)) where expected == actual:
            guard !text.isEmpty else { throw PrivateExchangeValidationError.blankPayload }; guard text.utf8.count <= 16_384 else { throw PrivateExchangeValidationError.tooLarge }
        case (.resolveDirectPath, .directPath(let session, let expected), .canonicalPath(let actualSession, let actualHandle, let path)) where session == actualSession && expected == actualHandle:
            guard !path.isEmpty else { throw PrivateExchangeValidationError.blankPayload }; guard path.utf8.count <= 16_384 else { throw PrivateExchangeValidationError.tooLarge }
        case (_, let identity, .failure(let actual, let code)) where identity == actual:
            guard !code.allSatisfy(\.isWhitespace) else { throw PrivateExchangeValidationError.blankPayload }; guard code.utf8.count <= 256 else { throw PrivateExchangeValidationError.tooLarge }
        default: throw PrivateExchangeValidationError.identityMismatch
        }
    }
    private enum CodingKeys: String, CodingKey { case schemaVersion, requestID, scope, requestKind, requestPurpose, requestIdentity, requestCreatedAt, requestExpiresAt, payload }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(UInt16.self, forKey: .schemaVersion) == 1 else { throw PrivateExchangeValidationError.unsupportedSchema }
        let request = try PrivateExchangeRequest(requestID: c.decode(UUID.self, forKey: .requestID), scope: c.decode(ServerScope.self, forKey: .scope), kind: c.decode(PrivateExchangeKind.self, forKey: .requestKind), purpose: c.decode(PrivateExchangePurpose.self, forKey: .requestPurpose), identity: c.decode(PrivateExchangeIdentity.self, forKey: .requestIdentity), createdAt: c.decode(Date.self, forKey: .requestCreatedAt), expiresAt: c.decode(Date.self, forKey: .requestExpiresAt))
        try self.init(request: request, payload: c.decode(PrivateExchangePayload.self, forKey: .payload))
    }
}
