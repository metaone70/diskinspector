import SwiftUI
import UniformTypeIdentifiers
import AppKit
import Combine

extension Color {
    static let c64Blue      = Color(red: 0.263, green: 0.216, blue: 0.631)
    static let c64LightBlue = Color(red: 0.467, green: 0.427, blue: 0.816)
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
        if let disk = D64Parser.parse(data: document.data) {
            DiskWindowView(disk: disk, document: document)
        } else {
            Text("Not a valid D64/D71/D81 file.")
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
    let colBlocks:       CGFloat = 42
    let colName:         CGFloat = 280
    let colType:         CGFloat = 130

    @StateObject private var monitorHolder = MonitorHolder()

    var totalLines: Int { disk.files.count + 4 + (showingInfo ? 10 : 0) }
    var infoPanelHeight: CGFloat {
        if !showingInfo { return 0 }
        // Fixed elements: divider(12) + NAME(16) + ID(16) + FORMAT(16)
        //                + USED label(16) + progress bar(34) + PRG(16) + TOTAL(16) = 142
        // VStack spacing(2) between 8 items = 14
        // Conditional type rows: SEQ, DEL, USR — each 18 (16 height + 2 spacing)
        let conditionalRows = (disk.files.contains { $0.fileType == "SEQ" } ? 1 : 0)
                            + (disk.files.contains { $0.fileType == "DEL" } ? 1 : 0)
                            + (disk.files.contains { $0.fileType == "USR" } ? 1 : 0)
        return 156 + CGFloat(conditionalRows) * 18 + 20  // +20 safety buffer
    }
        
    var windowWidth:   CGFloat { colBlocks + colName + colType + padding * 2 + 32 }
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
        .dropDestination(for: D64File.self) { droppedFiles, _ in
            let targetIndex = droppedAtIndex
            insertionIndex = nil
            droppedAtIndex = nil
            // Use staged drag files for multi-selection; fall back to single dropped file
            let staged = D64Clipboard.shared.peekDrag()
            let allFiles = staged.isEmpty ? droppedFiles : staged
            D64Clipboard.shared.endDrag()
            for dropped in allFiles {
                if isSameDisk(dropped) {
                    guard let srcIndex = disk.files.firstIndex(where: {
                        $0.track == dropped.track &&
                        $0.sector == dropped.sector &&
                        $0.filename == dropped.filename
                    }) else { continue }
                    guard let t = targetIndex, srcIndex != t else { continue }
                    let adjusted = t > srcIndex ? t - 1 : t
                    document.moveFile(from: srcIndex, to: adjusted)
                } else {
                    if !canFitFile(dropped) {
                        showCapacityError(filename: dropped.filename)
                        continue
                    }
                    let actualTarget: Int?
                    if let t = targetIndex, t < disk.files.count {
                        actualTarget = D64Parser.directoryIndex(
                            in: [UInt8](document.data),
                            forFile: disk.files[t]
                        )
                    } else {
                        actualTarget = nil
                    }
                    document.injectFile(dropped, at: actualTarget)
                }
            }
            return true
        } isTargeted: { isTargeted in
            if !isTargeted { insertionIndex = nil }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil)
                    else { return }
                    DispatchQueue.main.async { importFile(from: url) }
                }
            }
            return true
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
        let usedBlocks = disk.format.totalBlocks - disk.freeBlocks
        let barWidth = windowWidth - padding * 2 - 20
        let usedWidth = barWidth * CGFloat(usedBlocks) / CGFloat(disk.format.totalBlocks)
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
                        if let currentDisk = D64Parser.parse(data: document.data) {
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
                                guard let currentDisk = D64Parser.parse(data: doc.data) else { break }
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
                        if let currentDisk = D64Parser.parse(data: document.data) {
                            selection.clear()
                            for (index, file) in currentDisk.files.enumerated() {
                                selection.select(file, at: index)
                            }
                        }
                    }
                    return nil
                }
                // Arrow Down — select next file
                if event.keyCode == 125 && !cmd {
                    DispatchQueue.main.async {
                        guard let currentDisk = D64Parser.parse(data: document.data),
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
                        guard let currentDisk = D64Parser.parse(data: document.data),
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
                       let currentDisk = D64Parser.parse(data: document.data),
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
        guard let currentDisk = D64Parser.parse(data: document.data) else { return false }
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
                if insertionIndex == index {
                    insertionLine()
                }

                dirLine(
                    blocks: "\(file.blocks)",
                    name: "\"\(file.filename.uppercased())\"",
                    suffix: file.fileType,
                    nameColor: Color.c64Blue,
                    suffixColor: Color.c64LightBlue,
                    file: file,
                    index: index
                )
                .dropDestination(for: D64File.self) { droppedFiles, _ in
                    let targetIndex = droppedAtIndex
                    insertionIndex = nil
                    droppedAtIndex = nil
                    let staged = D64Clipboard.shared.peekDrag()
                    let allFiles = staged.isEmpty ? droppedFiles : staged
                    D64Clipboard.shared.endDrag()
                    for dropped in allFiles {
                        if isSameDisk(dropped) {
                            guard let srcIndex = disk.files.firstIndex(where: {
                                $0.track == dropped.track &&
                                $0.sector == dropped.sector &&
                                $0.filename == dropped.filename
                            }) else { continue }
                            guard let t = targetIndex, srcIndex != t else { continue }
                            let adjusted = t > srcIndex ? t - 1 : t
                            document.moveFile(from: srcIndex, to: adjusted)
                        } else {
                            if !canFitFile(dropped) {
                                showCapacityError(filename: dropped.filename)
                                continue
                            }
                            let actualTarget: Int?
                            if let t = targetIndex, t < disk.files.count {
                                actualTarget = D64Parser.directoryIndex(
                                    in: [UInt8](document.data),
                                    forFile: disk.files[t]
                                )
                            } else {
                                actualTarget = nil
                            }
                            document.injectFile(dropped, at: actualTarget)
                        }
                    }
                    return true
                } isTargeted: { isTargeted in
                    if isTargeted {
                        insertionIndex = index
                        droppedAtIndex = index
                    } else if insertionIndex == index {
                        // Clear only if we were the one who set it
                        insertionIndex = nil
                    }
                }
            }

            if insertionIndex == disk.files.count {
                insertionLine()
            }

            Spacer(minLength: 0)

            // Blocks free + info toggle + validate
            HStack(spacing: 0) {
                Text("\(disk.freeBlocks) BLOCKS FREE.")
                    .font(.custom("C64 Pro Mono", size: fontSize))
                    .foregroundColor(Color.c64Blue)
                    .frame(height: lineHeight)
                Spacer()
                Button(action: {
                    let issues = DiskValidator.validate(data: document.data)
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

                Button(action: { showingInfo.toggle() }) {
                    Text(showingInfo ? "▲ INFO" : "▼ INFO")
                        .font(.custom("C64 Pro Mono", size: 11))
                        .foregroundColor(Color.c64LightBlue)
                }
                .buttonStyle(.plain)
            }

            if showingInfo {
                infoPanel
            }
            
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
        .onChange(of: showingInfo) {
            resizeWindowForInfoToggle()
        }
        .onChange(of: document.data) {
            insertionIndex = nil
            droppedAtIndex = nil
            D64Clipboard.shared.endDrag()
            resizeWindowToFitContent()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .contextMenu {
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
            Button("Export Directory as Text…") {
                DiskExporter.saveAsText(data: document.data, diskName: disk.diskName)
            }
            Button("Export Directory as HTML…") {
                DiskExporter.saveAsHTML(data: document.data, diskName: disk.diskName)
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
                .frame(width: colName, height: lineHeight)
            } else {
                Text(name)
                    .font(.custom("C64 Pro Mono", size: fontSize))
                    .foregroundColor(isSelected ? .white : nameColor)
                    .frame(width: colName, height: lineHeight, alignment: .leading)
                    .clipped()
            }

            Text(suffix)
                .font(.custom("C64 Pro Mono", size: fontSize))
                .foregroundColor(isSelected ? .white : suffixColor)
                .frame(width: colType, height: lineHeight, alignment: .leading)

            Spacer()
        }
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
        .background(isSelected ? Color.c64Blue : Color.clear)
        .onTapGesture(count: 2) {
            // Double-click → try BASIC listing first, fall back to hex
            guard let file = file else { return }
            if renamingID != nil { return }
            if !BasicViewerWindow.tryOpen(file: file) {
                HexViewerWindow.open(file: file, document: document)
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

                Button("Rename") {
                    selection.selectOnly(file, at: index)
                    renameText = file.filename
                    renamingID = file.id
                }

                Divider()

                Button("Copy") {
                    let filesToCopy = selection.selectedKeys.isEmpty ? [file] :
                        disk.files.enumerated()
                            .filter { selection.isSelected($0.element, at: $0.offset) }
                            .map { $0.element }
                    D64Clipboard.shared.copy(filesToCopy)
                }

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

                Button("Export to Mac…") {
                    exportToMac(file: file)
                }

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

            } else {
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
                    // Return an NSItemProvider with the single file for SwiftUI's
                    // dropDestination(for: D64File.self) to decode
                    let provider = NSItemProvider()
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
            let contentLines = max(8, min(disk.files.count + 4, maxVisibleLines))
            let contentHeight = CGFloat(contentLines) * lineHeight + padding * 2 + infoPanelHeight + 16
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
            let neededHeight = CGFloat(contentLines) * lineHeight + padding * 2 + infoPanelHeight + 16
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

    /// When info panel is toggled: grow downward when opening, shrink upward when closing.
    /// Always keep the top edge fixed.
    func resizeWindowForInfoToggle() {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.keyWindow else { return }
            let contentLines = min(disk.files.count + 4, maxVisibleLines)
            let targetHeight = CGFloat(contentLines) * lineHeight + padding * 2 + infoPanelHeight + 16
            // Keep the top edge pinned, adjust the bottom
            let frame = NSRect(
                x: window.frame.minX,
                y: window.frame.maxY - targetHeight,
                width: windowWidth,
                height: targetHeight
            )
            window.setFrame(frame, display: true, animate: true)
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
