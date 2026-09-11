import Foundation
import Testing
@testable import WatchShared
@Suite struct OperationResultsTests{
 @Test func resultFamiliesExposeExactKinds()throws{let f=WatchTransportFailure.rejected(status:409,sanitizedCode:"attentionExactIDUnavailable");#expect(WatchOperationResult.failure(f).kind == nil);#expect(WatchOperationResult.mutation(CommandReceipt(receipt:try receipt(),value:EmptyValue())).kind == .controlTask)}
 private func receipt()throws->MutationReceipt{let s=ServerScope(epoch:InstallationEpoch(rawValue:UUID()),server:ServerID(rawValue:UUID()),generation:try Generation(1));let n=Date();let c=try CommandContext(stableCommandID:CommandID(rawValue:UUID()),scope:s,expectedRevision:Revision(1),createdAt:n,expiresAt:n.addingTimeInterval(1));return try MutationReceipt(context:c,operationKind:.controlTask,phase:.acknowledged,updatedAt:n,nonSecretResultID:nil)}
}
