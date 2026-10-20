import AppKit
import Carbon.HIToolbox

/// Trouve la touche physique qui tape un caractère sur le clavier actuel (AZERTY, QWERTY…).
enum KeyboardLayout {
    private static let named: [String: Int] = [
        "space": kVK_Space, "return": kVK_Return, "delete": kVK_Delete, "escape": kVK_Escape, "tab": kVK_Tab,
        "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
        "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6, "f7": kVK_F7,
        "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
    ]
    /// Les chiffres : on vise la rangée du haut (sur AZERTY, ⇧ + cette touche donne le chiffre).
    private static let digits: [String: Int] = [
        "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4, "5": kVK_ANSI_5,
        "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9, "0": kVK_ANSI_0,
    ]

    static func keyCode(for key: String) -> CGKeyCode? {
        let k = key.lowercased()
        if let n = named[k] { return CGKeyCode(n) }
        if let d = digits[k] { return CGKeyCode(d) }
        if k.hasPrefix("#"), let n = Int(k.dropFirst()), (0..<128).contains(n) { return CGKeyCode(n) }   // code brut enregistré
        return reverseMap()[k].map(CGKeyCode.init)
    }

    /// Table « caractère → touche » du clavier en cours.
    static func reverseMap() -> [String: Int] {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return fallback }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var out: [String: Int] = [:]
        data.withUnsafeBytes { raw in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            for code in 0..<128 {
                var dead: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var len = 0
                let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                                            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                            &dead, 4, &len, &chars)
                guard status == noErr, len > 0 else { continue }
                let s = String(utf16CodeUnits: chars, count: len).lowercased()
                if out[s] == nil { out[s] = code }
            }
        }
        return out.isEmpty ? fallback : out
    }

    private static let fallback: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
        "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
        "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
    ]
}

/// Exécute l'action d'un bouton sur le Mac.
@MainActor
enum Actions {
    static var canSendKeys: Bool { AXIsProcessTrusted() }

    /// Renvoie un message d'erreur lisible, ou nil si tout s'est bien passé.
    @discardableResult
    static func perform(_ a: DeckAction) async -> String? {
        switch a.kind {
        case .none:
            return nil
        case .shortcut:
            guard let combo = a.combo else { return "Raccourci vide" }
            guard canSendKeys else { return "Autorise AikoDeck dans Accessibilité" }
            if let target = a.targetApp {
                guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: target).first else {
                    return "L'appli n'est pas ouverte"
                }
                if !app.isActive {
                    app.activate(options: [])
                    try? await Task.sleep(nanoseconds: 150_000_000)
                }
            }
            return sendKey(combo) ? nil : "Touche inconnue : \(combo.key)"
        case .app:
            guard let v = a.value, !v.isEmpty else { return "Appli non choisie" }
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: v)
                ?? (FileManager.default.fileExists(atPath: v) ? URL(fileURLWithPath: v) : nil)
            guard let url else { return "Appli introuvable" }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
            return nil
        case .url:
            guard let s = a.value, let url = URL(string: s.contains("://") ? s : "https://" + s) else { return "Lien invalide" }
            NSWorkspace.shared.open(url)
            return nil
        case .text:
            guard canSendKeys else { return "Autorise AikoDeck dans Accessibilité" }
            typeText(a.value ?? "")
            return nil
        case .appleShortcut:
            guard let name = a.value, !name.isEmpty else { return "Nom du Raccourci vide" }
            return run("/usr/bin/shortcuts", ["run", name])
        case .command:
            guard let cmd = a.value, !cmd.isEmpty else { return "Commande vide" }
            return run("/bin/zsh", ["-lc", cmd])
        case .media:
            guard let m = a.media else { return nil }
            sendMedia(m)
            return nil
        }
    }

    @discardableResult
    static func sendKey(_ c: KeyCombo) -> Bool {
        guard let code = KeyboardLayout.keyCode(for: c.key) else { return false }
        var flags: CGEventFlags = []
        if c.command { flags.insert(.maskCommand) }
        if c.shift { flags.insert(.maskShift) }
        if c.option { flags.insert(.maskAlternate) }
        if c.control { flags.insert(.maskControl) }
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        return true
    }

    static func typeText(_ s: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        for ch in s {
            var units = Array(String(ch).utf16)
            let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
            let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            down?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            up?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    /// Touches multimédia (comme celles du clavier Apple).
    static func sendMedia(_ m: MediaKey) {
        let key: Int32
        switch m {
        case .playPause: key = 16   // NX_KEYTYPE_PLAY
        case .next: key = 17        // NX_KEYTYPE_NEXT
        case .previous: key = 18    // NX_KEYTYPE_PREVIOUS
        case .volumeUp: key = 0     // NX_KEYTYPE_SOUND_UP
        case .volumeDown: key = 1   // NX_KEYTYPE_SOUND_DOWN
        case .mute: key = 7         // NX_KEYTYPE_MUTE
        }
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
            let e = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                                       windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)
            e?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    private static func run(_ exe: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        do { try p.run() } catch { return "Impossible de lancer : \(error.localizedDescription)" }
        return nil
    }
}
