import AppKit
import Testing

@testable import PhraseLilt

@Test @MainActor func allMenuBarStatesHaveAnAvailableSystemImage() {
  for symbol in MenuBarSymbol.allCases {
    #expect(
      NSImage(systemSymbolName: symbol.rawValue, accessibilityDescription: nil) != nil,
      "Missing menu-bar image: \(symbol.rawValue)")
  }
}
