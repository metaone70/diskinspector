import SwiftUI
import AppKit
import Combine

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

    // PETSCII codes reference:
    // $40 = horizontal bar ─
    // $60 = lower-left bar
    // $6E = lower-right bar
    // $70 = upper-right bar
    // $7D = upper-left bar ┌ (in uppercase mode)
    // $43 = ─ (C shifted)
    // $55 = ┼ cross
    // $5D = │ vertical bar
    // $6B = ┤ right-T
    // $73 = ├ left-T
    // $72 = ┴ bottom-T
    // $71 = ┬ top-T
    // $51 = ● ball
    // $57 = ◤ upper-left triangle
    // $5C = ◣ lower-left triangle (shifted pound)
    // $69 = ◥ upper-right
    // $5F = ◢ lower-right
    // $66 = ▌ left half
    // $62 = ▐ right half
    // $A0 = shifted space (padding)
    // $2A = * asterisk
    // $2D = - dash
    // $3D = = equals

    static let patterns: [SeparatorPattern] = {
        var list: [SeparatorPattern] = []

        // ── Single Lines ──
        list.append(SeparatorPattern(
            name: "Horizontal Line",
            rawBytes: Array(repeating: UInt8(0x40), count: 16),
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

        // ── Box Drawing ──
        list.append(SeparatorPattern(
            name: "Top Border",
            rawBytes: [0x70] + Array(repeating: UInt8(0x40), count: 14) + [0x6E],
            category: "Borders"
        ))

        list.append(SeparatorPattern(
            name: "Bottom Border",
            rawBytes: [0x6D] + Array(repeating: UInt8(0x40), count: 14) + [0x7D],
            category: "Borders"
        ))

        list.append(SeparatorPattern(
            name: "T-Junction Line",
            rawBytes: [0x73] + Array(repeating: UInt8(0x40), count: 14) + [0x6B],
            category: "Borders"
        ))

        list.append(SeparatorPattern(
            name: "Cross Line",
            rawBytes: [0x5B] + Array(repeating: UInt8(0x40), count: 14) + [0x5B],
            category: "Borders"
        ))

        // ── Block Graphics ──
        list.append(SeparatorPattern(
            name: "Full Blocks",
            rawBytes: Array(repeating: UInt8(0xA0), count: 16),
            category: "Blocks"
        ))

        list.append(SeparatorPattern(
            name: "Left Half Blocks",
            rawBytes: Array(repeating: UInt8(0x61), count: 16),
            category: "Blocks"
        ))

        list.append(SeparatorPattern(
            name: "Upper Half Blocks",
            rawBytes: Array(repeating: UInt8(0x62), count: 16),
            category: "Blocks"
        ))

        list.append(SeparatorPattern(
            name: "Checker Pattern",
            rawBytes: (0..<16).map { $0 % 2 == 0 ? UInt8(0x66) : UInt8(0x5C) },
            category: "Blocks"
        ))

        // ── Decorative ──
        list.append(SeparatorPattern(
            name: "Ball Line",
            rawBytes: Array(repeating: UInt8(0x51), count: 16),
            category: "Decorative"
        ))

        list.append(SeparatorPattern(
            name: "Diamond Line",
            rawBytes: Array(repeating: UInt8(0x5A), count: 16),
            category: "Decorative"
        ))

        list.append(SeparatorPattern(
            name: "Heart Line",
            rawBytes: Array(repeating: UInt8(0x53), count: 16),
            category: "Decorative"
        ))

        list.append(SeparatorPattern(
            name: "Spade-Ball Alternate",
            rawBytes: (0..<16).map { $0 % 2 == 0 ? UInt8(0x41) : UInt8(0x51) },
            category: "Decorative"
        ))

        list.append(SeparatorPattern(
            name: "Arrow Right",
            rawBytes: [0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x3E, 0x3E,
                       0x3E, 0x3E, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40],
            category: "Decorative"
        ))

        list.append(SeparatorPattern(
            name: "Stars and Bars",
            rawBytes: [0x2A, 0x40, 0x40, 0x2A, 0x40, 0x40, 0x2A, 0x40,
                       0x40, 0x2A, 0x40, 0x40, 0x2A, 0x40, 0x40, 0x2A],
            category: "Decorative"
        ))

        // ── Blank ──
        list.append(SeparatorPattern(
            name: "Blank Line",
            rawBytes: [0x20],
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
    static func open(document: D64Document) {
        let view = NSHostingController(rootView: SeparatorLibraryView(document: document))
        let window = NSWindow(contentViewController: view)
        window.title = "Separators"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 420, height: 500))
        window.minSize = NSSize(width: 360, height: 300)
        window.center()
        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        objc_setAssociatedObject(window, "controller", controller, .OBJC_ASSOCIATION_RETAIN)
    }
}

struct SeparatorLibraryView: View {
    let document: D64Document
    @ObservedObject private var customSeparators = CustomSeparators.shared
    @State private var selectedID: UUID?
    @State private var showingCustomEditor = false
    @State private var customName = ""
    @State private var customText = ""

    private let monoFont = "C64 Pro Mono"

    var allPatterns: [SeparatorPattern] {
        SeparatorLibrary.patterns + customSeparators.patterns
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("SEPARATOR LIBRARY")
                    .font(.custom(monoFont, size: 14))
                    .foregroundColor(Color.c64Blue)
                Spacer()
                Button("New…") {
                    customName = ""
                    customText = ""
                    showingCustomEditor = true
                }
                .font(.custom(monoFont, size: 11))
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Pattern list grouped by category
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(SeparatorLibrary.categories + (customSeparators.patterns.isEmpty ? [] : ["Custom"]), id: \.self) { category in
                        Text(category.uppercased())
                            .font(.custom(monoFont, size: 10))
                            .foregroundColor(Color.c64LightBlue)
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                            .padding(.bottom, 4)

                        ForEach(patternsForCategory(category)) { pattern in
                            separatorRow(pattern)
                        }
                    }
                }
            }

            Divider()

            // Action buttons
            HStack {
                Button("Insert") {
                    insertSelected()
                }
                .disabled(selectedID == nil)
                .font(.custom(monoFont, size: 12))

                Button("Insert x3") {
                    insertSelectedMultiple(3)
                }
                .disabled(selectedID == nil)
                .font(.custom(monoFont, size: 12))

                Spacer()

                if let sel = selectedID, customSeparators.patterns.contains(where: { $0.id == sel }) {
                    Button("Delete Custom") {
                        if let idx = customSeparators.patterns.firstIndex(where: { $0.id == sel }) {
                            customSeparators.remove(at: idx)
                            selectedID = nil
                        }
                    }
                    .font(.custom(monoFont, size: 11))
                    .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 360, minHeight: 300)
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
        return HStack(spacing: 0) {
            // Preview: show as it would appear in directory
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
                .padding(.trailing, 16)
        }
        .padding(.horizontal, 16)
        .frame(height: 20)
        .background(isSelected ? Color.c64Blue : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedID = pattern.id
        }
        .onTapGesture(count: 2) {
            selectedID = pattern.id
            insertSelected()
        }
    }

    func insertSelected() {
        guard let sel = selectedID,
              let pattern = allPatterns.first(where: { $0.id == sel }) else { return }
        document.injectFile(pattern.toD64File())
    }

    func insertSelectedMultiple(_ count: Int) {
        guard let sel = selectedID,
              let pattern = allPatterns.first(where: { $0.id == sel }) else { return }
        for _ in 0..<count {
            document.injectFile(pattern.toD64File())
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
                TextField("Enter up to 16 characters", text: $customText)
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
                Button("Cancel") {
                    showingCustomEditor = false
                }
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
