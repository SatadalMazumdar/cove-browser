import SwiftUI

// MARK: - Drafts

/// The space editor's form. Nothing reaches the store until Save.
@MainActor
final class SpaceDraft: ObservableObject {
    let editing: Space?
    @Published var name: String
    @Published var icon: String
    @Published var theme: SpaceTheme
    @Published var twoColours: Bool
    /// Nil makes a new profile. Otherwise the new space shares this profile's cookies and logins.
    @Published var profileID: UUID?

    init(editing space: Space?) {
        editing = space
        name = space?.name ?? ""
        icon = space?.icon ?? "star.fill"
        theme = space?.theme ?? SpaceTheme(hue: Double.random(in: 0...1))
        twoColours = space?.theme.secondHue != nil
        profileID = nil
    }
}

@MainActor
final class ArcImportDraft: ObservableObject {
    let plan: ArcImport?
    let failure: String?
    @Published var chosen: Set<Int>
    @Published var includeToday = false
    @Published var replace: Bool

    init(replace: Bool) {
        self.replace = replace
        do {
            let plan = try ArcImport.read()
            self.plan = plan
            failure = nil
            chosen = Set(plan.spaces.indices)
        } catch {
            plan = nil
            failure = error.localizedDescription
            chosen = []
        }
    }
}

// MARK: - Host

/// Dims the window and centres a panel over it, the same way the command bar sits.
struct PanelHost: View {
    @ObservedObject var store: BrowserStore
    let panel: Panel
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .contentShape(Rectangle())
                .onTapGesture { store.closePanel() }

            Group {
                switch panel {
                case .space(let draft): SpaceEditor(store: store, draft: draft)
                case .arcImport(let draft): ArcImportPanel(store: store, draft: draft)
                case .settings: SettingsPanel(store: store)
                case .userscripts: UserscriptsPanel(store: store)
                }
            }
            .padding(22)
            .frame(width: 460)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hue: theme.hue, saturation: 0.25, brightness: 0.13))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.45), radius: 40, y: 18)
            }
            // The panel is always dark, so system controls inside it must draw for a dark background.
            .environment(\.colorScheme, .dark)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PanelTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FieldLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PanelButton: View {
    let title: String
    var primary = false
    var enabled = true
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(enabled ? 0.95 : 0.35))
                .padding(.horizontal, 16)
                .frame(height: 30)
                .background(primary ? theme.accent.opacity(enabled ? 0.6 : 0.2) : .white.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Space icons are SF Symbols, never emoji. A clean set keeps the sidebar looking like one app.
enum SpaceIcons {
    /// The set offered in the editor.
    static let choices = [
        "globe", "house.fill", "briefcase.fill", "leaf.fill", "book.fill", "graduationcap.fill",
        "paintbrush.pointed.fill", "hammer.fill", "chart.bar.fill", "cart.fill", "creditcard.fill", "bolt.fill",
        "flame.fill", "star.fill", "heart.fill", "bookmark.fill", "folder.fill", "tray.full.fill",
        "cube.fill", "sparkles", "terminal.fill", "camera.fill", "music.note", "gamecontroller.fill",
    ]
    static let fallback = "globe"

    /// Old spaces stored an emoji. Map the ones the app and the Arc importer produced to a symbol,
    /// so nothing shows an emoji after the switch. Anything unmapped becomes the fallback.
    private static let fromEmoji: [String: String] = [
        "🪐": "globe", "📁": "folder.fill", "🩺": "cross.case.fill", "💡": "lightbulb.fill",
        "💀": "flame.fill", "⭐️": "star.fill", "❤️": "heart.fill", "🏠": "house.fill",
        "📖": "book.fill", "💼": "briefcase.fill", "💻": "terminal.fill", "🎮": "gamecontroller.fill",
        "🎵": "music.note", "🍃": "leaf.fill", "🔥": "flame.fill", "🌙": "moon.fill",
        "☀️": "sun.max.fill", "☁️": "cloud.fill", "✈️": "airplane", "🛒": "cart.fill",
        "☕️": "cup.and.saucer.fill", "🍕": "fork.knife", "🎓": "graduationcap.fill", "🖌️": "paintbrush.fill",
        "📷": "camera.fill", "🔖": "bookmark.fill", "🧪": "flask.fill", "⚽️": "sportscourt.fill",
        "🐾": "pawprint.fill", "🚀": "sparkles", "⌨️": "keyboard.fill", "👛": "creditcard.fill",
        "🎁": "gift.fill", "🌸": "camera.macro", "🏋️": "figure.strengthtraining.traditional", "🎬": "film.fill",
        "💎": "diamond.fill", "🌍": "globe", "✉️": "envelope.fill", "👥": "person.2.fill",
        "👤": "person.fill", "⚡️": "bolt.fill",
    ]

    /// Turns whatever is stored into an SF Symbol name.
    static func symbol(_ icon: String) -> String {
        if icon.unicodeScalars.allSatisfy(\.isASCII) { return icon }
        return fromEmoji[icon] ?? fallback
    }
}

struct SpaceIcon: View {
    let icon: String
    var size: CGFloat = 12

    var body: some View {
        Image(systemName: SpaceIcons.symbol(icon)).font(.system(size: size, weight: .medium))
    }
}

// MARK: - Space editor

struct SpaceEditor: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var draft: SpaceDraft
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 14) {
            PanelTitle(text: draft.editing == nil ? "New Space" : "Edit Space")

            HStack(spacing: 12) {
                swatch
                TextField("Name", text: $draft.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .focused($nameFocused)
                    .onSubmit { store.save(draft) }
            }

            FieldLabel(text: "ICON")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 12), spacing: 4) {
                ForEach(SpaceIcons.choices, id: \.self) { icon in
                    SpaceIcon(icon: icon, size: 13)
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 30, height: 30)
                        .background(draft.icon == icon ? .white.opacity(0.22) : .white.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .contentShape(Rectangle())
                        .onTapGesture { draft.icon = icon }
                }
            }

            FieldLabel(text: "COLOUR")
            hueSlider($draft.theme.hue)
            Toggle("Second colour for the gradient", isOn: $draft.twoColours)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
            if draft.twoColours { hueSlider(secondHueBinding) }
            HStack(spacing: 10) {
                Text("Intensity").font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                Slider(value: $draft.theme.intensity, in: 0...1)
            }
            Picker("", selection: $draft.theme.mode) {
                Text("Match System").tag(SpaceTheme.Mode.auto)
                Text("Light").tag(SpaceTheme.Mode.light)
                Text("Dark").tag(SpaceTheme.Mode.dark)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            FieldLabel(text: "PROFILE")
            if let space = draft.editing {
                let shared = store.spaces(using: space.profile).count
                Text(shared > 1 ? "\(space.profile.name), shared by \(shared) spaces" : space.profile.name)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Picker("", selection: $draft.profileID) {
                    Text("New profile, with its own logins").tag(UUID?.none)
                    ForEach(store.profiles) { profile in
                        Text("Share logins with \(profile.name)").tag(UUID?.some(profile.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("Saved passwords come from iCloud Keychain and work in every profile.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                Spacer()
                PanelButton(title: "Cancel") { store.closePanel() }
                PanelButton(title: draft.editing == nil ? "Create" : "Save", primary: true,
                            enabled: !draft.name.trimmingCharacters(in: .whitespaces).isEmpty) {
                    store.save(draft)
                }
            }
            .padding(.top, 4)
        }
        .onAppear { DispatchQueue.main.async { nameFocused = true } }
        .onChange(of: draft.twoColours) { _, on in
            draft.theme.secondHue = on ? (draft.theme.hue + 0.2).truncatingRemainder(dividingBy: 1) : nil
        }
    }

    /// A small piece of the window as it will look.
    private var swatch: some View {
        let theme = Theme(draft.theme, systemDark: true)
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(LinearGradient(colors: [theme.backgroundTop, theme.backgroundBottom],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 38, height: 38)
            .overlay { SpaceIcon(icon: draft.icon, size: 15).foregroundStyle(theme.text.opacity(0.85)) }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 1)
            }
    }

    private var secondHueBinding: Binding<Double> {
        Binding(get: { draft.theme.resolvedSecondHue }, set: { draft.theme.secondHue = $0 })
    }

    private func hueSlider(_ value: Binding<Double>) -> some View {
        VStack(spacing: 2) {
            LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 0.1).map {
                Color(hue: $0, saturation: 0.6, brightness: 0.8)
            }, startPoint: .leading, endPoint: .trailing)
                .frame(height: 6)
                .clipShape(Capsule())
                .padding(.horizontal, 8)
            Slider(value: value, in: 0...0.999)
        }
    }
}

// MARK: - Arc import

struct ArcImportPanel: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var draft: ArcImportDraft

    var body: some View {
        VStack(spacing: 14) {
            PanelTitle(text: "Import from Arc")

            if let plan = draft.plan {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(Array(plan.spaces.enumerated()), id: \.offset) { index, space in
                            row(index, space, profile: plan.profiles.first { $0.key == space.profileKey })
                        }
                    }
                }
                .frame(maxHeight: 280)

                VStack(spacing: 6) {
                    option("Also bring over the open tabs under each space", isOn: $draft.includeToday)
                    option("Replace the spaces I have now", isOn: $draft.replace)
                }
                Text("Logins and saved passwords stay in Arc. Arc locks them with a key that only Arc should read, so you will sign in to each site again here. To move passwords, export them from Arc and import the file into the Passwords app.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(draft.failure ?? "Arc's data could not be read.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                Spacer()
                PanelButton(title: "Cancel") { store.closePanel() }
                if let plan = draft.plan {
                    PanelButton(title: draft.chosen.count == 1 ? "Import 1 Space" : "Import \(draft.chosen.count) Spaces", primary: true, enabled: !draft.chosen.isEmpty) {
                        store.apply(plan, options: ArcImportOptions(
                            chosen: draft.chosen, includeToday: draft.includeToday, replaceExisting: draft.replace
                        ))
                        store.closePanel()
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func option(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.8))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ index: Int, _ space: ArcImport.SpaceRecord, profile: ArcImport.ProfileRecord?) -> some View {
        let on = draft.chosen.contains(index)
        var parts = ["\(space.pinnedTabCount) pinned"]
        if space.folderCount > 0 { parts.append(space.folderCount == 1 ? "1 folder" : "\(space.folderCount) folders") }
        if draft.includeToday, !space.today.isEmpty { parts.append("\(space.today.count) open") }
        if let profile {
            parts.append("\(profile.name) profile")
            if !profile.favorites.isEmpty { parts.append("\(profile.favorites.count) favorites") }
        }
        let theme = Theme(space.theme, systemDark: true)
        return HStack(spacing: 10) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(on ? 0.9 : 0.3))
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(LinearGradient(colors: [theme.backgroundTop, theme.backgroundBottom],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 26, height: 26)
                .overlay { SpaceIcon(icon: space.icon, size: 11).foregroundStyle(theme.text.opacity(0.85)) }
            VStack(alignment: .leading, spacing: 1) {
                Text(space.name).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.92))
                Text(parts.joined(separator: ", ")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(.white.opacity(on ? 0.07 : 0.03), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            if on { draft.chosen.remove(index) } else { draft.chosen.insert(index) }
        }
    }
}

// MARK: - Settings

struct SettingsPanel: View {
    @ObservedObject var store: BrowserStore

    /// Tab-sleeping choices. 0 is never.
    private let sleepOptions: [(String, TimeInterval)] = [
        ("Off", 0), ("5 min", 300), ("10 min", 600), ("30 min", 1800),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelTitle(text: "Settings")

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "TAB SLEEPING")
                Picker("", selection: sleepBinding) {
                    ForEach(sleepOptions, id: \.1) { Text($0.0).tag($0.1) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(store.idleSeconds == 0
                     ? "Tabs stay loaded until you close them. Fastest to switch back to, uses the most memory."
                     : "A tab you have not touched for this long unloads and reloads when you return. Lower saves memory.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel(text: "SEARCH ENGINE")
                    Picker("", selection: Binding(get: { store.searchEngine }, set: { store.setSearchEngine($0) })) {
                        ForEach(SearchEngine.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    .labelsHidden()
                }
                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel(text: "APPEARANCE")
                    Picker("", selection: Binding(get: { store.appearance }, set: { store.setAppearance($0) })) {
                        ForEach(Appearance.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "PRIVACY")
                Toggle(isOn: Binding(get: { store.blockingEnabled }, set: { store.setBlocking($0) })) {
                    Text("Block ads and trackers")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .toggleStyle(.switch)
                Text("Drops requests to known ad and analytics hosts. Rule-list based, so it stops most display ads and trackers but not script-injected video ads.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(isOn: Binding(get: { store.passwordsEnabled }, set: { store.setPasswords($0) })) {
                    Text("Offer to save and fill passwords")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.85))
                }
                .toggleStyle(.switch)
                .padding(.top, 4)
                HStack(spacing: 12) {
                    Text("\(PasswordManager.shared.count) saved in Clove's own keychain store.")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                    if PasswordManager.shared.count > 0 {
                        Button("Forget all") { PasswordManager.shared.forgetAll(); store.objectWillChange.send() }
                            .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(hue: 0.0, saturation: 0.6, brightness: 0.95))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "NOW LOADED")
                Text("\(store.loadedTabCount) of \(store.everyTab.count) tabs are using memory.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
                Button("Sleep background tabs now") { store.unloadNow() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hue: 0.62, saturation: 0.5, brightness: 0.95))
            }

            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(text: "SPACES AND APPEARANCE")
                Text("Each space has its own icon, colours and light or dark setting. Right-click a space, or open it from the New menu, to change them.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                PanelButton(title: "Done", primary: true) { store.closePanel() }
            }
            .padding(.top, 2)
        }
    }

    private var sleepBinding: Binding<TimeInterval> {
        Binding(get: { store.idleSeconds }, set: { store.setIdle($0) })
    }
}

// MARK: - Userscripts

struct UserscriptsPanel: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var scripts = UserscriptStore.shared
    @Local private var selected: UUID?

    private var current: Int? { scripts.scripts.firstIndex { $0.id == selected } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelTitle(text: "Userscripts")
            Text("Custom JavaScript that runs on matching sites. Clove's stand-in for extensions.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))

            HStack(alignment: .top, spacing: 12) {
                // The list of scripts.
                VStack(spacing: 2) {
                    ForEach(scripts.scripts) { script in
                        row(script)
                    }
                    Button { scripts.add(); selected = scripts.scripts.last?.id } label: {
                        Label("Add Script", systemImage: "plus")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).frame(height: 32)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
                .frame(width: 160)
                .frame(maxHeight: 280)

                // The editor for the selected script.
                if let index = current {
                    editor(index)
                } else {
                    Text("Select a script, or add one.")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(height: 300)

            HStack {
                Spacer()
                PanelButton(title: "Done", primary: true) { store.closePanel() }
            }
        }
        .frame(width: 560)
    }

    private func row(_ script: Userscript) -> some View {
        HStack(spacing: 6) {
            Circle().fill(script.enabled ? Color.green.opacity(0.8) : .white.opacity(0.2)).frame(width: 6, height: 6)
            Text(script.name).font(.system(size: 12)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10).frame(height: 30)
        .background(selected == script.id ? .white.opacity(0.1) : .clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { selected = script.id }
    }

    private func editor(_ index: Int) -> some View {
        let binding = $scripts.scripts[index]
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Name", text: binding.name)
                    .textFieldStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                    .padding(.horizontal, 8).frame(height: 28)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                Toggle("", isOn: binding.enabled).toggleStyle(.switch).labelsHidden()
            }
            HStack(spacing: 6) {
                Text("Runs on").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                TextField("*  or  example.com", text: binding.match)
                    .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(.white)
                    .padding(.horizontal, 8).frame(height: 26)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            }
            TextEditor(text: binding.code)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("Delete") { let s = scripts.scripts[index]; selected = nil; scripts.delete(s) }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.red.opacity(0.9))
                Spacer()
                Button("Save and Apply") { scripts.save() }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(theme.accent)
            }
        }
    }

    @Environment(\.theme) private var theme
}
