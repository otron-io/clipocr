import Carbon
import Foundation

final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let onPress: () -> Void

    init(onPress: @escaping () -> Void) throws {
        self.onPress = onPress
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == 0x434F4352, id.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            let owner = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            owner.onPress()
            return noErr
        }, 1, &event, context, &eventHandler)
        guard handlerStatus == noErr else { throw HotKeyFailure(status: handlerStatus) }
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_6), UInt32(cmdKey | shiftKey),
                                         EventHotKeyID(signature: 0x434F4352, id: 1),
                                         GetApplicationEventTarget(), 0, &hotKey)
        guard status == noErr else {
            if let eventHandler { RemoveEventHandler(eventHandler) }
            self.eventHandler = nil
            throw HotKeyFailure(status: status)
        }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

private struct HotKeyFailure: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        "Could not register ⌘⇧6 (\(status)). Disable any conflicting shortcut in System Settings → Keyboard → Keyboard Shortcuts → Screenshots, then relaunch ClipOCR. Capture Text still works from the menu."
    }
}
