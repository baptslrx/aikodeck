import AppKit
import WebKit

/// `AikoDeck --selftest <dossier>` : serveur, sécurité, vraies frappes au clavier, captures de la télécommande.
@MainActor
final class SelfTest: NSObject {
    let outDir: URL
    private var failures: [String] = []
    private var report: [String] = []
    private let ci = ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != nil
    private var keep: [AnyObject] = []

    init(outDir: URL) { self.outDir = outDir }

    func run() {
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        Task { @MainActor in
            await steps()
            finish()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in
            MainActor.assumeIsolated { self?.check(false, "le test a dépassé 2 minutes"); self?.finish() }
        }
    }

    private func log(_ s: String) { print(s); fflush(stdout); report.append(s) }

    private func check(_ ok: Bool, _ what: String) {
        log((ok ? "  ok   " : "  FAIL ") + what)
        if !ok {
            failures.append(what)
            if ci { print("::error title=Test::\(what)") }
        }
    }

    private func sleep(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }

    private func get(_ url: String, key: String? = nil) async -> (Int, Data) {
        var r = URLRequest(url: URL(string: url)!)
        if let key { r.setValue(key, forHTTPHeaderField: "X-Aiko-Key") }
        guard let (d, resp) = try? await URLSession.shared.data(for: r) else { return (0, Data()) }
        return ((resp as? HTTPURLResponse)?.statusCode ?? 0, d)
    }

    private func press(_ base: String, key: String, deck: UUID, button: UUID) async -> [String: Any] {
        var r = URLRequest(url: URL(string: base + "/api/press")!)
        r.httpMethod = "POST"
        r.setValue(key, forHTTPHeaderField: "X-Aiko-Key")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["deck": deck.uuidString, "button": button.uuidString])
        guard let (d, _) = try? await URLSession.shared.data(for: r) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
    }

    private func steps() async {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("aikodeck-\(UUID().uuidString).json")
        let store = DeckStore(url: tmp)
        check(store.decks.count == 4 && store.decks[0].name == "DaVinci", "boutons de départ : \(store.decks.map(\.name))")

        let token = "testtoken1234567890abcd"
        let server = DeckServer(store: store, token: token)
        do { try await server.start(preferredPort: 18765) } catch { check(false, "serveur : \(error)"); return }
        let base = "http://127.0.0.1:\(server.port)"
        log("== Serveur sur le port \(server.port) — adresse affichée : \(server.url.replacingOccurrences(of: token, with: "…"))")

        var (st, data) = await get(base + "/")
        check(st == 200 && String(decoding: data, as: UTF8.self).contains("AikoDeck"), "la page de la télécommande s'ouvre")
        (st, _) = await get(base + "/api/decks")
        check(st == 401, "sans le code du QR : accès refusé (\(st))")
        (st, _) = await get(base + "/api/decks", key: "mauvais")
        check(st == 401, "avec un faux code : accès refusé")
        (st, data) = await get(base + "/api/decks", key: token)
        let decks = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["decks"] as? [[String: Any]] ?? []
        check(st == 200 && decks.count == 4, "avec le bon code : 4 pages de boutons")
        (st, data) = await get(base + "/icon.png")
        check(st == 200 && data.count > 500, "icône pour l'écran d'accueil")
        check(KeyboardLayout.keyCode(for: "b") != nil && KeyboardLayout.keyCode(for: "space") == 49, "touches du clavier trouvées")

        log("== Vraies frappes (Accessibilité : \(AXIsProcessTrusted() ? "oui" : "non"))")
        let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 500, height: 200), styleMask: [.titled], backing: .buffered,
                         defer: false)
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        w.contentView = scroll
        keep.append(w)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(tv)
        await sleep(0.8)
        let test = Deck(name: "Test", buttons: [
            DeckButton(label: "Texte", icon: "✍️", color: "#7DC8FF",
                       action: DeckAction(kind: .text, value: "Bonjour AikoDeck é")),
            DeckButton(label: "Touche B", icon: "🅱️", color: "#7DC8FF",
                       action: DeckAction(kind: .shortcut, combo: KeyCombo(key: "b"))),
            DeckButton(label: "Tout sélectionner", icon: "🔲", color: "#7DC8FF",
                       action: DeckAction(kind: .shortcut, combo: KeyCombo(key: "a", command: true))),
            DeckButton(label: "Vide", icon: "∅", color: "#7DC8FF",
                       action: DeckAction(kind: .shortcut, combo: KeyCombo(key: "#999"))),
        ])
        store.decks.append(test)
        if AXIsProcessTrusted() {
            var r = await press(base, key: token, deck: test.id, button: test.buttons[0].id)
            await sleep(0.6)
            check(r["ok"] as? Bool == true && tv.string == "Bonjour AikoDeck é", "bouton « taper un texte » → « \(tv.string) »")
            r = await press(base, key: token, deck: test.id, button: test.buttons[1].id)
            await sleep(0.4)
            check(tv.string.hasSuffix("b"), "bouton raccourci (touche B) → « \(tv.string) »")
            _ = await press(base, key: token, deck: test.id, button: test.buttons[2].id)
            await sleep(0.4)
            check(tv.selectedRange().length == tv.string.utf16.count && !tv.string.isEmpty, "⌘A envoyé : tout le texte est sélectionné")
            r = await press(base, key: token, deck: test.id, button: test.buttons[3].id)
            check(r["ok"] as? Bool == false, "touche impossible : erreur claire (« \(r["error"] as? String ?? "") »)")
        } else if ci {
            print("::warning title=Frappes::accessibilité non accordée sur la machine de test")
        }
        let v1 = store.version
        store.decks[0].name = "DaVinci Resolve"
        (st, data) = await get(base + "/api/version", key: token)
        let v2 = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["version"] as? Int ?? 0
        check(v2 > v1, "une modification sur le Mac est signalée au téléphone")
        store.decks.removeLast()
        store.decks[0].name = "DaVinci"
        w.orderOut(nil)

        log("== Captures de la télécommande (taille iPhone)")
        for dark in [true, false] {
            await snapshot(url: "\(base)/?k=\(token)", dark: dark, name: "telephone-\(dark ? "sombre" : "clair").png")
        }
        server.stop()
        try? FileManager.default.removeItem(at: tmp)
    }

    private func snapshot(url: String, dark: Bool, name: String) async {
        let size = NSSize(width: 390, height: 844)
        let web = WKWebView(frame: NSRect(origin: .zero, size: size))
        web.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let w = NSWindow(contentRect: NSRect(x: 60, y: 60, width: size.width, height: size.height), styleMask: [.borderless],
                         backing: .buffered, defer: false)
        w.appearance = web.appearance
        w.contentView = web
        w.orderFrontRegardless()
        keep.append(w)
        web.load(URLRequest(url: URL(string: url)!))
        await sleep(2.5)
        let img: NSImage? = await withCheckedContinuation { cont in
            web.takeSnapshot(with: nil) { image, _ in cont.resume(returning: image) }
        }
        if let img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: outDir.appendingPathComponent(name))
            log("   \(name)")
        } else {
            check(false, "capture \(name)")
        }
        w.orderOut(nil)
    }

    private var finished = false
    private func finish() {
        guard !finished else { return }
        finished = true
        log(failures.isEmpty ? "\nTout est OK" : "\nÉCHECS :\n" + failures.joined(separator: "\n"))
        try? report.joined(separator: "\n").write(to: outDir.appendingPathComponent("rapport.txt"), atomically: true, encoding: .utf8)
        exit(failures.isEmpty ? 0 : 1)
    }
}
