import Foundation

/// Ce que fait un bouton.
enum ActionKind: String, Codable, CaseIterable {
    case shortcut, app, url, text, appleShortcut, command, media, none

    var title: String {
        switch self {
        case .shortcut: return "Raccourci clavier"
        case .app: return "Ouvrir une appli"
        case .url: return "Ouvrir un lien"
        case .text: return "Taper un texte"
        case .appleShortcut: return "Lancer un Raccourci (app Raccourcis)"
        case .command: return "Commande Terminal"
        case .media: return "Musique et volume"
        case .none: return "Rien"
        }
    }
}

enum MediaKey: String, Codable, CaseIterable {
    case playPause, next, previous, volumeUp, volumeDown, mute

    var title: String {
        switch self {
        case .playPause: return "Lecture / pause"
        case .next: return "Suivant"
        case .previous: return "Précédent"
        case .volumeUp: return "Volume +"
        case .volumeDown: return "Volume −"
        case .mute: return "Couper le son"
        }
    }
}

/// Un raccourci clavier : une touche (caractère ou code de touche) + modificateurs.
struct KeyCombo: Codable, Equatable {
    var key: String              // « b », « space », « delete », « 2 »…
    var command = false
    var shift = false
    var option = false
    var control = false

    var label: String {
        var s = ""
        if control { s += "⌃" }
        if option { s += "⌥" }
        if shift { s += "⇧" }
        if command { s += "⌘" }
        let names = ["space": "Espace", "return": "↩", "delete": "⌫", "escape": "Échap", "tab": "⇥",
                     "left": "←", "right": "→", "up": "↑", "down": "↓"]
        return s + (names[key] ?? key.uppercased())
    }
}

struct DeckAction: Codable, Equatable {
    var kind: ActionKind = .none
    var combo: KeyCombo?
    /// Appli à mettre au premier plan avant le raccourci (identifiant, ex. com.blackmagic-design.DaVinciResolve).
    var targetApp: String?
    var value: String?           // appli, lien, texte, nom du Raccourci, commande
    var media: MediaKey?
}

struct DeckButton: Codable, Equatable, Identifiable {
    var id = UUID()
    var label: String
    var icon: String             // emoji
    var color: String            // couleur hex
    var action: DeckAction
}

struct Deck: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var buttons: [DeckButton]
}

// MARK: - Boutons de départ

enum Defaults {
    static let blue = "#7DC8FF", deep = "#1F7FC8", grey = "#2A2D33", red = "#FF6B6B", green = "#5FD39A"
    static let resolve = "com.blackmagic-design.DaVinciResolve"

    static func key(_ label: String, _ icon: String, _ k: String, cmd: Bool = false, shift: Bool = false,
                    opt: Bool = false, ctrl: Bool = false, app: String? = nil, color: String = grey) -> DeckButton {
        DeckButton(label: label, icon: icon, color: color,
                   action: DeckAction(kind: .shortcut, combo: KeyCombo(key: k, command: cmd, shift: shift, option: opt,
                                                                       control: ctrl), targetApp: app))
    }

    static func media(_ label: String, _ icon: String, _ m: MediaKey, color: String = grey) -> DeckButton {
        DeckButton(label: label, icon: icon, color: color, action: DeckAction(kind: .media, media: m))
    }

    static var decks: [Deck] {
        let r = resolve
        return [
            Deck(name: "DaVinci", buttons: [
                key("Lecture", "▶️", "space", app: r, color: blue),
                key("Couper", "✂️", "b", cmd: true, app: r, color: blue),
                key("Marqueur", "📍", "m", app: r),
                key("Entrée", "⇤", "i", app: r),
                key("Sortie", "⇥", "o", app: r),
                key("Suppr. + raccord", "🧲", "delete", shift: true, app: r),
                key("Annuler", "↩️", "z", cmd: true, app: r),
                key("Rétablir", "↪️", "z", cmd: true, shift: true, app: r),
                key("Tout voir", "🔍", "z", shift: true, app: r),
                key("Magnétisme", "🧷", "n", app: r),
                key("Enregistrer", "💾", "s", cmd: true, app: r, color: green),
                key("Montage", "🎬", "4", shift: true, app: r, color: deep),
                key("Étalonnage", "🎨", "6", shift: true, app: r, color: deep),
                key("Fairlight", "🎚️", "7", shift: true, app: r, color: deep),
                key("Exportation", "🚀", "8", shift: true, app: r, color: deep),
            ]),
            Deck(name: "Mac", buttons: [
                media("Lecture / pause", "⏯️", .playPause, color: blue),
                media("Précédent", "⏮️", .previous),
                media("Suivant", "⏭️", .next),
                media("Volume −", "🔉", .volumeDown),
                media("Volume +", "🔊", .volumeUp),
                media("Muet", "🔇", .mute),
                key("Capture", "📸", "4", cmd: true, shift: true, color: deep),
                key("Spotlight", "🔎", "space", cmd: true),
                key("Verrouiller", "🔒", "q", cmd: true, ctrl: true, color: red),
                DeckButton(label: "DaVinci", icon: "🎞️", color: grey,
                           action: DeckAction(kind: .app, value: resolve)),
                DeckButton(label: "Finder", icon: "🗂️", color: grey,
                           action: DeckAction(kind: .app, value: "com.apple.finder")),
            ]),
            Deck(name: "AikoFlow", buttons: (1...9).map {
                key("Page \($0)", ["1️⃣", "2️⃣", "3️⃣", "4️⃣", "5️⃣", "6️⃣", "7️⃣", "8️⃣", "9️⃣"][$0 - 1], "\($0)",
                    opt: true, ctrl: true, color: $0 == 1 ? blue : grey)
            } + [
                key("Vue d'ensemble", "🗺️", "tab", opt: true, ctrl: true, color: deep),
                key("Plein écran", "⛶", "f", opt: true, ctrl: true),
                key("Rééquilibrer", "⚖️", "r", opt: true, ctrl: true),
            ]),
            Deck(name: "Aiko", buttons: [
                key("Bouclier", "🛡️", "s", opt: true, ctrl: true, color: blue),
                key("Mémoire", "🧠", "m", opt: true, ctrl: true, color: blue),
                key("Pipette", "💧", "c", opt: true, color: blue),
                key("AikoFlow on/off", "🪟", "p", opt: true, ctrl: true, color: deep),
            ]),
        ]
    }
}

// MARK: - Sauvegarde

@MainActor
final class DeckStore: ObservableObject {
    @Published var decks: [Deck] { didSet { save(); version += 1 } }
    /// Change à chaque modification : le téléphone recharge ses boutons.
    private(set) var version = 1
    let url: URL

    init(url: URL? = nil) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AikoDeck", isDirectory: true)
        self.url = url ?? dir.appendingPathComponent("boutons.json")
        if let data = try? Data(contentsOf: self.url), let saved = try? JSONDecoder().decode([Deck].self, from: data),
           !saved.isEmpty {
            decks = saved
        } else {
            decks = Defaults.decks
        }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(decks).write(to: url, options: .atomic)
    }

    func button(deck: UUID, button: UUID) -> DeckButton? {
        decks.first { $0.id == deck }?.buttons.first { $0.id == button }
    }

    func resetToDefaults() { decks = Defaults.decks }
}
