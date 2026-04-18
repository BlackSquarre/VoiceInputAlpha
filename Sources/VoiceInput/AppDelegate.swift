import Cocoa
import AVFoundation
import Speech

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController!
    private var fnKeyMonitor: FnKeyMonitor!
    private var audioEngine: AudioEngineController!
    private var speechRecognizer: SpeechRecognizerController!
    private var capsuleWindow: CapsuleWindowController!
    private var textInjector: TextInjector!
    private var llmRefiner: LLMRefiner!
    private var isRecording = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "selectedLanguage": "zh-CN",
            "llmEnabled": false,
            "llmAPIBaseURL": "https://api.openai.com/v1",
            "llmModel": "gpt-4o-mini",
            "autoPunctuationEnabled": true,
            "llmResultDelay": 0.3,
            "animationStyle": "dynamicIsland",
            "animationSpeed": "medium",
        ])

        requestPermissions()

        llmRefiner = LLMRefiner()
        textInjector = TextInjector()
        capsuleWindow = CapsuleWindowController()
        audioEngine = AudioEngineController()
        speechRecognizer = SpeechRecognizerController()

        menuBarController = MenuBarController(
            onLanguageChanged: { [weak self] in
                self?.speechRecognizer.updateLanguage()
            },
            llmRefiner: llmRefiner
        )

        fnKeyMonitor = FnKeyMonitor(
            onFnDown: { [weak self] in self?.startRecording() },
            onFnUp: { [weak self] in self?.stopRecording() }
        )
        fnKeyMonitor.onTapDisabled = { [weak self] in
            self?.menuBarController.showAccessibilityWarning()
        }
        fnKeyMonitor.start()
    }

    // MARK: - Window activation helpers

    /// 在 LSUIElement=true (accessory) 模式下，普通 activate() 不会夺焦。
    /// 显示任何普通窗口前调用此函数切换策略并强制置前。
    static func bringToFront(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
            if #available(macOS 14.0, *) { NSApp.activate() }
            else { NSApp.activate(ignoringOtherApps: true) }
        }
    }

    /// 窗口关闭时调用：若已无其他普通窗口可见，恢复 accessory 策略。
    static func resetActivationIfNeeded(closing: NSWindow) {
        let hasOther = NSApp.windows.contains {
            $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled)
        }
        if !hasOther { NSApp.setActivationPolicy(.accessory) }
    }

    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = loc("permission.mic.title")
                    alert.informativeText = loc("permission.mic.message")
                    alert.runModal()
                }
            }
        }
        SFSpeechRecognizer.requestAuthorization { status in
            if status != .authorized {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = loc("permission.speech.title")
                    alert.informativeText = loc("permission.speech.message")
                    alert.runModal()
                }
            }
        }
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true

        DispatchQueue.main.async { [self] in
            capsuleWindow.show()

            let request = speechRecognizer.start { [weak self] text, isFinal in
                DispatchQueue.main.async {
                    self?.capsuleWindow.updateText(text)
                }
            }

            audioEngine.start(
                bandsHandler: { [weak self] bands in
                    DispatchQueue.main.async {
                        self?.capsuleWindow.updateBands(bands)
                    }
                },
                recognitionRequest: request
            )
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false

        DispatchQueue.main.async { [self] in
            let rawText = speechRecognizer.stop()
            audioEngine.stop()

            if rawText.isEmpty {
                capsuleWindow.dismiss()
                return
            }

            // 本地自动标点
            var processedText = rawText
            if UserDefaults.standard.bool(forKey: "autoPunctuationEnabled") {
                let lang = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "zh-CN"
                processedText = PunctuationProcessor.process(rawText, language: lang)
                capsuleWindow.updateText(processedText)
            }

            let llmEnabled = UserDefaults.standard.bool(forKey: "llmEnabled")
            let apiKey = UserDefaults.standard.string(forKey: "llmAPIKey") ?? ""

            if llmEnabled && !apiKey.isEmpty {
                capsuleWindow.showRefining()
                llmRefiner.refine(text: processedText) { [weak self] refined, errorMsg in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        if let errorMsg {
                            // 立即注入文字，同时胶囊显示错误 3 秒
                            self.textInjector.inject(text: processedText)
                            self.capsuleWindow.showError(errorMsg)
                            return
                        }
                        let finalText = refined ?? processedText
                        self.capsuleWindow.updateText(finalText)
                        let delay = UserDefaults.standard.double(forKey: "llmResultDelay")
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            self.capsuleWindow.dismiss {
                                self.textInjector.inject(text: finalText)
                            }
                        }
                    }
                }
            } else {
                capsuleWindow.dismiss { [self] in
                    textInjector.inject(text: processedText)
                }
            }
        }
    }
}
