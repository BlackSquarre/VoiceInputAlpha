import Cocoa

final class CapsuleWindowController {
    private var panel: NSPanel?
    private var waveformView: WaveformView?
    private var textLabel: NSTextField?
    private var refiningLabel: NSTextField?
    private var contentView: NSView?
    private var textWidthConstraint: NSLayoutConstraint?
    private var panelWidthConstraint: NSLayoutConstraint?

    private let capsuleHeight: CGFloat = 50
    private let cornerRadius: CGFloat = 25
    private let waveformWidth: CGFloat = 24
    private let waveformLeadingOffset: CGFloat = 8
    private let waveformTextGap: CGFloat = 12
    private let minTextWidth: CGFloat = 144
    private let maxTextWidth: CGFloat = 504
    private let horizontalPadding: CGFloat = 24

    private var isDynamicIsland: Bool {
        UserDefaults.standard.string(forKey: "animationStyle") != "minimal"
    }

    // MARK: - Show

    func show() {
        if panel != nil { return }

        let fullWidth: CGFloat = waveformWidth + waveformLeadingOffset + minTextWidth + horizontalPadding * 2 + waveformTextGap
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let targetX = screenFrame.midX - fullWidth / 2
        let targetY = screenFrame.minY + 54
        let targetFrame = NSRect(x: targetX, y: targetY, width: fullWidth, height: capsuleHeight)

        let panel = NSPanel(
            contentRect: targetFrame,
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

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let waveform = WaveformView(frame: .zero)
        waveform.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(waveform)

        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13.5, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingHead
        label.maximumNumberOfLines = 1
        label.cell?.truncatesLastVisibleLine = true
        container.addSubview(label)

        let refLabel = NSTextField(labelWithString: "优化中...")
        refLabel.translatesAutoresizingMaskIntoConstraints = false
        refLabel.font = .systemFont(ofSize: 12, weight: .regular)
        refLabel.textColor = .secondaryLabelColor
        refLabel.isHidden = true
        container.addSubview(refLabel)

        // minTextWidth 使用低优先级，允许在动画起始小帧时被违反
        let textWidth = label.widthAnchor.constraint(greaterThanOrEqualToConstant: minTextWidth)
        textWidth.priority = .defaultLow
        let maxWidth   = label.widthAnchor.constraint(lessThanOrEqualToConstant: maxTextWidth)
        let panelWidth = panel.contentView!.widthAnchor.constraint(equalToConstant: fullWidth)

        if #available(macOS 26.0, *) {
            let glassView = NSGlassEffectView()
            glassView.cornerRadius = cornerRadius
            glassView.style = .regular
            glassView.translatesAutoresizingMaskIntoConstraints = false
            glassView.contentView = container
            panel.contentView?.addSubview(glassView)
            NSLayoutConstraint.activate([
                glassView.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
                glassView.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
                glassView.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
                glassView.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor),
                container.leadingAnchor.constraint(equalTo: glassView.leadingAnchor, constant: horizontalPadding),
                container.trailingAnchor.constraint(equalTo: glassView.trailingAnchor, constant: -horizontalPadding),
                container.topAnchor.constraint(equalTo: glassView.topAnchor),
                container.bottomAnchor.constraint(equalTo: glassView.bottomAnchor),
            ])
        } else {
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
            NSLayoutConstraint.activate([
                container.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: horizontalPadding),
                container.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -horizontalPadding),
                container.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
                container.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor),
            ])
        }

        NSLayoutConstraint.activate([
            waveform.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: waveformLeadingOffset),
            waveform.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            waveform.widthAnchor.constraint(equalToConstant: waveformWidth),
            waveform.heightAnchor.constraint(equalToConstant: 29),
            label.leadingAnchor.constraint(equalTo: waveform.trailingAnchor, constant: waveformTextGap),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            textWidth, maxWidth,
            refLabel.leadingAnchor.constraint(equalTo: waveform.trailingAnchor, constant: waveformTextGap),
            refLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            panelWidth,
        ])

        self.panel = panel
        self.waveformView = waveform
        self.textLabel = label
        self.refiningLabel = refLabel
        self.contentView = container
        self.textWidthConstraint = textWidth
        self.panelWidthConstraint = panelWidth

        if isDynamicIsland {
            animateInDynamicIsland(panel: panel, container: container, targetFrame: targetFrame)
        } else {
            animateInMinimal(panel: panel, targetFrame: targetFrame)
        }
    }

    // MARK: - 灵动岛入场
    // 原理：窗口从中央小胶囊扩张到全尺寸（NSWindow frame 动画，无 transform）
    // 圆角由 glass/effect view 自然保持，模糊加在 container 层（被圆角裁剪）

    private func animateInDynamicIsland(panel: NSPanel, container: NSView, targetFrame: NSRect) {
        // 起始帧：与目标等高、水平居中、仅 capsuleHeight 宽（最小胶囊）
        let startWidth = capsuleHeight   // 正圆形起点
        let startFrame = NSRect(
            x: targetFrame.midX - startWidth / 2,
            y: targetFrame.minY,
            width: startWidth,
            height: capsuleHeight
        )

        // 初始模糊加在 container（内容层），glass view 的圆角会自然裁剪
        container.wantsLayer = true
        let blur = CIFilter(name: "CIGaussianBlur")!
        blur.setValue(14.0, forKey: kCIInputRadiusKey)
        container.layer?.filters = [blur]
        container.layer?.masksToBounds = false

        panel.setFrame(startFrame, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        // 模糊消除动画（独立 CABasicAnimation）
        let blurAnim = CABasicAnimation(keyPath: "filters.CIGaussianBlur.inputRadius")
        blurAnim.fromValue = 14.0
        blurAnim.toValue = 0.0
        blurAnim.duration = 0.42
        blurAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        blurAnim.fillMode = .forwards
        blurAnim.isRemovedOnCompletion = false
        container.layer?.add(blurAnim, forKey: "blurIn")

        // 窗口帧扩张 + 淡入（spring 曲线）
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.5
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1.0)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(targetFrame, display: true)
        }, completionHandler: {
            container.layer?.filters = nil
            container.layer?.removeAnimation(forKey: "blurIn")
        })
    }

    // MARK: - 简约模式入场

    private func animateInMinimal(panel: NSPanel, targetFrame: NSRect) {
        panel.contentView?.wantsLayer = true
        panel.alphaValue = 0
        var startFrame = targetFrame
        startFrame.origin.y -= 8
        panel.setFrame(startFrame, display: false)
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

    // MARK: - Update

    func updateBands(_ bands: [Float]) {
        waveformView?.updateBands(bands)
    }

    func updateText(_ text: String) {
        guard let label = textLabel, let panel = panel else { return }
        label.stringValue = text

        let textSize = (text as NSString).size(withAttributes: [.font: label.font!])
        let desiredTextWidth = min(max(textSize.width + 18, minTextWidth), maxTextWidth)
        let totalWidth = desiredTextWidth + waveformWidth + waveformLeadingOffset + horizontalPadding * 2 + waveformTextGap

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

    // MARK: - Dismiss

    func dismiss(completion: (() -> Void)? = nil) {
        guard let panel = panel else { completion?(); return }
        if isDynamicIsland {
            dismissDynamicIsland(panel: panel, completion: completion)
        } else {
            dismissMinimal(panel: panel, completion: completion)
        }
    }

    // MARK: - 灵动岛退场：窗口收缩回圆形 + 模糊 + 淡出

    private func dismissDynamicIsland(panel: NSPanel, completion: (() -> Void)?) {
        let endWidth = capsuleHeight
        let endFrame = NSRect(
            x: panel.frame.midX - endWidth / 2,
            y: panel.frame.minY,
            width: endWidth,
            height: capsuleHeight
        )

        if let container = contentView {
            container.wantsLayer = true
            let blur = CIFilter(name: "CIGaussianBlur")!
            blur.setValue(0.0, forKey: kCIInputRadiusKey)
            container.layer?.filters = [blur]
            container.layer?.masksToBounds = false

            let blurAnim = CABasicAnimation(keyPath: "filters.CIGaussianBlur.inputRadius")
            blurAnim.fromValue = 0.0
            blurAnim.toValue = 14.0
            blurAnim.duration = 0.26
            blurAnim.timingFunction = CAMediaTimingFunction(name: .easeIn)
            blurAnim.fillMode = .forwards
            blurAnim.isRemovedOnCompletion = false
            container.layer?.add(blurAnim, forKey: "blurOut")
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.36, 0.0, 0.66, 0.0) // ease-in spring
            panel.animator().alphaValue = 0
            panel.animator().setFrame(endFrame, display: true)
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.cleanup()
            completion?()
        })
    }

    // MARK: - 简约模式退场

    private func dismissMinimal(panel: NSPanel, completion: (() -> Void)?) {
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

    // MARK: - Cleanup

    private func cleanup() {
        waveformView?.stopAnimating()
        waveformView = nil
        textLabel = nil
        refiningLabel = nil
        contentView = nil
        textWidthConstraint = nil
        panelWidthConstraint = nil
        panel = nil
    }
}
