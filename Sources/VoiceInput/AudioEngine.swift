import AVFoundation
import Speech
import Accelerate

final class AudioEngineController {
    let engine = AVAudioEngine()
    private var bandsHandler: (([Float]) -> Void)?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?

    // FFT
    private let fftSize = 2048
    private var fftSetup: FFTSetup?
    private var hannWindow: [Float] = []
    private var sampleBuffer: [Float] = []

    // 频段频率范围（Hz），根据实际采样率动态计算 bin 索引
    // 设计目标：男声基频(85-180Hz)落在第2根，男声整体(200-1500Hz)集中在第2-3根
    //          女声整体(300-3000Hz)集中在第3-4根，高频气声/齿音在第5根
    private let bandFreqRanges: [(Float, Float)] = [
        (50,   150),   // 第1根 — 超低频/次声，普通说话几乎不亮
        (150,  600),   // 第2根 — 男声基频+低次谐波 (85-180Hz 基频+泛音)
        (600,  2200),  // 第3根 — 语音核心共振峰 F1/F2，男女声均最密集
        (2200, 5000),  // 第4根 — 女声上共振峰 F3/F4，辅音定义
        (5000, 12000), // 第5根 — 齿音/气息/擦音
    ]

    init() {
        let log2n = vDSP_Length(log2(Float(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        hannWindow = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&hannWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }

    deinit {
        if let s = fftSetup { vDSP_destroy_fftsetup(s) }
    }

    func start(bandsHandler: @escaping ([Float]) -> Void,
               recognitionRequest: SFSpeechAudioBufferRecognitionRequest?) {
        self.bandsHandler = bandsHandler
        self.recognitionRequest = recognitionRequest
        sampleBuffer = []

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let sampleRate = Float(format.sampleRate)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.recognitionRequest?.append(buffer)

            if let channelData = buffer.floatChannelData {
                let count = Int(buffer.frameLength)
                self.sampleBuffer.append(
                    contentsOf: UnsafeBufferPointer(start: channelData[0], count: count)
                )
            }

            // 攒够 fftSize 后做 FFT，50% 重叠提高时间分辨率
            while self.sampleBuffer.count >= self.fftSize {
                let chunk = Array(self.sampleBuffer.prefix(self.fftSize))
                self.sampleBuffer.removeFirst(self.fftSize / 2)
                let bands = self.computeBands(samples: chunk, sampleRate: sampleRate)
                self.bandsHandler?(bands)
            }
        }

        do { try engine.start() }
        catch { print("[AudioEngine] 启动失败: \(error)") }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        bandsHandler = nil
        recognitionRequest = nil
        sampleBuffer = []
    }

    // MARK: - FFT

    private func computeBands(samples: [Float], sampleRate: Float) -> [Float] {
        guard let fftSetup, samples.count == fftSize else {
            return [Float](repeating: 0, count: 5)
        }

        let halfSize = fftSize / 2
        let log2n = vDSP_Length(log2(Float(fftSize)))

        // 加汉宁窗
        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(samples, 1, hannWindow, 1, &windowed, 1, vDSP_Length(fftSize))

        // 实数 FFT
        var real = [Float](repeating: 0, count: halfSize)
        var imag = [Float](repeating: 0, count: halfSize)

        let bands: [Float] = real.withUnsafeMutableBufferPointer { realBuf in
            imag.withUnsafeMutableBufferPointer { imagBuf in
                var split = DSPSplitComplex(realp: realBuf.baseAddress!,
                                            imagp: imagBuf.baseAddress!)

                // 把 real 信号打包成复数格式
                windowed.withUnsafeBytes { rawPtr in
                    rawPtr.withMemoryRebound(to: DSPComplex.self) { complexPtr in
                        vDSP_ctoz(complexPtr.baseAddress!, 2, &split, 1, vDSP_Length(halfSize))
                    }
                }

                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

                // 幅度（不是功率），正确归一化：除以 N 再取 sqrt
                var mags = [Float](repeating: 0, count: halfSize)
                vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(halfSize))
                // vDSP_zvabs 输出是 sqrt(r²+i²)，但 zrip 的输出在 0 号位不含虚部
                // 归一化：除以 (fftSize/2)
                var norm = Float(halfSize)
                vDSP_vsdiv(mags, 1, &norm, &mags, 1, vDSP_Length(halfSize))

                // 按频率范围切分频段，取均值后转 dB，映射到 0-1
                let freqPerBin = sampleRate / Float(self.fftSize)
                return self.bandFreqRanges.enumerated().map { (i, range) in
                    let (loFreq, hiFreq) = range
                    let loIdx = max(1, Int(loFreq / freqPerBin))
                    let hiIdx = min(halfSize - 1, Int(hiFreq / freqPerBin))
                    guard loIdx < hiIdx else { return Float(0) }

                    let slice = mags[loIdx...hiIdx]
                    let mean = slice.reduce(0, +) / Float(slice.count)

                    // 对数映射：各频段使用不同灵敏度
                    // 第1根（超低频）不需要太灵敏，中间三根最灵敏，第5根齿音偏高
                    let dB = 20.0 * log10(max(mean, 1e-7))
                    let floors: [Float] = [-50, -65, -68, -62, -55]
                    let floor = i < floors.count ? floors[i] : -65
                    let range: Float = 48
                    let normalized = (dB - floor) / range
                    return max(0, min(1, normalized))
                }
            }
        }

        return bands
    }
}
