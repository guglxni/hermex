import Foundation
import WatchShared

/// Phone execution port: scoped `APIClient` calls, never a watch-invented endpoint.
struct APIClientWatchPhoneBackend: WatchPhoneBackend {
    /// The iPhone's active server is listed first; `WatchRootModel` follows that
    /// first entry when the watch has no explicit selection of its own.
    func servers() async -> [WatchPhoneServerAccount] {
        let registry = ServerRegistry.shared
        let active = registry.activeServerID
        return registry.servers
            .sorted { lhs, rhs in
                (lhs.id == active ? 0 : 1) < (rhs.id == active ? 0 : 1)
            }
            .map { WatchPhoneServerAccount(urlString: $0.urlString, displayName: $0.displayName) }
    }

    func listSessions(
        urlString: String,
        archived: Bool,
        query: String?,
        limit: Int
    ) async throws -> [WatchPhoneSessionRow] {
        let client = try client(for: urlString)
        let summaries: [SessionSummary]
        do {
            if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                summaries = try await client.searchSessions(query: query).sessions ?? []
            } else {
                summaries = try await client.sessions(includeArchived: archived).sessions ?? []
            }
        } catch let error as APIError {
            // Surface auth failure distinctly so the watch can say "sign in on
            // iPhone" instead of showing an empty ready surface. Reuses the
            // same 401 mapping APIClient uses everywhere else.
            throw WatchCompanionError.backend(Self.authCode(for: error))
        }
        return summaries
            .filter { archived ? ($0.archived == true) : ($0.archived != true) }
            .prefix(limit)
            .map(Self.row(from:))
    }

    func createSession(urlString: String, profileID: String?, workspace: String?) async throws -> String {
        let created = try await client(for: urlString).createSession(
            workspace: workspace,
            model: nil,
            modelProvider: nil,
            profile: profileID
        )
        guard let sessionID = created.session?.sessionId, !sessionID.isEmpty else {
            throw WatchCompanionError.backend(.invalidResponse)
        }
        return sessionID
    }

    func startChat(urlString: String, sessionID: String, message: String) async throws -> String {
        try await startChat(urlString: urlString, sessionID: sessionID, message: message, attachments: nil)
    }

    func startChat(
        urlString: String,
        sessionID: String,
        message: String,
        attachments: [WatchChatAttachment]?
    ) async throws -> String {
        let payloads = attachments?.map(\.jsonValue)
        let response = try await client(for: urlString).startChat(
            sessionID: sessionID,
            message: message,
            workspace: nil,
            model: nil,
            attachments: payloads
        )
        if let error = response.error, !error.isEmpty {
            throw WatchCompanionError.backend(.invalidResponse)
        }
        guard let streamID = response.streamId, !streamID.isEmpty else {
            throw WatchCompanionError.backend(.invalidResponse)
        }
        return streamID
    }

    func uploadFile(
        urlString: String,
        sessionID: String,
        data: Data,
        filename: String
    ) async throws -> WatchChatAttachment {
        let response = try await client(for: urlString).uploadFile(
            sessionID: sessionID,
            data: data,
            filename: filename
        )
        if let error = response.error, !error.isEmpty {
            throw WatchCompanionError.backend(.invalidResponse)
        }
        guard let path = response.path, !path.isEmpty else {
            throw WatchCompanionError.backend(.invalidResponse)
        }
        let name = response.filename?.trimmingCharacters(in: .whitespacesAndNewlines)
        return WatchChatAttachment(
            name: (name?.isEmpty == false) ? name! : filename,
            path: path,
            mime: response.mime ?? "application/octet-stream",
            size: response.size,
            isImage: response.isImage ?? false
        )
    }

    func cancelChat(urlString: String, streamID: String) async throws {
        _ = try await client(for: urlString).cancelChat(streamID: streamID)
    }

    func transcript(
        urlString: String,
        sessionID: String,
        before: Int?,
        limit: Int
    ) async throws -> WatchPhoneTranscriptPage {
        let detail = try await client(for: urlString).session(
            id: sessionID,
            includeMessages: true,
            messageLimit: limit,
            messageBefore: before
        ).session
        let messages = detail?.messages ?? []
        let blocks = messages.suffix(limit).map { message in
            WatchPhoneTranscriptPage.Block(
                id: message.id,
                role: Self.role(from: message.role),
                text: message.content ?? ""
            )
        }
        return WatchPhoneTranscriptPage(
            blocks: Array(blocks),
            nextBefore: detail?.messagesOffset,
            isTruncated: detail?.messagesTruncated == true
        )
    }

    func transcribeAudio(urlString: String, data: Data, filename: String) async throws -> String {
        let response = try await client(for: urlString).transcribeAudio(data: data, filename: filename)
        if let error = response.error, !error.isEmpty {
            throw WatchCompanionError.backend(.invalidResponse)
        }
        guard let text = response.transcript?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw WatchCompanionError.backend(.invalidResponse)
        }
        return text
    }

    func runPhase(
        urlString: String,
        sessionID: String,
        streamID: String
    ) async throws -> (phase: WatchRunPhase, isTerminal: Bool) {
        let client = try client(for: urlString)
        if let status = try? await client.chatStreamStatus(streamID: streamID) {
            let terminal = status.journal?.terminal == true || status.active == false
            let phase: WatchRunPhase = terminal ? .completed : .responding
            return (phase, terminal)
        }
        let status = try await client.sessionStatus(id: sessionID)
        let streaming = status.isStreaming == true || status.activeStreamId == streamID
        return (streaming ? .responding : .completed, !streaming)
    }

    private func client(for urlString: String) throws -> APIClient {
        guard let url = URL(string: urlString) else {
            throw WatchCompanionError.backend(.invalidResponse)
        }
        let headers = headers(for: urlString)
        return APIClient(baseURL: url, customHeaderProvider: { headers })
    }

    /// Headers resolve by URL because that is what the watch scope maps to; the
    /// active server's live edits come from the store, the rest from their
    /// per-server Keychain scope, so server A's proxy token never reaches server B.
    private func headers(for urlString: String) -> [CustomHeader] {
        if urlString == ServerRegistry.shared.activeServer?.urlString {
            return CustomHeaderStore.shared.snapshot()
        }
        if let stored = try? KeychainStore().load(.customHeaders, scope: urlString) {
            return [CustomHeader].decodeFromStorage(stored)
        }
        return []
    }

    private static func row(from summary: SessionSummary) -> WatchPhoneSessionRow {        WatchPhoneSessionRow(
            sessionID: summary.id,
            title: summary.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled",
            profile: summary.profile,
            workspaceLabel: summary.workspace,
            updatedAt: summary.updatedAt.map { Date(timeIntervalSince1970: $0) }
                ?? summary.lastMessageAt.map { Date(timeIntervalSince1970: $0) },
            isPinned: summary.pinned == true,
            isArchived: summary.archived == true,
            attention: summary.hasPendingUserMessage == true,
            runState: summary.isStreaming == true ? .responding : nil
        )
    }

    private static func role(from raw: String?) -> WatchMessageRole {
        switch raw?.lowercased() {
        case "assistant": return .assistant
        case "system": return .system
        default: return .user
        }
    }

    /// Maps an `APIError` to the sanitized diagnostic code the watch should see.
    /// A 401 (or `.unauthorized`) means the iPhone's session for this server is
    /// gone; the watch must tell the user to sign in on iPhone rather than
    /// present an empty ready surface. Everything else stays a generic failure.
    private static func authCode(for error: APIError) -> SanitizedDiagnosticCode {
        switch error {
        case .unauthorized:
            return .authRequired
        case .http(let status, _) where status == 401:
            return .authRequired
        default:
            return .unknown
        }
    }
}

private extension WatchChatAttachment {
    /// Same object the iOS composer sends as `PendingAttachment.toJSONValue`.
    var jsonValue: JSONValue {
        var object: [String: JSONValue] = [
            "name": .string(name),
            "path": .string(path),
            "mime": .string(mime),
            "is_image": .bool(isImage),
        ]
        if let size {
            object["size"] = .number(Double(size))
        }
        return .object(object)
    }
}

private extension String {
    var nilIfEmpty: String? {
        allSatisfy(\.isWhitespace) ? nil : self
    }
}
