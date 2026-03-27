import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

// MARK: - VICE Settings

class VICESettings {
    static let shared = VICESettings()
    private init() {}

    private let c64PathKey = "VICE_C64_Path"
    private let c128PathKey = "VICE_C128_Path"

    var c64Path: String? {
        get { UserDefaults.standard.string(forKey: c64PathKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: c64PathKey)
        }
    }

    var c128Path: String? {
        get { UserDefaults.standard.string(forKey: c128PathKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: c128PathKey)
        }
    }

    var hasC64: Bool {
        guard let p = c64Path, !p.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: p)
    }

    var hasC128: Bool {
        guard let p = c128Path, !p.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: p)
    }
}

// MARK: - VICE Path Setup Window

struct VICESetupWindow {
    static func show() {
        let state = VICESetupState()
        let view = NSHostingController(rootView: VICESetupView(state: state))
        let window = NSWindow(contentViewController: view)
        window.title = "VICE Emulator Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 620, height: 220))
        window.center()
        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        objc_setAssociatedObject(window, "controller", controller, .OBJC_ASSOCIATION_RETAIN)
    }
}

class VICESetupState: ObservableObject {
    @Published var c64Path: String
    @Published var c128Path: String

    init() {
        c64Path = VICESettings.shared.c64Path ?? ""
        c128Path = VICESettings.shared.c128Path ?? ""
    }

    func save() {
        VICESettings.shared.c64Path = c64Path.isEmpty ? nil : c64Path
        VICESettings.shared.c128Path = c128Path.isEmpty ? nil : c128Path
    }

    func browseC64() {
        if let path = Self.browseForApp(title: "Locate C64 Emulator (x64sc)") {
            c64Path = path
            save()
        }
    }

    func browseC128() {
        if let path = Self.browseForApp(title: "Locate C128 Emulator (x128)") {
            c128Path = path
            save()
        }
    }

    func autoDetect() {
        let searchPaths = [
            "/Applications/VICE",
            "/Applications/vice",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]

        // Also search /Applications for any VICE-like folder
        var allPaths = searchPaths
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: "/Applications") {
            for item in contents where item.lowercased().contains("vice") {
                allPaths.append("/Applications/" + item)
            }
        }

        for basePath in allPaths {
            // Check for .app bundles
            if c64Path.isEmpty {
                let candidates = [
                    basePath + "/x64sc.app",
                    basePath + "/x64sc",
                    basePath + "/bin/x64sc",
                ]
                for c in candidates {
                    if FileManager.default.fileExists(atPath: c) {
                        c64Path = c; break
                    }
                }
            }
            if c128Path.isEmpty {
                let candidates = [
                    basePath + "/x128.app",
                    basePath + "/x128",
                    basePath + "/bin/x128",
                ]
                for c in candidates {
                    if FileManager.default.fileExists(atPath: c) {
                        c128Path = c; break
                    }
                }
            }
        }
        save()
    }

    private static func browseForApp(title: String) -> String? {
        let panel = NSOpenPanel()
        panel.message = title + "\n(Select the binary file, e.g. inside the bin/ folder)"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.treatsFilePackagesAsDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            return url.path
        }
        return nil
    }
}

struct VICESetupView: View {
    @ObservedObject var state: VICESetupState
    private let monoFont = "C64 Pro Mono"

    private var c64Exists: Bool {
        !state.c64Path.isEmpty && FileManager.default.fileExists(atPath: state.c64Path)
    }
    private var c128Exists: Bool {
        !state.c128Path.isEmpty && FileManager.default.fileExists(atPath: state.c128Path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VICE EMULATOR PATHS")
                .font(.custom(monoFont, size: 14))
                .foregroundColor(Color.c64Blue)

            // C64 path
            HStack {
                Text("C64:")
                    .font(.custom(monoFont, size: 11))
                    .foregroundColor(Color.c64LightBlue)
                    .frame(width: 55, alignment: .trailing)
                    .fixedSize()
                TextField("Path to x64sc", text: $state.c64Path)
                    .font(.system(size: 11, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                Button("Browse…") { state.browseC64() }
                    .font(.system(size: 11))
                statusDot(exists: c64Exists)
            }

            // C128 path
            HStack {
                Text("C128:")
                    .font(.custom(monoFont, size: 11))
                    .foregroundColor(Color.c64LightBlue)
                    .frame(width: 55, alignment: .trailing)
                    .fixedSize()
                TextField("Path to x128", text: $state.c128Path)
                    .font(.system(size: 11, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                Button("Browse…") { state.browseC128() }
                    .font(.system(size: 11))
                statusDot(exists: c128Exists)
            }

            HStack {
                Button("Auto-Detect") { state.autoDetect() }

                Spacer()

                Text(c64Exists || c128Exists ? "Ready" : "Not configured")
                    .font(.custom(monoFont, size: 10))
                    .foregroundColor(c64Exists || c128Exists ? .green : .orange)

                Spacer()

                Button("Cancel") {
                    NSApplication.shared.keyWindow?.close()
                }

                Button("Save") {
                    state.save()
                    NSApplication.shared.keyWindow?.close()
                }
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(20)
        .frame(width: 620, height: 220)
    }

    func statusDot(exists: Bool) -> some View {
        Circle()
            .fill(exists ? Color.green : Color.red.opacity(0.5))
            .frame(width: 8, height: 8)
    }
}

// MARK: - VICE Launcher

struct VICELauncher {

    enum Emulator {
        case c64
        case c128

        var label: String {
            switch self {
            case .c64: return "C64"
            case .c128: return "C128"
            }
        }
    }

    /// Launch the whole disk in the specified emulator (attach to drive 8)
    static func launch(document: D64Document, emulator: Emulator) {
        document.saveDocument()

        guard let diskURL = document.fileURL ?? NSApplication.shared.keyWindow?.representedURL else {
            showSaveFirstAlert()
            return
        }

        guard let emuPath = pathFor(emulator: emulator) else {
            showNotConfiguredAlert(emulator: emulator)
            return
        }

        guard let binary = resolveBinary(emuPath) else {
            showBinaryNotFoundAlert(path: emuPath)
            return
        }

        // MNIB files can't be loaded by VICE directly — convert to a virtual D64 temp file first
        if document.diskFormat == .nib,
           let virtualD64 = NIBParser.buildVirtualD64(from: document.data) {
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("diskinspector_vice.d64")
            do {
                try virtualD64.write(to: tempURL)
                launchBinary(binary, args: ["-8", tempURL.path])
            } catch {
                showLaunchError(path: binary, error: error)
            }
            return
        }

        // -8 attaches disk to drive 8
        launchBinary(binary, args: ["-8", diskURL.path])
    }

    /// Launch a specific file from the disk in the specified emulator (autostart)
    static func launchFile(document: D64Document, file: D64File, emulator: Emulator) {
        document.saveDocument()

        guard let diskURL = document.fileURL ?? NSApplication.shared.keyWindow?.representedURL else {
            showSaveFirstAlert()
            return
        }

        guard let emuPath = pathFor(emulator: emulator) else {
            showNotConfiguredAlert(emulator: emulator)
            return
        }

        guard let binary = resolveBinary(emuPath) else {
            showBinaryNotFoundAlert(path: emuPath)
            return
        }

        // MNIB files can't be loaded by VICE directly — convert to a virtual D64 temp file first
        let targetURL: URL
        if document.diskFormat == .nib,
           let virtualD64 = NIBParser.buildVirtualD64(from: document.data) {
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("diskinspector_vice.d64")
            do {
                try virtualD64.write(to: tempURL)
                targetURL = tempURL
            } catch {
                showLaunchError(path: binary, error: error)
                return
            }
        } else {
            targetURL = diskURL
        }

        // -autostart with "disk:filename" loads and runs the file.
        // VICE expects the filename in the host encoding (UTF-8 on macOS).
        // PETSCII special chars are stored as Unicode PUA (U+E0xx); their 3-byte UTF-8
        // sequences confuse VICE, which reads them as three separate characters.
        // Replace each PUA char with '?' — CBM DOS treats it as a single-char wildcard
        // so the pattern still matches the correct file by both content and length.
        let safeFilename = file.filename.unicodeScalars.map { scalar -> String in
            scalar.value >= 0xE000 && scalar.value <= 0xE0FF ? "?" : String(scalar)
        }.joined().lowercased()
        let autostartArg = "\(targetURL.path):\(safeFilename)"
        launchBinary(binary, args: ["-autostart", autostartArg])
    }

    // MARK: - Private

    private static func pathFor(emulator: Emulator) -> String? {
        let settings = VICESettings.shared
        switch emulator {
        case .c64:
            guard let path = settings.c64Path, !path.isEmpty else { return nil }
            return path
        case .c128:
            guard let path = settings.c128Path, !path.isEmpty else { return nil }
            return path
        }
    }

    /// Resolve a path to the actual executable binary.
    private static func resolveBinary(_ path: String) -> String? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return nil }

        // Check for .app bundle FIRST (they are directories on macOS)
        if path.hasSuffix(".app") {
            let appName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            let candidates = [
                path + "/Contents/MacOS/" + appName,
                path + "/Contents/Resources/bin/" + appName,
            ]
            for c in candidates {
                if fm.fileExists(atPath: c) { return c }
            }
            return nil
        }

        // Check if it's a direct executable file
        var isDir: ObjCBool = false
        fm.fileExists(atPath: path, isDirectory: &isDir)

        if !isDir.boolValue { return path }

        // It's a directory — look for binaries inside
        for name in ["x64sc", "x128", "x64"] {
            let binPath = path + "/bin/" + name
            if fm.fileExists(atPath: binPath) { return binPath }
            let directPath = path + "/" + name
            if fm.fileExists(atPath: directPath) { return directPath }
        }
        return nil
    }

    /// Launch a binary directly with arguments.
    /// When the binary lives inside a macOS .app bundle, uses `open -n` to force a new
    /// VICE instance instead of bringing an existing one to the front.
    private static func launchBinary(_ binaryPath: String, args: [String]) {
        let process = Process()

        if binaryPath.contains(".app/Contents/") {
            // Derive the .app path from the inner binary path
            // e.g. "/Applications/VICE/x64sc.app/Contents/MacOS/x64sc" → "/Applications/VICE/x64sc.app"
            let appPath = binaryPath.components(separatedBy: ".app/Contents/").first! + ".app"
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-n", "-a", appPath, "--args"] + args
        } else {
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: binaryPath).deletingLastPathComponent()
        }

        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            showLaunchError(path: binaryPath, error: error)
        }
    }

    private static func showLaunchError(path: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = "Failed to Launch VICE"
        alert.informativeText = "Could not run: \(path)\n\(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func showSaveFirstAlert() {
        let alert = NSAlert()
        alert.messageText = "Save First"
        alert.informativeText = "Please save the disk image before launching in VICE."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func showNotConfiguredAlert(emulator: Emulator) {
        let alert = NSAlert()
        alert.messageText = "\(emulator.label) Emulator Not Configured"
        alert.informativeText = "Set the path to the \(emulator.label) emulator in Disk Inspector → VICE Settings."
        alert.addButton(withTitle: "Open Settings…")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            VICESetupWindow.show()
        }
    }

    private static func showBinaryNotFoundAlert(path: String) {
        let alert = NSAlert()
        alert.messageText = "Emulator Binary Not Found"
        alert.informativeText = "Could not find an executable at:\n\(path)\n\nPlease check your VICE Settings."
        alert.addButton(withTitle: "Open Settings…")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            VICESetupWindow.show()
        }
    }
}
