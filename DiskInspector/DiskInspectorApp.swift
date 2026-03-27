import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Maps windows to their D64Document instances so menu commands can find the active document.
final class DocumentRegistry {
    static let shared = DocumentRegistry()
    private init() {}

    private var docMap: [ObjectIdentifier: D64Document] = [:]
    private var selMap: [ObjectIdentifier: SelectionState] = [:]

    func register(window: NSWindow, document: D64Document) {
        docMap[ObjectIdentifier(window)] = document
    }

    func registerSelection(window: NSWindow, selection: SelectionState) {
        selMap[ObjectIdentifier(window)] = selection
    }

    func unregister(window: NSWindow) {
        docMap.removeValue(forKey: ObjectIdentifier(window))
        selMap.removeValue(forKey: ObjectIdentifier(window))
    }

    func document(for window: NSWindow) -> D64Document? {
        docMap[ObjectIdentifier(window)]
    }

    func selection(for window: NSWindow) -> SelectionState? {
        selMap[ObjectIdentifier(window)]
    }
}

@main
struct DiskInspectorApp: App {
    @State private var pendingFormat: DiskFormat = .d64

    var body: some Scene {
        DocumentGroup(newDocument: { D64Document(format: pendingFormat) }) { file in
            ContentView(document: file.document)
                .navigationTitle(file.document.diskDisplayName)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        if let window = NSApplication.shared.keyWindow {
                            // Register this document so Save/Save As can find it
                            DocumentRegistry.shared.register(window: window, document: file.document)
                            // Pick up existing file URL for opened documents
                            if let url = window.representedURL {
                                file.document.fileURL = url
                            }
                        }
                    }
                }
        }
        .commands {
            // ── New Disk ──
            CommandGroup(replacing: .newItem) {
                Button("New Disk…") {
                    let alert = NSAlert()
                    alert.messageText = "New Disk"
                    alert.informativeText = "Choose the format for the new disk:"
                    alert.addButton(withTitle: "D64 — 170 KB")
                    alert.addButton(withTitle: "D71 — 340 KB")
                    alert.addButton(withTitle: "D81 — 800 KB")
                    alert.alertStyle = .informational
                    switch alert.runModal() {
                    case .alertSecondButtonReturn: pendingFormat = .d71
                    case .alertThirdButtonReturn:  pendingFormat = .d81
                    default:                       pendingFormat = .d64
                    }
                    NSDocumentController.shared.newDocument(nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            // ── Save / Save As — replaces SwiftUI's built-in save ──
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    guard let window = NSApplication.shared.keyWindow,
                          let doc = DocumentRegistry.shared.document(for: window)
                    else { return }
                    doc.saveDocument()
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Save As…") {
                    guard let window = NSApplication.shared.keyWindow,
                          let doc = DocumentRegistry.shared.document(for: window)
                    else { return }
                    doc.saveDocumentAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }

            // ── Window ──
            CommandGroup(after: .windowArrangement) {
                Button("Bring All to Front") {
                    NSApplication.shared.windows.forEach { $0.orderFront(nil) }
                }
            }

            // ── Tools ──
            CommandMenu("Tools") {
                Button("Separators…") {
                    SeparatorLibraryWindow.open()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }

            // ── Help ──
            CommandGroup(replacing: .help) {
                Button("Disk Inspector Help") {
                    HelpWindow.show()
                }
            }

            // ── About ──
            CommandGroup(replacing: .appInfo) {
                Button("About Disk Inspector") {
                    AboutWindow.show()
                }

                Divider()

                Button("VICE Settings…") {
                    VICESetupWindow.show()
                }
            }
        }
    }
}

// MARK: - About Window

struct AboutWindow {
    static func show() {
        let aboutView = NSHostingController(rootView: AboutView())
        let window = NSWindow(contentViewController: aboutView)
        window.title = "About Disk Inspector"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 460, height: 330))
        window.center()
        window.isMovableByWindowBackground = true
        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        objc_setAssociatedObject(window, "controller", controller, .OBJC_ASSOCIATION_RETAIN)
    }
}

struct AboutView: View {
    private let monoFont = "C64 Pro Mono"

    var body: some View {
        VStack(spacing: 12) {
            // App icon
            if let appIcon = NSApplication.shared.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 96, height: 96)
            }

            Text("DISK INSPECTOR")
                .font(.custom(monoFont, size: 18))
                .foregroundColor(Color.c64Blue)

            Text("VERSION 1.4")
                .font(.custom(monoFont, size: 11))
                .foregroundColor(Color.c64LightBlue)

            Text("by metesev")
                .font(.custom(monoFont, size: 11))
                .foregroundColor(Color.c64LightBlue)

            Divider().frame(width: 200)

            Text("Commodore 64/128\ndisk image editor for macOS")
                .font(.custom(monoFont, size: 11))
                .foregroundColor(Color.c64Blue)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("D64 · D71 · D81")
                .font(.custom(monoFont, size: 12))
                .foregroundColor(Color.c64LightBlue)

            Text("T64 · LNX · G64 · NIB")
                .font(.custom(monoFont, size: 11))
                .foregroundColor(Color.c64LightBlue.opacity(0.7))

            Spacer().frame(height: 4)

            Text("© 2026 metesev")
                .font(.custom(monoFont, size: 10))
                .foregroundColor(Color.c64LightBlue.opacity(0.7))

            Link("metesev.itch.io", destination: URL(string: "https://metesev.itch.io")!)
                .font(.custom(monoFont, size: 10))
                .foregroundColor(Color.c64Blue)
        }
        .padding(24)
        .frame(width: 460, height: 330)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
