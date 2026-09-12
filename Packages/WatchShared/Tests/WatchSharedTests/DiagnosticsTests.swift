import Foundation
import Testing
@testable import WatchShared
@Suite struct DiagnosticsTests{
 @Test func diagnosticsValidateDatesScopeAndRoundTrip()throws{let s=ServerScope(epoch:InstallationEpoch(rawValue:UUID()),server:ServerID(rawValue:UUID()),generation:try Generation(1));let n=Date();let v=try WatchDiagnosticsProjection(scope:s,source:.direct,observedAt:n,expiresAt:n.addingTimeInterval(60),codes:[.tls,.dns]);#expect(try JSONDecoder().decode(WatchDiagnosticsProjection.self,from:JSONEncoder().encode(v))==v);#expect(throws:(any Error).self){try WatchDiagnosticsProjection(scope:s,source:.snapshot,observedAt:n,expiresAt:n,codes:[])}}
}

@Suite struct ManifestCoverage_DiagnosticsTests {
 @Test func executableTypedManifestCoverage() {
  func requireType<T>(_: T.Type) {}
  requireType(DiagnosticsSource.self)
  requireType(SanitizedDiagnosticCode.self)
 }
}
