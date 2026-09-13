import Foundation
import WatchConnectivity
import WatchShared

/// iPhone WCSession host. Decodes watch envelopes and runs them on the broker.
final class PhoneWatchConnectivityHost: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = PhoneWatchConnectivityHost()

    private let dispatcher: WatchWireDispatcher
    private let voiceInbox = WatchVoiceNoteFileInbox()

    override private init() {
        let broker = PhoneCompanionBroker(
            epoch: WatchInstallationIdentity.epoch(),
            backend: APIClientWatchPhoneBackend()
        )
        dispatcher = WatchWireDispatcher(service: broker) { request in
            await broker.sendVoiceNote(request)
        }
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard let data = message["data"] as? Data else {
            replyHandler(["error": "invalidEnvelope"])
            return
        }
        Task {
            let reply = await handle(data)
            replyHandler(["data": reply])
        }
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let raw = file.metadata?[WatchVoiceNoteWire.fileTransferMetadataKey] as? String,
              let transferID = UUID(uuidString: raw),
              let data = try? Data(contentsOf: file.fileURL),
              !data.isEmpty,
              data.count <= WatchVoiceNoteRequest.maximumAudioBytes
        else {
            return
        }
        Task { await voiceInbox.deposit(transferID: transferID, data: data) }
    }

    private func handle(_ data: Data) async -> Data {
        do {
            let message = try JSONDecoder().decode(WatchWireMessage.self, from: data)
            let resolved = await resolveFileHop(message)
            let reply = await dispatcher.handle(resolved)
            return try JSONEncoder().encode(reply)
        } catch {
            let failure = WatchWireReply.failure(.invalidEnvelope(code: "decodeFailed"))
            return (try? JSONEncoder().encode(failure)) ?? Data()
        }
    }

    private func resolveFileHop(_ message: WatchWireMessage) async -> WatchWireMessage {
        guard case .transcribeFile(let ref) = message else { return message }
        do {
            let audio = try await takeVoiceFile(transferID: ref.transferID)
            return .transcribe(try ref.makeRequest(audio: audio))
        } catch {
            return message
        }
    }

    private func takeVoiceFile(transferID: UUID) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { try await self.voiceInbox.take(transferID: transferID) }
            group.addTask {
                try await Task.sleep(for: .seconds(45))
                await self.voiceInbox.fail(
                    transferID: transferID,
                    error: WatchCompanionError.phoneUnavailable
                )
                throw WatchCompanionError.phoneUnavailable
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
