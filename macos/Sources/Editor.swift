import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = Int(s, radix: 16) ?? 0x7DC8FF
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// Éditeur des boutons : pages à gauche, grille au centre, réglages du bouton à droite.
struct EditorView: View {
    @ObservedObject var store: DeckStore
    @State private var deckID: UUID?
    @State private var buttonID: UUID?
    @Environment(\.colorScheme) private var scheme

    private var deckIndex: Int? { store.decks.firstIndex { $0.id == deckID } ?? (store.decks.isEmpty ? nil : 0) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 190)
            Rectangle().fill(Theme.line(scheme)).frame(width: 1)
            grid.frame(maxWidth: .infinity)
            Rectangle().fill(Theme.line(scheme)).frame(width: 1)
            inspector.frame(width: 320)
        }
        .frame(minWidth: 900, minHeight: 560)
        .background(Theme.background(scheme))
        .onAppear { deckID = store.decks.first?.id }
    }

    // MARK: Pages

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PAGES").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accentText(scheme))
                .padding(.horizontal, 14).padding(.top, 14)
            ForEach(store.decks.indices, id: \.self) { i in
                let selected = i == deckIndex
                TextField("Nom", text: $store.decks[i].name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Theme.accentUI.opacity(0.18) : .clear))
                    .contentShape(Rectangle())
                    .onTapGesture { deckID = store.decks[i].id; buttonID = nil }
                    .padding(.horizontal, 6)
            }
            HStack {
                Button { addDeck() } label: { Image(systemName: "plus") }.help("Nouvelle page")
                Button { deleteDeck() } label: { Image(systemName: "minus") }.help("Supprimer la page")
                    .disabled(store.decks.count <= 1)
                Button { moveDeck(-1) } label: { Image(systemName: "chevron.up") }.help("Monter")
                Button { moveDeck(1) } label: { Image(systemName: "chevron.down") }.help("Descendre")
            }
            .buttonStyle(.borderless).padding(14)
            Spacer()
            Button("Boutons de départ…") { confirmReset() }.buttonStyle(.borderless)
                .font(.system(size: 11)).padding(14)
        }
        .background(Theme.surface(scheme).opacity(0.5))
    }

    private func addDeck() {
        store.decks.append(Deck(name: "Nouvelle page", buttons: []))
        deckID = store.decks.last?.id
    }

    private func deleteDeck() {
        guard let i = deckIndex, store.decks.count > 1 else { return }
        store.decks.remove(at: i)
        deckID = store.decks.first?.id
        buttonID = nil
    }

    private func moveDeck(_ d: Int) {
        guard let i = deckIndex, store.decks.indices.contains(i + d) else { return }
        store.decks.swapAt(i, i + d)
    }

    private func confirmReset() {
        let a = NSAlert()
        a.messageText = "Revenir aux boutons de départ ?"
        a.informativeText = "Tes pages et boutons actuels seront remplacés."
        a.addButton(withTitle: "Remplacer")
        a.addButton(withTitle: "Annuler")
        if a.runModal() == .alertFirstButtonReturn {
            store.resetToDefaults()
            deckID = store.decks.first?.id
            buttonID = nil
        }
    }

    // MARK: Grille

    private var grid: some View {
        ScrollView {
            if let di = deckIndex {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(104), spacing: 12), count: 5), spacing: 12) {
                    ForEach(store.decks[di].buttons) { b in
                        tile(b).onTapGesture { buttonID = b.id }
                    }
                    Button { addButton() } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "plus").font(.system(size: 22))
                            Text("Ajouter").font(.system(size: 11))
                        }
                        .frame(width: 104, height: 104)
                        .background(RoundedRectangle(cornerRadius: 18).stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5])))
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
        }
    }

    private func tile(_ b: DeckButton) -> some View {
        let c = Color(hex: b.color)
        return VStack(spacing: 6) {
            Text(b.icon).font(.system(size: 30))
            Text(b.label).font(.system(size: 11, weight: .semibold)).multilineTextAlignment(.center).lineLimit(2)
        }
        .frame(width: 104, height: 104)
        .background(RoundedRectangle(cornerRadius: 18).fill(c.opacity(0.2)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(b.id == buttonID ? Theme.accentUI : c, lineWidth: b.id == buttonID ? 3 : 1.5))
    }

    private func addButton() {
        guard let di = deckIndex else { return }
        let b = DeckButton(label: "Nouveau", icon: "✨", color: Defaults.blue, action: DeckAction(kind: .shortcut))
        store.decks[di].buttons.append(b)
        buttonID = b.id
    }

    // MARK: Réglages du bouton

    @ViewBuilder private var inspector: some View {
        if let di = deckIndex, let bi = store.decks[di].buttons.firstIndex(where: { $0.id == buttonID }) {
            ButtonInspector(button: $store.decks[di].buttons[bi],
                            onDelete: { store.decks[di].buttons.remove(at: bi); buttonID = nil },
                            onMove: { d in
                                let j = bi + d
                                if store.decks[di].buttons.indices.contains(j) { store.decks[di].buttons.swapAt(bi, j) }
                            },
                            onTest: { a in Task { _ = await Actions.perform(a) } })
                .id(buttonID)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "hand.tap").font(.system(size: 28)).foregroundStyle(.secondary)
                Text("Choisis un bouton pour le modifier").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct ButtonInspector: View {
    @Binding var button: DeckButton
    var onDelete: () -> Void
    var onMove: (Int) -> Void
    var onTest: (DeckAction) -> Void
    @State private var recording = false
    @State private var monitor: Any?
    @Environment(\.colorScheme) private var scheme

    static let colors = ["#7DC8FF", "#1F7FC8", "#2A2D33", "#5FD39A", "#FFC861", "#FF8A5B", "#FF6B6B", "#C49BFF"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                field("Nom") { TextField("Nom", text: $button.label) }
                field("Icône (un emoji)") {
                    HStack {
                        TextField("🎬", text: $button.icon).frame(width: 60)
                        Button("Choisir…") { NSApp.orderFrontCharacterPalette(nil) }
                    }
                }
                field("Couleur") {
                    HStack(spacing: 6) {
                        ForEach(Self.colors, id: \.self) { c in
                            Circle().fill(Color(hex: c)).frame(width: 22, height: 22)
                                .overlay(Circle().stroke(Color.primary, lineWidth: button.color == c ? 2 : 0))
                                .onTapGesture { button.color = c }
                        }
                    }
                }
                field("Action") {
                    Picker("", selection: $button.action.kind) {
                        ForEach(ActionKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                }
                actionFields
                HStack {
                    Button("Tester") { onTest(button.action) }
                    Spacer()
                    Button { onMove(-1) } label: { Image(systemName: "arrow.left") }.help("Déplacer avant")
                    Button { onMove(1) } label: { Image(systemName: "arrow.right") }.help("Déplacer après")
                    Button(role: .destructive) { onDelete() } label: { Image(systemName: "trash") }.help("Supprimer")
                }
            }
            .padding(18)
        }
        .onDisappear { stopRecording() }
    }

    @ViewBuilder private var actionFields: some View {
        switch button.action.kind {
        case .shortcut:
            field("Raccourci") {
                HStack {
                    Text(recording ? "Appuie sur les touches…" : (button.action.combo?.label ?? "—"))
                        .font(.system(size: 15, weight: .semibold).monospaced())
                        .frame(minWidth: 120, alignment: .leading)
                    Button(recording ? "Annuler" : "Enregistrer") { recording ? stopRecording() : startRecording() }
                }
            }
            field("Envoyer à") {
                Picker("", selection: Binding(get: { button.action.targetApp ?? "" },
                                              set: { button.action.targetApp = $0.isEmpty ? nil : $0 })) {
                    Text("L'appli au premier plan").tag("")
                    ForEach(runningApps, id: \.0) { Text($0.1).tag($0.0) }
                    if let t = button.action.targetApp, !runningApps.contains(where: { $0.0 == t }) {
                        Text(appName(t)).tag(t)
                    }
                }
                .labelsHidden()
            }
        case .app:
            field("Appli") {
                HStack {
                    Text(button.action.value.map(appName) ?? "Aucune").lineLimit(1)
                    Spacer()
                    Button("Choisir…") { pickApp() }
                }
            }
        case .url:
            field("Lien") { TextField("https://…", text: value) }
        case .text:
            field("Texte à taper") { TextEditor(text: value).frame(height: 80).font(.system(size: 13)) }
        case .appleShortcut:
            field("Nom du Raccourci (app Raccourcis)") { TextField("Ex. Mode concentration", text: value) }
        case .command:
            field("Commande") { TextField("Ex. open ~/Documents/Montage", text: value).font(.system(size: 12).monospaced()) }
            Text("Exécutée sur ton Mac quand tu appuies sur le bouton.").font(.system(size: 11)).foregroundStyle(.secondary)
        case .media:
            field("Touche") {
                Picker("", selection: Binding(get: { button.action.media ?? .playPause }, set: { button.action.media = $0 })) {
                    ForEach(MediaKey.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
            }
        case .none:
            EmptyView()
        }
    }

    private var value: Binding<String> {
        Binding(get: { button.action.value ?? "" }, set: { button.action.value = $0 })
    }

    private var runningApps: [(String, String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { a in a.bundleIdentifier.map { ($0, a.localizedName ?? $0) } }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    private func appName(_ id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func pickApp() {
        let p = NSOpenPanel()
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        p.allowedContentTypes = [.applicationBundle]
        guard p.runModal() == .OK, let url = p.url else { return }
        button.action.value = Bundle(url: url)?.bundleIdentifier ?? url.path
        if button.label == "Nouveau" { button.label = url.deletingPathExtension().lastPathComponent }
    }

    private func field<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accentText(scheme))
            content()
        }
    }

    // MARK: Enregistrement d'un raccourci

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            MainActor.assumeIsolated {
                let f = e.modifierFlags
                button.action.combo = KeyCombo(key: Self.keyName(e), command: f.contains(.command), shift: f.contains(.shift),
                                               option: f.contains(.option), control: f.contains(.control))
                stopRecording()
            }
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    static func keyName(_ e: NSEvent) -> String {
        let named: [Int: String] = [
            kVK_Space: "space", kVK_Return: "return", kVK_Delete: "delete", kVK_Escape: "escape", kVK_Tab: "tab",
            kVK_LeftArrow: "left", kVK_RightArrow: "right", kVK_UpArrow: "up", kVK_DownArrow: "down",
            kVK_Home: "home", kVK_End: "end", kVK_PageUp: "pageup", kVK_PageDown: "pagedown",
            kVK_F1: "f1", kVK_F2: "f2", kVK_F3: "f3", kVK_F4: "f4", kVK_F5: "f5", kVK_F6: "f6", kVK_F7: "f7",
            kVK_F8: "f8", kVK_F9: "f9", kVK_F10: "f10", kVK_F11: "f11", kVK_F12: "f12",
            kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4", kVK_ANSI_5: "5",
            kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9", kVK_ANSI_0: "0",
        ]
        if let n = named[Int(e.keyCode)] { return n }
        if let c = e.characters(byApplyingModifiers: [])?.lowercased(), c.count == 1, c.first!.isLetter { return c }
        return "#\(e.keyCode)"
    }
}
