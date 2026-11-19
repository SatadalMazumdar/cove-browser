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

/// Draws an emoji as text and anything else as an SF Symbol.
struct SpaceIcon: View {
    let icon: String
    var size: CGFloat = 12

    static func isSymbol(_ icon: String) -> Bool {
        icon.unicodeScalars.allSatisfy(\.isASCII)
    }

    var body: some View {
        if Self.isSymbol(icon) {
            Image(systemName: icon).font(.system(size: size, weight: .medium))
        } else {
            Text(icon).font(.system(size: size + 1))
        }
    }
}

// MARK: - Space editor

struct SpaceEditor: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var draft: SpaceDraft
    @FocusState private var nameFocused: Bool

    private static let icons = [
        "star.fill", "leaf.fill", "briefcase.fill", "house.fill", "heart.fill", "book.fill",
        "gamecontroller.fill", "cart.fill", "paintbrush.fill", "airplane", "music.note", "bolt.fill",
        "🪐", "💡", "🧪", "🎓", "🚀", "☕️", "🎬", "💼", "🌙", "🔥", "🐾", "💀",
    ]

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
                ForEach(Self.icons, id: \.self) { icon in
                    SpaceIcon(icon: icon, size: 13)
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 30, height: 30)
                        .background(draft.icon == icon ? .white.opacity(0.22) : .white.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .contentShape(Rectangle())
                        .onTapGesture { draft.icon = icon }
                }
            }
            HStack(spacing: 8) {
                Text("Or type any emoji")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                TextField("", text: emojiBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
                    .frame(width: 44, height: 28)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Spacer()
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

    private var emojiBinding: Binding<String> {
        Binding(
            get: { SpaceIcon.isSymbol(draft.icon) ? "" : draft.icon },
            set: { text in
                // Keep the last character typed, so a new emoji replaces the old one.
                if let last = text.last, !SpaceIcon.isSymbol(String(last)) { draft.icon = String(last) }
            }
        )
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
