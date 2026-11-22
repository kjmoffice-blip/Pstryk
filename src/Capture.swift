import AppKit
import ImageIO
import UniformTypeIdentifiers
import Darwin

enum CaptureError: LocalizedError {
    case permission, missingDisplay, encode, write(String)
    var errorDescription: String? {
        switch self {
        case .permission:
            return "Włącz Pstryk w Ustawieniach systemowych → Prywatność i ochrona → Nagrywanie ekranu. Potem uruchom Pstryk ponownie."
        case .missingDisplay: return "Wybrany ekran został odłączony. Kliknij aparat na dostępnym ekranie."
        case .encode: return "Nie udało się utworzyć obrazu PNG. Kliknij, aby spróbować ponownie."
        case .write(let message): return "Nie zapisano zrzutu: \(message)"
        }
    }
}

enum Capture {
    static func downloads() throws -> URL {
        try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
    }

    @MainActor static func displayAtPointer() -> CGDirectDisplayID {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main ?? NSScreen.screens.first
        return (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value ?? CGMainDisplayID()
    }

    static func image(displayID: CGDirectDisplayID) async throws -> CGImage {
        guard CGDisplayIsOnline(displayID) != 0 else {
            throw CaptureError.missingDisplay
        }
        let bounds = CGDisplayBounds(displayID)
        guard !bounds.isEmpty else { throw CaptureError.missingDisplay }
        // Cały prostokąt monitora w globalnych współrzędnych macOS, również ujemnych.
        // Narzędzie Apple dobiera fizyczne piksele (Retina) i nie pokazuje własnego UI.
        let rect = "\(Int(bounds.minX)),\(Int(bounds.minY)),\(Int(bounds.width)),\(Int(bounds.height))"
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let fm = FileManager.default
                    let work = fm.temporaryDirectory.appendingPathComponent("Pstryk-\(UUID().uuidString)", isDirectory: true)
                    try fm.createDirectory(at: work, withIntermediateDirectories: true,
                                           attributes: [.posixPermissions: 0o700])
                    defer { try? fm.removeItem(at: work) }
                    let raw = work.appendingPathComponent("capture.png")
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    process.arguments = ["-x", "-t", "png", "-R" + rect, raw.path]
                    process.standardOutput = FileHandle.nullDevice
                    let errors = Pipe()
                    process.standardError = errors
                    try process.run()
                    let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
                    DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: watchdog)
                    process.waitUntilExit()
                    watchdog.cancel()
                    guard process.terminationStatus == 0 else {
                        let data = errors.fileHandleForReading.readDataToEndOfFile()
                        let message = String(data: data.prefix(300), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                        throw CaptureError.write(message?.isEmpty == false ? message! : "Odczyt ekranu nie powiódł się. Sprawdź zgodę ekranu i spróbuj ponownie.")
                    }
                    let data = try Data(contentsOf: raw)
                    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                          let image = CGImageSourceCreateImageAtIndex(source, 0,
                              [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { throw CaptureError.encode }
                    continuation.resume(returning: image)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    static func savePNG(_ image: CGImage, directory: URL, date: Date = Date()) throws -> URL {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CaptureError.encode
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CaptureError.encode }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        let stamp = formatter.string(from: date)
        let random = UUID().uuidString.prefix(8).lowercased()
        let target = directory.appendingPathComponent("Pstryk_\(stamp)_\(random).png")
        let temporary = directory.appendingPathComponent(".pstryk-\(UUID().uuidString).tmp")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw CaptureError.write(String(cString: strerror(errno))) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close(); try? fm.removeItem(at: temporary) }
        do {
            try handle.write(contentsOf: data as Data)
            try handle.synchronize()
            try handle.close()
        } catch { throw CaptureError.write(error.localizedDescription) }
        // Atomowe pojawienie się pełnego PNG; link nigdy nie nadpisze istniejącego pliku.
        guard link(temporary.path, target.path) == 0 else {
            throw CaptureError.write(String(cString: strerror(errno)))
        }
        return target
    }
}
