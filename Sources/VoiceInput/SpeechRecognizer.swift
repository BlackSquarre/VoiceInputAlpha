import Speech
import AVFoundation

final class SpeechRecognizerController {
    private var recognizer: SFSpeechRecognizer?
    private(set) var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var currentText: String = ""
    private var onResult: ((String, Bool) -> Void)?

    init() {
        updateLanguage()
    }

    func updateLanguage() {
        let langCode = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "zh-CN"
        let locale = Locale(identifier: langCode)
        recognizer = SFSpeechRecognizer(locale: locale)
        recognizer?.defaultTaskHint = .dictation
    }

    /// Creates the recognition request and starts the recognition task.
    /// Returns the request so AudioEngineController can append buffers to it.
    func start(onResult: @escaping (String, Bool) -> Void) -> SFSpeechAudioBufferRecognitionRequest? {
        self.onResult = onResult
        currentText = ""

        guard let recognizer = recognizer, recognizer.isAvailable else {
            print("[SpeechRecognizer] Recognizer not available")
            return nil
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        self.recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                self.currentText = result.bestTranscription.formattedString
                self.onResult?(self.currentText, result.isFinal)
            }
            if let error = error {
                // Only log unexpected errors, not cancellation
                let nsError = error as NSError
                if nsError.domain != "kAFAssistantErrorDomain" || nsError.code != 216 {
                    print("[SpeechRecognizer] Error: \(error.localizedDescription)")
                }
            }
        }

        return request
    }

    func stop() -> String {
        recognitionRequest?.endAudio()
        // 用 finish 而非 cancel，确保最后一帧 partial result 能被收到
        recognitionTask?.finish()
        recognitionTask = nil
        recognitionRequest = nil
        onResult = nil
        return currentText
    }
}
