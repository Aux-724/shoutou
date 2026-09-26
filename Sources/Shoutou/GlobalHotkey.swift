import Carbon
import Foundation

@MainActor
final class HotkeyBridge {
    static let shared = HotkeyBridge()
    var onPress: (() -> Void)?
}

final class GlobalHotkey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func register() -> Bool {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyCallback,
            1,
            &spec,
            nil,
            &handlerRef
        )
        guard installed == noErr else { return false }

        let hotKeyID = EventHotKeyID(signature: 0x5348_4F55, id: 1)
        let keyCodeSpace: UInt32 = 0x31
        let optionOnly: UInt32 = 1 << 11
        let registered = RegisterEventHotKey(
            keyCodeSpace,
            optionOnly,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        return registered == noErr
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }
}

private let hotkeyCallback: EventHandlerUPP = { _, _, _ in
    Task { @MainActor in
        HotkeyBridge.shared.onPress?()
    }
    return noErr
}
