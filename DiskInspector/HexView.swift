import SwiftUI
import AppKit
import Combine

// MARK: - Hex Viewer Window Launcher

struct HexViewerWindow {
    static func open(file: D64File, document: D64Document) {
        let editor = HexEditorState(data: file.rawData)
        let hexView = NSHostingController(rootView: HexView(file: file, document: document, editor: editor))
        let window = NSWindow(contentViewController: hexView)
        let byteCount = file.rawData.count
        let sizeString = byteCount >= 1024
            ? String(format: "%.1f KB", Double(byteCount) / 1024.0)
            : "\(byteCount) bytes"
        window.title = "\(file.filename.uppercased()) — \(sizeString)"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 580, height: 520))
        window.minSize = NSSize(width: 500, height: 300)
        window.center()

        // Install a key monitor scoped to this window
        let capturedWindow = window
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard NSApplication.shared.keyWindow === capturedWindow else { return event }
            // Don't intercept if a button or text field is focused
            if let responder = capturedWindow.firstResponder,
               responder is NSText {
                return event
            }
            return editor.handleKeyEvent(event) ? nil : event
        }

        // Store references so they aren't deallocated
        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        objc_setAssociatedObject(window, "controller", controller, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(window, "monitor", monitor as AnyObject, .OBJC_ASSOCIATION_RETAIN)

        // Remove monitor when window closes
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window, queue: .main
        ) { _ in
            NSEvent.removeMonitor(monitor)
        }
    }
}

// MARK: - Hex Editor State

class HexEditorState: ObservableObject {
    let originalData: [UInt8]
    let bytesPerRow: Int
    @Published var editedData: [UInt8]
    @Published var modifiedOffsets: Set<Int> = []
    @Published var selectedOffset: Int? = nil
    @Published var inputBuffer: String = ""

    var hasChanges: Bool { !modifiedOffsets.isEmpty }

    init(data: Data, bytesPerRow: Int = 8) {
        let bytes = [UInt8](data)
        self.originalData = bytes
        self.editedData = bytes
        self.bytesPerRow = bytesPerRow
    }

    func editByte(at offset: Int, value: UInt8) {
        guard offset < editedData.count else { return }
        editedData[offset] = value
        if editedData[offset] != originalData[offset] {
            modifiedOffsets.insert(offset)
        } else {
            modifiedOffsets.remove(offset)
        }
    }

    func revert() {
        editedData = originalData
        modifiedOffsets.removeAll()
        selectedOffset = nil
        inputBuffer = ""
    }

    func selectOffset(_ offset: Int?) {
        selectedOffset = offset
        inputBuffer = ""
    }

    func moveSelection(delta: Int) {
        guard let current = selectedOffset else { return }
        let next = current + delta
        if next >= 0 && next < editedData.count {
            selectOffset(next)
        }
    }

    /// Handle a key event. Returns true if the event was consumed.
    func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard selectedOffset != nil else { return false }

        let chars = event.charactersIgnoringModifiers?.uppercased() ?? ""

        // Hex digit input
        if chars.count == 1, let char = chars.first,
           "0123456789ABCDEF".contains(char) {
            inputBuffer.append(char)
            if inputBuffer.count >= 2 {
                if let value = UInt8(inputBuffer, radix: 16),
                   let offset = selectedOffset {
                    editByte(at: offset, value: value)
                    moveSelection(delta: 1)
                }
            }
            return true
        }

        switch event.keyCode {
        case 48: // Tab
            moveSelection(delta: event.modifierFlags.contains(.shift) ? -1 : 1)
            return true
        case 124: // Right arrow
            moveSelection(delta: 1)
            return true
        case 123: // Left arrow
            moveSelection(delta: -1)
            return true
        case 125: // Down arrow
            moveSelection(delta: bytesPerRow)
            return true
        case 126: // Up arrow
            moveSelection(delta: -bytesPerRow)
            return true
        case 36: // Enter
            selectOffset(nil)
            return true
        case 53: // Escape
            selectOffset(nil)
            return true
        default:
            return false
        }
    }
}

// MARK: - Hex View

struct HexView: View {
    let file: D64File
    let document: D64Document
    @ObservedObject var editor: HexEditorState

    private let bytesPerRow = 8
    private let monoFont = "C64 Pro Mono"
    private let hexFontSize: CGFloat = 13

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── File info header ──
            fileHeader
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            // ── Toolbar ──
            toolbar
                .padding(.horizontal, 16)
                .padding(.vertical, 6)

            Divider()

            // ── Hex dump ──
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Column header
                        Text(columnHeaderString)
                            .font(.custom(monoFont, size: hexFontSize))
                            .foregroundColor(Color.c64LightBlue)
                            .frame(height: 20)
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                            .padding(.bottom, 2)

                        Divider().padding(.horizontal, 16)

                        LazyVStack(alignment: .leading, spacing: 0) {
                            let rowCount = max(1, (editor.editedData.count + bytesPerRow - 1) / bytesPerRow)
                            ForEach(0..<rowCount, id: \.self) { row in
                                hexRow(row: row)
                                    .id(row)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                }
                .onChange(of: editor.selectedOffset) {
                    if let offset = editor.selectedOffset {
                        let row = offset / bytesPerRow
                        proxy.scrollTo(row, anchor: .center)
                    }
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(minWidth: 500, minHeight: 300)
    }

    // ── Column header ──

    var columnHeaderString: String {
        "ADDR 00 01 02 03 04 05 06 07  PETSCII"
    }

    // ── File info header ──

    var fileHeader: some View {
        HStack(spacing: 24) {
            headerItem(label: "FILE", value: file.filename.uppercased())
            headerItem(label: "TYPE", value: file.fileType)
            headerItem(label: "BLOCKS", value: "\(file.blocks)")
            headerItem(label: "SIZE", value: "\(file.rawData.count) BYTES")
            headerItem(label: "START", value: String(format: "T%d/S%d", file.track, file.sector))
            Spacer()
        }
    }

    func headerItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.custom(monoFont, size: 9))
                .foregroundColor(Color.c64LightBlue)
            Text(value)
                .font(.custom(monoFont, size: 12))
                .foregroundColor(Color.c64Blue)
        }
    }

    // ── Toolbar ──

    var toolbar: some View {
        HStack(spacing: 12) {
            Button("Save to Disk") {
                // Patch the in-memory document data
                document.patchFileData(file, newData: Data(editor.editedData))
                editor.modifiedOffsets.removeAll()
                // Write to the actual file on disk
                document.saveDocument()
            }
            .disabled(!editor.hasChanges)

            Button("Revert") {
                editor.revert()
            }
            .disabled(!editor.hasChanges)

            Spacer()

            if editor.hasChanges {
                Text("\(editor.modifiedOffsets.count) byte\(editor.modifiedOffsets.count == 1 ? "" : "s") modified")
                    .font(.custom(monoFont, size: 10))
                    .foregroundColor(.orange)
            }

            if let sel = editor.selectedOffset {
                Text(String(format: "OFFSET: $%04X (%d)", sel, sel))
                    .font(.custom(monoFont, size: 10))
                    .foregroundColor(Color.c64LightBlue)
            }
        }
    }

    // ── Single hex row ──

    func hexRow(row: Int) -> some View {
        let start = row * bytesPerRow
        let end = min(start + bytesPerRow, editor.editedData.count)
        let offsetStr = String(format: "%04X ", start)

        return HStack(spacing: 0) {
            // Offset
            Text(offsetStr)
                .font(.custom(monoFont, size: hexFontSize))
                .foregroundColor(Color.c64LightBlue)

            // Hex bytes — each is directly tappable
            ForEach(0..<bytesPerRow, id: \.self) { col in
                let byteOffset = start + col
                if byteOffset < end {
                    hexByteCell(offset: byteOffset)
                } else {
                    Text("   ")
                        .font(.custom(monoFont, size: hexFontSize))
                }
            }

            // PETSCII
            Text("  " + petsciiString(start: start, end: end))
                .font(.custom(monoFont, size: hexFontSize))
                .foregroundColor(Color.c64Blue.opacity(0.7))

            Spacer()
        }
        .frame(height: 18)
    }

    // ── Single clickable hex byte ──

    func hexByteCell(offset: Int) -> some View {
        let byte = editor.editedData[offset]
        let isSelected = editor.selectedOffset == offset
        let isModified = editor.modifiedOffsets.contains(offset)

        let displayText: String
        if isSelected && !editor.inputBuffer.isEmpty {
            displayText = editor.inputBuffer.padding(toLength: 2, withPad: "_", startingAt: 0) + " "
        } else {
            displayText = String(format: "%02X ", byte)
        }

        let fgColor: Color = isSelected ? .white : (isModified ? .orange : Color.c64Blue)

        return Text(displayText)
            .font(.custom(monoFont, size: hexFontSize))
            .foregroundColor(fgColor)
            .background(isSelected ? Color.c64Blue : Color.clear)
            .onTapGesture {
                editor.selectOffset(offset)
            }
    }

    // ── PETSCII ──

    func petsciiString(start: Int, end: Int) -> String {
        let bytes = editor.editedData[start..<end]
        let chars = bytes.map { byte -> Character in
            if byte >= 0x20 && byte <= 0x7E {
                return Character(UnicodeScalar(byte))
            }
            if byte >= 0xC1 && byte <= 0xDA {
                return Character(UnicodeScalar(byte - 0xC1 + 0x41))
            }
            return "·"
        }
        return String(chars).padding(toLength: 8, withPad: " ", startingAt: 0)
    }
}

