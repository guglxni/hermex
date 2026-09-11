import Foundation

enum CommandValidationError: Error, Equatable { case invalidDate, expired, scopeMismatch, blankPayload, tooLarge }

public struct CommandID: Hashable, Codable, Sendable { public let rawValue: UUID; public init(rawValue: UUID) { self.rawValue = rawValue } }
public struct CommandContext: Hashable, Codable, Sendable {
    public let stableCommandID: CommandID; public let scope: ServerScope; public let expectedRevision: Revision; public let createdAt: Date; public let expiresAt: Date
    public init(stableCommandID:CommandID,scope:ServerScope,expectedRevision:Revision,createdAt:Date,expiresAt:Date)throws{guard createdAt.timeIntervalSinceReferenceDate.isFinite,expiresAt.timeIntervalSinceReferenceDate.isFinite,createdAt<expiresAt else{throw CommandValidationError.invalidDate};self.stableCommandID=stableCommandID;self.scope=scope;self.expectedRevision=expectedRevision;self.createdAt=createdAt;self.expiresAt=expiresAt}
    private enum CodingKeys:String,CodingKey{case stableCommandID,scope,expectedRevision,createdAt,expiresAt}
    public init(from decoder:Decoder)throws{let c=try decoder.container(keyedBy:CodingKeys.self);try self.init(stableCommandID:c.decode(CommandID.self,forKey:.stableCommandID),scope:c.decode(ServerScope.self,forKey:.scope),expectedRevision:c.decode(Revision.self,forKey:.expectedRevision),createdAt:c.decode(Date.self,forKey:.createdAt),expiresAt:c.decode(Date.self,forKey:.expiresAt))}
}
public enum WatchMutationOperation: Hashable, Codable, Sendable {
    case createSession(scope:ServerScope,profileID:ProfileID?,workspaceHandle:WorkspaceHandle?)
    case send(session:SessionKey,text:String);case stop(run:RunKey);case respondApproval(approval:ApprovalKey,choice:ApprovalChoice);case respondClarification(clarification:ClarificationKey,answer:String);case controlTask(task:TaskKey,action:TaskControl);case sendBot(bot:BotKey,text:String);case interruptBot(bot:BotKey)
    public var kind:WatchOperationKind{switch self{case .createSession:return .createSession;case .send:return .send;case .stop:return .stop;case .respondApproval:return .respondApproval;case .respondClarification:return .respondClarification;case .controlTask:return .controlTask;case .sendBot:return .sendBot;case .interruptBot:return .interruptBot}}
    public static let currentlyEnabledKinds:Set<WatchOperationKind>=[.createSession,.send,.stop,.controlTask,.sendBot,.interruptBot]
    public var scope:ServerScope{switch self{case .createSession(let s,_,_):return s;case .send(let k,_):return k.scope;case .stop(let k):return k.session.scope;case .respondApproval(let k,_):return k.session.scope;case .respondClarification(let k,_):return k.session.scope;case .controlTask(let k,_):return k.scope;case .sendBot(let k,_),.interruptBot(let k):return k.scope}}
}
