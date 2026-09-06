import Foundation
import CoreAudio

final class VolumeController {
    private var savedVolume: Float?
    private let decreaseRatio: Float = 0.2
    private let fadeDownDuration: TimeInterval = 0.3
    private let fadeUpDuration: TimeInterval = 0.5
    private let queue = DispatchQueue(label: "com.atomvoice.volume", qos: .userInitiated)
    private var fadeTimer: DispatchSourceTimer?

    // MARK: - CoreAudio 音量控制

    /// 获取默认输出设备 ID（Get default output device ID）
    private func getDefaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        return status == noErr ? deviceID : nil
    }

    // macOS 系统音量 HUD 在 USB DAC 等设备上用的"虚拟主音量"属性 'vmvc'
    // (Apple's unified "main volume" abstraction used by the system volume HUD — required for USB DACs etc.)
    private static let virtualMainVolumeSelector: AudioObjectPropertySelector = 0x766d7663 // 'vmvc'

    /// 候选属性地址：先试 VirtualMainVolume，再试常规 VolumeScalar 的多组 scope/element。
    /// 第一个能成功 get 的就用它来 set，保证读写同源。
    /// (Candidate property addresses to probe — pick the first one that returns data, use the same for set.)
    private static let candidateAddresses: [AudioObjectPropertyAddress] = {
        var list: [AudioObjectPropertyAddress] = []
        // 虚拟主音量（macOS HUD 走这条）
        list.append(AudioObjectPropertyAddress(
            mSelector: VolumeController.virtualMainVolumeSelector,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        ))
        // 常规 VolumeScalar，输出 scope，主声道 / L / R
        for el: UInt32 in [kAudioObjectPropertyElementMain, 1, 2] {
            list.append(AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: el
            ))
        }
        return list
    }()

    /// 找出当前设备真正可用的音量属性地址，并返回读到的值。
    /// (Pick the first property address that yields a value on the current device.)
    private func resolveVolumeAddress(deviceID: AudioDeviceID) -> (AudioObjectPropertyAddress, Float)? {
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        for var addr in VolumeController.candidateAddresses {
            if AudioObjectHasProperty(deviceID, &addr),
               AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &volume) == noErr {
                return (addr, volume)
            }
        }
        return nil
    }

    /// 获取系统音量（0.0–1.0）（Get system volume, 0.0–1.0）
    private func getSystemVolume() -> Float? {
        guard let deviceID = getDefaultOutputDevice() else { return nil }
        return resolveVolumeAddress(deviceID: deviceID)?.1
    }

    /// 设置系统音量（0.0–1.0）（Set system volume, 0.0–1.0）
    private func setSystemVolume(_ volume: Float) {
        guard let deviceID = getDefaultOutputDevice() else { return }
        var vol = max(0, min(1, volume))
        guard var (addr, _) = resolveVolumeAddress(deviceID: deviceID) else { return }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(deviceID, &addr, &settable) == noErr,
              settable.boolValue else { return }
        AudioObjectSetPropertyData(deviceID, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &vol)
    }

    // MARK: - 渐变控制

    private func stopFade() {
        fadeTimer?.cancel()
        fadeTimer = nil
    }

    /// CoreAudio 查询和渐变全部在专用队列运行，避免蓝牙设备 IPC 阻塞录音 UI。
    private func startFade(from startVol: Float,
                           to targetVol: Float,
                           duration: TimeInterval,
                           onComplete: (() -> Void)? = nil) {
        stopFade()
        let startTime = ProcessInfo.processInfo.systemUptime
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.0 / 60.0, leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let progress = min((ProcessInfo.processInfo.systemUptime - startTime) / duration, 1.0)
            let eased: Double
            if startVol > targetVol {
                eased = 1 - pow(1 - progress, 3)
            } else if progress < 0.5 {
                eased = 4 * progress * progress * progress
            } else {
                eased = 1 - 2 * pow(1 - progress, 3)
            }
            self.setSystemVolume(Float(Double(startVol) + Double(targetVol - startVol) * eased))
            if progress >= 1 {
                self.stopFade()
                onComplete?()
            }
        }
        fadeTimer = timer
        timer.resume()
    }

    /// 保存原始音量并平滑降低。
    /// 关键修复：快速按键时若上一轮恢复 fade 还没跑完，`savedVolume` 仍持有"真正的"原始音量；
    /// 此时不要 re-capture 当前（中间值）音量，否则原始基准会被几何衰减。
    /// (Crucial fix: during rapid presses, if the previous restore fade hasn't completed,
    /// `savedVolume` still holds the true baseline. Do NOT re-capture the current
    /// (mid-fade) reading, otherwise the baseline drifts down geometrically.)
    func saveAndDecreaseVolume() {
        queue.async { [self] in saveAndDecreaseOnQueue() }
    }

    private func saveAndDecreaseOnQueue() {
        let baseline: Float
        if let existing = savedVolume {
            baseline = existing
        } else {
            guard let current = getSystemVolume() else { return }
            baseline = current
            savedVolume = current
        }
        let target = baseline * decreaseRatio
        let from = getSystemVolume() ?? baseline
        startFade(from: from, to: target, duration: fadeDownDuration)
    }

    /// 恢复到原始音量。
    /// 关键修复：在 fade *完成* 后才清空 `savedVolume`；如果在恢复中又被
    /// `saveAndDecreaseVolume` 打断，本次 onComplete 不会触发，原始基准得以保留。
    /// (Clear `savedVolume` only when the restore fade fully completes; if interrupted
    /// by another decrease, the baseline is preserved for the next restore.)
    func restoreVolume() {
        queue.async { [self] in restoreOnQueue() }
    }

    private func restoreOnQueue() {
        guard let saved = savedVolume else { return }
        let current = getSystemVolume() ?? saved
        startFade(from: current, to: saved, duration: fadeUpDuration) { [weak self] in
            self?.savedVolume = nil
        }
    }

    deinit {
        stopFade()
        if let saved = savedVolume {
            setSystemVolume(saved)
        }
    }
}
