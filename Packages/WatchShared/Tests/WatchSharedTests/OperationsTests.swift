import Foundation
import Testing
@testable import WatchShared
@Suite struct OperationsTests {
 private func s()throws->ServerScope{ServerScope(epoch:InstallationEpoch(rawValue:UUID()),server:ServerID(rawValue:UUID()),generation:try Generation(1))}
 @Test func allOperationsHaveOneToOneKindsAndRoundTrip()throws{let scope=try s();let session=try SessionKey(scope:scope,sessionID:"s");let run=try RunKey(session:session,streamID:"r");let reads:[WatchReadOperation]=[.sessions(scope:scope,collection:.current,query:nil,localLimit:10),.transcript(session:session,before:nil,limit:50),.runState(run:run),.diagnostics(scope:scope)];#expect(reads.map(\.kind)==[.sessions,.transcript,.runState,.diagnostics]);for value in reads{#expect(try JSONDecoder().decode(WatchReadOperation.self,from:JSONEncoder().encode(value))==value)};#expect(WatchStreamOperation.run(run,afterEventID:nil).kind == .runStream)}
}
