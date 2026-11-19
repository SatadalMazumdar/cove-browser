import SwiftUI

/// A small find-on-page bar in the top-right of the web card. Cmd+F opens it.
struct FindBar: View {
    @ObservedObject var store: BrowserStore
    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.secondary)
            TextField("Find on page", text: $store.findQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(theme.primary)
                .frame(width: 180)
                .focused($focused)
                .onSubmit { store.find(forward: true) }
                .onChange(of: store.findQuery) { _, _ in store.find(forward: true) }
                .onExitCommand { store.closeFind() }
            Divider().frame(height: 16)
            button("chevron.up") { store.find(forward: false) }
            button("chevron.down") { store.find(forward: true) }
            button("xmark") { store.closeFind() }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        // A solid background, not a blur, so it draws reliably over the web view's layer.
        .background(theme.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(theme.faint, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private func button(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
