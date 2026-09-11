import Foundation
import Testing
@testable import WatchShared
@Suite struct TransportEnvelopeTests{
 private func f()throws->(ServerScope,SessionKey,CommandContext){let s=ServerScope(epoch:InstallationEpoch(rawValue:UUID()),server:ServerID(rawValue:UUID()),generation:try Generation(1));let k=try SessionKey(scope:s,sessionID:"s");let n=Date();return(s,k,try CommandContext(stableCommandID:CommandID(rawValue:UUID()),scope:s,expectedRevision:Revision(1),createdAt:n,expiresAt:n.addingTimeInterval(60)))}
 @Test func mutationEnvelopeDerivesKindDatesAndScope()throws{let(_,k,c)=try f();let v=try WatchMutationRequest(requestID:UUID(),context:c,operation:.send(session:k,text:"hi"),createdAt:c.createdAt,expiresAt:c.expiresAt);#expect(v.operationKind == .send);#expect(try JSONDecoder().decode(WatchMutationRequest.self,from:JSONEncoder().encode(v))==v);#expect(throws:(any Error).self){try WatchMutationRequest(requestID:UUID(),context:c,operation:.send(session:k,text:"hi"),createdAt:c.createdAt,expiresAt:c.expiresAt.addingTimeInterval(1))}}
 @Test func requestEnvelopeRejectsWrongKind()throws{let(s,_,c)=try f();let v=try WatchRequestEnvelope.read(requestID:UUID(),scope:s,operation:.diagnostics(scope:s),createdAt:c.createdAt,expiresAt:c.expiresAt);#expect(v.operationKind == .diagnostics);#expect(try JSONDecoder().decode(WatchRequestEnvelope.self,from:JSONEncoder().encode(v))==v)}
}
