import Foundation
import Testing
@testable import WatchShared
@Suite struct ExtendedRouteTests{
 private func fixture()throws->(ServerScope,SessionKey){let s=ServerScope(epoch:InstallationEpoch(rawValue:UUID()),server:ServerID(rawValue:UUID()),generation:try Generation(1));return(s,try SessionKey(scope:s,sessionID:"s"))}
 @Test func typedRouteFamiliesRoundTripAndValidateNestedScope()throws{let(s,k)=try fixture();let n=Date();let targets:[WatchRouteTarget]=[.home,.sessions(collection:.current),.session(k,destination:.detail),.git(k,pathHandle:nil,diffKind:.staged,destination:.browse),.settings(s,destination:.watchSharing)];for target in targets{let r=try WatchHandoffRoute(routeID:UUID(),scope:s,target:target,createdAt:n,expiresAt:n.addingTimeInterval(60));#expect(try WatchHandoffRoute.decode(r.canonicalJSONData())==r)}}
 @Test func botDestinationCompatibilityIsExact()throws{let(s,_)=try fixture();let b=try BotKey(scope:s,connectionID:UUID(),profile:"p");let n=Date();_ = try WatchHandoffRoute(routeID:UUID(),scope:s,target:.bot(b,destination:.activity,requestID:"real"),createdAt:n,expiresAt:n.addingTimeInterval(60));#expect(throws:(any Error).self){try WatchHandoffRoute(routeID:UUID(),scope:s,target:.bot(b,destination:.conversation,requestID:"not-allowed"),createdAt:n,expiresAt:n.addingTimeInterval(60))}}
}
