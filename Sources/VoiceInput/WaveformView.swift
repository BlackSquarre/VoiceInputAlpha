import Cocoa

final class WaveformView: NSView {
    private let barCount = 5
    private let barWeights: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]
    private let barWidth: CGFloat = 3.6    // 4.0 * 0.9
    private let barSpacing: CGFloat = 2.7  // 3.0 * 0.9
    private let minBarHeight: CGFloat = 3.6
    private let maxBarHeight: CGFloat = 25.0  // 28 * 0.9

    private let attackCoeff: CGFloat = 0.40
    private let releaseCoeff: CGFloat = 0.15

    private var smoothedRMS: CGFloat = 0
    private var barHeights: [CGFloat]
    private var isAnimating = false
    private var timer: Timer?

    override init(frame: NSRect) {
        barHeights = Array(repeating: 3.6, count: barCount)
        super.init(frame: frame)
        wantsLayer = true
        startAnimating()
    }

    required init?(coder: NSCoder) {
        barHeights = Array(repeating: 3.6, count: 5)
        super.init(coder: coder)
    }

    deinit {
        stopAnimating()
    }

    func updateRMS(_ rms: Float) {
        let target = CGFloat(rms)
        if target > smoothedRMS {
            smoothedRMS += (target - smoothedRMS) * attackCoeff
        } else {
            smoothedRMS += (target - smoothedRMS) * releaseCoeff
        }
    }

    func stopAnimating() {
        isAnimating = false
        timer?.invalidate()
        timer = nil
        smoothedRMS = 0
        for i in 0..<barCount {
            barHeights[i] = minBarHeight
        }
        needsDisplay = true
    }

    func restartAnimating() {
        guard !isAnimating else { return }
        startAnimating()
    }

    private func startAnimating() {
        isAnimating = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isAnimating else { return }
            self.tick()
        }
    }

    private func tick() {
        for i in 0..<barCount {
            let weight = barWeights[i]
            let jitter = CGFloat.random(in: -0.04...0.04)
            let targetHeight = minBarHeight + (maxBarHeight - minBarHeight) * smoothedRMS * weight * (1.0 + jitter)
            let current = barHeights[i]
            if targetHeight > current {
                barHeights[i] += (targetHeight - current) * attackCoeff
            } else {
                barHeights[i] += (targetHeight - current) * releaseCoeff
            }
            barHeights[i] = max(minBarHeight, min(maxBarHeight, barHeights[i]))
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let totalBarsWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
        let startX = (bounds.width - totalBarsWidth) / 2

        // 自动适配深色/浅色模式
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let baseColor: NSColor = isDark ? .white : NSColor(white: 0.15, alpha: 1.0)

        for i in 0..<barCount {
            let height = barHeights[i]
            let x = startX + CGFloat(i) * (barWidth + barSpacing)
            let y = (bounds.height - height) / 2
            let rect = CGRect(x: x, y: y, width: barWidth, height: height)
            let path = NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2)

            let alpha: CGFloat = 0.7 + 0.3 * (barHeights[i] / maxBarHeight)
            ctx.setFillColor(baseColor.withAlphaComponent(alpha).cgColor)
            path.fill()
        }
    }
}
