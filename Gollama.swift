// Gollama.swift
// Native SwiftUI client for Gollama Search with Liquid Glass (iOS 26+, iPhone + iPad, Xcode 26).
//
// SETUP
//  1. App target, deployment target iOS 26. Use this as the only file with @main.
//  2. Info.plist:
//       NSLocalNetworkUsageDescription = "Gollama needs the local network to find your Gollama server."
//       App Transport Security Settings -> Allows Local Networking = YES      (private http://ip:port)
//     Public servers should use https (Cloudflare Tunnel does). A plain http:// public server needs an ATS exception.
//  3. On the computer running app.py: turn on the network server in Settings.
//
// NOTE: inside @Observable classes every stored property is declared on its own line (the macro can't take `var a = 1, b = 2`).

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
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

// MARK: - Palette + small shared views

enum Pal {
    static let blue = Color(red: 0.26, green: 0.52, blue: 0.96)
    static let red = Color(red: 0.92, green: 0.26, blue: 0.21)
    static let yellow = Color(red: 0.98, green: 0.74, blue: 0.02)
    static let green = Color(red: 0.20, green: 0.66, blue: 0.33)
    static let purple = Color(red: 0.61, green: 0.45, blue: 0.80)
    static let pink = Color(red: 0.85, green: 0.40, blue: 0.44)
    static let logo: [Color] = [blue, red, yellow, blue, green, red, blue]
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension View {
    /// Keeps content in a readable column on iPad / large windows.
    func readableWidth(_ w: CGFloat = 760) -> some View { frame(maxWidth: w).frame(maxWidth: .infinity) }
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

/// Round glass icon, exactly the same height as the search field next to it.
struct GlassIcon: View {
    let name: String
    var size: CGFloat = 44
    var body: some View {
        Image(systemName: name)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .glassEffect(.regular.interactive(), in: .circle)
    }
}

/// Small round send / stop button. Plain style on purpose: the glass button styles add padding that makes it huge.
struct SendButton: View {
    var systemName = "arrow.up"
    var enabled = true
    var size: CGFloat = 32
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(enabled ? Pal.blue : Color.gray.opacity(0.45), in: .circle)
                .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Wraps chips onto several lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        var w: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW && x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            w = max(w, x - spacing)
        }
        return CGSize(width: w, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX && x > bounds.minX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

// MARK: - Networking

enum ConnectMode: String, CaseIterable, Identifiable, Codable {
    case privateNet = "Private"
    case publicNet = "Public"
    var id: String { rawValue }
}

struct ServerAddress: Codable, Hashable {
    var urlString: String
    var mode: ConnectMode
    var base: URL { URL(string: urlString) ?? URL(string: "http://localhost")! }
    var display: String {
        let u = base
        let h = u.host ?? urlString
        if let p = u.port { return "\(h):\(p)" }
        return h
    }
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

    /// Looks at `/` to see whether a Gollama server (main page, not the ChatGPT-style one) answers there.
    static func probe(base: URL, timeout: TimeInterval = 0.7) async -> ProbeResult {
        guard let url = URL(string: base.absoluteString + "/") else { return .unreachable }
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
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
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

/// The Wi-Fi IPv4 address of this device.
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
    let title: String
    let url: String
    let snippet: String
    let site: String
    init?(_ d: [String: Any]) {
        guard let u = d["url"] as? String, !u.isEmpty else { return nil }
        url = u
        title = (d["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? u
        snippet = d["snippet"] as? String ?? ""
        site = (d["site"] as? String) ?? (d["source"] as? String) ?? URL(string: u)?.host?.replacingOccurrences(of: "www.", with: "") ?? ""
    }
    static func list(_ any: Any?) -> [Hit] { (any as? [[String: Any]])?.compactMap(Hit.init) ?? [] }
    var asDict: [String: Any] { ["title": title, "url": url, "snippet": snippet, "site": site] }
}

struct ImageItem: Identifiable, Hashable {
    let id = UUID()
    let thumb: URL?
    let full: URL?
    let page: String
    let title: String
    let source: String
}

struct NewsItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let url: String
    let snippet: String
    let source: String
    let date: String
    let image: URL?
}

struct ChatSummary: Identifiable, Hashable {
    let id: String
    let title: String
    let updated: Double
    let text: String
}

struct Suggestion: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let send: String
}

@Observable final class Overview {
    let id = UUID()
    var status = ""
    var text = ""
    var think = ""
    var error: String?
    var steps: [String] = []
    var sources: [Hit] = []
    var done = false
    var expanded = false
}

enum AttachKind { case image, file, video }

@Observable final class Attachment: Identifiable {
    let id = UUID()
    let kind: AttachKind
    let name: String
    var b64 = ""
    var text = ""
    var videoId: String?
    var state = "ready"          // ready | uploading | processing | error
    var progress = 0.0
    var message = ""
    var thumb: UIImage?
    init(kind: AttachKind, name: String) { self.kind = kind; self.name = name }
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
    var attNames: [String] = []
    var thumbs: [UIImage] = []
    var imagesB64: [String] = []
    var imageNames: [String] = []
    var fileDicts: [[String: String]] = []
    var videoIds: [String] = []
    var videoNames: [String] = []
    init(id: Int, text: String) { self.id = id; self.text = text }
}

enum SearchTab: String, CaseIterable, Identifiable {
    case all = "All"
    case images = "Images"
    case news = "News"
    var id: String { rawValue }
}

enum MainTab: Hashable { case search, mode }

/// A video picked from the photo library, copied somewhere we can read it.
struct VideoFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { v in
            SentTransferredFile(v.url)
        } importing: { received in
            let dst = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: dst)
            return VideoFile(url: dst)
        }
    }
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
    var notice: String?

    var mainTab: MainTab = .search

    // search
    var query = ""
    var searchTab: SearchTab = .all
    var started = false
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
    var recents: [String] = UserDefaults.standard.stringArray(forKey: "gollama.recents") ?? []
    var suggestions: [Suggestion] = []

    // AI Mode chat
    var turns: [ModeTurn] = []
    var chatId: String?
    var chatTitle = "New chat"
    var chats: [ChatSummary] = []
    var pending: [Attachment] = []

    private var nextTurn = 1
    private var titled = false
    private var pollTask: Task<Void, Never>?
    private var overviewActive = false
    private var activeTurns = Set<Int>()

    // MARK: connect
    func connect(base: URL, mode: ConnectMode, code: String) async throws {
        let shown = ServerAddress(urlString: base.absoluteString, mode: mode).display
        switch await GollamaClient.probe(base: base, timeout: mode == .publicNet ? 10 : 3) {
        case .unreachable:
            throw GollamaError.message("Couldn't reach \(shown). Check the address, and that the Gollama server" + (mode == .publicNet ? " or tunnel" : "") + " is running.")
        case .other:
            throw GollamaError.message("\(shown) answered, but it isn't Gollama's main page.")
        case .gollama(let needsCode):
            let c = GollamaClient(base: base)
            if needsCode && !code.isEmpty { try await c.login(code: code) }   // with no code we try the saved login cookie
            do { try await finishConnect(c, base, mode) }
            catch {
                guard needsCode else { throw error }
                throw GollamaError.message(code.isEmpty ? "This server needs an access code." : "That access code isn't right.")
            }
        }
    }

    private func finishConnect(_ c: GollamaClient, _ base: URL, _ mode: ConnectMode) async throws {
        let cfg = try await c.call("get_config") as? [String: Any] ?? [:]
        client = c
        address = ServerAddress(urlString: base.absoluteString, mode: mode)
        modelName = cfg["model"] as? String ?? ""
        tier = cfg["mode_tier"] as? String ?? "fast"
        let tm = cfg["think_mode"] as? String
        thinkMode = (tm == nil || tm == "auto") ? nil : tm
        connected = true
        UserDefaults.standard.set(try? JSONEncoder().encode(address), forKey: "gollama.server")
        await loadChats()
        await loadSuggestions()
    }

    func tryAutoReconnect() async {
        guard !connected, let d = UserDefaults.standard.data(forKey: "gollama.server"),
              let a = try? JSONDecoder().decode(ServerAddress.self, from: d) else { return }
        address = a
        try? await connect(base: a.base, mode: a.mode, code: "")
    }

    func disconnect() {
        pollTask?.cancel()
        pollTask = nil
        Task { await stopAll() }
        connected = false
        client = nil
        started = false
        query = ""
        results = []
        overview = Overview()
        turns = []
        chats = []
        chatId = nil
        mainTab = .search
    }

    func flash(_ message: String) {
        notice = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if notice == message { notice = nil }
        }
    }

    // MARK: search
    func goHome() {
        started = false
        query = ""
        results = []
        overview = Overview()
        images = []
        news = []
        searchTab = .all
        searchError = nil
        corrected = nil
        Task { try? await client?.call("stop") }
    }

    func addRecent(_ q: String) {
        recents.removeAll { $0.lowercased() == q.lowercased() }
        recents.insert(q, at: 0)
        if recents.count > 8 { recents = Array(recents.prefix(8)) }
        UserDefaults.standard.set(recents, forKey: "gollama.recents")
    }

    func submit(_ text: String, nocorrect: Bool = false) {
        let q = text.trimmed
        guard !q.isEmpty else { return }
        query = q
        started = true
        addRecent(q)
        results = []
        corrected = nil
        searchError = nil
        overview = Overview()
        images = []
        news = []
        imagesError = nil
        newsError = nil
        switch searchTab {
        case .all: Task { await runSearch(q, nocorrect: nocorrect) }
        case .images: Task { await loadImages() }
        case .news: Task { await loadNews() }
        }
    }

    func select(_ t: SearchTab) {
        searchTab = t
        if t == .all && results.isEmpty && !searching && !query.isEmpty { Task { await runSearch(query, nocorrect: false) } }
        if t == .images && images.isEmpty && !loadingImages && !query.isEmpty { Task { await loadImages() } }
        if t == .news && news.isEmpty && !loadingNews && !query.isEmpty { Task { await loadNews() } }
    }

    func runSearch(_ q: String, nocorrect: Bool) async {
        guard let c = client else { return }
        searching = true
        searchError = nil
        results = []
        corrected = nil
        overview = Overview()
        overviewActive = false
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
            overviewActive = false
            overview.done = true
            overview.status = ""
        }
    }

    func loadImages() async {
        guard let c = client else { return }
        loadingImages = true
        defer { loadingImages = false }
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
        loadingNews = true
        defer { loadingNews = false }
        do {
            let r = try await c.call("search_news", [query]) as? [String: Any] ?? [:]
            newsError = r["error"] as? String
            news = (r["items"] as? [[String: Any]] ?? []).map {
                NewsItem(title: $0["title"] as? String ?? "", url: $0["url"] as? String ?? "", snippet: $0["snippet"] as? String ?? "",
                         source: $0["source"] as? String ?? "", date: $0["date"] as? String ?? "", image: ($0["image"] as? String).flatMap(URL.init))
            }
        } catch { newsError = error.localizedDescription }
    }

    func loadSuggestions() async {
        guard let c = client, let r = try? await c.call("suggestions_get") as? [String: Any] else { return }
        suggestions = (r["items"] as? [[String: Any]] ?? []).compactMap { d in
            guard let t = d["title"] as? String, !t.isEmpty else { return nil }
            return Suggestion(title: t, send: d["send"] as? String ?? t)
        }
    }

    // MARK: chat history (stored on the server, same list the web page shows for this device)
    func loadChats() async {
        guard let c = client, let r = try? await c.call("chats_list") as? [[String: Any]] else { return }
        chats = r.compactMap { d in
            guard let id = d["id"] as? String else { return nil }
            return ChatSummary(id: id, title: d["title"] as? String ?? "Untitled", updated: d["updated"] as? Double ?? 0, text: d["text"] as? String ?? "")
        }
    }

    func newChat() {
        if modeBusy { stopMode() }
        turns = []
        chatId = nil
        chatTitle = "New chat"
        titled = false
        pending = []
    }

    func openChat(_ id: String) async {
        guard let c = client else { return }
        if modeBusy { stopMode() }
        guard let d = try? await c.call("chat_get", [id]) as? [String: Any] else { return }
        chatId = id
        chatTitle = d["title"] as? String ?? "Chat"
        titled = true
        pending = []
        var loaded: [ModeTurn] = []
        for td in (d["turns"] as? [[String: Any]] ?? []) {
            let t = ModeTurn(id: nextTurn, text: td["text"] as? String ?? "")
            nextTurn += 1
            t.answer = td["buf"] as? String ?? ""
            t.sources = Hit.list(td["results"])
            t.done = true
            if let att = td["att"] as? [String: Any] {
                var names = att["images"] as? [String] ?? []
                names += att["files"] as? [String] ?? []
                names += (att["videos"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
                t.attNames = names
            }
            loaded.append(t)
        }
        turns = loaded
    }

    func deleteChat(_ id: String) async {
        _ = try? await client?.call("chat_delete", [id])
        if chatId == id { newChat() }
        await loadChats()
    }

    func clearChats() async {
        _ = try? await client?.call("chats_clear")
        newChat()
        await loadChats()
    }

    private func ensureChat() {
        if chatId == nil {
            chatId = "c" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + String(Int.random(in: 0..<1296), radix: 36)
        }
    }

    private func saveChat() {
        guard client != nil, chatId != nil else { return }
        Task { await saveChatNow() }
    }

    private func saveChatNow() async {
        guard let c = client, let id = chatId else { return }
        let saved: [[String: Any]] = turns.filter { $0.done && !$0.answer.isEmpty }.map { t in
            [
                "text": t.text, "query": t.text, "buf": t.answer, "status": "done",
                "results": t.sources.map { $0.asDict }, "think": [Any](),
                "att": ["images": t.imageNames, "files": t.fileDicts.compactMap { $0["name"] }, "videos": t.videoNames.map { ["name": $0] }] as [String: Any]
            ] as [String: Any]
        }
        guard !saved.isEmpty else { return }
        let chat: [String: Any] = ["id": id, "title": chatTitle, "updated": Date().timeIntervalSince1970 * 1000, "turns": saved, "project": NSNull()]
        _ = try? await c.call("chat_save", [chat])
        await loadChats()
    }

    // MARK: AI Mode
    /// The AI Overview's follow-up bar: opens a chat that already contains the search and its overview, then asks the follow-up in it.
    func continueInMode(_ followUp: String) {
        let q = followUp.trimmed
        guard !q.isEmpty else { return }
        let base = ModeTurn(id: nextTurn, text: query)
        nextTurn += 1
        base.answer = overview.text
        base.sources = overview.sources.isEmpty ? results : overview.sources
        base.done = true
        newChat()
        turns = [base]
        chatTitle = String(query.prefix(40))
        titled = true
        mainTab = .mode
        Task { await sendMode(q) }
    }

    func sendMode(_ raw: String, force: Bool = false, reuse: ModeTurn? = nil) async {
        guard let c = client else { return }
        if pending.contains(where: { $0.state == "uploading" || $0.state == "processing" }) { flash("Wait for the attachment to finish."); return }
        let text = raw.trimmed
        if reuse == nil && text.isEmpty && pending.isEmpty { return }
        ensureChat()
        let turn: ModeTurn
        if let r = reuse {
            turn = r
            turn.noResultsFor = nil
            turn.answer = ""
            turn.done = false
        } else {
            let ready = pending.filter { $0.state == "ready" }
            let hasVideo = ready.contains { $0.kind == .video }
            let hasImage = ready.contains { $0.kind == .image }
            let shown = text.isEmpty ? "Take a look at the attached " + (hasVideo ? "video" : hasImage ? "image" : "file") + "." : text
            turn = ModeTurn(id: nextTurn, text: shown)
            nextTurn += 1
            for a in ready {
                switch a.kind {
                case .image:
                    turn.imagesB64.append(a.b64)
                    turn.imageNames.append(a.name)
                    if let t = a.thumb { turn.thumbs.append(t) }
                case .file:
                    turn.fileDicts.append(["name": a.name, "text": a.text])
                    turn.attNames.append(a.name)
                case .video:
                    if let id = a.videoId { turn.videoIds.append(id) }
                    turn.videoNames.append(a.name)
                    turn.attNames.append(a.name)
                }
            }
            turns.append(turn)
            pending = []
        }
        query = turn.text
        let idx = turns.firstIndex(where: { $0.id == turn.id }) ?? turns.count
        let prior = turns[..<idx].filter { $0.done && $0.error == nil && !$0.answer.isEmpty }
        let withImages = Set(prior.filter { !$0.imagesB64.isEmpty }.suffix(2).map { $0.id })
        var history: [[String: Any]] = []
        for t in prior {
            var m: [String: Any] = ["role": "user", "content": t.text + (t.videoNames.isEmpty ? "" : " [attached video: " + t.videoNames.joined(separator: ", ") + "]")]
            if withImages.contains(t.id) { m["images"] = t.imagesB64 }
            history.append(m)
            history.append(["role": "assistant", "content": t.answer])
        }
        let attach: [String: Any] = [
            "images": turn.imagesB64, "image_names": turn.imageNames, "files": turn.fileDicts,
            "videos": turn.videoIds, "temp": false, "project": NSNull()
        ]
        activeTurns.insert(turn.id)
        do {
            try await c.call("mode_send", [turn.id, turn.text, history, force, tier, attach, thinkMode.map { $0 as Any } ?? NSNull()])
            startPolling()
        } catch {
            turn.error = error.localizedDescription
            turn.done = true
            activeTurns.remove(turn.id)
        }
    }

    func stopMode() {
        for t in turns where !t.done { t.done = true; t.status = "" }
        activeTurns.removeAll()
        Task { try? await client?.call("mode_stop") }
    }

    func stopAll() async {
        _ = try? await client?.call("stop")
        _ = try? await client?.call("mode_stop")
    }

    var modeBusy: Bool { !activeTurns.isEmpty }

    private func turnFinished(_ t: ModeTurn) {
        activeTurns.remove(t.id)
        guard t.error == nil, !t.answer.isEmpty else { return }
        if !titled {
            titled = true
            chatTitle = String(t.text.prefix(40))
            if let c = client {
                let id = chatId
                let q = t.text
                let a = t.answer
                Task {
                    let title = try? await c.call("make_title", [q, a]) as? String
                    if let title, !title.isEmpty, chatId == id { chatTitle = title; saveChat() }
                }
            }
        }
        saveChat()
    }

    // MARK: attachments
    func addImage(data: Data, name: String) {
        guard pending.filter({ $0.kind == .image }).count < 4, let img = UIImage(data: data) else { return }
        let maxSide: CGFloat = 1280
        let scale = min(1, maxSide / max(img.size.width, img.size.height))
        let size = CGSize(width: max(1, (img.size.width * scale).rounded()), height: max(1, (img.size.height * scale).rounded()))
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        let small = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            img.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = small.jpegData(compressionQuality: 0.9) else { return }
        let a = Attachment(kind: .image, name: name)
        a.b64 = jpeg.base64EncodedString()
        a.thumb = small
        pending.append(a)
    }

    func attach(photo item: PhotosPickerItem) async {
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            if let v = try? await item.loadTransferable(type: VideoFile.self) {
                await addVideo(url: v.url, name: "video-\(pending.count + 1).mov")
            } else { flash("Couldn't read that video.") }
        } else if let data = try? await item.loadTransferable(type: Data.self) {
            addImage(data: data, name: "photo-\(pending.count + 1).jpg")
        } else { flash("Couldn't read that photo.") }
    }

    func attach(file url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let type = UTType(filenameExtension: url.pathExtension)
        if type?.conforms(to: .movie) == true {
            let dst = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
            if (try? FileManager.default.copyItem(at: url, to: dst)) != nil { await addVideo(url: dst, name: url.lastPathComponent) }
            else { flash("Couldn't read that video.") }
        } else if type?.conforms(to: .image) == true {
            if let d = try? Data(contentsOf: url) { addImage(data: d, name: url.lastPathComponent) }
        } else if let d = try? Data(contentsOf: url) {
            let head = d.prefix(60_000)
            var text: String?
            for cut in 0...3 where text == nil { text = String(data: head.dropLast(cut), encoding: .utf8) }
            guard let t = text else { flash("\(url.lastPathComponent) isn't a text file."); return }
            let a = Attachment(kind: .file, name: url.lastPathComponent)
            a.text = String(t.prefix(20000))
            pending.append(a)
        }
    }

    func addVideo(url: URL, name: String) async {
        guard let c = client else { return }
        for old in pending where old.kind == .video { discard(old) }
        pending.removeAll { $0.kind == .video }
        let a = Attachment(kind: .video, name: name)
        a.state = "uploading"
        a.message = "Uploading…"
        pending.append(a)
        func fail(_ m: String) { a.state = "error"; a.message = m }
        do {
            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
            let b = try await c.call("video_begin", [name, size, tier]) as? [String: Any]
            guard b?["ok"] as? Bool == true, let vid = b?["id"] as? String else { fail(b?["error"] as? String ?? "Upload failed."); return }
            a.videoId = vid
            let fh = try FileHandle(forReadingFrom: url)
            defer { try? fh.close() }
            var sent = 0
            while true {
                guard let chunk = try fh.read(upToCount: 700 * 1024), !chunk.isEmpty else { break }
                let r = try await c.call("video_chunk", [vid, chunk.base64EncodedString()]) as? [String: Any]
                if r?["ok"] as? Bool != true { fail(r?["error"] as? String ?? "Upload failed."); return }
                sent += chunk.count
                a.progress = min(0.95, Double(sent) / Double(max(size, 1)))
            }
            try await c.call("video_finish", [vid])
            a.state = "processing"
            a.message = "Reading the video…"
            a.progress = 0
            for _ in 0..<900 {
                try await Task.sleep(for: .seconds(1))
                guard pending.contains(where: { $0.id == a.id }) else { return }
                let s = try await c.call("video_status", [vid]) as? [String: Any] ?? [:]
                let st = s["state"] as? String ?? ""
                if st == "ready" { a.state = "ready"; a.message = ""; return }
                if st == "error" { fail(s["msg"] as? String ?? "Could not read the video."); return }
                a.message = s["msg"] as? String ?? ""
                a.progress = s["progress"] as? Double ?? 0
            }
            fail("Reading the video took too long.")
        } catch { fail(error.localizedDescription) }
    }

    func remove(_ a: Attachment) {
        pending.removeAll { $0.id == a.id }
        discard(a)
    }

    private func discard(_ a: Attachment) {
        if a.kind == .video, let id = a.videoId { Task { _ = try? await client?.call("video_discard", [id]) } }
    }

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
            case "onModeDone": t.done = true; t.status = ""; turnFinished(t)
            case "onModeError": t.error = s; t.done = true; t.status = ""; turnFinished(t)
            case "onModeNoResults": t.noResultsFor = t.text; t.done = true; t.status = ""; activeTurns.remove(id)
            default: break
            }
        }
    }
}

// MARK: - Answer rendering (markdown, highlights, follow-up links, rounded citation chips)

enum AnswerParser {
    enum Kind { case para, heading, bullet, number(Int), code }

    struct Block: Identifiable {
        let id: Int
        var kind: Kind
        var text = AttributedString()
        var raw = ""
        var cites: [Int] = []
        var chip: String?
    }

    struct Parsed {
        var blocks: [Block] = []
        var suggests: [String] = []
    }

    private static let citeRe = try! NSRegularExpression(pattern: #"\s?\[[\d\s,\[\]]*\d[\d\s,\[\]]*\]"#)
    private static let tagRe = try! NSRegularExpression(pattern: #"\[\[suggest:\s*([^\]]*?)\s*\]\]"#)
    private static let hlRe = try! NSRegularExpression(pattern: #"\[\[hl:\s*(.*?)\]\]"#, options: [.dotMatchesLineSeparators])

    static func parse(_ src: String, sourceCount: Int, fadeTail: Int) -> Parsed {
        var s = src.replacingOccurrences(of: "\r\n", with: "\n")
        // hide a tag that is still being typed (a half-written highlight is kept so it can appear as it streams)
        s = s.replacingOccurrences(of: #"\[\[(?!hl:)[^\]]*$"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\[[\d\s,\[]*$"#, with: "", options: .regularExpression)
        s = hlRe.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "\u{E000}$1\u{E001}")
        s = s.replacingOccurrences(of: "[[hl:", with: "\u{E000}")

        var items: [(Kind, String)] = []
        var para: [String] = []
        var code: [String] = []
        var inCode = false
        func flush() { if !para.isEmpty { items.append((.para, para.joined(separator: " "))); para = [] } }
        for rawLine in s.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if inCode { items.append((.code, code.joined(separator: "\n"))); code = [] } else { flush() }
                inCode.toggle()
                continue
            }
            if inCode { code.append(rawLine); continue }
            if line.isEmpty { flush(); continue }
            if let r = line.range(of: #"^#{1,4}\s+"#, options: .regularExpression) { flush(); items.append((.heading, String(line[r.upperBound...]))); continue }
            if let r = line.range(of: #"^[-*•]\s+"#, options: .regularExpression) { flush(); items.append((.bullet, String(line[r.upperBound...]))); continue }
            if let r = line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                flush()
                items.append((.number(Int(line.prefix(while: \.isNumber)) ?? 1), String(line[r.upperBound...])))
                continue
            }
            para.append(line)
        }
        if inCode && !code.isEmpty { items.append((.code, code.joined(separator: "\n"))) }
        flush()

        var out = Parsed()
        let lastText = items.lastIndex(where: { item in
            if case .code = item.0 { return false }
            return true
        })
        for (i, it) in items.enumerated() {
            var b = Block(id: i, kind: it.0)
            if case .code = it.0 { b.raw = it.1; out.blocks.append(b); continue }
            var raw = it.1
            if case .bullet = it.0 {
                let ns = raw as NSString
                if let m = tagRe.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)), m.range.location == 0 {
                    b.chip = ns.substring(with: m.range(at: 1))
                    raw = ns.substring(from: m.range.location + m.range.length).trimmingCharacters(in: CharacterSet(charactersIn: " -–—:\u{2009}"))
                }
            }
            let (clean, cites) = extractCites(raw, count: sourceCount)
            b.cites = cites
            b.text = attributed(clean, suggests: &out.suggests, fade: i == lastText ? fadeTail : 0)
            out.blocks.append(b)
        }
        return out
    }

    private static func extractCites(_ raw: String, count: Int) -> (String, [Int]) {
        let ns = raw as NSString
        let ms = NSMutableString(string: raw)
        var cites: [Int] = []
        for m in citeRe.matches(in: raw, range: NSRange(location: 0, length: ns.length)).reversed() {
            let nums = ns.substring(with: m.range).split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            if !nums.isEmpty && nums.allSatisfy({ $0 >= 1 && $0 <= count }) {
                cites.insert(contentsOf: nums, at: 0)
                ms.replaceCharacters(in: m.range, with: "")
            }
        }
        return (ms as String, cites)
    }

    private static func attributed(_ s: String, suggests: inout [String], fade: Int) -> AttributedString {
        // inline follow-up tags become pressable links
        var withLinks = ""
        let ns = s as NSString
        var last = 0
        for m in tagRe.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            withLinks += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let t = ns.substring(with: m.range(at: 1))
            withLinks += "[↳ \(t)](gsuggest://s\(suggests.count))"
            suggests.append(t)
            last = m.range.location + m.range.length
        }
        withLinks += ns.substring(from: last)

        // markdown per segment, highlighted segments get a background
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var out = AttributedString()
        var hl = false
        var buf = ""
        func flush() {
            guard !buf.isEmpty else { return }
            var seg = (try? AttributedString(markdown: buf, options: opts)) ?? AttributedString(buf)
            if hl { seg.backgroundColor = Pal.yellow.opacity(0.35) }
            out.append(seg)
            buf = ""
        }
        for ch in withLinks {
            if ch == "\u{E000}" { flush(); hl = true }
            else if ch == "\u{E001}" { flush(); hl = false }
            else { buf.append(ch) }
        }
        flush()

        for run in out.runs {
            if let l = run.link, l.scheme == "gsuggest" { out[run.range].foregroundColor = Pal.blue }
        }

        // the newest characters fade in
        if fade > 0 {
            let total = out.characters.count
            for k in 0..<min(fade, total) {
                let s0 = out.index(out.startIndex, offsetByCharacters: total - 1 - k)
                let e0 = out.index(s0, offsetByCharacters: 1)
                let alpha = 0.12 + 0.88 * Double(k) / Double(fade)
                out[s0..<e0].foregroundColor = Color.primary.opacity(alpha)
            }
        }
        return out
    }
}

struct MarkdownView: View {
    let text: String
    let sources: [Hit]
    var fading = false
    var onSuggest: ((String) -> Void)?

    var body: some View {
        let parsed = AnswerParser.parse(text, sourceCount: sources.count, fadeTail: fading ? 16 : 0)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(parsed.blocks) { b in blockView(b) }
        }
        .font(.body)
        .lineSpacing(3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "gsuggest", let h = url.host, h.hasPrefix("s"), let i = Int(h.dropFirst()), i < parsed.suggests.count {
                onSuggest?(parsed.suggests[i])
                return .handled
            }
            return .systemAction
        })
    }

    @ViewBuilder private func blockView(_ b: AnswerParser.Block) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch b.kind {
            case .code:
                ScrollView(.horizontal) { Text(b.raw).font(.system(.footnote, design: .monospaced)).padding(12) }
                    .glassEffect(.regular, in: .rect(cornerRadius: 14))
            case .heading:
                Text(b.text).font(.headline)
            case .para:
                Text(b.text)
            case .bullet:
                if let chip = b.chip {
                    VStack(alignment: .leading, spacing: 4) {
                        Button { onSuggest?(chip) } label: {
                            Label(chip, systemImage: "arrow.turn.down.right")
                                .font(.subheadline)
                                .multilineTextAlignment(.leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                        if !b.text.characters.isEmpty { Text(b.text).font(.footnote).foregroundStyle(.secondary) }
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) { Text("•"); Text(b.text) }
                }
            case .number(let n):
                HStack(alignment: .firstTextBaseline, spacing: 8) { Text("\(n).").monospacedDigit(); Text(b.text) }
            }
            if !b.cites.isEmpty { CiteRow(cites: b.cites, sources: sources) }
        }
    }
}

/// Citations as rounded glass chips under the paragraph they belong to.
struct CiteRow: View {
    let cites: [Int]
    let sources: [Hit]
    @Environment(\.openURL) private var openURL

    private var unique: [Int] {
        var seen = Set<Int>()
        return cites.filter { seen.insert($0).inserted }
    }

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(unique, id: \.self) { n in
                if n >= 1 && n <= sources.count {
                    let h = sources[n - 1]
                    Button { if let u = URL(string: h.url) { openURL(u) } } label: {
                        HStack(spacing: 5) {
                            Text("\(n)").font(.caption2.weight(.bold)).foregroundStyle(Pal.blue)
                            Text(h.site).font(.caption).lineLimit(1).frame(maxWidth: 150)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Reveals streamed text a little at a time, with the newest characters fading in.
struct AnswerText: View {
    let text: String
    let sources: [Hit]
    let streaming: Bool
    var onSuggest: ((String) -> Void)?
    @State private var shown: Int

    init(text: String, sources: [Hit], streaming: Bool, onSuggest: ((String) -> Void)? = nil) {
        self.text = text
        self.sources = sources
        self.streaming = streaming
        self.onSuggest = onSuggest
        _shown = State(initialValue: streaming ? 0 : text.count)
    }

    private var animating: Bool { streaming || shown < text.count }

    var body: some View {
        MarkdownView(text: animating ? String(text.prefix(shown)) : text, sources: sources, fading: animating, onSuggest: onSuggest)
            .task(id: text.count) { await reveal() }
    }

    private func reveal() async {
        let total = text.count
        while shown < total {
            shown += max(1, (total - shown) / 12)
            try? await Task.sleep(for: .milliseconds(30))
            if Task.isCancelled { return }
        }
    }
}

// MARK: - Root

struct RootView: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        @Bindable var app = app
        ZStack {
            AmbientBackground()
            if app.connected {
                TabView(selection: $app.mainTab) {
                    Tab("Search", systemImage: "magnifyingglass", value: MainTab.search) { SearchRoot() }
                    Tab("AI Mode", systemImage: "sparkles", value: MainTab.mode) { AIModeRoot() }
                }
                .tabViewStyle(.sidebarAdaptable)
                .transition(.opacity)
            } else {
                ConnectScreen().transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if let n = app.notice {
                Text(n)
                    .font(.footnote)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.3), value: app.connected)
        .animation(.smooth(duration: 0.25), value: app.notice)
    }
}

struct ServerMenu: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        Menu {
            if let a = app.address { Text(a.display) }
            if !app.modelName.isEmpty { Text("Model: \(app.modelName)") }
            Button("Disconnect", systemImage: "wifi.slash", role: .destructive) { app.disconnect() }
        } label: {
            GlassIcon(name: "ellipsis", size: 44)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
    }
}

// MARK: - Connect screen

struct Found: Identifiable, Hashable {
    let id = UUID()
    let host: String
    let port: Int
    let needsCode: Bool
}

struct ConnectScreen: View {
    @Environment(AppModel.self) private var app
    @State private var mode: ConnectMode = .privateNet
    @State private var host = ""
    @State private var port = "8765"
    @State private var portTo = "8765"
    @State private var publicURL = ""
    @State private var usePort = false
    @State private var publicPort = ""
    @State private var code = ""
    @State private var found: [Found] = []
    @State private var scanning = false
    @State private var progress = 0.0
    @State private var scanTask: Task<Void, Never>?
    @State private var connecting = false
    @State private var error: String?
    @State private var scannedOnce = false
    @FocusState private var focus: Field?
    enum Field { case host, port, portTo, url, publicPort, code }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                GollamaLogo(size: 60).padding(.top, 44)
                Text("Connect to Gollama").font(.title3.weight(.medium))

                GlassEffectContainer(spacing: 16) {
                    VStack(spacing: 14) {
                        Picker("Connection", selection: $mode) {
                            ForEach(ConnectMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding(6)
                        .glassEffect(.regular, in: .capsule)

                        if mode == .privateNet { privateCard } else { publicCard }
                        accessCard
                    }
                }
                .padding(.horizontal, 16)

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular.tint(Color.red.opacity(0.25)), in: .rect(cornerRadius: 16))
                        .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 40)
            .readableWidth(560)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            guard let a = app.address else { return }
            mode = a.mode
            if a.mode == .privateNet {
                host = a.base.host ?? ""
                if let p = a.base.port { port = String(p); portTo = String(p) }
            } else {
                publicURL = a.base.absoluteString
            }
        }
    }

    // private: IP + port (required), or scan
    private var privateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Same Wi-Fi as your computer", systemImage: "wifi").font(.headline)
            Text("Enter the computer's IP and the port Gollama's network server uses, or scan to find it.")
                .font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                field("IP address", text: $host, focus: .host, keyboard: .numbersAndPunctuation)
                field("Port", text: $port, focus: .port).frame(width: 96)
            }
            HStack(spacing: 10) {
                Text("Scan ports up to").font(.footnote).foregroundStyle(.secondary)
                field("Port", text: $portTo, focus: .portTo).frame(width: 96)
                Spacer()
            }
            Button { scanning ? cancelScan() : startScan() } label: {
                HStack { if scanning { ProgressView() }; Text(scanning ? "Stop scanning" : "Scan network") }.frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass).controlSize(.large)
            if scanning { ProgressView(value: progress).tint(Pal.blue) }
            ForEach(found) { f in
                Button {
                    host = f.host; port = String(f.port); portTo = port
                    if f.needsCode { focus = .code } else { connect() }
                } label: {
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
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    // public: a URL (server on the internet or a Cloudflare Tunnel), port optional
    private var publicCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Server or tunnel URL", systemImage: "globe").font(.headline)
            Text("Works with a public Gollama server or a Cloudflare Tunnel, for example https://name.trycloudflare.com.")
                .font(.footnote).foregroundStyle(.secondary)
            field("https://your-server.example.com", text: $publicURL, focus: .url, keyboard: .URL)
            Toggle("Use a port", isOn: $usePort.animation()).tint(Pal.blue)
            if usePort { field("Port (e.g. 8765)", text: $publicPort, focus: .publicPort) }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private var accessCard: some View {
        VStack(spacing: 12) {
            field("Access code (if the server has one)", text: $code, focus: .code, secure: true)
            Button { connect() } label: {
                HStack { if connecting { ProgressView().tint(.white) }; Text("Connect") }.frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent).tint(Pal.green).controlSize(.large)
            .disabled(connecting)
        }
        .padding(18).frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    @ViewBuilder private func field(_ title: String, text: Binding<String>, focus f: Field, keyboard: UIKeyboardType = .numberPad, secure: Bool = false) -> some View {
        Group {
            if secure { SecureField(title, text: text) } else { TextField(title, text: text).keyboardType(keyboard) }
        }
        .focused($focus, equals: f)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .padding(.horizontal, 16)
        .frame(height: 44)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func makeBase() -> URL? {
        switch mode {
        case .privateNet:
            var h = host.trimmed
            h = h.replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "https://", with: "")
            while h.hasSuffix("/") { h.removeLast() }
            guard !h.isEmpty else { error = "Enter the IP address of the computer running Gollama."; return nil }
            guard let p = Int(port.trimmed), (1...65535).contains(p) else { error = "Private connections need a port (Gollama's default is 8765)."; return nil }
            guard let u = URL(string: "http://\(h):\(p)") else { error = "That IP address doesn't look right."; return nil }
            return u
        case .publicNet:
            var p: Int?
            if usePort {
                guard let n = Int(publicPort.trimmed), (1...65535).contains(n) else { error = "Enter a valid port, or turn \"Use a port\" off."; return nil }
                p = n
            }
            guard let u = Self.publicURL(from: publicURL, port: p) else { error = "That doesn't look like a valid URL. Try https://your-server.example.com"; return nil }
            return u
        }
    }

    static func publicURL(from raw: String, port: Int?) -> URL? {
        var s = raw.trimmed
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        guard var c = URLComponents(string: s), let scheme = c.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = c.host, host.contains(".") || host == "localhost" else { return nil }
        c.scheme = scheme
        c.path = ""
        c.query = nil
        c.fragment = nil
        c.user = nil
        c.password = nil
        if let port { c.port = port }
        return c.url
    }

    private func connect() {
        error = nil
        focus = nil
        guard let base = makeBase() else { return }
        connecting = true
        let m = mode
        let c = code
        Task {
            defer { connecting = false }
            do { try await app.connect(base: base, mode: m, code: c) }
            catch { self.error = error.localizedDescription }
        }
    }

    private func cancelScan() { scanTask?.cancel(); scanning = false }

    private func startScan() {
        error = nil
        found = []
        focus = nil
        guard let me = localIPv4() else { error = "Couldn't read this device's Wi-Fi address. Join a Wi-Fi network, or enter the IP manually."; return }
        let lo = max(1, Int(port.trimmed) ?? 8765)
        let hi = min(65535, max(lo, Int(portTo.trimmed) ?? lo), lo + 199)
        let prefix = me.split(separator: ".").prefix(3).joined(separator: ".")
        let targets = (1...254).flatMap { h in (lo...hi).map { ("\(prefix).\(h)", $0) } }
        scanning = true
        scannedOnce = true
        progress = 0
        scanTask = Task {
            var done = 0
            let batch = 120
            for start in stride(from: 0, to: targets.count, by: batch) {
                if Task.isCancelled { break }
                let slice = targets[start..<min(start + batch, targets.count)]
                let hits = await withTaskGroup(of: Found?.self) { group -> [Found] in
                    for (h, p) in slice {
                        group.addTask {
                            guard let u = URL(string: "http://\(h):\(p)") else { return nil }
                            if case .gollama(let needs) = await GollamaClient.probe(base: u) { return Found(host: h, port: p, needsCode: needs) }
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

// MARK: - Search tab

struct SearchField: View {
    @Binding var text: String
    var placeholder: String
    var height: CGFloat = 44
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
        .padding(.horizontal, 16)
        .frame(height: height)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

struct SearchRoot: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        Group {
            if app.started { ResultsScreen() } else { HomeScreen() }
        }
        .animation(.smooth(duration: 0.25), value: app.started)
        .background(AmbientBackground())
    }
}

struct HomeScreen: View {
    @Environment(AppModel.self) private var app
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    HStack { Spacer(); ServerMenu() }.padding(.horizontal, 16).padding(.top, 6)
                    Spacer(minLength: 30)
                    GollamaLogo(size: 64).padding(.bottom, 24)
                    SearchField(text: $text, placeholder: "Search or ask anything", height: 52, focused: $focused) { app.submit(text) }
                        .padding(.horizontal, 20)
                    HStack(spacing: 12) {
                        Button("Gollama Search") { app.submit(text) }.buttonStyle(.glass)
                        Button {
                            let t = text.trimmed
                            app.mainTab = .mode
                            if !t.isEmpty { text = ""; Task { await app.sendMode(t) } }
                        } label: { Label("Ask AI Mode", systemImage: "sparkles") }
                            .buttonStyle(.glassProminent).tint(Pal.purple)
                    }
                    .controlSize(.large)
                    .padding(.top, 22)

                    if !app.recents.isEmpty || !app.suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            if !app.recents.isEmpty {
                                Text("Recent").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                                FlowLayout(spacing: 8) {
                                    ForEach(app.recents, id: \.self) { r in
                                        Button { text = r; app.submit(r) } label: {
                                            Label(r, systemImage: "clock").font(.subheadline).lineLimit(1)
                                                .padding(.horizontal, 12).padding(.vertical, 8)
                                                .glassEffect(.regular.interactive(), in: .capsule)
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                            if !app.suggestions.isEmpty {
                                Text("Try").font(.footnote.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 6)
                                FlowLayout(spacing: 8) {
                                    ForEach(app.suggestions.prefix(6)) { s in
                                        Button { text = s.send; app.submit(s.send) } label: {
                                            Label(s.title, systemImage: "sparkle").font(.subheadline).lineLimit(1)
                                                .padding(.horizontal, 12).padding(.vertical, 8)
                                                .glassEffect(.regular.interactive(), in: .capsule)
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 24).padding(.top, 30).readableWidth(640)
                    }
                    Spacer(minLength: 60)
                }
                .frame(minHeight: geo.size.height)
                .readableWidth(720)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

struct ResultsScreen: View {
    @Environment(AppModel.self) private var app
    @State private var text = ""
    @FocusState private var focused: Bool
    @Namespace private var ns

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch app.searchTab {
                case .all: AllTab()
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
                SearchField(text: $text, placeholder: "Search", height: 44, focused: $focused) { app.submit(text) }
                ServerMenu()
            }
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(SearchTab.allCases) { t in
                        Button { withAnimation(.bouncy) { app.select(t) } } label: {
                            Text(t.rawValue)
                                .font(.subheadline.weight(app.searchTab == t ? .semibold : .regular))
                                .padding(.horizontal, 16).padding(.vertical, 9)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(app.searchTab == t ? Pal.blue : .secondary)
                        .glassEffect(app.searchTab == t ? .regular.tint(Pal.blue.opacity(0.25)).interactive() : .regular.interactive(), in: .capsule)
                        .glassEffectID(t.id, in: ns)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .readableWidth(900)
    }
}

struct Favicon: View {
    let site: String
    var body: some View {
        AsyncImage(url: URL(string: "https://www.google.com/s2/favicons?domain=\(site)&sz=64")) { p in
            if let i = p.image {
                i.resizable().scaledToFit().padding(6)
            } else {
                Text(String(site.first ?? "•").uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 30, height: 30)
        .glassEffect(.regular, in: .circle)
        .clipShape(Circle())
    }
}

struct HitRow: View {
    let hit: Hit
    @Environment(\.openURL) private var openURL
    var body: some View {
        Button { if let u = URL(string: hit.url) { openURL(u) } } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Favicon(site: hit.site)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(hit.site).font(.footnote.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                        Text(hit.url).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                Text(hit.title).font(.headline).foregroundStyle(Pal.blue).multilineTextAlignment(.leading)
                if !hit.snippet.isEmpty {
                    Text(hit.snippet).font(.subheadline).foregroundStyle(.secondary).lineLimit(3).multilineTextAlignment(.leading)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
            .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let u = URL(string: hit.url) { ShareLink(item: u) }
            Button("Copy link", systemImage: "doc.on.doc") { UIPasteboard.general.string = hit.url }
        }
    }
}

struct AllTab: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if let c = app.corrected {
                    VStack(alignment: .leading, spacing: 3) {
                        (Text("Showing results for ").foregroundStyle(.secondary) + Text(c).foregroundStyle(Pal.blue).fontWeight(.medium))
                        Button { app.submit(app.original, nocorrect: true) } label: {
                            Text("Search instead for \(app.original)").font(.footnote).foregroundStyle(Pal.blue)
                        }
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 4)
                }
                OverviewCard()
                if app.searching && app.results.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding(.top, 30)
                }
                if let e = app.searchError, app.results.isEmpty, !app.searching {
                    Text(e).foregroundStyle(.secondary).padding()
                }
                ForEach(app.results) { h in HitRow(hit: h) }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 30)
            .readableWidth(760)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - AI Overview (no stop button: it's an overview)

struct OverviewCard: View {
    @Environment(AppModel.self) private var app
    @State private var followUp = ""
    @State private var contentH: CGFloat = 0
    @FocusState private var focused: Bool
    private let cap: CGFloat = 250

    var body: some View {
        let ov = app.overview
        if ov.status.isEmpty && ov.text.isEmpty && ov.error == nil && ov.steps.isEmpty && !app.searching {
            EmptyView()
        } else {
            card(ov)
        }
    }

    private func card(_ ov: Overview) -> some View {
        let overflow = contentH > cap + 6
        let clamped = overflow && !ov.expanded
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Spark(size: 20)
                Text("AI Overview").font(.title3.weight(.medium))
                Spacer()
                if !app.modelName.isEmpty {
                    Text(app.modelName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 3).glassEffect(.regular, in: .capsule)
                }
            }
            if !ov.status.isEmpty { HStack(spacing: 8) { ThinkingDots(); Text(ov.status).font(.footnote).foregroundStyle(.secondary) } }
            if !ov.steps.isEmpty || !ov.think.isEmpty {
                DisclosureGroup("Show thinking") {
                    Text((ov.steps + [ov.think]).filter { !$0.isEmpty }.joined(separator: "\n"))
                        .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.footnote).tint(.secondary)
            }
            if let e = ov.error { Text(e).foregroundStyle(.red).font(.subheadline) }

            if !ov.text.isEmpty {
                // capped as soon as it's taller than the cap, even while it is still being written
                AnswerText(text: ov.text, sources: ov.sources.isEmpty ? app.results : ov.sources, streaming: !ov.done,
                           onSuggest: { app.continueInMode($0) })
                    .id(ov.id)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { g in
                        Color.clear.onChange(of: g.size.height, initial: true) { _, h in contentH = h }
                    })
                    .frame(height: clamped ? cap : contentH, alignment: .top)
                    .clipped()
                    .mask {
                        VStack(spacing: 0) {
                            Rectangle()
                            if clamped { LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 44) }
                        }
                    }
                    .animation(.smooth(duration: 0.3), value: ov.expanded)

                if overflow {
                    HStack(spacing: 10) {
                        Button { ov.expanded.toggle() } label: {
                            Label(ov.expanded ? "Show less" : "Show more", systemImage: ov.expanded ? "chevron.up" : "chevron.down").font(.footnote)
                        }
                        .buttonStyle(.glass).controlSize(.small)
                        if !ov.done { ThinkingDots() }
                        Spacer()
                    }
                }
            }

            if ov.done && ov.error == nil && !ov.text.isEmpty {
                HStack(spacing: 8) {
                    TextField("Ask a follow-up", text: $followUp).focused($focused).submitLabel(.send).onSubmit { send() }
                    SendButton(enabled: !followUp.trimmed.isEmpty, size: 30) { send() }
                }
                .padding(.leading, 16)
                .padding(.trailing, 7)
                .frame(height: 44)
                .glassEffect(.regular, in: .capsule)
                .padding(.top, 4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(Pal.purple.opacity(0.12)), in: .rect(cornerRadius: 26))
    }

    private func send() {
        let t = followUp.trimmed
        guard !t.isEmpty else { return }
        followUp = ""
        focused = false
        app.continueInMode(t)
    }
}

// MARK: - Images tab

struct ImagesTab: View {
    @Environment(AppModel.self) private var app
    @State private var selected: ImageItem?
    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 10)]

    var body: some View {
        ScrollView {
            if app.loadingImages { ProgressView().padding(.top, 40) }
            if let e = app.imagesError, app.images.isEmpty { Text(e).foregroundStyle(.secondary).padding() }
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(app.images) { img in
                    Button { selected = img } label: {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                AsyncImage(url: img.thumb) { p in
                                    switch p {
                                    case .success(let i): i.resizable().scaledToFill()
                                    case .failure: Image(systemName: "photo").foregroundStyle(.secondary)
                                    default: ProgressView()
                                    }
                                }
                            }
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .overlay(alignment: .bottomLeading) {
                                Text(img.source).font(.caption2).lineLimit(1)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .glassEffect(.regular, in: .capsule).padding(6)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 30)
            .readableWidth(900)
        }
        .sheet(item: $selected) { ImagePreview(item: $0) }
    }
}

struct ImagePreview: View {
    let item: ImageItem
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 16) {
            AsyncImage(url: item.full ?? item.thumb) { p in
                switch p {
                case .success(let i): i.resizable().scaledToFit()
                case .failure: Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
                default: ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            if !item.title.isEmpty { Text(item.title).font(.subheadline).multilineTextAlignment(.center) }
            HStack(spacing: 12) {
                Button { if let u = URL(string: item.page) { openURL(u) } } label: { Label("Visit page", systemImage: "safari") }
                    .buttonStyle(.glassProminent).tint(Pal.blue)
                if let u = item.full { ShareLink(item: u) { Label("Share", systemImage: "square.and.arrow.up") }.buttonStyle(.glass) }
                Button("Done") { dismiss() }.buttonStyle(.glass)
            }
        }
        .padding(20)
        .presentationDetents([.large])
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
                                .frame(width: 84, height: 84)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: .rect(cornerRadius: 22))
                        .contentShape(.rect(cornerRadius: 22))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 30)
            .readableWidth(760)
        }
    }
}

// MARK: - AI Mode tab (chat + history)

struct AIModeRoot: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var sidebarOpen = false
    @State private var dragX: CGFloat = 0
    @State private var draggingSidebar: Bool? = nil

    var body: some View {
        Group {
            if hSize == .regular {
                NavigationStack {
                    HStack(spacing: 0) {
                        HistoryList().frame(width: 300)
                        Divider()
                        ChatView()
                    }
                    .navigationTitle(app.chatTitle)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { trailingToolbar }
                }
            } else {
                GeometryReader { geo in
                    let sidebarW = min(geo.size.width * 0.82, 320)
                    let baseOffset: CGFloat = sidebarOpen ? sidebarW : 0
                    let offset = min(sidebarW, max(0, baseOffset + dragX))
                    let progress = sidebarW > 0 ? offset / sidebarW : 0

                    ZStack(alignment: .leading) {
                        HistoryList(onPick: { setSidebar(false) })
                            .frame(width: sidebarW)
                            .frame(maxHeight: .infinity)
                            .background(.ultraThinMaterial)
                            .overlay(alignment: .trailing) { Divider() }
                            .offset(x: offset - sidebarW)
                            .allowsHitTesting(offset > 0)

                        NavigationStack {
                            ChatView()
                                .navigationTitle(app.chatTitle)
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbar {
                                    ToolbarItem(placement: .topBarLeading) {
                                        Button {
                                            dismissKeyboard()
                                            setSidebar(!sidebarOpen)
                                        } label: {
                                            Image(systemName: "sidebar.left")
                                        }
                                    }
                                    trailingToolbar
                                }
                        }
                        .offset(x: offset)
                        .overlay {
                            if offset > 0 {
                                Color.black.opacity(0.28 * progress)
                                    .ignoresSafeArea()
                                    .offset(x: offset)
                                    .onTapGesture { setSidebar(false) }
                            }
                        }
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 20, coordinateSpace: .global)
                            .onChanged { v in
                                if draggingSidebar == nil {
                                    let dx = v.translation.width
                                    let dy = v.translation.height
                                    if abs(dx) > 14 && abs(dx) > abs(dy) * 1.4 {
                                        if (!sidebarOpen && dx > 0) || (sidebarOpen && dx < 0) {
                                            draggingSidebar = true
                                            dismissKeyboard()
                                        } else {
                                            draggingSidebar = false
                                        }
                                    } else if abs(dy) > 14 {
                                        draggingSidebar = false
                                    }
                                }
                                if draggingSidebar == true {
                                    dragX = v.translation.width
                                }
                            }
                            .onEnded { v in
                                defer {
                                    draggingSidebar = nil
                                    dragX = 0
                                }
                                guard draggingSidebar == true else { return }
                                let predicted = (sidebarOpen ? sidebarW : 0) + v.predictedEndTranslation.width
                                setSidebar(predicted > sidebarW * 0.45)
                            }
                    )
                    .onChange(of: sidebarOpen) { _, open in
                        if open { Task { await app.loadChats() } }
                    }
                }
            }
        }
        .background(AmbientBackground())
    }

    @ToolbarContentBuilder
    private var trailingToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { app.newChat() } label: { Image(systemName: "square.and.pencil") }
            Menu {
                if let a = app.address { Text(a.display) }
                if !app.modelName.isEmpty { Text("Model: \(app.modelName)") }
                Button("Disconnect", systemImage: "wifi.slash", role: .destructive) { app.disconnect() }
            } label: { Image(systemName: "ellipsis") }
        }
    }

    private func setSidebar(_ open: Bool) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            sidebarOpen = open
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

struct HistoryList: View {
    @Environment(AppModel.self) private var app
    var onPick: () -> Void = {}
    @State private var filter = ""
    @State private var confirmClear = false

    private var items: [ChatSummary] {
        let q = filter.trimmed.lowercased()
        return q.isEmpty ? app.chats : app.chats.filter { ($0.title + " " + $0.text).lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("History").font(.title3.weight(.semibold))
                Spacer()
                Button { app.newChat(); onPick() } label: { GlassIcon(name: "square.and.pencil", size: 38) }.buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search chats", text: $filter).autocorrectionDisabled()
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 16)

            if items.isEmpty {
                Spacer()
                Text(filter.isEmpty ? "No chats yet" : "No matching chats").foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(items) { c in
                        Button { Task { await app.openChat(c.id); onPick() } } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.title).lineLimit(1).foregroundStyle(.primary)
                                Text(Date(timeIntervalSince1970: c.updated / 1000).formatted(.relative(presentation: .named)))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .listRowBackground(c.id == app.chatId ? Pal.blue.opacity(0.18) : Color.clear)
                        .swipeActions {
                            Button(role: .destructive) { Task { await app.deleteChat(c.id) } } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

            if !app.chats.isEmpty {
                Button("Clear all history", role: .destructive) { confirmClear = true }
                    .font(.footnote)
                    .padding(.bottom, 10)
            }
        }
        .confirmationDialog("Delete every chat on this device?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) { Task { await app.clearChats() } }
        }
        .task { await app.loadChats() }
    }
}

struct ChatView: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if app.turns.isEmpty { EmptyChat() }
                    ForEach(app.turns) { t in TurnView(turn: t) }
                    Color.clear.frame(height: 8).id("end")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .readableWidth(760)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: app.turns.last?.answer) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: app.turns.count) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            .onChange(of: app.chatId) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            .safeAreaInset(edge: .bottom) {
                ChatInputBar()
                    .readableWidth(760)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
        }
    }
}

struct EmptyChat: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        VStack(spacing: 14) {
            Spark(size: 36)
            Text("Ask anything").font(.title2.weight(.medium))
            Text("AI Mode searches the web and answers with sources.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if !app.suggestions.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(app.suggestions.prefix(6)) { s in
                        Button { Task { await app.sendMode(s.send) } } label: {
                            Text(s.title).font(.subheadline).lineLimit(1)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .glassEffect(.regular.interactive(), in: .capsule)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

struct TurnView: View {
    @Environment(AppModel.self) private var app
    let turn: ModeTurn

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer(minLength: 40)
                VStack(alignment: .trailing, spacing: 6) {
                    if !turn.thumbs.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(Array(turn.thumbs.enumerated()), id: \.offset) { _, img in
                                Image(uiImage: img).resizable().scaledToFill()
                                    .frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                    if !turn.attNames.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(turn.attNames, id: \.self) { n in
                                Label(n, systemImage: "paperclip").font(.caption).lineLimit(1)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .glassEffect(.regular, in: .capsule)
                            }
                        }
                    }
                    Text(turn.text)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .glassEffect(.regular.tint(Pal.blue.opacity(0.3)), in: .rect(cornerRadius: 22))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                if !turn.status.isEmpty { HStack(spacing: 8) { ThinkingDots(); Text(turn.status).font(.footnote).foregroundStyle(.secondary) } }
                if !turn.steps.isEmpty || !turn.think.isEmpty {
                    DisclosureGroup("Show thinking") {
                        Text((turn.steps + [turn.think]).filter { !$0.isEmpty }.joined(separator: "\n"))
                            .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.footnote).tint(.secondary)
                }
                if !turn.answer.isEmpty {
                    AnswerText(text: turn.answer, sources: turn.sources, streaming: !turn.done,
                               onSuggest: { s in Task { await app.sendMode(s) } })
                }
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
                        HStack(spacing: 8) {
                            ForEach(Array(turn.sources.prefix(8).enumerated()), id: \.offset) { i, h in SourceChip(index: i + 1, hit: h) }
                        }
                    }
                }
                if turn.done && !turn.answer.isEmpty {
                    Button { UIPasteboard.general.string = turn.answer; app.flash("Copied") } label: {
                        Image(systemName: "doc.on.doc").font(.footnote).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 26))
        }
    }
}

struct SourceChip: View {
    let index: Int
    let hit: Hit
    @Environment(\.openURL) private var openURL
    var body: some View {
        Button { if let u = URL(string: hit.url) { openURL(u) } } label: {
            HStack(spacing: 5) {
                Text("\(index)").font(.caption2.weight(.bold)).foregroundStyle(Pal.blue)
                Text(hit.site).font(.caption).lineLimit(1).frame(maxWidth: 170)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chat input bar (text on top, controls underneath so the send button stays small)

struct ChatInputBar: View {
    @Environment(AppModel.self) private var app
    @State private var text = ""
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var photoItems: [PhotosPickerItem] = []
    @FocusState private var focused: Bool

    private static let fileTypes: [UTType] = [.plainText, .text, .json, .xml, .sourceCode, .commaSeparatedText, .html, .movie, .image]

    private var uploading: Bool { app.pending.contains { $0.state == "uploading" || $0.state == "processing" } }
    private var canSend: Bool { !uploading && (!text.trimmed.isEmpty || app.pending.contains { $0.state == "ready" }) }

    var body: some View {
        @Bindable var app = app
        VStack(alignment: .leading, spacing: 8) {
            if !app.pending.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(app.pending) { AttachChip(att: $0) } }
                }
            }
            TextField("Ask AI Mode", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.top, 2)

            HStack(spacing: 8) {
                Menu {
                    Button("Photos & Videos", systemImage: "photo.on.rectangle") { showPhotos = true }
                    Button("Files", systemImage: "doc") { showFiles = true }
                } label: {
                    Image(systemName: "plus").font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                        .frame(width: 32, height: 32).glassEffect(.regular.interactive(), in: .circle)
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)

                Menu {
                    Picker("Model", selection: $app.tier) {
                        Text("Fast").tag("fast")
                        Text("Pro").tag("pro")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(app.tier == "pro" ? "Pro" : "Fast")
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)

                Spacer()

                if app.modeBusy {
                    SendButton(systemName: "stop.fill", enabled: true, size: 32) { app.stopMode() }
                } else {
                    SendButton(enabled: canSend, size: 32) { send() }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .photosPicker(isPresented: $showPhotos, selection: $photoItems, maxSelectionCount: 4, matching: .any(of: [.images, .videos]))
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            let picked = items
            photoItems = []
            Task { for it in picked { await app.attach(photo: it) } }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: Self.fileTypes, allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            Task { for u in urls { await app.attach(file: u) } }
        }
    }

    private func send() {
        let t = text
        text = ""
        Task { await app.sendMode(t) }
    }
}

struct AttachChip: View {
    let att: Attachment
    @Environment(AppModel.self) private var app
    var body: some View {
        HStack(spacing: 8) {
            if let t = att.thumb {
                Image(uiImage: t).resizable().scaledToFill().frame(width: 30, height: 30).clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: att.kind == .video ? "film" : "doc.text").frame(width: 30, height: 30)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(att.name).font(.caption.weight(.medium)).lineLimit(1)
                if att.state == "uploading" || att.state == "processing" {
                    ProgressView(value: att.progress).frame(width: 90)
                    Text(att.message).font(.caption2).foregroundStyle(.secondary)
                } else if att.state == "error" {
                    Text(att.message).font(.caption2).foregroundStyle(.red).lineLimit(1)
                }
            }
            Button { app.remove(att) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 260)
        .glassEffect(.regular, in: .capsule)
    }
}