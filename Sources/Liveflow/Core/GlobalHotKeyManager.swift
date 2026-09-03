import Foundation
import Carbon
import AppKit

/// System-wide global hotkey manager using Carbon APIs (does not require Accessibility permissions).
public final class GlobalHotKeyManager: @unchecked Sendable {
    public static let shared = GlobalHotKeyManager()

    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var isHandlerInstalled = false

    private init() {}

    public func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @MainActor @escaping () -> Void) {
        handlers[id] = handler

        if !isHandlerInstalled {
            installEventHandler()
        }

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C464C57) /* 'LFLW' */, id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr, let ref = hotKeyRef {
            hotKeyRefs[id] = ref
        } else {
            print("[GlobalHotKeyManager] Failed to register hotkey id \(id): status \(status)")
        }
    }

    public func unregister(id: UInt32) {
        if let ref = hotKeyRefs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        handlers.removeValue(forKey: id)
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            guard let event = event, let userData = userData else { return noErr }
            let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            if status == noErr {
                DispatchQueue.main.async {
                    manager.handlers[hotKeyID.id]?()
                }
            }

            return noErr
        }, 1, &eventType, selfPtr, nil)

        isHandlerInstalled = true
    }
}
