import SwiftUI

#if os(macOS)
/// Mobile-only keyboard configuration is presentation guidance, not input validation.
/// These typed hints intentionally have no effect on a physical Mac keyboard.
enum FleetMobileKeyboardHint {
    case numberPad
    case decimalPad
    case numbersAndPunctuation
    case URL
    case asciiCapable
}

enum FleetMobileAutocapitalizationHint {
    case never
    case words
    case sentences
    case characters
}

enum FleetMobileNavigationTitleMode {
    case inline
    case large
}

extension View {
    /// Keeps shared form source compiling on macOS. The hint does not enforce validation.
    func keyboardType(_ hint: FleetMobileKeyboardHint) -> some View {
        self
    }

    /// Text capitalization is controlled by the user's Mac input source, not this mobile hint.
    func textInputAutocapitalization(_ hint: FleetMobileAutocapitalizationHint) -> some View {
        self
    }

    /// Navigation title sizing is controlled by the native Mac navigation container.
    func navigationBarTitleDisplayMode(_ mode: FleetMobileNavigationTitleMode) -> some View {
        self
    }
}
#endif
