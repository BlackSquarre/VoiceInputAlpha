import Cocoa

final class FnKeyMonitor {
    private let onFnDown: () -> Void
    private let onFnUp: () -> Void
    var onTapDisabled: (() -> Void)?  // 权限丢失时通知外部
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fnIsDown = false

    private static let fnKeyCode: UInt16 = 0x3F  // 63

    init(onFnDown: @escaping () -> Void, onFnUp: @escaping () -> Void) {
        self.onFnDown = onFnDown
        self.onFnUp = onFnUp
    }

    func start() {
        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let monitor = Unmanaged<FnKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[FnKeyMonitor] 无法创建事件监听。请在系统设置 > 隐私与安全性 > 辅助功能中授权本应用。")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[FnKeyMonitor] 事件监听已启动")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            print("[FnKeyMonitor] 事件 tap 被系统禁用，正在重启...")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                // 如果是因为权限被撤销，tapEnable 后仍无法工作，通知外部
                if !CGEvent.tapIsEnabled(tap: tap) {
                    DispatchQueue.main.async { [weak self] in
                        self?.onTapDisabled?()
                    }
                }
            }
            return Unmanaged.passRetained(event)
        }

        let flags = event.flags
        let hasFn = flags.contains(.maskSecondaryFn)

        // 调试：记录所有 Fn 相关事件
        if type == .keyDown || type == .keyUp {
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            if keyCode == FnKeyMonitor.fnKeyCode || hasFn {
                print("[FnKeyMonitor] \(type == .keyDown ? "keyDown" : "keyUp") keyCode=\(keyCode) flags=\(flags.rawValue) hasFn=\(hasFn)")
            }

            // 拦截 Fn/Globe 键（keycode 63）
            if keyCode == FnKeyMonitor.fnKeyCode {
                if type == .keyDown && !fnIsDown {
                    fnIsDown = true
                    print("[FnKeyMonitor] >>> Fn 按下 (via keyDown)")
                    onFnDown()
                } else if type == .keyUp && fnIsDown {
                    fnIsDown = false
                    print("[FnKeyMonitor] >>> Fn 松开 (via keyUp)")
                    onFnUp()
                }
                return nil
            }
            return Unmanaged.passRetained(event)
        }

        if type == .flagsChanged {
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let otherModifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
            let hasOtherModifiers = !flags.intersection(otherModifiers).isEmpty

            print("[FnKeyMonitor] flagsChanged keyCode=\(keyCode) flags=\(flags.rawValue) hasFn=\(hasFn) hasOther=\(hasOtherModifiers)")

            // 方式 1: 通过 keyCode 63 判断
            if keyCode == FnKeyMonitor.fnKeyCode {
                if hasFn && !fnIsDown && !hasOtherModifiers {
                    fnIsDown = true
                    print("[FnKeyMonitor] >>> Fn 按下 (via flagsChanged keyCode)")
                    onFnDown()
                    return nil
                } else if !hasFn && fnIsDown {
                    fnIsDown = false
                    print("[FnKeyMonitor] >>> Fn 松开 (via flagsChanged keyCode)")
                    onFnUp()
                    return nil
                }
                return nil  // 吞掉 Fn 的 flagsChanged
            }

            // 方式 2: 纯 flag 判断（备用，某些机型 keyCode 不是 63）
            if hasFn && !fnIsDown && !hasOtherModifiers {
                fnIsDown = true
                print("[FnKeyMonitor] >>> Fn 按下 (via flagsChanged flags-only)")
                onFnDown()
                return nil
            } else if !hasFn && fnIsDown {
                fnIsDown = false
                print("[FnKeyMonitor] >>> Fn 松开 (via flagsChanged flags-only)")
                onFnUp()
                return nil
            }
        }

        return Unmanaged.passRetained(event)
    }
}
