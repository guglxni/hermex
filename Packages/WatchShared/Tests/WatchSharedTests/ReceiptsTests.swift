import Foundation
import Testing
@testable import WatchShared
@Suite struct ReceiptsTests{
 private func context()throws->CommandContext{let s=ServerScope(epoch:InstallationEpoch(rawValue:UUID()),server:ServerID(rawValue:UUID()),generation:try Generation(1));let n=Date();return try CommandContext(stableCommandID:CommandID(rawValue:UUID()),scope:s,expectedRevision:Revision(1),createdAt:n,expiresAt:n.addingTimeInterval(60))}
 @Test func receiptsValidatePhaseDatesAndRoundTrip()throws{let c=try context();let r=try MutationReceipt(context:c,operationKind:.stop,phase:.dispatching,updatedAt:c.createdAt,nonSecretResultID:nil);let v=CommandReceipt(receipt:r,value:EmptyValue());#expect(try JSONDecoder().decode(CommandReceipt<EmptyValue>.self,from:JSONEncoder().encode(v))==v);#expect(throws:(any Error).self){try MutationReceipt(context:c,operationKind:.stop,phase:.uncertain,updatedAt:c.createdAt.addingTimeInterval(-1),nonSecretResultID:nil)}}
 @Test func failuresAreClosedSanitizedFamilies(){let values:[WatchTransportFailure]=[.definitelyNotSent(code:"offline"),.uncertain(code:"lost"),.rejected(status:409,sanitizedCode:"attentionExactIDUnavailable"),.invalidEnvelope(code:"mismatch")];#expect(values.count==4)}
}
