import AppKit
import Carbon
import CoreAudio
import CoreGraphics

private func hotKeyCallback(
  _ next: EventHandlerCallRef?, _ event: EventRef?, _ context: UnsafeMutableRawPointer?
) -> OSStatus {
  guard let event, let context else { return OSStatus(eventNotHandledErr) }
  let kind = GetEventKind(event)
  let shortcut = Unmanaged<HoldShortcut>.fromOpaque(context).takeUnretainedValue()
  MainActor.assumeIsolated { shortcut.receive(down: kind == UInt32(kEventHotKeyPressed)) }
  return noErr
}

@MainActor final class HoldShortcut {
  var pressed: (() -> Void)?
  var released: (() -> Void)?
  private var handler: EventHandlerRef?
  private var hotKey: EventHotKeyRef?
  private var watchdog: Timer?
  private(set) var held = false
  private var keyCode: UInt32 = 49
  func register(key: UInt32) -> Bool {
    unregister()
    keyCode = key
    var types = [
      EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
      EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
    ]
    let pointer = Unmanaged.passUnretained(self).toOpaque()
    guard
      InstallEventHandler(GetApplicationEventTarget(), hotKeyCallback, 2, &types, pointer, &handler)
        == noErr
    else { return false }
    let id = EventHotKeyID(signature: 0x504C_494C, id: 1)
    let result = RegisterEventHotKey(
      key, UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
    if result != noErr {
      unregister()
      return false
    }
    return true
  }
  func receive(down: Bool) {
    if down {
      guard !held else { return }
      held = true
      pressed?()
      // Key-state polling recovers lost Carbon key-up events without an event tap or Accessibility access.
      watchdog = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          if !CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(self.keyCode)) {
            self.release()
          }
        }
      }
    } else {
      release()
    }
  }
  func release() {
    watchdog?.invalidate()
    watchdog = nil
    guard held else { return }
    held = false
    released?()
  }
  func unregister() {
    release()
    if let hotKey { UnregisterEventHotKey(hotKey) }
    hotKey = nil
    if let handler { RemoveEventHandler(handler) }
    handler = nil
  }
}

@MainActor final class InputDeviceObserver {
  private var address = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultInputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)
  private var listener: AudioObjectPropertyListenerBlock?
  func start(_ changed: @escaping @MainActor () -> Void) {
    let callback: AudioObjectPropertyListenerBlock = { _, _ in Task { @MainActor in changed() } }
    listener = callback
    AudioObjectAddPropertyListenerBlock(
      AudioObjectID(kAudioObjectSystemObject), &address, .main, callback)
  }
  func stop() {
    if let listener {
      AudioObjectRemovePropertyListenerBlock(
        AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
    }
    listener = nil
  }
}
