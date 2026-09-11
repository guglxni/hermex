import Foundation

public struct InstallationEpoch: Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public enum IdentityValidationError: Error, Equatable, Sendable {
    case generationMustBePositive
    case blankIdentifier
    case identifierTooLong(maxUTF8Bytes: Int)
}

public struct Generation: Hashable, Codable, Sendable {
    public let rawValue: UInt64

    public init(_ rawValue: UInt64) throws {
        guard rawValue > 0 else {
            throw IdentityValidationError.generationMustBePositive
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(UInt64.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ServerID: Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct ServerScope: Hashable, Codable, Sendable {
    public let epoch: InstallationEpoch
    public let server: ServerID
    public let generation: Generation

    public init(epoch: InstallationEpoch, server: ServerID, generation: Generation) {
        self.epoch = epoch
        self.server = server
        self.generation = generation
    }
}

public struct Revision: Hashable, Codable, Sendable {
    public let rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(UInt64.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct SessionKey: Hashable, Codable, Sendable {
    public let scope: ServerScope
    public let sessionID: String

    public init(scope: ServerScope, sessionID: String) throws {
        guard !sessionID.allSatisfy(\.isWhitespace) else {
            throw IdentityValidationError.blankIdentifier
        }
        guard sessionID.utf8.count <= ContractLimits.identifierUTF8Bytes else {
            throw IdentityValidationError.identifierTooLong(maxUTF8Bytes: ContractLimits.identifierUTF8Bytes)
        }
        self.scope = scope
        self.sessionID = sessionID
    }

    private enum CodingKeys: String, CodingKey {
        case scope, sessionID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            scope: container.decode(ServerScope.self, forKey: .scope),
            sessionID: container.decode(String.self, forKey: .sessionID)
        )
    }
}

public struct BotKey: Hashable, Codable, Sendable {
    public let scope: ServerScope
    public let connectionID: UUID
    public let profile: String

    public init(scope: ServerScope, connectionID: UUID, profile: String) throws {
        guard !profile.allSatisfy(\.isWhitespace) else {
            throw IdentityValidationError.blankIdentifier
        }
        guard profile.utf8.count <= ContractLimits.profileUTF8Bytes else {
            throw IdentityValidationError.identifierTooLong(maxUTF8Bytes: ContractLimits.profileUTF8Bytes)
        }
        self.scope = scope
        self.connectionID = connectionID
        self.profile = profile
    }

    private enum CodingKeys: String, CodingKey {
        case scope, connectionID, profile
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            scope: container.decode(ServerScope.self, forKey: .scope),
            connectionID: container.decode(UUID.self, forKey: .connectionID),
            profile: container.decode(String.self, forKey: .profile)
        )
    }
}
