import Carbon
import Foundation

@MainActor
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var fallbackHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    var onPressed: (() -> Void)?

    init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let pointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { manager.onPressed?() }
                return noErr
            },
            1,
            &eventType,
            pointer,
            &eventHandlerRef
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x53455048), id: 1) // SEPH
        RegisterEventHotKey(
            UInt32(kVK_F8),
            0,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        let fallbackID = EventHotKeyID(signature: OSType(0x53455048), id: 2)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_I),
            UInt32(optionKey | cmdKey),
            fallbackID,
            GetApplicationEventTarget(),
            0,
            &fallbackHotKeyRef
        )
    }

}
