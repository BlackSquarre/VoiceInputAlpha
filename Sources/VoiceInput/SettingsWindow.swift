import Cocoa

final class SettingsWindowController {
    private var window: NSWindow?
    private var apiBaseURLField: NSTextField!
    private var apiKeyField: NSSecureTextField!
    private var modelField: NSTextField!
    private var delayField: NSTextField!
    private var statusLabel: NSTextField!
    private let llmRefiner: LLMRefiner

    init(llmRefiner: LLMRefiner) {
        self.llmRefiner = llmRefiner
    }

    func showWindow() {
        if let window = window {
            // 每次打开都刷新字段为最新值
            refreshFields()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 330),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "LLM 文本优化设置"
        window.center()
        window.isReleasedWhenClosed = false

        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        let padding: CGFloat = 20
        let labelWidth: CGFloat = 120
        let fieldHeight: CGFloat = 24
        var y: CGFloat = 280

        // API 地址
        let urlLabel = makeLabel("API 地址:", frame: NSRect(x: padding, y: y, width: labelWidth, height: fieldHeight))
        contentView.addSubview(urlLabel)

        apiBaseURLField = NSTextField(frame: NSRect(x: padding + labelWidth + 8, y: y, width: 300, height: fieldHeight))
        apiBaseURLField.stringValue = UserDefaults.standard.string(forKey: "llmAPIBaseURL") ?? "https://api.openai.com/v1"
        apiBaseURLField.placeholderString = "https://api.openai.com/v1"
        contentView.addSubview(apiBaseURLField)

        y -= 40

        // API 密钥
        let keyLabel = makeLabel("API 密钥:", frame: NSRect(x: padding, y: y, width: labelWidth, height: fieldHeight))
        contentView.addSubview(keyLabel)

        apiKeyField = NSSecureTextField(frame: NSRect(x: padding + labelWidth + 8, y: y, width: 300, height: fieldHeight))
        apiKeyField.stringValue = UserDefaults.standard.string(forKey: "llmAPIKey") ?? ""
        apiKeyField.placeholderString = "sk-..."
        contentView.addSubview(apiKeyField)

        y -= 40

        // 模型
        let modelLabel = makeLabel("模型:", frame: NSRect(x: padding, y: y, width: labelWidth, height: fieldHeight))
        contentView.addSubview(modelLabel)

        modelField = NSTextField(frame: NSRect(x: padding + labelWidth + 8, y: y, width: 300, height: fieldHeight))
        modelField.stringValue = UserDefaults.standard.string(forKey: "llmModel") ?? "gpt-4o-mini"
        modelField.placeholderString = "gpt-4o-mini"
        contentView.addSubview(modelField)

        y -= 40

        // 结果展示延迟
        let delayLabel = makeLabel("结果展示延迟:", frame: NSRect(x: padding, y: y, width: labelWidth, height: fieldHeight))
        contentView.addSubview(delayLabel)

        delayField = NSTextField(frame: NSRect(x: padding + labelWidth + 8, y: y, width: 60, height: fieldHeight))
        let currentDelay = UserDefaults.standard.double(forKey: "llmResultDelay")
        delayField.stringValue = String(format: "%.1f", currentDelay > 0 ? currentDelay : 0.3)
        delayField.placeholderString = "0.3"
        contentView.addSubview(delayField)

        let unitLabel = NSTextField(labelWithString: "秒（LLM 返回后等待时间，0 为立即注入）")
        unitLabel.frame = NSRect(x: padding + labelWidth + 8 + 68, y: y, width: 260, height: fieldHeight)
        unitLabel.font = .systemFont(ofSize: 11)
        unitLabel.textColor = .secondaryLabelColor
        contentView.addSubview(unitLabel)

        y -= 50

        // 状态标签
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: padding, y: y, width: 440, height: fieldHeight)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        contentView.addSubview(statusLabel)

        y -= 40

        // 按钮
        let testButton = NSButton(title: "测试连接", target: self, action: #selector(testConnection(_:)))
        testButton.frame = NSRect(x: 480 - padding - 80 - 12 - 80 - 12 - 80, y: y, width: 80, height: 32)
        testButton.bezelStyle = .rounded
        contentView.addSubview(testButton)

        let saveButton = NSButton(title: "保存", target: self, action: #selector(saveSettings(_:)))
        saveButton.frame = NSRect(x: 480 - padding - 80 - 12 - 80, y: y, width: 80, height: 32)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        contentView.addSubview(saveButton)

        let cancelButton = NSButton(title: "取消", target: self, action: #selector(cancelSettings(_:)))
        cancelButton.frame = NSRect(x: 480 - padding - 80, y: y, width: 80, height: 32)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        contentView.addSubview(cancelButton)

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshFields() {
        apiBaseURLField?.stringValue = UserDefaults.standard.string(forKey: "llmAPIBaseURL") ?? "https://api.openai.com/v1"
        apiKeyField?.stringValue = UserDefaults.standard.string(forKey: "llmAPIKey") ?? ""
        modelField?.stringValue = UserDefaults.standard.string(forKey: "llmModel") ?? "gpt-4o-mini"
        let delay = UserDefaults.standard.double(forKey: "llmResultDelay")
        delayField?.stringValue = String(format: "%.1f", delay > 0 ? delay : 0.3)
        statusLabel?.stringValue = ""
    }

    private func makeLabel(_ text: String, frame: NSRect) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        label.alignment = .right
        label.font = .systemFont(ofSize: 13)
        return label
    }

    @objc private func testConnection(_ sender: NSButton) {
        let origBase = UserDefaults.standard.string(forKey: "llmAPIBaseURL")
        let origKey = UserDefaults.standard.string(forKey: "llmAPIKey")
        let origModel = UserDefaults.standard.string(forKey: "llmModel")

        UserDefaults.standard.set(apiBaseURLField.stringValue, forKey: "llmAPIBaseURL")
        UserDefaults.standard.set(apiKeyField.stringValue, forKey: "llmAPIKey")
        UserDefaults.standard.set(modelField.stringValue, forKey: "llmModel")

        statusLabel.stringValue = "正在测试..."
        statusLabel.textColor = .secondaryLabelColor

        llmRefiner.testConnection { [weak self] success, message in
            DispatchQueue.main.async {
                self?.statusLabel.stringValue = success ? "连接成功!" : "连接失败: \(message)"
                self?.statusLabel.textColor = success ? .systemGreen : .systemRed

                if let base = origBase { UserDefaults.standard.set(base, forKey: "llmAPIBaseURL") }
                if let key = origKey { UserDefaults.standard.set(key, forKey: "llmAPIKey") }
                if let model = origModel { UserDefaults.standard.set(model, forKey: "llmModel") }
            }
        }
    }

    @objc private func saveSettings(_ sender: NSButton) {
        UserDefaults.standard.set(apiBaseURLField.stringValue, forKey: "llmAPIBaseURL")
        UserDefaults.standard.set(apiKeyField.stringValue, forKey: "llmAPIKey")
        UserDefaults.standard.set(modelField.stringValue, forKey: "llmModel")

        // 解析并保存延迟时间
        let delayValue = Double(delayField.stringValue) ?? 0.3
        UserDefaults.standard.set(max(0, delayValue), forKey: "llmResultDelay")

        statusLabel.stringValue = "已保存"
        statusLabel.textColor = .systemGreen
        window?.close()
    }

    @objc private func cancelSettings(_ sender: NSButton) {
        window?.close()
    }
}
