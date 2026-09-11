import Foundation
import Testing
@testable import WatchShared
@Suite struct ServiceBoundaryTests{
 @Test func serviceProtocolIsPublicSendableSolelyOwnedAndDoesNotEnableCurrentPinResponses()throws{let _:any Sendable.Type=(any WatchCompanionServicing).self;let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/WatchShared");let files=try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).filter{$0.pathExtension=="swift"};let owners=try files.filter{try String(contentsOf:$0,encoding:.utf8).contains("protocol WatchCompanionServicing")};#expect(owners.map(\.lastPathComponent)==["ServiceBoundary.swift"]);let source=try String(contentsOf:root.appendingPathComponent("ServiceBoundary.swift"),encoding:.utf8);#expect(!source.contains("func respond(approval:"));#expect(!source.contains("func respond(clarification:"))}
}
