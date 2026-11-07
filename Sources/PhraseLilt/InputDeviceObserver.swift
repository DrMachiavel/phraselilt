import AppKit
import CoreAudio

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
