import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

// MARK: - Separator Pattern

struct SeparatorPattern: Identifiable {
    let id = UUID()
    let name: String
    let rawBytes: [UInt8]   // PETSCII bytes (up to 16)
    let category: String

    /// Display string using the same PETSCII→String logic as the parser
    var displayName: String {
        D64Parser.petsciiToString(ArraySlice(rawBytes))
    }

    /// Create a 0-block DEL file for injection into a disk directory
    func toD64File() -> D64File {
        D64File(
            filename: displayName,
            rawFilename: rawBytes,
            fileType: "DEL",
            fileTypeByte: 0x80,   // closed DEL
            blocks: 0,
            track: 0,
            sector: 0,
            rawData: Data()
        )
    }
}

// MARK: - Built-in Separator Library

struct SeparatorLibrary {

    // PETSCII graphics byte reference:
    // Bytes $60-$7F and $C0-$DF → PUA graphics in C64 Pro Mono
    // Bytes $20-$5F → ASCII (letters/symbols, NOT graphics)
    //
    // $C0/$60 = ─  horizontal line
    // $DD/$7D = │  vertical line
    // $70     = ┘  corner
    // $6E     = ┐  corner
    // $6D     = └  corner
    // $6B     = ┌  corner
    // $73     = ├  left-T / heart
    // $7B     = ┼  cross
    // $71     = ●  ball/circle
    // $61     = ♠  spade
    // $78     = ♣  club
    // $7A     = ♦  diamond
    // $62     = ▌  half block

    static let patterns: [SeparatorPattern] = {
        var list: [SeparatorPattern] = []

        // ── Frame Parts (DirMaster-style, at the top) ──
        // These are the building blocks for creating boxes/frames
        list.append(SeparatorPattern(
            name: "Top Frame",
            rawBytes: [0xB0] + Array(repeating: UInt8(0x60), count: 14) + [0xAE],
            category: "Frames"
        ))
        list.append(SeparatorPattern(
            name: "Middle Frame",
            rawBytes: [0xAB] + Array(repeating: UInt8(0x63), count: 14) + [0xB3],
            category: "Frames"
        ))
        list.append(SeparatorPattern(
            name: "Bottom Frame",
            rawBytes: [0xAD] + Array(repeating: UInt8(0x60), count: 14) + [0xBD],
            category: "Frames"
        ))
        list.append(SeparatorPattern(
            name: "Side Frame",
            rawBytes: [0x62] + Array(repeating: UInt8(0x20), count: 14) + [0x62],
            category: "Frames"
        ))

        // ── Lines ──
        list.append(SeparatorPattern(
            name: "Horizontal Line",
            rawBytes: Array(repeating: UInt8(0xC0), count: 16),
            category: "Lines"
        ))
        list.append(SeparatorPattern(
            name: "Dashes",
            rawBytes: Array(repeating: UInt8(0x2D), count: 16),
            category: "Lines"
        ))
        list.append(SeparatorPattern(
            name: "Equals",
            rawBytes: Array(repeating: UInt8(0x3D), count: 16),
            category: "Lines"
        ))
        list.append(SeparatorPattern(
            name: "Asterisks",
            rawBytes: Array(repeating: UInt8(0x2A), count: 16),
            category: "Lines"
        ))
        list.append(SeparatorPattern(
            name: "Dots",
            rawBytes: Array(repeating: UInt8(0x2E), count: 16),
            category: "Lines"
        ))
        // ── Decorative ──
        list.append(SeparatorPattern(
            name: "Ball Line",
            rawBytes: Array(repeating: UInt8(0x71), count: 16),
            category: "Decorative"
        ))
        list.append(SeparatorPattern(
            name: "Diamond Line",
            rawBytes: Array(repeating: UInt8(0x7A), count: 16),
            category: "Decorative"
        ))
        list.append(SeparatorPattern(
            name: "Heart Line",
            rawBytes: Array(repeating: UInt8(0x73), count: 16),
            category: "Decorative"
        ))
        list.append(SeparatorPattern(
            name: "Club Line",
            rawBytes: Array(repeating: UInt8(0x78), count: 16),
            category: "Decorative"
        ))
        list.append(SeparatorPattern(
            name: "Cross Line",
            rawBytes: Array(repeating: UInt8(0x7B), count: 16),
            category: "Decorative"
        ))
        list.append(SeparatorPattern(
            name: "Stars and Lines",
            rawBytes: [0x2A, 0xC0, 0xC0, 0x2A, 0xC0, 0xC0, 0x2A, 0xC0,
                       0xC0, 0x2A, 0xC0, 0xC0, 0x2A, 0xC0, 0xC0, 0x2A],
            category: "Decorative"
        ))
        list.append(SeparatorPattern(
            name: "Balls and Lines",
            rawBytes: [0x71, 0xC0, 0xC0, 0x71, 0xC0, 0xC0, 0x71, 0xC0,
                       0xC0, 0x71, 0xC0, 0xC0, 0x71, 0xC0, 0xC0, 0x71],
            category: "Decorative"
        ))

        // ── Blank ──
        list.append(SeparatorPattern(
            name: "Blank Line",
            rawBytes: Array(repeating: UInt8(0x20), count: 16),
            category: "Spacing"
        ))

        return list
    }()

    static var categories: [String] {
        var seen: [String] = []
        for p in patterns {
            if !seen.contains(p.category) { seen.append(p.category) }
        }
        return seen
    }
}

// MARK: - Custom Separator Storage

class CustomSeparators: ObservableObject {
    static let shared = CustomSeparators()
    private let storageKey = "CustomSeparatorPatterns"

    @Published var patterns: [SeparatorPattern] = []

    private init() {
        load()
    }

    func add(name: String, rawBytes: [UInt8]) {
        let pattern = SeparatorPattern(name: name, rawBytes: rawBytes, category: "Custom")
        patterns.append(pattern)
        save()
    }

    func remove(at index: Int) {
        guard index < patterns.count else { return }
        patterns.remove(at: index)
        save()
    }

    private func save() {
        let dicts = patterns.map { ["name": $0.name, "bytes": $0.rawBytes.map { Int($0) }] } as [[String: Any]]
        UserDefaults.standard.set(dicts, forKey: storageKey)
    }

    private func load() {
        guard let dicts = UserDefaults.standard.array(forKey: storageKey) as? [[String: Any]] else { return }
        patterns = dicts.compactMap { dict in
            guard let name = dict["name"] as? String,
                  let ints = dict["bytes"] as? [Int] else { return nil }
            return SeparatorPattern(name: name, rawBytes: ints.map { UInt8($0) }, category: "Custom")
        }
    }
}

// MARK: - Separator Library Window

struct SeparatorLibraryWindow {
    /// Open the separator library. Pass the selection state so inserts go after the selected file.
    static func open(document: D64Document, selection: SelectionState? = nil) {
        let view = NSHostingController(
            rootView: SeparatorLibraryView(document: document, selection: selection)
        )
        let window = NSWindow(contentViewController: view)
        window.title = "Separators"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 520, height: 540))
        window.minSize = NSSize(width: 440, height: 300)
        window.center()
        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        objc_setAssociatedObject(window, "controller", controller, .OBJC_ASSOCIATION_RETAIN)
    }
}

// MARK: - Separator Library View

struct SeparatorLibraryView: View {
    let document: D64Document
    let selection: SelectionState?
    @ObservedObject private var customSeparators = CustomSeparators.shared
    @State private var selectedID: UUID?
    @State private var showingCustomEditor = false
    @State private var customName = ""
    @State private var customText = ""

    private let monoFont = "C64 Pro Mono"
    private let rowHeight: CGFloat = 18

    var allPatterns: [SeparatorPattern] {
        SeparatorLibrary.patterns + customSeparators.patterns
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Pattern list ──
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let cats = SeparatorLibrary.categories
                        + (customSeparators.patterns.isEmpty ? [] : ["Custom"])

                    ForEach(cats, id: \.self) { category in
                        Text(category.uppercased())
                            .font(.custom(monoFont, size: 10))
                            .foregroundColor(Color.c64LightBlue)
                            .padding(.leading, 12)
                            .padding(.top, 10)
                            .padding(.bottom, 2)

                        ForEach(patternsForCategory(category)) { pattern in
                            separatorRow(pattern)
                        }
                    }
                }
                .padding(.bottom, 8)
            }

            Divider()

            // ── Action bar ──
            HStack(spacing: 12) {
                Button("Insert") { insertSelected() }
                    .disabled(selectedID == nil)

                Button("Insert x3") { insertSelectedMultiple(3) }
                    .disabled(selectedID == nil)

                Spacer()

                Button("New…") {
                    customName = ""
                    customText = ""
                    showingCustomEditor = true
                }

                if let sel = selectedID, customSeparators.patterns.contains(where: { $0.id == sel }) {
                    Button("Delete") {
                        if let idx = customSeparators.patterns.firstIndex(where: { $0.id == sel }) {
                            customSeparators.remove(at: idx)
                            selectedID = nil
                        }
                    }
                    .foregroundColor(.red)
                }
            }
            .font(.custom(monoFont, size: 11))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 440, minHeight: 300)
        .sheet(isPresented: $showingCustomEditor) {
            customEditorSheet
        }
    }

    func patternsForCategory(_ category: String) -> [SeparatorPattern] {
        if category == "Custom" {
            return customSeparators.patterns
        }
        return SeparatorLibrary.patterns.filter { $0.category == category }
    }

    func separatorRow(_ pattern: SeparatorPattern) -> some View {
        let isSelected = selectedID == pattern.id
        let row = HStack(spacing: 0) {
            Text("0   ")
                .font(.custom(monoFont, size: 14))
                .foregroundColor(isSelected ? .white : Color.c64Blue)

            Text("\"\(pattern.displayName)\"")
                .font(.custom(monoFont, size: 14))
                .foregroundColor(isSelected ? .white : Color.c64Blue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            Text("DEL")
                .font(.custom(monoFont, size: 14))
                .foregroundColor(isSelected ? .white : Color.c64LightBlue)
        }
        .padding(.horizontal, 12)
        .frame(height: rowHeight)
        .background(isSelected ? Color.c64Blue : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            selectedID = pattern.id
            insertSelected()
        }
        .onTapGesture {
            selectedID = pattern.id
        }

        // Drag support — drag the separator as a D64File to the main directory window
        let d64file = pattern.toD64File()
        return row.onDrag {
            let provider = NSItemProvider()
            if let encoded = try? JSONEncoder().encode(d64file) {
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
    }

    /// Find the directory slot index to insert AFTER the selected file in the main window
    private func insertionTargetIndex() -> Int? {
        guard let sel = selection, let lastIdx = sel.lastTappedIndex() else { return nil }
        guard let disk = D64Parser.parse(data: document.data) else { return nil }
        guard lastIdx < disk.files.count else { return nil }
        let targetFile = disk.files[lastIdx]
        guard let dirIdx = D64Parser.directoryIndex(
            in: [UInt8](document.data), forFile: targetFile
        ) else { return nil }
        return dirIdx + 1  // insert AFTER the selected file
    }

    func insertSelected() {
        guard let sel = selectedID,
              let pattern = allPatterns.first(where: { $0.id == sel }) else { return }
        let target = insertionTargetIndex()
        document.injectFile(pattern.toD64File(), at: target)
    }

    func insertSelectedMultiple(_ count: Int) {
        guard let sel = selectedID,
              let pattern = allPatterns.first(where: { $0.id == sel }) else { return }
        var target = insertionTargetIndex()
        for _ in 0..<count {
            document.injectFile(pattern.toD64File(), at: target)
            // Advance target so subsequent inserts go in order
            if let t = target { target = t + 1 }
        }
    }

    var customEditorSheet: some View {
        VStack(spacing: 12) {
            Text("CREATE CUSTOM SEPARATOR")
                .font(.custom(monoFont, size: 14))
                .foregroundColor(Color.c64Blue)

            HStack {
                Text("Name:")
                    .font(.custom(monoFont, size: 11))
                    .foregroundColor(Color.c64LightBlue)
                TextField("My Separator", text: $customName)
                    .font(.system(size: 12, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
            }

            HStack(alignment: .top) {
                Text("Text:")
                    .font(.custom(monoFont, size: 11))
                    .foregroundColor(Color.c64LightBlue)
                TextField("Up to 16 characters", text: $customText)
                    .font(.custom(monoFont, size: 14))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: customText) {
                        if customText.count > 16 {
                            customText = String(customText.prefix(16))
                        }
                    }
            }

            Text("Type ASCII characters. They will be stored as PETSCII.")
                .font(.custom(monoFont, size: 9))
                .foregroundColor(Color.c64LightBlue.opacity(0.7))

            HStack {
                Button("Cancel") { showingCustomEditor = false }
                Spacer()
                Button("Add") {
                    guard !customName.isEmpty, !customText.isEmpty else { return }
                    let rawBytes = Array(customText.uppercased().utf8).prefix(16).map { UInt8($0) }
                    customSeparators.add(name: customName, rawBytes: Array(rawBytes))
                    showingCustomEditor = false
                }
                .disabled(customName.isEmpty || customText.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
