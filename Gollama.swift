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
        .accessibilityLabel(systemName == "stop.fill" ? "Stop" : "Send")
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
    static func save(_ src: URL, id: String) -> URL? {
        let ext = src.pathExtension.isEmpty ? "mov" : src.pathExtension
        let dst = dir.appendingPathComponent("\(id).\(ext)")
        try? FileManager.default.removeItem(at: dst)
        return (try? FileManager.default.copyItem(at: src, to: dst)) != nil ? dst : nil
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
        if pending.contains(where: { $0.state == "uploading" || $0.state == "processing" }) { flash("Wait for the attachment to finish."); return }
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
        flash("Copied")
    }

    func copyMarkdown(_ t: ModeTurn) {
        UIPasteboard.general.string = t.answer
        flash("Copied as Markdown")
    }

    func copySources(_ t: ModeTurn) {
        UIPasteboard.general.string = t.sources.enumerated().map { "[\($0.offset + 1)] \($0.element.title) - \($0.element.url)" }.joined(separator: "\n")
        flash("Sources copied")
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
        pending.removeAll { $0.kind == .video }
        let a = Attachment(kind: .video, name: name)
        a.state = "uploading"
        a.message = "Uploading…"
        a.localURL = url
        pending.append(a)
        Task { a.thumb = await VideoStore.thumbnail(url) }
        func fail(_ m: String) { a.state = "error"; a.message = m }
        do {
            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
            let b = try await c.call("video_begin", [name, size, tier]) as? [String: Any]
            guard b?["ok"] as? Bool == true, let vid = b?["id"] as? String else { fail(b?["error"] as? String ?? "Upload failed."); return }
            a.videoId = vid
            if let kept = VideoStore.save(url, id: vid) { a.localURL = kept }     // so you can watch it again from the chat
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

    func makeCoordinator() -> Coordinator { Coordinator(height: $height, onLink: onLink) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.isScrollEnabled = true
        wv.scrollView.backgroundColor = .clear
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        context.coordinator.onLink = onLink
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

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML = ""
        @Binding var height: CGFloat
        var onLink: (URL) -> Void
        init(height: Binding<CGFloat>, onLink: @escaping (URL) -> Void) {
            _height = height
            self.onLink = onLink
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                if let res = try? await webView.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)"),
                   let num = res as? NSNumber {
                    let h = CGFloat(num.doubleValue)
                    if h > 20 {
                        self.height = min(max(h, 140), 420)
                    }
                }
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let u = navigationAction.request.url {
                onLink(u)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

/// ```run.html blocks (and "html live" / "html run") run right in the chat, like the website's Interactive HTML box.
struct LiveHTMLBlock: View {
    let code: String
    let open: Bool
    @Environment(AppModel.self) private var app
    @State private var h: CGFloat = 220
    @State private var runId = UUID()
    @State private var showCode = false
    @State private var fullScreen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Label("Interactive HTML", systemImage: "play.rectangle").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if !open {
                    Button("Re-run", systemImage: "arrow.clockwise") { runId = UUID(); h = 220 }
                        .font(.footnote).buttonStyle(.plain).foregroundStyle(Pal.blue)
                    Button { fullScreen = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            if open {
                HStack(spacing: 8) { ThinkingDots(); Text("Writing the interactive block…").font(.footnote).foregroundStyle(.secondary) }
                    .padding(.vertical, 12)
            } else {
                HTMLPreviewView(html: code, height: $h, onLink: { app.open($0) })
                    .frame(height: h)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .id(runId)
            }
            DisclosureGroup("Show code", isExpanded: $showCode) {
                ScrollView(.horizontal) { Text(code).font(.system(.footnote, design: .monospaced)).textSelection(.enabled).padding(10) }
            }
            .font(.footnote)
            .tint(.secondary)
            Text("AI-generated. Don't enter sensitive personal info.").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .clipped()
        .sheet(isPresented: $fullScreen) {
            NavigationStack {
                HTMLPreviewView(html: code, height: .constant(600), onLink: { app.open($0) })
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("Interactive HTML")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { Button("Done") { fullScreen = false } }
                    }
            }
        }
    }
}

/// Ordinary code. HTML / SVG blocks also get a Run button.
struct CodeBlock: View {
    let lang: String
    let code: String
    let open: Bool
    var note: String?
    @Environment(AppModel.self) private var app
    @State private var preview = false
    @State private var h: CGFloat = 220

    private var canRun: Bool { !open && ["html", "svg"].contains(lang.lowercased()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(lang.isEmpty ? "text" : lang).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if canRun {
                    Button(preview ? "Code" : "Run", systemImage: preview ? "chevron.left.forwardslash.chevron.right" : "play.fill") { preview.toggle() }
                        .font(.caption.weight(.semibold)).buttonStyle(.plain).foregroundStyle(Pal.blue)
                }
                Button { UIPasteboard.general.string = code; app.flash("Copied") } label: { Image(systemName: "doc.on.doc").font(.caption) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            if preview {
                HTMLPreviewView(html: code, height: $h, onLink: { app.open($0) })
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

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var drag: CGFloat = 0
    @State private var width: CGFloat = 390
    private let corner: CGFloat = 50      // roughly the corner radius of a Face ID iPhone

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
                }
                // the whole app slides over like a card, and the card is rounded to the device's corners while the sidebar is open
                TabView(selection: $app.mainTab) {
                    Tab("Search", systemImage: "magnifyingglass", value: MainTab.search) { SearchRoot() }
                    Tab("AI Mode", systemImage: "sparkles", value: MainTab.mode) { AIModeRoot() }
                }
                .tabViewStyle(.sidebarAdaptable)
                .background(AmbientBackground())
                .overlay {
                    if progress > 0 {
                        Color.black.opacity(0.14 * progress).onTapGesture { app.closeSidebar() }
                    }
                }
                .mask { RoundedRectangle(cornerRadius: corner * progress, style: .continuous).ignoresSafeArea() }
                .shadow(color: .black.opacity(0.28 * progress), radius: 24, x: -6)
                .offset(x: progress * drawerW)
                .transition(.opacity)
            } else {
                ConnectScreen().transition(.opacity)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .simultaneousGesture(sidebarDrag)
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
        .environment(\.openURL, OpenURLAction { url in
            app.open(url)
            return .handled
        })
        .animation(.smooth(duration: 0.3), value: app.connected)
        .animation(.smooth(duration: 0.25), value: app.notice)
    }

    /// Swipe from the left edge to open the sidebar, swipe left (anywhere) to close it. Only on the AI Mode tab.
    private var sidebarDrag: some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .global)
            .onChanged { v in
                guard compact, app.connected else { return }
                guard abs(v.translation.width) > abs(v.translation.height) * 1.2 else { return }
                if app.sidebarOpen {
                    drag = min(0, max(-drawerW, v.translation.width))
                } else if app.mainTab == .mode && v.startLocation.x < 60 {
                    drag = min(drawerW, max(0, v.translation.width))
                }
            }
            .onEnded { v in
                guard drag != 0 else { return }
                let base: CGFloat = app.sidebarOpen ? drawerW : 0
                let momentum = (v.predictedEndTranslation.width - v.translation.width) * 0.25
                let open = base + drag + momentum > drawerW * 0.5
                if open { hideKeyboard() }
                withAnimation(.smooth(duration: 0.3)) {
                    app.sidebarOpen = open
                    drag = 0
                }
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
                        .padding(.horizontal, 24).padding(.top, 30)
                        .frame(maxWidth: min(geo.size.width, 640), alignment: .leading)
                    }
                    Spacer(minLength: 60)
                }
                .frame(width: min(geo.size.width, 720), minHeight: geo.size.height)
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
        let speakKey = "ov-\(ov.id)"
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Spark(size: 20)
                Text("AI Overview").font(.title3.weight(.medium))
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
                    TextField("Ask a follow-up", text: $followUp).focused($focused).submitLabel(.send).onSubmit { send() }
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
                Button { if let u = URL(string: item.page) { dismiss(); openURL(u) } } label: { Label("Visit page", systemImage: "safari") }
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
                        if !app.modelName.isEmpty { Text("Model: \(app.modelName)") }
                        Button("Disconnect", systemImage: "wifi.slash", role: .destructive) { app.disconnect() }
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
                Text("History").font(.title3.weight(.semibold))
                Spacer()
                Button { app.newChat(); picked() } label: { GlassIcon(name: "square.and.pencil", size: 38) }.buttonStyle(.plain)
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
                        Button { Task { await app.openChat(c.id); picked() } } label: {
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
            TextField("Message", text: $app.editText, axis: .vertical)
                .lineLimit(1...8)
                .focused($focused)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
            HStack(spacing: 10) {
                Button("Cancel") { app.cancelEdit() }.buttonStyle(.glass)
                Button("Submit") { app.submitEdit(turn) }
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
        Button { if let u = video.url { app.player = PlayerItem(url: u) } else { app.flash("That video isn't on this device anymore.") } } label: {
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
                Button("Branch in new chat", systemImage: "arrow.triangle.branch") { Task { await app.branchChat(from: turn) } }
                Button("Try again without searching", systemImage: "text.magnifyingglass") { app.retry(turn, force: true) }
                Button("Copy as Markdown", systemImage: "doc.richtext") { app.copyMarkdown(turn) }
                if !turn.sources.isEmpty { Button("Copy sources", systemImage: "link") { app.copySources(turn) } }
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
                            Button("Edit", systemImage: "pencil") { app.beginEdit(turn) }
                            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = turn.text; app.flash("Copied") }
                        }
                    if turn.done && !app.modeBusy {
                        HStack(spacing: 2) {
                            Button { UIPasteboard.general.string = turn.text; app.flash("Copied") } label: {
                                Image(systemName: "doc.on.doc").font(.system(size: 13)).frame(width: 32, height: 28)
                            }
                            Button { app.beginEdit(turn) } label: {
                                Image(systemName: "pencil").font(.system(size: 13)).frame(width: 32, height: 28)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
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