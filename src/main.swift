import AppKit
import ServiceManagement

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    enum State: String { case ready, busy, error }
    private(set) var state: State = .ready
    private(set) var saved: [URL] = []
    private(set) var lastError: String?
    private(set) var transitions: [String] = []
    private(set) var capturedDisplay: CGDirectDisplayID?
    private(set) var statusItem: NSStatusItem!
    private var loginError: String?
    private var permissionRequested = false
    private var generation = UUID()
    private var timeout: Timer?
    let verificationDirectory: URL?
    var outputOverride: URL? // Wyłącznie tryb kontroli --verify, brak opcji w produkcie.
    var verifier: BuildVerifier?

    init(verificationDirectory: URL?) { self.verificationDirectory = verificationDirectory }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if verificationDirectory == nil,
           let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: 30)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Pstryk — zrzut całego ekranu")
        }
        setState(.ready)
        if let directory = verificationDirectory {
            verifier = BuildVerifier(app: self, directory: directory)
            verifier?.start()
        } else {
            registerFirstLogin()
        }
    }

    private func setState(_ value: State, detail: String? = nil) {
        state = value
        transitions.append(value.rawValue)
        statusItem.button?.image = CameraIcon.image(color: value == .ready ? CameraIcon.blue : CameraIcon.red)
        switch value {
        case .ready: statusItem.button?.toolTip = "Pstryk — kliknij, aby zapisać cały ekran w Pobranych. Prawy klik: menu."
        case .busy: statusItem.button?.toolTip = "Pstryk — zapisuję zrzut…"
        case .error: statusItem.button?.toolTip = detail ?? "Pstryk — błąd zapisu. Kliknij, aby spróbować ponownie."
        }
    }

    @objc func clicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            let menu = makeMenu()
            statusItem.menu = menu
            menu.delegate = self
            statusItem.button?.performClick(nil)
        } else { takeScreenshot() }
    }

    func menuDidClose(_ menu: NSMenu) { statusItem.menu = nil }

    func takeScreenshot() {
        guard state != .busy else { return } // Podwójny klik nie uruchamia dwóch zapisów naraz.
        let display = Capture.displayAtPointer()
        capturedDisplay = display
        setState(.busy)
        lastError = nil
        guard CGPreflightScreenCaptureAccess() else {
            // Tylko jawny klik użytkownika może wywołać systemowy monit.
            if verificationDirectory == nil && !permissionRequested {
                permissionRequested = true
                _ = CGRequestScreenCaptureAccess()
                if !CGPreflightScreenCaptureAccess() { openScreenSettings(nil) }
            }
            if !CGPreflightScreenCaptureAccess() { fail(CaptureError.permission); return }
            startCapture(display: display)
            return
        }
        startCapture(display: display)
    }

    private func startCapture(display: CGDirectDisplayID) {
        let token = UUID()
        generation = token
        let began = Date()
        timeout?.invalidate()
        timeout = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            guard let owner = self else { return }
            Task { @MainActor in
                guard owner.generation == token, owner.state == .busy else { return }
                owner.generation = UUID()
                owner.fail(CaptureError.write("Upłynął czas odczytu ekranu. Spróbuj ponownie."))
            }
        }
        Task {
            do {
                let image = try await Capture.image(displayID: display)
                guard generation == token else { return }
                // Po pobraniu ekranu kontrolujemy zakończenie rzeczywistego zapisu na dysku.
                timeout?.invalidate()
                let folder = try outputOverride ?? Capture.downloads()
                let url = try await Task.detached(priority: .userInitiated) {
                    try Capture.savePNG(image, directory: folder)
                }.value
                saved.append(url)
                // Czerwony stan widoczny co najmniej pół sekundy, również na szybkim SSD.
                let rest = max(0, 0.5 - Date().timeIntervalSince(began))
                if rest > 0 { try? await Task.sleep(nanoseconds: UInt64(rest * 1_000_000_000)) }
                setState(.ready)
            } catch {
                guard generation == token else { return }
                fail(error)
            }
        }
    }

    private func fail(_ error: Error) {
        timeout?.invalidate()
        lastError = error.localizedDescription
        // Bez okien/banerów/dźwięków. Czerwony pozostaje, by nie udawać udanego zapisu.
        setState(.error, detail: lastError)
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if let error = lastError {
            let item = NSMenuItem(title: error, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            if !CGPreflightScreenCaptureAccess() {
                addItem("Zezwól na zrzuty ekranu…", #selector(openScreenSettings(_:)), to: menu)
            }
            menu.addItem(.separator())
        }
        let status = SMAppService.mainApp.status
        let login = addItem(status == .requiresApproval ? "Autostart — zatwierdź w ustawieniach…" : "Uruchamiaj po zalogowaniu",
                            #selector(toggleLogin(_:)), to: menu)
        login.state = status == .enabled ? .on : (status == .requiresApproval ? .mixed : .off)
        if let error = loginError {
            let item = NSMenuItem(title: error, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())
        addItem("Zakończ Pstryk", #selector(quit(_:)), to: menu)
        return menu
    }

    @discardableResult private func addItem(_ title: String, _ action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    private func registerFirstLogin() {
        let path = Bundle.main.bundleURL.standardizedFileURL.path
        let userApps = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path + "/"
        guard path.hasPrefix("/Applications/") || path.hasPrefix(userApps) else { return }
        guard !UserDefaults.standard.bool(forKey: "loginConfigured") else { return }
        if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
            UserDefaults.standard.set(true, forKey: "loginConfigured")
            return
        }
        do {
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "loginConfigured")
        } catch { loginError = "Nie włączono autostartu. Włącz go tutaj albo w ustawieniach macOS." }
    }

    @objc private func toggleLogin(_ sender: Any?) {
        guard verificationDirectory == nil else { return }
        do {
            switch SMAppService.mainApp.status {
            case .enabled: try SMAppService.mainApp.unregister()
            case .requiresApproval: SMAppService.openSystemSettingsLoginItems()
            default: try SMAppService.mainApp.register()
            }
            UserDefaults.standard.set(true, forKey: "loginConfigured")
            loginError = nil
        } catch { loginError = "Autostart: " + error.localizedDescription }
    }

    @objc private func openScreenSettings(_ sender: Any?) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit(_ sender: Any?) {
        // Zakończenie w trakcie zapisu odkładamy do jego końca.
        if state == .busy {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.quit(nil) }
        } else { NSApp.terminate(nil) }
    }

    func applicationWillTerminate(_ notification: Notification) { timeout?.invalidate() }
}

let arguments = CommandLine.arguments
let verification: URL?
if let index = arguments.firstIndex(of: "--verify"), arguments.indices.contains(index + 1) {
    verification = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
} else { verification = nil }
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate(verificationDirectory: verification)
    application.delegate = delegate
    withExtendedLifetime(delegate) { application.run() }
}
