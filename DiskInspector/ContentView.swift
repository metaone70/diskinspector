import SwiftUI
import UniformTypeIdentifiers
import AppKit
import Combine

extension Color {
    // Authentic C64 blue in light mode; lighter for readability in dark mode.
    static let c64Blue = Color(NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.45, green: 0.50, blue: 0.90, alpha: 1.0)
            : NSColor(red: 0.263, green: 0.216, blue: 0.631, alpha: 1.0)
    }))
    static let c64LightBlue = Color(NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.65, green: 0.68, blue: 0.98, alpha: 1.0)
            : NSColor(red: 0.467, green: 0.427, blue: 0.816, alpha: 1.0)
    }))
}

// MARK: - C64-styled rename text field

/// NSTextField wrapper with white cursor, white text, and visible selection on c64Blue background.
struct C64TextField: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    var autoFocus: Bool = true
    var onSubmit: () -> Void
    var onEscape: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.stringValue = text
        field.font = NSFont(name: "C64 Pro Mono", size: fontSize)
        field.textColor = .white
        field.backgroundColor = NSColor(Color.c64Blue)
        field.isBordered = false
        field.isBezeled = false
        field.focusRingType = .none
        field.drawsBackground = true
        field.isEditable = true
        field.isSelectable = true
        field.delegate = context.coordinator
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.cell?.wraps = false

        if autoFocus {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                field.window?.makeFirstResponder(field)
                field.currentEditor()?.selectAll(nil)
                if let editor = field.currentEditor() as? NSTextView {
                    editor.insertionPointColor = .white
                    editor.selectedTextAttributes = [
                        .backgroundColor: NSColor.white.withAlphaComponent(0.3),
                        .foregroundColor: NSColor.white
                    ]
                }
            }
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: C64TextField
        init(_ parent: C64TextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if sel == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape()
                return true
            }
            return false
        }

        // Re-apply cursor/selection colors when the field editor activates
        func controlTextDidBeginEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField,
                  let editor = field.currentEditor() as? NSTextView else { return }
            editor.insertionPointColor = .white
            editor.selectedTextAttributes = [
                .backgroundColor: NSColor.white.withAlphaComponent(0.3),
                .foregroundColor: NSColor.white
            ]
        }
    }
}

final class SelectionState: ObservableObject {
    @Published var selectedKeys: Set<String> = []
    @Published var lastTappedKey: String?    = nil

    func key(for file: D64File, at index: Int) -> String {
        "\(index):\(file.track):\(file.sector):\(file.filename)"
    }

    func isSelected(_ file: D64File, at index: Int) -> Bool {
        selectedKeys.contains(key(for: file, at: index))
    }

    func select(_ file: D64File, at index: Int) {
        let k = key(for: file, at: index)
        selectedKeys.insert(k)
        lastTappedKey = k
    }

    func deselect(_ file: D64File, at index: Int) {
        selectedKeys.remove(key(for: file, at: index))
    }

    func toggle(_ file: D64File, at index: Int) {
        let k = key(for: file, at: index)
        if selectedKeys.contains(k) { selectedKeys.remove(k) }
        else { selectedKeys.insert(k); lastTappedKey = k }
    }

    func selectOnly(_ file: D64File, at index: Int) {
        let k = key(for: file, at: index)
        selectedKeys = [k]
        lastTappedKey = k
    }

    func clear() {
        selectedKeys.removeAll()
        lastTappedKey = nil
    }

    func indexFromKey(_ key: String) -> Int? {
        guard let colonIdx = key.firstIndex(of: ":") else { return nil }
        return Int(key[key.startIndex..<colonIdx])
    }

    func lastTappedIndex() -> Int? {
        guard let k = lastTappedKey else { return nil }
        return indexFromKey(k)
    }
}

struct ContentView: View {
    @ObservedObject var document: D64Document

    var body: some View {
        if let disk = D64Parser.parse(data: document.data, formatHint: document.diskFormat) {
            DiskWindowView(disk: disk, document: document)
        } else {
            Text("Not a valid disk image or archive.")
                .font(.custom("C64 Pro Mono", size: 14))
                .foregroundColor(Color.c64Blue)
                .padding(20)
        }
    }
}

struct DiskWindowView: View {
    let disk: D64Disk
    @ObservedObject var document: D64Document
    @ObservedObject private var clipboard = D64Clipboard.shared
    @StateObject private var selection = SelectionState()

    @State private var insertionIndex: Int?    = nil
    @State private var droppedAtIndex: Int?    = nil
    @State private var isDropTargeted: Bool    = false
    @State private var renamingID:     UUID?   = nil
    @State private var renameText:     String  = ""
    @State private var renamingDisk:   Bool    = false
    @State private var diskNameText:   String  = ""
    @State private var diskIDText:     String  = ""
    @FocusState private var renameFieldFocused: Bool
    @FocusState private var diskNameFocused:    Bool
    @State private var showingInfo: Bool = false
    let fontSize:        CGFloat = 14
    let lineHeight:      CGFloat = 14
    let padding:         CGFloat = 16
    let maxVisibleLines: Int     = 25
    let colBlocks:       CGFloat = 56
    let colName:         CGFloat = 280
    let colType:         CGFloat = 56

    @StateObject private var monitorHolder = MonitorHolder()

    var totalLines: Int { disk.files.count + 4 + (showingInfo ? 10 : 0) }
        
    var windowWidth: CGFloat { colBlocks + colName + colType + padding * 2 + 96 }
    var initialHeight: CGFloat {
        let lines = min(totalLines, maxVisibleLines)
        return CGFloat(lines) * lineHeight + padding * 2 + 8
    }
    var needsScroll: Bool { totalLines > maxVisibleLines }

    var body: some View {
        Group {
            if needsScroll {
                ScrollView(.vertical, showsIndicators: true) {
                    listContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                listContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: windowWidth)
        // Single unified drop handler for both DI-to-DI drag and Finder drag.
        // Using two separate .dropDestination/.onDrop on the same view causes
        // .dropDestination to consume all events, blocking Finder drops.
        .onDrop(of: [UTType.d64File, UTType.fileURL, UTType.url], isTargeted: $isDropTargeted) { providers, _ in
            guard !disk.format.isArchive else { return false }

            // ── Internal DI drag dropped outside all insertion zones ──
            // Insertion zones handle targeted drops; this catches misses.
            // Same-disk moves with no zone target = no-op (user missed).
            // Cross-disk / separator drops = append to end.
            let staged = D64Clipboard.shared.peekDrag()
            if !staged.isEmpty {
                insertionIndex = nil
                droppedAtIndex = nil
                D64Clipboard.shared.endDrag()
                for dropped in staged where !isSameDisk(dropped) {
                    if canFitFile(dropped) {
                        document.injectFile(dropped, at: nil)
                    } else {
                        showCapacityError(filename: dropped.filename)
                    }
                }
                return true
            }

            // ── Finder drag: load file URLs from providers ──
            insertionIndex = nil
            droppedAtIndex = nil
            var handled = false
            for provider in providers {
                if provider.canLoadObject(ofClass: URL.self) {
                    handled = true
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url = url, url.isFileURL else { return }
                        DispatchQueue.main.async { importFile(from: url) }
                    }
                }
            }
            return handled
        }
        .onChange(of: isDropTargeted) { _, targeted in
            if !targeted { insertionIndex = nil }
        }
        .onAppear {
            resizeWindow()
            setupDeleteKeyMonitor()
            // Register selection state so Separators window can insert after selected file
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let window = NSApplication.shared.keyWindow {
                    DocumentRegistry.shared.registerSelection(window: window, selection: selection)
                }
            }
        }
        .onDisappear {
            removeDeleteKeyMonitor()
        }
    }

    var infoPanel: some View {
        let prg = disk.files.filter { $0.fileType == "PRG" }.count
        let seq = disk.files.filter { $0.fileType == "SEQ" }.count
        let del = disk.files.filter { $0.fileType == "DEL" }.count
        let usr = disk.files.filter { $0.fileType == "USR" }.count

        return VStack(alignment: .leading, spacing: 2) {
            Divider()
                .background(Color.c64LightBlue)
                .padding(.vertical, 4)

            infoRow(label: "NAME  ", value: disk.diskName.uppercased())
            infoRow(label: "ID    ", value: disk.diskID.uppercased())
            infoRow(label: "FORMAT", value: disk.format.displayName)

            if !disk.format.isArchive {
                let usedBlocks = disk.format.totalBlocks - disk.freeBlocks
                let barWidth   = windowWidth - padding * 2 - 20
                let usedWidth  = barWidth * CGFloat(usedBlocks) / CGFloat(disk.format.totalBlocks)

                // Progress bar
                HStack {
                    Text("USED")
                        .font(.custom("C64 Pro Mono", size: 11))
                        .foregroundColor(Color.c64LightBlue)
                    Spacer()
                    Text("\(usedBlocks) / \(disk.format.totalBlocks)")
                        .font(.custom("C64 Pro Mono", size: 11))
                        .foregroundColor(Color.c64LightBlue)
                }
                .frame(height: 16)

                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.c64Blue)
                        .frame(width: max(2, usedWidth), height: 10)
                    Rectangle()
                        .fill(Color.c64LightBlue.opacity(0.3))
                        .frame(width: barWidth - max(2, usedWidth), height: 10)
                }
                .padding(.vertical, 4)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }

            infoRow(label: "PRG  ", value: "\(prg) files")
            if seq > 0 { infoRow(label: "SEQ  ", value: "\(seq) files") }
            if del > 0 { infoRow(label: "DEL  ", value: "\(del) files") }
            if usr > 0 { infoRow(label: "USR  ", value: "\(usr) files") }
            infoRow(label: "TOTAL", value: "\(disk.files.count) files")
        }
    }
    
   
    func infoRow(label: String, value: String) -> some View {
        HStack(spacing: 0) {
            Text(label + ": ")
                .font(.custom("C64 Pro Mono", size: 11))
                .foregroundColor(Color.c64LightBlue)
            Text(value)
                .font(.custom("C64 Pro Mono", size: 11))
                .foregroundColor(Color.c64Blue)
            Spacer()
        }
        .frame(height: 16)
    }
    
       
    // ── Keyboard monitor ──────────────────────────────────
    func setupDeleteKeyMonitor() {
        // Delay slightly so the window is available
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak monitorHolder, weak selection] in
            guard let monitorHolder = monitorHolder, let selection = selection else { return }
            guard let myWindow = NSApplication.shared.keyWindow else { return }
            // Capture THIS view's window — only act when it's the key window
            let capturedWindow = myWindow

            monitorHolder.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard NSApplication.shared.keyWindow === capturedWindow else { return event }
                // Don't intercept while a text field has focus (rename, etc.)
                if let responder = capturedWindow.firstResponder, responder is NSText {
                    return event
                }
                let cmd = event.modifierFlags.contains(.command)
                let shift = event.modifierFlags.contains(.shift)

                // Delete / Forward-Delete
                if (event.keyCode == 51 || event.keyCode == 117) && !selection.selectedKeys.isEmpty {
                    let keys = selection.selectedKeys
                    let doc = document
                    DispatchQueue.main.async {
                        let indices = keys
                            .compactMap { selection.indexFromKey($0) }
                            .sorted()
                            .reversed()
                        for i in indices {
                            doc.deleteFileAtIndex(i)
                        }
                        selection.clear()
                    }
                    return nil
                }
                // Cmd-Z  Undo
                if event.keyCode == 6 && cmd && !shift {
                    DispatchQueue.main.async { document.undo() }
                    return nil
                }
                // Cmd-Shift-Z  Redo
                if event.keyCode == 6 && cmd && shift {
                    DispatchQueue.main.async { document.redo() }
                    return nil
                }
                // Cmd-C  Copy
                if event.keyCode == 8 && cmd {
                    if !selection.selectedKeys.isEmpty {
                        // Re-parse current disk data — don't use stale captured `disk`
                        if let currentDisk = D64Parser.parse(data: document.data, formatHint: document.diskFormat) {
                            let filesToCopy = currentDisk.files.enumerated()
                                .filter { selection.isSelected($0.element, at: $0.offset) }
                                .map { $0.element }
                            if !filesToCopy.isEmpty {
                                D64Clipboard.shared.copy(filesToCopy)
                            }
                        }
                    }
                    return nil
                }
                // Cmd-V  Paste
                if event.keyCode == 9 && cmd {
                    let filesToPaste = D64Clipboard.shared.paste()
                    if !filesToPaste.isEmpty {
                        let doc = document
                        DispatchQueue.main.async {
                            for f in filesToPaste {
                                guard let currentDisk = D64Parser.parse(data: doc.data, formatHint: doc.diskFormat) else { break }
                                if f.blocks <= currentDisk.freeBlocks {
                                    doc.injectFile(f)
                                }
                            }
                        }
                    }
                    return nil
                }
                // Cmd-A  Select All
                if event.keyCode == 0 && cmd {
                    DispatchQueue.main.async {
                        if let currentDisk = D64Parser.parse(data: document.data, formatHint: document.diskFormat) {
                            selection.clear()
                            for (index, file) in currentDisk.files.enumerated() {
                                selection.select(file, at: index)
                            }
                        }
                    }
                    return nil
                }
                // Cmd+Down — move selected file(s) down one slot
                if event.keyCode == 125 && cmd {
                    DispatchQueue.main.async {
                        guard !disk.format.isArchive,
                              let currentDisk = D64Parser.parse(data: document.data, formatHint: document.diskFormat),
                              !currentDisk.files.isEmpty else { return }
                        let indices = currentDisk.files.indices.filter { selection.isSelected(currentDisk.files[$0], at: $0) }.sorted()
                        guard !indices.isEmpty else { return }
                        // Don't move if the last selected file is already at the bottom
                        guard indices.last! < currentDisk.files.count - 1 else { return }
                        // Move from bottom to top to preserve relative order
                        for srcIndex in indices.reversed() {
                            document.moveFile(from: srcIndex, to: srcIndex + 1)
                        }
                        // Update selection to follow the moved files
                        if let refreshed = D64Parser.parse(data: document.data, formatHint: document.diskFormat) {
                            let newIndices = indices.map { $0 + 1 }
                            selection.clear()
                            for i in newIndices {
                                guard i < refreshed.files.count else { continue }
                                selection.select(refreshed.files[i], at: i)
                            }
                            if let last = newIndices.last, last < refreshed.files.count {
                                selection.lastTappedKey = selection.key(for: refreshed.files[last], at: last)
                            }
                        }
                    }
                    return nil
                }
                // Cmd+Up — move selected file(s) up one slot
                if event.keyCode == 126 && cmd {
                    DispatchQueue.main.async {
                        guard !disk.format.isArchive,
                              let currentDisk = D64Parser.parse(data: document.data, formatHint: document.diskFormat),
                              !currentDisk.files.isEmpty else { return }
                        let indices = currentDisk.files.indices.filter { selection.isSelected(currentDisk.files[$0], at: $0) }.sorted()
                        guard !indices.isEmpty else { return }
                        // Don't move if the first selected file is already at the top
                        guard indices.first! > 0 else { return }
                        // Move from top to bottom to preserve relative order
                        for srcIndex in indices {
                            document.moveFile(from: srcIndex, to: srcIndex - 1)
                        }
                        // Update selection to follow the moved files
                        if let refreshed = D64Parser.parse(data: document.data, formatHint: document.diskFormat) {
                            let newIndices = indices.map { $0 - 1 }
                            selection.clear()
                            for i in newIndices {
                                guard i >= 0 && i < refreshed.files.count else { continue }
                                selection.select(refreshed.files[i], at: i)
                            }
                            if let first = newIndices.first, first >= 0 && first < refreshed.files.count {
                                selection.lastTappedKey = selection.key(for: refreshed.files[first], at: first)
                            }
                        }
                    }
                    return nil
                }
                // Arrow Down — select next file
                if event.keyCode == 125 && !cmd {
                    DispatchQueue.main.async {
                        guard let currentDisk = D64Parser.parse(data: document.data, formatHint: document.diskFormat),
                              !currentDisk.files.isEmpty else { return }
                        let lastIdx = selection.lastTappedIndex() ?? -1
                        let nextIdx = min(lastIdx + 1, currentDisk.files.count - 1)
                        let file = currentDisk.files[nextIdx]
                        if shift {
                            selection.select(file, at: nextIdx)
                            selection.lastTappedKey = selection.key(for: file, at: nextIdx)
                        } else {
                            selection.selectOnly(file, at: nextIdx)
                        }
                    }
                    return nil
                }
                // Arrow Up — select previous file
                if event.keyCode == 126 && !cmd {
                    DispatchQueue.main.async {
                        guard let currentDisk = D64Parser.parse(data: document.data, formatHint: document.diskFormat),
                              !currentDisk.files.isEmpty else { return }
                        let lastIdx = selection.lastTappedIndex() ?? currentDisk.files.count
                        let prevIdx = max(lastIdx - 1, 0)
                        let file = currentDisk.files[prevIdx]
                        if shift {
                            selection.select(file, at: prevIdx)
                            selection.lastTappedKey = selection.key(for: file, at: prevIdx)
                        } else {
                            selection.selectOnly(file, at: prevIdx)
                        }
                    }
                    return nil
                }
                // Cmd-R  Run selected file in C64 VICE
                // Cmd-Shift-R  Run selected file in C128 VICE
                if event.keyCode == 15 && cmd {
                    if let lastIdx = selection.lastTappedIndex(),
                       let currentDisk = D64Parser.parse(data: document.data, formatHint: document.diskFormat),
                       lastIdx < currentDisk.files.count {
                        let file = currentDisk.files[lastIdx]
                        let emulator: VICELauncher.Emulator = shift ? .c128 : .c64
                        DispatchQueue.main.async {
                            VICELauncher.launchFile(document: document, file: file, emulator: emulator)
                        }
                    }
                    return nil
                }
                return event
            }
        }
    }

    func removeDeleteKeyMonitor() {
        if let monitor = monitorHolder.monitor {
            NSEvent.removeMonitor(monitor)
            monitorHolder.monitor = nil
        }
    }

    func canFitFile(_ file: D64File) -> Bool {
        guard !disk.format.isArchive else { return false }
        guard let currentDisk = D64Parser.parse(data: document.data, formatHint: document.diskFormat) else { return false }
        return file.blocks <= currentDisk.freeBlocks
    }

    func showCapacityError(filename: String) {
        let alert = NSAlert()
        alert.messageText = "Not Enough Space"
        alert.informativeText = "Cannot copy \"\(filename.uppercased())\" — not enough free blocks on this disk."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // ── List content ───────────────────────────────────────

    var listContent: some View {
        VStack(alignment: .leading, spacing: 0) {

            HStack(spacing: 0) {
                Text(" 0   ")
                    .font(.custom("C64 Pro Mono", size: fontSize))
                    .foregroundColor(.white)

                if renamingDisk {
                    Text("\"")
                        .font(.custom("C64 Pro Mono", size: fontSize))
                        .foregroundColor(.white)

                    C64TextField(
                        text: $diskNameText,
                        fontSize: fontSize,
                        onSubmit: { commitDiskRename() },
                        onEscape: { renamingDisk = false }
                    )
                    .frame(width: 160, height: lineHeight)

                    Text("\" ")
                        .font(.custom("C64 Pro Mono", size: fontSize))
                        .foregroundColor(.white)

                    C64TextField(
                        text: $diskIDText,
                        fontSize: fontSize,
                        autoFocus: false,
                        onSubmit: { commitDiskRename() },
                        onEscape: { renamingDisk = false }
                    )
                    .frame(width: 40, height: lineHeight)

                    Text(" \(disk.format.dosVersion)")
                        .font(.custom("C64 Pro Mono", size: fontSize))
                        .foregroundColor(.white)

                } else {
                    Text("\"\(disk.diskName.uppercased())\" \(disk.diskID.uppercased()) \(disk.format.dosVersion)")
                        .font(.custom("C64 Pro Mono", size: fontSize))
                        .foregroundColor(.white)
                        .onTapGesture(count: 2) {
                            guard !disk.format.isArchive else { return }
                            diskNameText = disk.diskName
                            diskIDText   = disk.diskID
                            renamingDisk = true
                        }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: lineHeight)
            .background(Color.c64Blue)
            .lineLimit(1)

            ForEach(Array(zip(disk.files.indices, disk.files)), id: \.1.id) { index, file in
                let isLocked = file.fileTypeByte & 0x40 != 0
                let isSplat  = file.fileTypeByte & 0x80 == 0
                dirLine(
                    blocks: "\(file.blocks)",
                    name: "\(isSplat ? "*" : " ")\"\(file.filename.uppercased())\"",
                    suffix: file.fileType + (isLocked ? "<" : ""),
                    nameColor: Color.c64Blue,
                    suffixColor: Color.c64LightBlue,
                    file: file,
                    index: index
                )
                // Row is stable (UUID id) — onDrop here never gets rebuilt during drag.
                // This prevents the feedback loop that caused unresponsiveness with
                // positional insertion zone views.
                .onDrop(
                    of: [UTType.d64File],
                    isTargeted: Binding<Bool>(
                        get: { insertionIndex == index },
                        set: { val in
                            if val { insertionIndex = index; droppedAtIndex = index }
                            else if insertionIndex == index { insertionIndex = nil; droppedAtIndex = nil }
                        }
                    )
                ) { _, _ in
                    guard !disk.format.isArchive else { return false }
                    let staged = D64Clipboard.shared.peekDrag()
                    guard !staged.isEmpty else { return false }
                    let targetIndex = index
                    insertionIndex = nil
                    droppedAtIndex = nil
                    D64Clipboard.shared.endDrag()
                    for dropped in staged {
                        if isSameDisk(dropped) {
                            guard let srcIndex = disk.files.firstIndex(where: {
                                $0.track == dropped.track &&
                                $0.sector == dropped.sector &&
                                $0.filename == dropped.filename
                            }) else { continue }
                            if srcIndex == targetIndex || srcIndex + 1 == targetIndex { continue }
                            let adjustedDest = targetIndex > srcIndex ? targetIndex - 1 : targetIndex
                            document.moveFile(from: srcIndex, to: adjustedDest)
                        } else {
                            if !canFitFile(dropped) { showCapacityError(filename: dropped.filename); continue }
                            let actualTarget: Int? = targetIndex < disk.files.count
                                ? D64Parser.directoryIndex(in: [UInt8](document.data), forFile: disk.files[targetIndex])
                                : nil
                            document.injectFile(dropped, at: actualTarget)
                        }
                    }
                    return true
                }
                // Insertion indicator as an overlay — zero layout impact, no VStack shift.
                // Offset upward so it appears in the gap between this row and the one above.
                .overlay(alignment: .top) {
                    if insertionIndex == index {
                        insertionLine()
                            .offset(y: -6)
                            .allowsHitTesting(false)
                    }
                }
            }

            Spacer(minLength: 0)

            // Blocks free (own row) + buttons row below
            VStack(alignment: .leading, spacing: 4) {
                if disk.format != .t64 && disk.format != .lnx {
                    Text("\(disk.freeBlocks) BLOCKS FREE.")
                        .font(.custom("C64 Pro Mono", size: fontSize))
                        .foregroundColor(Color.c64Blue)
                        .frame(height: lineHeight)
                }

                HStack(spacing: 0) {
                    if disk.format != .t64 && disk.format != .lnx {
                        Button(action: {
                            let issues = DiskValidator.validate(data: document.analysableData)
                            ValidationWindow.open(issues: issues, diskName: disk.diskName)
                        }) {
                            Text("✓ VALIDATE")
                                .font(.custom("C64 Pro Mono", size: 11))
                                .foregroundColor(Color.c64LightBlue)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 12)

                        Button(action: {
                            BAMViewWindow.open(document: document)
                        }) {
                            Text("▦ BAM")
                                .font(.custom("C64 Pro Mono", size: 11))
                                .foregroundColor(Color.c64LightBlue)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 12)
                    }

                    if !disk.format.isArchive {
                        Button(action: {
                            RecoveryWindow.open(document: document, diskName: disk.diskName)
                        }) {
                            Text("♻ RECOVER")
                                .font(.custom("C64 Pro Mono", size: 11))
                                .foregroundColor(Color.c64LightBlue)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 12)
                    }

                    if disk.format == .g64 || disk.format == .nib {
                        Button(action: {
                            TrackMapWindow.open(disk: disk)
                        }) {
                            Text("▤ TRACKS")
                                .font(.custom("C64 Pro Mono", size: 11))
                                .foregroundColor(Color.c64LightBlue)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 12)
                    }

                    if !disk.format.isArchive && !disk.files.isEmpty {
                        Menu {
                            Button("Name (A→Z)")    { document.sortFiles(by: .name,     ascending: true)  }
                            Button("Name (Z→A)")    { document.sortFiles(by: .name,     ascending: false) }
                            Divider()
                            Button("Type")          { document.sortFiles(by: .fileType, ascending: true)  }
                            Divider()
                            Button("Blocks (↑)")    { document.sortFiles(by: .blocks,   ascending: true)  }
                            Button("Blocks (↓)")    { document.sortFiles(by: .blocks,   ascending: false) }
                        } label: {
                            Text("↕ SORT")
                                .font(.custom("C64 Pro Mono", size: 11))
                                .foregroundColor(Color.c64LightBlue)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .padding(.trailing, 12)
                    }

                    Button(action: { showingInfo.toggle() }) {
                        Text(showingInfo ? "▲ INFO" : "▼ INFO")
                            .font(.custom("C64 Pro Mono", size: 11))
                            .foregroundColor(Color.c64LightBlue)
                    }
                    .buttonStyle(.plain)
                }
            }

            if showingInfo {
                infoPanel
            }

        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
        .onChange(of: document.data) {
            insertionIndex = nil
            droppedAtIndex = nil
            D64Clipboard.shared.endDrag()
            resizeWindowToFitContent()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .contextMenu {
            if !disk.format.isArchive {
                Button("Paste") {
                    for f in D64Clipboard.shared.paste() {
                        if !canFitFile(f) {
                            showCapacityError(filename: f.filename)
                            continue
                        }
                        document.injectFile(f)
                    }
                }
                .disabled(clipboard.isEmpty)
                Divider()
                Button("Import from Mac…") {
                    importFromMac()
                }
                Divider()
            }
            Button("Export Directory as Text…") {
                DiskExporter.saveAsText(data: document.data, diskName: disk.diskName)
            }
            Button("Export Directory as HTML…") {
                DiskExporter.saveAsHTML(data: document.data, diskName: disk.diskName)
            }
            Button("Export Directory as PNG…") {
                DiskExporter.saveAsPNG(data: document.data, diskName: disk.diskName)
            }
        }
    }

    // ── Insertion line ─────────────────────────────────────

    func insertionLine() -> some View {
        HStack(spacing: 0) {
            Triangle()
                .fill(Color.c64LightBlue)
                .frame(width: 6, height: 8)
            Rectangle()
                .fill(Color.c64LightBlue)
                .frame(height: 2)
            Triangle()
                .fill(Color.c64LightBlue)
                .rotationEffect(.degrees(180))
                .frame(width: 6, height: 8)
        }
        .frame(height: 8)
        .padding(.vertical, 1)
    }

    func spacerLine() -> some View {
        Text(" ")
            .font(.custom("C64 Pro Mono", size: fontSize))
            .frame(height: 4)
    }

    // ── Directory row ──────────────────────────────────────

    func dirLine(
        blocks: String,
        name: String,
        suffix: String,
        nameColor: Color,
        suffixColor: Color,
        file: D64File?,
        index: Int
    ) -> some View {
        let paddedBlocks = blocks.padding(toLength: 4, withPad: " ", startingAt: 0)
        let isSelected   = file.map { selection.isSelected($0, at: index) } ?? false
        let isRenaming   = file.map { renamingID == $0.id } ?? false

        let row = HStack(spacing: 0) {
            Text(paddedBlocks)
                .font(.custom("C64 Pro Mono", size: fontSize))
                .foregroundColor(isSelected ? Color.white : Color.c64Blue)
                .frame(width: colBlocks, height: lineHeight, alignment: .leading)

            if isRenaming {
                HStack(spacing: 0) {
                    Text("\"")
                        .font(.custom("C64 Pro Mono", size: fontSize))
                        .foregroundColor(.white)
                    C64TextField(
                        text: $renameText,
                        fontSize: fontSize,
                        onSubmit: { commitRename() },
                        onEscape: { renamingID = nil }
                    )
                    Text("\"")
                        .font(.custom("C64 Pro Mono", size: fontSize))
                        .foregroundColor(.white)
                    Spacer(minLength: 0)
                }
                .background(Color.c64Blue)
                .frame(maxWidth: .infinity)
                .frame(height: lineHeight)
            } else {
                Text(name)
                    .font(.custom("C64 Pro Mono", size: fontSize))
                    .foregroundColor(isSelected ? .white : nameColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: lineHeight)
                    .clipped()
            }

            Text(suffix)
                .font(.custom("C64 Pro Mono", size: fontSize))
                .foregroundColor(isSelected ? .white : suffixColor)
                .frame(width: colType, height: lineHeight, alignment: .leading)
        }
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
        .background(isSelected ? Color.c64Blue : Color.clear)
        .onTapGesture(count: 2) {
            // Double-click → try BASIC → try SEQ → fall back to hex
            guard let file = file else { return }
            if renamingID != nil { return }
            if !BasicViewerWindow.tryOpen(file: file) {
                if !SEQViewerWindow.tryOpen(file: file) {
                    HexViewerWindow.open(file: file, document: document)
                }
            }
        }
        .onTapGesture {
            guard let file = file else { return }
            if renamingID != nil { renamingID = nil; return }
            if NSEvent.modifierFlags.contains(.command) {
                selection.toggle(file, at: index)
            } else if NSEvent.modifierFlags.contains(.shift) {
                if let lastIndex = selection.lastTappedIndex() {
                    let range = min(lastIndex, index)...max(lastIndex, index)
                    for i in range {
                        if i < disk.files.count {
                            selection.select(disk.files[i], at: i)
                        }
                    }
                } else {
                    selection.select(file, at: index)
                }
            } else {
                selection.selectOnly(file, at: index)
            }
        }
        .contextMenu {
            if let file = file {
                Button("View BASIC") {
                    if !BasicViewerWindow.tryOpen(file: file) {
                        let alert = NSAlert()
                        alert.messageText = "Not a BASIC Program"
                        alert.informativeText = "\"\(file.filename.uppercased())\" does not appear to be a BASIC program."
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }

                Button("View Hex") {
                    HexViewerWindow.open(file: file, document: document)
                }

                if SEQViewerWindow.canOpen(file: file) {
                    Button("View SEQ") {
                        SEQViewerWindow.open(file: file)
                    }
                }

                if DisassemblerWindow.canOpen(file: file) {
                    Button("View Disassembly") {
                        DisassemblerWindow.open(file: file)
                    }
                }

                if file.track != 0 {
                    Button("View Sector Chain…") {
                        SectorChainWindow.open(file: file, data: document.data, format: document.diskFormat)
                    }
                }

                Divider()

                Menu("Run File in VICE") {
                    Button("Run in C64 (x64sc)") {
                        VICELauncher.launchFile(document: document, file: file, emulator: .c64)
                    }
                    Button("Run in C128 (x128)") {
                        VICELauncher.launchFile(document: document, file: file, emulator: .c128)
                    }
                }

                Menu("Open Disk in VICE") {
                    Button("Open in C64 (x64sc)") {
                        VICELauncher.launch(document: document, emulator: .c64)
                    }
                    Button("Open in C128 (x128)") {
                        VICELauncher.launch(document: document, emulator: .c128)
                    }
                }

                Divider()

                if !disk.format.isArchive {
                    Button("Rename") {
                        selection.selectOnly(file, at: index)
                        renameText = file.filename
                        renamingID = file.id
                    }

                    Divider()

                    // ── File type, lock, splat, block count ──
                    let typeByte = file.fileTypeByte
                    let isLocked = typeByte & 0x40 != 0
                    let isSplat  = typeByte & 0x80 == 0

                    Menu("Change Type") {
                        let types: [(String, UInt8)] = [("PRG", 2), ("SEQ", 1), ("USR", 3), ("REL", 4)]
                        ForEach(types, id: \.0) { label, code in
                            Button(action: {
                                let newByte = (typeByte & 0xF8) | code
                                document.setFileTypeByte(at: index, newTypeByte: newByte)
                            }) {
                                if (typeByte & 0x07) == code {
                                    Label(label, systemImage: "checkmark")
                                } else {
                                    Text(label)
                                }
                            }
                        }
                    }

                    Button(isLocked ? "Unlock" : "Lock") {
                        document.setFileTypeByte(at: index, newTypeByte: typeByte ^ 0x40)
                    }

                    Button(isSplat ? "Clear Splat (*)" : "Mark as Splat (*)") {
                        document.setFileTypeByte(at: index, newTypeByte: typeByte ^ 0x80)
                    }

                    if file.track != 0 {
                        Button("Fix Block Count") {
                            document.fixBlockCount(at: index)
                        }
                    }

                    Divider()
                }

                Button("Copy") {
                    let filesToCopy = selection.selectedKeys.isEmpty ? [file] :
                        disk.files.enumerated()
                            .filter { selection.isSelected($0.element, at: $0.offset) }
                            .map { $0.element }
                    D64Clipboard.shared.copy(filesToCopy)
                }

                if !disk.format.isArchive {
                    Button("Paste") {
                        for f in D64Clipboard.shared.paste() {
                            if !canFitFile(f) {
                                showCapacityError(filename: f.filename)
                                continue
                            }
                            document.injectFile(f)
                        }
                    }
                    .disabled(clipboard.isEmpty)
                }

                Divider()

                Button("Export to Mac…") {
                    exportToMac(file: file)
                }

                if selection.selectedKeys.count > 1 {
                    Button("Export Selected to Mac…") {
                        exportSelectedToMac()
                    }
                }

                Button("Export All to Mac…") {
                    exportAllToMac()
                }
                .disabled(disk.files.isEmpty)

                if !disk.format.isArchive {
                    Divider()

                    Button(selection.selectedKeys.count > 1 ? "Delete \(selection.selectedKeys.count) Files" : "Delete \"\(file.filename.uppercased())\"", role: .destructive) {
                        let indices = selection.selectedKeys.isEmpty
                            ? [index]
                            : selection.selectedKeys
                                .compactMap { selection.indexFromKey($0) }
                                .sorted()
                                .reversed()
                        for i in indices {
                            document.deleteFileAtIndex(i)
                        }
                        selection.clear()
                    }
                }

            } else {
                Button("Export All to Mac…") {
                    exportAllToMac()
                }
                .disabled(disk.files.isEmpty)

                if !disk.format.isArchive {
                    Divider()

                    Button("Paste") {
                        for f in D64Clipboard.shared.paste() {
                            if !canFitFile(f) {
                                showCapacityError(filename: f.filename)
                                continue
                            }
                            document.injectFile(f)
                        }
                    }
                    .disabled(clipboard.isEmpty)

                    Divider()

                    Button("Import from Mac…") {
                        importFromMac()
                    }
                }
            }
        }

        if let file = file {
            var stampedFile = file
            stampedFile.sourceDocumentID = document.documentID
            return AnyView(
                row.onDrag {
                    // Stage all selected files for the drop handler.
                    // .onDrag runs reliably at drag start, unlike .draggable's preview.
                    let filesToDrag: [D64File]
                    if selection.isSelected(file, at: index) && selection.selectedKeys.count > 1 {
                        filesToDrag = disk.files.enumerated()
                            .filter { selection.isSelected($0.element, at: $0.offset) }
                            .map {
                                var f = $0.element
                                f.sourceDocumentID = document.documentID
                                return f
                            }
                    } else {
                        filesToDrag = [stampedFile]
                    }
                    D64Clipboard.shared.stageDrag(filesToDrag)
                    let provider = NSItemProvider()

                    // Set filename so Finder names the file correctly on drop
                    let ext = stampedFile.fileType.lowercased()
                    var safeName = stampedFile.filename
                        .replacingOccurrences(of: "/", with: "_")
                        .replacingOccurrences(of: ":", with: "_")
                    if safeName.isEmpty { safeName = "unnamed" }
                    provider.suggestedName = "\(safeName).\(ext)"

                    // Raw file data — lets Finder save the actual content
                    provider.registerDataRepresentation(
                        forTypeIdentifier: UTType.data.identifier,
                        visibility: .all
                    ) { completion in
                        completion(stampedFile.rawData, nil)
                        return nil
                    }

                    // D64File JSON — used for DI-to-DI drag between windows
                    if let encoded = try? JSONEncoder().encode(stampedFile) {
                        provider.registerDataRepresentation(
                            forTypeIdentifier: UTType.d64File.identifier,
                            visibility: .all
                        ) { completion in
                            completion(encoded, nil)
                            return nil
                        }
                    }
                    return provider
                }
            )
        } else {
            return AnyView(row)
        }
    }

    // ── Actions ────────────────────────────────────────────

    func commitRename() {
        guard let id = renamingID,
              let fileIndex = disk.files.firstIndex(where: { $0.id == id }),
              !renameText.isEmpty else {
            renamingID = nil
            return
        }
        document.renameFileAtIndex(fileIndex, to: renameText)
        renamingID = nil
    }

    func commitDiskRename() {
        guard !diskNameText.isEmpty else {
            renamingDisk = false
            return
        }
        document.renameDisk(name: diskNameText, id: diskIDText)
        renamingDisk = false
    }

    func isSameDisk(_ file: D64File) -> Bool {
        file.sourceDocumentID == document.documentID
    }

    func exportToMac(file: D64File) {
        let panel = NSSavePanel()
        let ext = file.fileType.lowercased()
        panel.nameFieldStringValue = "\(file.filename).\(ext)"
        panel.allowedContentTypes  = [UTType(filenameExtension: ext) ?? .data]
        panel.message = "Export \(file.filename.uppercased()) to Mac"
        if panel.runModal() == .OK, let url = panel.url {
            try? document.exportFile(file, to: url)
        }
    }

    func exportAllToMac() {
        let exportable = disk.files.filter { !$0.rawData.isEmpty }
        guard !exportable.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Export \(exportable.count) file(s) from \(disk.diskName.uppercased()) to a folder"
        panel.prompt = "Export Here"
        guard panel.runModal() == .OK, let folderURL = panel.url else { return }

        var exported = 0
        var failed = 0
        for file in exportable {
            var safeName = file.filename
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: ":", with: "_")
                .replacingOccurrences(of: "\0", with: "")
            if safeName.isEmpty { safeName = "unnamed" }
            let ext = file.fileType.lowercased()
            var destURL = folderURL.appendingPathComponent("\(safeName).\(ext)")
            var counter = 1
            while FileManager.default.fileExists(atPath: destURL.path) {
                destURL = folderURL.appendingPathComponent("\(safeName)_\(counter).\(ext)")
                counter += 1
            }
            do {
                try document.exportFile(file, to: destURL)
                exported += 1
            } catch {
                failed += 1
            }
        }

        let alert = NSAlert()
        alert.messageText = "Export Complete"
        alert.informativeText = failed == 0
            ? "\(exported) file(s) exported successfully."
            : "\(exported) file(s) exported, \(failed) failed."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func exportSelectedToMac() {
        let selectedFiles = disk.files.enumerated()
            .filter { selection.isSelected($0.element, at: $0.offset) && !$0.element.rawData.isEmpty }
            .map { $0.element }
        guard !selectedFiles.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Export \(selectedFiles.count) selected file(s) from \(disk.diskName.uppercased()) to a folder"
        panel.prompt = "Export Here"
        guard panel.runModal() == .OK, let folderURL = panel.url else { return }

        var exported = 0
        var failed = 0
        for file in selectedFiles {
            var safeName = file.filename
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: ":", with: "_")
                .replacingOccurrences(of: "\0", with: "")
            if safeName.isEmpty { safeName = "unnamed" }
            let ext = file.fileType.lowercased()
            var destURL = folderURL.appendingPathComponent("\(safeName).\(ext)")
            var counter = 1
            while FileManager.default.fileExists(atPath: destURL.path) {
                destURL = folderURL.appendingPathComponent("\(safeName)_\(counter).\(ext)")
                counter += 1
            }
            do {
                try document.exportFile(file, to: destURL)
                exported += 1
            } catch {
                failed += 1
            }
        }

        let alert = NSAlert()
        alert.messageText = "Export Complete"
        alert.informativeText = failed == 0
            ? "\(exported) file(s) exported successfully."
            : "\(exported) file(s) exported, \(failed) failed."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func importFromMac() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories    = false
        panel.message = "Choose files to import into this disk"
        if panel.runModal() == .OK {
            for url in panel.urls {
                importFile(from: url)
            }
        }
    }

    func importFile(from url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let name = url.deletingPathExtension().lastPathComponent
            .uppercased()
            .prefix(16)
            .replacingOccurrences(of: " ", with: ".")
        let ext  = url.pathExtension.uppercased()
        let type = ["PRG", "SEQ", "USR", "REL"].contains(ext) ? ext : "PRG"
        let file = D64File(
            filename: String(name),
            fileType: type,
            blocks: (data.count + 253) / 254,
            track: 0,
            sector: 0,
            rawData: data
        )
        if !canFitFile(file) {
            showCapacityError(filename: String(name))
            return
        }
        document.injectFile(file)
    }

    func resizeWindow() {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.keyWindow else { return }
            let contentLines = max(14, min(disk.files.count + 4, maxVisibleLines))
            let contentHeight = CGFloat(contentLines) * lineHeight + padding * 2 + 16
            let frame = NSRect(
                x: window.frame.minX,
                y: window.frame.maxY - contentHeight,
                width: windowWidth,
                height: contentHeight
            )
            window.setFrame(frame, display: true, animate: false)
            window.minSize = NSSize(width: windowWidth, height: lineHeight * 8)
            // Don't cap maxSize tightly — let the user enlarge freely
            window.maxSize = NSSize(width: windowWidth, height: 10000)
        }
    }

    /// After files are added/removed: grow the window if content needs more space,
    /// but never shrink it (the user may have enlarged it intentionally).
    func resizeWindowToFitContent() {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.keyWindow else { return }
            let contentLines = min(disk.files.count + 4, maxVisibleLines)
            let neededHeight = CGFloat(contentLines) * lineHeight + padding * 2 + 16
            if neededHeight > window.frame.height {
                // Grow downward (keep top edge fixed)
                let frame = NSRect(
                    x: window.frame.minX,
                    y: window.frame.maxY - neededHeight,
                    width: windowWidth,
                    height: neededHeight
                )
                window.setFrame(frame, display: true, animate: true)
            }
            window.maxSize = NSSize(width: windowWidth, height: 10000)
        }
    }

}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

final class MonitorHolder: ObservableObject {
    var monitor: Any? = nil
    deinit {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

#Preview {
    ContentView(document: D64Document())
}
