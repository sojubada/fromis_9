import Foundation

/// 앱 저장소. tvOS 는 Documents 에 쓸 수 없는 경우가 많아, 쓸 수 있는 폴더를 찾아 쓴다.
/// 이름·API 키는 UserDefaults(재부팅·앱 재시작 후에도 유지)에 저장한다.
enum Store {
    static let fm = FileManager.default
    static let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    static let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    static var base: URL = caches
    static var diag = ""
    static let exts = ["jpg", "jpeg", "png", "webp", "gif"]
    static var photosDir: URL { base.appendingPathComponent("photos", isDirectory: true) }
    static var indexURL: URL { photosDir.appendingPathComponent("index.json") }

    private static func writable(_ dir: URL) -> Bool {
        let p = dir.appendingPathComponent("photos", isDirectory: true)
        do {
            try fm.createDirectory(at: p, withIntermediateDirectories: true)
            let t = p.appendingPathComponent(".probe")
            try Data("1".utf8).write(to: t)
            try? fm.removeItem(at: t)
            return true
        } catch {
            diag += "\(dir.lastPathComponent) 쓰기 실패(\(error.localizedDescription)); "
            return false
        }
    }

    static func setup() {
        if writable(docs) { base = docs } else if writable(caches) { base = caches }
        else { diag += "저장할 폴더가 없음; " }
    }

    static func captions() -> [String: String] {
        guard let d = try? Data(contentsOf: indexURL),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: String] else { return [:] }
        return o
    }

    static func saveCaptions(_ c: [String: String]) {
        if let d = try? JSONSerialization.data(withJSONObject: c) { try? d.write(to: indexURL) }
    }

    static func photos() -> [[String: String]] {
        let files = (try? fm.contentsOfDirectory(atPath: photosDir.path)) ?? []
        let caps = captions()
        return files
            .filter { exts.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted()
            .map { f in
                let base = (f as NSString).deletingPathExtension.replacingOccurrences(of: "_", with: " ")
                return ["f": f, "c": caps[f] ?? base]
            }
    }

    static func config() -> [String: Any] { UserDefaults.standard.dictionary(forKey: "hb_config") ?? [:] }
    static func key() -> String { (config()["key"] as? String) ?? "" }
    static func name() -> String { (config()["name"] as? String) ?? "" }

    static func merge(_ add: [String: Any]) {
        var o = config()
        for (k, v) in add where k == "key" || k == "name" { o[k] = v }
        UserDefaults.standard.set(o, forKey: "hb_config")
        UserDefaults.standard.synchronize()
    }
}
