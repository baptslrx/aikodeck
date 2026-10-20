import Foundation
import Network

/// Petit serveur web local : sert la télécommande au téléphone et reçoit les appuis sur les boutons.
@MainActor
final class DeckServer {
    let store: DeckStore
    let token: String
    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private var seen: [String: Date] = [:]
    var onPress: ((DeckButton, String?) -> Void)?
    var onDevicesChanged: (() -> Void)?

    init(store: DeckStore, token: String) {
        self.store = store
        self.token = token
    }

    /// Appareils qui ont parlé au serveur dans les 30 dernières secondes.
    var connectedDevices: Int { seen.values.filter { Date().timeIntervalSince($0) < 30 }.count }

    func start(preferredPort: UInt16 = 8765) async throws {
        for p in [preferredPort, preferredPort + 1, preferredPort + 2, 0] {
            guard let l = try? NWListener(using: .tcp, on: p == 0 ? .any : NWEndpoint.Port(rawValue: p)!) else { continue }
            l.newConnectionHandler = { [weak self] c in
                MainActor.assumeIsolated { self?.accept(c) }
            }
            let ok: Bool = await withCheckedContinuation { cont in
                let once = Once()
                l.stateUpdateHandler = { state in
                    switch state {
                    case .ready: if once.fire() { cont.resume(returning: true) }
                    case .failed, .cancelled: if once.fire() { cont.resume(returning: false) }
                    default: break
                    }
                }
                l.start(queue: .main)
            }
            if ok, let port = l.port {
                l.stateUpdateHandler = nil
                listener = l
                self.port = port.rawValue
                return
            }
            l.cancel()
        }
        throw NSError(domain: "AikoDeck", code: 1, userInfo: [NSLocalizedDescriptionKey: "Aucun port libre"])
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - HTTP minimal

    private func accept(_ c: NWConnection) {
        c.start(queue: .main)
        receive(c, buffer: Data())
    }

    private func receive(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                var buf = buffer
                if let data { buf.append(data) }
                if let req = Request(buf) {
                    self.respond(c, req)
                } else if done || error != nil || buf.count > 1_000_000 {
                    c.cancel()
                } else {
                    self.receive(c, buffer: buf)
                }
            }
        }
    }

    struct Request {
        let method: String
        let path: String
        let query: [String: String]
        let headers: [String: String]
        let body: Data

        init?(_ data: Data) {
            guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
            guard let head = String(data: data[..<end.lowerBound], encoding: .utf8) else { return nil }
            var lines = head.components(separatedBy: "\r\n")
            let first = lines.removeFirst().split(separator: " ")
            guard first.count >= 2 else { return nil }
            method = String(first[0])
            let target = String(first[1])
            var h: [String: String] = [:]
            for l in lines {
                guard let i = l.firstIndex(of: ":") else { continue }
                h[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)
            }
            headers = h
            let length = Int(h["content-length"] ?? "0") ?? 0
            let bodyStart = end.upperBound
            guard data.count - bodyStart >= length else { return nil }
            body = data[bodyStart..<(bodyStart + length)]
            let comps = URLComponents(string: target)
            path = comps?.path ?? target
            var q: [String: String] = [:]
            for item in comps?.queryItems ?? [] { q[item.name] = item.value ?? "" }
            query = q
        }
    }

    private func send(_ c: NWConnection, _ status: String, _ type: String, _ body: Data, cache: Bool = false) {
        var head = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\n"
        head += cache ? "Cache-Control: max-age=86400\r\n" : "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n\r\n"
        c.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in c.cancel() })
    }

    private func json(_ c: NWConnection, _ obj: Any, status: String = "200 OK") {
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
        send(c, status, "application/json; charset=utf-8", data)
    }

    private func authorized(_ r: Request) -> Bool {
        (r.headers["x-aiko-key"] ?? r.query["k"]) == token
    }

    private func respond(_ c: NWConnection, _ r: Request) {
        let who: String = {
            if case .hostPort(let host, _) = c.endpoint { return "\(host)" }
            return "?"
        }()
        switch (r.method, r.path) {
        case ("GET", "/"), ("GET", "/index.html"):
            send(c, "200 OK", "text/html; charset=utf-8", Data(WebPage.html.utf8))
        case ("GET", "/manifest.webmanifest"):
            let k = (r.query["k"] ?? "").filter { $0.isLetter || $0.isNumber }
            send(c, "200 OK", "application/manifest+json", Data(WebPage.manifest(token: k).utf8))
        case ("GET", "/icon.png"):
            send(c, "200 OK", "image/png", WebPage.iconPNG, cache: true)
        case (_, let p) where p.hasPrefix("/api/"):
            guard authorized(r) else {
                json(c, ["error": "Scanne à nouveau le QR code affiché sur le Mac."], status: "401 Unauthorized")
                return
            }
            let before = connectedDevices
            seen[who] = Date()
            if connectedDevices != before { onDevicesChanged?() }
            api(c, r)
        default:
            send(c, "404 Not Found", "text/plain", Data("introuvable".utf8))
        }
    }

    private func api(_ c: NWConnection, _ r: Request) {
        switch (r.method, r.path) {
        case ("GET", "/api/version"):
            json(c, ["version": store.version])
        case ("GET", "/api/decks"):
            let decks: [[String: Any]] = store.decks.map { d in
                ["id": d.id.uuidString, "name": d.name, "buttons": d.buttons.map { b in
                    ["id": b.id.uuidString, "label": b.label, "icon": b.icon, "color": b.color] as [String: Any]
                }]
            }
            json(c, ["version": store.version, "mac": Host.current().localizedName ?? "Mac", "decks": decks])
        case ("POST", "/api/press"):
            guard let obj = try? JSONSerialization.jsonObject(with: r.body) as? [String: String],
                  let d = obj["deck"].flatMap(UUID.init(uuidString:)), let b = obj["button"].flatMap(UUID.init(uuidString:)),
                  let button = store.button(deck: d, button: b) else {
                json(c, ["ok": false, "error": "Bouton introuvable"], status: "404 Not Found")
                return
            }
            Task { @MainActor in
                let err = await Actions.perform(button.action)
                self.onPress?(button, err)
                if let err { self.json(c, ["ok": false, "error": err]) } else { self.json(c, ["ok": true]) }
            }
        default:
            json(c, ["error": "inconnu"], status: "404 Not Found")
        }
    }

    // MARK: - Adresse à afficher

    /// Adresses du Mac sur le Wi-Fi / réseau local.
    static func localAddresses() -> [String] {
        var out: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return out }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let i = ptr.pointee
            guard let addr = i.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(i.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: i.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: host)
            if !ip.hasPrefix("169.254") { out.append(ip) }
        }
        return out
    }

    var url: String {
        let ip = Self.localAddresses().first ?? "127.0.0.1"
        return "http://\(ip):\(port)/?k=\(token)"
    }
}

/// Ne laisse passer qu'une seule fois (pour ne reprendre une attente qu'une fois).
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func fire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
