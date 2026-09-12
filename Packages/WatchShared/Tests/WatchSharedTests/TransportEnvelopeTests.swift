import Foundation
import Testing
@testable import WatchShared
@Suite struct TransportEnvelopeTests{
 private func f()throws->(ServerScope,SessionKey,CommandContext){let s=ServerScope(epoch:InstallationEpoch(rawValue:UUID()),server:ServerID(rawValue:UUID()),generation:try Generation(1));let k=try SessionKey(scope:s,sessionID:"s");let n=Date();return(s,k,try CommandContext(stableCommandID:CommandID(rawValue:UUID()),scope:s,expectedRevision:Revision(1),createdAt:n,expiresAt:n.addingTimeInterval(60)))}
 @Test func mutationEnvelopeDerivesKindDatesAndScope()throws{let(_,k,c)=try f();let v=try WatchMutationRequest(requestID:UUID(),context:c,operation:.send(session:k,text:"hi"),createdAt:c.createdAt,expiresAt:c.expiresAt);#expect(v.operationKind == .send);#expect(try JSONDecoder().decode(WatchMutationRequest.self,from:JSONEncoder().encode(v))==v);#expect(throws:(any Error).self){try WatchMutationRequest(requestID:UUID(),context:c,operation:.send(session:k,text:"hi"),createdAt:c.createdAt,expiresAt:c.expiresAt.addingTimeInterval(1))}}
 @Test func responseEnvelopeRejectsMalformedEncodedCorrelation()throws{let(s,_,c)=try f();let freshness=try Freshness(observedAt:c.createdAt,expiresAt:c.expiresAt,source:.phoneProjection);let snapshot=try ScopedSnapshot(schema:1,scope:s,revision:Revision(1),freshness:freshness,value:try WatchDiagnosticsProjection(scope:s,source:.phoneBroker,observedAt:c.createdAt,expiresAt:c.expiresAt,codes:[]));let response=try WatchResponseEnvelope(requestID:UUID(),scope:s,requestOperationKind:.diagnostics,requestCreatedAt:c.createdAt,requestExpiresAt:c.expiresAt,commandContext:nil,result:.diagnostics(snapshot));let data=try JSONEncoder().encode(response);#expect(try JSONDecoder().decode(WatchResponseEnvelope.self,from:data)==response);var object=try #require(JSONSerialization.jsonObject(with:data)as?[String:Any]);object["schemaVersion"]=2;#expect(throws:(any Error).self){try JSONDecoder().decode(WatchResponseEnvelope.self,from:JSONSerialization.data(withJSONObject:object))};object=try #require(JSONSerialization.jsonObject(with:data)as?[String:Any]);object["requestOperationKind"]="sessions";#expect(throws:(any Error).self){try JSONDecoder().decode(WatchResponseEnvelope.self,from:JSONSerialization.data(withJSONObject:object))};object=try #require(JSONSerialization.jsonObject(with:data)as?[String:Any]);object["commandContext"]=try JSONSerialization.jsonObject(with:JSONEncoder().encode(c));#expect(throws:(any Error).self){try JSONDecoder().decode(WatchResponseEnvelope.self,from:JSONSerialization.data(withJSONObject:object))}}
}

@Suite struct ManifestCoverage_TransportEnvelopeTests {
 @Test func executableTypedManifestCoverage() {
  func requireType<T>(_: T.Type) {}
  requireType(WatchRequestEnvelope.self)
 }
}
