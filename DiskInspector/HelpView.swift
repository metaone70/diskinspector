import SwiftUI
import AppKit

// MARK: - Help Window

struct HelpWindow {
    static func show() {
        let view = NSHostingController(rootView: HelpView())
        let window = NSWindow(contentViewController: view)
        window.title = "Disk Inspector — Help"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 560, height: 620))
        window.minSize = NSSize(width: 480, height: 400)
        window.center()
        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        objc_setAssociatedObject(window, "controller", controller, .OBJC_ASSOCIATION_RETAIN)
    }
}

// MARK: - Help View

struct HelpView: View {
    private let monoFont = "C64 Pro Mono"

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {

                // Title
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        if let appIcon = NSApplication.shared.applicationIconImage {
                            Image(nsImage: appIcon)
                                .resizable()
                                .frame(width: 64, height: 64)
                        }
                        Text("DISK INSPECTOR")
                            .font(.custom(monoFont, size: 18))
                            .foregroundColor(Color.c64Blue)
                        Text("User Guide")
                            .font(.custom(monoFont, size: 12))
                            .foregroundColor(Color.c64LightBlue)
                    }
                    Spacer()
                }
                .padding(.bottom, 8)

                // Sections
                helpSection("DISK FORMAT SUPPORT") {
                    helpLine("D64 — 1541 single-sided (170 KB, 35 tracks)")
                    helpLine("D71 — 1571 double-sided (340 KB, 70 tracks)")
                    helpLine("D81 — 1581 (800 KB, 80 tracks)")
                    helpLine("Create new blank disks in any format")
                    helpLine("Open, save, and Save As with correct extension")
                }

                helpSection("FILE OPERATIONS") {
                    helpLine("View directory in authentic C64 style")
                    helpLine("Copy files between disks (drag-and-drop or Cmd-C/V)")
                    helpLine("Multi-select with Cmd-click, Shift-click, Cmd-A")
                    helpLine("Delete files (Delete key or right-click)")
                    helpLine("Rename files (right-click or double-click name)")
                    helpLine("Reorder files (drag within same disk)")
                    helpLine("Import files from Mac (PRG, SEQ, USR)")
                    helpLine("Export files to Mac filesystem")
                    helpLine("Undo / Redo all operations")
                }

                helpSection("KEYBOARD SHORTCUTS") {
                    shortcutLine("Cmd-C", "Copy selected files")
                    shortcutLine("Cmd-V", "Paste files")
                    shortcutLine("Cmd-A", "Select all files")
                    shortcutLine("Cmd-Z", "Undo")
                    shortcutLine("Cmd-Shift-Z", "Redo")
                    shortcutLine("Cmd-S", "Save")
                    shortcutLine("Cmd-Shift-S", "Save As")
                    shortcutLine("Delete", "Delete selected files")
                    shortcutLine("Double-click", "View file (BASIC or Hex)")
                }

                helpSection("HEX EDITOR") {
                    helpLine("Double-click any file to open hex view")
                    helpLine("Click a byte to select, type hex digits to edit")
                    helpLine("Arrow keys and Tab to navigate")
                    helpLine("Modified bytes shown in orange")
                    helpLine("Save to Disk writes changes to the disk image")
                }

                helpSection("BASIC LISTING VIEWER") {
                    helpLine("Auto-detects BASIC programs (C64 and C128)")
                    helpLine("Detokenizes BASIC 2.0 and BASIC 7.0")
                    helpLine("Double-click a BASIC PRG to see the listing")
                    helpLine("Non-BASIC files open in hex editor instead")
                }

                helpSection("VISUAL BAM MAP") {
                    helpLine("Click BAM button to see the sector map")
                    helpLine("Green=free, Blue=file, Grey=system, Red=orphaned")
                    helpLine("Select a file to highlight its sector chain")
                    helpLine("Hover a sector for track/sector and owner info")
                    helpLine("Click a sector to edit it in hex")
                }

                helpSection("DISK VALIDATION") {
                    helpLine("Click VALIDATE to check disk integrity")
                    helpLine("Detects BAM errors and cross-linked files")
                    helpLine("Finds orphaned/lost sectors")
                    helpLine("Verifies block counts and sector chains")
                    helpLine("Reports duplicate filenames")
                }

                helpSection("EXPORT") {
                    helpLine("Right-click background for export options")
                    helpLine("Export Directory as Text — plain text listing")
                    helpLine("Export Directory as HTML — styled C64 theme page")
                }

                helpSection("VICE INTEGRATION") {
                    helpLine("Right-click a file to run in C64 or C128")
                    helpLine("Open entire disk in VICE emulator")
                    helpLine("Set emulator paths in VICE Settings (app menu)")
                    helpLine("Supports GTK3 VICE for macOS (x64sc, x128)")
                }

                helpSection("DISK INFO PANEL") {
                    helpLine("Click INFO to toggle the info panel")
                    helpLine("Shows disk name, ID, format, and DOS version")
                    helpLine("Usage bar with used/free block count")
                    helpLine("File count breakdown by type")
                }

                helpSection("TIPS") {
                    helpLine("Open multiple disks and drag files between them")
                    helpLine("Double-click the disk header to rename the disk")
                    helpLine("Right-click empty area for Paste and Import")
                    helpLine("The C64 Pro Mono font is bundled in the app")
                }

                // Footer
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text("© 2026 metesev")
                            .font(.custom(monoFont, size: 10))
                            .foregroundColor(Color.c64LightBlue.opacity(0.6))
                        Link("metesev.itch.io", destination: URL(string: "https://metesev.itch.io")!)
                            .font(.custom(monoFont, size: 10))
                            .foregroundColor(Color.c64Blue)
                    }
                    Spacer()
                }
                .padding(.top, 8)
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(minWidth: 480, minHeight: 400)
    }

    // MARK: - Helpers

    func helpSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.custom(monoFont, size: 13))
                .foregroundColor(Color.c64Blue)
                .padding(.bottom, 2)
            content()
        }
    }

    func helpLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("·")
                .font(.custom(monoFont, size: 11))
                .foregroundColor(Color.c64LightBlue)
            Text(text)
                .font(.custom(monoFont, size: 11))
                .foregroundColor(Color.c64LightBlue)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func shortcutLine(_ key: String, _ action: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(key)
                .font(.custom(monoFont, size: 11))
                .foregroundColor(Color.c64Blue)
                .frame(width: 140, alignment: .leading)
            Text(action)
                .font(.custom(monoFont, size: 11))
                .foregroundColor(Color.c64LightBlue)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
