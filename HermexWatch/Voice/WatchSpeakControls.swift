import SwiftUI
import HermexWatchRoot
import WatchShared

struct WatchSpeakControls: View {
    @Bindable var model: WatchRootModel
    let session: WatchSessionSummary
    var compact: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var capture = WatchVoiceCapture()
    @State private var recorder = WatchVoiceNoteRecorder()
    @State private var draft = ""

    var listenAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            if let listenAction {
                Button("Listen", action: listenAction)
                    .frame(maxWidth: .infinity)
            }

            Button {
                Task { await toggleVoice() }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: capture.phase == .recording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: compact ? 28 : 44, weight: .regular))
                        .symbolEffect(.pulse, isActive: !reduceMotion && capture.phase == .recording)
                    Text(micLabel)
                        .font(.caption2)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityLabel(micAccessibilityLabel)
            .accessibilityHint("Records up to \(WatchVoiceCapturePolicy.maximumDurationPhrase). Your iPhone transcribes it and Hermex sends the recording.")
            .disabled(capture.phase == .transcribing || capture.phase == .sending)

            if capture.phase == .recording {
                Text(elapsedLabel)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Recording, \(elapsedLabel)")
            }

            if case .failed(let code) = capture.phase {
                Text(failureCopy(code))
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            if model.activeRun(for: session) != nil {
                Button(role: .destructive) {
                    Task {
                        if await model.stop(session) {
                            WatchHaptics.play(.stop)
                        }
                    }
                } label: {
                    Text("Stop")
                }
                .frame(maxWidth: .infinity)
            }

            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...3)
                .multilineTextAlignment(.center)
            Button("Send") {
                Task { await sendDraft() }
            }
            .frame(maxWidth: .infinity)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .frame(maxWidth: .infinity)
        .onChange(of: recorder.elapsed) { _, elapsed in
            if capture.phase == .recording, elapsed >= WatchVoiceCapturePolicy.maximumDuration {
                Task { await finishVoice() }
            }
        }
    }

    private var elapsedLabel: String {
        let total = max(0, Int(recorder.elapsed.rounded(.down)))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var micLabel: String {
        switch capture.phase {
        case .idle, .failed: return "Speak"
        case .recording: return "Tap to send"
        case .transcribing: return "Transcribing"
        case .sending: return "Sending"
        }
    }

    private var micAccessibilityLabel: String {
        switch capture.phase {
        case .recording: return "Stop recording and send"
        case .transcribing: return "Transcribing voice note"
        case .sending: return "Sending voice note"
        case .idle, .failed: return "Speak to Hermex"
        }
    }

    private func failureCopy(_ code: String) -> String {
        switch code {
        case "tooShort": return "Hold a moment longer."
        case "tooLong": return "Clip was cut at \(WatchVoiceCapturePolicy.maximumDurationPhrase)."
        case "tooLarge": return "That note is too large to send from Apple Watch. Try a shorter one."
        case "micDenied": return "Enable the microphone in Settings."
        case "empty": return "Nothing to send."
        default: return "Couldn’t send that note."
        }
    }

    private func toggleVoice() async {
        switch capture.phase {
        case .idle, .failed:
            do {
                try await recorder.begin()
                capture.beginRecording()
                WatchHaptics.play(.start)
            } catch {
                capture.fail(code: "micDenied")
                WatchHaptics.play(.failure)
            }
        case .recording:
            await finishVoice()
        case .transcribing, .sending:
            break
        }
    }

    private func finishVoice() async {
        guard capture.phase == .recording else { return }
        guard let clip = recorder.finish(), capture.finishRecording(duration: clip.duration) else {
            recorder.cancel()
            if capture.phase != .failed(code: "tooShort") && capture.phase != .failed(code: "tooLong") {
                capture.fail(code: "tooShort")
            }
            WatchHaptics.play(.failure)
            return
        }
        await transcribeAndSend(clip: clip)
    }

    private func transcribeAndSend(clip: WatchVoiceNoteRecorder.Clip) async {
        do {
            let data = try Data(contentsOf: clip.url)
            try? FileManager.default.removeItem(at: clip.url)
            capture.markSending()
            if await model.sendVoiceNote(audio: data, filename: clip.url.lastPathComponent, to: session) != nil {
                WatchHaptics.play(.success)
                capture.markIdle()
                WatchWidgetSnapshotPublisher.publish(model)
            } else {
                capture.fail(code: model.lastErrorCode == "tooLarge" ? "tooLarge" : "sendRejected")
                WatchHaptics.play(.failure)
            }
        } catch WatchVoiceNoteValidationError.audioTooLarge {
            try? FileManager.default.removeItem(at: clip.url)
            capture.fail(code: "tooLarge")
            WatchHaptics.play(.failure)
        } catch {
            try? FileManager.default.removeItem(at: clip.url)
            capture.fail(code: "speechUnavailable")
            WatchHaptics.play(.failure)
        }
    }

    private func sendDraft() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if await model.send(text: text, to: session) != nil {
            draft = ""
            WatchHaptics.play(.success)
            WatchWidgetSnapshotPublisher.publish(model)
        } else {
            WatchHaptics.play(.failure)
        }
    }
}
