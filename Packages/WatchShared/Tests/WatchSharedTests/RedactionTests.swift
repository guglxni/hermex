import Foundation
import Testing
@testable import WatchShared
@Suite struct RedactionTests{
 @Test func placeholdersAliasesAndCanariesStayBounded()throws{#expect(WatchRedactor.fixedPlaceholder(for:.chat)=="Private chat content");#expect(try WatchRedactor.displayName(aliasIndex:0).rawValue=="Server1");for context in [RedactionContext.route,.widget,.diagnostics,.receipt,.log]{#expect(throws:(any Error).self){try WatchRedactor.validateNonSecretProjection(Data("cookie=secret https://host/path".utf8),context:context)}};#expect(throws:(any Error).self){try WatchRedactor.displayName(aliasIndex:-1)}}
}
