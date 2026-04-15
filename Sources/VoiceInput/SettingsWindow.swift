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
            refreshFields()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 360),
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

        let padding: CGFloat = 24
        let labelWidth: CGFloat = 110
        let fieldHeight: CGFloat = 28          // macOS 26 推荐更高的控件
        let rowSpacing: CGFloat = 44           // 行间距更宽松
        var y: CGFloat = 308

        // API 地址
        contentView.addSubview(makeLabel("API 地址:", frame: NSRect(x: padding, y: y, width: labelWidth, height: fieldHeight)))
        apiBaseURLField = makeTextField(frame: NSRect(x: padding + labelWidth + 8, y: y, width: 320, height: fieldHeight))
        apiBaseURLField.stringValue = UserDefaults.standard.string(forKey: "llmAPIBaseURL") ?? "https://api.openai.com/v1"
        apiBaseURLField.placeholderString = "https://api.openai.com/v1"
        contentView.addSubview(apiBaseURLField)
        y -= rowSpacing

        // API 密钥
        contentView.addSubview(makeLabel("API 密钥:", frame: NSRect(x: padding, y: y, width: labelWidth, height: fieldHeight)))
        apiKeyField = NSSecureTextField(frame: NSRect(x: padding + labelWidth + 8, y: y, width: 320, height: fieldHeight))
        apiKeyField.stringValue = UserDefaults.standard.string(forKey: "llmAPIKey") ?? ""
        apiKeyField.placeholderString = "sk-..."
        styleTextField(apiKeyField)
        contentView.addSubview(apiKeyField)
        y -= rowSpacing

        // 模型
        contentView.addSubview(makeLabel("模型:", frame: NSRect(x: padding, y: y, width: labelWidth, height: fieldHeight)))
        modelField = makeTextField(frame: NSRect(x: padding + labelWidth + 8, y: y, width: 320, height: fieldHeight))
        modelField.stringValue = UserDefaults.standard.string(forKey: "llmModel") ?? "gpt-4o-mini"
        modelField.placeholderString = "gpt-4o-mini"
        contentView.addSubview(modelField)
        y -= rowSpacing

        // 结果展示延迟
        contentView.addSubview(makeLabel("结果展示延迟:", frame: NSRect(x: padding, y: y, width: labelWidth, height: fieldHeight)))
        delayField = makeTextField(frame: NSRect(x: padding + labelWidth + 8, y: y, width: 60, height: fieldHeight))
        let currentDelay = UserDefaults.standard.double(forKey: "llmResultDelay")
        delayField.stringValue = String(format: "%.1f", currentDelay > 0 ? currentDelay : 0.3)
        delayField.placeholderString = "0.3"
        contentView.addSubview(delayField)

        let unitLabel = NSTextField(labelWithString: "秒（0 为立即注入）")
        unitLabel.frame = NSRect(x: padding + labelWidth + 8 + 68, y: y + 4, width: 200, height: 20)
        unitLabel.font = .systemFont(ofSize: 12)
        unitLabel.textColor = .tertiaryLabelColor
        contentView.addSubview(unitLabel)
        y -= 52

        // 分割线
        let separator = NSBox()
        separator.frame = NSRect(x: padding, y: y, width: 500 - padding * 2, height: 1)
        separator.boxType = .separator
        contentView.addSubview(separator)
        y -= 36

        // 状态标签
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: padding, y: y, width: 310, height: 20)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        contentView.addSubview(statusLabel)

        // 按钮（macOS 26 用 .glass 样式，旧系统降级为 .rounded）
        let btnW: CGFloat = 88
        let btnH: CGFloat = 32
        let btnY = y - 2

        let testButton = makeButton("测试连接", action: #selector(testConnection(_:)),
                                    frame: NSRect(x: 500 - padding - btnW * 3 - 10 * 2, y: btnY, width: btnW, height: btnH))
        contentView.addSubview(testButton)

        let saveButton = makeButton("保存", action: #selector(saveSettings(_:)),
                                    frame: NSRect(x: 500 - padding - btnW * 2 - 10, y: btnY, width: btnW, height: btnH),
                                    isPrimary: true)
        saveButton.keyEquivalent = "\r"
        contentView.addSubview(saveButton)

        let cancelButton = makeButton("取消", action: #selector(cancelSettings(_:)),
                                      frame: NSRect(x: 500 - padding - btnW, y: btnY, width: btnW, height: btnH))
        cancelButton.keyEquivalent = "\u{1b}"
        contentView.addSubview(cancelButton)

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Factory Helpers

    private func makeLabel(_ text: String, frame: NSRect) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        label.alignment = .right
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeTextField(frame: NSRect) -> NSTextField {
        let field = NSTextField(frame: frame)
        styleTextField(field)
        return field
    }

    private func styleTextField(_ field: NSTextField) {
        field.bezelStyle = .roundedBezel
        field.font = .systemFont(ofSize: 13)
    }

    private func makeButton(_ title: String, action: Selector, frame: NSRect, isPrimary: Bool = false) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.frame = frame
        if #available(macOS 26.0, *) {
            btn.bezelStyle = .glass
        } else {
            btn.bezelStyle = .rounded
        }
        if isPrimary {
            btn.hasDestructiveAction = false
            btn.keyEquivalentModifierMask = []
        }
        return btn
    }

    // MARK: - State

    private func refreshFields() {
        apiBaseURLField?.stringValue = UserDefaults.standard.string(forKey: "llmAPIBaseURL") ?? "https://api.openai.com/v1"
        apiKeyField?.stringValue = UserDefaults.standard.string(forKey: "llmAPIKey") ?? ""
        modelField?.stringValue = UserDefaults.standard.string(forKey: "llmModel") ?? "gpt-4o-mini"
        let delay = UserDefaults.standard.double(forKey: "llmResultDelay")
        delayField?.stringValue = String(format: "%.1f", delay > 0 ? delay : 0.3)
        statusLabel?.stringValue = ""
    }

    // MARK: - Actions

    @objc private func testConnection(_ sender: NSButton) {
        let origBase  = UserDefaults.standard.string(forKey: "llmAPIBaseURL")
        let origKey   = UserDefaults.standard.string(forKey: "llmAPIKey")
        let origModel = UserDefaults.standard.string(forKey: "llmModel")

        UserDefaults.standard.set(apiBaseURLField.stringValue, forKey: "llmAPIBaseURL")
        UserDefaults.standard.set(apiKeyField.stringValue,     forKey: "llmAPIKey")
        UserDefaults.standard.set(modelField.stringValue,      forKey: "llmModel")

        statusLabel.stringValue = "正在测试..."
        statusLabel.textColor = .secondaryLabelColor

        llmRefiner.testConnection { [weak self] success, message in
            DispatchQueue.main.async {
                self?.statusLabel.stringValue = success ? "连接成功!" : "连接失败: \(message)"
                self?.statusLabel.textColor = success ? .systemGreen : .systemRed

                if let base  = origBase  { UserDefaults.standard.set(base,  forKey: "llmAPIBaseURL") }
                if let key   = origKey   { UserDefaults.standard.set(key,   forKey: "llmAPIKey") }
                if let model = origModel { UserDefaults.standard.set(model, forKey: "llmModel") }
            }
        }
    }

    @objc private func saveSettings(_ sender: NSButton) {
        UserDefaults.standard.set(apiBaseURLField.stringValue, forKey: "llmAPIBaseURL")
        UserDefaults.standard.set(apiKeyField.stringValue,     forKey: "llmAPIKey")
        UserDefaults.standard.set(modelField.stringValue,      forKey: "llmModel")
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
