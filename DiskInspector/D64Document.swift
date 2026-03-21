import SwiftUI
import UniformTypeIdentifiers
import Combine

class D64Document: ReferenceFileDocument {
    let documentID = UUID()

    @Published var data: Data
    /// The format of this document — determines the correct save extension
    private(set) var diskFormat: DiskFormat
    /// The URL this document was last saved to (or opened from)
    var fileURL: URL?
    private var undoStack: [Data] = []
    private var redoStack: [Data] = []

    static var readableContentTypes: [UTType] {
        // Include our declared types AND any system/third-party types already
        // registered for these extensions — so the Open dialog accepts files
        // regardless of which UTType the system has assigned to them.
        var types: [UTType] = [.d64Disk, .d71Disk, .d81Disk]
        for ext in ["d64", "d71", "d81"] {
            if let systemType = UTType(filenameExtension: ext),
               !types.contains(systemType) {
                types.append(systemType)
            }
        }
        return types
    }

    static var writableContentTypes: [UTType] {
        [.d64Disk, .d71Disk, .d81Disk]
    }

    required init(configuration: ReadConfiguration) throws {
        if let fileData = configuration.file.regularFileContents {
            data = fileData
            diskFormat = DiskFormat.detect(size: fileData.count) ?? .d64
        } else {
            data = D64Document.createBlankD64(name: "NEW DISK", id: "00")
            diskFormat = .d64
        }
    }

    init() {
        data = D64Document.createBlankD64(name: "NEW DISK", id: "00")
        diskFormat = .d64
    }

    // MARK: - Disk display name

    var diskDisplayName: String {
        if let disk = D64Parser.parse(data: data) {
            return disk.diskName.uppercased()
        }
        return "DiskInspector"
    }

    // MARK: - Create blank disks

    init(format: DiskFormat = .d64) {
        diskFormat = format
        switch format {
        case .d71: data = D64Document.createBlankD71(name: "NEW DISK", id: "00")
        case .d81: data = D64Document.createBlankD81(name: "NEW DISK", id: "00")
        default:   data = D64Document.createBlankD64(name: "NEW DISK", id: "00")
        }
    }
    static func createBlankD64(name: String, id: String) -> Data {
        var bytes = [UInt8](repeating: 0x00, count: 174848)
        let bamOffset = D64Parser.offset(track: 18, sector: 0)

        bytes[bamOffset + 0x00] = 18
        bytes[bamOffset + 0x01] = 1
        bytes[bamOffset + 0x02] = 0x41
        bytes[bamOffset + 0x03] = 0x00

        for t in 1...35 {
            let entry = bamOffset + 4 + (t - 1) * 4
            if t == 18 {
                bytes[entry]     = 0
                bytes[entry + 1] = 0x00
                bytes[entry + 2] = 0x00
                bytes[entry + 3] = 0x00
            } else {
                let sectors = D64Parser.trackSectors(track: t, format: .d64)
                bytes[entry] = UInt8(sectors)
                let bits: UInt32 = (1 << sectors) - 1
                bytes[entry + 1] = UInt8(bits & 0xFF)
                bytes[entry + 2] = UInt8((bits >> 8) & 0xFF)
                bytes[entry + 3] = UInt8((bits >> 16) & 0xFF)
            }
        }

        let nameBytes = Array(name.uppercased().utf8)
        for i in 0..<16 {
            bytes[bamOffset + 0x90 + i] = i < nameBytes.count ? nameBytes[i] : 0xA0
        }
        bytes[bamOffset + 0xA0] = 0xA0
        bytes[bamOffset + 0xA1] = 0xA0
        let idBytes = Array(id.uppercased().utf8)
        for i in 0..<2 {
            bytes[bamOffset + 0xA2 + i] = i < idBytes.count ? idBytes[i] : 0x30
        }
        bytes[bamOffset + 0xA4] = 0xA0
        bytes[bamOffset + 0xA5] = 0x32
        bytes[bamOffset + 0xA6] = 0x41

        let dirOffset = D64Parser.offset(track: 18, sector: 1)
        bytes[dirOffset + 0x00] = 0x00
        bytes[dirOffset + 0x01] = 0xFF

        return Data(bytes)
    }

    static func createBlankD71(name: String, id: String) -> Data {
        var bytes = [UInt8](repeating: 0x00, count: 349696)

        let bam1 = D64Parser.offset(track: 18, sector: 0, format: .d71)
        bytes[bam1 + 0x00] = 18
        bytes[bam1 + 0x01] = 1
        bytes[bam1 + 0x02] = 0x41
        bytes[bam1 + 0x03] = 0x80
        bytes[bam1 + 0x04] = 53
        bytes[bam1 + 0x05] = 0

        for t in 1...35 {
            let entry = bam1 + 4 + (t - 1) * 4
            if t == 18 {
                bytes[entry]     = 0
                bytes[entry + 1] = 0x00
                bytes[entry + 2] = 0x00
                bytes[entry + 3] = 0x00
            } else {
                let sectors = D64Parser.trackSectors(track: t, format: .d71)
                bytes[entry] = UInt8(sectors)
                let bits: UInt32 = (1 << sectors) - 1
                bytes[entry + 1] = UInt8(bits & 0xFF)
                bytes[entry + 2] = UInt8((bits >> 8) & 0xFF)
                bytes[entry + 3] = UInt8((bits >> 16) & 0xFF)
            }
        }

        let nameBytes = Array(name.uppercased().utf8)
        for i in 0..<16 { bytes[bam1 + 0x90 + i] = i < nameBytes.count ? nameBytes[i] : 0xA0 }
        bytes[bam1 + 0xA0] = 0xA0
        bytes[bam1 + 0xA1] = 0xA0
        let idBytes = Array(id.uppercased().utf8)
        for i in 0..<2 { bytes[bam1 + 0xA2 + i] = i < idBytes.count ? idBytes[i] : 0x30 }
        bytes[bam1 + 0xA4] = 0xA0
        bytes[bam1 + 0xA5] = 0x32
        bytes[bam1 + 0xA6] = 0x41

        // Side 2 free counts stored at bam1 + 0xDC (one byte per track, tracks 36-70)
        for t in 36...70 {
            if t == 53 { continue }
            let freeCountOffset = bam1 + 0xDC + (t - 36)
            let sectors = D64Parser.trackSectors(track: t, format: .d71)
            bytes[freeCountOffset] = UInt8(sectors)
        }

        // Side 2 BAM bitmaps at T53/S0 — 3 bytes per track (no free-count byte)
        let bam2 = D64Parser.offset(track: 53, sector: 0, format: .d71)
        for t in 36...70 {
            let entry = bam2 + (t - 36) * 3
            if t == 53 {
                bytes[entry]     = 0x00
                bytes[entry + 1] = 0x00
                bytes[entry + 2] = 0x00
            } else {
                let sectors = D64Parser.trackSectors(track: t, format: .d71)
                let bits: UInt32 = (1 << sectors) - 1
                bytes[entry]     = UInt8(bits & 0xFF)
                bytes[entry + 1] = UInt8((bits >> 8) & 0xFF)
                bytes[entry + 2] = UInt8((bits >> 16) & 0xFF)
            }
        }

        let dir = D64Parser.offset(track: 18, sector: 1, format: .d71)
        bytes[dir + 0x00] = 0x00
        bytes[dir + 0x01] = 0xFF

        return Data(bytes)
    }

    static func createBlankD81(name: String, id: String) -> Data {
        var bytes = [UInt8](repeating: 0x00, count: 819200)
        let nameBytes = Array(name.uppercased().utf8)
        let idBytes   = Array(id.uppercased().utf8)

        // ── Header sector — track 40 sector 0 ──
        let header = D64Parser.offset(track: 40, sector: 0, format: .d81)
        bytes[header + 0x00] = 40   // link to first directory sector
        bytes[header + 0x01] = 3
        bytes[header + 0x02] = 0x44 // 'D'
        bytes[header + 0x03] = 0x00
        for i in 0..<16 { bytes[header + 0x04 + i] = i < nameBytes.count ? nameBytes[i] : 0xA0 }
        bytes[header + 0x14] = 0xA0
        bytes[header + 0x15] = 0xA0
        for i in 0..<2 { bytes[header + 0x16 + i] = i < idBytes.count ? idBytes[i] : 0x30 }
        bytes[header + 0x18] = 0xA0
        bytes[header + 0x19] = 0x33 // '3'
        bytes[header + 0x1A] = 0x44 // 'D'

        // ── BAM sector 1 — track 40 sector 1 (tracks 1-40) ──
        let bam1 = D64Parser.offset(track: 40, sector: 1, format: .d81)
        bytes[bam1 + 0x00] = 40   // link to BAM2
        bytes[bam1 + 0x01] = 2
        bytes[bam1 + 0x02] = 0x44
        bytes[bam1 + 0x03] = 0xBB
        for i in 0..<2 { bytes[bam1 + 0x04 + i] = i < idBytes.count ? idBytes[i] : 0x30 }
        bytes[bam1 + 0x06] = 0xC0
        // BAM entries at 0x10 — 6 bytes per track
        for t in 1...40 {
            let entry = bam1 + 0x10 + (t - 1) * 6
            if t == 40 {
                bytes[entry] = 0  // system track — all used
            } else {
                bytes[entry]     = 40
                bytes[entry + 1] = 0xFF
                bytes[entry + 2] = 0xFF
                bytes[entry + 3] = 0xFF
                bytes[entry + 4] = 0xFF
                bytes[entry + 5] = 0xFF
            }
        }

        // ── BAM sector 2 — track 40 sector 2 (tracks 41-80) ──
        let bam2 = D64Parser.offset(track: 40, sector: 2, format: .d81)
        bytes[bam2 + 0x00] = 0x00  // end of BAM chain
        bytes[bam2 + 0x01] = 0xFF
        bytes[bam2 + 0x02] = 0x44
        bytes[bam2 + 0x03] = 0xBB
        for i in 0..<2 { bytes[bam2 + 0x04 + i] = i < idBytes.count ? idBytes[i] : 0x30 }
        bytes[bam2 + 0x06] = 0xC0
        for t in 41...80 {
            let entry = bam2 + 0x10 + (t - 41) * 6
            bytes[entry]     = 40
            bytes[entry + 1] = 0xFF
            bytes[entry + 2] = 0xFF
            bytes[entry + 3] = 0xFF
            bytes[entry + 4] = 0xFF
            bytes[entry + 5] = 0xFF
        }

        // ── Directory — track 40 sector 3 ──
        let dir = D64Parser.offset(track: 40, sector: 3, format: .d81)
        bytes[dir + 0x00] = 0x00
        bytes[dir + 0x01] = 0xFF

        return Data(bytes)
    }

    // MARK: - Disk operations

    func renameDisk(name: String, id: String) {
        saveUndo()
        guard let bytes = D64Parser.renameDisk(in: [UInt8](data), name: name, id: id)
        else { undoStack.removeLast(); return }
        data = Data(bytes)
    }

    func snapshot(contentType: UTType) throws -> Data { data }

    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot)
    }

    /// File extension for this document's format
    var fileExtension: String {
        switch diskFormat {
        case .d64: return "d64"
        case .d71: return "d71"
        case .d81: return "d81"
        }
    }

    /// Save to the existing fileURL, or show a save panel if no URL yet
    func saveDocument() {
        if let url = fileURL ?? NSApplication.shared.keyWindow?.representedURL {
            do {
                try data.write(to: url)
                fileURL = url
            } catch {
                showSaveError(error)
            }
        } else {
            saveDocumentAs()
        }
    }

    /// Show a save panel and save to the chosen location
    func saveDocumentAs() {
        let panel = NSSavePanel()
        let filename = diskDisplayName.lowercased() + "." + fileExtension
        panel.nameFieldStringValue = filename
        // Use our declared UTType if available; fall back to generic .data
        // so the save panel always works even if Info.plist isn't loaded yet
        if let knownType = UTType(filenameExtension: fileExtension) {
            panel.allowedContentTypes = [knownType]
        } else {
            panel.allowedContentTypes = [.data]
        }
        panel.allowsOtherFileTypes = false
        panel.canSelectHiddenExtension = false
        panel.isExtensionHidden = false
        panel.message = "Save \(diskFormat.displayName) Disk Image"
        if panel.runModal() == .OK, var url = panel.url {
            // Ensure the correct extension is always present
            if url.pathExtension.lowercased() != fileExtension {
                url = url.appendingPathExtension(fileExtension)
            }
            do {
                try data.write(to: url)
                fileURL = url
                if let window = NSApplication.shared.keyWindow {
                    window.representedURL = url
                    window.title = diskDisplayName
                }
            } catch {
                showSaveError(error)
            }
        }
    }

    private func showSaveError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Save Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// The content type matching this document's disk format
    var currentContentType: UTType {
        switch diskFormat {
        case .d64: return .d64Disk
        case .d71: return .d71Disk
        case .d81: return .d81Disk
        }
    }

    // MARK: - Undo/Redo

    private func saveUndo() {
        undoStack.append(data)
        redoStack.removeAll()
        if undoStack.count > 20 { undoStack.removeFirst() }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(data)
        data = previous
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(data)
        data = next
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - File operations

    func injectFile(_ file: D64File, at targetIndex: Int? = nil) {
        saveUndo()
        guard let bytes = D64Parser.injectFile(into: [UInt8](data), file: file, at: targetIndex)
        else { undoStack.removeLast(); return }
        data = Data(bytes)
    }

    func deleteFile(_ file: D64File) {
        saveUndo()
        guard let bytes = D64Parser.deleteFile(from: [UInt8](data), file: file)
        else { undoStack.removeLast(); return }
        data = Data(bytes)
    }

    func deleteFileAtIndex(_ index: Int) {
        saveUndo()
        guard let bytes = D64Parser.deleteFileAtIndex(from: [UInt8](data), index: index)
        else { undoStack.removeLast(); return }
        data = Data(bytes)
    }

    func moveFile(from sourceIndex: Int, to destinationIndex: Int) {
        saveUndo()
        guard let bytes = D64Parser.moveFile(in: [UInt8](data), from: sourceIndex, to: destinationIndex)
        else { undoStack.removeLast(); return }
        data = Data(bytes)
    }

    func renameFile(_ file: D64File, to newName: String) {
        saveUndo()
        guard let bytes = D64Parser.renameFile(in: [UInt8](data), file: file, newName: newName)
        else { undoStack.removeLast(); return }
        data = Data(bytes)
    }

    func exportFile(_ file: D64File, to url: URL) throws {
        try file.rawData.write(to: url)
    }

    /// Write modified file data back into the disk image's sector chain
    func patchFileData(_ file: D64File, newData: Data) {
        guard file.track != 0 else { return }
        saveUndo()
        guard let format = DiskFormat.detect(size: data.count),
              let bytes = D64Parser.writeBytesToFile(
                  in: [UInt8](data),
                  startTrack: file.track,
                  startSector: file.sector,
                  newFileData: [UInt8](newData),
                  format: format)
        else { undoStack.removeLast(); return }
        data = Data(bytes)
    }
}
