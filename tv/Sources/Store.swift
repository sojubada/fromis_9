import Foundation

/// 앱 전용 저장소(Documents). 사진은 Documents/photos, 설정은 Documents/config.json
enum Store {
    static let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    static let photosDir = docs.appendingPathComponent("photos", isDirectory: true)
    static let indexURL = photosDir.appendingPathComponent("index.json")
    static let configURL = docs.appendingPathComponent("config.json")
    static let exts = ["jpg", "jpeg", "png", "webp", "gif"]

    static func setup() {
        try? FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
    }

    static func captions() -> [String: String] {
        guard let d = try? Data(contentsOf: indexURL),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: String] else { return [:] }
        return o
    }

    static func saveCaptions(_ c: [String: String]) {
        if let d = try? JSONSerialization.data(withJSONObject: c) { try? d.write(to: indexURL) }
    }

    /// 폴더에 직접 넣은 파일도 목록에 나온다. 제목은 index.json, 없으면 파일 이름.
    static func photos() -> [[String: String]] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: photosDir.path)) ?? []
        let caps = captions()
        return files
            .filter { exts.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted()
            .map { f in
                let base = (f as NSString).deletingPathExtension.replacingOccurrences(of: "_", with: " ")
                return ["f": f, "c": caps[f] ?? base]
            }
    }

    static func config() -> [String: Any] {
        guard let d = try? Data(contentsOf: configURL),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        return o
    }

    static func key() -> String { (config()["key"] as? String) ?? "" }
    static func name() -> String { (config()["name"] as? String) ?? "" }

    static func merge(_ add: [String: Any]) {
        var o = config()
        for (k, v) in add where k == "key" || k == "name" { o[k] = v }
        if let d = try? JSONSerialization.data(withJSONObject: o) { try? d.write(to: configURL) }
    }
}
