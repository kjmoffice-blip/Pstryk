// Ukryta kontrola gotowego .app. --verify KATALOG nie włącza autostartu,
// nie wywołuje monitów zgód i nie zapisuje testowych obrazów w Pobranych.
import AppKit
import ImageIO
import ServiceManagement

@MainActor final class BuildVerifier {
    unowned let app: AppDelegate
    let directory: URL
    var results: [[String: Any]] = []
    var limitations: [String] = []
    var panel: NSPanel?

    init(app: AppDelegate, directory: URL) { self.app = app; self.directory = directory }
    func record(_ test: String, _ passed: Bool, _ detail: String = "") {
        results.append(["test": test, "passed": passed, "detail": detail])
    }

    func start() {
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { fputs("Brak katalogu kontroli: \(error)\n", stderr); NSApp.terminate(nil); return }
        app.outputOverride = directory.appendingPathComponent("captures", isDirectory: true)
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await run()
        }
    }

    func waitForSave() async throws {
        for _ in 0..<250 {
            if app.state != .busy { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw CaptureError.write("Przekroczono czas kontroli.")
    }

    func makePanel() {
        let id = Capture.displayAtPointer()
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        } ?? NSScreen.screens[0]
        panel = NSPanel(contentRect: NSRect(x: screen.frame.midX - 130, y: screen.frame.midY - 70,
                                          width: 260, height: 140),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel?.level = .floating
        panel?.backgroundColor = NSColor(srgbRed: 0.12, green: 0.82, blue: 0.35, alpha: 1)
        panel?.orderFrontRegardless()
    }

    func iconPixels(_ image: NSImage?, red: Bool) -> Bool {
        guard let data = image?.tiffRepresentation, let rep = NSBitmapImageRep(data: data) else { return false }
        var count = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.alphaComponent > 0.8 else { continue }
                if red ? c.redComponent > 0.8 && c.blueComponent < 0.4
                    : c.blueComponent > 0.8 && c.redComponent < 0.3 { count += 1 }
            }
        }
        return count > 20
    }

    func run() async {
        let windows = NSApp.windows.filter { $0.isVisible }
        let regularWindows = windows.filter { String(describing: type(of: $0)) != "NSStatusBarWindow" }
        let detail = "Widoczność: \(app.statusItem.isVisible); polityka: \(NSApp.activationPolicy().rawValue); okna: \(windows.map { String(describing: type(of: $0)) })"
        record("Status item bez Docka i okna", app.statusItem.isVisible && app.statusItem.button != nil
               && NSApp.activationPolicy() == .accessory && regularWindows.isEmpty, detail)
        record("Niebieski aparat, bez trybu template", iconPixels(app.statusItem.button?.image, red: false)
               && app.statusItem.button?.image?.isTemplate == false)
        record("Menu: tylko autostart i zakończenie", app.makeMenu().items.filter { !$0.isSeparatorItem }.count == 2)
        do {
            record("Docelowy folder systemowy Pobrane", try Capture.downloads().standardizedFileURL
                   == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").standardizedFileURL)
            guard CGPreflightScreenCaptureAccess() else {
                app.takeScreenshot()
                record("Odmowa zgody: czerwony stan, bez okna", app.state == .error && app.saved.isEmpty)
                limitations.append("Brak zgody ekranu dla tego sposobu uruchomienia; nie wykonano prawdziwych zrzutów.")
                finish(); return
            }
            makePanel()
            try await Task.sleep(nanoseconds: 300_000_000)
            let before = app.saved.count
            app.statusItem.button?.performClick(nil)
            record("Klik aparatu: czerwony stan", app.state == .busy && iconPixels(app.statusItem.button?.image, red: true))
            app.takeScreenshot() // Powtórzony klik w trakcie zapisu jest ignorowany.
            try await waitForSave()
            record("Jeden zapis mimo ponownego kliknięcia", app.saved.count == before + 1, app.lastError ?? "")
            record("Powrót do niebieskiego po zapisie", app.state == .ready && iconPixels(app.statusItem.button?.image, red: false))
            guard let file = app.saved.last, let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw CaptureError.encode
            }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let id = app.capturedDisplay ?? 0
            let screen = NSScreen.screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
            }
            let logicalWidth = Int(screen?.frame.width ?? 0)
            let logicalHeight = Int(screen?.frame.height ?? 0)
            record("Pełny PNG: wymiary ekranu", image.width >= logicalWidth && image.height >= logicalHeight
                   && logicalWidth > 0 && abs(Double(image.width) / Double(image.height) - Double(logicalWidth) / Double(logicalHeight)) < 0.02,
                   "\(image.width) × \(image.height); ekran w punktach \(logicalWidth) × \(logicalHeight); PNG \(properties != nil)")
            let bitmap = NSBitmapImageRep(cgImage: image)
            let pixel = bitmap.colorAt(x: image.width / 2, y: image.height / 2)?.usingColorSpace(.sRGB)
            record("Rzeczywisty ekran zawiera okno znacznika", pixel != nil && pixel!.greenComponent > pixel!.redComponent + 0.3
                   && pixel!.greenComponent > pixel!.blueComponent + 0.2)
            panel?.close(); panel = nil
            let original = try Data(contentsOf: file)
            let fixed = Date(timeIntervalSince1970: 1_700_000_000)
            let second = try Capture.savePNG(image, directory: app.outputOverride!, date: fixed)
            let third = try Capture.savePNG(image, directory: app.outputOverride!, date: fixed)
            let contents = try [second, third, file].map { try Data(contentsOf: $0) }
            record("Kolizja czasu nie nadpisuje plików", second != third && contents.allSatisfy { $0 == original })
            let bad = directory.appendingPathComponent("not-a-directory")
            try Data("fixture".utf8).write(to: bad)
            let folder = app.outputOverride
            app.outputOverride = bad
            app.takeScreenshot()
            try await waitForSave()
            record("Błąd dysku: czerwony, bez zapisanego pliku", app.state == .error && app.saved.count == before + 1
                   && app.lastError != nil && iconPixels(app.statusItem.button?.image, red: true))
            app.outputOverride = folder
            app.takeScreenshot()
            try await waitForSave()
            record("Ponowna próba po błędzie działa", app.state == .ready && app.saved.count == before + 2)
            let files = try FileManager.default.contentsOfDirectory(atPath: folder!.path)
            record("Brak częściowych plików po zapisie", !files.contains { $0.hasSuffix(".tmp") })
            do {
                _ = try await Capture.image(displayID: UInt32.max)
                record("Obsługa odłączonego monitora", false)
            } catch CaptureError.missingDisplay { record("Obsługa odłączonego monitora", true) }
            catch { record("Obsługa odłączonego monitora", false, error.localizedDescription) }
            if CommandLine.arguments.contains("--verify-login") {
                let initial = SMAppService.mainApp.status
                if initial == .notRegistered || initial == .notFound {
                    do {
                        try SMAppService.mainApp.register()
                        let registered = SMAppService.mainApp.status
                        try await SMAppService.mainApp.unregister()
                        record("Rejestracja i wyrejestrowanie autostartu", registered == .enabled || registered == .requiresApproval,
                               "Po rejestracji: \(registered.rawValue); po usunięciu: \(SMAppService.mainApp.status.rawValue)")
                    } catch {
                        try? await SMAppService.mainApp.unregister()
                        limitations.append("Rejestracja autostartu niepotwierdzona: " + error.localizedDescription)
                    }
                } else { limitations.append("Autostart już zarejestrowany; zachowano istniejący stan.") }
            }
        } catch { record("Kontrola wykonania", false, error.localizedDescription) }
        finish()
    }

    func finish() {
        panel?.close()
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        limitations.append("Nie testowano wylogowania/restartu, drugiego fizycznego monitora ani fizycznego Maca Intel. Rozdzielczość 2× sprawdzona na ekranie środowiska testowego.")
        let report: [String: Any] = ["architecture": architecture,
            "system": ProcessInfo.processInfo.operatingSystemVersionString,
            "bundle": Bundle.main.bundleURL.path, "checks": results,
            "limitations": limitations, "transitions": app.transitions,
            "allChecksPassed": results.allSatisfy { $0["passed"] as? Bool == true },
            "captureCount": app.saved.count,
            "windowsAfterTest": NSApp.windows.filter { $0.isVisible && String(describing: type(of: $0)) != "NSStatusBarWindow" }.count]
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent("results.json"), options: .atomic)
        } catch { fputs("Nie zapisano raportu: \(error)\n", stderr) }
        NSApp.terminate(nil)
    }
}
