import UIKit
import AVFoundation
import GameController

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Store.setup()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        _ = Server.shared.start()
        application.isIdleTimerDisabled = true
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = HostViewController()
        w.makeKeyAndVisible()
        window = w
        return true
    }
}

/// 웹 화면(한글 별밤)을 띄우고, 시리 리모컨·컨트롤러 입력을 웹앱의 window.tvKey 로 넘긴다.
final class HostViewController: UIViewController {
    private var web: UIView?
    private var lastDir = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.07, green: 0.09, blue: 0.21, alpha: 1)
        if let w = makeWebView() {
            w.frame = view.bounds
            w.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            // 입력은 모두 이 화면이 받아서 웹앱(window.tvKey)으로 넘긴다
            w.isUserInteractionEnabled = false
            if w.responds(to: NSSelectorFromString("scrollView")), let sv = w.value(forKey: "scrollView") as? UIScrollView { sv.isScrollEnabled = false; sv.bounces = false }
            w.isOpaque = false
            w.backgroundColor = view.backgroundColor
            view.addSubview(w)
            web = w
            let url = URL(string: "http://127.0.0.1:\(Server.shared.port)/index.html")!
            let sel = NSSelectorFromString("loadRequest:")
            if w.responds(to: sel) { _ = w.perform(sel, with: URLRequest(url: url) as NSURLRequest) }
        } else {
            let l = UILabel(frame: view.bounds)
            l.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            l.textAlignment = .center
            l.textColor = .white
            l.numberOfLines = 0
            l.font = UIFont.systemFont(ofSize: 40)
            l.text = "웹 화면을 만들 수 없어요.\n이 Apple TV 버전은 지원되지 않습니다."
            view.addSubview(l)
        }
        for d in [UISwipeGestureRecognizer.Direction.up, .down, .left, .right] {
            let g = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
            g.direction = d
            view.addGestureRecognizer(g)
        }
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] n in
            if let c = n.object as? GCController { self?.bind(c) }
        }
        GCController.controllers().forEach { bind($0) }
    }

    // MARK: 웹뷰 만들기 (tvOS 에는 공개 WebKit 이 없어 런타임에 불러온다)
    private func makeWebView() -> UIView? {
        for p in ["/System/Library/Frameworks/WebKit.framework/WebKit",
                  "/System/Library/PrivateFrameworks/WebKit.framework/WebKit"] {
            if dlopen(p, RTLD_NOW) != nil { break }
        }
        if let cls = NSClassFromString("WKWebView") as? NSObject.Type,
           let cfgCls = NSClassFromString("WKWebViewConfiguration") as? NSObject.Type {
            let cfg = cfgCls.init()
            if cfg.responds(to: NSSelectorFromString("setMediaTypesRequiringUserActionForPlayback:")) {
                cfg.setValue(0, forKey: "mediaTypesRequiringUserActionForPlayback")
            }
            if cfg.responds(to: NSSelectorFromString("setAllowsInlineMediaPlayback:")) {
                cfg.setValue(true, forKey: "allowsInlineMediaPlayback")
            }
            let allocSel = NSSelectorFromString("alloc")
            if let raw = (cls as AnyObject).perform(allocSel)?.takeUnretainedValue() as? NSObject {
                let sel = NSSelectorFromString("initWithFrame:configuration:")
                if raw.responds(to: sel) {
                    typealias InitFn = @convention(c) (AnyObject, Selector, CGRect, AnyObject) -> Unmanaged<AnyObject>
                    let fn = unsafeBitCast(raw.method(for: sel), to: InitFn.self)
                    let v = fn(raw, sel, UIScreen.main.bounds, cfg).takeUnretainedValue()
                    if let view = v as? UIView { Server.shared.engine = "WKWebView"; return view }
                }
            }
        }
        if let cls = NSClassFromString("UIWebView") as? UIView.Type {
            Server.shared.engine = "UIWebView"
            return cls.init(frame: UIScreen.main.bounds)
        }
        return nil
    }

    private func eval(_ js: String) {
        guard let w = web else { return }
        let s1 = NSSelectorFromString("evaluateJavaScript:completionHandler:")
        if w.responds(to: s1) {
            typealias EvalFn = @convention(c) (AnyObject, Selector, NSString, @escaping @convention(block) (AnyObject?, AnyObject?) -> Void) -> Void
            let fn = unsafeBitCast(w.method(for: s1), to: EvalFn.self)
            fn(w, s1, js as NSString, { _, _ in })
            return
        }
        let s2 = NSSelectorFromString("stringByEvaluatingJavaScriptFromString:")
        if w.responds(to: s2) { _ = w.perform(s2, with: js) }
    }

    private func send(_ key: String) {
        eval("window.tvKey&&window.tvKey('\(key)')")
    }

    // MARK: 시리 리모컨
    @objc private func swiped(_ g: UISwipeGestureRecognizer) {
        switch g.direction {
        case .up: send("up")
        case .down: send("down")
        case .left: send("left")
        default: send("right")
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for p in presses {
            switch p.type {
            case .upArrow: send("up"); handled = true
            case .downArrow: send("down"); handled = true
            case .leftArrow: send("left"); handled = true
            case .rightArrow: send("right"); handled = true
            case .select: send("select"); handled = true
            case .menu:
                // 첫 화면에서만 앱을 나간다. 그 밖에서는 '뒤로'.
                if Server.shared.screen != "home" { send("back"); handled = true }
            default: break
            }
        }
        if !handled { super.pressesBegan(presses, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .menu }) && Server.shared.screen != "home" { return }
        super.pressesEnded(presses, with: event)
    }

    // MARK: 게임 컨트롤러(블루투스 패드)
    private func bind(_ c: GCController) {
        guard let g = c.extendedGamepad else { return }
        g.dpad.valueChangedHandler = { [weak self] _, x, y in self?.axis(x, y) }
        g.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in self?.axis(x, y) }
        g.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in if pressed { self?.send("select") } }
        g.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in if pressed { self?.send("back") } }
    }

    private func axis(_ x: Float, _ y: Float) {
        var d = ""
        if x < -0.6 { d = "left" } else if x > 0.6 { d = "right" } else if y > 0.6 { d = "up" } else if y < -0.6 { d = "down" }
        if d != lastDir {
            lastDir = d
            if !d.isEmpty { send(d) }
        }
    }
}
