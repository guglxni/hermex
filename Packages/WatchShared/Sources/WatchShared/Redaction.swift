import Foundation
public enum SourceTextCategory:String,Hashable,Codable,Sendable{case chat,command,question,answer,path,backendError}
public enum RedactionContext:String,Hashable,Codable,Sendable{case route,widget,diagnostics,receipt,log}
public enum WatchRedactor{
 public static func fixedPlaceholder(for category:SourceTextCategory)->String{switch category{case .chat:return"Private chat content";case .command:return"Private command";case .question:return"Private question";case .answer:return"Private answer";case .path:return"Private path";case .backendError:return"Private server error"}}
 public static func displayName(aliasIndex:Int)throws->RedactedDisplayName{guard aliasIndex>=0 else{throw DTOValidationError.invalidCount};return try RedactedDisplayName("Server\(aliasIndex+1)")}
 public static func validateNonSecretProjection(_ data:Data,context:RedactionContext)throws{
  let limit:Int
  switch context{case .route:limit=ContractLimits.routeJSONBytes;case .widget:limit=ContractLimits.widgetJSONBytes;case .diagnostics,.receipt,.log:limit=16384}
  guard data.count<=limit,let string=String(data:data,encoding:.utf8)else{throw DTOValidationError.tooLarge}
  guard !string.unicodeScalars.contains(where:{$0.value<32||$0.value==127})else{throw DTOValidationError.tooLarge}
  let lower=string.lowercased()
  let forbidden=["http://","https://","cookie","authorization","set-cookie","password","secret","/users/","\\users\\","u01c_secret_canary"]
  let permittedClientCodes=["attentionexactidunavailable"]
  guard !forbidden.contains(where:{lower.contains($0) && !permittedClientCodes.contains(where:lower.contains)})else{throw DTOValidationError.tooLarge}
 }
}
