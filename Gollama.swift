// Gollama.swift
// Native SwiftUI client for Gollama Search with Liquid Glass (iOS 26+, iPhone + iPad, Xcode 26).
//
// SETUP
//  1. App target, deployment target iOS 26. This is the only file with @main.
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
import SafariServices
import WebKit
import AVKit
import AVFoundation
import NaturalLanguage

// MARK: - App

@main
struct GollamaApp: App {
    @State private var app = AppModel()
    init() { Storage.tidyOnLaunch() }
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

func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
/// Round glass icon used as a button label. The glass is NOT interactive on purpose: interactive glass inside a
/// button/menu label swallows the tap (same problem as SendButton), which left the sidebar's new-chat and
/// 3-dot buttons doing nothing.
struct GlassIcon: View {
    let name: String
    var size: CGFloat = 44
    var body: some View {
        Image(systemName: name)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .glassEffect(.regular, in: .circle)
            .contentShape(.circle)
    }
}

/// Small round send / stop button. The glass here is NOT interactive on purpose: interactive glass inside a
/// button label was swallowing the tap, which is why sending from the AI Mode bar did nothing.
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
                .background(Circle().fill(enabled ? Pal.blue : Color.gray.opacity(0.4)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(tr(systemName == "stop.fill" ? "Stop" : "Send"))
    }
}

/// Wraps chips onto several lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        let childProposal = maxW.isFinite ? ProposedViewSize(width: maxW, height: nil) : .unspecified
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        var w: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(childProposal)
            if x + sz.width > maxW && x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            w = max(w, min(maxW, x - spacing))
        }
        return CGSize(width: maxW.isFinite ? min(maxW, w) : w, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let childProposal = ProposedViewSize(width: bounds.width, height: nil)
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(childProposal)
            if x + sz.width > bounds.maxX && x > bounds.minX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            let clampedW = min(sz.width, bounds.width)
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: clampedW, height: sz.height))
            x += clampedW + spacing
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

struct BrowserItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct PlayerItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// One entry of the saved "thinking": k = "s" (a search step) or "r" (reasoning text). Same shape the web page saves.
struct ThinkEntry: Hashable {
    var k: String
    var t: String
}

struct VideoRef: Identifiable {
    let id: String          // the server's video id
    let name: String
    var url: URL?           // local copy, so it can be watched again
    var thumb: UIImage?
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
    var localURL: URL?
    init(kind: AttachKind, name: String) { self.kind = kind; self.name = name }
}

@Observable final class ModeTurn: Identifiable {
    let id: Int
    let text: String
    var answer = ""
    var status = ""
    var think: [ThinkEntry] = []
    var sources: [Hit] = []
    var done = false
    var error: String?
    var noResultsFor: String?
    var fb: String?
    var forced = false
    var attNames: [String] = []
    var thumbs: [UIImage] = []
    var imagesB64: [String] = []
    var imageNames: [String] = []
    var fileDicts: [[String: String]] = []
    var videos: [VideoRef] = []
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

/// Keeps uploaded videos on the phone so they can be watched again from the chat.
enum VideoStore {
    static var dir: URL {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("videos", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    // Chosen in Settings > Manage Storage (read straight from UserDefaults so this stays usable anywhere).
    static var enabled: Bool { UserDefaults.standard.object(forKey: "gollama.keepVideos") as? Bool ?? true }
    static var cap: Int64 { Int64(UserDefaults.standard.object(forKey: "gollama.videoCapMB") as? Int ?? 64) * 1024 * 1024 }
    static var maxAge: TimeInterval {
        let days = UserDefaults.standard.object(forKey: "gollama.videoDays") as? Int ?? 14
        return days <= 0 ? .infinity : TimeInterval(days) * 24 * 3600
    }

    static func save(_ src: URL, id: String) -> URL? {
        guard enabled else { return nil }
        let ext = src.pathExtension.isEmpty ? "mov" : src.pathExtension
        let dst = dir.appendingPathComponent("\(id).\(ext)")
        try? FileManager.default.removeItem(at: dst)
        guard (try? FileManager.default.copyItem(at: src, to: dst)) != nil else { return nil }
        prune(keeping: dst)
        return dst
    }

    /// Deletes expired videos, then the oldest ones until the folder fits under `cap`. `keeping` is never touched.
    static func prune(keeping: URL? = nil) {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys) else { return }
        var entries: [(url: URL, date: Date, size: Int64)] = files.map { f in
            let v = try? f.resourceValues(forKeys: Set(keys))
            return (f, v?.contentModificationDate ?? .distantPast, Int64(v?.fileSize ?? 0))
        }
        let now = Date()
        entries.removeAll { e in
            guard e.url != keeping, now.timeIntervalSince(e.date) > maxAge else { return false }
            try? fm.removeItem(at: e.url)
            return true
        }
        let limit = cap
        var total = entries.reduce(Int64(0)) { $0 + $1.size }
        for e in entries.sorted(by: { $0.date < $1.date }) where total > limit && e.url != keeping {
            try? fm.removeItem(at: e.url)
            total -= e.size
        }
    }

    /// Removes a picked/imported video's temporary copy (never anything outside the temp folder).
    static func discardTemp(_ url: URL) {
        guard url.path.hasPrefix(FileManager.default.temporaryDirectory.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }
    static func cached(_ id: String) -> URL? {
        (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?.first { $0.deletingPathExtension().lastPathComponent == id }
    }
    static func thumbnail(_ url: URL) async -> UIImage? {
        let g = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        g.appliesPreferredTrackTransform = true
        g.maximumSize = CGSize(width: 480, height: 480)
        if let r = try? await g.image(at: .zero) { return UIImage(cgImage: r.image) }
        return nil
    }
}

/// Everything the app keeps on disk that can be rebuilt: saved videos, image/web caches and leftover temp files.
/// Never touched here: the login cookie (Library/Cookies) and the saved server address (UserDefaults), so you stay
/// signed in and your server-side chat history stays reachable.
enum Storage {
    private static var caches: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0] }
    private static var temp: URL { FileManager.default.temporaryDirectory }

    private static func bytes(in dir: URL) -> Int64 {
        guard let en = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in en {
            let v = try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if v?.isRegularFile == true { total += Int64(v?.totalFileAllocatedSize ?? 0) }
        }
        return total
    }

    static func videoBytes() -> Int64 { bytes(in: VideoStore.dir) }
    /// Image/web caches plus temp files (everything except the saved videos).
    static func cacheBytes() -> Int64 { max(0, bytes(in: caches) - videoBytes()) + bytes(in: temp) }
    static func size() -> Int64 { bytes(in: caches) + bytes(in: temp) }

    private static func empty(_ dir: URL, except keep: String? = nil) {
        let fm = FileManager.default
        for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] where f.lastPathComponent != keep {
            try? fm.removeItem(at: f)
        }
    }

    private static func clearWebCaches() {
        let types: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeOfflineWebApplicationCache, WKWebsiteDataTypeFetchCache]
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {}
    }

    /// Applies the image cache limit from Settings (0 = no image cache at all).
    static func applyImageCacheLimit() {
        let mb = UserDefaults.standard.object(forKey: "gollama.imageCacheMB") as? Int ?? 12
        URLCache.shared = URLCache(memoryCapacity: mb == 0 ? 0 : 8 << 20, diskCapacity: mb << 20)
    }

    /// Runs on every launch: image cache limit, no stale temp copies, saved videos trimmed, old web caches dropped.
    static func tidyOnLaunch() {
        applyImageCacheLimit()
        empty(temp)
        VideoStore.prune()
        clearWebCaches()
    }

    /// Image/web caches and temp files. Saved videos are left alone.
    static func clearCache() {
        URLCache.shared.removeAllCachedResponses()
        clearWebCaches()
        empty(temp)
        empty(caches, except: VideoStore.dir.lastPathComponent)
    }

    static func clearVideos() { empty(VideoStore.dir) }
}

// MARK: - Regex helpers

func rxs(_ pattern: String, _ s: String, _ template: String, _ opts: NSRegularExpression.Options = []) -> String {
    guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { return s }
    return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
}

/// Replaces every match with `f(group 1)`.
func rxMap(_ pattern: String, _ s: String, _ opts: NSRegularExpression.Options = [], _ f: (String) -> String) -> String {
    guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { return s }
    let ns = s as NSString
    var out = ""
    var last = 0
    for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
        out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
        let r = m.range(at: 1)
        out += r.location == NSNotFound ? "" : f(ns.substring(with: r))
        last = m.range.location + m.range.length
    }
    return out + ns.substring(from: last)
}

// MARK: - LaTeX -> readable Unicode (used for inline formulas, copy and read-aloud; block formulas get real KaTeX)

enum TeX {
    static let symbols: [String: String] = [
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "varepsilon": "ε", "zeta": "ζ", "eta": "η",
        "theta": "θ", "vartheta": "ϑ", "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "pi": "π",
        "varpi": "ϖ", "rho": "ρ", "varrho": "ϱ", "sigma": "σ", "varsigma": "ς", "tau": "τ", "upsilon": "υ", "phi": "φ",
        "varphi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ", "Pi": "Π", "Sigma": "Σ", "Upsilon": "Υ",
        "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
        "times": "×", "cdot": "·", "div": "÷", "pm": "±", "mp": "∓", "ast": "∗", "star": "⋆", "circ": "∘", "bullet": "•",
        "oplus": "⊕", "otimes": "⊗",
        "leq": "≤", "le": "≤", "geq": "≥", "ge": "≥", "neq": "≠", "ne": "≠", "approx": "≈", "equiv": "≡", "sim": "∼",
        "simeq": "≃", "cong": "≅", "propto": "∝", "ll": "≪", "gg": "≫",
        "infty": "∞", "partial": "∂", "nabla": "∇", "forall": "∀", "exists": "∃", "nexists": "∄", "emptyset": "∅",
        "varnothing": "∅", "in": "∈", "notin": "∉", "ni": "∋", "subset": "⊂", "supset": "⊃", "subseteq": "⊆",
        "supseteq": "⊇", "cup": "∪", "cap": "∩", "setminus": "∖", "land": "∧", "wedge": "∧", "lor": "∨", "vee": "∨",
        "lnot": "¬", "neg": "¬",
        "sum": "∑", "prod": "∏", "int": "∫", "iint": "∬", "iiint": "∭", "oint": "∮", "coprod": "∐",
        "to": "→", "rightarrow": "→", "leftarrow": "←", "leftrightarrow": "↔", "Rightarrow": "⇒", "Leftarrow": "⇐",
        "Leftrightarrow": "⇔", "implies": "⟹", "iff": "⟺", "mapsto": "↦", "uparrow": "↑", "downarrow": "↓",
        "longrightarrow": "⟶",
        "ldots": "…", "cdots": "⋯", "dots": "…", "vdots": "⋮", "ddots": "⋱", "degree": "°", "angle": "∠", "perp": "⊥",
        "parallel": "∥", "therefore": "∴", "because": "∵", "prime": "′", "hbar": "ℏ", "ell": "ℓ", "Re": "ℜ", "Im": "ℑ",
        "aleph": "ℵ", "mid": "|", "lvert": "|", "rvert": "|", "langle": "⟨", "rangle": "⟩", "lfloor": "⌊", "rfloor": "⌋",
        "lceil": "⌈", "rceil": "⌉", "quad": "  ", "qquad": "    ", "dagger": "†", "ddagger": "‡",
        "sin": "sin", "cos": "cos", "tan": "tan", "cot": "cot", "sec": "sec", "csc": "csc", "arcsin": "arcsin",
        "arccos": "arccos", "arctan": "arctan", "sinh": "sinh", "cosh": "cosh", "tanh": "tanh", "log": "log", "ln": "ln",
        "lg": "lg", "exp": "exp", "lim": "lim", "max": "max", "min": "min", "sup": "sup", "inf": "inf", "det": "det",
        "dim": "dim", "gcd": "gcd", "deg": "deg", "arg": "arg", "Pr": "Pr", "mod": "mod", "bmod": "mod", "hline": ""
    ]
    private static let supMap: [Character: Character] = Dictionary(uniqueKeysWithValues: zip(Array("0123456789+-=()ni"), Array("⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾ⁿⁱ")))
    private static let subMap: [Character: Character] = Dictionary(uniqueKeysWithValues: zip(Array("0123456789+-=()aeoxhklmnpst"), Array("₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎ₐₑₒₓₕₖₗₘₙₚₛₜ")))

    static func unicode(_ tex: String) -> String {
        let c = Array(tex)
        var i = 0
        let s = parse(c, &i, stopAtBrace: false)
        return s.replacingOccurrences(of: "  ", with: " ").trimmed
    }

    private static func parse(_ c: [Character], _ i: inout Int, stopAtBrace: Bool) -> String {
        var out = ""
        while i < c.count {
            let ch = c[i]
            if ch == "}" && stopAtBrace { return out }
            if ch == "}" { i += 1; continue }
            if ch == "{" {
                i += 1
                out += parse(c, &i, stopAtBrace: true)
                if i < c.count { i += 1 }
                continue
            }
            if ch == "\\" {
                i += 1
                guard i < c.count else { break }
                if !c[i].isLetter {
                    let n = c[i]
                    i += 1
                    switch n {
                    case ",", ";", ":": out += " "
                    case "!": break
                    case "\\": out += "; "
                    case "|": out += "‖"
                    default: out.append(n)
                    }
                    continue
                }
                var name = ""
                while i < c.count, c[i].isLetter { name.append(c[i]); i += 1 }
                out += command(name, c, &i)
                continue
            }
            if ch == "^" || ch == "_" {
                i += 1
                let arg = readArg(c, &i)
                out += script(arg, sup: ch == "^")
                continue
            }
            if ch == "&" || ch == "~" { out += " "; i += 1; continue }
            out.append(ch)
            i += 1
        }
        return out
    }

    private static func readArg(_ c: [Character], _ i: inout Int) -> String {
        while i < c.count, c[i] == " " { i += 1 }
        guard i < c.count else { return "" }
        if c[i] == "{" {
            i += 1
            let r = parse(c, &i, stopAtBrace: true)
            if i < c.count { i += 1 }
            return r
        }
        if c[i] == "\\" {
            i += 1
            var name = ""
            while i < c.count, c[i].isLetter { name.append(c[i]); i += 1 }
            return command(name, c, &i)
        }
        let ch = c[i]
        i += 1
        return String(ch)
    }

    private static func paren(_ s: String) -> String {
        s.count <= 1 || s.allSatisfy({ $0.isLetter || $0.isNumber }) ? s : "(\(s))"
    }

    private static func command(_ name: String, _ c: [Character], _ i: inout Int) -> String {
        switch name {
        case "frac", "dfrac", "tfrac", "cfrac":
            let a = readArg(c, &i)
            let b = readArg(c, &i)
            return paren(a) + "/" + paren(b)
        case "binom":
            let a = readArg(c, &i)
            let b = readArg(c, &i)
            return "C(\(a), \(b))"
        case "sqrt":
            if i < c.count, c[i] == "[" {
                while i < c.count, c[i] != "]" { i += 1 }
                i += 1
            }
            return "√" + paren(readArg(c, &i))
        case "text", "mathrm", "mathbf", "mathit", "operatorname", "mathbb", "mathcal", "mathsf", "mathtt", "textbf", "textit", "boldsymbol", "bf", "rm":
            return readArg(c, &i)
        case "left", "right", "big", "Big", "bigg", "Bigg":
            if i < c.count, c[i] == "." { i += 1 }
            return ""
        case "begin", "end":
            _ = readArg(c, &i)
            return ""
        case "overline", "bar": return readArg(c, &i) + "\u{0304}"
        case "vec": return readArg(c, &i) + "\u{20D7}"
        case "hat": return readArg(c, &i) + "\u{0302}"
        case "tilde": return readArg(c, &i) + "\u{0303}"
        case "dot": return readArg(c, &i) + "\u{0307}"
        case "displaystyle", "textstyle", "limits", "nolimits", "label", "nonumber", "notag": return ""
        default: return symbols[name] ?? name
        }
    }

    private static func script(_ s: String, sup: Bool) -> String {
        let map = sup ? supMap : subMap
        var out = ""
        for ch in s {
            guard let m = map[ch] else { return (sup ? "^" : "_") + (s.count > 1 ? "(\(s))" : s) }
            out.append(m)
        }
        return out
    }
}

// MARK: - Cleaning answer text (for copy and read-aloud)

enum TextClean {
    /// Tags and citations removed, Markdown kept.
    static func copyText(_ raw: String) -> String {
        var s = raw
        s = rxs(#"\[\s*(\[{2,3}\s*(?:suggest(?:ion)?|ask|say|reply)\s*:[^\]]*\]{2,3})\s*\]"#, s, "$1", [.caseInsensitive])
        s = rxs(#"\[{2,3}\s*(?:suggest(?:ion)?|ask|say|reply)\s*:\s*([^\]|]*)(?:\|[^\]]*)?\]{2,3}"#, s, "$1", [.caseInsensitive])
        s = rxs(#"\[{2,3}\s*(?:hl|highlight|key)\s*:\s*([^\]]*)\]{2,3}"#, s, "$1", [.caseInsensitive])
        s = rxs(#"\[\[[^\]]*\]\]"#, s, "")
        s = rxs(#"\s?\[[\d\s,\[\]]*\d[\d\s,\[\]]*\]"#, s, "")
        return s.trimmed
    }

    /// What a voice should say: no code, no symbols, formulas turned into words.
    static func spoken(_ raw: String) -> String {
        var s = copyText(raw).replacingOccurrences(of: "\r\n", with: "\n")
        s = rxs(#"```[\s\S]*?(```|$)"#, s, " ")
        s = rxMap(#"\$\$([\s\S]+?)\$\$"#, s) { TeX.unicode($0) }
        s = rxMap(#"\\\[([\s\S]+?)\\\]"#, s) { TeX.unicode($0) }
        s = rxMap(#"\\\(([\s\S]+?)\\\)"#, s) { TeX.unicode($0) }
        s = rxMap(#"(?<![\\\w$])\$([^\s$][^$\n]*?[^\s$])\$(?![\w$])"#, s) { TeX.unicode($0) }
        s = rxs(#"!\[[^\]]*\]\([^)]*\)"#, s, "")
        s = rxs(#"\[([^\]]+)\]\([^)]*\)"#, s, "$1")
        s = rxs(#"(?m)^\s{0,3}#{1,6}\s*"#, s, "")
        s = rxs(#"(?m)^\s*[-*+•]\s+"#, s, "")
        s = rxs(#"(?m)^\s*>\s?"#, s, "")
        s = rxs(#"(?m)^[ \t]*\|?[ \t:|-]+\|?[ \t]*$"#, s, "")
        s = s.replacingOccurrences(of: "|", with: ", ")
        for ch in ["**", "__", "~~", "==", "`", "*"] { s = s.replacingOccurrences(of: ch, with: "") }
        s = rxs(#"[ \t]+"#, s, " ")
        s = rxs(#"\n{2,}"#, s, "\n\n")
        return s.trimmed
    }
}

// MARK: - Text to speech (the device's own voices only; nothing goes through the Python server)

final class SpeechController: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var current: AVSpeechUtterance?
    var onFinish: (() -> Void)?

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String) {
        stop()
        let u = AVSpeechUtterance(string: text)
        u.voice = Self.voice(for: text)
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        current = u
        synth.speak(u)
    }

    func stop() {
        current = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    /// Picks the best installed voice for the language the text is written in.
    private static func voice(for text: String) -> AVSpeechSynthesisVoice? {
        let lang = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue ?? (Locale.current.language.languageCode?.identifier ?? "en")
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(lang) }
        if let best = voices.max(by: { $0.quality.rawValue < $1.quality.rawValue }) {
            let sameRegion = voices.filter { $0.quality == best.quality && $0.language == Locale.current.identifier.replacingOccurrences(of: "_", with: "-") }
            return sameRegion.first ?? best
        }
        return AVSpeechSynthesisVoice(language: Locale.current.identifier.replacingOccurrences(of: "_", with: "-"))
    }

    private func finished(_ u: AVSpeechUtterance) {
        DispatchQueue.main.async {
            guard u === self.current else { return }
            self.current = nil
            self.onFinish?()
        }
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { finished(u) }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { finished(u) }
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

    // chrome
    var mainTab: MainTab = .search
    var sidebarOpen = false
    var showSettings = false
    var browser: BrowserItem?
    var player: PlayerItem?
    var speakingKey: String?

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
    var editingId: Int?
    var editText = ""

    private var nextTurn = 1
    private var titled = false
    private var pollTask: Task<Void, Never>?
    private var overviewActive = false
    private var activeTurns = Set<Int>()
    private let speech = SpeechController()

    // MARK: links, sidebar, speech
    /// Web links open inside the app (SFSafariViewController) so you don't get kicked out; there's a button to open Safari instead.
    func open(_ url: URL) {
        if let s = url.scheme?.lowercased(), s == "http" || s == "https" { browser = BrowserItem(url: url) }
        else { UIApplication.shared.open(url) }
    }

    func openSidebar() {
        hideKeyboard()
        withAnimation(.smooth(duration: 0.32)) { sidebarOpen = true }
    }

    func closeSidebar() {
        withAnimation(.smooth(duration: 0.32)) { sidebarOpen = false }
    }

    func toggleSpeech(key: String, raw: String) {
        if speakingKey == key { speech.stop(); speakingKey = nil; return }
        let text = TextClean.spoken(raw)
        guard !text.isEmpty else { return }
        speech.onFinish = { [weak self] in Task { @MainActor in self?.speakingKey = nil } }
        speakingKey = key
        speech.speak(text)
    }

    func stopSpeech() { speech.stop(); speakingKey = nil }

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
        stopSpeech()
        let c = client
        Task { _ = try? await c?.call("stop"); _ = try? await c?.call("mode_stop") }
        connected = false
        client = nil
        started = false
        query = ""
        results = []
        overview = Overview()
        turns = []
        chats = []
        chatId = nil
        sidebarOpen = false
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
        if recents.count > 5 { recents = Array(recents.prefix(5)) }
        UserDefaults.standard.set(recents, forKey: "gollama.recents")
    }

    func removeRecent(_ q: String) {
        recents.removeAll { $0 == q }
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
        stopSpeech()
        turns = []
        chatId = nil
        chatTitle = "New chat"
        titled = false
        pending = []
        editingId = nil
    }

    func openChat(_ id: String) async {
        guard let c = client else { return }
        if modeBusy { stopMode() }
        stopSpeech()
        guard let d = try? await c.call("chat_get", [id]) as? [String: Any] else { return }
        chatId = id
        chatTitle = d["title"] as? String ?? "Chat"
        titled = true
        pending = []
        editingId = nil
        var loaded: [ModeTurn] = []
        for td in (d["turns"] as? [[String: Any]] ?? []) {
            let t = ModeTurn(id: nextTurn, text: td["text"] as? String ?? "")
            nextTurn += 1
            t.answer = td["buf"] as? String ?? ""
            t.sources = Hit.list(td["results"])
            t.done = true
            t.fb = td["fb"] as? String
            t.forced = td["forced"] as? Bool ?? false
            t.think = (td["think"] as? [[String: Any]] ?? []).compactMap { e in
                guard let text = e["t"] as? String else { return nil }
                return ThinkEntry(k: e["k"] as? String ?? "s", t: text)
            }
            if let att = td["att"] as? [String: Any] {
                var names = att["images"] as? [String] ?? []
                names += att["files"] as? [String] ?? []
                for v in (att["videos"] as? [[String: Any]] ?? []) {
                    let name = v["name"] as? String ?? "video"
                    if let vid = v["id"] as? String { t.videos.append(VideoRef(id: vid, name: name, url: VideoStore.cached(vid), thumb: nil)) }
                    else { names.append(name) }
                }
                t.attNames = names
            }
            loaded.append(t)
        }
        turns = loaded
        for t in loaded {
            for (i, v) in t.videos.enumerated() where v.url != nil {
                if let u = v.url { Task { t.videos[i].thumb = await VideoStore.thumbnail(u) } }
            }
        }
    }

    func deleteChat(_ id: String) async {
        _ = try? await client?.call("chat_delete", [id])
        if chatId == id { newChat() }
        await loadChats()
    }

    func clearChats() async {
        _ = try? await client?.call("chats_clear")
        try? FileManager.default.removeItem(at: VideoStore.dir)
        newChat()
        await loadChats()
    }

    private func newChatId() -> String {
        "c" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + String(Int.random(in: 0..<1296), radix: 36)
    }

    private func ensureChat() {
        if chatId == nil { chatId = newChatId() }
    }

    private func turnDict(_ t: ModeTurn) -> [String: Any] {
        let att: [String: Any] = [
            "images": t.imageNames,
            "files": t.fileDicts.compactMap { $0["name"] },
            "videos": t.videos.map { ["name": $0.name, "id": $0.id] }
        ]
        var d: [String: Any] = [
            "text": t.text, "query": t.text, "buf": t.answer, "status": "done",
            "results": t.sources.map { $0.asDict },
            "think": t.think.map { ["k": $0.k, "t": $0.t] },
            "att": att
        ]
        if let fb = t.fb { d["fb"] = fb }
        if t.forced { d["forced"] = true }
        return d
    }

    func saveChat() {
        guard client != nil, chatId != nil else { return }
        Task { await saveChatNow() }
    }

    private func saveChatNow() async {
        guard let c = client, let id = chatId else { return }
        let saved = turns.filter { $0.done && !$0.answer.isEmpty }.map { turnDict($0) }
        guard !saved.isEmpty else { return }
        let chat: [String: Any] = ["id": id, "title": chatTitle, "updated": Date().timeIntervalSince1970 * 1000, "turns": saved, "project": NSNull()]
        _ = try? await c.call("chat_save", [chat])
        await loadChats()
    }

    /// "Branch in new chat": copies the conversation up to this answer into a new chat and opens it.
    func branchChat(from t: ModeTurn) async {
        guard let c = client, let idx = turns.firstIndex(where: { $0.id == t.id }) else { return }
        await saveChatNow()
        let sub = turns[...idx].filter { $0.done && !$0.answer.isEmpty }.map { turnDict($0) }
        guard !sub.isEmpty else { return }
        let id = newChatId()
        let chat: [String: Any] = ["id": id, "title": chatTitle + " (branch)", "updated": Date().timeIntervalSince1970 * 1000, "turns": sub, "project": NSNull()]
        _ = try? await c.call("chat_save", [chat])
        await loadChats()
        await openChat(id)
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

    func sendMode(_ raw: String, force: Bool = false, reuse: ModeTurn? = nil, inherit: ModeTurn? = nil) async {
        guard let c = client else { return }
        if pending.contains(where: { $0.state == "uploading" || $0.state == "processing" }) { flash(tr("Wait for the attachment to finish.")); return }
        let text = raw.trimmed
        if reuse == nil && inherit == nil && text.isEmpty && pending.isEmpty { return }
        ensureChat()
        let turn: ModeTurn
        if let r = reuse {
            turn = r
            turn.noResultsFor = nil
            turn.answer = ""
            turn.done = false
            turn.forced = true
        } else {
            let ready = pending.filter { $0.state == "ready" }
            let hasVideo = ready.contains { $0.kind == .video }
            let hasImage = ready.contains { $0.kind == .image }
            let shown = text.isEmpty ? "Take a look at the attached " + (hasVideo ? "video" : hasImage ? "image" : "file") + "." : text
            turn = ModeTurn(id: nextTurn, text: shown)
            nextTurn += 1
            turn.forced = force
            if let src = inherit {
                turn.imagesB64 = src.imagesB64
                turn.imageNames = src.imageNames
                turn.thumbs = src.thumbs
                turn.fileDicts = src.fileDicts
                turn.videos = src.videos
                turn.attNames = src.attNames
            }
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
                    if let id = a.videoId { turn.videos.append(VideoRef(id: id, name: a.name, url: a.localURL, thumb: a.thumb)) }
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
            let vnote = t.videos.isEmpty ? "" : " [attached video: " + t.videos.map { $0.name }.joined(separator: ", ") + "]"
            var m: [String: Any] = ["role": "user", "content": t.text + vnote]
            if withImages.contains(t.id) { m["images"] = t.imagesB64 }
            history.append(m)
            history.append(["role": "assistant", "content": t.answer])
        }
        let attach: [String: Any] = [
            "images": turn.imagesB64, "image_names": turn.imageNames, "files": turn.fileDicts,
            "videos": turn.videos.map { $0.id }, "temp": false, "project": NSNull()
        ]
        activeTurns.insert(turn.id)
        do {
            try await c.call("mode_send", [turn.id, turn.text, history, force || turn.forced, tier, attach, thinkMode.map { $0 as Any } ?? NSNull()])
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

    // edit / retry (the turn and everything after it is replaced, like the website's "edit" and "try again")
    func beginEdit(_ t: ModeTurn) {
        guard !modeBusy else { return }
        editingId = t.id
        editText = t.text
    }

    func cancelEdit() { editingId = nil }

    func submitEdit(_ t: ModeTurn) {
        let v = editText.trimmed
        editingId = nil
        guard !v.isEmpty, v != t.text.trimmed else { return }
        replaceTurn(t, text: v, force: false)
    }

    func retry(_ t: ModeTurn, force: Bool) {
        guard !modeBusy else { return }
        replaceTurn(t, text: t.text, force: force)
    }

    private func replaceTurn(_ t: ModeTurn, text: String, force: Bool) {
        guard let i = turns.firstIndex(where: { $0.id == t.id }) else { return }
        stopSpeech()
        turns.removeSubrange(i...)
        Task { await sendMode(text, force: force, inherit: t) }
    }

    func setFeedback(_ t: ModeTurn, _ k: String) {
        t.fb = t.fb == k ? nil : k
        saveChat()
    }

    func copyAnswer(_ t: ModeTurn) {
        UIPasteboard.general.string = TextClean.copyText(t.answer)
        flash(tr("Copied"))
    }

    func copyMarkdown(_ t: ModeTurn) {
        UIPasteboard.general.string = t.answer
        flash(tr("Copied as Markdown"))
    }

    func copySources(_ t: ModeTurn) {
        UIPasteboard.general.string = t.sources.enumerated().map { "[\($0.offset + 1)] \($0.element.title) - \($0.element.url)" }.joined(separator: "\n")
        flash(tr("Sources copied"))
    }

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
            } else { flash(tr("Couldn't read that video.")) }
        } else if let data = try? await item.loadTransferable(type: Data.self) {
            addImage(data: data, name: "photo-\(pending.count + 1).jpg")
        } else { flash(tr("Couldn't read that photo.")) }
    }

    func attach(file url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let type = UTType(filenameExtension: url.pathExtension)
        if type?.conforms(to: .movie) == true {
            let dst = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
            if (try? FileManager.default.copyItem(at: url, to: dst)) != nil { await addVideo(url: dst, name: url.lastPathComponent) }
            else { flash(tr("Couldn't read that video.")) }
        } else if type?.conforms(to: .image) == true {
            if let d = try? Data(contentsOf: url) { addImage(data: d, name: url.lastPathComponent) }
        } else if let d = try? Data(contentsOf: url) {
            let head = d.prefix(60_000)
            var text: String?
            for cut in 0...3 where text == nil { text = String(data: head.dropLast(cut), encoding: .utf8) }
            guard let t = text else { flash(String(format: tr("%@ isn't a text file."), url.lastPathComponent)); return }
            let a = Attachment(kind: .file, name: url.lastPathComponent)
            a.text = String(t.prefix(20000))
            pending.append(a)
        }
    }

    func addVideo(url: URL, name: String) async {
        guard let c = client else { return }
        pending.removeAll { $0.kind == .video }
        let a = Attachment(kind: .video, name: name)
        a.state = "uploading"
        a.message = "Uploading…"
        a.localURL = url
        pending.append(a)
        Task { a.thumb = await VideoStore.thumbnail(url) }
        defer { if a.localURL != url { VideoStore.discardTemp(url) } }     // the picker's temporary copy isn't needed once saved
        func fail(_ m: String) { a.state = "error"; a.message = m }
        do {
            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
            let b = try await c.call("video_begin", [name, size, tier]) as? [String: Any]
            guard b?["ok"] as? Bool == true, let vid = b?["id"] as? String else { fail(b?["error"] as? String ?? "Upload failed."); return }
            a.videoId = vid
            if let kept = VideoStore.save(url, id: vid) { a.localURL = kept }     // so you can watch it again from the chat
            let fh = try FileHandle(forReadingFrom: a.localURL ?? url)
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
        if a.kind == .video, let id = a.videoId { Task { _ = try? await client?.call("video_discard", [id]) } }
        if a.kind == .video, let u = a.localURL, u.path.hasPrefix(VideoStore.dir.path) { try? FileManager.default.removeItem(at: u) }
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
            case "onModeStep": t.think.append(ThinkEntry(k: "s", t: s))
            case "onModeThink":
                if let last = t.think.last, last.k == "r" { t.think[t.think.count - 1].t += s }
                else { t.think.append(ThinkEntry(k: "r", t: s)) }
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

// MARK: - Answer rendering (Markdown, lists, tables, quotes, math, live HTML, highlights, follow-ups, citations)

/// Tags text that should get the rounded blue highlight behind it.
struct HighlightAttribute: TextAttribute {}

/// Draws the Google-style rounded highlight behind tagged text (per line, so wrapped highlights look right).
struct HighlightRenderer: TextRenderer {
    var color: Color
    var displayPadding = EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4)
    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        for line in layout {
            for run in line {
                if run[HighlightAttribute.self] != nil {
                    let r = run.typographicBounds.rect.insetBy(dx: -3, dy: -1)
                    ctx.fill(Path(roundedRect: r, cornerRadius: 6, style: .continuous), with: .color(color))
                }
                ctx.draw(run)
            }
        }
    }
}

struct ABlock: Identifiable {
    enum Kind { case para, heading, item, quote, table, rule, code, live, math, image }
    let id: Int
    var kind: Kind
    var level = 0
    var marker = ""
    var task: Bool?
    var text = Text("")
    var hasHL = false
    var cites: [Int] = []
    var raw = ""
    var lang = ""
    var open = false
    var cells: [[Text]] = []
}

enum AnswerParser {
    struct Draft {
        var kind: ABlock.Kind
        var level = 0
        var marker = ""
        var task: Bool?
        var raw = ""
        var lang = ""
        var open = false
        var rows: [[String]] = []
    }

    struct Parsed {
        var blocks: [ABlock] = []
        var sends: [String] = []
    }

    final class Ctx {
        var sends: [String] = []
        var labels: [String] = []
        var maths: [String] = []
        var hl = 0
        let sourceCount: Int
        init(_ n: Int) { sourceCount = n }
    }

    enum Part {
        case text(String)
        case code(info: String, body: String, open: Bool)
    }

    private static func rxc(_ p: String, _ o: NSRegularExpression.Options = []) -> NSRegularExpression {
        (try? NSRegularExpression(pattern: p, options: o)) ?? (try! NSRegularExpression(pattern: "(?!)"))
    }

    static let liveKinds: [String: String] = [
        "run.html": "html", "run-html": "html", "html.run": "html", "html-run": "html", "live.html": "html", "live-html": "html", "html-live": "html",
        "run.python": "python", "run.py": "python", "run-python": "python", "python.run": "python", "python-run": "python", "py.run": "python", "py-run": "python", "live-python": "python"
    ]

    private static let reUnclosedTag = rxc(#"\[\[(?!\s*(?:hl|highlight|key)\s*:)[^\]]*$"#, [.caseInsensitive])
    private static let reUnclosedSingle = rxc(#"\[\s*suggest(?:ion)?\s*:[^\]\[]*$"#, [.caseInsensitive])
    private static let reUnclosedCite = rxc(#"\[[\d\s,\[]*$"#)
    private static let reImageTag = rxc(#"\[image:\s*[^\]]{2,100}\]"#, [.caseInsensitive])
    private static let reWrapTag = rxc(#"\[\s*(\[{2,3}\s*(?:suggest(?:ion)?|ask|say|reply)\s*:[^\]]*\]{2,3})\s*\]"#, [.caseInsensitive])
    private static let reSugg = rxc(#"\[{2,3}\s*(?:suggest(?:ion)?|ask|say|reply)\s*:\s*([^\]]{2,500})\]{2,3}|\[\s*suggest(?:ion)?\s*:\s*([^\]\[]{2,500})\]"#, [.caseInsensitive])
    private static let reCodeSpan = rxc("`[^`\\n]*`")
    private static let reSpanBack = rxc("\u{E030}(\\d+)\u{E031}")
    private static let reDollar2 = rxc(#"\$\$([\s\S]+?)\$\$"#)
    private static let reBracket = rxc(#"\\\[([\s\S]+?)\\\]"#)
    private static let reBareBracket = rxc(#"^[ \t]*\[\s*((?:(?!\]\s*\()[^\[\]])*?\\[a-zA-Z](?:(?!\]\s*\()[^\[\]])*?)\s*\][ \t]*$"#, [.anchorsMatchLines])
    private static let reEnv = rxc(#"\\begin\{(equation\*?|align\*?|gather\*?|multline\*?|eqnarray\*?|aligned|cases|[pbBvV]?matrix|array)\}[\s\S]*?\\end\{\1\}"#)
    private static let reParen = rxc(#"\\\(([\s\S]+?)\\\)"#)
    private static let reInline = rxc(#"(^|[^\\$\w])\$([^\s$](?:(?:\\.|[^$\\\n])*?[^\s$\\])?)\$(?![\w$])"#)
    private static let reMathOpen = rxc(#"(\\\[|\$\$|\\begin\{(?:equation|align|gather|aligned|cases|[pbBvV]?matrix|array)\*?\})([\s\S]{0,800})$"#)
    private static let reHL = rxc(#"\[\[\s*(?:hl|highlight|key)\s*:\s*((?:[^\]\n]|\](?!\]))+?)\s*\]\]"#, [.caseInsensitive])
    private static let reEq = rxc(#"(^|[^=\w])==(?!\s)([^=\n]*?[^=\s])==(?![=\w])"#)
    private static let reHLOpen = rxc(#"\[\[\s*(?:hl|highlight|key)\s*:((?:[^\]\n]|\](?!\]))*)$"#, [.caseInsensitive])
    private static let reMathLine = rxc("^\u{E010}(\\d+)\u{E011}$")
    private static let reList = rxc(#"^([ \t]*)([-*+•]|\d{1,3}[.)])[ \t]+(.*)$"#)
    private static let reImageLine = rxc(#"^!\[([^\]]*)\]\((https?://[^)\s]+)[^)]*\)$"#)
    private static let reCite = rxc(#"\s?\[[\d\s,\[\]]*\d[\d\s,\[\]]*\]"#)
    private static let reReq = rxc(#"^(explain|tell|show|compare|describe|give|list|summari[sz]e|walk|help|write|make|create|find|what|how|why|who|when|where|which|can|could|do|does|is|are|should|would|let|look|dig|break|go|elaborate|expand|cover|outline|teach|suggest|recommend|draw|plot|calculate|solve|translate|provide|identify|discuss|analy[sz]e|review|simplify|define|demonstrate|illustrate|clarify|contrast|detail|focus|share|compile|check|try|convert|rewrite|dive)\b"#, [.caseInsensitive])

    // MARK: entry point
    static func parse(_ src: String, sourceCount: Int, fadeTail: Int) -> Parsed {
        let c = Ctx(sourceCount)
        var drafts: [Draft] = []
        for part in splitFences(src.replacingOccurrences(of: "\r\n", with: "\n")) {
            switch part {
            case .code(let info, let body, let open): drafts.append(codeDraft(info: info, body: body, open: open))
            case .text(let t): drafts += blockDrafts(transform(t, c), c)
            }
        }
        let textKinds: [ABlock.Kind] = [.para, .heading, .item, .quote]
        let lastText = drafts.lastIndex(where: { textKinds.contains($0.kind) })
        var out = Parsed()
        for (i, d) in drafts.enumerated() {
            var b = ABlock(id: i, kind: d.kind)
            b.level = d.level
            b.marker = d.marker
            b.task = d.task
            b.raw = d.raw
            b.lang = d.lang
            b.open = d.open
            switch d.kind {
            case .para, .heading, .item, .quote:
                let (clean, cites) = extractCites(d.raw, count: c.sourceCount)
                let arrow = !(d.kind == .item && clean.trimmingCharacters(in: .whitespaces).hasPrefix("\u{E020}"))
                let r = makeText(clean, c, fade: i == lastText ? fadeTail : 0, arrow: arrow)
                b.text = r.text
                b.hasHL = r.hl
                b.cites = cites
            case .table:
                b.cells = d.rows.map { row in row.map { makeText($0, c, fade: 0, arrow: true).text } }
            default:
                break
            }
            out.blocks.append(b)
        }
        out.sends = c.sends
        return out
    }

    // MARK: splitting code fences
    private static func splitFences(_ s: String) -> [Part] {
        var parts: [Part] = []
        var textBuf: [String] = []
        var codeBuf: [String] = []
        var info = ""
        var inCode = false
        for line in s.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") {
                if inCode {
                    parts.append(.code(info: info, body: codeBuf.joined(separator: "\n"), open: false))
                    codeBuf = []
                    inCode = false
                } else {
                    if !textBuf.isEmpty { parts.append(.text(textBuf.joined(separator: "\n"))); textBuf = [] }
                    info = String(t.dropFirst(3)).trimmed
                    inCode = true
                }
                continue
            }
            if inCode { codeBuf.append(line) } else { textBuf.append(line) }
        }
        if inCode { parts.append(.code(info: info, body: codeBuf.joined(separator: "\n"), open: true)) }
        else if !textBuf.isEmpty { parts.append(.text(textBuf.joined(separator: "\n"))) }
        return parts
    }

    private static func codeDraft(info: String, body: String, open: Bool) -> Draft {
        let words = info.lowercased().split(separator: " ").map(String.init)
        let first = words.first ?? ""
        var kind = liveKinds[first]
        if kind == nil, first.contains("run.html") || first.contains("live.html") {
            kind = "html"
        }
        if kind == nil, words.contains(where: { $0 == "live" || $0 == "run" }) {
            if first == "html" { kind = "html" } else if first == "python" || first == "py" { kind = "python" }
        }
        var d = Draft(kind: .code)
        d.raw = body
        d.open = open
        if kind == "html" { d.kind = .live; d.lang = "html" }
        else if kind == "python" { d.lang = "python"; d.marker = "run" }
        else { d.lang = first }
        return d
    }

    // MARK: tags, formulas and highlights -> placeholders
    private static func sub(_ re: NSRegularExpression, _ s: String, _ template: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
    }

    private static func grp(_ m: NSTextCheckingResult, _ ns: NSString, _ i: Int) -> String? {
        let r = m.range(at: i)
        return r.location == NSNotFound ? nil : ns.substring(with: r)
    }

    private static func replaceMatches(_ re: NSRegularExpression, in s: String, _ f: (NSTextCheckingResult, NSString) -> String) -> String {
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += f(m, ns)
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }

    private static func isAlone(_ ns: NSString, _ r: NSRange) -> Bool {
        let head = ns.substring(to: r.location).components(separatedBy: "\n").last ?? ""
        let tail = ns.substring(from: r.location + r.length).components(separatedBy: "\n").first ?? ""
        return head.trimmed.isEmpty && tail.trimmed.isEmpty
    }

    /// What pressing a follow-up sends (same rule as the website).
    static func sendFor(_ label: String) -> String {
        var t = label.trimmed
        while let l = t.last, " \t\n.!:–—-".contains(l) { t.removeLast() }
        guard !t.isEmpty else { return "" }
        let ns = t as NSString
        if reReq.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)) != nil { return t.prefix(1).uppercased() + t.dropFirst() }
        return "Tell me more about " + t
    }

    private static func transform(_ input: String, _ c: Ctx) -> String {
        var s = input
        // hide tags and formulas that are still being typed
        s = sub(reUnclosedTag, s, "")
        s = sub(reUnclosedSingle, s, "")
        s = sub(reUnclosedCite, s, "")
        s = sub(reImageTag, s, "")

        // follow-ups: [[suggest: ...]] (also suggestion / ask / say / reply, 2-3 brackets, wrapped or single-bracket)
        s = sub(reWrapTag, s, "$1")
        s = replaceMatches(reSugg, in: s) { m, ns in
            let body = grp(m, ns, 1) ?? grp(m, ns, 2) ?? ""
            let head = body.components(separatedBy: "|").first ?? body
            let label = String(head.replacingOccurrences(of: "*", with: "").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").prefix(140))
            if label.isEmpty { return "" }
            c.labels.append(label)
            c.sends.append(sendFor(label))
            return "\u{E020}\(c.labels.count - 1)\u{E021}"
        }

        // math, with inline code protected
        var spans: [String] = []
        s = replaceMatches(reCodeSpan, in: s) { m, ns in
            spans.append(ns.substring(with: m.range))
            return "\u{E030}\(spans.count - 1)\u{E031}"
        }
        func disp(_ m: NSTextCheckingResult, _ ns: NSString, _ g: Int) -> String {
            let tex = (g > 0 ? (grp(m, ns, g) ?? "") : ns.substring(with: m.range)).trimmed
            let own = isAlone(ns, m.range)
            c.maths.append(tex)
            let i = c.maths.count - 1
            return own ? "\u{E010}\(i)\u{E011}" : "\u{E012}\(i)\u{E013}"
        }
        s = replaceMatches(reDollar2, in: s) { m, ns in disp(m, ns, 1) }
        s = replaceMatches(reBracket, in: s) { m, ns in disp(m, ns, 1) }
        s = replaceMatches(reBareBracket, in: s) { m, ns in disp(m, ns, 1) }
        s = replaceMatches(reEnv, in: s) { m, ns in disp(m, ns, 0) }
        s = replaceMatches(reParen, in: s) { m, ns in
            c.maths.append((grp(m, ns, 1) ?? "").trimmed)
            return "\u{E012}\(c.maths.count - 1)\u{E013}"
        }
        s = replaceMatches(reInline, in: s) { m, ns in
            c.maths.append(grp(m, ns, 2) ?? "")
            return (grp(m, ns, 1) ?? "") + "\u{E012}\(c.maths.count - 1)\u{E013}"
        }
        s = replaceMatches(reMathOpen, in: s) { m, ns in      // a formula that is still streaming: hide it until it's closed
            let rest = grp(m, ns, 2) ?? ""
            return rest.range(of: #"\\[a-zA-Z]|[\^_{=]"#, options: .regularExpression) != nil ? "" : ns.substring(with: m.range)
        }
        s = replaceMatches(reSpanBack, in: s) { m, ns in
            guard let i = Int(grp(m, ns, 1) ?? ""), i < spans.count else { return "" }
            return spans[i]
        }

        // highlights: [[hl: x]] / [[highlight: x]] / [[key: x]] / ==x==  (at most 8)
        s = replaceMatches(reHL, in: s) { m, ns in
            let inner = grp(m, ns, 1) ?? ""
            c.hl += 1
            return (c.hl > 8 || inner.count > 500) ? inner : "\u{E000}\(inner)\u{E001}"
        }
        s = replaceMatches(reEq, in: s) { m, ns in
            let pre = grp(m, ns, 1) ?? ""
            let inner = grp(m, ns, 2) ?? ""
            c.hl += 1
            return pre + (c.hl > 8 ? inner : "\u{E000}\(inner)\u{E001}")
        }
        s = sub(reHLOpen, s, "\u{E000}$1")
        return s
    }

    // MARK: blocks
    private static func indentWidth(_ s: String) -> Int { s.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } }

    private static func isSeparator(_ line: String) -> Bool {
        let t = line.trimmed
        return t.contains("|") && t.contains("-") && t.range(of: #"^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?$"#, options: .regularExpression) != nil
    }

    private static func splitRow(_ line: String) -> [String] {
        var t = line.trimmed
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { $0.trimmed }
    }

    private static func pad(_ r: [String], _ n: Int) -> [String] {
        var x = r
        while x.count < n { x.append("") }
        return Array(x.prefix(n))
    }

    private static func blockDrafts(_ text: String, _ c: Ctx) -> [Draft] {
        var out: [Draft] = []
        var para: [String] = []
        var stack: [Int] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        func flush() {
            if !para.isEmpty {
                var d = Draft(kind: .para)
                d.raw = para.joined(separator: "\n")
                out.append(d)
                para = []
            }
        }
        while i < lines.count {
            let raw = lines[i]
            let t = raw.trimmingCharacters(in: .whitespaces)
            let tns = t as NSString
            if t.isEmpty { flush(); i += 1; continue }

            if let m = reMathLine.firstMatch(in: t, range: NSRange(location: 0, length: tns.length)) {
                flush()
                stack = []
                let idx = Int(tns.substring(with: m.range(at: 1))) ?? 0
                var d = Draft(kind: .math)
                d.raw = idx < c.maths.count ? c.maths[idx] : ""
                out.append(d)
                i += 1
                continue
            }
            if let r = t.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                flush()
                stack = []
                var d = Draft(kind: .heading)
                d.level = t.prefix(while: { $0 == "#" }).count
                d.raw = String(t[r.upperBound...])
                out.append(d)
                i += 1
                continue
            }
            if t.range(of: #"^(-{3,}|\*{3,}|_{3,})$"#, options: .regularExpression) != nil {
                flush()
                stack = []
                out.append(Draft(kind: .rule))
                i += 1
                continue
            }
            if let m = reImageLine.firstMatch(in: t, range: NSRange(location: 0, length: tns.length)) {
                flush()
                var d = Draft(kind: .image)
                d.raw = tns.substring(with: m.range(at: 2))
                d.lang = tns.substring(with: m.range(at: 1))
                out.append(d)
                i += 1
                continue
            }
            if t.contains("|"), i + 1 < lines.count, isSeparator(lines[i + 1]) {
                flush()
                stack = []
                var rows: [[String]] = [splitRow(t)]
                var j = i + 2
                while j < lines.count {
                    let tj = lines[j].trimmingCharacters(in: .whitespaces)
                    if tj.isEmpty || !tj.contains("|") { break }
                    rows.append(splitRow(tj))
                    j += 1
                }
                let n = rows[0].count
                var d = Draft(kind: .table)
                d.rows = rows.map { pad($0, n) }
                out.append(d)
                i = j
                continue
            }
            if t.hasPrefix(">") {
                flush()
                stack = []
                var q: [String] = []
                var j = i
                while j < lines.count {
                    let tj = lines[j].trimmingCharacters(in: .whitespaces)
                    guard tj.hasPrefix(">") else { break }
                    q.append(String(tj.dropFirst()).trimmingCharacters(in: .whitespaces))
                    j += 1
                }
                var d = Draft(kind: .quote)
                d.raw = q.joined(separator: "\n")
                out.append(d)
                i = j
                continue
            }
            let rns = raw as NSString
            if let m = reList.firstMatch(in: raw, range: NSRange(location: 0, length: rns.length)) {
                flush()
                let indent = indentWidth(rns.substring(with: m.range(at: 1)))
                let marker = rns.substring(with: m.range(at: 2))
                var body = rns.substring(with: m.range(at: 3))
                while let last = stack.last, last > indent { stack.removeLast() }
                if stack.last != indent { stack.append(indent) }
                var d = Draft(kind: .item)
                d.level = stack.count - 1
                d.marker = marker.first?.isNumber == true ? marker : ["•", "◦", "▪"][min(d.level, 2)]
                if body.hasPrefix("[ ] ") { d.task = false; body = String(body.dropFirst(4)) }
                else if body.lowercased().hasPrefix("[x] ") { d.task = true; body = String(body.dropFirst(4)) }
                d.raw = body
                out.append(d)
                i += 1
                continue
            }
            if !stack.isEmpty, para.isEmpty, indentWidth(String(raw.prefix(while: { $0 == " " || $0 == "\t" }))) > 0,
               let li = out.indices.last, out[li].kind == .item {
                out[li].raw += "\n" + t          // an indented line continues the list item above
                i += 1
                continue
            }
            stack = []
            para.append(t)
            i += 1
        }
        flush()
        return out
    }

    // MARK: inline
    private static func extractCites(_ raw: String, count: Int) -> (String, [Int]) {
        let ns = raw as NSString
        let ms = NSMutableString(string: raw)
        var cites: [Int] = []
        for m in reCite.matches(in: raw, range: NSRange(location: 0, length: ns.length)).reversed() {
            let nums = ns.substring(with: m.range).split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            if !nums.isEmpty && nums.allSatisfy({ $0 >= 1 && $0 <= count }) {
                cites.insert(contentsOf: nums, at: 0)
                ms.replaceCharacters(in: m.range, with: "")
            }
        }
        return (ms as String, cites)
    }

    private enum Seg {
        case plain(String)
        case hl(String)
        case sugg(Int, Bool)
        case math(Int)
    }

    private static func makeText(_ raw: String, _ c: Ctx, fade: Int, arrow: Bool) -> (text: Text, hl: Bool) {
        var segs: [Seg] = []
        var buf = ""
        var inHL = false
        var firstSugg = true
        let chars = Array(raw)
        var i = 0
        func flush() {
            if !buf.isEmpty { segs.append(inHL ? .hl(buf) : .plain(buf)); buf = "" }
        }
        func number(_ end: Character) -> Int? {
            var n = ""
            while i < chars.count, chars[i] != end { n.append(chars[i]); i += 1 }
            i += 1
            return Int(n)
        }
        while i < chars.count {
            let ch = chars[i]
            switch ch {
            case "\u{E000}": flush(); inHL = true; i += 1
            case "\u{E001}": flush(); inHL = false; i += 1
            case "\u{E020}":
                flush()
                i += 1
                if let n = number("\u{E021}") { segs.append(.sugg(n, arrow && firstSugg)); firstSugg = false }
            case "\u{E012}":
                flush()
                i += 1
                if let n = number("\u{E013}") { segs.append(.math(n)) }
            default:
                buf.append(ch)
                i += 1
            }
        }
        flush()

        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        func attr(_ s: String) -> AttributedString { (try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s) }

        var result = Text("")
        var hasHL = false
        let lastIdx = segs.count - 1
        for (k, seg) in segs.enumerated() {
            switch seg {
            case .plain(let s):
                var a = attr(s)
                if fade > 0 && k == lastIdx { fadeTail(&a, fade) }
                result = result + Text(a)
            case .hl(let s):
                var a = attr(s)
                a.foregroundColor = Pal.blue
                hasHL = true
                result = result + Text(a).fontWeight(.medium).customAttribute(HighlightAttribute())
            case .sugg(let n, let withArrow):
                if withArrow { result = result + Text(Image(systemName: "arrow.turn.down.right")).foregroundStyle(.secondary) + Text(" ") }
                var a = AttributedString(n < c.labels.count ? c.labels[n] : "")
                a.link = URL(string: "gsuggest://s\(n)")
                a.foregroundColor = Color.primary
                result = result + Text(a).bold().underline()
            case .math(let n):
                result = result + Text(n < c.maths.count ? TeX.unicode(c.maths[n]) : "")
            }
        }
        return (result, hasHL)
    }

    /// The newest characters fade in.
    private static func fadeTail(_ a: inout AttributedString, _ n: Int) {
        let total = a.characters.count
        for k in 0..<min(n, total) {
            let s0 = a.index(a.startIndex, offsetByCharacters: total - 1 - k)
            let e0 = a.index(s0, offsetByCharacters: 1)
            let alpha = 0.12 + 0.88 * Double(k) / Double(n)
            a[s0..<e0].foregroundColor = Color.primary.opacity(alpha)
        }
    }
}

// MARK: - Web views (interactive HTML blocks and KaTeX formulas)

final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) { target?.userContentController(c, didReceive: m) }
}

/// A WKWebView you can drop into the middle of the UI. The page reports its height through `window.webkit.messageHandlers.h`.
struct HTMLWebView: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat
    var scrolls = false
    var onLink: (URL) -> Void = { _ in }

    func makeCoordinator() -> Coord { Coord(self) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        cfg.userContentController.add(WeakScriptHandler(context.coordinator), name: "h")
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.isOpaque = false
        v.backgroundColor = .clear
        v.scrollView.backgroundColor = .clear
        v.scrollView.isScrollEnabled = scrolls
        v.scrollView.alwaysBounceVertical = false
        v.scrollView.isDirectionalLockEnabled = true
        v.scrollView.showsVerticalScrollIndicator = false
        v.navigationDelegate = context.coordinator
        context.coordinator.loaded = html
        v.loadHTMLString(html, baseURL: nil)
        return v
    }

    func updateUIView(_ v: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.loaded != html {
            context.coordinator.loaded = html
            v.loadHTMLString(html, baseURL: nil)
        }
    }

    static func dismantleUIView(_ v: WKWebView, coordinator: Coord) {
        v.configuration.userContentController.removeScriptMessageHandler(forName: "h")
    }

    final class Coord: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: HTMLWebView
        var loaded = ""
        init(_ p: HTMLWebView) { parent = p }

        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
            guard let n = (m.body as? NSNumber)?.doubleValue else { return }
            let h = CGFloat(n)
            if abs(h - parent.height) > 1 {
                DispatchQueue.main.async { self.parent.height = h }
            }
        }

        func webView(_ w: WKWebView, decidePolicyFor a: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if a.navigationType == .linkActivated, let u = a.request.url {
                parent.onLink(u)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

enum LiveHTML {
    static let csp = "default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval' https://cdnjs.cloudflare.com https://cdn.jsdelivr.net; style-src 'unsafe-inline' https://fonts.googleapis.com https://cdnjs.cloudflare.com; font-src data: https://fonts.gstatic.com https://cdnjs.cloudflare.com; img-src data: blob:; media-src data: blob:; connect-src 'none'; frame-src 'none'; form-action 'none'"

    /// Same sandbox idea as the website: scripts run, but the page can't make network requests or touch the app.
    static func page(_ code: String, dark: Bool) -> String {
        let fg = dark ? "#f2f2f7" : "#111111"
        let head = """
        <meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="\(csp)">
        <style>html,body{margin:0;padding:0}body{padding:10px;font:15px/1.5 -apple-system,system-ui,sans-serif;color:\(fg);background:transparent;color-scheme:light dark}</style>
        <script>(function(){function s(){try{window.webkit.messageHandlers.h.postMessage(document.documentElement.scrollHeight)}catch(e){}}try{new ResizeObserver(s).observe(document.documentElement)}catch(e){}addEventListener("load",s);setInterval(s,800)})()</script>
        """
        let ns = code as NSString
        if let re = try? NSRegularExpression(pattern: "<head[^>]*>", options: [.caseInsensitive]), let m = re.firstMatch(in: code, range: NSRange(location: 0, length: ns.length)) {
            return ns.replacingCharacters(in: NSRange(location: m.range.location + m.range.length, length: 0), with: head)
        }
        if let re = try? NSRegularExpression(pattern: "<html[^>]*>", options: [.caseInsensitive]), let m = re.firstMatch(in: code, range: NSRange(location: 0, length: ns.length)) {
            return ns.replacingCharacters(in: NSRange(location: m.range.location + m.range.length, length: 0), with: "<head>" + head + "</head>")
        }
        return "<!doctype html><html><head>" + head + "</head><body>" + code + "</body></html>"
    }
}

enum MathPage {
    static func html(_ tex: String, dark: Bool) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [tex])) ?? Data("[\"\"]".utf8)
        let json = (String(data: data, encoding: .utf8) ?? "[\"\"]").replacingOccurrences(of: "<", with: "\\u003c")
        let fg = dark ? "#f2f2f7" : "#111111"
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.16.11/katex.min.css">
        <script src="https://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.16.11/katex.min.js"></script>
        <style>html,body{margin:0;padding:0;background:transparent}body{color:\(fg);font-size:19px;-webkit-text-size-adjust:100%}#m{padding:4px 2px;display:inline-block;min-width:100%;box-sizing:border-box}.katex-display{margin:0}</style>
        </head><body><div id="m"></div><script>
        var T=\(json)[0];
        function post(){try{window.webkit.messageHandlers.h.postMessage(Math.ceil(document.body.getBoundingClientRect().height))}catch(e){}}
        try{katex.render(T,document.getElementById('m'),{displayMode:true,throwOnError:false,strict:'ignore',trust:false,maxSize:20,maxExpand:500})}catch(e){document.getElementById('m').textContent=T}
        post();addEventListener('load',post);setTimeout(post,300);
        </script></body></html>
        """
    }
}

/// A block formula, typeset with KaTeX (the same library the website uses).
struct MathBlock: View {
    let tex: String
    @Environment(\.colorScheme) private var scheme
    @State private var h: CGFloat = 44
    var body: some View {
        HTMLWebView(html: MathPage.html(tex, dark: scheme == .dark), height: $h, scrolls: true)
            .frame(height: max(30, h))
            .frame(maxWidth: .infinity)
            .id("\(scheme == .dark)-\(tex)")
    }
}

struct HTMLPreviewView: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat
    var onLink: (URL) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.websiteDataStore = .nonPersistent()              // previews shouldn't leave caches on disk
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.isScrollEnabled = true
        wv.scrollView.backgroundColor = .clear
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            let lower = html.lowercased()
            let wrapped: String
            if lower.contains("<html") || lower.contains("<!doctype") {
                wrapped = html
            } else {
                wrapped = """
                <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1.0"><style>body{font-family:-apple-system,sans-serif;margin:12px;color:#111;background:#fff;}@media(prefers-color-scheme:dark){body{color:#f5f5f5;background:#1c1c1e;}}</style></head><body>\(html)</body></html>
                """
            }
            wv.loadHTMLString(wrapped, baseURL: nil)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: HTMLPreviewView
        var lastHTML = ""
        init(_ p: HTMLPreviewView) { parent = p }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)") { res, _ in
                guard let num = res as? NSNumber else { return }
                let h = CGFloat(num.doubleValue)
                if h > 20 {
                    DispatchQueue.main.async { self.parent.height = min(max(h, 140), 420) }
                }
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let u = navigationAction.request.url {
                parent.onLink(u)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

/// ```run.html blocks (and "html live" / "html run") run right in the chat via WKWebView.
struct LiveHTMLBlock: View {
    let code: String
    let open: Bool
    @Environment(AppModel.self) private var app
    @State private var showPreview = true
    @State private var h: CGFloat = 220
    @State private var runId = UUID()
    @State private var fullScreen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker(tr("View"), selection: $showPreview) {
                    Text(tr("Preview")).tag(true)
                    Text(tr("Code")).tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                Spacer()
                if !open {
                    Button { runId = UUID(); h = 220 } label: {
                        Image(systemName: "arrow.clockwise").font(.caption.weight(.semibold)).padding(6)
                    }
                    .buttonStyle(.plain).foregroundStyle(Pal.blue)
                    Button { fullScreen = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption.weight(.semibold)).padding(6)
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            if open {
                HStack(spacing: 8) { ThinkingDots(); Text(tr("Writing the interactive block…")).font(.footnote).foregroundStyle(.secondary) }
                    .padding(.vertical, 12)
            } else if showPreview {
                HTMLPreviewView(html: code, height: $h, onLink: { app.open($0) })
                    .frame(height: h)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .id(runId)
            } else {
                ScrollView(.horizontal) {
                    Text(code).font(.system(.footnote, design: .monospaced)).padding(4).textSelection(.enabled)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .clipped()
        .sheet(isPresented: $fullScreen) {
            NavigationStack {
                HTMLPreviewView(html: code, height: .constant(600), onLink: { app.open($0) })
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle(tr("HTML Preview"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { Button(tr("Done")) { fullScreen = false } }
                    }
            }
        }
    }
}

/// Ordinary code. HTML / SVG / JavaScript blocks can run directly inside the chat.
struct CodeBlock: View {
    let lang: String
    let code: String
    let open: Bool
    var note: String?
    @Environment(AppModel.self) private var app
    @State private var preview = false
    @State private var h: CGFloat = 220

    private var lowerLang: String { lang.lowercased() }
    private var isHTML: Bool { ["html", "htm", "svg"].contains(lowerLang) }
    private var isJS: Bool { ["js", "javascript"].contains(lowerLang) }
    private var canRun: Bool { !open && (isHTML || isJS) }

    private var runnableHTML: String {
        if isHTML { return code }
        let b64 = Data(code.utf8).base64EncodedString()
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>body{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:13px;margin:10px;color:#111;background:transparent;}@media(prefers-color-scheme:dark){body{color:#f2f2f7;}}.err{color:#ff453a;}.dim{opacity:.6;}</style>
        </head><body><pre id="out" style="white-space:pre-wrap;margin:0"></pre>
        <script>
        const out=document.getElementById('out');
        const add=(cls,args)=>{const d=document.createElement('div');if(cls)d.className=cls;d.textContent=Array.from(args).map(a=>typeof a==='object'?JSON.stringify(a,null,2):String(a)).join(' ');out.appendChild(d);};
        console.log=(...a)=>add('',a);console.warn=(...a)=>add('',a);console.error=(...a)=>add('err',a);
        try{
          const src=decodeURIComponent(escape(atob('\(b64)')));
          const res=(0,eval)(src);
          if(res!==undefined)add('dim',['→',res]);
          if(!out.children.length)add('dim',['(finished with no output)']);
        }catch(e){add('err',[e.name+': '+e.message]);}
        </script></body></html>
        """
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(lang.isEmpty ? "text" : lang).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if canRun {
                    Button(preview ? "Code" : "Run", systemImage: preview ? "chevron.left.forwardslash.chevron.right" : "play.fill") { preview.toggle() }
                        .font(.caption.weight(.semibold)).buttonStyle(.plain).foregroundStyle(Pal.blue)
                }
                Button { UIPasteboard.general.string = code; app.flash(tr("Copied")) } label: { Image(systemName: "doc.on.doc").font(.caption) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            if preview && canRun {
                HTMLPreviewView(html: runnableHTML, height: $h, onLink: { app.open($0) })
                    .frame(height: h)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                ScrollView(.horizontal) { Text(code).font(.system(.footnote, design: .monospaced)).textSelection(.enabled).padding(.vertical, 4) }
            }
            if let note { Text(note).font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .clipped()
        .onAppear { if !open && isHTML { preview = true } }
        .onChange(of: open) { _, isOpen in if !isOpen && isHTML { preview = true } }
    }
}

// MARK: - Block views

struct RichText: View {
    let text: Text
    let hasHL: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        if hasHL {
            text.textRenderer(HighlightRenderer(color: Pal.blue.opacity(scheme == .dark ? 0.30 : 0.16)))
        } else {
            text
        }
    }
}

struct TableBlock: View {
    let cells: [[Text]]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                ForEach(Array(cells.enumerated()), id: \.offset) { r, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            cell.fontWeight(r == 0 ? .semibold : .regular).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 260, alignment: .leading)
                        }
                    }
                    if r == 0 { Divider().gridCellUnsizedAxes(.horizontal) }
                }
            }
            .padding(14)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

struct BlockView: View {
    let b: ABlock
    let sources: [Hit]

    private static func headingFont(_ level: Int) -> Font {
        if level <= 1 { return Font.title2.bold() }
        if level == 2 { return Font.title3.weight(.semibold) }
        return Font.headline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch b.kind {
            case .para:
                RichText(text: b.text, hasHL: b.hasHL)
            case .heading:
                RichText(text: b.text, hasHL: b.hasHL)
                    .font(Self.headingFont(b.level))
                    .padding(.top, 4)
            case .item:
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let done = b.task {
                        Image(systemName: done ? "checkmark.square.fill" : "square").foregroundStyle(done ? Pal.blue : Color.secondary)
                    } else {
                        Text(b.marker).foregroundStyle(.secondary).monospacedDigit()
                    }
                    RichText(text: b.text, hasHL: b.hasHL)
                }
                .padding(.leading, CGFloat(b.level) * 20)
            case .quote:
                RichText(text: b.text, hasHL: b.hasHL)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 14)
                    .overlay(alignment: .leading) { Capsule().fill(Pal.blue.opacity(0.7)).frame(width: 3) }
            case .table:
                TableBlock(cells: b.cells)
            case .rule:
                Divider().padding(.vertical, 4)
            case .math:
                MathBlock(tex: b.raw)
            case .live:
                LiveHTMLBlock(code: b.raw, open: b.open)
            case .code:
                CodeBlock(lang: b.lang, code: b.raw, open: b.open, note: b.marker == "run" ? "This Python block runs in the web app. Here it's shown as code." : nil)
            case .image:
                AsyncImage(url: URL(string: b.raw)) { p in
                    if let i = p.image { i.resizable().scaledToFit() }
                    else if p.error != nil { Label(b.lang.isEmpty ? "Image" : b.lang, systemImage: "photo").foregroundStyle(.secondary) }
                    else { ProgressView() }
                }
                .frame(maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if !b.cites.isEmpty { CiteRow(cites: b.cites, sources: sources) }
        }
    }
}

struct MarkdownView: View {
    let text: String
    let sources: [Hit]
    var fading = false
    var onSuggest: ((String) -> Void)?
    @Environment(AppModel.self) private var app

    var body: some View {
        let parsed = AnswerParser.parse(text, sourceCount: sources.count, fadeTail: fading ? 16 : 0)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(parsed.blocks) { b in BlockView(b: b, sources: sources) }
        }
        .font(.body)
        .lineSpacing(3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "gsuggest", let h = url.host, h.hasPrefix("s"), let i = Int(h.dropFirst()), i < parsed.sends.count {
                onSuggest?(parsed.sends[i])
                return .handled
            }
            app.open(url)
            return .handled
        })
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

// MARK: - Root, sidebar drawer, in-app browser, video player

/// Masks the app "card" while the sidebar is showing.
/// The corners come entirely from `.rect(corners: .concentric)`; there is no custom radius maths here. The only rule
/// is that no corner is applied while the sidebar isn't showing at all (progress == 0).
/// It's `Animatable` on `progress`, so that "is the sidebar showing?" check follows the card's real position through
/// the whole slide (button, drag or release) instead of flipping the moment the animation starts.
struct ConcentricCardMask: ViewModifier, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.mask {
            ZStack {
                // ignoresSafeArea goes on the fill *before* the clip so the concentric corners are
                // resolved against the full-screen frame rather than the safe-area-inset one
                Color.black
                    .ignoresSafeArea()
                    .clipShape(.rect(corners: .concentric))
                // sidebar fully hidden: square, no corners at all
                Rectangle().opacity(progress > 0 ? 0 : 1).ignoresSafeArea()
            }
            .ignoresSafeArea()
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var drag: CGFloat = 0
    @GestureState private var dragging = false
    @State private var width: CGFloat = 390

    private var compact: Bool { hSize != .regular }
    private var drawerW: CGFloat { min(width * 0.84, 340) }
    private var progress: CGFloat {
        guard compact, app.connected else { return 0 }
        let base: CGFloat = app.sidebarOpen ? drawerW : 0
        return min(max((base + drag) / drawerW, 0), 1)
    }

    var body: some View {
        @Bindable var app = app
        ZStack(alignment: .leading) {
            AmbientBackground()
            if app.connected {
                if compact {
                    SidebarDrawer()
                        .frame(width: drawerW)
                        .offset(x: -(1 - progress) * 60)
                        .opacity(progress > 0 ? 1 : 0)
                        .allowsHitTesting(progress > 0.9)
                        .zIndex(progress > 0.99 ? 2 : 0)
                }
                // the whole app slides over like a card, and the card is rounded to the device's corners while the sidebar is open
                TabView(selection: $app.mainTab) {
                    Tab(tr("Search"), systemImage: "magnifyingglass", value: MainTab.search) { SearchRoot() }
                    Tab(tr("AI Mode"), systemImage: "sparkles", value: MainTab.mode) { AIModeRoot() }
                }
                .tabViewStyle(.sidebarAdaptable)
                .background(AmbientBackground())
                .overlay {
                    if progress > 0 {
                        Color.black.opacity(0.14 * progress)
                            .allowsHitTesting(false)
                    }
                }
                .modifier(ConcentricCardMask(progress: progress))
                .shadow(color: .black.opacity(0.28 * progress), radius: 24, x: -6)
                .allowsHitTesting(progress == 0)
                .offset(x: progress * drawerW)
                .transition(.opacity)
                // Tap / swipe-to-close layer over the card. It's a plain view that sits beside the drawer, so it moves
                // with the card, and it stays alive for as long as the sidebar is marked open (even at progress 0),
                // so a closing drag can never leave the sidebar "open" but invisible.
                if compact, app.sidebarOpen || drag != 0 {
                    Color.clear
                        .contentShape(Rectangle())
                        .offset(x: progress * drawerW)
                        .onTapGesture { app.closeSidebar() }
                        .gesture(sidebarDrag)
                }
            } else {
                ConnectScreen().transition(.opacity)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onChange(of: dragging) { _, isDragging in
            if !isDragging, drag != 0 { settle(momentum: 0) }
        }
        .onChange(of: app.sidebarOpen) { _, _ in
            if !dragging { drag = 0 }
        }
        // The drag lives on a thin strip along the left edge (closed) or on the scrim over the card (open),
        // not on the whole screen. A screen-wide DragGesture makes UIKit cancel touches in segmented controls
        // and sliders as soon as the drag starts, which is what killed dragging between segments.
        .overlay(alignment: .leading) {
            if compact, app.connected, !app.sidebarOpen, app.mainTab == .mode {
                Color.clear
                    .frame(width: 24)
                    .frame(maxHeight: .infinity)
                    .padding(.top, 110)
                    .padding(.bottom, 100)
                    .contentShape(Rectangle())
                    .gesture(sidebarDrag)
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
        .fullScreenCover(item: $app.browser) { BrowserSheet(item: $0) }
        .sheet(item: $app.player) { PlayerSheet(item: $0) }
        .sheet(isPresented: $app.showSettings) { SettingsView() }
        .preferredColorScheme(Prefs.shared.theme.scheme)
        .environment(\.openURL, OpenURLAction { url in
            app.open(url)
            return .handled
        })
        .animation(.smooth(duration: 0.3), value: app.connected)
        .animation(.smooth(duration: 0.25), value: app.notice)
    }

    /// Swipe from the left edge strip to open the sidebar, swipe left on the card to close it. Only on the AI Mode tab.
    private var sidebarDrag: some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .global)
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { v in
                guard compact, app.connected else { return }
                guard abs(v.translation.width) > abs(v.translation.height) * 1.2 else { return }
                if app.sidebarOpen {
                    drag = min(0, max(-drawerW, v.translation.width))
                } else if app.mainTab == .mode {
                    drag = min(drawerW, max(0, v.translation.width))
                }
            }
            .onEnded { v in
                guard drag != 0 else { return }
                settle(momentum: (v.predictedEndTranslation.width - v.translation.width) * 0.25)
            }
    }

    /// Snaps the sidebar fully open or closed from wherever the drag left it.
    private func settle(momentum: CGFloat) {
        let base: CGFloat = app.sidebarOpen ? drawerW : 0
        let open = base + drag + momentum > drawerW * 0.5
        if open { hideKeyboard() }
        withAnimation(.smooth(duration: 0.3)) {
            app.sidebarOpen = open
            drag = 0
        }
    }
}

struct SidebarDrawer: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                GollamaLogo(size: 26)
                Spacer()
                ServerMenu()
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            HistoryList()
        }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    var onDone: () -> Void

    func makeCoordinator() -> Coord { Coord(onDone) }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let cfg = SFSafariViewController.Configuration()
        cfg.entersReaderIfAvailable = false
        let c = SFSafariViewController(url: url, configuration: cfg)
        c.preferredControlTintColor = UIColor(Pal.blue)
        c.delegate = context.coordinator
        return c
    }

    func updateUIViewController(_ c: SFSafariViewController, context: Context) {}

    final class Coord: NSObject, SFSafariViewControllerDelegate {
        let onDone: () -> Void
        init(_ d: @escaping () -> Void) { onDone = d }
        func safariViewControllerDidFinish(_ c: SFSafariViewController) { onDone() }
    }
}

/// Links open here inside SFSafariViewController, which includes native Close and Open in Safari controls.
struct BrowserSheet: View {
    let item: BrowserItem
    @Environment(AppModel.self) private var app
    var body: some View {
        SafariView(url: item.url) { app.browser = nil }
            .ignoresSafeArea()
    }
}

struct PlayerSheet: View {
    let item: PlayerItem
    @Environment(AppModel.self) private var app
    @State private var player: AVPlayer?
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let p = player { VideoPlayer(player: p).ignoresSafeArea() }
            Button { app.player = nil } label: { GlassIcon(name: "xmark", size: 40) }
                .buttonStyle(.plain)
                .padding(16)
        }
        .onAppear {
            let p = AVPlayer(url: item.url)
            player = p
            p.play()
        }
        .onDisappear { player?.pause() }
    }
}

struct ServerMenu: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        Menu {
            if let a = app.address { Text(a.display) }
            if !app.modelName.isEmpty { Text(String(format: tr("Model: %@"), app.modelName)) }
            Button(tr("Settings"), systemImage: "gearshape") { app.showSettings = true }
            Button(tr("Disconnect"), systemImage: "wifi.slash", role: .destructive) { app.disconnect() }
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
                Text(tr("Connect to Gollama")).font(.title3.weight(.medium))

                GlassEffectContainer(spacing: 16) {
                    VStack(spacing: 14) {
                        Picker(tr("Connection"), selection: $mode) {
                            ForEach(ConnectMode.allCases) { Text(tr($0.rawValue)).tag($0) }
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
            Label(tr("Same Wi-Fi as your computer"), systemImage: "wifi").font(.headline)
            Text(tr("Enter the computer's IP and the port Gollama's network server uses, or scan to find it."))
                .font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                field("IP address", text: $host, focus: .host, keyboard: .numbersAndPunctuation)
                field("Port", text: $port, focus: .port).frame(width: 96)
            }
            HStack(spacing: 10) {
                Text(tr("Scan ports up to")).font(.footnote).foregroundStyle(.secondary)
                field("Port", text: $portTo, focus: .portTo).frame(width: 96)
                Spacer()
            }
            Button { scanning ? cancelScan() : startScan() } label: {
                HStack { if scanning { ProgressView() }; Text(tr(scanning ? "Stop scanning" : "Scan network")) }.frame(maxWidth: .infinity)
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
                Text(tr("No Gollama server found. Check the server is on and both devices share the same Wi-Fi."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    // public: a URL (server on the internet or a Cloudflare Tunnel), port optional
    private var publicCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(tr("Server or tunnel URL"), systemImage: "globe").font(.headline)
            Text(tr("Works with a public Gollama server or a Cloudflare Tunnel, for example https://name.trycloudflare.com."))
                .font(.footnote).foregroundStyle(.secondary)
            field("https://your-server.example.com", text: $publicURL, focus: .url, keyboard: .URL)
            Toggle(tr("Use a port"), isOn: $usePort.animation()).tint(Pal.blue)
            if usePort { field("Port (e.g. 8765)", text: $publicPort, focus: .publicPort) }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private var accessCard: some View {
        VStack(spacing: 12) {
            field("Access code (if the server has one)", text: $code, focus: .code, secure: true)
            Button { connect() } label: {
                HStack { if connecting { ProgressView().tint(.white) }; Text(tr("Connect")) }.frame(maxWidth: .infinity)
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
                    SearchField(text: $text, placeholder: tr("Search or ask anything"), height: 52, focused: $focused) { app.submit(text) }
                        .padding(.horizontal, 20)
                    HStack(spacing: 12) {
                        Button(tr("Gollama Search")) { app.submit(text) }.buttonStyle(.glass)
                        Button {
                            let t = text.trimmed
                            app.mainTab = .mode
                            if !t.isEmpty { text = ""; Task { await app.sendMode(t) } }
                        } label: { Label(tr("Ask AI Mode"), systemImage: "sparkles") }
                            .buttonStyle(.glassProminent).tint(Pal.purple)
                    }
                    .controlSize(.large)
                    .padding(.top, 22)

                    if !app.recents.isEmpty || !app.suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            if !app.recents.isEmpty {
                                Text(tr("Recent")).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                                FlowLayout(spacing: 8) {
                                    ForEach(Array(app.recents.prefix(5)), id: \.self) { r in
                                        Button { text = r; app.submit(r) } label: {
                                            Label(r, systemImage: "clock").font(.subheadline).lineLimit(1)
                                                .padding(.horizontal, 12).padding(.vertical, 8)
                                                .glassEffect(.regular.interactive(), in: .capsule)
                                        }
                                        .buttonStyle(.plain)
                                        .contextMenu {
                                            Button(tr("Delete"), systemImage: "trash", role: .destructive) {
                                                withAnimation(.smooth(duration: 0.2)) {
                                                    app.removeRecent(r)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            if !app.suggestions.isEmpty {
                                Text(tr("Try")).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 6)
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
                        .padding(.horizontal, 24).padding(.top, 30)
                        .frame(maxWidth: min(geo.size.width, 640), alignment: .leading)
                    }
                    Spacer(minLength: 60)
                }
                .frame(width: min(geo.size.width, 720))
                .frame(minHeight: geo.size.height)
                .frame(maxWidth: .infinity)
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
                SearchField(text: $text, placeholder: tr("Search"), height: 44, focused: $focused) { app.submit(text) }
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
            Button(tr("Copy link"), systemImage: "doc.on.doc") { UIPasteboard.general.string = hit.url }
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
                        (Text(tr("Showing results for") + " ").foregroundStyle(.secondary) + Text(c).foregroundStyle(Pal.blue).fontWeight(.medium))
                        Button { app.submit(app.original, nocorrect: true) } label: {
                            Text(String(format: tr("Search instead for %@"), app.original)).font(.footnote).foregroundStyle(Pal.blue)
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
        let speakKey = "ov-\(ov.id)"
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Spark(size: 20)
                Text(tr("AI Overview")).font(.title3.weight(.medium))
                Spacer()
                if ov.done && !ov.text.isEmpty {
                    Button { app.toggleSpeech(key: speakKey, raw: ov.text) } label: {
                        Image(systemName: app.speakingKey == speakKey ? "stop.circle.fill" : "speaker.wave.2")
                            .font(.system(size: 16)).foregroundStyle(.secondary).frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                }
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
                    TextField(tr("Ask a follow-up"), text: $followUp).focused($focused).submitLabel(.send).onSubmit { send() }
                    SendButton(enabled: !followUp.trimmed.isEmpty, size: 30) { send() }
                }
                .padding(.leading, 16)
                .padding(.trailing, 7)
                .frame(height: 44)
                .glassEffect(.regular.interactive(), in: .capsule)
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
                Button { if let u = URL(string: item.page) { dismiss(); openURL(u) } } label: { Label(tr("Visit page"), systemImage: "safari") }
                    .buttonStyle(.glassProminent).tint(Pal.blue)
                if let u = item.full { ShareLink(item: u) { Label(tr("Share"), systemImage: "square.and.arrow.up") }.buttonStyle(.glass) }
                Button(tr("Done")) { dismiss() }.buttonStyle(.glass)
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

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                if hSize == .regular {
                    HistoryList().frame(width: 300)
                    Divider()
                }
                ChatView()
            }
            .navigationTitle(app.chatTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if hSize != .regular {
                        Button { app.openSidebar() } label: { Image(systemName: "sidebar.left") }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { app.newChat() } label: { Image(systemName: "square.and.pencil") }
                    Menu {
                        if let a = app.address { Text(a.display) }
                        if !app.modelName.isEmpty { Text(String(format: tr("Model: %@"), app.modelName)) }
                        Button(tr("Settings"), systemImage: "gearshape") { app.showSettings = true }
                        Button(tr("Disconnect"), systemImage: "wifi.slash", role: .destructive) { app.disconnect() }
                    } label: { Image(systemName: "ellipsis") }
                }
            }
        }
        .background(AmbientBackground())
    }
}

/// Chat history. On iPhone it lives in the slide-over sidebar, on iPad it's a column.
struct HistoryList: View {
    @Environment(AppModel.self) private var app
    @State private var filter = ""
    @State private var confirmClear = false

    private var items: [ChatSummary] {
        let q = filter.trimmed.lowercased()
        return q.isEmpty ? app.chats : app.chats.filter { ($0.title + " " + $0.text).lowercased().contains(q) }
    }

    private func picked() {
        app.mainTab = .mode
        app.closeSidebar()
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(tr("History")).font(.title3.weight(.semibold))
                Spacer()
                Button { app.newChat(); picked() } label: { GlassIcon(name: "square.and.pencil", size: 38) }.buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(tr("Search chats"), text: $filter).autocorrectionDisabled()
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
                        Button { Task { await app.openChat(c.id); picked() } } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.title).lineLimit(1).foregroundStyle(.primary)
                                Text(Date(timeIntervalSince1970: c.updated / 1000).formatted(.relative(presentation: .named)))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .listRowBackground(c.id == app.chatId ? Pal.blue.opacity(0.18) : Color.clear)
                        .swipeActions {
                            Button(role: .destructive) { Task { await app.deleteChat(c.id) } } label: { Label(tr("Delete"), systemImage: "trash") }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

            if !app.chats.isEmpty {
                Button(tr("Clear all history"), role: .destructive) { confirmClear = true }
                    .font(.footnote)
                    .padding(.bottom, 10)
            }
        }
        .confirmationDialog(tr("Delete every chat on this device?"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(tr("Delete all"), role: .destructive) { Task { await app.clearChats() } }
        }
        .task { await app.loadChats() }
    }
}

struct ChatView: View {
    @Environment(AppModel.self) private var app
    @State private var follow = true
    @State private var dragging = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // a plain VStack (not Lazy): estimated row heights were what made the message jump to the middle while streaming
                VStack(alignment: .leading, spacing: 22) {
                    if app.turns.isEmpty { EmptyChat() }
                    ForEach(app.turns) { t in TurnView(turn: t) }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .readableWidth(760)
            }
            .scrollDismissesKeyboard(.interactively)
            // follow the new text only while you're at the bottom; scrolling up lets go, scrolling back down picks it up again
            .onScrollPhaseChange { _, phase in dragging = (phase == .interacting) }
            .onScrollGeometryChange(for: CGFloat.self, of: { g in g.contentSize.height - g.contentOffset.y - g.containerSize.height }) { _, dist in
                if dragging { follow = dist < 80 }
            }
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentSize.height }) { _, _ in
                if follow { proxy.scrollTo("end", anchor: .bottom) }
            }
            .onChange(of: app.turns.count) { _, _ in follow = true; proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: app.chatId) { _, _ in follow = true; proxy.scrollTo("end", anchor: .bottom) }
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
            Text(tr("Ask anything")).font(.title2.weight(.medium))
            Text(tr("AI Mode searches the web and answers with sources.")).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
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

struct ThinkingBox: View {
    let entries: [ThinkEntry]
    var body: some View {
        DisclosureGroup("Show thinking") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, e in
                    if e.k == "s" {
                        Label(e.t, systemImage: "magnifyingglass").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text(e.t).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.footnote)
        .tint(.secondary)
    }
}

/// The edit box that replaces the bubble, like the website's in-place edit.
struct EditBox: View {
    let turn: ModeTurn
    @Environment(AppModel.self) private var app
    @FocusState private var focused: Bool
    var body: some View {
        @Bindable var app = app
        VStack(alignment: .trailing, spacing: 10) {
            TextField(tr("Message"), text: $app.editText, axis: .vertical)
                .lineLimit(1...8)
                .focused($focused)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
            HStack(spacing: 10) {
                Button(tr("Cancel")) { app.cancelEdit() }.buttonStyle(.glass)
                Button(tr("Submit")) { app.submitEdit(turn) }
                    .buttonStyle(.glassProminent).tint(Pal.blue)
                    .disabled(app.editText.trimmed.isEmpty)
            }
            .controlSize(.regular)
        }
        .onAppear { focused = true }
    }
}

struct VideoTile: View {
    let video: VideoRef
    @Environment(AppModel.self) private var app
    var body: some View {
        Button { if let u = video.url { app.player = PlayerItem(url: u) } else { app.flash(tr("That video isn't on this device anymore.")) } } label: {
            ZStack {
                if let t = video.thumb { Image(uiImage: t).resizable().scaledToFill() } else { Color.secondary.opacity(0.25) }
                Image(systemName: "play.fill").font(.title3).foregroundStyle(.white)
                    .frame(width: 38, height: 38).glassEffect(.regular, in: .circle)
            }
            .frame(width: 110, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Copy / thumbs / read aloud / try again / More (branch, try again without searching, copy as Markdown, copy sources).
struct TurnActions: View {
    let turn: ModeTurn
    @Environment(AppModel.self) private var app

    private func icon(_ name: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 15)).frame(width: 36, height: 34).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    var body: some View {
        let key = "turn-\(turn.id)"
        HStack(spacing: 2) {
            icon("doc.on.doc", "Copy") { app.copyAnswer(turn) }
            icon(turn.fb == "up" ? "hand.thumbsup.fill" : "hand.thumbsup", "Good response") { app.setFeedback(turn, "up") }
            icon(turn.fb == "down" ? "hand.thumbsdown.fill" : "hand.thumbsdown", "Bad response") { app.setFeedback(turn, "down") }
            icon(app.speakingKey == key ? "stop.circle.fill" : "speaker.wave.2", "Read aloud") { app.toggleSpeech(key: key, raw: turn.answer) }
            icon("arrow.clockwise", "Try again") { app.retry(turn, force: false) }
            Menu {
                Button(tr("Branch in new chat"), systemImage: "arrow.triangle.branch") { Task { await app.branchChat(from: turn) } }
                Button(tr("Try again without searching"), systemImage: "text.magnifyingglass") { app.retry(turn, force: true) }
                Button(tr("Copy as Markdown"), systemImage: "doc.richtext") { app.copyMarkdown(turn) }
                if !turn.sources.isEmpty { Button(tr("Copy sources"), systemImage: "link") { app.copySources(turn) } }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15)).frame(width: 36, height: 34).contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .disabled(app.modeBusy)
    }
}

struct TurnView: View {
    let turn: ModeTurn
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            userPart
            answerPart
        }
    }

    @ViewBuilder private var userPart: some View {
        if app.editingId == turn.id {
            EditBox(turn: turn)
        } else {
            HStack {
                Spacer(minLength: 40)
                VStack(alignment: .trailing, spacing: 6) {
                    if !turn.videos.isEmpty || !turn.thumbs.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(Array(turn.thumbs.enumerated()), id: \.offset) { _, img in
                                Image(uiImage: img).resizable().scaledToFill()
                                    .frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            ForEach(turn.videos) { v in VideoTile(video: v) }
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
                        .contextMenu {
                            Button(tr("Edit"), systemImage: "pencil") { app.beginEdit(turn) }
                            Button(tr("Copy"), systemImage: "doc.on.doc") { UIPasteboard.general.string = turn.text; app.flash(tr("Copied")) }
                        }
                }
            }
        }
    }

    private var answerPart: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !turn.status.isEmpty { HStack(spacing: 8) { ThinkingDots(); Text(turn.status).font(.footnote).foregroundStyle(.secondary) } }
            if !turn.think.isEmpty { ThinkingBox(entries: turn.think) }
            if !turn.answer.isEmpty {
                AnswerText(text: turn.answer, sources: turn.sources, streaming: !turn.done,
                           onSuggest: { s in Task { await app.sendMode(s) } })
            }
            if let e = turn.error { Text(e).foregroundStyle(.red).font(.subheadline) }
            if turn.noResultsFor != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("There isn't a result available for this search.")).fontWeight(.medium)
                    Text(tr("You can still get an answer from the model, but it won't be backed by sources.")).font(.subheadline).foregroundStyle(.secondary)
                    Button(tr("Continue anyway")) { Task { await app.sendMode(turn.text, force: true, reuse: turn) } }
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
            if turn.done && !turn.answer.isEmpty { TurnActions(turn: turn) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
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
            TextField(tr("Ask AI Mode"), text: $text, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.top, 2)

            HStack(spacing: 8) {
                Menu {
                    Button(tr("Photos & Videos"), systemImage: "photo.on.rectangle") { showPhotos = true }
                    Button(tr("Files"), systemImage: "doc") { showFiles = true }
                } label: {
                    Image(systemName: "plus").font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                        .frame(width: 32, height: 32).glassEffect(.regular.interactive(), in: .circle)
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)

                Menu {
                    Picker(tr("Model"), selection: $app.tier) {
                        Text(tr("Fast")).tag("fast")
                        Text(tr("Pro")).tag("pro")
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
            // tap a video to watch it before you send it
            Button {
                if att.kind == .video, let u = att.localURL { app.player = PlayerItem(url: u) }
            } label: {
                HStack(spacing: 8) {
                    ZStack {
                        if let t = att.thumb {
                            Image(uiImage: t).resizable().scaledToFill()
                        } else {
                            Image(systemName: att.kind == .video ? "film" : "doc.text")
                        }
                        if att.kind == .video { Image(systemName: "play.fill").font(.system(size: 10)).foregroundStyle(.white).shadow(radius: 2) }
                    }
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(att.name).font(.caption.weight(.medium)).lineLimit(1)
                        if att.state == "uploading" || att.state == "processing" {
                            ProgressView(value: att.progress).frame(width: 90)
                            Text(att.message).font(.caption2).foregroundStyle(.secondary)
                        } else if att.state == "error" {
                            Text(att.message).font(.caption2).foregroundStyle(.red).lineLimit(1)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            Button { app.remove(att) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 260)
        .glassEffect(.regular, in: .capsule)
    }
}


// MARK: - Appearance, languages & settings

/// Light, dark, or follow the device.
enum AppTheme: String, CaseIterable, Identifiable {
    case auto, light, dark
    var id: String { rawValue }
    var scheme: ColorScheme? {
        switch self {
        case .auto: nil
        case .light: .light
        case .dark: .dark
        }
    }
    var titleKey: String {
        switch self {
        case .auto: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    var icon: String {
        switch self {
        case .auto: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }
}

/// Every language the interface can be shown in. `.system` follows the device.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, es, fr, de, it, pt, nl, sv, pl, tr, ru, uk, ar, he, hi, th, vi, idn, ja, ko, zhHans, zhHant, cs
    var id: String { rawValue }

    /// Each language is listed under its own name so people can always find theirs.
    var nativeName: String {
        switch self {
        case .system: ""
        case .en: "English"
        case .es: "Español"
        case .fr: "Français"
        case .de: "Deutsch"
        case .it: "Italiano"
        case .pt: "Português"
        case .nl: "Nederlands"
        case .sv: "Svenska"
        case .pl: "Polski"
        case .tr: "Türkçe"
        case .ru: "Русский"
        case .uk: "Українська"
        case .ar: "العربية"
        case .he: "עברית"
        case .hi: "हिन्दी"
        case .th: "ไทย"
        case .vi: "Tiếng Việt"
        case .idn: "Bahasa Indonesia"
        case .ja: "日本語"
        case .ko: "한국어"
        case .zhHans: "简体中文"
        case .zhHant: "繁體中文"
        case .cs: "Čeština"
        }
    }

    /// The device's preferred language, mapped to one we ship (English if we don't have it).
    static var device: AppLanguage {
        for code in Locale.preferredLanguages {
            let c = code.lowercased()
            if c.hasPrefix("zh-hant") || c.hasPrefix("zh-tw") || c.hasPrefix("zh-hk") || c.hasPrefix("zh-mo") { return .zhHant }
            if c.hasPrefix("zh") { return .zhHans }
            if c.hasPrefix("iw") { return .he }
            let base = String(c.prefix(2))
            if base == "id" { return .idn }
            if base == "en" { return .en }
            switch base {
            case "es": return .es
            case "fr": return .fr
            case "de": return .de
            case "it": return .it
            case "pt": return .pt
            case "nl": return .nl
            case "sv": return .sv
            case "pl": return .pl
            case "tr": return .tr
            case "ru": return .ru
            case "uk": return .uk
            case "ar": return .ar
            case "he": return .he
            case "hi": return .hi
            case "th": return .th
            case "vi": return .vi
            case "ja": return .ja
            case "ko": return .ko
            case "cs": return .cs
            default: continue
            }
        }
        return .en
    }
}

/// Saved appearance + language. Observable, so changing either one updates the whole UI immediately.
@MainActor @Observable final class Prefs {
    static let shared = Prefs()
    var theme: AppTheme { didSet { UserDefaults.standard.set(theme.rawValue, forKey: "gollama.theme") } }
    var language: AppLanguage { didSet { UserDefaults.standard.set(language.rawValue, forKey: "gollama.language") } }
    var effectiveLanguage: AppLanguage { language == .system ? AppLanguage.device : language }

    private init() {
        theme = AppTheme(rawValue: UserDefaults.standard.string(forKey: "gollama.theme") ?? "") ?? .auto
        language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "gollama.language") ?? "") ?? .system
    }
}

/// Looks a UI string up in the selected language. English text is the key, so anything missing falls back to English.
@MainActor func tr(_ key: String) -> String {
    let lang = Prefs.shared.effectiveLanguage
    if lang == .en { return key }
    return L10n.tables[lang]?[key] ?? key
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var prefs = Prefs.shared
    @State private var totalBytes: Int64 = 0

    private var languageName: String {
        prefs.language == .system ? tr("System default") : prefs.language.nativeName
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        ForEach(AppTheme.allCases) { option in
                            let selected = prefs.theme == option
                            Button {
                                withAnimation(.smooth(duration: 0.25)) { prefs.theme = option }
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: option.icon).font(.system(size: 24))
                                    Text(tr(option.titleKey)).font(.footnote.weight(.medium))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .foregroundStyle(selected ? Pal.blue : Color.primary)
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(selected ? Pal.blue.opacity(0.16) : Color.primary.opacity(0.06)))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? Pal.blue : Color.clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    Text(tr("Appearance"))
                } footer: {
                    Text(tr("Auto follows your device's appearance."))
                }

                Section {
                    NavigationLink {
                        LanguageSettingsView()
                    } label: {
                        LabeledContent {
                            Text(languageName)
                        } label: {
                            Label(tr("Language"), systemImage: "globe")
                        }
                    }
                    NavigationLink {
                        StorageSettingsView()
                    } label: {
                        LabeledContent {
                            Text(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))
                        } label: {
                            Label(tr("Manage Storage"), systemImage: "internaldrive")
                        }
                    }
                }
            }
            .navigationTitle(tr("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .task { totalBytes = Storage.size() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(tr("Done")) { dismiss() } }
            }
        }
    }
}

/// Settings > Language: one tap to pick the interface language.
struct LanguageSettingsView: View {
    @Bindable private var prefs = Prefs.shared

    var body: some View {
        Form {
            ForEach(AppLanguage.allCases) { lang in
                Button {
                    prefs.language = lang
                } label: {
                    HStack {
                        Text(lang == .system ? tr("System default") : lang.nativeName)
                        Spacer()
                        if prefs.language == lang {
                            Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Pal.blue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(tr("Language"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Settings > Manage Storage: what gets saved, how much room it may use, and what is using space right now.
struct StorageSettingsView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("gollama.keepVideos") private var keepVideos = true
    @AppStorage("gollama.videoCapMB") private var videoCapMB = 64
    @AppStorage("gollama.videoDays") private var videoDays = 14
    @AppStorage("gollama.imageCacheMB") private var imageCacheMB = 12
    @State private var videoBytes: Int64 = 0
    @State private var cacheBytes: Int64 = 0

    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    private func mb(_ n: Int) -> String { size(Int64(n) * 1024 * 1024) }
    private func days(_ n: Int) -> String {
        n <= 0 ? tr("Forever") : n == 1 ? tr("1 day") : String(format: tr("%d days"), n)
    }
    private func refresh() {
        videoBytes = Storage.videoBytes()
        cacheBytes = Storage.cacheBytes()
    }

    var body: some View {
        Form {
            Section {
                Toggle(tr("Save uploaded videos"), isOn: $keepVideos)
                Picker(tr("Video storage limit"), selection: $videoCapMB) {
                    ForEach([32, 64, 128, 256, 512, 1024], id: \.self) { Text(mb($0)).tag($0) }
                }
                .disabled(!keepVideos)
                Picker(tr("Keep videos for"), selection: $videoDays) {
                    ForEach([1, 7, 14, 30, 0], id: \.self) { Text(days($0)).tag($0) }
                }
                .disabled(!keepVideos)
            } header: {
                Text(tr("Saved videos"))
            } footer: {
                Text(tr("Lets you watch a video again from the chat after you've sent it."))
            }

            Section {
                Picker(tr("Image cache limit"), selection: $imageCacheMB) {
                    ForEach([0, 12, 32, 64, 128], id: \.self) { Text($0 == 0 ? tr("Off") : mb($0)).tag($0) }
                }
            } footer: {
                Text(tr("Images and web pages are kept so they load faster."))
            }

            Section {
                LabeledContent(tr("Saved videos"), value: size(videoBytes))
                LabeledContent(tr("Cache and temporary files"), value: size(cacheBytes))
                LabeledContent(tr("Total"), value: size(videoBytes + cacheBytes)).fontWeight(.semibold)
            } header: {
                Text(tr("Usage"))
            }

            Section {
                Button(tr("Clear saved videos"), role: .destructive) {
                    Storage.clearVideos()
                    refresh()
                    app.flash(tr("Done"))
                }
                Button(tr("Clear cache"), role: .destructive) {
                    Storage.clearCache()
                    refresh()
                    app.flash(tr("Done"))
                }
            } footer: {
                Text(tr("Your chats live on the server, so clearing storage never deletes them."))
            }
        }
        .navigationTitle(tr("Manage Storage"))
        .navigationBarTitleDisplayMode(.inline)
        .task { refresh() }
        .onChange(of: videoCapMB) { _, _ in VideoStore.prune(); refresh() }
        .onChange(of: videoDays) { _, _ in VideoStore.prune(); refresh() }
        .onChange(of: imageCacheMB) { _, _ in Storage.applyImageCacheLimit(); refresh() }
    }
}

/// UI translations, keyed by the English string.
enum L10n {
    static let tables: [AppLanguage: [String: String]] = [.es: es, .fr: fr, .de: de, .it: it, .pt: pt, .nl: nl, .sv: sv, .pl: pl, .tr: tr, .ru: ru, .uk: uk, .ar: ar, .he: he, .hi: hi, .th: th, .vi: vi, .idn: idn, .ja: ja, .ko: ko, .zhHans: zhHans, .zhHant: zhHant, .cs: cs]

    static let es: [String: String] = [
        "Settings": "Ajustes",
        "Appearance": "Apariencia",
        "Auto": "Automático",
        "Light": "Claro",
        "Dark": "Oscuro",
        "Auto follows your device's appearance.": "Automático sigue la apariencia de tu dispositivo.",
        "Language": "Idioma",
        "System default": "Predeterminado del sistema",
        "Done": "Listo",
        "Preview": "Vista previa",
        "Code": "Código",
        "View": "Vista",
        "Writing the interactive block…": "Escribiendo el bloque interactivo…",
        "HTML Preview": "Vista previa HTML",
        "Model: %@": "Modelo: %@",
        "Disconnect": "Desconectar",
        "Connect to Gollama": "Conectar a Gollama",
        "Private": "Privada",
        "Public": "Pública",
        "Connection": "Conexión",
        "Same Wi-Fi as your computer": "Misma Wi-Fi que tu ordenador",
        "Enter the computer's IP and the port Gollama's network server uses, or scan to find it.": "Introduce la IP del ordenador y el puerto del servidor de red de Gollama, o escanea para encontrarlo.",
        "Scan ports up to": "Escanear puertos hasta",
        "No Gollama server found. Check the server is on and both devices share the same Wi-Fi.": "No se encontró ningún servidor de Gollama. Comprueba que el servidor esté activo y que ambos dispositivos estén en la misma Wi-Fi.",
        "Server or tunnel URL": "URL del servidor o túnel",
        "Works with a public Gollama server or a Cloudflare Tunnel, for example https://name.trycloudflare.com.": "Funciona con un servidor Gollama público o un túnel de Cloudflare, por ejemplo https://name.trycloudflare.com.",
        "Use a port": "Usar un puerto",
        "Connect": "Conectar",
        "Stop scanning": "Detener escaneo",
        "Scan network": "Escanear red",
        "Gollama Search": "Buscar con Gollama",
        "Ask AI Mode": "Preguntar al Modo IA",
        "Recent": "Recientes",
        "Delete": "Eliminar",
        "Try": "Prueba",
        "Copy link": "Copiar enlace",
        "Showing results for": "Mostrando resultados de",
        "Search instead for %@": "Buscar en su lugar %@",
        "AI Overview": "Resumen de IA",
        "Ask a follow-up": "Haz otra pregunta",
        "Visit page": "Visitar página",
        "Share": "Compartir",
        "History": "Historial",
        "Search chats": "Buscar chats",
        "Clear all history": "Borrar todo el historial",
        "Delete every chat on this device?": "¿Eliminar todos los chats de este dispositivo?",
        "Delete all": "Eliminar todo",
        "Ask anything": "Pregunta lo que quieras",
        "AI Mode searches the web and answers with sources.": "El Modo IA busca en la web y responde con fuentes.",
        "Message": "Mensaje",
        "Cancel": "Cancelar",
        "Submit": "Enviar",
        "That video isn't on this device anymore.": "Ese vídeo ya no está en este dispositivo.",
        "Branch in new chat": "Ramificar en un chat nuevo",
        "Try again without searching": "Reintentar sin buscar",
        "Copy as Markdown": "Copiar como Markdown",
        "Copy sources": "Copiar fuentes",
        "Edit": "Editar",
        "Copy": "Copiar",
        "There isn't a result available for this search.": "No hay ningún resultado disponible para esta búsqueda.",
        "You can still get an answer from the model, but it won't be backed by sources.": "Aún puedes obtener una respuesta del modelo, pero no estará respaldada por fuentes.",
        "Continue anyway": "Continuar de todos modos",
        "Photos & Videos": "Fotos y vídeos",
        "Files": "Archivos",
        "Model": "Modelo",
        "Fast": "Rápido",
        "Pro": "Pro",
        "Search": "Buscar",
        "AI Mode": "Modo IA",
        "Search or ask anything": "Busca o pregunta lo que quieras",
        "Copied": "Copiado",
        "Copied as Markdown": "Copiado como Markdown",
        "Sources copied": "Fuentes copiadas",
        "Stop": "Detener",
        "Send": "Enviar",
        "Wait for the attachment to finish.": "Espera a que termine el adjunto.",
        "Couldn't read that video.": "No se pudo leer ese vídeo.",
        "Couldn't read that photo.": "No se pudo leer esa foto.",
        "%@ isn't a text file.": "%@ no es un archivo de texto.",
        "Storage": "Almacenamiento",
        "Clear cache": "Borrar caché",
        "Saved videos and cached images. Your chats stay on the server.": "Vídeos guardados e imágenes en caché. Tus chats permanecen en el servidor.",
        "Manage Storage": "Administrar almacenamiento",
        "Save uploaded videos": "Guardar vídeos subidos",
        "Lets you watch a video again from the chat after you've sent it.": "Te permite volver a ver un vídeo desde el chat después de enviarlo.",
        "Video storage limit": "Límite de almacenamiento de vídeo",
        "Keep videos for": "Conservar vídeos durante",
        "%d days": "%d días",
        "1 day": "1 día",
        "Forever": "Siempre",
        "Image cache limit": "Límite de caché de imágenes",
        "Off": "Desactivado",
        "Images and web pages are kept so they load faster.": "Las imágenes y páginas web se guardan para que carguen más rápido.",
        "Saved videos": "Vídeos guardados",
        "Cache and temporary files": "Caché y archivos temporales",
        "Total": "Total",
        "Clear saved videos": "Borrar vídeos guardados",
        "Usage": "Uso",
        "Your chats live on the server, so clearing storage never deletes them.": "Tus chats están en el servidor, así que liberar almacenamiento nunca los elimina."
    ]
    static let fr: [String: String] = [
        "Settings": "Réglages",
        "Appearance": "Apparence",
        "Auto": "Auto",
        "Light": "Clair",
        "Dark": "Sombre",
        "Auto follows your device's appearance.": "Auto suit l'apparence de votre appareil.",
        "Language": "Langue",
        "System default": "Par défaut du système",
        "Done": "Terminé",
        "Preview": "Aperçu",
        "Code": "Code",
        "View": "Affichage",
        "Writing the interactive block…": "Écriture du bloc interactif…",
        "HTML Preview": "Aperçu HTML",
        "Model: %@": "Modèle : %@",
        "Disconnect": "Déconnecter",
        "Connect to Gollama": "Se connecter à Gollama",
        "Private": "Privé",
        "Public": "Public",
        "Connection": "Connexion",
        "Same Wi-Fi as your computer": "Même Wi-Fi que votre ordinateur",
        "Enter the computer's IP and the port Gollama's network server uses, or scan to find it.": "Saisissez l'IP de l'ordinateur et le port du serveur réseau de Gollama, ou lancez une recherche pour le trouver.",
        "Scan ports up to": "Scanner les ports jusqu'à",
        "No Gollama server found. Check the server is on and both devices share the same Wi-Fi.": "Aucun serveur Gollama trouvé. Vérifiez que le serveur est activé et que les deux appareils sont sur le même Wi-Fi.",
        "Server or tunnel URL": "URL du serveur ou du tunnel",
        "Works with a public Gollama server or a Cloudflare Tunnel, for example https://name.trycloudflare.com.": "Fonctionne avec un serveur Gollama public ou un tunnel Cloudflare, par exemple https://name.trycloudflare.com.",
        "Use a port": "Utiliser un port",
        "Connect": "Se connecter",
        "Stop scanning": "Arrêter la recherche",
        "Scan network": "Analyser le réseau",
        "Gollama Search": "Recherche Gollama",
        "Ask AI Mode": "Demander au mode IA",
        "Recent": "Récentes",
        "Delete": "Supprimer",
        "Try": "Essayer",
        "Copy link": "Copier le lien",
        "Showing results for": "Résultats affichés pour",
        "Search instead for %@": "Rechercher plutôt %@",
        "AI Overview": "Aperçu IA",
        "Ask a follow-up": "Poser une question complémentaire",
        "Visit page": "Visiter la page",
        "Share": "Partager",
        "History": "Historique",
        "Search chats": "Rechercher des discussions",
        "Clear all history": "Effacer tout l'historique",
        "Delete every chat on this device?": "Supprimer toutes les discussions sur cet appareil ?",
        "Delete all": "Tout supprimer",
        "Ask anything": "Posez n'importe quelle question",
        "AI Mode searches the web and answers with sources.": "Le mode IA effectue des recherches sur le Web et répond en citant ses sources.",
        "Message": "Message",
        "Cancel": "Annuler",
        "Submit": "Envoyer",
        "That video isn't on this device anymore.": "Cette vidéo n'est plus sur cet appareil.",
        "Branch in new chat": "Créer une branche dans une nouvelle discussion",
        "Try again without searching": "Réessayer sans recherche",
        "Copy as Markdown": "Copier en Markdown",
        "Copy sources": "Copier les sources",
        "Edit": "Modifier",
        "Copy": "Copier",
        "There isn't a result available for this search.": "Aucun résultat n'est disponible pour cette recherche.",
        "You can still get an answer from the model, but it won't be backed by sources.": "Vous pouvez quand même obtenir une réponse du modèle, mais elle ne sera pas appuyée par des sources.",
        "Continue anyway": "Continuer quand même",
        "Photos & Videos": "Photos et vidéos",
        "Files": "Fichiers",
        "Model": "Modèle",
        "Fast": "Rapide",
        "Pro": "Pro",
        "Search": "Recherche",
        "AI Mode": "Mode IA",
        "Search or ask anything": "Recherchez ou posez une question",
        "Copied": "Copié",
        "Copied as Markdown": "Copié en Markdown",
        "Sources copied": "Sources copiées",
        "Stop": "Arrêter",
        "Send": "Envoyer",
        "Wait for the attachment to finish.": "Attendez la fin du chargement de la pièce jointe.",
        "Couldn't read that video.": "Impossible de lire cette vidéo.",
        "Couldn't read that photo.": "Impossible de lire cette photo.",
        "%@ isn't a text file.": "%@ n'est pas un fichier texte.",
        "Storage": "Stockage",
        "Clear cache": "Vider le cache",
        "Saved videos and cached images. Your chats stay on the server.": "Vidéos enregistrées et images en cache. Vos discussions restent sur le serveur.",
        "Manage Storage": "Gérer le stockage",
        "Save uploaded videos": "Enregistrer les vidéos envoyées",
        "Lets you watch a video again from the chat after you've sent it.": "Permet de revoir une vidéo depuis la discussion après l'envoi.",
        "Video storage limit": "Limite de stockage des vidéos",
        "Keep videos for": "Conserver les vidéos pendant",
        "%d days": "%d jours",
        "1 day": "1 jour",
        "Forever": "Toujours",
        "Image cache limit": "Limite du cache d'images",
        "Off": "Désactivé",
        "Images and web pages are kept so they load faster.": "Les images et pages web sont conservées pour se charger plus vite.",
        "Saved videos": "Vidéos enregistrées",
        "Cache and temporary files": "Cache et fichiers temporaires",
        "Total": "Total",
        "Clear saved videos": "Supprimer les vidéos enregistrées",
        "Usage": "Utilisation",
        "Your chats live on the server, so clearing storage never deletes them.": "Vos discussions sont sur le serveur : libérer du stockage ne les supprime jamais."
    ]
    static let de: [String: String] = [
        "Settings": "Einstellungen",
        "Appearance": "Darstellung",
        "Auto": "Automatisch",
        "Light": "Hell",
        "Dark": "Dunkel",
        "Auto follows your device's appearance.": "Automatisch folgt der Darstellung deines Geräts.",
        "Language": "Sprache",
        "System default": "Systemstandard",
        "Done": "Fertig",
        "Preview": "Vorschau",
        "Code": "Code",
        "View": "Ansicht",
        "Writing the interactive block…": "Interaktiver Block wird erstellt …",
        "HTML Preview": "HTML-Vorschau",
        "Model: %@": "Modell: %@",
        "Disconnect": "Trennen",
        "Connect to Gollama": "Mit Gollama verbinden",
        "Private": "Privat",
        "Public": "Öffentlich",
        "Connection": "Verbindung",
        "Same Wi-Fi as your computer": "Gleiches WLAN wie dein Computer",
        "Enter the computer's IP and the port Gollama's network server uses, or scan to find it.": "Gib die IP des Computers und den Port des Gollama-Netzwerkservers ein oder suche ihn per Scan.",
        "Scan ports up to": "Ports scannen bis",
        "No Gollama server found. Check the server is on and both devices share the same Wi-Fi.": "Kein Gollama-Server gefunden. Prüfe, ob der Server läuft und beide Geräte im selben WLAN sind.",
        "Server or tunnel URL": "Server- oder Tunnel-URL",
        "Works with a public Gollama server or a Cloudflare Tunnel, for example https://name.trycloudflare.com.": "Funktioniert mit einem öffentlichen Gollama-Server oder einem Cloudflare-Tunnel, z. B. https://name.trycloudflare.com.",
        "Use a port": "Port verwenden",
        "Connect": "Verbinden",
        "Stop scanning": "Scan stoppen",
        "Scan network": "Netzwerk scannen",
        "Gollama Search": "Gollama-Suche",
        "Ask AI Mode": "Im KI-Modus fragen",
        "Recent": "Zuletzt",
        "Delete": "Löschen",
        "Try": "Probier's aus",
        "Copy link": "Link kopieren",
        "Showing results for": "Ergebnisse für",
        "Search instead for %@": "Stattdessen nach %@ suchen",
        "AI Overview": "KI-Übersicht",
        "Ask a follow-up": "Folgefrage stellen",
        "Visit page": "Seite besuchen",
        "Share": "Teilen",
        "History": "Verlauf",
        "Search chats": "Chats durchsuchen",
        "Clear all history": "Gesamten Verlauf löschen",
        "Delete every chat on this device?": "Alle Chats auf diesem Gerät löschen?",
        "Delete all": "Alle löschen",
        "Ask anything": "Frag einfach",
        "AI Mode searches the web and answers with sources.": "Der KI-Modus durchsucht das Web und antwortet mit Quellen.",
        "Message": "Nachricht",
        "Cancel": "Abbrechen",
        "Submit": "Senden",
        "That video isn't on this device anymore.": "Dieses Video ist nicht mehr auf diesem Gerät.",
        "Branch in new chat": "In neuem Chat verzweigen",
        "Try again without searching": "Ohne Suche erneut versuchen",
        "Copy as Markdown": "Als Markdown kopieren",
        "Copy sources": "Quellen kopieren",
        "Edit": "Bearbeiten",
        "Copy": "Kopieren",
        "There isn't a result available for this search.": "Für diese Suche ist kein Ergebnis verfügbar.",
        "You can still get an answer from the model, but it won't be backed by sources.": "Du kannst trotzdem eine Antwort vom Modell erhalten, sie ist aber nicht durch Quellen belegt.",
        "Continue anyway": "Trotzdem fortfahren",
        "Photos & Videos": "Fotos & Videos",
        "Files": "Dateien",
        "Model": "Modell",
        "Fast": "Schnell",
        "Pro": "Pro",
        "Search": "Suche",
        "AI Mode": "KI-Modus",
        "Search or ask anything": "Suchen oder etwas fragen",
        "Copied": "Kopiert",
        "Copied as Markdown": "Als Markdown kopiert",
        "Sources copied": "Quellen kopiert",
        "Stop": "Stopp",
        "Send": "Senden",
        "Wait for the attachment to finish.": "Warte, bis der Anhang fertig ist.",
        "Couldn't read that video.": "Das Video konnte nicht gelesen werden.",
        "Couldn't read that photo.": "Das Foto konnte nicht gelesen werden.",
        "%@ isn't a text file.": "%@ ist keine Textdatei.",
        "Storage": "Speicher",
        "Clear cache": "Cache leeren",
        "Saved videos and cached images. Your chats stay on the server.": "Gespeicherte Videos und zwischengespeicherte Bilder. Deine Chats bleiben auf dem Server.",
        "Manage Storage": "Speicher verwalten",
        "Save uploaded videos": "Hochgeladene Videos speichern",
        "Lets you watch a video again from the chat after you've sent it.": "Damit kannst du ein Video nach dem Senden im Chat erneut ansehen.",
        "Video storage limit": "Speicherlimit für Videos",
        "Keep videos for": "Videos behalten für",
        "%d days": "%d Tage",
        "1 day": "1 Tag",
        "Forever": "Für immer",
        "Image cache limit": "Limit für Bildcache",
        "Off": "Aus",
        "Images and web pages are kept so they load faster.": "Bilder und Webseiten werden zwischengespeichert, damit sie schneller laden.",
        "Saved videos": "Gespeicherte Videos",
        "Cache and temporary files": "Cache und temporäre Dateien",
        "Total": "Gesamt",
        "Clear saved videos": "Gespeicherte Videos löschen",
        "Usage": "Belegung",
        "Your chats live on the server, so clearing storage never deletes them.": "Deine Chats liegen auf dem Server, daher werden sie beim Leeren nie gelöscht."
    ]
    static let it: [String: String] = [
        "Settings": "Impostazioni",
        "Appearance": "Aspetto",
        "Auto": "Automatico",
        "Light": "Chiaro",
        "Dark": "Scuro",
        "Auto follows your device's appearance.": "Automatico segue l'aspetto del dispositivo.",
        "Language": "Lingua",
        "System default": "Predefinito di sistema",
        "Done": "Fine",
        "Preview": "Anteprima",
        "Code": "Codice",
        "View": "Vista",
        "Writing the interactive block…": "Scrittura del blocco interattivo…",
        "HTML Preview": "Anteprima HTML",
        "Model: %@": "Modello: %@",
        "Disconnect": "Disconnetti",
        "Connect to Gollama": "Connettiti a Gollama",
        "Private": "Privata",
        "Public": "Pubblica",
        "Connection": "Connessione",
        "Same Wi-Fi as your computer": "Stessa rete Wi-Fi del computer",
        "Enter the computer's IP and the port Gollama's network server uses, or scan to find it.": "Inserisci l'IP del computer e la porta del server di rete di Gollama, oppure scansiona per trovarlo.",
        "Scan ports up to": "Scansiona le porte fino a",
        "No Gollama server found. Check the server is on and both devices share the same Wi-Fi.": "Nessun server Gollama trovato. Verifica che il server sia attivo e che entrambi i dispositivi siano sulla stessa rete Wi-Fi.",
        "Server or tunnel URL": "URL del server o del tunnel",
        "Works with a public Gollama server or a Cloudflare Tunnel, for example https://name.trycloudflare.com.": "Funziona con un server Gollama pubblico o un tunnel Cloudflare, ad esempio https://name.trycloudflare.com.",
        "Use a port": "Usa una porta",
        "Connect": "Connetti",
        "Stop scanning": "Interrompi scansione",
        "Scan network": "Scansiona rete",
        "Gollama Search": "Cerca con Gollama",
        "Ask AI Mode": "Chiedi alla modalità IA",
        "Recent": "Recenti",
        "Delete": "Elimina",
        "Try": "Prova",
        "Copy link": "Copia link",
        "Showing results for": "Risultati per",
        "Search instead for %@": "Cerca invece %@",
        "AI Overview": "Panoramica IA",
        "Ask a follow-up": "Fai una domanda di approfondimento",
        "Visit page": "Visita la pagina",
        "Share": "Condividi",
        "History": "Cronologia",
        "Search chats": "Cerca nelle chat",
        "Clear all history": "Cancella tutta la cronologia",
        "Delete every chat on this device?": "Eliminare tutte le chat su questo dispositivo?",
        "Delete all": "Elimina tutto",
        "Ask anything": "Chiedi qualsiasi cosa",
        "AI Mode searches the web and answers with sources.": "La modalità IA cerca sul web e risponde citando le fonti.",
        "Message": "Messaggio",
        "Cancel": "Annulla",
        "Submit": "Invia",
        "That video isn't on this device anymore.": "Quel video non è più su questo dispositivo.",
        "Branch in new chat": "Crea ramo in una nuova chat",
        "Try again without searching": "Riprova senza cercare",
        "Copy as Markdown": "Copia come Markdown",
        "Copy sources": "Copia fonti",
        "Edit": "Modifica",
        "Copy": "Copia",
        "There isn't a result available for this search.": "Non ci sono risultati disponibili per questa ricerca.",
        "You can still get an answer from the model, but it won't be backed by sources.": "Puoi comunque ottenere una risposta dal modello, ma non sarà supportata da fonti.",
        "Continue anyway": "Continua comunque",
        "Photos & Videos": "Foto e video",
        "Files": "File",
        "Model": "Modello",
        "Fast": "Veloce",
        "Pro": "Pro",
        "Search": "Cerca",
        "AI Mode": "Modalità IA",
        "Search or ask anything": "Cerca o chiedi qualsiasi cosa",
        "Copied": "Copiato",
        "Copied as Markdown": "Copiato come Markdown",
        "Sources copied": "Fonti copiate",
        "Stop": "Interrompi",
        "Send": "Invia",
        "Wait for the attachment to finish.": "Attendi il completamento dell'allegato.",
        "Couldn't read that video.": "Impossibile leggere quel video.",
        "Couldn't read that photo.": "Impossibile leggere quella foto.",
        "%@ isn't a text file.": "%@ non è un file di testo.",
        "Storage": "Spazio di archiviazione",
        "Clear cache": "Svuota cache",
        "Saved videos and cached images. Your chats stay on the server.": "Video salvati e immagini nella cache. Le chat restano sul server.",
        "Manage Storage": "Gestisci spazio",
        "Save uploaded videos": "Salva i video caricati",
        "Lets you watch a video again from the chat after you've sent it.": "Ti permette di rivedere un video dalla chat dopo averlo inviato.",
        "Video storage limit": "Limite di spazio per i video",
        "Keep videos for": "Conserva i video per",
        "%d days": "%d giorni",
        "1 day": "1 giorno",
        "Forever": "Per sempre",
        "Image cache limit": "Limite cache immagini",
        "Off": "Disattivato",
        "Images and web pages are kept so they load faster.": "Immagini e pagine web vengono conservate per caricarsi più velocemente.",
        "Saved videos": "Video salvati",
        "Cache and temporary files": "Cache e file temporanei",
        "Total": "Totale",
        "Clear saved videos": "Elimina video salvati",
        "Usage": "Utilizzo",
        "Your chats live on the server, so clearing storage never deletes them.": "Le chat sono sul server, quindi liberare spazio non le elimina mai."
    ]
    static let pt: [String: String] = [
        "Settings": "Ajustes",
        "Appearance": "Aparência",
        "Auto": "Automático",
        "Light": "Claro",
        "Dark": "Escuro",
        "Auto follows your device's appearance.": "Automático segue a aparência do seu dispositivo.",
        "Language": "Idioma",
        "System default": "Padrão do sistema",
        "Done": "Concluído",
        "Preview": "Pré-visualização",
        "Code": "Código",
        "View": "Vista",
        "Writing the interactive block…": "Escrevendo o bloco interativo…",
        "HTML Preview": "Pré-visualização HTML",
        "Model: %@": "Modelo: %@",
        "Disconnect": "Desconectar",
        "Connect to Gollama": "Conectar ao Gollama",
        "Private": "Privada",
        "Public": "Pública",
        "Connection": "Conexão",
        "Same Wi-Fi as your computer": "Mesmo Wi-Fi do seu computador",
        "Enter the computer's IP and the port Gollama's network server uses, or scan to find it.": "Insira o IP do computador e a porta do servidor de rede do Gollama, ou faça uma busca para encontrá-lo.",
        "Scan ports up to": "Verificar portas até",
        "No Gollama server found. Check the server is on and both devices share the same Wi-Fi.": "Nenhum servidor Gollama encontrado. Verifique se o servidor está ligado e se os dois dispositivos estão no mesmo Wi-Fi.",
        "Server or tunnel URL": "URL do servidor ou túnel",
        "Works with a public Gollama server or a Cloudflare Tunnel, for example https://name.trycloudflare.com.": "Funciona com um servidor Gollama público ou um túnel Cloudflare, por exemplo https://name.trycloudflare.com.",
        "Use a port": "Usar uma porta",
        "Connect": "Conectar",
        "Stop scanning": "Parar verificação",
        "Scan network": "Verificar rede",
        "Gollama Search": "Pesquisa Gollama",
        "Ask AI Mode": "Perguntar ao Modo IA",
        "Recent": "Recentes",
        "Delete": "Excluir",
        "Try": "Experimente",
        "Copy link": "Copiar link",
        "Showing results for": "Mostrando resultados para",
        "Search instead for %@": "Pesquisar por %@",
        "AI Overview": "Visão geral por IA",
        "Ask a follow-up": "Faça uma pergunta de acompanhamento",
        "Visit page": "Visitar página",
        "Share": "Compartilhar",
        "History": "Histórico",
        "Search chats": "Pesquisar conversas",
        "Clear all history": "Limpar todo o histórico",
        "Delete every chat on this device?": "Excluir todas as conversas deste dispositivo?",
        "Delete all": "Excluir tudo",
        "Ask anything": "Pergunte qualquer coisa",
        "AI Mode searches the web and answers with sources.": "O Modo IA pesquisa na web e responde com fontes.",
        "Message": "Mensagem",
        "Cancel": "Cancelar",
        "Submit": "Enviar",
        "That video isn't on this device anymore.": "Esse vídeo não está mais neste dispositivo.",
        "Branch in new chat": "Ramificar em nova conversa",
        "Try again without searching": "Tentar de novo sem pesquisar",
        "Copy as Markdown": "Copiar como Markdown",
        "Copy sources": "Copiar fontes",
        "Edit": "Editar",
        "Copy": "Copiar",
        "There isn't a result available for this search.": "Não há resultados disponíveis para esta pesquisa.",
        "You can still get an answer from the model, but it won't be backed by sources.": "Você ainda pode obter uma resposta do modelo, mas ela não terá fontes.",
        "Continue anyway": "Continuar mesmo assim",
        "Photos & Videos": "Fotos e vídeos",
        "Files": "Arquivos",
        "Model": "Modelo",
        "Fast": "Rápido",
        "Pro": "Pro",
        "Search": "Pesquisa",
        "AI Mode": "Modo IA",
        "Search or ask anything": "Pesquise ou pergunte qualquer coisa",
        "Copied": "Copiado",
        "Copied as Markdown": "Copiado como Markdown",
        "Sources copied": "Fontes copiadas",
        "Stop": "Parar",
        "Send": "Enviar",
        "Wait for the attachment to finish.": "Aguarde o anexo terminar.",
        "Couldn't read that video.": "Não foi possível ler esse vídeo.",
        "Couldn't read that photo.": "Não foi possível ler essa foto.",
        "%@ isn't a text file.": "%@ não é um arquivo de texto.",
        "Storage": "Armazenamento",
        "Clear cache": "Limpar cache",
        "Saved videos and cached images. Your chats stay on the server.": "Vídeos salvos e imagens em cache. Suas conversas ficam no servidor.",
        "Manage Storage": "Gerenciar armazenamento",
        "Save uploaded videos": "Salvar vídeos enviados",
        "Lets you watch a video again from the chat after you've sent it.": "Permite assistir a um vídeo de novo na conversa depois de enviá-lo.",
        "Video storage limit": "Limite de armazenamento de vídeos",
        "Keep videos for": "Manter vídeos por",
        "%d days": "%d dias",
        "1 day": "1 dia",
        "Forever": "Para sempre",
        "Image cache limit": "Limite do cache de imagens",
        "Off": "Desativado",
        "Images and web pages are kept so they load faster.": "Imagens e páginas da web são mantidas para carregar mais rápido.",
        "Saved videos": "Vídeos salvos",
        "Cache and temporary files": "Cache e arquivos temporários",
        "Total": "Total",
        "Clear saved videos": "Limpar vídeos salvos",
        "Usage": "Uso",
        "Your chats live on the server, so clearing storage never deletes them.": "Suas conversas ficam no servidor, então limpar o armazenamento nunca as exclui."
    ]
    static let nl: [String: String] = [
        "Settings": "Instellingen",
        "Appearance": "Weergave",
        "Auto": "Automatisch",
        "Light": "Licht",
        "Dark": "Donker",
        "Auto follows your device's appearance.": "Automatisch volgt de weergave van je apparaat.",
        "Language": "Taal",
        "System default": "Systeemstandaard",
        "Done": "Gereed",
        "Preview": "Voorbeeld",
        "Code": "Code",
        "View": "Weergave",
        "Writing the interactive block…": "Interactief blok wordt geschreven…",
        "HTML Preview": "HTML-voorbeeld",
        "Model: %@": "Model: %@",
        "Disconnect": "Verbinding verbreken",
        "Connect to Gollama": "Verbinden met Gollama",
        "Private": "Privé",
        "Public": "Openbaar",
        "Connection": "Verbinding",
        "Same Wi-Fi as your computer": "Zelfde wifi als je computer",
        "Enter the computer's IP and the port Gollama's network server uses, or scan to find it.": "Voer het IP-adres van de computer en de poort van Gollama's netwerkserver in, of scan om hem te vinden.",
        "Scan ports up to": "Poorten scannen tot",
        "No Gollama server found. Check the server is on and both devices share the same Wi-Fi.": "Geen Gollama-server gevonden. Controleer of de server aanstaat en beide apparaten hetzelfde wifi gebruiken.",
        "Server or tunnel URL": "Server- of tunnel-URL",
        "Works with a public Gollama server or a Cloudflare Tunnel, for example https://name.trycloudflare.com.": "Werkt met een openbare Gollama-server of een Cloudflare Tunnel, bijvoorbeeld https://name.trycloudflare.com.",
        "Use a port": "Poort gebruiken",
        "Connect": "Verbinden",
        "Stop scanning": "Scannen stoppen",
        "Scan network": "Netwerk scannen",
        "Gollama Search": "Gollama zoeken",
        "Ask AI Mode": "Vraag het AI-modus",
        "Recent": "Recent",
        "Delete": "Verwijderen",
        "Try": "Probeer",
        "Copy link": "Link kopiëren",
        "Showing results for": "Resultaten voor",
        "Search instead for %@": "Zoek in plaats daarvan naar %@",
        "AI Overview": "AI-overzicht",
        "Ask a follow-up": "Stel een vervolgvraag",
        "Visit page": "Pagina bezoeken",
        "Share": "Delen",
        "History": "Geschiedenis",
        "Search chats": "Chats zoeken",
        "Clear all history": "Alle geschiedenis wissen",
        "Delete every chat on this device?": "Alle chats op dit apparaat verwijderen?",
        "Delete all": "Alles verwijderen",
        "Ask anything": "Vraag maar raak",
        "AI Mode searches the web and answers with sources.": "AI-modus doorzoekt het web en antwoordt met bronnen.",
        "Message": "Bericht",
        "Cancel": "Annuleren",
        "Submit": "Verzenden",
        "That video isn't on this device anymore.": "Die video staat niet meer op dit apparaat.",
        "Branch in new chat": "Vertakken in nieuwe chat",
        "Try again without searching": "Opnieuw zonder zoeken",
        "Copy as Markdown": "Kopiëren als Markdown",
        "Copy sources": "Bronnen kopiëren",
        "Edit": "Bewerken",
        "Copy": "Kopiëren",
        "There isn't a result available for this search.": "Er is geen resultaat beschikbaar voor deze zoekopdracht.",
        "You can still get an answer from the model, but it won't be backed by sources.": "Je kunt nog steeds een antwoord van het model krijgen, maar zonder bronnen.",
        "Continue anyway": "Toch doorgaan",
        "Photos & Videos": "Foto's en video's",
        "Files": "Bestanden",
        "Model": "Model",
        "Fast": "Snel",
        "Pro": "Pro",
        "Search": "Zoeken",
        "AI Mode": "AI-modus",
        "Search or ask anything": "Zoek of vraag iets",
        "Copied": "Gekopieerd",
        "Copied as Markdown": "Gekopieerd als Markdown",
        "Sources copied": "Bronnen gekopieerd",
        "Stop": "Stoppen",
        "Send": "Verstuur",
        "Wait for the attachment to finish.": "Wacht tot de bijlage klaar is.",
        "Couldn't read that video.": "Kon die video niet lezen.",
        "Couldn't read that photo.": "Kon die foto niet lezen.",
        "%@ isn't a text file.": "%@ is geen tekstbestand.",
        "Storage": "Opslag",
        "Clear cache": "Cache wissen",
        "Saved videos and cached images. Your chats stay on the server.": "Opgeslagen video's en gecachete afbeeldingen. Je chats blijven op de server.",
        "Manage Storage": "Opslag beheren",
        "Save uploaded videos": "Geüploade video's bewaren",
        "Lets you watch a video again from the chat after you've sent it.": "Hiermee kun je een video na het versturen opnieuw bekijken in de chat.",
        "Video storage limit": "Opslaglimiet voor video's",
        "Keep videos for": "Video's bewaren gedurende",
        "%d days": "%d dagen",
        "1 day": "1 dag",
        "Forever": "Voor altijd",
        "Image cache limit": "Limiet voor afbeeldingscache",
        "Off": "Uit",
        "Images and web pages are kept so they load faster.": "Afbeeldingen en webpagina's worden bewaard zodat ze sneller laden.",
        "Saved videos": "Opgeslagen video's",
        "Cache and temporary files": "Cache en tijdelijke bestanden",
        "Total": "Totaal",
        "Clear saved videos": "Opgeslagen video's wissen",
        "Usage": "Gebruik",
        "Your chats live on the server, so clearing storage never deletes them.": "Je chats staan op de server, dus opslag wissen verwijdert ze nooit."
    ]
    static let sv: [String: String] = [
        "Settings": "Inställningar",
        "Appearance": "Utseende",
        "Auto": "Automatiskt",
        "Light": "Ljust",
        "Dark": "Mörkt",
        "Auto follows your device's appearance.": "Automatiskt följer enhetens utseende.",
        "Language": "Språk",
        "System default": "Systemstandard",
        "Done": "Klar",
        "Preview": "Förhandsgranskning",
        "Code": "Kod",
        "View": "Vy",
        "Writing the interactive block…": "Skriver det interaktiva blocket…",
        "HTML Preview": "HTML-förhandsgranskning",
        "Model: %@": "Modell: %@",
        "Disconnect": "Koppla från",
        "Connect to Gollama": "Anslut till Gollama",
        "Private": "Privat",
        "Public": "Offentlig",
        "Connection": "Anslutning",
        "Same Wi-Fi as your computer": "Samma Wi-Fi som din dator",
        "Enter the computer's IP and the port Gollama's network server uses, or scan to find it.": "Ange datorns IP-adress och porten som Gollamas nätverksserver använder, eller skanna för att hitta den.",
        "Scan ports up to": "Skanna portar upp till",
        "No Gollama server found. Check the server is on and both devices share the same Wi-Fi.": "Ingen Gollama-server hittades. Kontrollera att servern är på och att båda enheterna är på samma Wi-Fi.",
        "Server or tunnel URL": "Server- eller tunnel-URL",
        "Works with a public Gollama server or a Cloudflare Tunnel, for example https://name.trycloudflare.com.": "Fungerar med en offentlig Gollama-server eller en Cloudflare Tunnel, till exempel https://name.trycloudflare.com.",
        "Use a port": "Använd en port",
        "Connect": "Anslut",
        "Stop scanning": "Stoppa skanning",
        "Scan network": "Skanna nätverk",
        "Gollama Search": "Gollama-sökning",
        "Ask AI Mode": "Fråga AI-läget",
        "Recent": "Senaste",
        "Delete": "Radera",
        "Try": "Prova",
        "Copy link": "Kopiera länk",
        "Showing results for": "Visar resultat för",
        "Search instead for %@": "Sök istället efter %@",
        "AI Overview": "AI-översikt",
        "Ask a follow-up": "Ställ en följdfråga",
        "Visit page": "Besök sidan",
        "Share": "Dela",
        "History": "Historik",
        "Search chats": "Sök i chattar",
        "Clear all history": "Rensa all historik",
        "Delete every chat on this device?": "Radera alla chattar på den här enheten?",
        "Delete all": "Radera alla",
        "Ask anything": "Fråga vad som helst",
        "AI Mode searches the web and answers with sources.": "AI-läget söker på webben och svarar med källor.",
        "Message": "Meddelande",
        "Cancel": "Avbryt",
        "Submit": "Skicka",
        "That video isn't on this device anymore.": "Den videon finns inte kvar på den här enheten.",
        "Branch in new chat": "Förgrena i ny chatt",
        "Try again without searching": "Försök igen utan sökning",
        "Copy as Markdown": "Kopiera som Markdown",
        "Copy sources": "Kopiera källor",
        "Edit": "Redigera",
        "Copy": "Kopiera",
        "There isn't a result available for this search.": "Det finns inget resultat för den här sökningen.",
        "You can still get an answer from the model, but it won't be backed by sources.": "Du kan ändå få ett svar från modellen, men det saknar källor.",
        "Continue anyway": "Fortsätt ändå",
        "Photos & Videos": "Foton och videor",
        "Files": "Filer",
        "Model": "Modell",
        "Fast": "Snabb",
        "Pro": "Pro",
        "Search": "Sök",
        "AI Mode": "AI-läge",
        "Search or ask anything": "Sök eller fråga vad som helst",
        "Copied": "Kopierat",
        "Copied as Markdown": "Kopierat som Markdown",
        "Sources copied": "Källor kopierade",
        "Stop": "Stoppa",
        "Send": "Skicka",
        "Wait for the attachment to finish.": "Vänta tills bilagan är klar.",
        "Couldn't read that video.": "Det gick inte att läsa videon.",
        "Couldn't read that photo.": "Det gick inte att läsa fotot.",
        "%@ isn't a text file.": "%@ är inte en textfil.",
        "Storage": "Lagring",
        "Clear cache": "Rensa cache",
        "Saved videos and cached images. Your chats stay on the server.": "Sparade videor och cachade bilder. Dina chattar finns kvar på servern.",
        "Manage Storage": "Hantera lagring",
        "Save uploaded videos": "Spara uppladdade videor",
        "Lets you watch a video again from the chat after you've sent it.": "Låter dig se en video igen från chatten efter att du skickat den.",
        "Video storage limit": "Lagringsgräns för videor",
        "Keep videos for": "Behåll videor i",
        "%d days": "%d dagar",
        "1 day": "1 dag",
        "Forever": "För alltid",
        "Image cache limit": "Gräns för bildcache",
        "Off": "Av",
        "Images and web pages are kept so they load faster.": "Bilder och webbsidor sparas så att de laddas snabbare.",
        "Saved videos": "Sparade videor",
        "Cache and temporary files": "Cache och tillfälliga filer",
        "Total": "Totalt",
        "Clear saved videos": "Rensa sparade videor",
        "Usage": "Användning",
        "Your chats live on the server, so clearing storage never deletes them.": "Dina chattar finns på servern, så att rensa lagring tar aldrig bort dem."
    ]
    static let pl: [String: String] = [
        "Settings": "Ustawienia",
        "Appearance": "Wygląd",
        "Auto": "Automatycznie",
        "Light": "Jasny",
        "Dark": "Ciemny",
        "Auto follows your device's appearance.": "Automatycznie dopasowuje się do wyglądu urządzenia.",
        "Language": "Język",
        "System default": "Domyślny systemu",
        "Done": "Gotowe",
        "Preview": "Podgląd",
        "Code": "Kod",
        "View": "Widok",
        "Writing the interactive block…": "Tworzenie bloku interaktywnego…",
        "HTML Preview": "Podgląd HTML",
        "Model: %@": "Model: %@",
        "Disconnect": "Rozłącz",
        "Connect to Gollama": "Połącz z Gollama",
        "Private": "Prywatna",
        "Public": "Publiczna",
        "Connection": "Połączenie",
        "Same Wi-Fi as your computer": "Ta sama sieć Wi-Fi co komputer",
        "Enter the computer's IP and the port Gollama's network server uses, or scan to find it.": "Wpisz adres IP komputera i port serwera sieciowego Gollama lub przeskanuj sieć, aby go znaleźć.",
        "Scan ports up to": "Skanuj porty do",
        "No Gollama server found. Check the server is on and both devices share the same Wi-Fi.": "Nie znaleziono serwera Gollama. Sprawdź, czy serwer jest włączony, a oba urządzenia są w tej samej sieci Wi-Fi.",
        "Server or tunnel URL": "Adres URL serwera lub tunelu",
        "Works with a public Gollama server or a Cloudflare Tunnel, for example https://name.trycloudflare.com.": "Działa z publicznym serwerem Gollama lub tunelem Cloudflare, na przykład https://name.trycloudflare.com.",
        "Use a port": "Użyj portu",
        "Connect": "Połącz",
        "Stop scanning": "Zatrzymaj skanowanie",
        "Scan network": "Skanuj sieć",
        "Gollama Search": "Szukaj w Gollama",
        "Ask AI Mode": "Zapytaj tryb AI",
        "Recent": "Ostatnie",
        "Delete": "Usuń",
        "Try": "Wypróbuj",
        "Copy link": "Kopiuj link",
        "Showing results for": "Wyniki dla",
        "Search instead for %@": "Szukaj zamiast tego: %@",
        "AI Overview": "Przegląd AI",
        "Ask a follow-up": "Zadaj pytanie uzupełniające",
        "Visit page": "Odwiedź stronę",
        "Share": "Udostępnij",
        "History": "Historia",
        "Search chats": "Szukaj w czatach",
        "Clear all history": "Wyczyść całą historię",
        "Delete every chat on this device?": "Usunąć wszystkie czaty z tego urządzenia?",
        "Delete all": "Usuń wszystko",
        "Ask anything": "Zapytaj o cokolwiek",
        "AI Mode searches the web and answers with sources.": "Tryb AI przeszukuje internet i odpowiada ze źródłami.",
        "Message": "Wiadomość",
        "Cancel": "Anuluj",
        "Submit": "Wyślij",
        "That video isn't on this device anymore.": "Tego filmu nie ma już na tym urządzeniu.",
        "Branch in new chat": "Rozgałęź w nowym czacie",
        "Try again without searching": "Spróbuj ponownie bez wyszukiwania",
        "Copy as Markdown": "Kopiuj jako Markdown",
        "Copy sources": "Kopiuj źródła",
        "Edit": "Edytuj",
        "Copy": "Kopiuj",
        "There isn't a result available for this search.": "Brak wyników dla tego wyszukiwania.",
        "You can still get an answer from the model, but it won't be backed by sources.": "Nadal możesz otrzymać odpowiedź od modelu, ale bez źródeł.",
        "Continue anyway": "Kontynuuj mimo to",
        "Photos & Videos": "Zdjęcia i filmy",
        "Files": "Pliki",
        "Model": "Model",
        "Fast": "Szybki",
        "Pro": "Pro",
        "Search": "Szukaj",
        "AI Mode": "Tryb AI",
        "Search or ask anything": "Szukaj lub zapytaj o cokolwiek",
        "Copied": "Skopiowano",
        "Copied as Markdown": "Skopiowano jako Markdown",
        "Sources copied": "Skopiowano źródła",
        "Stop": "Zatrzymaj",
        "Send": "Wyślij",
        "Wait for the attachment to finish.": "Poczekaj na zakończenie przesyłania załącznika.",
        "Couldn't read that video.": "Nie udało się odczytać tego filmu.",
        "Couldn't read that photo.": "Nie udało się odczytać tego zdjęcia.",
        "%@ isn't a text file.": "%@ nie jest plikiem tekstowym.",
        "Storage": "Pamięć",
        "Clear cache": "Wyczyść pamięć podręczną",
        "Saved videos and cached images. Your chats stay on the server.": "Zapisane filmy i obrazy w pamięci podręcznej. Czaty pozostają na serwerze.",
        "Manage Storage": "Zarządzaj pamięcią",
        "Save uploaded videos": "Zapisuj przesłane filmy",
        "Lets you watch a video again from the chat after you've sent it.": "Pozwala ponownie obejrzeć film z czatu po jego wysłaniu.",
        "Video storage limit": "Limit miejsca na filmy",
        "Keep videos for": "Przechowuj filmy przez",
        "%d days": "%d dni",
        "1 day": "1 dzień",
        "Forever": "Bezterminowo",
        "Image cache limit": "Limit pamięci podręcznej obrazów",
        "Off": "Wyłączone",
        "Images and web pages are kept so they load faster.": "Obrazy i strony internetowe są zapisywane, aby ładowały się szybciej.",
        "Saved videos": "Zapisane filmy",
        "Cache and temporary files": "Pamięć podręczna i pliki tymczasowe",
        "Total": "Razem",
        "Clear saved videos": "Usuń zapisane filmy",
        "Usage": "Wykorzystanie",
        "Your chats live on the server, so clearing storage never deletes them.": "Twoje czaty są na serwerze, więc czyszczenie pamięci nigdy ich nie usuwa."
    ]
    static let tr: [String: String] = [
        "Settings": "Ayarlar",
        "Appearance": "Görünüm",
        "Auto": "Otomatik",
        "Light": "Açık",
        "Dark": "Koyu",
        "Auto follows your device's appearance.": "Otomatik, cihazınızın görünümünü takip eder.",
        "Language": "Dil",
        "System default": "Sistem varsayılanı",
        "Done": "Bitti",
        "Preview": "Önizleme",
        "Code": "Kod",
        "View": "Görünüm",
        "Writing the interactive block…": "Etkileşimli blok yazılıyor…",
        "HTML Preview": "HTML Önizleme",
        "Model: %@": "Model: %@",
        "Disconnect": "Bağlantıyı kes",
        "Connect to Gollama": "Gollama'ya bağlan",
        "Private": "Özel",
        "Public": "Genel",
        "Connection": "Bağlantı",
        "Same Wi-Fi as your computer": "Bilgisayarınızla aynı Wi-Fi",
        "Enter the computer's IP and the port Gollama's network server uses, or scan to find it.": "Bilgisayarın IP adresini ve Gollama ağ sunucusunun kullandığı bağlantı noktasını girin veya bulmak için tarayın.",
        "Scan ports up to": "Taranacak son bağlantı noktası",
        "No Gollama server found. Check the server is on and both devices share the same Wi-Fi.": "Gollama sunucusu bulunamadı. Sunucunun açık olduğunu ve iki cihazın aynı Wi-Fi'da olduğunu kontrol edin.",
        "Server or tunnel URL": "Sunucu veya tünel URL'si",
        "Works with a public Gollama server or a Cloudflare Tunnel, for example https://name.trycloudflare.com.": "Genel bir Gollama sunucusu veya Cloudflare Tunnel ile çalışır, örneğin https://name.trycloudflare.com.",
        "Use a port": "Bağlantı noktası kullan",
        "Connect": "Bağlan",
        "Stop scanning": "Taramayı durdur",
        "Scan network": "Ağı tara",
        "Gollama Search": "Gollama Arama",
        "Ask AI Mode": "AI Modu'na sor",
        "Recent": "Son",
        "Delete": "Sil",
        "Try": "Deneyin",
        "Copy link": "Bağlantıyı kopyala",
        "Showing results for": "Şunun için sonuçlar gösteriliyor:",
        "Search instead for %@": "Bunun yerine şunu ara: %@",
        "AI Overview": "AI Genel Bakışı",
        "Ask a follow-up": "Devam sorusu sor",
        "Visit page": "Sayfayı ziyaret et",
        "Share": "Paylaş",
        "History": "Geçmiş",
        "Search chats": "Sohbetlerde ara",
        "Clear all history": "Tüm geçmişi temizle",
        "Delete every chat on this device?": "Bu cihazdaki tüm sohbetler silinsin mi?",
        "Delete all": "Tümünü sil",
        "Ask anything": "Her şeyi sorun",
        "AI Mode searches the web and answers with sources.": "AI Modu web'de arama yapar ve kaynaklarla yanıt verir.",
        "Message": "Mesaj",
        "Cancel": "İptal",
        "Submit": "Gönder",
        "That video isn't on this device anymore.": "Bu video artık bu cihazda değil.",
        "Branch in new chat": "Yeni sohbette dallandır",
        "Try again without searching": "Aramadan tekrar dene",
        "Copy as Markdown": "Markdown olarak kopyala",
        "Copy sources": "Kaynakları kopyala",
        "Edit": "Düzenle",
        "Copy": "Kopyala",
        "There isn't a result available for this search.": "Bu arama için sonuç yok.",
        "You can still get an answer from the model, but it won't be backed by sources.": "Yine de modelden yanıt alabilirsiniz ancak kaynaklarla desteklenmez.",
        "Continue anyway": "Yine de devam et",
        "Photos & Videos": "Fotoğraflar ve Videolar",
        "Files": "Dosyalar",
        "Model": "Model",
        "Fast": "Hızlı",
        "Pro": "Pro",
        "Search": "Ara",
        "AI Mode": "AI Modu",
        "Search or ask anything": "Arayın veya her şeyi sorun",
        "Copied": "Kopyalandı",
        "Copied as Markdown": "Markdown olarak kopyalandı",
        "Sources copied": "Kaynaklar kopyalandı",
        "Stop": "Durdur",
        "Send": "Gönder",
        "Wait for the attachment to finish.": "Ek dosyanın işlenmesinin bitmesini bekleyin.",
        "Couldn't read that video.": "Video okunamadı.",
        "Couldn't read that photo.": "Fotoğraf okunamadı.",
        "%@ isn't a text file.": "%@ bir metin dosyası değil.",
        "Storage": "Depolama",
        "Clear cache": "Önbelleği temizle",
        "Saved videos and cached images. Your chats stay on the server.": "Kaydedilen videolar ve önbelleğe alınan görseller. Sohbetleriniz sunucuda kalır.",
        "Manage Storage": "Depolamayı yönet",
        "Save uploaded videos": "Yüklenen videoları kaydet",
        "Lets you watch a video again from the chat after you've sent it.": "Gönderdikten sonra videoyu sohbetten tekrar izlemenizi sağlar.",
        "Video storage limit": "Video depolama sınırı",
        "Keep videos for": "Videoları saklama süresi",
        "%d days": "%d gün",
        "1 day": "1 gün",
        "Forever": "Süresiz",
        "Image cache limit": "Görsel önbellek sınırı",
        "Off": "Kapalı",
        "Images and web pages are kept so they load faster.": "Görseller ve web sayfaları daha hızlı yüklensin diye saklanır.",
        "Saved videos": "Kaydedilen videolar",
        "Cache and temporary files": "Önbellek ve geçici dosyalar",
        "Total": "Toplam",
        "Clear saved videos": "Kaydedilen videoları temizle",
        "Usage": "Kullanım",
        "Your chats live on the server, so clearing storage never deletes them.": "Sohbetleriniz sunucuda durur; depolamayı temizlemek onları asla silmez."
    ]
    static let ru: [String: String] = [
        "Settings": "Настройки",
        "Appearance": "Оформление",
        "Auto": "Авто",
        "Light": "Светлая",
        "Dark": "Тёмная",
        "Auto follows your device's appearance.": "Авто следует оформлению устройства.",
        "Language": "Язык",
        "System default": "Как в системе",
        "Done": "Готово",
        "Preview": "Просмотр",
        "Code": "Код",
        "View": "Вид",
        "Writing the interactive block…": "Создаётся интерактивный блок…",
        "HTML Preview": "Просмотр HTML",
        "Model: %@": "Модель: %@",
        "Disconnect": "Отключиться",
        "Connect to Gollama": "Подключение к Gollama",
        "Private": "Частная",
        "Public": "Публичная",
        "Connection": "Подключение",
        "Same Wi-Fi as your computer": "Та же сеть Wi-Fi, что и у компьютера",
        "Enter the computer's IP and the port Gollama's network server uses, or scan to find it.": "Введите IP-адрес компьютера и порт сетевого сервера Gollama или запустите сканирование.",
        "Scan ports up to": "Сканировать порты до",
        "No Gollama server found. Check the server is on and both devices share the same Wi-Fi.": "Сервер Gollama не найден. Убедитесь, что сервер включён, а оба устройства подключены к одной сети Wi-Fi.",
        "Server or tunnel URL": "URL сервера или туннеля",
        "Works with a public Gollama server or a Cloudflare Tunnel, for example https://name.trycloudflare.com.": "Работает с публичным сервером Gollama или туннелем Cloudflare, например https://name.trycloudflare.com.",
        "Use a port": "Указать порт",
        "Connect": "Подключиться",
        "Stop scanning": "Остановить сканирование",
        "Scan network": "Сканировать сеть",
        "Gollama Search": "Поиск Gollama",
        "Ask AI Mode": "Спросить в режиме ИИ",
        "Recent": "Недавние",
        "Delete": "Удалить",
        "Try": "Попробуйте",
        "Copy link": "Копировать ссылку",
        "Showing results for": "Показаны результаты по запросу",
        "Search instead for %@": "Искать вместо этого: %@",
        "AI Overview": "Обзор от ИИ",
        "Ask a follow-up": "Задать уточняющий вопрос",
        "Visit page": "Открыть страницу",
        "Share": "Поделиться",
        "History": "История",
        "Search chats": "Поиск по чатам",
        "Clear all history": "Очистить всю историю",
        "Delete every chat on this device?": "Удалить все чаты на этом устройстве?",
        "Delete all": "Удалить все",
        "Ask anything": "Спрашивайте что угодно",
        "AI Mode searches the web and answers with sources.": "Режим ИИ ищет в интернете и отвечает со ссылками на источники.",
        "Message": "Сообщение",
        "Cancel": "Отмена",
        "Submit": "Отправить",
        "That video isn't on this device anymore.": "Этого видео больше нет на устройстве.",
        "Branch in new chat": "Ответвить в новый чат",
        "Try again without searching": "Повторить без поиска",
        "Copy as Markdown": "Копировать как Markdown",
        "Copy sources": "Копировать источники",
        "Edit": "Изменить",
        "Copy": "Копировать",
        "There isn't a result available for this search.": "По этому запросу нет результатов.",
        "You can still get an answer from the model, but it won't be backed by sources.": "Вы всё равно можете получить ответ модели, но без источников.",
        "Continue anyway": "Всё равно продолжить",
        "Photos & Videos": "Фото и видео",
        "Files": "Файлы",
        "Model": "Модель",
        "Fast": "Быстрая",
        "Pro": "Pro",
        "Search": "Поиск",
        "AI Mode": "Режим ИИ",
        "Search or ask anything": "Введите запрос или вопрос",
        "Copied": "Скопировано",
        "Copied as Markdown": "Скопировано как Markdown",
        "Sources copied": "Источники скопированы",
        "Stop": "Остановить",
        "Send": "Отправить",
        "Wait for the attachment to finish.": "Дождитесь завершения загрузки вложения.",
        "Couldn't read that video.": "Не удалось прочитать видео.",
        "Couldn't read that photo.": "Не удалось прочитать фото.",
        "%@ isn't a text file.": "%@ не является текстовым файлом.",
        "Storage": "Хранилище",
        "Clear cache": "Очистить кэш",
        "Saved videos and cached images. Your chats stay on the server.": "Сохранённые видео и кэшированные изображения. Чаты остаются на сервере.",
        "Manage Storage": "Управление хранилищем",
        "Save uploaded videos": "Сохранять загруженные видео",
        "Lets you watch a video again from the chat after you've sent it.": "Позволяет пересмотреть видео в чате после отправки.",
        "Video storage limit": "Лимит памяти для видео",
        "Keep videos for": "Хранить видео",
        "%d days": "%d дн.",
        "1 day": "1 день",
        "Forever": "Всегда",
        "Image cache limit": "Лимит кэша изображений",
        "Off": "Выкл.",
        "Images and web pages are kept so they load faster.": "Изображения и веб-страницы сохраняются, чтобы загружаться быстрее.",
        "Saved videos": "Сохранённые видео",
        "Cache and temporary files": "Кэш и временные файлы",
        "Total": "Итого",
        "Clear saved videos": "Удалить сохранённые видео",
        "Usage": "Использование",
        "Your chats live on the server, so clearing storage never deletes them.": "Ваши чаты хранятся на сервере, поэтому очистка хранилища их не удаляет."
    ]
    static let uk: [String: String] = [
        "Settings": "Налаштування",
        "Appearance": "Вигляд",
        "Auto": "Авто",
        "Light": "Світла",
        "Dark": "Темна",
        "Auto follows your device's appearance.": "Авто відповідає вигляду пристрою.",
        "Language": "Мова",
        "System default": "Як у системі",
        "Done": "Готово",
        "Preview": "Перегляд",
        "Code": "Код",
        "View": "Вигляд",
        "Writing the interactive block…": "Створюється інтерактивний блок…",
        "HTML Preview": "Перегляд HTML",
        "Model: %@": "Модель: %@",
        "Disconnect": "Від’єднатися",
        "Connect to Gollama": "Підключення до Gollama",
        "Private": "Приватна",
        "Public": "Публічна",
        "Connection": "Підключення",
        "Same Wi-Fi as your computer": "Та сама мережа Wi-Fi, що й комп’ютер",
        "Enter the computer's IP and the port Gollama's network server uses, or scan to find it.": "Введіть IP-адресу комп’ютера та порт мережевого сервера Gollama або скористайтеся скануванням.",
        "Scan ports up to": "Сканувати порти до",
        "No Gollama server found. Check the server is on and both devices share the same Wi-Fi.": "Сервер Gollama не знайдено. Переконайтеся, що сервер увімкнено, а обидва пристрої в одній мережі Wi-Fi.",
        "Server or tunnel URL": "URL сервера або тунелю",
        "Works with a public Gollama server or a Cloudflare Tunnel, for example https://name.trycloudflare.com.": "Працює з публічним сервером Gollama або тунелем Cloudflare, наприклад https://name.trycloudflare.com.",
        "Use a port": "Вказати порт",
        "Connect": "Підключитися",
        "Stop scanning": "Зупинити сканування",
        "Scan network": "Сканувати мережу",
        "Gollama Search": "Пошук Gollama",
        "Ask AI Mode": "Запитати в режимі ШІ",
        "Recent": "Нещодавні",
        "Delete": "Видалити",
        "Try": "Спробуйте",
        "Copy link": "Копіювати посилання",
        "Showing results for": "Показано результати для",
        "Search instead for %@": "Шукати натомість: %@",
        "AI Overview": "Огляд від ШІ",
        "Ask a follow-up": "Поставити уточнювальне запитання",
        "Visit page": "Відкрити сторінку",
        "Share": "Поділитися",
        "History": "Історія",
        "Search chats": "Пошук у чатах",
        "Clear all history": "Очистити всю історію",
        "Delete every chat on this device?": "Видалити всі чати на цьому пристрої?",
        "Delete all": "Видалити все",
        "Ask anything": "Запитуйте будь-що",
        "AI Mode searches the web and answers with sources.": "Режим ШІ шукає в інтернеті й відповідає з посиланнями на джерела.",
        "Message": "Повідомлення",
        "Cancel": "Скасувати",
        "Submit": "Надіслати",
        "That video isn't on this device anymore.": "Цього відео більше немає на пристрої.",
        "Branch in new chat": "Відгалузити в новий чат",
        "Try again without searching": "Повторити без пошуку",
        "Copy as Markdown": "Копіювати як Markdown",
        "Copy sources": "Копіювати джерела",
        "Edit": "Редагувати",
        "Copy": "Копіювати",
        "There isn't a result available for this search.": "За цим запитом немає результатів.",
        "You can still get an answer from the model, but it won't be backed by sources.": "Ви все одно можете отримати відповідь моделі, але без джерел.",
        "Continue anyway": "Все одно продовжити",
        "Photos & Videos": "Фото та відео",
        "Files": "Файли",
        "Model": "Модель",
        "Fast": "Швидка",
        "Pro": "Pro",
        "Search": "Пошук",
        "AI Mode": "Режим ШІ",
        "Search or ask anything": "Введіть запит або запитання",
        "Copied": "Скопійовано",
        "Copied as Markdown": "Скопійовано як Markdown",
        "Sources copied": "Джерела скопійовано",
        "Stop": "Зупинити",
        "Send": "Надіслати",
        "Wait for the attachment to finish.": "Дочекайтеся завершення завантаження вкладення.",
        "Couldn't read that video.": "Не вдалося прочитати відео.",
        "Couldn't read that photo.": "Не вдалося прочитати фото.",
        "%@ isn't a text file.": "%@ не є текстовим файлом.",
        "Storage": "Сховище",
        "Clear cache": "Очистити кеш",
        "Saved videos and cached images. Your chats stay on the server.": "Збережені відео та кешовані зображення. Чати залишаються на сервері.",
        "Manage Storage": "Керування сховищем",
        "Save uploaded videos": "Зберігати завантажені відео",
        "Lets you watch a video again from the chat after you've sent it.": "Дозволяє переглянути відео в чаті ще раз після надсилання.",
        "Video storage limit": "Ліміт сховища для відео",
        "Keep videos for": "Зберігати відео",
        "%d days": "%d дн.",
        "1 day": "1 день",
        "Forever": "Завжди",
        "Image cache limit": "Ліміт кешу зображень",
        "Off": "Вимк.",
        "Images and web pages are kept so they load faster.": "Зображення та вебсторінки зберігаються, щоб завантажуватися швидше.",
        "Saved videos": "Збережені відео",
        "Cache and temporary files": "Кеш і тимчасові файли",
        "Total": "Разом",
        "Clear saved videos": "Видалити збережені відео",
        "Usage": "Використання",
        "Your chats live on the server, so clearing storage never deletes them.": "Ваші чати зберігаються на сервері, тож очищення сховища їх не видаляє."
    ]
    static let ar: [String: String] = [
        "Settings": "الإعدادات",
        "Appearance": "المظهر",
        "Auto": "تلقائي",
        "Light": "فاتح",
        "Dark": "داكن",
        "Auto follows your device's appearance.": "الوضع التلقائي يتبع مظهر جهازك.",
        "Language": "اللغة",
        "System default": "افتراضي النظام",
        "Done": "تم",
        "Preview": "معاينة",
        "Code": "الشيفرة",
        "View": "عرض",
        "Writing the interactive block…": "جارٍ كتابة الكتلة التفاعلية…",
        "HTML Preview": "معاينة HTML",
        "Model: %@": "النموذج: %@",
        "Disconnect": "قطع الاتصال",
        "Connect to Gollama": "الاتصال بـ Gollama",
        "Private": "خاصة",
        "Public": "عامة",
        "Connection": "الاتصال",
        "Same Wi-Fi as your computer": "نفس شبكة Wi-Fi للكمبيوتر",
        "Enter the computer's IP and the port Gollama's network server uses, or scan to find it.": "أدخل عنوان IP للكمبيوتر والمنفذ الذي يستخدمه خادم الشبكة في Gollama، أو امسح الشبكة للعثور عليه.",
        "Scan ports up to": "فحص المنافذ حتى",
        "No Gollama server found. Check the server is on and both devices share the same Wi-Fi.": "لم يتم العثور على خادم Gollama. تأكد من تشغيل الخادم ومن اتصال الجهازين بنفس شبكة Wi-Fi.",
        "Server or tunnel URL": "عنوان URL للخادم أو النفق",
        "Works with a public Gollama server or a Cloudflare Tunnel, for example https://name.trycloudflare.com.": "يعمل مع خادم Gollama عام أو نفق Cloudflare، مثل https://name.trycloudflare.com.",
        "Use a port": "استخدام منفذ",
        "Connect": "اتصال",
        "Stop scanning": "إيقاف الفحص",
        "Scan network": "فحص الشبكة",
        "Gollama Search": "بحث Gollama",
        "Ask AI Mode": "اسأل وضع الذكاء الاصطناعي",
        "Recent": "الأخيرة",
        "Delete": "حذف",
        "Try": "جرّب",
        "Copy link": "نسخ الرابط",
        "Showing results for": "عرض النتائج لـ",
        "Search instead for %@": "البحث عن %@ بدلاً من ذلك",
        "AI Overview": "نظرة عامة بالذكاء الاصطناعي",
        "Ask a follow-up": "اطرح سؤالاً متابعاً",
        "Visit page": "زيارة الصفحة",
        "Share": "مشاركة",
        "History": "السجل",
        "Search chats": "البحث في المحادثات",
        "Clear all history": "مسح كل السجل",
        "Delete every chat on this device?": "هل تريد حذف كل المحادثات على هذا الجهاز؟",
        "Delete all": "حذف الكل",
        "Ask anything": "اسأل أي شيء",
        "AI Mode searches the web and answers with sources.": "يبحث وضع الذكاء الاصطناعي في الويب ويجيب مع المصادر.",
        "Message": "رسالة",
        "Cancel": "إلغاء",
        "Submit": "إرسال",
        "That video isn't on this device anymore.": "لم يعد هذا الفيديو موجوداً على هذا الجهاز.",
        "Branch in new chat": "تفريع في محادثة جديدة",
        "Try again without searching": "إعادة المحاولة دون بحث",
        "Copy as Markdown": "نسخ بصيغة Markdown",
        "Copy sources": "نسخ المصادر",
        "Edit": "تعديل",
        "Copy": "نسخ",
        "There isn't a result available for this search.": "لا توجد نتيجة متاحة لهذا البحث.",
        "You can still get an answer from the model, but it won't be backed by sources.": "لا يزال بإمكانك الحصول على إجابة من النموذج، لكنها لن تستند إلى مصادر.",
        "Continue anyway": "المتابعة على أي حال",
        "Photos & Videos": "الصور والفيديوهات",
        "Files": "الملفات",
        "Model": "النموذج",
        "Fast": "سريع",
        "Pro": "احترافي",
        "Search": "بحث",
        "AI Mode": "وضع الذكاء الاصطناعي",
        "Search or ask anything": "ابحث أو اسأل أي شيء",
        "Copied": "تم النسخ",
        "Copied as Markdown": "تم النسخ بصيغة Markdown",
        "Sources copied": "تم نسخ المصادر",
        "Stop": "إيقاف",
        "Send": "إرسال",
        "Wait for the attachment to finish.": "انتظر حتى يكتمل المرفق.",
        "Couldn't read that video.": "تعذّرت قراءة هذا الفيديو.",
        "Couldn't read that photo.": "تعذّرت قراءة هذه الصورة.",
        "%@ isn't a text file.": "%@ ليس ملفاً نصياً.",
        "Storage": "التخزين",
        "Clear cache": "مسح ذاكرة التخزين المؤقت",
        "Saved videos and cached images. Your chats stay on the server.": "مقاطع الفيديو المحفوظة والصور المخزنة مؤقتاً. تبقى محادثاتك على الخادم.",
        "Manage Storage": "إدارة التخزين",
        "Save uploaded videos": "حفظ الفيديوهات المرفوعة",
        "Lets you watch a video again from the chat after you've sent it.": "يتيح لك مشاهدة الفيديو مرة أخرى من المحادثة بعد إرساله.",
        "Video storage limit": "حد تخزين الفيديو",
        "Keep videos for": "الاحتفاظ بالفيديوهات لمدة",
        "%d days": "%d يوم",
        "1 day": "يوم واحد",
        "Forever": "دائماً",
        "Image cache limit": "حد ذاكرة الصور المؤقتة",
        "Off": "إيقاف",
        "Images and web pages are kept so they load faster.": "تُحفظ الصور وصفحات الويب لتحميلها بشكل أسرع.",
        "Saved videos": "الفيديوهات المحفوظة",
        "Cache and temporary files": "ذاكرة التخزين المؤقت والملفات المؤقتة",
        "Total": "الإجمالي",
        "Clear saved videos": "مسح الفيديوهات المحفوظة",
        "Usage": "الاستخدام",
        "Your chats live on the server, so clearing storage never deletes them.": "محادثاتك محفوظة على الخادم، لذا لا يؤدي مسح التخزين إلى حذفها أبداً."
    ]
    static let he: [String: String] = [
        "Settings": "הגדרות",
        "Appearance": "מראה",
        "Auto": "אוטומטי",
        "Light": "בהיר",
        "Dark": "כהה",
        "Auto follows your device's appearance.": "אוטומטי עוקב אחר מראה המכשיר.",
        "Language": "שפה",
        "System default": "ברירת מחדל של המערכת",
        "Done": "סיום",
        "Preview": "תצוגה מקדימה",
        "Code": "קוד",
        "View": "תצוגה",
        "Writing the interactive block…": "כותב את הבלוק האינטראקטיבי…",
        "HTML Preview": "תצוגת HTML מקדימה",
        "Model: %@": "מודל: %@",
        "Disconnect": "התנתק",
        "Connect to Gollama": "התחברות ל-Gollama",
        "Private": "פרטית",
        "Public": "ציבורית",
        "Connection": "חיבור",
        "Same Wi-Fi as your computer": "אותה רשת Wi-Fi כמו המחשב",
        "Enter the computer's IP and the port Gollama's network server uses, or scan to find it.": "הזינו את כתובת ה-IP של המחשב ואת היציאה שבה שרת הרשת של Gollama משתמש, או סרקו כדי למצוא אותו.",
        "Scan ports up to": "סרוק יציאות עד",
        "No Gollama server found. Check the server is on and both devices share the same Wi-Fi.": "לא נמצא שרת Gollama. ודאו שהשרת פועל ושני המכשירים מחוברים לאותה רשת Wi-Fi.",
        "Server or tunnel URL": "כתובת URL של שרת או מנהרה",
        "Works with a public Gollama server or a Cloudflare Tunnel, for example https://name.trycloudflare.com.": "עובד עם שרת Gollama ציבורי או מנהרת Cloudflare, למשל https://name.trycloudflare.com.",
        "Use a port": "שימוש ביציאה",
        "Connect": "התחבר",
        "Stop scanning": "עצור סריקה",
        "Scan network": "סרוק רשת",
        "Gollama Search": "חיפוש Gollama",
        "Ask AI Mode": "שאל את מצב AI",
        "Recent": "אחרונים",
        "Delete": "מחק",
        "Try": "נסו",
        "Copy link": "העתק קישור",
        "Showing results for": "מציג תוצאות עבור",
        "Search instead for %@": "חפש במקום זאת %@",
        "AI Overview": "סקירת AI",
        "Ask a follow-up": "שאל שאלת המשך",
        "Visit page": "בקר בדף",
        "Share": "שתף",
        "History": "היסטוריה",
        "Search chats": "חפש בצ'אטים",
        "Clear all history": "נקה את כל ההיסטוריה",
        "Delete every chat on this device?": "למחוק את כל הצ'אטים במכשיר זה?",
        "Delete all": "מחק הכל",
        "Ask anything": "שאל כל דבר",
        "AI Mode searches the web and answers with sources.": "מצב AI מחפש ברשת ועונה עם מקורות.",
        "Message": "הודעה",
        "Cancel": "ביטול",
        "Submit": "שלח",
        "That video isn't on this device anymore.": "הסרטון הזה כבר לא נמצא במכשיר.",
        "Branch in new chat": "הסתעף בצ'אט חדש",
        "Try again without searching": "נסה שוב בלי חיפוש",
        "Copy as Markdown": "העתק כ-Markdown",
        "Copy sources": "העתק מקורות",
        "Edit": "ערוך",
        "Copy": "העתק",
        "There isn't a result available for this search.": "אין תוצאה זמינה עבור החיפוש הזה.",
        "You can still get an answer from the model, but it won't be backed by sources.": "עדיין אפשר לקבל תשובה מהמודל, אך היא לא תתבסס על מקורות.",
        "Continue anyway": "המשך בכל זאת",
        "Photos & Videos": "תמונות וסרטונים",
        "Files": "קבצים",
        "Model": "מודל",
        "Fast": "מהיר",
        "Pro": "Pro",
        "Search": "חיפוש",
        "AI Mode": "מצב AI",
        "Search or ask anything": "חפש או שאל כל דבר",
        "Copied": "הועתק",
        "Copied as Markdown": "הועתק כ-Markdown",
        "Sources copied": "המקורות הועתקו",
        "Stop": "עצור",
        "Send": "שלח",
        "Wait for the attachment to finish.": "המתן לסיום טעינת הקובץ המצורף.",
        "Couldn't read that video.": "לא ניתן לקרוא את הסרטון.",
        "Couldn't read that photo.": "לא ניתן לקרוא את התמונה.",
        "%@ isn't a text file.": "%@ אינו קובץ טקסט.",
        "Storage": "אחסון",
        "Clear cache": "נקה מטמון",
        "Saved videos and cached images. Your chats stay on the server.": "סרטונים שמורים ותמונות במטמון. הצ'אטים שלך נשארים בשרת.",
        "Manage Storage": "ניהול אחסון",
        "Save uploaded videos": "שמור סרטונים שהועלו",
        "Lets you watch a video again from the chat after you've sent it.": "מאפשר לצפות שוב בסרטון מהצ'אט אחרי ששלחת אותו.",
        "Video storage limit": "מגבלת אחסון לסרטונים",
        "Keep videos for": "שמור סרטונים למשך",
        "%d days": "%d ימים",
        "1 day": "יום אחד",
        "Forever": "ללא הגבלה",
        "Image cache limit": "מגבלת מטמון תמונות",
        "Off": "כבוי",
        "Images and web pages are kept so they load faster.": "תמונות ודפי אינטרנט נשמרים כדי שייטענו מהר יותר.",
        "Saved videos": "סרטונים שמורים",
        "Cache and temporary files": "מטמון וקבצים זמניים",
        "Total": "סה״כ",
        "Clear saved videos": "מחק סרטונים שמורים",
        "Usage": "שימוש",
        "Your chats live on the server, so clearing storage never deletes them.": "הצ'אטים שלך נשמרים בשרת, ולכן ניקוי האחסון לא מוחק אותם לעולם."
    ]
    static let hi: [String: String] = [
        "Settings": "सेटिंग्स",
        "Appearance": "दिखावट",
        "Auto": "स्वचालित",
        "Light": "लाइट",
        "Dark": "डार्क",
        "Auto follows your device's appearance.": "स्वचालित आपके डिवाइस के अनुसार चलता है।",
        "Language": "भाषा",
        "System default": "सिस्टम डिफ़ॉल्ट",
        "Done": "पूर्ण",
        "Preview": "पूर्वावलोकन",
        "Code": "कोड",
        "View": "दृश्य",
        "Writing the interactive block…": "इंटरैक्टिव ब्लॉक लिखा जा रहा है…",
        "HTML Preview": "HTML पूर्वावलोकन",
        "Model: %@": "मॉडल: %@",
        "Disconnect": "डिस्कनेक्ट करें",
        "Connect to Gollama": "Gollama से कनेक्ट करें",
        "Private": "निजी",
        "Public": "सार्वजनिक",
        "Connection": "कनेक्शन",
        "Same Wi-Fi as your computer": "आपके कंप्यूटर वाला ही Wi-Fi",
        "Enter the computer's IP and the port Gollama's network server uses, or scan to find it.": "कंप्यूटर का IP और Gollama के नेटवर्क सर्वर का पोर्ट दर्ज करें, या खोजने के लिए स्कैन करें।",
        "Scan ports up to": "पोर्ट स्कैन करें, अधिकतम",
        "No Gollama server found. Check the server is on and both devices share the same Wi-Fi.": "कोई Gollama सर्वर नहीं मिला। जाँचें कि सर्वर चालू है और दोनों डिवाइस एक ही Wi-Fi पर हैं।",
        "Server or tunnel URL": "सर्वर या टनल URL",
        "Works with a public Gollama server or a Cloudflare Tunnel, for example https://name.trycloudflare.com.": "सार्वजनिक Gollama सर्वर या Cloudflare Tunnel के साथ काम करता है, जैसे https://name.trycloudflare.com।",
        "Use a port": "पोर्ट का उपयोग करें",
        "Connect": "कनेक्ट करें",
        "Stop scanning": "स्कैन रोकें",
        "Scan network": "नेटवर्क स्कैन करें",
        "Gollama Search": "Gollama खोज",
        "Ask AI Mode": "AI मोड से पूछें",
        "Recent": "हाल के",
        "Delete": "हटाएं",
        "Try": "आज़माएं",
        "Copy link": "लिंक कॉपी करें",
        "Showing results for": "इसके परिणाम दिखाए जा रहे हैं:",
        "Search instead for %@": "इसके बजाय %@ खोजें",
        "AI Overview": "AI ओवरव्यू",
        "Ask a follow-up": "अगला सवाल पूछें",
        "Visit page": "पेज पर जाएं",
        "Share": "साझा करें",
        "History": "इतिहास",
        "Search chats": "चैट खोजें",
        "Clear all history": "पूरा इतिहास साफ़ करें",
        "Delete every chat on this device?": "इस डिवाइस की सभी चैट हटाएं?",
        "Delete all": "सब हटाएं",
        "Ask anything": "कुछ भी पूछें",
        "AI Mode searches the web and answers with sources.": "AI मोड वेब खोजता है और स्रोतों के साथ जवाब देता है।",
        "Message": "संदेश",
        "Cancel": "रद्द करें",
        "Submit": "सबमिट करें",
        "That video isn't on this device anymore.": "यह वीडियो अब इस डिवाइस पर नहीं है।",
        "Branch in new chat": "नई चैट में शाखा बनाएं",
        "Try again without searching": "बिना खोज के फिर कोशिश करें",
        "Copy as Markdown": "Markdown के रूप में कॉपी करें",
        "Copy sources": "स्रोत कॉपी करें",
        "Edit": "संपादित करें",
        "Copy": "कॉपी करें",
        "There isn't a result available for this search.": "इस खोज के लिए कोई परिणाम उपलब्ध नहीं है।",
        "You can still get an answer from the model, but it won't be backed by sources.": "आप अब भी मॉडल से उत्तर पा सकते हैं, लेकिन वह स्रोतों पर आधारित नहीं होगा।",
        "Continue anyway": "फिर भी जारी रखें",
        "Photos & Videos": "फ़ोटो और वीडियो",
        "Files": "फ़ाइलें",
        "Model": "मॉडल",
        "Fast": "तेज़",
        "Pro": "प्रो",
        "Search": "खोज",
        "AI Mode": "AI मोड",
        "Search or ask anything": "खोजें या कुछ भी पूछें",
        "Copied": "कॉपी किया गया",
        "Copied as Markdown": "Markdown के रूप में कॉपी किया गया",
        "Sources copied": "स्रोत कॉपी किए गए",
        "Stop": "रोकें",
        "Send": "भेजें",
        "Wait for the attachment to finish.": "अटैचमेंट पूरा होने तक प्रतीक्षा करें।",
        "Couldn't read that video.": "वह वीडियो पढ़ा नहीं जा सका।",
        "Couldn't read that photo.": "वह फ़ोटो पढ़ी नहीं जा सकी।",
        "%@ isn't a text file.": "%@ टेक्स्ट फ़ाइल नहीं है।",
        "Storage": "स्टोरेज",
        "Clear cache": "कैश साफ़ करें",
        "Saved videos and cached images. Your chats stay on the server.": "सहेजे गए वीडियो और कैश की गई छवियाँ। आपकी चैट सर्वर पर ही रहती हैं।",
        "Manage Storage": "स्टोरेज प्रबंधित करें",
        "Save uploaded videos": "अपलोड किए वीडियो सहेजें",
        "Lets you watch a video again from the chat after you've sent it.": "भेजने के बाद चैट से वीडियो दोबारा देखने की सुविधा देता है।",
        "Video storage limit": "वीडियो स्टोरेज सीमा",
        "Keep videos for": "वीडियो रखें",
        "%d days": "%d दिन",
        "1 day": "1 दिन",
        "Forever": "हमेशा",
        "Image cache limit": "छवि कैश सीमा",
        "Off": "बंद",
        "Images and web pages are kept so they load faster.": "छवियाँ और वेब पेज तेज़ी से लोड होने के लिए सहेजे जाते हैं।",
        "Saved videos": "सहेजे गए वीडियो",
        "Cache and temporary files": "कैश और अस्थायी फ़ाइलें",
        "Total": "कुल",
        "Clear saved videos": "सहेजे गए वीडियो साफ़ करें",
        "Usage": "उपयोग",
        "Your chats live on the server, so clearing storage never deletes them.": "आपकी चैट सर्वर पर रहती हैं, इसलिए स्टोरेज साफ़ करने से वे कभी नहीं हटतीं।"
    ]
    static let th: [String: String] = [
        "Settings": "การตั้งค่า",
        "Appearance": "รูปลักษณ์",
        "Auto": "อัตโนมัติ",
        "Light": "สว่าง",
        "Dark": "มืด",
        "Auto follows your device's appearance.": "อัตโนมัติจะตามรูปลักษณ์ของอุปกรณ์",
        "Language": "ภาษา",
        "System default": "ค่าเริ่มต้นของระบบ",
        "Done": "เสร็จสิ้น",
        "Preview": "ตัวอย่าง",
        "Code": "โค้ด",
        "View": "มุมมอง",
        "Writing the interactive block…": "กำลังเขียนบล็อกแบบโต้ตอบ…",
        "HTML Preview": "ตัวอย่าง HTML",
        "Model: %@": "โมเดล: %@",
        "Disconnect": "ตัดการเชื่อมต่อ",
        "Connect to Gollama": "เชื่อมต่อกับ Gollama",
        "Private": "ส่วนตัว",
        "Public": "สาธารณะ",
        "Connection": "การเชื่อมต่อ",
        "Same Wi-Fi as your computer": "Wi-Fi เดียวกับคอมพิวเตอร์",
        "Enter the computer's IP and the port Gollama's network server uses, or scan to find it.": "ป้อน IP ของคอมพิวเตอร์และพอร์ตที่เซิร์ฟเวอร์เครือข่ายของ Gollama ใช้ หรือสแกนเพื่อค้นหา",
        "Scan ports up to": "สแกนพอร์ตถึง",
        "No Gollama server found. Check the server is on and both devices share the same Wi-Fi.": "ไม่พบเซิร์ฟเวอร์ Gollama ตรวจสอบว่าเซิร์ฟเวอร์เปิดอยู่และทั้งสองอุปกรณ์ใช้ Wi-Fi เดียวกัน",
        "Server or tunnel URL": "URL เซิร์ฟเวอร์หรืออุโมงค์",
        "Works with a public Gollama server or a Cloudflare Tunnel, for example https://name.trycloudflare.com.": "ใช้ได้กับเซิร์ฟเวอร์ Gollama สาธารณะหรือ Cloudflare Tunnel เช่น https://name.trycloudflare.com",
        "Use a port": "ใช้พอร์ต",
        "Connect": "เชื่อมต่อ",
        "Stop scanning": "หยุดสแกน",
        "Scan network": "สแกนเครือข่าย",
        "Gollama Search": "ค้นหาด้วย Gollama",
        "Ask AI Mode": "ถามโหมด AI",
        "Recent": "ล่าสุด",
        "Delete": "ลบ",
        "Try": "ลองดู",
        "Copy link": "คัดลอกลิงก์",
        "Showing results for": "แสดงผลลัพธ์สำหรับ",
        "Search instead for %@": "ค้นหา %@ แทน",
        "AI Overview": "ภาพรวมจาก AI",
        "Ask a follow-up": "ถามต่อ",
        "Visit page": "เยี่ยมชมหน้า",
        "Share": "แชร์",
        "History": "ประวัติ",
        "Search chats": "ค้นหาแชต",
        "Clear all history": "ล้างประวัติทั้งหมด",
        "Delete every chat on this device?": "ลบแชตทั้งหมดในอุปกรณ์นี้หรือไม่",
        "Delete all": "ลบทั้งหมด",
        "Ask anything": "ถามได้ทุกเรื่อง",
        "AI Mode searches the web and answers with sources.": "โหมด AI ค้นหาในเว็บและตอบพร้อมแหล่งที่มา",
        "Message": "ข้อความ",
        "Cancel": "ยกเลิก",
        "Submit": "ส่ง",
        "That video isn't on this device anymore.": "วิดีโอนั้นไม่อยู่ในอุปกรณ์นี้อีกต่อไป",
        "Branch in new chat": "แตกแขนงเป็นแชตใหม่",
        "Try again without searching": "ลองอีกครั้งโดยไม่ค้นหา",
        "Copy as Markdown": "คัดลอกเป็น Markdown",
        "Copy sources": "คัดลอกแหล่งที่มา",
        "Edit": "แก้ไข",
        "Copy": "คัดลอก",
        "There isn't a result available for this search.": "ไม่มีผลลัพธ์สำหรับการค้นหานี้",
        "You can still get an answer from the model, but it won't be backed by sources.": "คุณยังรับคำตอบจากโมเดลได้ แต่จะไม่มีแหล่งที่มาสนับสนุน",
        "Continue anyway": "ดำเนินการต่อ",
        "Photos & Videos": "รูปภาพและวิดีโอ",
        "Files": "ไฟล์",
        "Model": "โมเดล",
        "Fast": "เร็ว",
        "Pro": "โปร",
        "Search": "ค้นหา",
        "AI Mode": "โหมด AI",
        "Search or ask anything": "ค้นหาหรือถามได้ทุกเรื่อง",
        "Copied": "คัดลอกแล้ว",
        "Copied as Markdown": "คัดลอกเป็น Markdown แล้ว",
        "Sources copied": "คัดลอกแหล่งที่มาแล้ว",
        "Stop": "หยุด",
        "Send": "ส่ง",
        "Wait for the attachment to finish.": "รอให้ไฟล์แนบเสร็จก่อน",
        "Couldn't read that video.": "ไม่สามารถอ่านวิดีโอนั้นได้",
        "Couldn't read that photo.": "ไม่สามารถอ่านรูปภาพนั้นได้",
        "%@ isn't a text file.": "%@ ไม่ใช่ไฟล์ข้อความ",
        "Storage": "พื้นที่จัดเก็บ",
        "Clear cache": "ล้างแคช",
        "Saved videos and cached images. Your chats stay on the server.": "วิดีโอที่บันทึกไว้และรูปภาพในแคช แชตของคุณยังอยู่บนเซิร์ฟเวอร์",
        "Manage Storage": "จัดการพื้นที่จัดเก็บ",
        "Save uploaded videos": "บันทึกวิดีโอที่อัปโหลด",
        "Lets you watch a video again from the chat after you've sent it.": "ช่วยให้ดูวิดีโอซ้ำจากแชตได้หลังจากส่งแล้ว",
        "Video storage limit": "ขีดจำกัดพื้นที่วิดีโอ",
        "Keep videos for": "เก็บวิดีโอไว้",
        "%d days": "%d วัน",
        "1 day": "1 วัน",
        "Forever": "ตลอดไป",
        "Image cache limit": "ขีดจำกัดแคชรูปภาพ",
        "Off": "ปิด",
        "Images and web pages are kept so they load faster.": "เก็บรูปภาพและหน้าเว็บไว้เพื่อให้โหลดเร็วขึ้น",
        "Saved videos": "วิดีโอที่บันทึกไว้",
        "Cache and temporary files": "แคชและไฟล์ชั่วคราว",
        "Total": "รวม",
        "Clear saved videos": "ล้างวิดีโอที่บันทึกไว้",
        "Usage": "การใช้งาน",
        "Your chats live on the server, so clearing storage never deletes them.": "แชตของคุณอยู่บนเซิร์ฟเวอร์ ดังนั้นการล้างพื้นที่จัดเก็บจะไม่ลบแชตเหล่านั้น"
    ]
    static let vi: [String: String] = [
        "Settings": "Cài đặt",
        "Appearance": "Giao diện",
        "Auto": "Tự động",
        "Light": "Sáng",
        "Dark": "Tối",
        "Auto follows your device's appearance.": "Tự động theo giao diện của thiết bị.",
        "Language": "Ngôn ngữ",
        "System default": "Mặc định hệ thống",
        "Done": "Xong",
        "Preview": "Xem trước",
        "Code": "Mã",
        "View": "Xem",
        "Writing the interactive block…": "Đang viết khối tương tác…",
        "HTML Preview": "Xem trước HTML",
        "Model: %@": "Mô hình: %@",
        "Disconnect": "Ngắt kết nối",
        "Connect to Gollama": "Kết nối với Gollama",
        "Private": "Riêng tư",
        "Public": "Công khai",
        "Connection": "Kết nối",
        "Same Wi-Fi as your computer": "Cùng Wi-Fi với máy tính",
        "Enter the computer's IP and the port Gollama's network server uses, or scan to find it.": "Nhập IP của máy tính và cổng mà máy chủ mạng của Gollama sử dụng, hoặc quét để tìm.",
        "Scan ports up to": "Quét cổng đến",
        "No Gollama server found. Check the server is on and both devices share the same Wi-Fi.": "Không tìm thấy máy chủ Gollama. Hãy kiểm tra máy chủ đã bật và cả hai thiết bị dùng chung Wi-Fi.",
        "Server or tunnel URL": "URL máy chủ hoặc đường hầm",
        "Works with a public Gollama server or a Cloudflare Tunnel, for example https://name.trycloudflare.com.": "Hoạt động với máy chủ Gollama công khai hoặc Cloudflare Tunnel, ví dụ https://name.trycloudflare.com.",
        "Use a port": "Dùng cổng",
        "Connect": "Kết nối",
        "Stop scanning": "Dừng quét",
        "Scan network": "Quét mạng",
        "Gollama Search": "Tìm với Gollama",
        "Ask AI Mode": "Hỏi Chế độ AI",
        "Recent": "Gần đây",
        "Delete": "Xóa",
        "Try": "Thử",
        "Copy link": "Sao chép liên kết",
        "Showing results for": "Hiển thị kết quả cho",
        "Search instead for %@": "Tìm kiếm %@ thay thế",
        "AI Overview": "Tổng quan từ AI",
        "Ask a follow-up": "Đặt câu hỏi tiếp theo",
        "Visit page": "Truy cập trang",
        "Share": "Chia sẻ",
        "History": "Lịch sử",
        "Search chats": "Tìm kiếm trò chuyện",
        "Clear all history": "Xóa toàn bộ lịch sử",
        "Delete every chat on this device?": "Xóa mọi cuộc trò chuyện trên thiết bị này?",
        "Delete all": "Xóa tất cả",
        "Ask anything": "Hỏi bất cứ điều gì",
        "AI Mode searches the web and answers with sources.": "Chế độ AI tìm kiếm trên web và trả lời kèm nguồn.",
        "Message": "Tin nhắn",
        "Cancel": "Hủy",
        "Submit": "Gửi",
        "That video isn't on this device anymore.": "Video đó không còn trên thiết bị này.",
        "Branch in new chat": "Tách sang cuộc trò chuyện mới",
        "Try again without searching": "Thử lại không tìm kiếm",
        "Copy as Markdown": "Sao chép dạng Markdown",
        "Copy sources": "Sao chép nguồn",
        "Edit": "Chỉnh sửa",
        "Copy": "Sao chép",
        "There isn't a result available for this search.": "Không có kết quả nào cho tìm kiếm này.",
        "You can still get an answer from the model, but it won't be backed by sources.": "Bạn vẫn có thể nhận câu trả lời từ mô hình, nhưng sẽ không có nguồn dẫn chứng.",
        "Continue anyway": "Vẫn tiếp tục",
        "Photos & Videos": "Ảnh và video",
        "Files": "Tệp",
        "Model": "Mô hình",
        "Fast": "Nhanh",
        "Pro": "Pro",
        "Search": "Tìm kiếm",
        "AI Mode": "Chế độ AI",
        "Search or ask anything": "Tìm kiếm hoặc hỏi bất cứ điều gì",
        "Copied": "Đã sao chép",
        "Copied as Markdown": "Đã sao chép dạng Markdown",
        "Sources copied": "Đã sao chép nguồn",
        "Stop": "Dừng",
        "Send": "Gửi",
        "Wait for the attachment to finish.": "Hãy đợi tệp đính kèm xử lý xong.",
        "Couldn't read that video.": "Không thể đọc video đó.",
        "Couldn't read that photo.": "Không thể đọc ảnh đó.",
        "%@ isn't a text file.": "%@ không phải là tệp văn bản.",
        "Storage": "Dung lượng",
        "Clear cache": "Xóa bộ nhớ đệm",
        "Saved videos and cached images. Your chats stay on the server.": "Video đã lưu và hình ảnh trong bộ nhớ đệm. Cuộc trò chuyện của bạn vẫn ở trên máy chủ.",
        "Manage Storage": "Quản lý dung lượng",
        "Save uploaded videos": "Lưu video đã tải lên",
        "Lets you watch a video again from the chat after you've sent it.": "Cho phép xem lại video từ cuộc trò chuyện sau khi đã gửi.",
        "Video storage limit": "Giới hạn dung lượng video",
        "Keep videos for": "Giữ video trong",
        "%d days": "%d ngày",
        "1 day": "1 ngày",
        "Forever": "Mãi mãi",
        "Image cache limit": "Giới hạn bộ nhớ đệm ảnh",
        "Off": "Tắt",
        "Images and web pages are kept so they load faster.": "Hình ảnh và trang web được giữ lại để tải nhanh hơn.",
        "Saved videos": "Video đã lưu",
        "Cache and temporary files": "Bộ nhớ đệm và tệp tạm",
        "Total": "Tổng cộng",
        "Clear saved videos": "Xóa video đã lưu",
        "Usage": "Mức sử dụng",
        "Your chats live on the server, so clearing storage never deletes them.": "Cuộc trò chuyện nằm trên máy chủ nên việc dọn dung lượng không bao giờ xóa chúng."
    ]
    static let idn: [String: String] = [
        "Settings": "Pengaturan",
        "Appearance": "Tampilan",
        "Auto": "Otomatis",
        "Light": "Terang",
        "Dark": "Gelap",
        "Auto follows your device's appearance.": "Otomatis mengikuti tampilan perangkat Anda.",
        "Language": "Bahasa",
        "System default": "Default sistem",
        "Done": "Selesai",
        "Preview": "Pratinjau",
        "Code": "Kode",
        "View": "Tampilan",
        "Writing the interactive block…": "Menulis blok interaktif…",
        "HTML Preview": "Pratinjau HTML",
        "Model: %@": "Model: %@",
        "Disconnect": "Putuskan",
        "Connect to Gollama": "Hubungkan ke Gollama",
        "Private": "Pribadi",
        "Public": "Publik",
        "Connection": "Koneksi",
        "Same Wi-Fi as your computer": "Wi-Fi yang sama dengan komputer",
        "Enter the computer's IP and the port Gollama's network server uses, or scan to find it.": "Masukkan IP komputer dan port yang digunakan server jaringan Gollama, atau pindai untuk menemukannya.",
        "Scan ports up to": "Pindai port hingga",
        "No Gollama server found. Check the server is on and both devices share the same Wi-Fi.": "Server Gollama tidak ditemukan. Pastikan server menyala dan kedua perangkat memakai Wi-Fi yang sama.",
        "Server or tunnel URL": "URL server atau tunnel",
        "Works with a public Gollama server or a Cloudflare Tunnel, for example https://name.trycloudflare.com.": "Berfungsi dengan server Gollama publik atau Cloudflare Tunnel, misalnya https://name.trycloudflare.com.",
        "Use a port": "Gunakan port",
        "Connect": "Hubungkan",
        "Stop scanning": "Hentikan pemindaian",
        "Scan network": "Pindai jaringan",
        "Gollama Search": "Cari dengan Gollama",
        "Ask AI Mode": "Tanya Mode AI",
        "Recent": "Terbaru",
        "Delete": "Hapus",
        "Try": "Coba",
        "Copy link": "Salin tautan",
        "Showing results for": "Menampilkan hasil untuk",
        "Search instead for %@": "Cari %@ saja",
        "AI Overview": "Ringkasan AI",
        "Ask a follow-up": "Ajukan pertanyaan lanjutan",
        "Visit page": "Kunjungi halaman",
        "Share": "Bagikan",
        "History": "Riwayat",
        "Search chats": "Cari obrolan",
        "Clear all history": "Hapus semua riwayat",
        "Delete every chat on this device?": "Hapus semua obrolan di perangkat ini?",
        "Delete all": "Hapus semua",
        "Ask anything": "Tanyakan apa saja",
        "AI Mode searches the web and answers with sources.": "Mode AI mencari di web dan menjawab dengan sumber.",
        "Message": "Pesan",
        "Cancel": "Batal",
        "Submit": "Kirim",
        "That video isn't on this device anymore.": "Video itu sudah tidak ada di perangkat ini.",
        "Branch in new chat": "Cabangkan ke obrolan baru",
        "Try again without searching": "Coba lagi tanpa mencari",
        "Copy as Markdown": "Salin sebagai Markdown",
        "Copy sources": "Salin sumber",
        "Edit": "Edit",
        "Copy": "Salin",
        "There isn't a result available for this search.": "Tidak ada hasil untuk pencarian ini.",
        "You can still get an answer from the model, but it won't be backed by sources.": "Anda tetap bisa mendapat jawaban dari model, tetapi tanpa dukungan sumber.",
        "Continue anyway": "Tetap lanjutkan",
        "Photos & Videos": "Foto & Video",
        "Files": "File",
        "Model": "Model",
        "Fast": "Cepat",
        "Pro": "Pro",
        "Search": "Cari",
        "AI Mode": "Mode AI",
        "Search or ask anything": "Cari atau tanyakan apa saja",
        "Copied": "Tersalin",
        "Copied as Markdown": "Tersalin sebagai Markdown",
        "Sources copied": "Sumber tersalin",
        "Stop": "Berhenti",
        "Send": "Kirim",
        "Wait for the attachment to finish.": "Tunggu hingga lampiran selesai.",
        "Couldn't read that video.": "Tidak dapat membaca video itu.",
        "Couldn't read that photo.": "Tidak dapat membaca foto itu.",
        "%@ isn't a text file.": "%@ bukan file teks.",
        "Storage": "Penyimpanan",
        "Clear cache": "Hapus cache",
        "Saved videos and cached images. Your chats stay on the server.": "Video tersimpan dan gambar cache. Obrolan Anda tetap ada di server.",
        "Manage Storage": "Kelola penyimpanan",
        "Save uploaded videos": "Simpan video yang diunggah",
        "Lets you watch a video again from the chat after you've sent it.": "Memungkinkan Anda menonton ulang video dari obrolan setelah dikirim.",
        "Video storage limit": "Batas penyimpanan video",
        "Keep videos for": "Simpan video selama",
        "%d days": "%d hari",
        "1 day": "1 hari",
        "Forever": "Selamanya",
        "Image cache limit": "Batas cache gambar",
        "Off": "Mati",
        "Images and web pages are kept so they load faster.": "Gambar dan halaman web disimpan agar dimuat lebih cepat.",
        "Saved videos": "Video tersimpan",
        "Cache and temporary files": "Cache dan file sementara",
        "Total": "Total",
        "Clear saved videos": "Hapus video tersimpan",
        "Usage": "Penggunaan",
        "Your chats live on the server, so clearing storage never deletes them.": "Obrolan Anda ada di server, jadi membersihkan penyimpanan tidak akan menghapusnya."
    ]
    static let ja: [String: String] = [
        "Settings": "設定",
        "Appearance": "外観",
        "Auto": "自動",
        "Light": "ライト",
        "Dark": "ダーク",
        "Auto follows your device's appearance.": "自動はデバイスの外観設定に従います。",
        "Language": "言語",
        "System default": "システムの設定",
        "Done": "完了",
        "Preview": "プレビュー",
        "Code": "コード",
        "View": "表示",
        "Writing the interactive block…": "インタラクティブブロックを作成中…",
        "HTML Preview": "HTMLプレビュー",
        "Model: %@": "モデル: %@",
        "Disconnect": "切断",
        "Connect to Gollama": "Gollama に接続",
        "Private": "プライベート",
        "Public": "パブリック",
        "Connection": "接続",
        "Same Wi-Fi as your computer": "コンピュータと同じ Wi-Fi",
        "Enter the computer's IP and the port Gollama's network server uses, or scan to find it.": "コンピュータの IP と Gollama のネットワークサーバーが使うポートを入力するか、スキャンして見つけます。",
        "Scan ports up to": "スキャンするポートの上限",
        "No Gollama server found. Check the server is on and both devices share the same Wi-Fi.": "Gollama サーバーが見つかりません。サーバーがオンで、両方のデバイスが同じ Wi-Fi に接続されているか確認してください。",
        "Server or tunnel URL": "サーバーまたはトンネルの URL",
        "Works with a public Gollama server or a Cloudflare Tunnel, for example https://name.trycloudflare.com.": "公開 Gollama サーバーまたは Cloudflare Tunnel で使えます。例: https://name.trycloudflare.com",
        "Use a port": "ポートを使用",
        "Connect": "接続",
        "Stop scanning": "スキャンを停止",
        "Scan network": "ネットワークをスキャン",
        "Gollama Search": "Gollama 検索",
        "Ask AI Mode": "AI モードに質問",
        "Recent": "最近",
        "Delete": "削除",
        "Try": "試してみる",
        "Copy link": "リンクをコピー",
        "Showing results for": "次の検索結果を表示:",
        "Search instead for %@": "代わりに「%@」を検索",
        "AI Overview": "AI による概要",
        "Ask a follow-up": "追加で質問",
        "Visit page": "ページを開く",
        "Share": "共有",
        "History": "履歴",
        "Search chats": "チャットを検索",
        "Clear all history": "履歴をすべて消去",
        "Delete every chat on this device?": "このデバイスのチャットをすべて削除しますか？",
        "Delete all": "すべて削除",
        "Ask anything": "何でも聞いてください",
        "AI Mode searches the web and answers with sources.": "AI モードはウェブを検索し、出典付きで回答します。",
        "Message": "メッセージ",
        "Cancel": "キャンセル",
        "Submit": "送信",
        "That video isn't on this device anymore.": "その動画はもうこのデバイスにありません。",
        "Branch in new chat": "新しいチャットに分岐",
        "Try again without searching": "検索せずにもう一度",
        "Copy as Markdown": "Markdown としてコピー",
        "Copy sources": "出典をコピー",
        "Edit": "編集",
        "Copy": "コピー",
        "There isn't a result available for this search.": "この検索には結果がありません。",
        "You can still get an answer from the model, but it won't be backed by sources.": "モデルからの回答は得られますが、出典の裏付けはありません。",
        "Continue anyway": "このまま続ける",
        "Photos & Videos": "写真とビデオ",
        "Files": "ファイル",
        "Model": "モデル",
        "Fast": "高速",
        "Pro": "Pro",
        "Search": "検索",
        "AI Mode": "AI モード",
        "Search or ask anything": "検索または質問",
        "Copied": "コピーしました",
        "Copied as Markdown": "Markdown としてコピーしました",
        "Sources copied": "出典をコピーしました",
        "Stop": "停止",
        "Send": "送信",
        "Wait for the attachment to finish.": "添付ファイルの処理が終わるまでお待ちください。",
        "Couldn't read that video.": "その動画を読み込めませんでした。",
        "Couldn't read that photo.": "その写真を読み込めませんでした。",
        "%@ isn't a text file.": "%@ はテキストファイルではありません。",
        "Storage": "ストレージ",
        "Clear cache": "キャッシュを消去",
        "Saved videos and cached images. Your chats stay on the server.": "保存した動画とキャッシュ画像。チャットはサーバーに残ります。",
        "Manage Storage": "ストレージを管理",
        "Save uploaded videos": "アップロードした動画を保存",
        "Lets you watch a video again from the chat after you've sent it.": "送信後でも、チャットから動画をもう一度見られます。",
        "Video storage limit": "動画の保存容量の上限",
        "Keep videos for": "動画の保存期間",
        "%d days": "%d日",
        "1 day": "1日",
        "Forever": "無期限",
        "Image cache limit": "画像キャッシュの上限",
        "Off": "オフ",
        "Images and web pages are kept so they load faster.": "画像やウェブページを保持して、読み込みを速くします。",
        "Saved videos": "保存した動画",
        "Cache and temporary files": "キャッシュと一時ファイル",
        "Total": "合計",
        "Clear saved videos": "保存した動画を消去",
        "Usage": "使用状況",
        "Your chats live on the server, so clearing storage never deletes them.": "チャットはサーバーに保存されているため、ストレージを消去しても削除されません。"
    ]
    static let ko: [String: String] = [
        "Settings": "설정",
        "Appearance": "화면 스타일",
        "Auto": "자동",
        "Light": "라이트",
        "Dark": "다크",
        "Auto follows your device's appearance.": "자동은 기기의 화면 스타일을 따릅니다.",
        "Language": "언어",
        "System default": "시스템 기본값",
        "Done": "완료",
        "Preview": "미리보기",
        "Code": "코드",
        "View": "보기",
        "Writing the interactive block…": "인터랙티브 블록 작성 중…",
        "HTML Preview": "HTML 미리보기",
        "Model: %@": "모델: %@",
        "Disconnect": "연결 해제",
        "Connect to Gollama": "Gollama에 연결",
        "Private": "비공개",
        "Public": "공개",
        "Connection": "연결",
        "Same Wi-Fi as your computer": "컴퓨터와 같은 Wi-Fi",
        "Enter the computer's IP and the port Gollama's network server uses, or scan to find it.": "컴퓨터의 IP와 Gollama 네트워크 서버가 사용하는 포트를 입력하거나 스캔해서 찾으세요.",
        "Scan ports up to": "스캔할 포트 최대",
        "No Gollama server found. Check the server is on and both devices share the same Wi-Fi.": "Gollama 서버를 찾을 수 없습니다. 서버가 켜져 있고 두 기기가 같은 Wi-Fi에 연결되어 있는지 확인하세요.",
        "Server or tunnel URL": "서버 또는 터널 URL",
        "Works with a public Gollama server or a Cloudflare Tunnel, for example https://name.trycloudflare.com.": "공개 Gollama 서버 또는 Cloudflare Tunnel에서 작동합니다. 예: https://name.trycloudflare.com",
        "Use a port": "포트 사용",
        "Connect": "연결",
        "Stop scanning": "스캔 중지",
        "Scan network": "네트워크 스캔",
        "Gollama Search": "Gollama 검색",
        "Ask AI Mode": "AI 모드에 질문",
        "Recent": "최근",
        "Delete": "삭제",
        "Try": "추천",
        "Copy link": "링크 복사",
        "Showing results for": "다음 검색결과를 표시:",
        "Search instead for %@": "대신 %@ 검색",
        "AI Overview": "AI 개요",
        "Ask a follow-up": "추가 질문하기",
        "Visit page": "페이지 방문",
        "Share": "공유",
        "History": "기록",
        "Search chats": "채팅 검색",
        "Clear all history": "모든 기록 지우기",
        "Delete every chat on this device?": "이 기기의 모든 채팅을 삭제할까요?",
        "Delete all": "모두 삭제",
        "Ask anything": "무엇이든 물어보세요",
        "AI Mode searches the web and answers with sources.": "AI 모드는 웹을 검색하고 출처와 함께 답변합니다.",
        "Message": "메시지",
        "Cancel": "취소",
        "Submit": "제출",
        "That video isn't on this device anymore.": "해당 동영상이 더 이상 이 기기에 없습니다.",
        "Branch in new chat": "새 채팅으로 분기",
        "Try again without searching": "검색 없이 다시 시도",
        "Copy as Markdown": "Markdown으로 복사",
        "Copy sources": "출처 복사",
        "Edit": "편집",
        "Copy": "복사",
        "There isn't a result available for this search.": "이 검색에 대한 결과가 없습니다.",
        "You can still get an answer from the model, but it won't be backed by sources.": "모델의 답변은 받을 수 있지만 출처의 뒷받침은 없습니다.",
        "Continue anyway": "그래도 계속",
        "Photos & Videos": "사진 및 비디오",
        "Files": "파일",
        "Model": "모델",
        "Fast": "빠름",
        "Pro": "프로",
        "Search": "검색",
        "AI Mode": "AI 모드",
        "Search or ask anything": "검색하거나 무엇이든 질문",
        "Copied": "복사됨",
        "Copied as Markdown": "Markdown으로 복사됨",
        "Sources copied": "출처 복사됨",
        "Stop": "중지",
        "Send": "보내기",
        "Wait for the attachment to finish.": "첨부 파일 처리가 끝날 때까지 기다리세요.",
        "Couldn't read that video.": "해당 동영상을 읽을 수 없습니다.",
        "Couldn't read that photo.": "해당 사진을 읽을 수 없습니다.",
        "%@ isn't a text file.": "%@은(는) 텍스트 파일이 아닙니다.",
        "Storage": "저장 공간",
        "Clear cache": "캐시 지우기",
        "Saved videos and cached images. Your chats stay on the server.": "저장된 동영상과 캐시된 이미지입니다. 채팅은 서버에 그대로 남습니다.",
        "Manage Storage": "저장 공간 관리",
        "Save uploaded videos": "업로드한 동영상 저장",
        "Lets you watch a video again from the chat after you've sent it.": "전송한 뒤에도 채팅에서 동영상을 다시 볼 수 있습니다.",
        "Video storage limit": "동영상 저장 용량 한도",
        "Keep videos for": "동영상 보관 기간",
        "%d days": "%d일",
        "1 day": "1일",
        "Forever": "무기한",
        "Image cache limit": "이미지 캐시 한도",
        "Off": "끔",
        "Images and web pages are kept so they load faster.": "이미지와 웹페이지를 보관해 더 빠르게 로드합니다.",
        "Saved videos": "저장된 동영상",
        "Cache and temporary files": "캐시 및 임시 파일",
        "Total": "합계",
        "Clear saved videos": "저장된 동영상 지우기",
        "Usage": "사용량",
        "Your chats live on the server, so clearing storage never deletes them.": "채팅은 서버에 저장되므로 저장 공간을 지워도 삭제되지 않습니다."
    ]
    static let zhHans: [String: String] = [
        "Settings": "设置",
        "Appearance": "外观",
        "Auto": "自动",
        "Light": "浅色",
        "Dark": "深色",
        "Auto follows your device's appearance.": "自动将跟随设备的外观设置。",
        "Language": "语言",
        "System default": "系统默认",
        "Done": "完成",
        "Preview": "预览",
        "Code": "代码",
        "View": "视图",
        "Writing the interactive block…": "正在编写交互式内容块…",
        "HTML Preview": "HTML 预览",
        "Model: %@": "模型：%@",
        "Disconnect": "断开连接",
        "Connect to Gollama": "连接到 Gollama",
        "Private": "私有",
        "Public": "公共",
        "Connection": "连接",
        "Same Wi-Fi as your computer": "与电脑相同的 Wi-Fi",
        "Enter the computer's IP and the port Gollama's network server uses, or scan to find it.": "输入电脑的 IP 和 Gollama 网络服务器使用的端口，或扫描查找。",
        "Scan ports up to": "扫描端口至",
        "No Gollama server found. Check the server is on and both devices share the same Wi-Fi.": "未找到 Gollama 服务器。请确认服务器已开启，且两台设备连接同一 Wi-Fi。",
        "Server or tunnel URL": "服务器或隧道 URL",
        "Works with a public Gollama server or a Cloudflare Tunnel, for example https://name.trycloudflare.com.": "适用于公共 Gollama 服务器或 Cloudflare Tunnel，例如 https://name.trycloudflare.com。",
        "Use a port": "使用端口",
        "Connect": "连接",
        "Stop scanning": "停止扫描",
        "Scan network": "扫描网络",
        "Gollama Search": "Gollama 搜索",
        "Ask AI Mode": "询问 AI 模式",
        "Recent": "最近",
        "Delete": "删除",
        "Try": "试试",
        "Copy link": "复制链接",
        "Showing results for": "显示以下内容的结果：",
        "Search instead for %@": "仍然搜索 %@",
        "AI Overview": "AI 概览",
        "Ask a follow-up": "继续提问",
        "Visit page": "访问页面",
        "Share": "分享",
        "History": "历史记录",
        "Search chats": "搜索聊天",
        "Clear all history": "清除所有历史记录",
        "Delete every chat on this device?": "要删除此设备上的所有聊天吗？",
        "Delete all": "全部删除",
        "Ask anything": "随便问",
        "AI Mode searches the web and answers with sources.": "AI 模式会搜索网络并附带来源作答。",
        "Message": "消息",
        "Cancel": "取消",
        "Submit": "提交",
        "That video isn't on this device anymore.": "该视频已不在此设备上。",
        "Branch in new chat": "在新聊天中分支",
        "Try again without searching": "不搜索重试",
        "Copy as Markdown": "复制为 Markdown",
        "Copy sources": "复制来源",
        "Edit": "编辑",
        "Copy": "复制",
        "There isn't a result available for this search.": "此搜索没有可用结果。",
        "You can still get an answer from the model, but it won't be backed by sources.": "你仍可获得模型的回答，但没有来源支持。",
        "Continue anyway": "仍然继续",
        "Photos & Videos": "照片和视频",
        "Files": "文件",
        "Model": "模型",
        "Fast": "快速",
        "Pro": "专业",
        "Search": "搜索",
        "AI Mode": "AI 模式",
        "Search or ask anything": "搜索或提问",
        "Copied": "已复制",
        "Copied as Markdown": "已复制为 Markdown",
        "Sources copied": "已复制来源",
        "Stop": "停止",
        "Send": "发送",
        "Wait for the attachment to finish.": "请等待附件处理完成。",
        "Couldn't read that video.": "无法读取该视频。",
        "Couldn't read that photo.": "无法读取该照片。",
        "%@ isn't a text file.": "%@ 不是文本文件。",
        "Storage": "存储空间",
        "Clear cache": "清除缓存",
        "Saved videos and cached images. Your chats stay on the server.": "已保存的视频和缓存的图片。聊天记录保留在服务器上。",
        "Manage Storage": "管理存储空间",
        "Save uploaded videos": "保存已上传的视频",
        "Lets you watch a video again from the chat after you've sent it.": "让你在发送后仍可在聊天中再次观看视频。",
        "Video storage limit": "视频存储上限",
        "Keep videos for": "视频保留时间",
        "%d days": "%d 天",
        "1 day": "1 天",
        "Forever": "永久",
        "Image cache limit": "图片缓存上限",
        "Off": "关闭",
        "Images and web pages are kept so they load faster.": "保留图片和网页，以便更快加载。",
        "Saved videos": "已保存的视频",
        "Cache and temporary files": "缓存和临时文件",
        "Total": "总计",
        "Clear saved videos": "清除已保存的视频",
        "Usage": "使用情况",
        "Your chats live on the server, so clearing storage never deletes them.": "聊天记录保存在服务器上，因此清理存储空间不会删除它们。"
    ]
    static let zhHant: [String: String] = [
        "Settings": "設定",
        "Appearance": "外觀",
        "Auto": "自動",
        "Light": "淺色",
        "Dark": "深色",
        "Auto follows your device's appearance.": "自動會跟隨裝置的外觀設定。",
        "Language": "語言",
        "System default": "系統預設",
        "Done": "完成",
        "Preview": "預覽",
        "Code": "程式碼",
        "View": "檢視",
        "Writing the interactive block…": "正在撰寫互動區塊…",
        "HTML Preview": "HTML 預覽",
        "Model: %@": "模型：%@",
        "Disconnect": "中斷連線",
        "Connect to Gollama": "連線到 Gollama",
        "Private": "私人",
        "Public": "公開",
        "Connection": "連線",
        "Same Wi-Fi as your computer": "與電腦相同的 Wi-Fi",
        "Enter the computer's IP and the port Gollama's network server uses, or scan to find it.": "輸入電腦的 IP 與 Gollama 網路伺服器使用的連接埠，或掃描來尋找。",
        "Scan ports up to": "掃描連接埠至",
        "No Gollama server found. Check the server is on and both devices share the same Wi-Fi.": "找不到 Gollama 伺服器。請確認伺服器已開啟，且兩台裝置連接同一個 Wi-Fi。",
        "Server or tunnel URL": "伺服器或通道 URL",
        "Works with a public Gollama server or a Cloudflare Tunnel, for example https://name.trycloudflare.com.": "適用於公開的 Gollama 伺服器或 Cloudflare Tunnel，例如 https://name.trycloudflare.com。",
        "Use a port": "使用連接埠",
        "Connect": "連線",
        "Stop scanning": "停止掃描",
        "Scan network": "掃描網路",
        "Gollama Search": "Gollama 搜尋",
        "Ask AI Mode": "詢問 AI 模式",
        "Recent": "最近",
        "Delete": "刪除",
        "Try": "試試",
        "Copy link": "拷貝連結",
        "Showing results for": "顯示以下內容的結果：",
        "Search instead for %@": "改為搜尋 %@",
        "AI Overview": "AI 總覽",
        "Ask a follow-up": "繼續提問",
        "Visit page": "前往頁面",
        "Share": "分享",
        "History": "記錄",
        "Search chats": "搜尋對話",
        "Clear all history": "清除所有記錄",
        "Delete every chat on this device?": "要刪除此裝置上的所有對話嗎？",
        "Delete all": "全部刪除",
        "Ask anything": "盡管問",
        "AI Mode searches the web and answers with sources.": "AI 模式會搜尋網路並附上來源回答。",
        "Message": "訊息",
        "Cancel": "取消",
        "Submit": "送出",
        "That video isn't on this device anymore.": "該影片已不在此裝置上。",
        "Branch in new chat": "在新對話中建立分支",
        "Try again without searching": "不搜尋再試一次",
        "Copy as Markdown": "拷貝為 Markdown",
        "Copy sources": "拷貝來源",
        "Edit": "編輯",
        "Copy": "拷貝",
        "There isn't a result available for this search.": "此搜尋沒有可用的結果。",
        "You can still get an answer from the model, but it won't be backed by sources.": "你仍可取得模型的回答，但沒有來源佐證。",
        "Continue anyway": "仍然繼續",
        "Photos & Videos": "照片和影片",
        "Files": "檔案",
        "Model": "模型",
        "Fast": "快速",
        "Pro": "專業",
        "Search": "搜尋",
        "AI Mode": "AI 模式",
        "Search or ask anything": "搜尋或提問",
        "Copied": "已拷貝",
        "Copied as Markdown": "已拷貝為 Markdown",
        "Sources copied": "已拷貝來源",
        "Stop": "停止",
        "Send": "傳送",
        "Wait for the attachment to finish.": "請等待附件處理完成。",
        "Couldn't read that video.": "無法讀取該影片。",
        "Couldn't read that photo.": "無法讀取該照片。",
        "%@ isn't a text file.": "%@ 不是文字檔。",
        "Storage": "儲存空間",
        "Clear cache": "清除快取",
        "Saved videos and cached images. Your chats stay on the server.": "已儲存的影片和快取的圖片。對話保留在伺服器上。",
        "Manage Storage": "管理儲存空間",
        "Save uploaded videos": "儲存已上傳的影片",
        "Lets you watch a video again from the chat after you've sent it.": "讓你在傳送後仍可在對話中再次觀看影片。",
        "Video storage limit": "影片儲存上限",
        "Keep videos for": "影片保留時間",
        "%d days": "%d 天",
        "1 day": "1 天",
        "Forever": "永久",
        "Image cache limit": "圖片快取上限",
        "Off": "關閉",
        "Images and web pages are kept so they load faster.": "保留圖片和網頁，以便更快載入。",
        "Saved videos": "已儲存的影片",
        "Cache and temporary files": "快取和暫存檔案",
        "Total": "總計",
        "Clear saved videos": "清除已儲存的影片",
        "Usage": "使用情況",
        "Your chats live on the server, so clearing storage never deletes them.": "對話保存在伺服器上，因此清理儲存空間不會刪除它們。"
    ]
    static let cs: [String: String] = [
        "Settings": "Nastavení",
        "Appearance": "Vzhled",
        "Auto": "Automaticky",
        "Light": "Světlý",
        "Dark": "Tmavý",
        "Auto follows your device's appearance.": "Automaticky se řídí vzhledem zařízení.",
        "Language": "Jazyk",
        "System default": "Výchozí systémové",
        "Done": "Hotovo",
        "Preview": "Náhled",
        "Code": "Kód",
        "View": "Zobrazení",
        "Writing the interactive block…": "Zapisuje se interaktivní blok…",
        "HTML Preview": "Náhled HTML",
        "Model: %@": "Model: %@",
        "Disconnect": "Odpojit",
        "Connect to Gollama": "Připojit ke Gollama",
        "Private": "Soukromá",
        "Public": "Veřejná",
        "Connection": "Připojení",
        "Same Wi-Fi as your computer": "Stejná Wi-Fi jako počítač",
        "Enter the computer's IP and the port Gollama's network server uses, or scan to find it.": "Zadejte IP adresu počítače a port síťového serveru Gollama nebo je vyhledejte skenováním.",
        "Scan ports up to": "Skenovat porty do",
        "No Gollama server found. Check the server is on and both devices share the same Wi-Fi.": "Server Gollama nebyl nalezen. Zkontrolujte, zda server běží a obě zařízení jsou ve stejné Wi-Fi.",
        "Server or tunnel URL": "URL serveru nebo tunelu",
        "Works with a public Gollama server or a Cloudflare Tunnel, for example https://name.trycloudflare.com.": "Funguje s veřejným serverem Gollama nebo tunelem Cloudflare, například https://name.trycloudflare.com.",
        "Use a port": "Použít port",
        "Connect": "Připojit",
        "Stop scanning": "Zastavit skenování",
        "Scan network": "Skenovat síť",
        "Gollama Search": "Hledat v Gollama",
        "Ask AI Mode": "Zeptat se v režimu AI",
        "Recent": "Nedávné",
        "Delete": "Smazat",
        "Try": "Zkuste",
        "Copy link": "Kopírovat odkaz",
        "Showing results for": "Zobrazují se výsledky pro",
        "Search instead for %@": "Hledat místo toho %@",
        "AI Overview": "Přehled od AI",
        "Ask a follow-up": "Zeptat se na další",
        "Visit page": "Navštívit stránku",
        "Share": "Sdílet",
        "History": "Historie",
        "Search chats": "Hledat v chatech",
        "Clear all history": "Vymazat celou historii",
        "Delete every chat on this device?": "Smazat všechny chaty v tomto zařízení?",
        "Delete all": "Smazat vše",
        "Ask anything": "Ptejte se na cokoli",
        "AI Mode searches the web and answers with sources.": "Režim AI prohledává web a odpovídá se zdroji.",
        "Message": "Zpráva",
        "Cancel": "Zrušit",
        "Submit": "Odeslat",
        "That video isn't on this device anymore.": "Toto video už v tomto zařízení není.",
        "Branch in new chat": "Odbočit do nového chatu",
        "Try again without searching": "Zkusit znovu bez vyhledávání",
        "Copy as Markdown": "Kopírovat jako Markdown",
        "Copy sources": "Kopírovat zdroje",
        "Edit": "Upravit",
        "Copy": "Kopírovat",
        "There isn't a result available for this search.": "Pro toto hledání není k dispozici žádný výsledek.",
        "You can still get an answer from the model, but it won't be backed by sources.": "Odpověď od modelu stále získáte, ale nebude podložena zdroji.",
        "Continue anyway": "Přesto pokračovat",
        "Photos & Videos": "Fotky a videa",
        "Files": "Soubory",
        "Model": "Model",
        "Fast": "Rychlý",
        "Pro": "Pro",
        "Search": "Hledat",
        "AI Mode": "Režim AI",
        "Search or ask anything": "Hledejte nebo se na cokoli zeptejte",
        "Copied": "Zkopírováno",
        "Copied as Markdown": "Zkopírováno jako Markdown",
        "Sources copied": "Zdroje zkopírovány",
        "Stop": "Zastavit",
        "Send": "Odeslat",
        "Wait for the attachment to finish.": "Počkejte, až se příloha dokončí.",
        "Couldn't read that video.": "Video se nepodařilo načíst.",
        "Couldn't read that photo.": "Fotku se nepodařilo načíst.",
        "%@ isn't a text file.": "%@ není textový soubor.",
        "Storage": "Úložiště",
        "Clear cache": "Vymazat mezipaměť",
        "Saved videos and cached images. Your chats stay on the server.": "Uložená videa a obrázky v mezipaměti. Chaty zůstávají na serveru.",
        "Manage Storage": "Správa úložiště",
        "Save uploaded videos": "Ukládat nahraná videa",
        "Lets you watch a video again from the chat after you've sent it.": "Umožní vám video po odeslání znovu přehrát z chatu.",
        "Video storage limit": "Limit úložiště pro videa",
        "Keep videos for": "Uchovávat videa po dobu",
        "%d days": "%d dní",
        "1 day": "1 den",
        "Forever": "Navždy",
        "Image cache limit": "Limit mezipaměti obrázků",
        "Off": "Vypnuto",
        "Images and web pages are kept so they load faster.": "Obrázky a webové stránky se ukládají, aby se načítaly rychleji.",
        "Saved videos": "Uložená videa",
        "Cache and temporary files": "Mezipaměť a dočasné soubory",
        "Total": "Celkem",
        "Clear saved videos": "Vymazat uložená videa",
        "Usage": "Využití",
        "Your chats live on the server, so clearing storage never deletes them.": "Vaše chaty jsou na serveru, takže vymazání úložiště je nikdy neodstraní."
    ]
}