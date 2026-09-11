import Foundation
import Testing
@testable import WatchShared

@Suite struct CommandsTests {
    private func fixture() throws -> (ServerScope, SessionKey) { let s=ServerScope(epoch:InstallationEpoch(rawValue:UUID()),server:ServerID(rawValue:UUID()),generation:try Generation(1)); return(s,try SessionKey(scope:s,sessionID:"s")) }
    @Test func commandContextValidatesLifetimeAndDecoding() throws { let (s,_)=try fixture();let now=Date();let value=try CommandContext(stableCommandID:CommandID(rawValue:UUID()),scope:s,expectedRevision:Revision(1),createdAt:now,expiresAt:now.addingTimeInterval(60));#expect(try JSONDecoder().decode(CommandContext.self,from:JSONEncoder().encode(value))==value);#expect(throws:(any Error).self){try CommandContext(stableCommandID:CommandID(rawValue:UUID()),scope:s,expectedRevision:Revision(1),createdAt:now,expiresAt:now)} }
    @Test func mutationCasesIncludeDisabledAttentionAsDomainOnly() throws { let(s,key)=try fixture();let a=try ApprovalKey(session:key,remoteID:"a");let c=try ClarificationKey(session:key,remoteID:"c");let cases:[WatchMutationOperation]=[.createSession(scope:s,profileID:nil,workspaceHandle:nil),.send(session:key,text:"hello"),.respondApproval(approval:a,choice:.once),.respondClarification(clarification:c,answer:"answer")];#expect(cases.map(\.kind)==[.createSession,.send,.respondApproval,.respondClarification]);#expect(WatchMutationOperation.currentlyEnabledKinds.contains(.respondApproval)==false);#expect(WatchMutationOperation.currentlyEnabledKinds.contains(.respondClarification)==false) }
}
