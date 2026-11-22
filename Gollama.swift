// GollamaApp.swift
// Native SwiftUI client for Gollama Search, with Liquid Glass (iOS 26 / macOS 26, Xcode 26).
//
// SETUP
//  1. New Xcode project -> App (SwiftUI), deployment target iOS 26. Replace the generated App/ContentView with this file.
//  2. Info.plist keys (Target -> Info):
//       NSLocalNetworkUsageDescription = "Gollama needs the local network to find your Gollama server."
//       App Transport Security Settings -> Allows Local Networking = YES
//     (the server speaks plain http on your LAN, so ATS must allow local networking)
//  3. On the computer running app.py: Settings -> turn on the network server (default port 8765, optional access code).
//
// HOW IT TALKS TO THE SERVER (same protocol the web page uses when opened from another device)
//   GET  /                  -> login page or main page (used to detect Gollama and whether a code is needed)
//   POST /login             -> code=<access code>, sets a cookie
//   POST /api/<method>      -> {"args":[...]} -> {"result":...}
//   POST /api/poll          -> streamed events (onOverviewChunk, onModeChunk, ...)

import SwiftUI
import Foundation

// MARK: - App

@main
struct GollamaApp: App {
    @State private var app = AppModel()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .task { await app.tryAutoReconnect() }
        }
    }
}

// MARK: - Palette (from the web UI)

enum Pal {
    static let blue = Color(red: 0.26, green: 0.52, blue: 0.96)
    static let red = Color(red: 0.92, green: 0.26, blue: 0.21)
    static let yellow = Color(red: 0.98, green: 0.74, blue: 0.02)
    static let green = Color(red: 0.20, green: 0.66, blue: 0.33)
    static let purple = Color(red: 0.61, green: 0.45, blue: 0.80)
    static let pink = Color(red: 0.85, green: 0.40, blue: 0.44)
    static let logo: [Color] = [blue, red, yellow, blue, green, red, blue]
}

struct GollamaLogo: View {
    var size: CGFloat
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array("Gollama".enumerated()), id: \.offset) { i, ch in
                Text(String(ch)).tracking(-size * 0.045).foregroundStyle(Pal.logo[i])
            }
        }
        .font(.system(size: size, weight: .medium, design: .rounded))
    }
}

struct Spark: View {
    var size: CGFloat = 20
    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(LinearGradient(colors: [Pal.blue, Pal.purple, Pal.pink], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

struct ThinkingDots: View {
    @State private var on = false
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle().fill([Pal.blue, Pal.purple, Pal.pink][i]).frame(width: 6, height: 6)
                    .scaleEffect(on ? 1 : 0.55).opacity(on ? 1 : 0.5)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.15), value: on)
            }
        }
        .onAppear { on = true }
    }
}

// MARK: - Networking

struct ServerAddress: Codable, Hashable {
    var host: String
    var port: Int
    var base: URL { URL(string: "http://\(host):\(port)")! }
}

enum GollamaError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
}

enum ProbeResult { case gollama(needsCode: Bool), other, unreachable }

final class GollamaClient: @unchecked Sendable {
    let base: URL
    private let session: URLSession

    init(base: URL) {
        self.base = base
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = .shared          // keeps the login cookie between launches
        cfg.httpShouldSetCookies = true
        cfg.timeoutIntervalForRequest = 120
        session = URLSession(configuration: cfg)
    }

    /// Looks at `/` to see whether a Gollama server (main page, not the ChatGPT-style one) is listening.
    static func probe(host: String, port: Int, timeout: TimeInterval = 0.7) async -> ProbeResult {
        guard let url = URL(string: "http://\(host):\(port)/") else { return .unreachable }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout * 2
        cfg.waitsForConnectivity = false
        do {
            let (data, resp) = try await URLSession(configuration: cfg).data(from: url)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else { return .other }
            guard html.contains("<title>Gollama Search</title>") else { return .other }
            return .gollama(needsCode: html.contains("name=\"code\""))
        } catch { return .unreachable }
    }

    func login(code: String) async throws {
        var req = URLRequest(url: base.appendingPathComponent("login"))
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        req.httpBody = "code=\(code.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")".data(using: .utf8)
        _ = try await session.data(for: req)     // 303 -> "/" is followed automatically; cookie is stored
    }

    @discardableResult
    func call(_ name: String, _ args: [Any] = []) async throws -> Any? {
        var req = URLRequest(url: base.appendingPathComponent("api/\(name)"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["args": args])
        let (data, resp) = try await session.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let e = json?["error"] as? String { throw GollamaError.message(e) }
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw GollamaError.message("Server answered HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        let r = json?["result"]
        return r is NSNull ? nil : r
    }
}

/// Finds the Wi-Fi IPv4 address of this device.
func localIPv4() -> String? {
    var addrs: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&addrs) == 0, let first = addrs else { return nil }
    defer { freeifaddrs(addrs) }
    var best: String?
    for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
        let i = p.pointee
        guard let sa = i.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
        let name = String(cString: i.ifa_name)
        guard name.hasPrefix("en") else { continue }
        var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        getnameinfo(sa, socklen_t(sa.pointee.sa_len), &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST)
        best = String(cString: buf)
        if name == "en0" { break }
    }
    return best
}

// MARK: - Data

struct Hit: Identifiable, Hashable {
    var id: String { url }
    let title: String, url: String, snippet: String, site: String
    init?(_ d: [String: Any]) {
        guard let u = d["url"] as? String, !u.isEmpty else { return nil }
        url = u
        title = (d["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? u
        snippet = d["snippet"] as? String ?? ""
        site = (d["site"] as? String) ?? (d["source"] as? String) ?? URL(string: u)?.host?.replacingOccurrences(of: "www.", with: "") ?? ""
    }
    static func list(_ any: Any?) -> [Hit] { (any as? [[String: Any]])?.compactMap(Hit.init) ?? [] }
}

struct ImageItem: Identifiable, Hashable {
    let id = UUID()
    let thumb: URL?, full: URL?, page: String, title: String, source: String
}

struct NewsItem: Identifiable, Hashable {
    let id = UUID()
    let title: String, url: String, snippet: String, source: String, date: String, image: URL?
}

@Observable final class Overview {
    var status = ""
    var text = ""
    var think = ""
    var error: String?
    var steps: [String] = []
    var sources: [Hit] = []
    var done = false
    var expanded = false
}

@Observable final class ModeTurn: Identifiable {
    let id: Int
    let text: String
    var answer = ""
    var status = ""
    var think = ""
    var steps: [String] = []
    var sources: [Hit] = []
    var done = false
    var error: String?
    var noResultsFor: String?
    init(id: Int, text: String) { self.id = id; self.text = text }
}

enum SearchTab: String, CaseIterable, Identifiable {
    case all = "All", mode = "AI Mode", images = "Images", news = "News"
    var id: String { rawValue }
}

// MARK: - App model

@Observable @MainActor final class AppModel {
    // connection
    var client: GollamaClient?
    var address: ServerAddress?
    var connected = false
    var modelName = ""
    var tier = "fast"
    var thinkMode: String?

    // search
    var query = ""
    var tab: SearchTab = .all
    var started = false          // false = home screen
    var searching = false
    var results: [Hit] = []
    var corrected: String?
    var original = ""
    var searchError: String?
    var overview = Overview()
    var images: [ImageItem] = []
    var news: [NewsItem] = []
    var loadingImages = false
    var loadingNews = false
    var imagesError: String?
    var newsError: String?
    var turns: [ModeTurn] = []
    var seedHistory: [[String: String]] = []

    private var nextTurn = 1
    private var pollTask: Task<Void, Never>?
    private var overviewActive = false
    private var activeTurns = Set<Int>()

    // MARK: connect
    func connect(host: String, port: Int, code: String) async throws {
        let host = host.trimmingCharacters(in: .whitespaces)
        switch await GollamaClient.probe(host: host, port: port, timeout: 3) {
        case .unreachable: throw GollamaError.message("Couldn't reach \(host):\(port). Is the Gollama network server turned on?")
        case .other: throw GollamaError.message("Something is listening on \(host):\(port), but it isn't Gollama's main page.")
        case .gollama(let needsCode):
            let c = GollamaClient(base: ServerAddress(host: host, port: port).base)
            if needsCode && !code.isEmpty { try await c.login(code: code) }   // with no code we try the saved login cookie
            do { try await finishConnect(c, host, port) }
            catch {
                guard needsCode else { throw error }
                throw GollamaError.message(code.isEmpty ? "This server needs an access code." : "That access code isn't right.")
            }
        }
    }

    private func finishConnect(_ c: GollamaClient, _ host: String, _ port: Int) async throws {
        let cfg = try await c.call("get_config") as? [String: Any] ?? [:]
        client = c
        address = ServerAddress(host: host, port: port)
        modelName = cfg["model"] as? String ?? ""
        tier = cfg["mode_tier"] as? String ?? "fast"
        let tm = cfg["think_mode"] as? String
        thinkMode = (tm == nil || tm == "auto") ? nil : tm
        connected = true
        UserDefaults.standard.set(try? JSONEncoder().encode(address), forKey: "gollama.address")
    }

    func tryAutoReconnect() async {
        guard !connected, let d = UserDefaults.standard.data(forKey: "gollama.address"),
              let a = try? JSONDecoder().decode(ServerAddress.self, from: d) else { return }
        try? await connect(host: a.host, port: a.port, code: "")
    }

    func disconnect() {
        pollTask?.cancel(); pollTask = nil
        connected = false; client = nil; goHome()
        turns = []
    }

    // MARK: search
    func goHome() {
        Task { await stopAll() }
        started = false; query = ""; results = []; overview = Overview(); images = []; news = []
        tab = .all; searchError = nil; corrected = nil
    }

    func submit(_ text: String, nocorrect: Bool = false) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        query = q; started = true
        images = []; news = []; imagesError = nil; newsError = nil
        switch tab {
        case .mode: Task { await sendMode(q) }
        case .images: Task { await loadImages() }
        case .news: Task { await loadNews() }
        case .all: Task { await runSearch(q, nocorrect: nocorrect) }
        }
    }

    func select(_ t: SearchTab) {
        tab = t
        if t == .all && results.isEmpty && !searching && !query.isEmpty { Task { await runSearch(query, nocorrect: false) } }
        switch t {
        case .images where images.isEmpty && !loadingImages && !query.isEmpty: Task { await loadImages() }
        case .news where news.isEmpty && !loadingNews && !query.isEmpty: Task { await loadNews() }
        default: break
        }
    }

    func runSearch(_ q: String, nocorrect: Bool) async {
        guard let c = client else { return }
        searching = true; searchError = nil; results = []; corrected = nil
        overview = Overview(); overviewActive = false
        defer { searching = false }
        do {
            let r = try await c.call("search_corrected", [q, nocorrect]) as? [String: Any] ?? [:]
            results = Hit.list(r["results"])
            corrected = r["corrected"] as? String
            original = r["original"] as? String ?? q
            if let used = r["query"] as? String { query = used }
            if results.isEmpty { searchError = (r["error"] as? String) ?? "Nothing came back for “\(q)”." }
            overview.status = "Starting…"
            overviewActive = true
            let raw = (r["results"] as? [[String: Any]]) ?? []
            try await c.call("generate", [query, raw])
            startPolling()
        } catch {
            searchError = error.localizedDescription
            overviewActive = false; overview.done = true; overview.status = ""
        }
    }

    func stopOverview() { overviewActive = false; overview.status = ""; overview.done = true; Task { try? await client?.call("stop") } }

    func loadImages() async {
        guard let c = client else { return }
        loadingImages = true; defer { loadingImages = false }
        do {
            let r = try await c.call("search_images", [query]) as? [String: Any] ?? [:]
            imagesError = r["error"] as? String
            images = (r["items"] as? [[String: Any]] ?? []).map {
                ImageItem(thumb: ($0["thumb"] as? String).flatMap(URL.init), full: ($0["image"] as? String).flatMap(URL.init),
                          page: $0["url"] as? String ?? "", title: $0["title"] as? String ?? "", source: $0["source"] as? String ?? "")
            }
        } catch { imagesError = error.localizedDescription }
    }

    func loadNews() async {
        guard let c = client else { return }
        loadingNews = true; defer { loadingNews = false }
        do {
            let r = try await c.call("search_news", [query]) as? [String: Any] ?? [:]
            newsError = r["error"] as? String
            news = (r["items"] as? [[String: Any]] ?? []).map {
                NewsItem(title: $0["title"] as? String ?? "", url: $0["url"] as? String ?? "", snippet: $0["snippet"] as? String ?? "",
                         source: $0["source"] as? String ?? "", date: $0["date"] as? String ?? "", image: ($0["image"] as? String).flatMap(URL.init))
            }
        } catch { newsError = error.localizedDescription }
    }

    // MARK: AI Mode
    func continueInMode(_ followUp: String) {
        seedHistory = [["role": "user", "content": query], ["role": "assistant", "content": overview.text]]
        turns = []
        tab = .mode
        Task { await sendMode(followUp) }
    }

    func sendMode(_ text: String, force: Bool = false, reuse: ModeTurn? = nil) async {
        guard let c = client else { return }
        let turn = reuse ?? ModeTurn(id: nextTurn, text: text)
        if reuse == nil { nextTurn += 1; turns.append(turn) } else { turn.noResultsFor = nil; turn.answer = ""; turn.done = false }
        query = text; started = true
        var history = seedHistory
        for t in turns where t.id != turn.id && t.done && t.error == nil {
            history.append(["role": "user", "content": t.text]); history.append(["role": "assistant", "content": t.answer])
        }
        activeTurns.insert(turn.id)
        do {
            try await c.call("mode_send", [turn.id, text, history, force, tier, [String: Any](), thinkMode.map { $0 as Any } ?? NSNull()])
            startPolling()
        } catch { turn.error = error.localizedDescription; turn.done = true; activeTurns.remove(turn.id) }
    }

    func stopMode() {
        for t in turns where !t.done { t.done = true; t.status = "" }
        activeTurns.removeAll()
        Task { try? await client?.call("mode_stop") }
    }

    func stopAll() async { _ = try? await client?.call("stop"); _ = try? await client?.call("mode_stop") }

    var modeBusy: Bool { !activeTurns.isEmpty }

    // MARK: event polling
    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            var idle = 0
            while !Task.isCancelled {
                guard let self, let c = self.client else { break }
                if !self.overviewActive && self.activeTurns.isEmpty { idle += 1; if idle > 3 { break } } else { idle = 0 }
                do {
                    let events = try await c.call("poll") as? [[Any]] ?? []
                    for e in events {
                        if let fn = e.first as? String, e.count > 1, let args = e[1] as? [Any] { self.handle(fn, args) }
                    }
                } catch { /* transient; try again */ }
                try? await Task.sleep(for: .milliseconds(180))
            }
            await MainActor.run { [weak self] in self?.pollTask = nil }
        }
    }

    private func handle(_ fn: String, _ a: [Any]) {
        let s = a.last as? String ?? ""
        let ov = overview
        switch fn {
        case "onOverviewStatus": ov.status = s
        case "onOverviewStep": ov.steps.append(s)
        case "onOverviewThink": ov.think += s
        case "onOverviewResults": ov.sources = Hit.list(a.first)
        case "onOverviewChunk": ov.status = ""; ov.text += s
        case "onOverviewPrefix": ov.text = s + "\n\n" + ov.text
        case "onOverviewDone": ov.done = true; ov.status = ""; overviewActive = false
        case "onOverviewError": ov.error = s; ov.done = true; ov.status = ""; overviewActive = false
        default:
            guard fn.hasPrefix("onMode"), let id = a.first as? Int, let t = turns.first(where: { $0.id == id }) else { return }
            switch fn {
            case "onModeStatus": t.status = s
            case "onModeStep": t.steps.append(s)
            case "onModeThink": t.think += s
            case "onModeResults": t.sources = Hit.list(a.count > 1 ? a[1] : nil)
            case "onModeChunk": t.status = ""; t.answer += s
            case "onModeDone": t.done = true; t.status = ""; activeTurns.remove(id)
            case "onModeError": t.error = s; t.done = true; t.status = ""; activeTurns.remove(id)
            case "onModeNoResults": t.noResultsFor = t.text; t.done = true; t.status = ""; activeTurns.remove(id)
            default: break
            }
        }
    }
}

// MARK: - Glass helpers

extension View {
    func glassCard(cornerRadius: CGFloat = 24, tint: Color? = nil) -> some View {
        glassEffect(tint.map { Glass.regular.tint($0.opacity(0.25)) } ?? .regular, in: .rect(cornerRadius: cornerRadius))
    }
    func glassPill(interactive: Bool = false, tint: Color? = nil) -> some View {
        var g = Glass.regular
        if let tint { g = g.tint(tint) }
        if interactive { g = g.interactive() }
        return glassEffect(g, in: .capsule)
    }
}

struct AmbientBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Color(scheme == .dark ? .black : .white)
            Circle().fill(Pal.blue.opacity(scheme == .dark ? 0.35 : 0.22)).frame(width: 360).blur(radius: 90).offset(x: -150, y: -280)
            Circle().fill(Pal.purple.opacity(scheme == .dark ? 0.30 : 0.18)).frame(width: 320).blur(radius: 90).offset(x: 170, y: -80)
            Circle().fill(Pal.pink.opacity(scheme == .dark ? 0.22 : 0.14)).frame(width: 300).blur(radius: 90).offset(x: -90, y: 330)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Root

struct RootView: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        ZStack {
            AmbientBackground()
            if app.connected {
                if app.started { ResultsScreen().transition(.opacity) } else { HomeScreen().transition(.opacity) }
            } else {
                ConnectScreen().transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: app.connected)
        .animation(.smooth(duration: 0.3), value: app.started)
    }
}

// MARK: - Connect screen (find the server on the network)

struct Found: Identifiable, Hashable { let id = UUID(); let host: String; let port: Int; let needsCode: Bool }

struct ConnectScreen: View {
    @Environment(AppModel.self) private var app
    @State private var host = ""
    @State private var port = "8765"
    @State private var portTo = "8765"
    @State private var code = ""
    @State private var found: [Found] = []
    @State private var scanning = false
    @State private var progress = 0.0
    @State private var scanTask: Task<Void, Never>?
    @State private var connecting = false
    @State private var error: String?
    @State private var scannedOnce = false
    @FocusState private var focus: Field?
    enum Field { case host, port, portTo, code }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                GollamaLogo(size: 60).padding(.top, 50)
                Text("Connect to your Gollama server").font(.title3.weight(.medium))
                Text("Turn on the network server in Gollama on your computer, then scan your Wi-Fi or enter the address.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)

                GlassEffectContainer(spacing: 16) {
                    VStack(spacing: 14) {
                        scanCard
                        manualCard
                    }
                }
                .padding(.horizontal, 16)

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.red).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(cornerRadius: 16, tint: .red).padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { if let a = app.address { host = a.host; port = String(a.port); portTo = port } }
    }

    private var scanCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Find on my network", systemImage: "wifi").font(.headline)
            HStack(spacing: 10) {
                field("Port", text: $port, focus: .port).frame(maxWidth: .infinity)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                field("to", text: $portTo, focus: .portTo).frame(maxWidth: .infinity)
            }
            Text("Gollama defaults to port 8765. Widen the range if you changed it (max 200 ports).")
                .font(.caption).foregroundStyle(.secondary)

            Button { scanning ? cancelScan() : startScan() } label: {
                HStack { if scanning { ProgressView().tint(.primary) } ; Text(scanning ? "Stop scanning" : "Scan network") }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent).tint(Pal.blue).controlSize(.large)

            if scanning { ProgressView(value: progress).tint(Pal.blue) }

            ForEach(found) { f in
                Button { host = f.host; port = String(f.port); portTo = port; focus = f.needsCode ? .code : nil; if !f.needsCode { connect() } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "server.rack").foregroundStyle(Pal.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(f.host):\(f.port)").font(.body.weight(.medium))
                            Text(f.needsCode ? "Access code required" : "Open").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: f.needsCode ? "lock.fill" : "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            if scannedOnce && !scanning && found.isEmpty {
                Text("No Gollama server found. Check the server is on and both devices share the same Wi-Fi.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }

    private var manualCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Enter manually", systemImage: "keyboard").font(.headline)
            field("IP address (e.g. 192.168.1.20)", text: $host, focus: .host, keyboard: .numbersAndPunctuation)
            field("Access code (if set)", text: $code, focus: .code, secure: true)
            Button { connect() } label: {
                HStack { if connecting { ProgressView().tint(.white) }; Text("Connect") }.frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent).tint(Pal.green).controlSize(.large)
            .disabled(host.isEmpty || connecting)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }

    @ViewBuilder private func field(_ title: String, text: Binding<String>, focus f: Field, keyboard: UIKeyboardType = .numberPad, secure: Bool = false) -> some View {
        Group {
            if secure { SecureField(title, text: text) } else { TextField(title, text: text).keyboardType(keyboard) }
        }
        .focused($focus, equals: f)
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .padding(.horizontal, 16).frame(height: 44)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func connect() {
        error = nil; connecting = true; focus = nil
        Task {
            defer { connecting = false }
            do { try await app.connect(host: host, port: Int(port) ?? 8765, code: code) }
            catch { self.error = error.localizedDescription }
        }
    }

    private func cancelScan() { scanTask?.cancel(); scanning = false }

    private func startScan() {
        error = nil; found = []; focus = nil
        guard let me = localIPv4() else { error = "Couldn't read this device's Wi-Fi address. Join a Wi-Fi network, or enter the IP manually."; return }
        let lo = max(1, Int(port) ?? 8765), hi = min(65535, max(lo, Int(portTo) ?? lo), lo + 199)
        let prefix = me.split(separator: ".").prefix(3).joined(separator: ".")
        let targets = (1...254).flatMap { h in (lo...hi).map { ("\(prefix).\(h)", $0) } }
        scanning = true; scannedOnce = true; progress = 0
        scanTask = Task {
            var done = 0
            let batch = 120
            for start in stride(from: 0, to: targets.count, by: batch) {
                if Task.isCancelled { break }
                let slice = targets[start..<min(start + batch, targets.count)]
                let hits = await withTaskGroup(of: Found?.self) { group -> [Found] in
                    for (h, p) in slice {
                        group.addTask {
                            if case .gollama(let needs) = await GollamaClient.probe(host: h, port: p) { return Found(host: h, port: p, needsCode: needs) }
                            return nil
                        }
                    }
                    var out: [Found] = []
                    for await r in group { if let r { out.append(r) } }
                    return out
                }
                found += hits
                done += slice.count
                progress = Double(done) / Double(targets.count)
            }
            scanning = false
        }
    }
}

// MARK: - Home

struct HomeScreen: View {
    @Environment(AppModel.self) private var app
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Menu {
                    if let a = app.address { Text("\(a.host):\(a.port)") }
                    Button("Disconnect", systemImage: "wifi.slash", role: .destructive) { app.disconnect() }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                .buttonStyle(.glass).buttonBorderShape(.circle)
            }
            .padding(.horizontal, 16)

            Spacer()
            GollamaLogo(size: 64).padding(.bottom, 26)

            GlassEffectContainer(spacing: 20) {
                VStack(spacing: 22) {
                    SearchField(text: $text, placeholder: "Search or ask anything", focused: $focused) { app.submit(text) }
                    HStack(spacing: 12) {
                        Button("Gollama Search") { app.tab = .all; app.submit(text) }.buttonStyle(.glass)
                        Button { app.tab = .mode; app.started = true } label: { Label("AI Mode", systemImage: "sparkle") }
                            .buttonStyle(.glassProminent).tint(Pal.purple)
                    }
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 20)

            if !app.modelName.isEmpty {
                Text("Model: \(app.modelName)").font(.footnote).foregroundStyle(.secondary).padding(.top, 22)
            }
            Spacer(); Spacer()
        }
    }
}

struct SearchField: View {
    @Binding var text: String
    var placeholder: String
    var focused: FocusState<Bool>.Binding
    var onSubmit: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(placeholder, text: $text).submitLabel(.search).focused(focused).onSubmit(onSubmit)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18).frame(height: 50)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

// MARK: - Results screen

struct ResultsScreen: View {
    @Environment(AppModel.self) private var app
    @State private var text = ""
    @FocusState private var focused: Bool
    @Namespace private var ns

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch app.tab {
                case .all: AllTab()
                case .mode: ModeTab()
                case .images: ImagesTab()
                case .news: NewsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { text = app.query }
        .onChange(of: app.query) { _, q in if !focused { text = q } }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { app.goHome() } label: { GollamaLogo(size: 24) }.buttonStyle(.plain)
                SearchField(text: $text, placeholder: "Search", focused: $focused) { app.submit(text) }
                Menu {
                    if let a = app.address { Text("\(a.host):\(a.port)") }
                    if !app.modelName.isEmpty { Text("Model: \(app.modelName)") }
                    Picker("AI Mode model", selection: Binding(get: { app.tier }, set: { app.tier = $0 })) {
                        Text("Fast").tag("fast"); Text("Pro").tag("pro")
                    }
                    Button("Disconnect", systemImage: "wifi.slash", role: .destructive) { app.disconnect() }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                .buttonStyle(.glass).buttonBorderShape(.circle)
            }
            .padding(.horizontal, 14)

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(SearchTab.allCases) { t in
                        Button { withAnimation(.bouncy) { app.select(t) } } label: {
                            HStack(spacing: 5) { if t == .mode { Spark(size: 13) }; Text(t.rawValue) }
                                .font(.subheadline.weight(app.tab == t ? .semibold : .regular))
                                .padding(.horizontal, 14).padding(.vertical, 9)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(app.tab == t ? Pal.blue : .secondary)
                        .glassEffect(app.tab == t ? .regular.tint(Pal.blue.opacity(0.25)).interactive() : .regular.interactive(), in: .capsule)
                        .glassEffectID(t.id, in: ns)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14)
        }
        .padding(.top, 6).padding(.bottom, 8)
    }
}

// MARK: - All tab

struct AllTab: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var followUp = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if let c = app.corrected {
                    VStack(alignment: .leading, spacing: 3) {
                        (Text("Showing results for ").foregroundStyle(.secondary) + Text(c).foregroundStyle(Pal.blue).fontWeight(.medium))
                        Button { app.submit(app.original, nocorrect: true) } label: {
                            Text("Search instead for \(app.original)").font(.footnote).foregroundStyle(Pal.blue)
                        }
                    }.font(.subheadline)
                }
                OverviewCard(followUp: $followUp)

                if app.searching && app.results.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding(.top, 30)
                }
                if let e = app.searchError, app.results.isEmpty, !app.searching {
                    Text(e).foregroundStyle(.secondary).padding()
                }
                ForEach(app.results) { h in HitRow(hit: h) }
            }
            .padding(.horizontal, 16).padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

struct HitRow: View {
    let hit: Hit
    @Environment(\.openURL) private var openURL
    var body: some View {
        Button { if let u = URL(string: hit.url) { openURL(u) } } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Text(String(hit.site.first.map(String.init) ?? "•").uppercased())
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(width: 26, height: 26).glassEffect(.regular, in: .circle)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(hit.site).font(.footnote.weight(.medium)).foregroundStyle(.primary)
                        Text(hit.url).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Text(hit.title).font(.title3).foregroundStyle(Pal.blue).multilineTextAlignment(.leading)
                if !hit.snippet.isEmpty {
                    Text(hit.snippet).font(.subheadline).foregroundStyle(.secondary).lineLimit(3).multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AI overview

struct OverviewCard: View {
    @Environment(AppModel.self) private var app
    @Binding var followUp: String
    @FocusState private var focused: Bool

    var body: some View {
        let ov = app.overview
        if ov.status.isEmpty && ov.text.isEmpty && ov.error == nil && !app.searching && ov.steps.isEmpty { EmptyView() } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Spark(size: 20)
                    Text("AI Overview").font(.title3.weight(.medium))
                    Spacer()
                    if !app.modelName.isEmpty {
                        Text(app.modelName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            .padding(.horizontal, 10).padding(.vertical, 3).glassEffect(.regular, in: .capsule)
                    }
                    if !ov.done && app.overviewRunning {
                        Button { app.stopOverview() } label: { Image(systemName: "stop.fill").frame(width: 30, height: 30) }
                            .buttonStyle(.glass).buttonBorderShape(.circle)
                    }
                }

                if !ov.status.isEmpty { HStack(spacing: 8) { ThinkingDots(); Text(ov.status).font(.footnote).foregroundStyle(.secondary) } }
                if !ov.steps.isEmpty || !ov.think.isEmpty {
                    DisclosureGroup("Show thinking") {
                        Text((ov.steps + [ov.think]).filter { !$0.isEmpty }.joined(separator: "\n"))
                            .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }.font(.footnote).tint(.secondary)
                }
                if let e = ov.error { Text(e).foregroundStyle(.red).font(.subheadline) }

                if !ov.text.isEmpty {
                    MarkdownView(text: ov.text, sources: ov.sources.isEmpty ? app.results : ov.sources)
                        .frame(maxHeight: (ov.expanded || !ov.done) ? nil : 260, alignment: .top)
                        .clipped()
                    if ov.done {
                        Button { withAnimation(.smooth) { ov.expanded.toggle() } } label: {
                            Label(ov.expanded ? "Show less" : "Show more", systemImage: ov.expanded ? "chevron.up" : "chevron.down").font(.footnote)
                        }.buttonStyle(.glass)
                    }
                }

                if ov.done && ov.error == nil && !ov.text.isEmpty {
                    HStack(spacing: 8) {
                        TextField("Ask a follow-up", text: $followUp).focused($focused).submitLabel(.send)
                            .onSubmit { send() }
                        Button { send() } label: { Image(systemName: "arrow.up").font(.body.weight(.bold)).frame(width: 34, height: 34) }
                            .buttonStyle(.glassProminent).buttonBorderShape(.circle).tint(Pal.blue)
                            .disabled(followUp.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.leading, 16).padding(.trailing, 6).frame(height: 46)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .padding(.top, 4)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(Pal.purple.opacity(0.12)), in: .rect(cornerRadius: 26))
        }
    }

    private func send() {
        let t = followUp.trimmingCharacters(in: .whitespaces); guard !t.isEmpty else { return }
        followUp = ""; focused = false; app.continueInMode(t)
    }
}

extension AppModel { var overviewRunning: Bool { !overview.done } }

// MARK: - Markdown with citation chips

struct MarkdownView: View {
    let text: String
    let sources: [Hit]
    @Environment(\.openURL) private var openURL

    private enum Block: Hashable { case p(String), h(String), bullet(String), num(Int, String), code(String) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                switch b {
                case .p(let s): inline(s)
                case .h(let s): inline(s).font(.headline)
                case .bullet(let s): HStack(alignment: .firstTextBaseline, spacing: 8) { Text("•"); inline(s) }
                case .num(let n, let s): HStack(alignment: .firstTextBaseline, spacing: 8) { Text("\(n).").monospacedDigit(); inline(s) }
                case .code(let s):
                    ScrollView(.horizontal) { Text(s).font(.system(.footnote, design: .monospaced)).padding(12) }
                        .glassEffect(.regular, in: .rect(cornerRadius: 14))
                }
            }
        }
        .font(.body).lineSpacing(3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "gcite", let i = Int(url.host ?? ""), i >= 1, i <= sources.count, let u = URL(string: sources[i - 1].url) {
                openURL(u); return .handled
            }
            return .systemAction
        })
    }

    private func inline(_ s: String) -> Text {
        let withChips = Self.chips(in: s, sources: sources)
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var a = (try? AttributedString(markdown: withChips, options: opts)) ?? AttributedString(withChips)
        for run in a.runs {
            if let l = run.link, l.scheme == "gcite" {
                a[run.range].foregroundColor = .secondary
                a[run.range].backgroundColor = Color.secondary.opacity(0.15)
                a[run.range].font = .caption
            }
        }
        return Text(a)
    }

    /// [1], [[1]], [1, 2], [[1],[2]] -> small tappable site tags
    static func chips(in s: String, sources: [Hit]) -> String {
        var t = s.replacingOccurrences(of: #"\[\[[A-Za-z][^\]]*\]\]"#, with: "", options: .regularExpression)   // [[Draw: ...]] etc.
        guard let re = try? NSRegularExpression(pattern: #"\[[\d\s,\[\]]*\d[\d\s,\[\]]*\]"#) else { return t }
        let ns = t as NSString
        var out = "", last = 0
        for m in re.matches(in: t, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let nums = ns.substring(with: m.range).split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            var seen = Set<Int>()
            let valid = nums.filter { $0 >= 1 && $0 <= sources.count }
            if valid.isEmpty { out += ns.substring(with: m.range) }      // e.g. "[2024]" is not a citation
            for n in valid where seen.insert(n).inserted {
                let name = sources[n - 1].site.isEmpty ? "source \(n)" : sources[n - 1].site
                out += " [\u{2009}\(name)\u{2009}](gcite://\(n))"
            }
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        t = out
        return t
    }

    private var blocks: [Block] {
        var out: [Block] = [], para: [String] = [], code: [String] = [], inCode = false
        func flush() { if !para.isEmpty { out.append(.p(para.joined(separator: " "))); para = [] } }
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if inCode { out.append(.code(code.joined(separator: "\n"))); code = [] } else { flush() }
                inCode.toggle(); continue
            }
            if inCode { code.append(raw); continue }
            if line.isEmpty { flush(); continue }
            if let r = line.range(of: #"^#{1,4}\s+"#, options: .regularExpression) { flush(); out.append(.h(String(line[r.upperBound...]))); continue }
            if let r = line.range(of: #"^[-*•]\s+"#, options: .regularExpression) { flush(); out.append(.bullet(String(line[r.upperBound...]))); continue }
            if let r = line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                flush(); out.append(.num(Int(line.prefix(while: \.isNumber)) ?? 1, String(line[r.upperBound...]))); continue
            }
            para.append(line)
        }
        if inCode, !code.isEmpty { out.append(.code(code.joined(separator: "\n"))) }
        flush()
        return out
    }
}

// MARK: - Images tab

struct ImagesTab: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 8)]
    var body: some View {
        ScrollView {
            if app.loadingImages { ProgressView().padding(.top, 40) }
            if let e = app.imagesError, app.images.isEmpty { Text(e).foregroundStyle(.secondary).padding() }
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(app.images) { img in
                    Button { if let u = URL(string: img.page) { openURL(u) } } label: {
                        AsyncImage(url: img.thumb) { p in
                            switch p {
                            case .success(let i): i.resizable().scaledToFill()
                            case .failure: Color.secondary.opacity(0.2).overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                            default: Color.secondary.opacity(0.12)
                            }
                        }
                        .frame(height: 120).frame(maxWidth: .infinity).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(alignment: .bottomLeading) {
                            Text(img.source).font(.caption2).lineLimit(1).padding(.horizontal, 8).padding(.vertical, 3)
                                .glassEffect(.regular, in: .capsule).padding(6)
                        }
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 40)
        }
    }
}

// MARK: - News tab

struct NewsTab: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    var body: some View {
        ScrollView {
            if app.loadingNews { ProgressView().padding(.top, 40) }
            if let e = app.newsError, app.news.isEmpty { Text(e).foregroundStyle(.secondary).padding() }
            LazyVStack(spacing: 12) {
                ForEach(app.news) { n in
                    Button { if let u = URL(string: n.url) { openURL(u) } } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(n.source)\(n.date.isEmpty ? "" : " · " + n.date)").font(.caption).foregroundStyle(.secondary)
                                Text(n.title).font(.headline).multilineTextAlignment(.leading)
                                Text(n.snippet).font(.subheadline).foregroundStyle(.secondary).lineLimit(3).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            if let img = n.image {
                                AsyncImage(url: img) { p in
                                    if let i = p.image { i.resizable().scaledToFill() } else { Color.secondary.opacity(0.12) }
                                }
                                .frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: .rect(cornerRadius: 22))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 40)
        }
    }
}

// MARK: - AI Mode

struct ModeTab: View {
    @Environment(AppModel.self) private var app
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if app.turns.isEmpty {
                        VStack(spacing: 10) {
                            Spark(size: 34)
                            Text("Ask anything").font(.title3.weight(.medium))
                            Text("AI Mode searches the web and answers with sources.").font(.subheadline).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.top, 60)
                    }
                    ForEach(app.turns) { t in TurnView(turn: t).id(t.id) }
                    Color.clear.frame(height: 90).id("end")
                }
                .padding(.horizontal, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: app.turns.last?.answer) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            .safeAreaInset(edge: .bottom) { inputBar }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask AI Mode", text: $text, axis: .vertical).lineLimit(1...4).focused($focused)
                .padding(.leading, 18).padding(.vertical, 12)
            Button {
                if app.modeBusy { app.stopMode() } else { send() }
            } label: {
                Image(systemName: app.modeBusy ? "stop.fill" : "arrow.up").font(.body.weight(.bold)).frame(width: 38, height: 38)
            }
            .buttonStyle(.glassProminent).buttonBorderShape(.circle).tint(Pal.blue)
            .disabled(!app.modeBusy && text.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.trailing, 5)
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 28))
        .padding(.horizontal, 14).padding(.bottom, 6)
    }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { return }
        text = ""; Task { await app.sendMode(t) }
    }
}

struct TurnView: View {
    @Environment(AppModel.self) private var app
    let turn: ModeTurn

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer(minLength: 50)
                Text(turn.text).padding(.horizontal, 16).padding(.vertical, 10)
                    .glassEffect(.regular.tint(Pal.blue.opacity(0.3)), in: .rect(cornerRadius: 22))
            }
            VStack(alignment: .leading, spacing: 10) {
                if !turn.status.isEmpty { HStack(spacing: 8) { ThinkingDots(); Text(turn.status).font(.footnote).foregroundStyle(.secondary) } }
                if !turn.steps.isEmpty || !turn.think.isEmpty {
                    DisclosureGroup("Show thinking") {
                        Text((turn.steps + [turn.think]).filter { !$0.isEmpty }.joined(separator: "\n"))
                            .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }.font(.footnote).tint(.secondary)
                }
                if !turn.answer.isEmpty { MarkdownView(text: turn.answer, sources: turn.sources) }
                if let e = turn.error { Text(e).foregroundStyle(.red).font(.subheadline) }
                if turn.noResultsFor != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("There isn't a result available for this search.").fontWeight(.medium)
                        Text("You can still get an answer from the model, but it won't be backed by sources.").font(.subheadline).foregroundStyle(.secondary)
                        Button("Continue anyway") { Task { await app.sendMode(turn.text, force: true, reuse: turn) } }
                            .buttonStyle(.glassProminent).tint(Pal.blue)
                    }
                }
                if turn.status.isEmpty && turn.answer.isEmpty && turn.error == nil && turn.noResultsFor == nil && !turn.done { ThinkingDots() }
                if turn.done && !turn.sources.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        GlassEffectContainer(spacing: 8) {
                            HStack(spacing: 8) {
                                ForEach(Array(turn.sources.prefix(8).enumerated()), id: \.offset) { i, h in
                                    SourceChip(index: i + 1, hit: h)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 26))
        }
    }
}

struct SourceChip: View {
    let index: Int, hit: Hit
    @Environment(\.openURL) private var openURL
    var body: some View {
        Button { if let u = URL(string: hit.url) { openURL(u) } } label: {
            Text("\(index) · \(hit.site)").font(.caption).lineLimit(1).frame(maxWidth: 190).padding(.horizontal, 10).padding(.vertical, 6)
        }.buttonStyle(.glass)
    }
}