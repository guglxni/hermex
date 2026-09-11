import Foundation

public enum RouteValidationError: Error, Equatable, Sendable {
    case tooLarge
    case unsupportedSchema(Int)
}

public enum RedactedRoute: Hashable, Sendable {
    case servers(InstallationEpoch)
    case sessions(ServerScope)
    case session(SessionKey)
    case bot(BotKey)

    public func canonicalJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> RedactedRoute {
        guard data.count <= ContractLimits.routeJSONBytes else {
            throw RouteValidationError.tooLarge
        }
        return try JSONDecoder().decode(Self.self, from: data)
    }
}

extension RedactedRoute: Codable {
    private enum EnvelopeKeys: String, CodingKey { case schema, route }
    private enum RouteKeys: String, CodingKey { case kind, epoch, scope, session, bot }
    private enum Kind: String, Codable { case servers, sessions, session, bot }

    public init(from decoder: Decoder) throws {
        let envelope = try decoder.container(keyedBy: EnvelopeKeys.self)
        let schema = try envelope.decode(Int.self, forKey: .schema)
        guard schema == 1 else { throw RouteValidationError.unsupportedSchema(schema) }
        let container = try envelope.nestedContainer(keyedBy: RouteKeys.self, forKey: .route)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .servers: self = .servers(try container.decode(InstallationEpoch.self, forKey: .epoch))
        case .sessions: self = .sessions(try container.decode(ServerScope.self, forKey: .scope))
        case .session: self = .session(try container.decode(SessionKey.self, forKey: .session))
        case .bot: self = .bot(try container.decode(BotKey.self, forKey: .bot))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var envelope = encoder.container(keyedBy: EnvelopeKeys.self)
        try envelope.encode(1, forKey: .schema)
        var container = envelope.nestedContainer(keyedBy: RouteKeys.self, forKey: .route)
        switch self {
        case .servers(let epoch):
            try container.encode(Kind.servers, forKey: .kind)
            try container.encode(epoch, forKey: .epoch)
        case .sessions(let scope):
            try container.encode(Kind.sessions, forKey: .kind)
            try container.encode(scope, forKey: .scope)
        case .session(let key):
            try container.encode(Kind.session, forKey: .kind)
            try container.encode(key, forKey: .session)
        case .bot(let key):
            try container.encode(Kind.bot, forKey: .kind)
            try container.encode(key, forKey: .bot)
        }
    }
}

public struct CacheKey: Hashable, Sendable {
    public let rawValue: String

    private init(encoded data: Data) {
        self.rawValue = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func scope(_ scope: ServerScope) throws -> Self {
        try encoded(scope)
    }

    public static func session(_ key: SessionKey) throws -> Self {
        try encoded(key)
    }

    public static func bot(_ key: BotKey) throws -> Self {
        try encoded(key)
    }

    private static func encoded<Value: Encodable>(_ value: Value) throws -> Self {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return Self(encoded: try encoder.encode(value))
    }
}
