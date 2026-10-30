import AppKit
import WebKit

let width: CGFloat = 300
let height: CGFloat = 380
let margin: CGFloat = 24

let saveURL: URL = {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("DeskNote", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("note.txt")
}()

// Borderless windows refuse keyboard focus by default.
class NoteWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

class NoteTextView: NSTextView {
    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) { onEscape?() }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit DeskNote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        return menu
    }
}

// Lets a click on the unfocused note switch straight to editing.
class PreviewWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate, NSWindowDelegate,
                   WKNavigationDelegate, WKScriptMessageHandler {
    var window: NoteWindow!
    var scroll: NSScrollView!
    var textView: NoteTextView!
    var webView: PreviewWebView!
    var pageLoaded = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NoteWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        // Sit on the desktop: above the icons, below every normal window.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.delegate = self

        let blur = NSVisualEffectView()
        blur.material = .popover
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 16
        blur.layer?.masksToBounds = true
        window.contentView = blur

        scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: blur.topAnchor, constant: 14),
            scroll.bottomAnchor.constraint(equalTo: blur.bottomAnchor, constant: -14),
            scroll.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -12),
        ])

        textView = NoteTextView(frame: NSRect(x: 0, y: 0, width: width - 24, height: height - 28))
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 15)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.delegate = self
        textView.onEscape = { [weak self] in self?.showPreview() }
        textView.string = (try? String(contentsOf: saveURL, encoding: .utf8)) ?? ""
        scroll.documentView = textView

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "edit")
        webView = PreviewWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: blur.topAnchor),
            webView.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
        ])
        let resources = Bundle.main.resourceURL!
        webView.loadFileURL(resources.appendingPathComponent("preview.html"), allowingReadAccessTo: resources)

        showPreview()
        position()
        NotificationCenter.default.addObserver(self, selector: #selector(position),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        window.orderFront(nil)
    }

    // Middle of the left edge of the main screen.
    @objc func position() {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        window.setFrame(NSRect(x: f.minX + margin, y: f.midY - height / 2, width: width, height: height), display: true)
    }

    func showPreview() {
        scroll.isHidden = true
        webView.isHidden = false
        render()
    }

    func showEditor() {
        webView.isHidden = true
        scroll.isHidden = false
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
        window.makeFirstResponder(textView)
    }

    func render() {
        guard pageLoaded,
              let data = try? JSONEncoder().encode(textView.string),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("render(\(json))")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageLoaded = true
        render()
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        showEditor()
    }

    func windowDidResignKey(_ notification: Notification) {
        showPreview()
    }

    func textDidChange(_ notification: Notification) {
        try? textView.string.write(to: saveURL, atomically: true, encoding: .utf8)
    }
}

// Never shown (accessory app), but ⌘V/⌘C/⌘X/⌘A/⌘Z are only routed through the main menu.
func makeMainMenu() -> NSMenu {
    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    edit.addItem(.separator())
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    let editItem = NSMenuItem()
    editItem.submenu = edit
    let main = NSMenu()
    main.addItem(NSMenuItem())
    main.addItem(editItem)
    return main
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.mainMenu = makeMainMenu()
app.setActivationPolicy(.accessory)
app.run()
