import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

@main
@MainActor
struct AikoDeckMain {
    static func main() {
        let app = NSApplication.shared
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--selftest") {
            let test = SelfTest(outDir: URL(fileURLWithPath: i + 1 < args.count ? args[i + 1] : "screenshots"))
            app.setActivationPolicy(.regular)
            DispatchQueue.main.async { test.run() }
            app.run()
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var url = ""
    @Published var devices = 0
    @Published var lastPress = ""
    @Published var error: String?
    @Published var trusted = AXIsProcessTrusted()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = DeckStore()
    private var server: DeckServer!
    private let model = AppModel()
    private var statusItem: NSStatusItem!
    private var mainWindow: NSWindow?
    private var editorWindow: NSWindow?

    static var token: String {
        if let t = UserDefaults.standard.string(forKey: "token"), t.count >= 16 { return t }
        let t = newToken()
        UserDefaults.standard.set(t, forKey: "token")
        return t
    }

    static func newToken() -> String {
        let chars = Array("abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<22).map { _ in chars.randomElement()! })
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let img = NSImage(systemSymbolName: "square.grid.3x3.square", accessibilityDescription: "AikoDeck")?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        img?.isTemplate = true
        statusItem.button?.image = img
        statusItem.button?.target = self
        statusItem.button?.action = #selector(showMain)
        startServer(token: Self.token)
        if !AXIsProcessTrusted() {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.model.trusted = AXIsProcessTrusted()
                self.model.devices = self.server?.connectedDevices ?? 0
                self.model.url = self.server?.url ?? ""
            }
        }
        showMain()
    }

    private func startServer(token: String) {
        server?.stop()
        let s = DeckServer(store: store, token: token)
        s.onPress = { [weak self] b, err in
            self?.model.lastPress = "\(b.icon) \(b.label)"
            self?.model.error = err
        }
        s.onDevicesChanged = { [weak self] in self?.model.devices = self?.server.connectedDevices ?? 0 }
        server = s
        Task {
            do {
                try await s.start()
                model.url = s.url
            } catch {
                model.error = "Impossible d'ouvrir le serveur : \(error.localizedDescription)"
            }
        }
    }

    @objc func showMain() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = mainWindow { w.makeKeyAndOrderFront(nil); return }
        let view = MainView(model: model,
                            onEdit: { [weak self] in self?.showEditor() },
                            onNewCode: { [weak self] in
                                let t = Self.newToken()
                                UserDefaults.standard.set(t, forKey: "token")
                                self?.startServer(token: t)
                            },
                            onAccessibility: {
                                if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                    NSWorkspace.shared.open(u)
                                }
                            },
                            onQuit: { NSApp.terminate(nil) })
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.title = "AikoDeck"
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.isReleasedWhenClosed = false
        w.center()
        mainWindow = w
        w.makeKeyAndOrderFront(nil)
    }

    func showEditor() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = editorWindow { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentViewController: NSHostingController(rootView: EditorView(store: store)))
        w.title = "Boutons AikoDeck"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.setContentSize(NSSize(width: 980, height: 620))
        w.isReleasedWhenClosed = false
        w.center()
        editorWindow = w
        w.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Fenêtre principale : le QR code

enum QR {
    static func image(_ text: String, size: CGFloat = 220) -> NSImage {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage else { return NSImage() }
        let scale = size / out.extent.width
        let scaled = out.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}

struct MainView: View {
    @ObservedObject var model: AppModel
    var onEdit: () -> Void
    var onNewCode: () -> Void
    var onAccessibility: () -> Void
    var onQuit: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.3x3.square.fill").font(.system(size: 26)).foregroundStyle(Theme.accentText(scheme))
                VStack(alignment: .leading, spacing: 2) {
                    Text("AikoDeck").font(.system(size: 20, weight: .semibold))
                    Text("Ton téléphone devient une télécommande").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top, spacing: 18) {
                if !model.url.isEmpty {
                    Image(nsImage: QR.image(model.url))
                        .interpolation(.none).resizable().frame(width: 190, height: 190)
                        .padding(10).background(RoundedRectangle(cornerRadius: 12).fill(.white))
                } else {
                    ProgressView().frame(width: 210, height: 210)
                }
                VStack(alignment: .leading, spacing: 10) {
                    step(1, "Ton téléphone sur le même Wi-Fi que le Mac.")
                    step(2, "Scanne le QR code avec l'appareil photo.")
                    step(3, "Dans Safari : Partager → « Sur l'écran d'accueil » pour l'avoir comme une appli.")
                    HStack(spacing: 6) {
                        Circle().fill(model.devices > 0 ? Theme.accentUI : Color.gray).frame(width: 8, height: 8)
                        Text(model.devices > 0 ? "\(model.devices) appareil\(model.devices > 1 ? "s" : "") connecté\(model.devices > 1 ? "s" : "")"
                                               : "Aucun appareil connecté")
                            .font(.system(size: 12))
                    }
                    if !model.lastPress.isEmpty {
                        Text("Dernier bouton : \(model.lastPress)").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    if let e = model.error {
                        Text(e).font(.system(size: 12)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !model.trusted {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("Pour envoyer des raccourcis, autorise AikoDeck dans Accessibilité.").font(.system(size: 12))
                    Spacer()
                    Button("Ouvrir les réglages") { onAccessibility() }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
            }
            HStack {
                Button("Modifier les boutons…") { onEdit() }.keyboardShortcut(.defaultAction).tint(Theme.accentUI)
                Button("Nouveau QR code") { onNewCode() }
                    .help("Les téléphones déjà connectés devront scanner le nouveau code")
                Spacer()
                Button("Quitter") { onQuit() }
            }
            Text("Seuls les appareils qui ont scanné ce code peuvent piloter ton Mac.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(width: 560)
        .background(Theme.background(scheme))
    }

    private func step(_ n: Int, _ s: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.onAccent)
                .frame(width: 20, height: 20).background(Circle().fill(Theme.accentUI))
            Text(s).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
