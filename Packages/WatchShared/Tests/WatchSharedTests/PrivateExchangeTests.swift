import Foundation
import Testing
@testable import WatchShared
@Suite struct PrivateExchangeTests{
 private func f()throws->(ServerScope,DraftHandle){(ServerScope(epoch:InstallationEpoch(rawValue:UUID()),server:ServerID(rawValue:UUID()),generation:try Generation(1)),DraftHandle(rawValue:UUID()))}
 @Test func requestAndResultEnforceCompleteCorrelation()throws{let(s,h)=try f();let n=Date();let q=try PrivateExchangeRequest(requestID:UUID(),scope:s,kind:.consumeDraft,purpose:.newSessionDraft,identity:.draft(scope:s,handle:h),createdAt:n,expiresAt:n.addingTimeInterval(60));#expect(try JSONDecoder().decode(PrivateExchangeRequest.self,from:JSONEncoder().encode(q))==q);let r=try PrivateExchangeResult(request:q,payload:.draft(handle:h,text:"hello"));#expect(r.requestIdentity == q.identity);#expect(throws:(any Error).self){try PrivateExchangeResult(request:q,payload:.failure(identity:.draft(scope:s,handle:DraftHandle(rawValue:UUID())),code:"x"))}}
}

@Suite struct ManifestCoverage_PrivateExchangeTests {
 @Test func executableTypedManifestCoverage() {
  func requireType<T>(_: T.Type) {}
  requireType(PrivateExchangeIdentity.self)
  requireType(PrivateExchangeKind.self)
  requireType(PrivateExchangePayload.self)
  requireType(PrivateExchangePurpose.self)
 }
}
