import Foundation
import Network
import AVFoundation
import UIKit

struct Req {
    var method = ""
    var path = ""
    var query: [String: String] = [:]
    var headers: [String: String] = [:]
    var body = Data()
    var complete = false
}

/// 앱 안에서 도는 작은 HTTP 서버. 웹앱 파일을 내주고, 사진 올리기·API 키 설정·소리 내기를 맡는다.
final class Server {
    static let shared = Server()
    private(set) var port: UInt16 = 8765
    var screen = "home"
    var engine = "?"
    let token = UUID().uuidString
    var hits = 0
    var lastError = ""
    var lastLog = ""
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "hangul.server")
    private let speech = AVSpeechSynthesizer()

    func start() -> Bool {
        for p in UInt16(8765)...UInt16(8775) {
            guard let np = NWEndpoint.Port(rawValue: p), let l = try? NWListener(using: .tcp, on: np) else { continue }
            let sem = DispatchSemaphore(value: 0)
            var ready = false
            l.stateUpdateHandler = { st in
                switch st {
                case .ready: ready = true; sem.signal()
                case .failed, .cancelled: sem.signal()
                default: break
                }
            }
            l.newConnectionHandler = { [weak self] c in self?.handle(c) }
            l.start(queue: queue)
            _ = sem.wait(timeout: .now() + 2)
            if ready { listener = l; port = p; return true }
            l.cancel()
        }
        return false
    }

    private func handle(_ c: NWConnection) {
        c.start(queue: queue)
        var buf = Data()
        func loop() {
            c.receive(minimumIncompleteLength: 1, maximumLength: 262144) { [weak self] data, _, isDone, err in
                guard let self = self else { c.cancel(); return }
                if let d = data { buf.append(d) }
                if let req = self.parse(buf), req.complete { self.route(req, c); return }
                if err != nil || isDone || buf.count > 40_000_000 { c.cancel(); return }
                loop()
            }
        }
        loop()
    }

    private func parse(_ d: Data) -> Req? {
        guard let r = d.range(of: Data([13, 10, 13, 10])) else { return nil }
        guard let head = String(data: d.subdata(in: d.startIndex..<r.lowerBound), encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let first = lines.removeFirst().split(separator: " ")
        guard first.count >= 2 else { return nil }
        var req = Req()
        req.method = String(first[0])
        let parts = String(first[1]).split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        req.path = String(parts[0]).removingPercentEncoding ?? String(parts[0])
        if parts.count > 1 {
            for kv in parts[1].split(separator: "&") {
                let p = kv.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let k = String(p[0]).removingPercentEncoding ?? ""
                let v = p.count > 1 ? (String(p[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? "") : ""
                req.query[k] = v
            }
        }
        for l in lines {
            if let i = l.firstIndex(of: ":") {
                let k = String(l[l.startIndex..<i]).lowercased()
                let v = String(l[l.index(after: i)...]).trimmingCharacters(in: .whitespaces)
                req.headers[k] = v
            }
        }
        let need = Int(req.headers["content-length"] ?? "0") ?? 0
        var body = d.subdata(in: r.upperBound..<d.endIndex)
        req.complete = body.count >= need
        if body.count > need { body = body.subdata(in: body.startIndex..<(body.startIndex + need)) }
        req.body = body
        return req
    }

    private func isLocal(_ c: NWConnection) -> Bool {
        if case let .hostPort(host, _) = c.endpoint {
            let s = "\(host)"
            return s.hasPrefix("127.") || s.hasPrefix("::1") || s.contains("::ffff:127.")
        }
        return false
    }

    private func route(_ r: Req, _ c: NWConnection) {
        hits += 1
        let local = isLocal(c) || r.query["k"] == token
        switch (r.method, r.path) {
        case ("GET", "/"), ("GET", "/index.html"):
            file(c, "www/index.html")
        case ("GET", "/setup"):
            file(c, "www/setup.html")
        case ("GET", "/api/info"):
            json(c, ["ip": Server.localIP(), "port": Int(port), "photos": Store.photos().count, "hasKey": !Store.key().isEmpty, "name": Store.name(), "engine": engine,  "os": UIDevice.current.systemVersion] as [String: Any])
        case ("GET", "/api/config"):
            if local { json(c, ["key": Store.key(), "name": Store.name()]) } else { reply(c, 403, "text/plain", Data("forbidden".utf8)) }
        case ("POST", "/api/config"):
            if let o = (try? JSONSerialization.jsonObject(with: r.body)) as? [String: Any] {
                var add: [String: Any] = [:]
                if let k = o["key"] as? String { add["key"] = k.trimmingCharacters(in: .whitespacesAndNewlines) }
                if let n = o["name"] as? String { add["name"] = String(n.trimmingCharacters(in: .whitespacesAndNewlines).prefix(8)) }
                Store.merge(add)
                json(c, ["ok": true])
            } else { reply(c, 400, "text/plain", Data("bad".utf8)) }
        case ("GET", "/api/photos"):
            json(c, Store.photos())
        case ("POST", "/upload"):
            let ct = r.headers["content-type"] ?? ""
            let ext = ct.contains("png") ? "png" : (ct.contains("webp") ? "webp" : "jpg")
            if r.body.isEmpty { reply(c, 400, "text/plain", Data("empty".utf8)); return }
            let name = "p\(Int(Date().timeIntervalSince1970 * 1000)).\(ext)"
            do {
                try r.body.write(to: Store.photosDir.appendingPathComponent(name))
                var caps = Store.captions()
                let cap = (r.query["cap"] ?? "").trimmingCharacters(in: .whitespaces)
                caps[name] = cap.isEmpty ? "우리 가족 사진" : cap
                Store.saveCaptions(caps)
                json(c, ["ok": true, "f": name])
            } catch { lastError = error.localizedDescription; reply(c, 500, "text/plain", Data("저장 실패: \(error.localizedDescription)".utf8)) }
        case ("POST", "/api/delete"):
            let f = r.query["f"] ?? ""
            if f.isEmpty || f.contains("/") || f.contains("..") { reply(c, 400, "text/plain", Data("bad".utf8)); return }
            try? FileManager.default.removeItem(at: Store.photosDir.appendingPathComponent(f))
            var caps = Store.captions(); caps.removeValue(forKey: f); Store.saveCaptions(caps)
            json(c, ["ok": true])
        case ("GET", "/api/speak"):
            let t = r.query["t"] ?? ""
            if !t.isEmpty && local { say(t, queue: r.query["q"] == "1") }
            json(c, ["ok": true])
        case ("GET", "/api/diag"):
            json(c, ["base": Store.base.path, "problems": Store.diag, "lastError": lastError, "hits": hits, "photos": Store.photos().count, "hasKey": !Store.key().isEmpty, "name": Store.name(), "engine": engine, "voice": (voice.map { "\($0.name) q\($0.quality.rawValue)" } ?? "없음"), "os": UIDevice.current.systemVersion] as [String: Any])
        case ("POST", "/api/log"):
            lastLog = String(data: r.body.prefix(2000), encoding: .utf8) ?? ""
            json(c, ["ok": true])
        case ("GET", "/api/log"):
            json(c, ["engine": engine, "os": UIDevice.current.systemVersion, "log": lastLog])
        case ("POST", "/api/screen"):
            screen = r.query["s"] ?? "home"
            json(c, ["ok": true])
        default:
            if r.method == "GET" && (r.path.hasPrefix("/img/") || r.path.hasPrefix("/fonts/")) {
                file(c, "www" + r.path)
            } else if r.method == "GET" && r.path.hasPrefix("/photos/") {
                let f = String(r.path.dropFirst("/photos/".count))
                if f.isEmpty || f.contains("/") || f.contains("..") { reply(c, 404, "text/plain", Data()); return }
                let url = Store.photosDir.appendingPathComponent(f)
                if let d = try? Data(contentsOf: url) { reply(c, 200, mime(url.pathExtension), d) } else { reply(c, 404, "text/plain", Data()) }
            } else {
                reply(c, 404, "text/plain", Data("not found".utf8))
            }
        }
    }

    /// 한국어 음성 중 가장 좋은 것(프리미엄 > 향상 > 기본, 여성 '유나' 우선)
    static func bestVoice() -> AVSpeechSynthesisVoice? {
        let ko = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("ko") }
        func score(_ v: AVSpeechSynthesisVoice) -> Int {
            var s = v.quality.rawValue * 10
            if v.name.contains("Yuna") || v.name.contains("유나") { s += 15 }
            return s
        }
        return ko.max { score($0) < score($1) } ?? AVSpeechSynthesisVoice(language: "ko-KR")
    }
    lazy var voice: AVSpeechSynthesisVoice? = Server.bestVoice()

    private func say(_ t: String, queue: Bool) {
        DispatchQueue.main.async {
            let u = AVSpeechUtterance(string: t)
            u.voice = self.voice
            u.rate = 0.42
            u.pitchMultiplier = 1.12
            u.volume = 1.0
            u.preUtteranceDelay = 0.05
            u.postUtteranceDelay = 0.12
            if !queue { self.speech.stopSpeaking(at: .immediate) }
            self.speech.speak(u)
        }
    }

    private func file(_ c: NWConnection, _ rel: String) {
        guard !rel.contains(".."), let base = Bundle.main.resourceURL else { reply(c, 404, "text/plain", Data()); return }
        let url = base.appendingPathComponent(rel)
        if let d = try? Data(contentsOf: url) { reply(c, 200, mime(url.pathExtension), d) } else { reply(c, 404, "text/plain", Data()) }
    }

    private func json(_ c: NWConnection, _ obj: Any) {
        let d = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
        reply(c, 200, "application/json; charset=utf-8", d)
    }

    private func mime(_ ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        case "ttf": return "font/ttf"
        default: return "application/octet-stream"
        }
    }

    private func reply(_ c: NWConnection, _ code: Int, _ type: String, _ body: Data) {
        let names: [Int: String] = [200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 500: "Server Error"]
        let head = "HTTP/1.1 \(code) \(names[code] ?? "OK")\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        c.send(content: out, contentContext: .defaultMessage, isComplete: true, completion: .contentProcessed { _ in c.cancel() })
    }

    static func localIP() -> String {
        var addr = "127.0.0.1"
        var ifa: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifa) == 0 {
            var p = ifa
            while let cur = p {
                let i = cur.pointee
                if let sa = i.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) {
                    let name = String(cString: i.ifa_name)
                    if name.hasPrefix("en") {
                        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                            addr = String(cString: host)
                            break
                        }
                    }
                }
                p = i.ifa_next
            }
            freeifaddrs(ifa)
        }
        return addr
    }
}
