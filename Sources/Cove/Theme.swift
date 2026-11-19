import SwiftUI

/// What a space stores about its look. `Theme` turns this into colours.
struct SpaceTheme: Codable, Equatable {
    enum Mode: String, Codable, CaseIterable { case auto, light, dark }

    var hue: Double = 0.72
    /// The gradient's far corner. Nil means a small shift from `hue`.
    var secondHue: Double?
    /// 0 is nearly grey, 1 is saturated.
    var intensity: Double = 0.5
    var mode: Mode = .auto

    var resolvedSecondHue: Double {
        secondHue ?? (hue + 0.07).truncatingRemainder(dividingBy: 1)
    }

    func isDark(system: Bool) -> Bool {
        mode == .auto ? system : mode == .dark
    }
}

/// Colours for one space. The whole window is tinted with the space's hue.
struct Theme {
    var hue: Double = 0.72
    var secondHue: Double = 0.79
    var intensity: Double = 0.5
    var dark: Bool = true

    init() {}

    init(_ theme: SpaceTheme, systemDark: Bool) {
        hue = theme.hue
        secondHue = theme.resolvedSecondHue
        intensity = theme.intensity
        dark = theme.isDark(system: systemDark)
    }

    /// The tint part of the way through a swipe from one space to the next.
    static func between(_ a: SpaceTheme, _ b: SpaceTheme, fraction: Double, systemDark: Bool) -> Theme {
        var theme = Theme()
        theme.hue = mixHue(a.hue, b.hue, fraction)
        theme.secondHue = mixHue(a.resolvedSecondHue, b.resolvedSecondHue, fraction)
        theme.intensity = a.intensity + (b.intensity - a.intensity) * fraction
        theme.dark = (fraction < 0.5 ? a : b).isDark(system: systemDark)
        return theme
    }

    /// Hue is a circle, so the blend takes the short way round.
    private static func mixHue(_ a: Double, _ b: Double, _ fraction: Double) -> Double {
        var delta = b - a
        if delta > 0.5 { delta -= 1 }
        if delta < -0.5 { delta += 1 }
        let mixed = a + delta * fraction
        return mixed - mixed.rounded(.down)
    }

    private var strength: Double { 0.4 + 1.2 * intensity }

    var backgroundTop: Color {
        dark ? Color(hue: hue, saturation: min(1, 0.42 * strength), brightness: 0.24)
             : Color(hue: hue, saturation: min(1, 0.20 * strength), brightness: 0.96)
    }
    var backgroundBottom: Color {
        dark ? Color(hue: secondHue, saturation: min(1, 0.48 * strength), brightness: 0.17)
             : Color(hue: secondHue, saturation: min(1, 0.26 * strength), brightness: 0.92)
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
