import SwiftUI

/// Colours for one space. The whole window is tinted with the space's hue.
struct Theme {
    var hue: Double = 0.72
    var dark: Bool = true

    var backgroundTop: Color {
        dark ? Color(hue: hue, saturation: 0.42, brightness: 0.24)
             : Color(hue: hue, saturation: 0.20, brightness: 0.96)
    }
    var backgroundBottom: Color {
        let shifted = (hue + 0.07).truncatingRemainder(dividingBy: 1)
        return dark ? Color(hue: shifted, saturation: 0.48, brightness: 0.17)
                    : Color(hue: shifted, saturation: 0.26, brightness: 0.92)
    }
    var accent: Color { Color(hue: hue, saturation: 0.55, brightness: dark ? 0.85 : 0.65) }
    var text: Color { dark ? .white : .black }
    var primary: Color { text.opacity(0.9) }
    var secondary: Color { text.opacity(0.55) }
    var faint: Color { text.opacity(0.12) }
    var hover: Color { text.opacity(0.07) }
    var pill: Color { text.opacity(0.09) }
    var selected: Color { dark ? Color.white.opacity(0.17) : Color.white.opacity(0.92) }
    var selectedShadow: Color { dark ? .clear : Color.black.opacity(0.10) }
    var card: Color { dark ? Color(white: 0.11) : .white }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme()
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

enum Metrics {
    static let sidebarWidth: CGFloat = 244
    static let gutter: CGFloat = 8
    static let cardRadius: CGFloat = 10
    static let rowHeight: CGFloat = 34
    static let rowRadius: CGFloat = 9
}

/// View-local state. Stands in for `@State`, which the macOS 27 SDK turned into a macro
/// whose compiler plugin ships with Xcode but not with the Command Line Tools.
@propertyWrapper
struct Local<Value>: DynamicProperty {
    private var state: State<Value>

    init(wrappedValue: Value) {
        state = State(initialValue: wrappedValue)
    }

    var wrappedValue: Value {
        get { state.wrappedValue }
        nonmutating set { state.wrappedValue = newValue }
    }

    var projectedValue: Binding<Value> { state.projectedValue }
}
