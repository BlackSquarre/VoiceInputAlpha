import Cocoa

final class CapsuleWindowController {
    private var panel: NSPanel?
    private var waveformView: WaveformView?
    private var textLabel: NSTextField?
    private var refiningLabel: NSTextField?
    private var panelWidthConstraint: NSLayoutConstraint?

    private let capsuleHeight: CGFloat = 50
    private let cornerRadius: CGFloat = 25
    private let waveformWidth: CGFloat = 40
    private let minTextWidth: CGFloat = 144
    private let maxTextWidth: CGFloat = 504
    private let horizontalPadding: CGFloat = 18

    func show() {
        if panel != nil { return }

        let initialWidth: CGFloat = waveformWidth + minTextWidth + horizontalPadding * 3
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let x = screenFrame.midX - initialWidth / 2
        let y = screenFrame.minY + 54

        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: initialWidth, height: capsuleHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.styleMask.remove(.titled)

        // 内容容器（直接铺满 panel）
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // 波形视图
        let waveform = WaveformView(frame: .zero)
        waveform.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(waveform)

        // 转录文字
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13.5, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.cell?.truncatesLastVisibleLine = true
        container.addSubview(label)

        // 优化中指示
        let refLabel = NSTextField(labelWithString: "优化中...")
        refLabel.translatesAutoresizingMaskIntoConstraints = false
        refLabel.font = .systemFont(ofSize: 12, weight: .regular)
        refLabel.isHidden = true
        container.addSubview(refLabel)

        // 文字颜色根据模式（GlassEffectView 背景下始终用 labelColor）
        label.textColor = .labelColor
        refLabel.textColor = .secondaryLabelColor

        let maxWidth = label.widthAnchor.constraint(lessThanOrEqualToConstant: maxTextWidth)
        let minWidth = label.widthAnchor.constraint(greaterThanOrEqualToConstant: minTextWidth)

        NSLayoutConstraint.activate([
            waveform.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            waveform.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            waveform.widthAnchor.constraint(equalToConstant: waveformWidth),
            waveform.heightAnchor.constraint(equalToConstant: 29),

            label.leadingAnchor.constraint(equalTo: waveform.trailingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            minWidth, maxWidth,

            refLabel.leadingAnchor.constraint(equalTo: waveform.trailingAnchor, constant: 10),
            refLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        // 根据系统版本选择背景
        let panelWidth: NSLayoutConstraint

        if #available(macOS 26.0, *) {
            // ── 液态玻璃效果 ──────────────────────────────────
            let glassView = NSGlassEffectView()
            glassView.cornerRadius = cornerRadius
            glassView.style = .regular
            glassView.contentView = container
            glassView.translatesAutoresizingMaskIntoConstraints = false

            panel.contentView?.addSubview(glassView)
            NSLayoutConstraint.activate([
                glassView.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
                glassView.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
                glassView.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
                glassView.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor),
            ])

            // container 在 glassView.contentView 内布局
            container.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                container.leadingAnchor.constraint(equalTo: glassView.leadingAnchor, constant: horizontalPadding),
                container.trailingAnchor.constraint(equalTo: glassView.trailingAnchor, constant: -horizontalPadding),
                container.topAnchor.constraint(equalTo: glassView.topAnchor),
                container.bottomAnchor.constraint(equalTo: glassView.bottomAnchor),
            ])

            _ = glassView
            panelWidth = panel.contentView!.widthAnchor.constraint(equalToConstant: initialWidth)
        } else {
            // ── 毛玻璃降级方案 ───────────────────────────────
            let effectView = NSVisualEffectView(frame: panel.contentView!.bounds)
            effectView.autoresizingMask = [.width, .height]
            effectView.material = .hudWindow
            effectView.state = .active
            effectView.blendingMode = .behindWindow
            effectView.wantsLayer = true
            effectView.layer?.cornerRadius = cornerRadius
            effectView.layer?.masksToBounds = true
            effectView.layer?.cornerCurve = .continuous
            panel.contentView?.addSubview(effectView)
            panel.contentView?.addSubview(container)

            container.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                container.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: horizontalPadding),
                container.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -horizontalPadding),
                container.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
                container.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor),
            ])

            _ = effectView
            panelWidth = panel.contentView!.widthAnchor.constraint(equalToConstant: initialWidth)
        }

        panelWidth.isActive = true

        self.panel = panel
        self.waveformView = waveform
        self.textLabel = label
        self.refiningLabel = refLabel
        self.panelWidthConstraint = panelWidth

        // 入场动画
        panel.contentView?.wantsLayer = true
        panel.alphaValue = 0

        var startFrame = panel.frame
        startFrame.origin.y -= 8
        panel.setFrame(startFrame, display: false)
        let targetFrame = NSRect(x: x, y: y, width: initialWidth, height: capsuleHeight)

        panel.contentView?.layer?.transform = CATransform3DMakeScale(0.92, 0.92, 1.0)
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            panel.animator().alphaValue = 1
            panel.animator().setFrame(targetFrame, display: true)
            panel.contentView?.layer?.transform = CATransform3DIdentity
        })
    }

    func updateRMS(_ rms: Float) {
        waveformView?.updateRMS(rms)
    }

    func updateText(_ text: String) {
        guard let label = textLabel, let panel = panel else { return }
        label.stringValue = text

        let textSize = (text as NSString).size(withAttributes: [.font: label.font!])
        let desiredTextWidth = min(max(textSize.width + 18, minTextWidth), maxTextWidth)
        let totalWidth = desiredTextWidth + waveformWidth + horizontalPadding * 3 + 10

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.allowsImplicitAnimation = true
            panelWidthConstraint?.animator().constant = totalWidth
            let screenFrame = NSScreen.main?.visibleFrame ?? .zero
            var frame = panel.frame
            frame.size.width = totalWidth
            frame.origin.x = screenFrame.midX - totalWidth / 2
            panel.animator().setFrame(frame, display: true)
        })
    }

    func showRefining() {
        textLabel?.isHidden = true
        refiningLabel?.isHidden = false
        waveformView?.stopAnimating()
    }

    func dismiss(completion: (() -> Void)? = nil) {
        guard let panel = panel else {
            completion?()
            return
        }

        var targetFrame = panel.frame
        targetFrame.origin.y -= 8

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            ctx.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0
            panel.animator().setFrame(targetFrame, display: true)
            panel.contentView?.layer?.transform = CATransform3DMakeScale(0.92, 0.92, 1.0)
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.cleanup()
            completion?()
        })
    }

    private func cleanup() {
        waveformView?.stopAnimating()
        waveformView = nil
        textLabel = nil
        refiningLabel = nil
        panelWidthConstraint = nil
        panel = nil
    }
}
