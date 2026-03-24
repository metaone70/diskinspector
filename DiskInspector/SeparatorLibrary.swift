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

    // PETSCII codes reference (uppercase/graphics mode):
    // $40 = horizontal bar ─
    // $6D = lower-left corner └
    // $6E = lower-right corner (upper-left visually) ┐
    // $70 = upper-right corner ┘
    // $7D = upper-left corner ┌
    // $5D = vertical bar │
    // $6B = right-T ┤
    // $73 = left-T ├
    // $72 = bottom-T ┴
    // $71 = top-T ┬
    // $5B = cross ┼
    // $51 = ● filled circle
    // $57 = ◤ triangle upper-left
    // $5C = ◣ triangle lower-left
    // $69 = ◢ triangle lower-right
    // $5F = ◥ triangle upper-right
    // $61 = ▌ left half block
    // $62 = ▐ right half / upper half
    // $A0 = shifted space (solid block when reversed)
    // $2A = * asterisk
    // $2D = - dash
    // $3D = = equals
    // $2E = . period
    // $5A = ♦ diamond
    // $53 = ♥ heart
    // $41 = ♠ spade
    // $58 = ♣ club

    static let patterns: [SeparatorPattern] = {
        var list: [SeparatorPattern] = []

        // ── Lines ──
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
            name: "Club Line",
            rawBytes: Array(repeating: UInt8(0x58), count: 16),
            category: "Decorative"
        ))
        list.append(SeparatorPattern(
            name: "Spade Line",
            rawBytes: Array(repeating: UInt8(0x41), count: 16),
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
        window.setContentSize(NSSize(width: 520, height: 540))
        window.minSize = NSSize(width: 440, height: 300)
        window.center()
        window.backgroundColor = NSColor(Color.c64Blue)
        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        objc_setAssociatedObject(window, "controller", controller, .OBJC_ASSOCIATION_RETAIN)
    }
}

// MARK: - Separator Library View (DirMaster-style C64 look)

struct SeparatorLibraryView: View {
    let document: D64Document
    @ObservedObject private var customSeparators = CustomSeparators.shared
    @State private var selectedID: UUID?
    @State private var showingCustomEditor = false
    @State private var customName = ""
    @State private var customText = ""

    private let monoFont = "C64 Pro Mono"
    private let rowHeight: CGFloat = 16

    var allPatterns: [SeparatorPattern] {
        SeparatorLibrary.patterns + customSeparators.patterns
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── C64-style header bar ──
            HStack {
                Text(" SEPARATORS ")
                    .font(.custom(monoFont, size: 14))
                    .foregroundColor(Color.c64Blue)
                    .background(Color.c64LightBlue)
                Spacer()
                Button(action: {
                    customName = ""
                    customText = ""
                    showingCustomEditor = true
                }) {
                    Text(" NEW ")
                        .font(.custom(monoFont, size: 11))
                        .foregroundColor(Color.c64Blue)
                        .background(Color.c64LightBlue)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color.c64Blue)

            // ── Separator list on blue background ──
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let cats = SeparatorLibrary.categories
                        + (customSeparators.patterns.isEmpty ? [] : ["Custom"])

                    ForEach(cats, id: \.self) { category in
                        // Category header — light blue text on blue
                        Text("  \(category.uppercased())")
                            .font(.custom(monoFont, size: 11))
                            .foregroundColor(Color.c64LightBlue)
                            .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
                            .padding(.top, 6)

                        ForEach(patternsForCategory(category)) { pattern in
                            separatorRow(pattern)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .background(Color.c64Blue)

            // ── Bottom action bar ──
            HStack(spacing: 12) {
                Button(action: { insertSelected() }) {
                    Text("INSERT")
                        .font(.custom(monoFont, size: 11))
                        .foregroundColor(selectedID != nil ? Color.c64Blue : Color.c64Blue.opacity(0.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(selectedID != nil ? Color.c64LightBlue : Color.c64LightBlue.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(selectedID == nil)

                Button(action: { insertSelectedMultiple(3) }) {
                    Text("INSERT X3")
                        .font(.custom(monoFont, size: 11))
                        .foregroundColor(selectedID != nil ? Color.c64Blue : Color.c64Blue.opacity(0.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(selectedID != nil ? Color.c64LightBlue : Color.c64LightBlue.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(selectedID == nil)

                Spacer()

                if let sel = selectedID, customSeparators.patterns.contains(where: { $0.id == sel }) {
                    Button(action: {
                        if let idx = customSeparators.patterns.firstIndex(where: { $0.id == sel }) {
                            customSeparators.remove(at: idx)
                            selectedID = nil
                        }
                    }) {
                        Text("DELETE")
                            .font(.custom(monoFont, size: 11))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.c64Blue)
        }
        .background(Color.c64Blue)
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
            Text("0   ")
                .font(.custom(monoFont, size: 14))
                .foregroundColor(isSelected ? Color.c64Blue : Color.c64LightBlue)

            Text("\"\(pattern.displayName)\"")
                .font(.custom(monoFont, size: 14))
                .foregroundColor(isSelected ? Color.c64Blue : Color.c64LightBlue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            Text("DEL")
                .font(.custom(monoFont, size: 14))
                .foregroundColor(isSelected ? Color.c64Blue : Color.c64LightBlue)
        }
        .padding(.horizontal, 8)
        .frame(height: rowHeight)
        .background(isSelected ? Color.c64LightBlue : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            selectedID = pattern.id
            insertSelected()
        }
        .onTapGesture {
            selectedID = pattern.id
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
