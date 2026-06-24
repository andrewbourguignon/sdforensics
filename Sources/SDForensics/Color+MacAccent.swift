import SwiftUI

#if os(macOS)
import AppKit
#endif

extension Color {
    public static var macAccent: Color {
        #if os(macOS)
        return Color(NSColor.controlAccentColor)
        #else
        return .accentColor
        #endif
    }
}
