import Foundation

enum DTOValidationError: Error, Equatable {
    case blank
    case tooLong
    case tooLarge
    case tooManyItems
    case invalidLimit
    case invalidCount
    case invalidDate
    case scopeMismatch
    case invalidSize
    case invalidDigest
}

private func dtoString(_ value: String, max: Int = ContractLimits.identifierUTF8Bytes, allowEmpty: Bool = false) throws -> String {
    if !allowEmpty && value.allSatisfy(\.isWhitespace) { throw DTOValidationError.blank }
    if value.utf8.count > max { throw DTOValidationError.tooLong }
    return value
}
private func dtoDate(_ value: Date) throws -> Date { guard value.timeIntervalSinceReferenceDate.isFinite else { throw DTOValidationError.invalidDate }; return value }

public enum WatchAuthMode: String, Hashable, Codable, Sendable { case none, password, trustedHeader, oidc, passkey, unknown }
public enum DirectAccessState: String, Hashable, Codable, Sendable { case notConfigured, provisioning, available, revocationPending, authRequired, unavailable }
public enum SessionCollection: String, Hashable, Codable, Sendable { case current, archived }
public enum WatchMessageRole: String, Hashable, Codable, Sendable { case user, assistant, system }
public enum WatchRunPhase: String, Hashable, Codable, Sendable { case starting, thinking, tool, searching, files, command, responding, attention, completed, failed, stopped, unknown }
public enum ApprovalChoice: String, Hashable, Codable, CaseIterable, Sendable { case once, session, always, deny }
public enum TaskControl: String, Hashable, Codable, Sendable { case run, pause, resume }
public enum GitDiffKind: String, Hashable, Codable, Sendable { case workingTree, staged }
public enum BotPhoneDestination: String, Hashable, Codable, Sendable { case conversation, activity, historyUnavailable }
public enum AlertSource: String, Hashable, Codable, Sendable { case foregroundRefresh, brokerSnapshot, localSchedule }
public enum AlertKind: String, Hashable, Codable, Sendable { case approvalHead, clarificationHead, runTerminal, taskFailure, taskDue, serverDisconnected }

public struct PageRequest: Hashable, Codable, Sendable {
    public let continuation: String?; public let limit: Int
    public init(continuation: String?, limit: Int) throws { if !(1...50).contains(limit) { throw DTOValidationError.invalidLimit }; if let continuation { _ = try dtoString(continuation) }; self.continuation = continuation; self.limit = limit }
    private enum CodingKeys: String, CodingKey { case continuation, limit }
    public init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); try self.init(continuation: c.decodeIfPresent(String.self, forKey: .continuation), limit: c.decode(Int.self, forKey: .limit)) }
}

public struct BoundedPage<Item: Hashable & Codable & Sendable>: Hashable, Codable, Sendable {
    public let items: [Item]; public let continuation: String?; public let isTruncated: Bool
    public init(items: [Item], continuation: String?, isTruncated: Bool, maximumItems: Int = 256) throws { guard maximumItems >= 0, items.count <= maximumItems else { throw DTOValidationError.tooManyItems }; if let continuation { _ = try dtoString(continuation) }; self.items = items; self.continuation = continuation; self.isTruncated = isTruncated }
    private enum CodingKeys: String, CodingKey { case items, continuation, isTruncated }
    public init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); try self.init(items: c.decode([Item].self, forKey: .items), continuation: c.decodeIfPresent(String.self, forKey: .continuation), isTruncated: c.decode(Bool.self, forKey: .isTruncated)) }
}

public struct BoundedCollection<Item: Hashable & Codable & Sendable>: Hashable, Codable, Sendable {
    public let items: [Item]; public let isTruncated: Bool
    public init(items: [Item], isTruncated: Bool, maximumItems: Int = 256) throws { guard maximumItems >= 0, items.count <= maximumItems else { throw DTOValidationError.tooManyItems }; self.items = items; self.isTruncated = isTruncated }
    private enum CodingKeys: String, CodingKey { case items, isTruncated }
    public init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); try self.init(items: c.decode([Item].self, forKey: .items), isTruncated: c.decode(Bool.self, forKey: .isTruncated)) }
}

public struct WatchServerDescriptor: Hashable, Codable, Sendable {
    public let scope: ServerScope; public let displayName: RedactedDisplayName; public let authMode: WatchAuthMode; public let directState: DirectAccessState
    public init(scope: ServerScope, displayName: RedactedDisplayName, authMode: WatchAuthMode, directState: DirectAccessState) { self.scope = scope; self.displayName = displayName; self.authMode = authMode; self.directState = directState }
}

public struct WatchSessionSummary: Hashable, Codable, Sendable {
    public let key: SessionKey; public let title: String; public let profile: String?; public let workspaceLabel: String?; public let updatedAt: Date?; public let isPinned: Bool; public let isArchived: Bool; public let attention: Bool; public let runState: WatchRunPhase?
    public init(key: SessionKey, title: String, profile: String?, workspaceLabel: String?, updatedAt: Date?, isPinned: Bool, isArchived: Bool, attention: Bool, runState: WatchRunPhase?) throws { self.key = key; self.title = try dtoString(title, max: 1024); self.profile = try profile.map { try dtoString($0) }; self.workspaceLabel = try workspaceLabel.map { try dtoString($0) }; self.updatedAt = try updatedAt.map(dtoDate); self.isPinned = isPinned; self.isArchived = isArchived; self.attention = attention; self.runState = runState }
}

public struct WatchComposerOptions: Hashable, Codable, Sendable {
    public struct ProfileChoice: Hashable, Codable, Sendable { public let id: ProfileID; public let label: String; public init(id: ProfileID, label: String) throws { self.id = id; self.label = try dtoString(label) } }
    public struct WorkspaceChoice: Hashable, Codable, Sendable { public let handle: WorkspaceHandle; public let label: String; public init(handle: WorkspaceHandle, label: String) throws { self.handle = handle; self.label = try dtoString(label) } }
    public let scope: ServerScope; public let profiles: [ProfileChoice]; public let workspaces: [WorkspaceChoice]; public let defaultProfileID: ProfileID?; public let defaultWorkspaceHandle: WorkspaceHandle?
    public init(scope: ServerScope, profiles: [ProfileChoice], workspaces: [WorkspaceChoice], defaultProfileID: ProfileID?, defaultWorkspaceHandle: WorkspaceHandle?) throws { guard profiles.count <= 128, workspaces.count <= 128 else { throw DTOValidationError.tooManyItems }; self.scope = scope; self.profiles = profiles; self.workspaces = workspaces; self.defaultProfileID = defaultProfileID; self.defaultWorkspaceHandle = defaultWorkspaceHandle }
}

public enum WatchTranscriptBlock: Hashable, Codable, Sendable {
    case text(id: String, role: WatchMessageRole, text: String)
    case code(id: String, language: String?, text: String, isTruncated: Bool)
    case tool(id: String, title: String, state: String, summary: String?)
    case image(id: String, descriptor: WatchMediaDescriptor, alt: String?)
    case unsupported(id: String, kind: String, summary: String)
    fileprivate func validate() throws { let id: String; switch self { case .text(let v, _, let text): id=v; _ = try dtoString(text, max: 16_384, allowEmpty: true); case .code(let v, let language, let text, _): id=v; _ = try language.map { try dtoString($0) }; _ = try dtoString(text, max: 16_384, allowEmpty: true); case .tool(let v, let title, let state, let summary): id=v; _ = try dtoString(title); _ = try dtoString(state); _ = try summary.map { try dtoString($0, max: 2048) }; case .image(let v, _, let alt): id=v; _ = try alt.map { try dtoString($0, max: 1024) }; case .unsupported(let v, let kind, let summary): id=v; _ = try dtoString(kind); _ = try dtoString(summary, max: 2048) }; _ = try dtoString(id) }
}

public struct WatchTranscript: Hashable, Codable, Sendable {
    public let session: SessionKey; public let blocks: [WatchTranscriptBlock]; public let nextBefore: Int?; public let isTruncated: Bool
    public init(session: SessionKey, blocks: [WatchTranscriptBlock], nextBefore: Int?, isTruncated: Bool) throws { guard blocks.count <= 50 else { throw DTOValidationError.tooManyItems }; if let nextBefore, nextBefore < 0 { throw DTOValidationError.invalidCount }; try blocks.forEach { try $0.validate() }; self.session=session; self.blocks=blocks; self.nextBefore=nextBefore; self.isTruncated=isTruncated }
    private enum CodingKeys: String, CodingKey { case session, blocks, nextBefore, isTruncated }
    public init(from decoder: Decoder) throws { let c=try decoder.container(keyedBy:CodingKeys.self); try self.init(session:c.decode(SessionKey.self,forKey:.session),blocks:c.decode([WatchTranscriptBlock].self,forKey:.blocks),nextBefore:c.decodeIfPresent(Int.self,forKey:.nextBefore),isTruncated:c.decode(Bool.self,forKey:.isTruncated)) }
}

public struct WatchRunState: Hashable, Codable, Sendable { public let key: RunKey; public let phase: WatchRunPhase; public let lastEventID: String?; public let lastSequence: Int?; public let isTerminal: Bool; public let summary: String?; public init(key: RunKey, phase: WatchRunPhase, lastEventID: String?, lastSequence: Int?, isTerminal: Bool, summary: String?) throws { if let lastSequence, lastSequence < 0 { throw DTOValidationError.invalidCount }; self.key=key; self.phase=phase; self.lastEventID=try lastEventID.map{try dtoString($0)}; self.lastSequence=lastSequence; self.isTerminal=isTerminal; self.summary=try summary.map{try dtoString($0,max:2048)} } }
public struct WatchRunEvent: Hashable, Codable, Sendable { public let key: RunKey; public let eventID: String; public let sequence: Int; public let phase: WatchRunPhase; public let textDelta: String?; public let terminal: Bool; public init(key: RunKey,eventID:String,sequence:Int,phase:WatchRunPhase,textDelta:String?,terminal:Bool)throws{guard sequence>=0 else{throw DTOValidationError.invalidCount};self.key=key;self.eventID=try dtoString(eventID);self.sequence=sequence;self.phase=phase;self.textDelta=try textDelta.map{try dtoString($0,max:16_384,allowEmpty:true)};self.terminal=terminal} }

public struct WatchBotApprovalProjection: Hashable, Codable, Sendable { public let requestID:String;public let choices:BoundedCollection<String>?;public let redactedCommand:String?;public let toolName:String?;public let displaySummary:String?;public init(requestID:String,choices:BoundedCollection<String>?,redactedCommand:String?,toolName:String?,displaySummary:String?)throws{self.requestID=try dtoString(requestID);self.choices=choices;self.redactedCommand=try redactedCommand.map{try dtoString($0,max:2048)};self.toolName=try toolName.map{try dtoString($0)};self.displaySummary=try displaySummary.map{try dtoString($0,max:2048)}} }
public struct WatchBotClarificationQuestion: Hashable, Codable, Sendable { public let prompt:String?;public let choices:BoundedCollection<String>?;public init(prompt:String?,choices:BoundedCollection<String>?)throws{self.prompt=try prompt.map{try dtoString($0,max:2048)};self.choices=choices} }
public enum WatchBotClarificationForm: Hashable, Codable, Sendable { case open;case single(WatchBotClarificationQuestion);case batch(BoundedCollection<WatchBotClarificationQuestion>);case questions(BoundedCollection<WatchBotClarificationQuestion>) }
public struct WatchBotClarificationProjection: Hashable, Codable, Sendable { public let requestID:String;public let form:WatchBotClarificationForm;public let displaySummary:String?;public init(requestID:String,form:WatchBotClarificationForm,displaySummary:String?)throws{self.requestID=try dtoString(requestID);self.form=form;self.displaySummary=try displaySummary.map{try dtoString($0,max:2048)}} }

public enum WatchBotActivity: Hashable, Codable, Sendable {
    case sessionInfo(profileName:String,model:String?,provider:String?);case status(kind:String,text:String?);case messageStart;case messageDelta(delta:String);case messageInterim(text:String,alreadyStreamed:Bool);case thinkingDelta(delta:String);case reasoningDelta(delta:String);case reasoningAvailable(text:String);case messageComplete(status:String,content:String,reasoning:String?);case toolStart(toolCallID:String,name:String,summary:String?);case toolUpdate(toolCallID:String,name:String,summary:String?,status:String?);case toolComplete(toolCallID:String,name:String,summary:String?,status:String?,durationSeconds:Double?);case todoUpdated(completed:Int,total:Int,currentTask:String?);case approvalBlocked(WatchBotApprovalProjection);case clarificationBlocked(WatchBotClarificationProjection);case notification(notificationID:String,level:String,message:String);case notificationCleared(notificationID:String);case reviewSummary(summary:String);case sanitizedError(code:String);case unsupported(eventName:String)
}
public struct WatchBotEvent: Hashable, Codable, Sendable { public let key:BotKey;public let replayEpoch:String;public let runtimeSessionID:String;public let sequence:Int;public let activity:WatchBotActivity;public init(key:BotKey,replayEpoch:String,runtimeSessionID:String,sequence:Int,activity:WatchBotActivity)throws{guard sequence>=0 else{throw DTOValidationError.invalidCount};self.key=key;self.replayEpoch=try dtoString(replayEpoch);self.runtimeSessionID=try dtoString(runtimeSessionID);self.sequence=sequence;self.activity=activity} }

public struct WatchApproval: Hashable, Codable, Sendable { public let key:ApprovalKey;public let title:String;public let detail:String?;public let choices:[ApprovalChoice];public let requestedAt:Date?;public init(key:ApprovalKey,title:String,detail:String?,choices:[ApprovalChoice],requestedAt:Date?)throws{guard !choices.isEmpty,choices.count<=4 else{throw DTOValidationError.invalidCount};self.key=key;self.title=try dtoString(title,max:1024);self.detail=try detail.map{try dtoString($0,max:2048)};self.choices=choices;self.requestedAt=try requestedAt.map(dtoDate)} }
public struct WatchClarification: Hashable, Codable, Sendable { public let key:ClarificationKey;public let question:String;public let choices:[String];public let requestedAt:Date?;public init(key:ClarificationKey,question:String,choices:[String],requestedAt:Date?)throws{guard choices.count<=32 else{throw DTOValidationError.tooManyItems};self.key=key;self.question=try dtoString(question,max:4096);self.choices=try choices.map{try dtoString($0,max:1024)};self.requestedAt=try requestedAt.map(dtoDate)} }
public struct WatchAttentionHead<Item:Hashable&Codable&Sendable>:Hashable,Codable,Sendable{public let item:Item?;public let reportedPendingCount:Int?;public init(item:Item?,reportedPendingCount:Int?)throws{if let reportedPendingCount,reportedPendingCount<0{throw DTOValidationError.invalidCount};self.item=item;self.reportedPendingCount=reportedPendingCount}}

public struct WatchTaskSummary:Hashable,Codable,Sendable{public let key:TaskKey;public let name:String;public let schedule:String;public let enabled:Bool;public let running:Bool;public let lastResult:String?;public init(key:TaskKey,name:String,schedule:String,enabled:Bool,running:Bool,lastResult:String?)throws{self.key=key;self.name=try dtoString(name,max:1024);self.schedule=try dtoString(schedule,max:1024);self.enabled=enabled;self.running=running;self.lastResult=try lastResult.map{try dtoString($0,max:2048)}}}
public struct WatchTaskRun:Hashable,Codable,Sendable{public let task:TaskKey;public let runID:String;public let startedAt:Date?;public let finishedAt:Date?;public let status:String;public let output:String?;public let isTruncated:Bool;public init(task:TaskKey,runID:String,startedAt:Date?,finishedAt:Date?,status:String,output:String?,isTruncated:Bool)throws{self.task=task;self.runID=try dtoString(runID);self.startedAt=try startedAt.map(dtoDate);self.finishedAt=try finishedAt.map(dtoDate);if let startedAt,let finishedAt,finishedAt<startedAt{throw DTOValidationError.invalidDate};self.status=try dtoString(status);self.output=try output.map{try dtoString($0,max:16_384,allowEmpty:true)};self.isTruncated=isTruncated}}
public struct WatchTaskRunDetail:Hashable,Codable,Sendable{public let run:WatchTaskRun;public let output:String?;public let outputTruncated:Bool;public init(run:WatchTaskRun,output:String?,outputTruncated:Bool)throws{self.run=run;self.output=try output.map{try dtoString($0,max:262_144,allowEmpty:true)};self.outputTruncated=outputTruncated}}

public struct WatchSkillSummary:Hashable,Codable,Sendable{public let key:SkillKey;public let summary:String;public let enabled:Bool?;public init(key:SkillKey,summary:String,enabled:Bool?)throws{self.key=key;self.summary=try dtoString(summary,max:4096,allowEmpty:true);self.enabled=enabled}}
public struct WatchSkillDetail:Hashable,Codable,Sendable{public struct LinkedFile:Hashable,Codable,Sendable{public let handle:PathHandle;public let name:String;public let byteSize:Int?;public init(handle:PathHandle,name:String,byteSize:Int?)throws{if let byteSize,byteSize<0{throw DTOValidationError.invalidSize};self.handle=handle;self.name=try dtoString(name);self.byteSize=byteSize}};public let key:SkillKey;public let summary:String;public let linkedFiles:BoundedCollection<LinkedFile>;public init(key:SkillKey,summary:String,linkedFiles:BoundedCollection<LinkedFile>)throws{self.key=key;self.summary=try dtoString(summary,max:4096,allowEmpty:true);self.linkedFiles=linkedFiles}}
public struct WatchSkillContent:Hashable,Codable,Sendable{public let key:SkillKey;public let fileHandle:PathHandle?;public let content:String;public let isTruncated:Bool;public init(key:SkillKey,fileHandle:PathHandle?,content:String,isTruncated:Bool)throws{self.key=key;self.fileHandle=fileHandle;self.content=try dtoString(content,max:262_144,allowEmpty:true);self.isTruncated=isTruncated}}
public struct WatchMemorySection:Hashable,Codable,Sendable{public let key:MemoryKey;public let section:String;public let redactedContent:String;public let isTruncated:Bool;public init(key:MemoryKey,section:String,redactedContent:String,isTruncated:Bool)throws{self.key=key;self.section=try dtoString(section);self.redactedContent=try dtoString(redactedContent,max:16_384,allowEmpty:true);self.isTruncated=isTruncated}}
public struct WatchMemoryDocument:Hashable,Codable,Sendable{public let sections:[WatchMemorySection];public init(sections:[WatchMemorySection])throws{guard sections.count<=2,Set(sections.map(\.section)).count==sections.count else{throw DTOValidationError.invalidCount};self.sections=sections}}
public struct InsightsDays:Hashable,Codable,Sendable{public let value:Int;public init(_ value:Int)throws{guard(1...365).contains(value)else{throw DTOValidationError.invalidCount};self.value=value};public init(from decoder:Decoder)throws{try self.init(decoder.singleValueContainer().decode(Int.self))};public func encode(to encoder:Encoder)throws{var c=encoder.singleValueContainer();try c.encode(value)}}
public struct WatchInsightsAggregate:Hashable,Codable,Sendable{public let days:InsightsDays;public let totalSessions:Int;public let totalMessages:Int;public let totalInputTokens:Int;public let totalOutputTokens:Int;public let totalTokens:Int;public let totalCost:Decimal;public let models:BoundedCollection<String>;public let dailyTokens:BoundedCollection<Int>;public let activityByDay:BoundedCollection<Int>;public let activityByHour:BoundedCollection<Int>;public init(days:InsightsDays,totalSessions:Int,totalMessages:Int,totalInputTokens:Int,totalOutputTokens:Int,totalTokens:Int,totalCost:Decimal,models:BoundedCollection<String>,dailyTokens:BoundedCollection<Int>,activityByDay:BoundedCollection<Int>,activityByHour:BoundedCollection<Int>)throws{guard [totalSessions,totalMessages,totalInputTokens,totalOutputTokens,totalTokens].allSatisfy({$0>=0}) else{throw DTOValidationError.invalidCount};self.days=days;self.totalSessions=totalSessions;self.totalMessages=totalMessages;self.totalInputTokens=totalInputTokens;self.totalOutputTokens=totalOutputTokens;self.totalTokens=totalTokens;self.totalCost=totalCost;self.models=models;self.dailyTokens=dailyTokens;self.activityByDay=activityByDay;self.activityByHour=activityByHour}}

public struct WatchWorkspaceEntry:Hashable,Codable,Sendable{public enum Kind:String,Hashable,Codable,Sendable{case directory,text,image,binary,unknown};public let session:SessionKey;public let pathHandle:PathHandle;public let name:String;public let kind:Kind;public let byteSize:Int?;public init(session:SessionKey,pathHandle:PathHandle,name:String,kind:Kind,byteSize:Int?)throws{if let byteSize,byteSize<0{throw DTOValidationError.invalidSize};self.session=session;self.pathHandle=pathHandle;self.name=try dtoString(name);self.kind=kind;self.byteSize=byteSize}}
public enum WatchFilePreview:Hashable,Codable,Sendable{case text(pathHandle:PathHandle,text:String,isTruncated:Bool);case image(pathHandle:PathHandle,media:WatchMediaDescriptor);case unsupported(pathHandle:PathHandle,kind:String)}
public struct WatchGitAggregate:Hashable,Codable,Sendable{public let session:SessionKey;public let branch:String?;public let isRepository:Bool;public let dirty:Bool;public let modifiedCount:Int;public let untrackedCount:Int;public let ahead:Int;public let behind:Int;public init(session:SessionKey,branch:String?,isRepository:Bool,dirty:Bool,modifiedCount:Int,untrackedCount:Int,ahead:Int,behind:Int)throws{guard[modifiedCount,untrackedCount,ahead,behind].allSatisfy({$0>=0})else{throw DTOValidationError.invalidCount};self.session=session;self.branch=try branch.map{try dtoString($0)};self.isRepository=isRepository;self.dirty=dirty;self.modifiedCount=modifiedCount;self.untrackedCount=untrackedCount;self.ahead=ahead;self.behind=behind}}
public struct WatchBotSummary:Hashable,Codable,Sendable{public let key:BotKey;public let title:String;public let phase:WatchRunPhase?;public init(key:BotKey,title:String,phase:WatchRunPhase?)throws{self.key=key;self.title=try dtoString(title,max:1024);self.phase=phase}}
public enum WatchBotHistoryAvailability:Hashable,Codable,Sendable{case complete;case unavailableOversize(limit:Int)}
public struct WatchBotConversation:Hashable,Codable,Sendable{public let key:BotKey;public let blocks:[WatchTranscriptBlock];public let replayEpoch:String;public let lastSequence:Int?;public let phase:WatchRunPhase?;public let history:WatchBotHistoryAvailability;public init(key:BotKey,blocks:[WatchTranscriptBlock],replayEpoch:String,lastSequence:Int?,phase:WatchRunPhase?,history:WatchBotHistoryAvailability)throws{guard blocks.count<=50,(lastSequence ?? 0)>=0 else{throw DTOValidationError.invalidCount};try blocks.forEach{try $0.validate()};self.key=key;self.blocks=blocks;self.replayEpoch=try dtoString(replayEpoch);self.lastSequence=lastSequence;self.phase=phase;self.history=history}}

public struct WatchMediaDescriptor:Hashable,Codable,Sendable{public let scope:ServerScope;public let session:SessionKey;public let origin:OriginBinding;public let handle:MediaHandle;public let mimeType:String;public let byteSize:Int;public let sha256:String;public let observedAt:Date;public let expiresAt:Date;public init(scope:ServerScope,session:SessionKey,origin:OriginBinding,handle:MediaHandle,mimeType:String,byteSize:Int,sha256:String,observedAt:Date,expiresAt:Date)throws{guard session.scope==scope else{throw DTOValidationError.scopeMismatch};guard(0...1_048_576).contains(byteSize)else{throw DTOValidationError.invalidSize};guard sha256.count==64,sha256.allSatisfy({$0.isHexDigit})else{throw DTOValidationError.invalidDigest};guard try dtoDate(expiresAt)>dtoDate(observedAt)else{throw DTOValidationError.invalidDate};self.scope=scope;self.session=session;self.origin=origin;self.handle=handle;self.mimeType=try dtoString(mimeType);self.byteSize=byteSize;self.sha256=sha256;self.observedAt=observedAt;self.expiresAt=expiresAt}}
public struct WatchMediaPayload:Hashable,Codable,Sendable{public let descriptor:WatchMediaDescriptor;public let bytes:Data;public init(descriptor:WatchMediaDescriptor,bytes:Data)throws{guard bytes.count==descriptor.byteSize,bytes.count<=1_048_576 else{throw DTOValidationError.invalidSize};self.descriptor=descriptor;self.bytes=bytes}}
public enum WatchAlertRoute:Hashable,Codable,Sendable{case attention(ServerScope);case run(RunKey);case task(TaskKey);case diagnostics(ServerScope)}
public struct WatchAlertProjection:Hashable,Codable,Sendable{public let scope:ServerScope;public let alertID:UUID;public let kind:AlertKind;public let dedupeKey:String;public let source:AlertSource;public let observedAt:Date;public let expiresAt:Date;public let route:WatchAlertRoute;public let genericTitleCode:String;public let genericBodyCode:String;public init(scope:ServerScope,alertID:UUID,kind:AlertKind,dedupeKey:String,source:AlertSource,observedAt:Date,expiresAt:Date,route:WatchAlertRoute,genericTitleCode:String,genericBodyCode:String)throws{guard try dtoDate(expiresAt)>dtoDate(observedAt)else{throw DTOValidationError.invalidDate};self.scope=scope;self.alertID=alertID;self.kind=kind;self.dedupeKey=try dtoString(dedupeKey);self.source=source;self.observedAt=observedAt;self.expiresAt=expiresAt;self.route=route;self.genericTitleCode=try dtoString(genericTitleCode);self.genericBodyCode=try dtoString(genericBodyCode)}}
