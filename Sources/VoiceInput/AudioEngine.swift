import AVFoundation
import Speech
import Accelerate

final class AudioEngineController {
    let engine = AVAudioEngine()
    private var bandsHandler: (([Float]) -> Void)?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?

    // FFT 配置
    private let fftSize = 2048
    private var fftSetup: FFTSetup?
    private var window: [Float] = []

    // 5 个频段的 bin 范围（基于 44100Hz 采样率，fftSize=2048）
    // freq_per_bin = sampleRate / fftSize ≈ 21.5 Hz/bin
    // 频段: 80-300Hz | 300-800Hz | 800-2500Hz | 2500-5000Hz | 5000-10000Hz
    private let bandRanges: [(Int, Int)] = [
        (4,  14),   // 86–301 Hz   — 低频/胸腔共鸣
        (14, 38),   // 301–817 Hz  — 中低/元音基频
        (38, 116),  // 817–2494 Hz — 中频/语音主体
        (116, 233), // 2494–5011 Hz — 中高/辅音清晰度
        (233, 466), // 5011–10022 Hz — 高频/齿音/气息
    ]

    init() {
        fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Float(fftSize))), FFTRadix(kFFTRadix2))
        // 汉宁窗，降低频谱泄漏
        window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }

    deinit {
        if let setup = fftSetup { vDSP_destroy_fftsetup(setup) }
    }

    func start(bandsHandler: @escaping ([Float]) -> Void,
               recognitionRequest: SFSpeechAudioBufferRecognitionRequest?) {
        self.bandsHandler = bandsHandler
        self.recognitionRequest = recognitionRequest

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // 积攒样本做 FFT 用
        var sampleBuffer: [Float] = []

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.recognitionRequest?.append(buffer)

            // 收集样本
            if let channelData = buffer.floatChannelData {
                let count = Int(buffer.frameLength)
                sampleBuffer.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: count))
            }

            // 攒够 fftSize 个样本就做一次 FFT
            if sampleBuffer.count >= self.fftSize {
                let chunk = Array(sampleBuffer.prefix(self.fftSize))
                sampleBuffer.removeFirst(min(512, sampleBuffer.count)) // 50% 重叠
                let bands = self.computeBands(samples: chunk, sampleRate: Float(format.sampleRate))
                self.bandsHandler?(bands)
            }
        }

        do {
            try engine.start()
        } catch {
            print("[AudioEngine] 启动失败: \(error)")
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        bandsHandler = nil
        recognitionRequest = nil
    }

    // MARK: - FFT

    private func computeBands(samples: [Float], sampleRate: Float) -> [Float] {
        guard let fftSetup, samples.count == fftSize else { return [Float](repeating: 0, count: 5) }

        // 加窗
        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        // 拆分复数（用 withUnsafeMutablePointer 确保指针生命周期安全）
        var realPart = [Float](windowed.prefix(fftSize / 2))
        var imagPart = [Float](repeating: 0, count: fftSize / 2)

        realPart.withUnsafeMutableBufferPointer { realBuf in
            imagPart.withUnsafeMutableBufferPointer { imagBuf in
                var splitComplex = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)

                windowed.withUnsafeBytes { ptr in
                    let complexPtr = ptr.baseAddress!.assumingMemoryBound(to: DSPComplex.self)
                    vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
                }

                vDSP_fft_zrip(fftSetup, &splitComplex, 1,
                               vDSP_Length(log2(Float(fftSize))), FFTDirection(FFT_FORWARD))

                // 计算幅度谱（覆盖 realPart）
                vDSP_zvmags(&splitComplex, 1, realBuf.baseAddress!, 1, vDSP_Length(fftSize / 2))
            }
        }

        // realPart 现在存储幅度谱
        var magnitudes = realPart

        // 归一化
        var scaledMag = [Float](repeating: 0, count: fftSize / 2)
        var scale = Float(1.0 / Float(fftSize))
        vDSP_vsmul(magnitudes, 1, &scale, &scaledMag, 1, vDSP_Length(fftSize / 2))

        // 各频段取均值 → 归一化到 0-1
        var bands = [Float](repeating: 0, count: 5)
        for (i, (lo, hi)) in bandRanges.enumerated() {
            let clampedHi = min(hi, scaledMag.count)
            guard lo < clampedHi else { continue }
            let slice = scaledMag[lo..<clampedHi]
            let mean = slice.reduce(0, +) / Float(slice.count)
            // 语音信号的幅度范围大概在 0~0.01，放大并 clamp
            bands[i] = min(mean * 300.0, 1.0)
        }

        return bands
    }
}
