import Foundation
import AVFoundation

/// 말소리를 스피커로 바로 내지 않고 WAV 로 만들어 웹 화면(Web Audio)에서 재생한다.
/// tvOS 에서 웹뷰 효과음과 AVSpeechSynthesizer 직접 재생이 부딪혀 말소리가 안 나는 문제를 피한다.
final class TTSRender {
    static let shared = TTSRender()
    private var cache: [String: Data] = [:]
    private var order: [String] = []
    private var live: [AVSpeechSynthesizer] = []
    var lastError = ""

    private var jobs: [(String, AVSpeechSynthesisVoice?, (Data?) -> Void)] = []
    private var busy = false

    /// 여러 요청이 한꺼번에 와도 하나씩 차례로 만든다 (동시에 만들면 소리가 섞이거나 빠진다)
    func render(_ text: String, voice: AVSpeechSynthesisVoice?, done: @escaping (Data?) -> Void) {
        DispatchQueue.main.async {
            if let d = self.cache[text] { done(d); return }
            self.jobs.append((text, voice, done))
            self.pump()
        }
    }

    private func pump() {
        if busy || jobs.isEmpty { return }
        busy = true
        let (text, voice, done) = jobs.removeFirst()
        if let d = cache[text] { done(d); busy = false; pump(); return }
        renderOne(text, voice: voice) { d in
            done(d)
            self.busy = false
            self.pump()
        }
    }

    private func renderOne(_ text: String, voice: AVSpeechSynthesisVoice?, done: @escaping (Data?) -> Void) {
        do {
            let syn = AVSpeechSynthesizer()
            self.live.append(syn)
            let u = AVSpeechUtterance(string: text)
            u.voice = voice
            u.rate = 0.42
            u.pitchMultiplier = 1.12
            u.volume = 1.0
            var pcm = Data()
            var rate = 22050
            var finished = false
            var tick = 0
            func finish() {
                if finished { return }
                finished = true
                self.live.removeAll { $0 === syn }
                if pcm.isEmpty { self.lastError = "음성 데이터 없음"; done(nil); return }
                let wav = TTSRender.wav(pcm, rate: rate)
                self.cache[text] = wav
                self.order.append(text)
                if self.order.count > 120 { self.cache.removeValue(forKey: self.order.removeFirst()) }
                done(wav)
            }
            func idleCheck(_ mark: Int) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { if mark == tick && !pcm.isEmpty { finish() } }
            }
            syn.write(u) { buf in
                guard let b = buf as? AVAudioPCMBuffer, b.frameLength > 0 else {
                    DispatchQueue.main.async { finish() }
                    return
                }
                let n = Int(b.frameLength)
                let sr = Int(b.format.sampleRate)
                var samples = [Int16](repeating: 0, count: n)
                if let f = b.floatChannelData {
                    for i in 0..<n { samples[i] = Int16(max(-1, min(1, f[0][i])) * 32767) }
                } else if let s = b.int16ChannelData {
                    for i in 0..<n { samples[i] = s[0][i] }
                } else if let s = b.int32ChannelData {
                    for i in 0..<n { samples[i] = Int16(truncatingIfNeeded: s[0][i] >> 16) }
                }
                let chunk = samples.withUnsafeBufferPointer { Data(buffer: $0) }
                DispatchQueue.main.async {
                    rate = sr
                    pcm.append(chunk)
                    tick += 1
                    idleCheck(tick)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { finish() }
        }
    }

    static func wav(_ pcm: Data, rate: Int) -> Data {
        var d = Data()
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append(Data("RIFF".utf8)); u32(36 + pcm.count); d.append(Data("WAVE".utf8))
        d.append(Data("fmt ".utf8)); u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
        d.append(Data("data".utf8)); u32(pcm.count); d.append(pcm)
        return d
    }
}
