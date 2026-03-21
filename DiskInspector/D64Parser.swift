import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Disk Format

enum DiskFormat {
    case d64
    case d71
    case d81

    static func detect(size: Int) -> DiskFormat? {
        switch size {
        case 174848: return .d64
        case 349696: return .d71
        case 819200: return .d81
        default:     return nil
        }
    }

    var bamTrack: Int {
        switch self {
        case .d64, .d71: return 18
        case .d81:       return 40
        }
    }

    var bamSector: Int {
        switch self {
        case .d64, .d71: return 0
        case .d81:       return 1
        }
    }

    var dirTrack: Int {
        switch self {
        case .d64, .d71: return 18
        case .d81:       return 40
        }
    }

    var dirSector: Int {
        switch self {
        case .d64, .d71: return 1
        case .d81:       return 3
        }
    }

    var totalBlocks: Int {
        switch self {
        case .d64: return 664
        case .d71: return 1328
        case .d81: return 3160
        }
    }

    var totalTracks: Int {
        switch self {
        case .d64: return 35
        case .d71: return 70
        case .d81: return 80
        }
    }

    var systemTrack: Int {
        switch self {
        case .d64, .d71: return 18
        case .d81:       return 40
        }
    }

    var displayName: String {
        switch self {
        case .d64: return "D64"
        case .d71: return "D71"
        case .d81: return "D81"
        }
    }

    var dosVersion: String {
        switch self {
        case .d64: return "2A"
        case .d71: return "2A"
        case .d81: return "3D"
        }
    }
}

// MARK: - D64File

struct D64File: Identifiable, Codable, Transferable {
    let id: UUID
    let filename: String
    let rawFilename: [UInt8]
    let fileType: String
    /// The original file-type byte from the directory entry (preserves locked/splat bits)
    let fileTypeByte: UInt8
    let blocks: Int
    let track: UInt8
    let sector: UInt8
    let rawData: Data
    var sourceDocumentID: UUID

    init(filename: String, rawFilename: [UInt8] = [], fileType: String, fileTypeByte: UInt8? = nil,
         blocks: Int, track: UInt8, sector: UInt8, rawData: Data = Data(),
         sourceDocumentID: UUID = UUID()) {
        self.id = UUID()
        self.filename = filename
        self.rawFilename = rawFilename
        self.fileType = fileType
        // If no explicit byte provided, synthesize a closed (bit 7) type byte
        if let ftb = fileTypeByte {
            self.fileTypeByte = ftb
        } else {
            let code: UInt8
            switch fileType {
            case "DEL": code = 0x00
            case "SEQ": code = 0x01
            case "USR": code = 0x03
            case "REL": code = 0x04
            default:    code = 0x02 // PRG
            }
            self.fileTypeByte = 0x80 | code
        }
        self.blocks = blocks
        self.track = track
        self.sector = sector
        self.rawData = rawData
        self.sourceDocumentID = sourceDocumentID
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .d64File)
    }
}

extension UTType {
    // For D64File clipboard transfer
    static let d64File = UTType(exportedAs: "com.diskinspector.d64file")

    // For disk image documents — these must match the Info.plist exported type declarations
    static let d64Disk = UTType(exportedAs: "com.diskinspector.d64",
                                conformingTo: .data)
    static let d71Disk = UTType(exportedAs: "com.diskinspector.d71",
                                conformingTo: .data)
    static let d81Disk = UTType(exportedAs: "com.diskinspector.d81",
                                conformingTo: .data)
}

// MARK: - D64Disk

struct D64Disk {
    let diskName:   String
    let diskID:     String
    let freeBlocks: Int
    let files:      [D64File]
    let format:     DiskFormat
}

// MARK: - D64Parser

struct D64Parser {

    // Legacy array — kept for createBlankD64 compatibility
    static let sectorsPerTrack: [Int] = [
        0,
        21,21,21,21,21,21,21,21,21,
        21,21,21,21,21,21,21,21,
        19,19,19,19,19,19,19,
        18,18,18,18,18,18,
        17,17,17,17,17
    ]

    static func trackSectors(track: Int, format: DiskFormat) -> Int {
        switch format {
        case .d81:
            return 40
        case .d64:
            switch track {
            case 1...17:  return 21
            case 18...24: return 19
            case 25...30: return 18
            case 31...35: return 17
            default:      return 0
            }
        case .d71:
            switch track {
            case 1...17:  return 21
            case 18...24: return 19
            case 25...30: return 18
            case 31...35: return 17
            case 36...52: return 21
            case 53...59: return 19
            case 60...65: return 18
            case 66...70: return 17
            default:      return 0
            }
        }
    }

    static func offset(track: Int, sector: Int, format: DiskFormat) -> Int {
        var total = 0
        for t in 1..<track {
            total += trackSectors(track: t, format: format)
        }
        return (total + sector) * 256
    }

    // Legacy offset — keeps existing callers working
    static func offset(track: Int, sector: Int) -> Int {
        return offset(track: track, sector: sector, format: .d64)
    }

    // MARK: - BAM Offsets
    //
    // Returns (freeCountOffset, bitmapOffset) for a given track.
    // D71 side 2 stores free counts at T18/S0+0xDC and bitmaps
    // at T53/S0 in 3-byte groups — unlike side 1's contiguous 4-byte entries.

    static func bamOffsets(track t: Int, format: DiskFormat) -> (freeCount: Int, bitmap: Int) {
        switch format {
        case .d64:
            let e = offset(track: 18, sector: 0, format: .d64) + 4 + (t - 1) * 4
            return (e, e + 1)
        case .d71:
            if t <= 35 {
                let e = offset(track: 18, sector: 0, format: .d71) + 4 + (t - 1) * 4
                return (e, e + 1)
            } else {
                let bam1 = offset(track: 18, sector: 0, format: .d71)
                let bam2 = offset(track: 53, sector: 0, format: .d71)
                return (bam1 + 0xDC + (t - 36), bam2 + (t - 36) * 3)
            }
        case .d81:
            if t <= 40 {
                let e = offset(track: 40, sector: 1, format: .d81) + 0x10 + (t - 1) * 6
                return (e, e + 1)
            } else {
                let e = offset(track: 40, sector: 2, format: .d81) + 0x10 + (t - 41) * 6
                return (e, e + 1)
            }
        }
    }

    // MARK: - PETSCII

    static func petsciiToString(_ bytes: ArraySlice<UInt8>) -> String {
        let cleaned = bytes
            .prefix(while: { $0 != 0xA0 && $0 != 0x00 })
            .map { b -> Character in
                if b >= 0x20 && b <= 0x5F {
                    return Character(UnicodeScalar(b))
                }
                if b >= 0x80 && b <= 0x9F {
                    return Character(UnicodeScalar(0x2588)!)
                }
                if let scalar = Unicode.Scalar(UInt32(b) + 0xE000) {
                    return Character(scalar)
                }
                return Character(" ")
            }
        return String(cleaned)
    }

    // MARK: - Parse

    static func parse(data: Data) -> D64Disk? {
        guard let format = DiskFormat.detect(size: data.count) else { return nil }
        let bytes = [UInt8](data)

        let diskName: String
        let diskID:   String
        var freeBlocks = 0

        switch format {
        case .d64, .d71:
            let bamOffset = offset(track: 18, sector: 0, format: format)
            diskName  = petsciiToString(bytes[(bamOffset + 0x90)..<(bamOffset + 0xA0)])
            diskID    = petsciiToString(bytes[(bamOffset + 0xA2)..<(bamOffset + 0xA7)])
            for t in 1...35 {
                if t == 18 { continue }
                let entry = bamOffset + 0x04 + (t - 1) * 4
                freeBlocks += Int(bytes[entry])
            }
            if format == .d71 {
                let bam1 = offset(track: 18, sector: 0, format: .d71)
                for t in 36...70 {
                    if t == 53 { continue }
                    let entry = bam1 + 0xDC + (t - 36)
                    if entry < bytes.count { freeBlocks += Int(bytes[entry]) }
                }
            }

        case .d81:
            let headerOff = offset(track: 40, sector: 0, format: .d81)
            diskName = petsciiToString(bytes[(headerOff + 0x04)..<(headerOff + 0x14)])
            diskID   = petsciiToString(bytes[(headerOff + 0x16)..<(headerOff + 0x18)])
            let bam1 = offset(track: 40, sector: 1, format: .d81)
            for t in 1...40 {
                if t == 40 { continue }
                let entry = bam1 + 0x10 + (t - 1) * 6
                if entry < bytes.count { freeBlocks += Int(bytes[entry]) }
            }
            let bam2 = offset(track: 40, sector: 2, format: .d81)
            for t in 41...80 {
                let entry = bam2 + 0x10 + (t - 41) * 6
                if entry < bytes.count { freeBlocks += Int(bytes[entry]) }
            }
        }

        // Directory entries — same 32-byte format for all formats
        var files:     [D64File] = []
        var dirTrack   = UInt8(format.dirTrack)
        var dirSector  = UInt8(format.dirSector)
        var visited    = Set<String>()

        while dirTrack != 0 {
            let key = "\(dirTrack):\(dirSector)"
            if visited.contains(key) { break }
            visited.insert(key)

            let sectorOff = offset(track: Int(dirTrack), sector: Int(dirSector), format: format)
            dirTrack  = bytes[sectorOff]
            dirSector = bytes[sectorOff + 1]

            for entry in 0..<8 {
                let base = sectorOff + 2 + (entry * 32)
                let fileTypeByte = bytes[base]
                if fileTypeByte == 0x00 { continue }

                let typeCode = fileTypeByte & 0x07
                let fileType: String
                switch typeCode {
                case 0x00: fileType = "DEL"
                case 0x01: fileType = "SEQ"
                case 0x02: fileType = "PRG"
                case 0x03: fileType = "USR"
                case 0x04: fileType = "REL"
                default:   fileType = "???"
                }

                let firstTrack  = bytes[base + 1]
                let firstSector = bytes[base + 2]
                let nameSlice   = bytes[(base + 3)..<(base + 19)]

                let rawName = nameSlice.prefix(while: { $0 != 0xA0 && $0 != 0x00 })
                if rawName.allSatisfy({ $0 == 0x01 }) { continue }

                let filename = petsciiToString(nameSlice)
                let blocks   = Int(bytes[base + 28]) | (Int(bytes[base + 29]) << 8)
                let fileData = extractFile(bytes: bytes, startTrack: firstTrack,
                                           startSector: firstSector, format: format)

                if !filename.isEmpty {
                    files.append(D64File(
                        filename:    filename,
                        rawFilename: Array(nameSlice.prefix(while: { $0 != 0xA0 && $0 != 0x00 })),
                        fileType:    fileType,
                        fileTypeByte: fileTypeByte,
                        blocks:      blocks,
                        track:       firstTrack,
                        sector:      firstSector,
                        rawData:     fileData
                    ))
                }
            }
        }

        return D64Disk(diskName: diskName, diskID: diskID,
                       freeBlocks: freeBlocks, files: files, format: format)
    }

    // MARK: - Extract File

    static func extractFile(bytes: [UInt8], startTrack: UInt8, startSector: UInt8,
                             format: DiskFormat = .d64) -> Data {
        var result = Data()
        var curTrack  = startTrack
        var curSector = startSector
        var visited = Set<String>()
        guard startTrack != 0 else { return result }

        while curTrack != 0 {
            let key = "\(curTrack):\(curSector)"
            if visited.contains(key) { break }
            visited.insert(key)
            guard curTrack <= UInt8(format.totalTracks) else { break }
            let s = offset(track: Int(curTrack), sector: Int(curSector), format: format)
            guard s + 256 <= bytes.count else { break }
            let nTrack  = bytes[s]
            let nSector = bytes[s + 1]
            if nTrack == 0 {
                let last = Int(nSector)
                if last >= 2 { result.append(contentsOf: bytes[(s + 2)..<(s + last + 1)]) }
            } else {
                result.append(contentsOf: bytes[(s + 2)..<(s + 256)])
            }
            curTrack  = nTrack
            curSector = nSector
        }
        return result
    }

    // MARK: - Free Sectors in BAM

    static func freeSectorsInBAM(bytes: inout [UInt8], startTrack: UInt8,
                                  startSector: UInt8, format: DiskFormat = .d64) {
        var curTrack  = startTrack
        var curSector = startSector
        var visited = Set<String>()

        while curTrack != 0 && curTrack <= UInt8(format.totalTracks) {
            let key = "\(curTrack):\(curSector)"
            if visited.contains(key) { break }
            visited.insert(key)
            let s = offset(track: Int(curTrack), sector: Int(curSector), format: format)
            guard s + 2 <= bytes.count else { break }
            let nTrack  = bytes[s]
            let nSector = bytes[s + 1]

            let t = Int(curTrack)
            let byteIdx = Int(curSector) / 8
            let bitIdx  = Int(curSector) % 8

            let (fcOff, bmOff) = bamOffsets(track: t, format: format)
            let maxFree = UInt8(trackSectors(track: t, format: format))
            if bytes[fcOff] < maxFree {
                bytes[fcOff] += 1
            }
            bytes[bmOff + byteIdx] |= (1 << bitIdx)

            curTrack  = nTrack
            curSector = nSector
        }
    }

    // MARK: - Inject File

    static func injectFile(into bytes: [UInt8], file: D64File, at targetIndex: Int? = nil) -> [UInt8]? {
        guard let format = DiskFormat.detect(size: bytes.count) else { return nil }
        var b = bytes
        let fileBytes = Array(file.rawData)
        var allocatedSectors: [(track: Int, sector: Int)] = []
        let needsSectors = !fileBytes.isEmpty && file.fileType != "DEL"

        if needsSectors {
            // Always compute from actual payload — the original block count
            // is preserved separately in the directory entry.
            let requiredSectors = max(1, (fileBytes.count + 253) / 254)

            // D71 has two system tracks: 18 (dir/BAM side 1) and 53 (BAM side 2)
            let systemTracks: Set<Int>
            switch format {
            case .d71: systemTracks = [18, 53]
            default:   systemTracks = [format.systemTrack]
            }

            outerLoop: for track in 1...format.totalTracks {
                if systemTracks.contains(track) { continue }
                let t = track
                let numSectors = trackSectors(track: t, format: format)

                let (fcOff, bmOff) = bamOffsets(track: t, format: format)
                if Int(b[fcOff]) == 0 { continue }

                for sec in 0..<numSectors {
                    let byteIdx = sec / 8
                    let bitIdx  = sec % 8
                    let isFree  = (b[bmOff + byteIdx] >> bitIdx) & 1 == 1
                    if isFree {
                        allocatedSectors.append((track: t, sector: sec))
                        b[bmOff + byteIdx] &= ~(1 << bitIdx)
                        if b[fcOff] > 0 { b[fcOff] -= 1 }
                        if allocatedSectors.count >= requiredSectors { break outerLoop }
                    }
                }
            }
            guard !allocatedSectors.isEmpty else { return nil }

            for (i, loc) in allocatedSectors.enumerated() {
                let s = offset(track: loc.track, sector: loc.sector, format: format)
                let isLast     = i == allocatedSectors.count - 1
                let chunkStart = i * 254
                let chunkEnd   = min(chunkStart + 254, fileBytes.count)
                if isLast {
                    b[s]     = 0x00
                    if chunkStart < fileBytes.count {
                        let chunk = Array(fileBytes[chunkStart..<chunkEnd])
                        b[s + 1] = UInt8(chunk.count + 1)
                        for (j, byte) in chunk.enumerated() { b[s + 2 + j] = byte }
                    } else {
                        b[s + 1] = 0x01
                    }
                } else {
                    let next = allocatedSectors[i + 1]
                    b[s]     = UInt8(next.track)
                    b[s + 1] = UInt8(next.sector)
                    if chunkStart < fileBytes.count {
                        let chunk = Array(fileBytes[chunkStart..<chunkEnd])
                        for (j, byte) in chunk.enumerated() { b[s + 2 + j] = byte }
                    }
                }
            }
        }

        // Find free directory slot
        var dirTrackNum  = UInt8(format.dirTrack)
        var dirSectorNum = UInt8(format.dirSector)
        var visited   = Set<String>()
        var insertBase:      Int? = nil
        var insertBaseIndex  = 0
        var lastSectorOff    = 0

        while dirTrackNum != 0 {
            let key = "\(dirTrackNum):\(dirSectorNum)"
            if visited.contains(key) { break }
            visited.insert(key)
            let sectorOff  = offset(track: Int(dirTrackNum), sector: Int(dirSectorNum), format: format)
            lastSectorOff  = sectorOff
            let nextDirTrack  = b[sectorOff]
            let nextDirSector = b[sectorOff + 1]
            for entry in 0..<8 {
                let base = sectorOff + 2 + (entry * 32)
                if b[base] == 0x00 {
                    if insertBase == nil { insertBase = base }
                } else {
                    if insertBase == nil { insertBaseIndex += 1 }
                }
            }
            dirTrackNum  = nextDirTrack
            dirSectorNum = nextDirSector
        }

        // If no free slot, allocate a new directory sector on the system track
        if insertBase == nil {
            let sysTrack   = format.systemTrack
            let sysSectors = trackSectors(track: sysTrack, format: format)

            // Collect all sectors already used on the system track
            var usedSectors = Set<Int>()
            switch format {
            case .d64:
                usedSectors.insert(0)  // T18/S0 = BAM
            case .d71:
                usedSectors.insert(0)  // T18/S0 = BAM side 1
            case .d81:
                usedSectors.insert(0)  // T40/S0 = header
                usedSectors.insert(1)  // T40/S1 = BAM1
                usedSectors.insert(2)  // T40/S2 = BAM2
            }
            // Walk the directory chain to find all used dir sectors
            var walkTrack  = UInt8(format.dirTrack)
            var walkSector = UInt8(format.dirSector)
            var walkVisited = Set<String>()
            while walkTrack != 0 && Int(walkTrack) == sysTrack {
                let wk = "\(walkTrack):\(walkSector)"
                if walkVisited.contains(wk) { break }
                walkVisited.insert(wk)
                usedSectors.insert(Int(walkSector))
                let wo = offset(track: Int(walkTrack), sector: Int(walkSector), format: format)
                walkTrack  = b[wo]
                walkSector = b[wo + 1]
            }

            // Find first unused sector on the system track
            var newSector: Int? = nil
            for s in 0..<sysSectors {
                if !usedSectors.contains(s) {
                    let sOff = offset(track: sysTrack, sector: s, format: format)
                    let isEmpty = (0..<256).allSatisfy { b[sOff + $0] == 0x00 }
                    if isEmpty {
                        newSector = s
                        break
                    }
                }
            }
            guard let ns = newSector else { return nil }

            // Link last directory sector to new one
            b[lastSectorOff]     = UInt8(sysTrack)
            b[lastSectorOff + 1] = UInt8(ns)

            // Initialize new directory sector
            let newOff = offset(track: sysTrack, sector: ns, format: format)
            b[newOff]     = 0x00
            b[newOff + 1] = 0xFF
            for i in 2..<256 { b[newOff + i] = 0x00 }

            insertBase = newOff + 2
        }

        guard let base = insertBase else { return nil }

        b[base]     = file.fileTypeByte
        b[base + 1] = needsSectors ? UInt8(allocatedSectors[0].track)   : file.track
        b[base + 2] = needsSectors ? UInt8(allocatedSectors[0].sector)  : file.sector

        if !file.rawFilename.isEmpty {
            for i in 0..<16 {
                b[base + 3 + i] = i < file.rawFilename.count ? file.rawFilename[i] : 0xA0
            }
        } else {
            let nameBytes = Array(file.filename.uppercased().utf8)
            for i in 0..<16 { b[base + 3 + i] = i < nameBytes.count ? nameBytes[i] : 0xA0 }
        }

        // Preserve the original directory block count when copying between disks;
        // fall back to allocated sector count for freshly imported files.
        let blockCount = needsSectors
            ? (file.blocks > 0 ? file.blocks : allocatedSectors.count)
            : file.blocks
        b[base + 28] = UInt8(blockCount & 0xFF)
        b[base + 29] = UInt8((blockCount >> 8) & 0xFF)

        if let target = targetIndex, insertBaseIndex != target {
            if let moved = moveFile(in: b, from: insertBaseIndex, to: target) { return moved }
        }
        return b
    }

    // MARK: - Move File

    static func moveFile(in bytes: [UInt8], from sourceIndex: Int, to destinationIndex: Int) -> [UInt8]? {
        guard let format = DiskFormat.detect(size: bytes.count) else { return nil }
        var b = bytes
        var allSlots:  [Int] = []
        var dirTrackNum   = UInt8(format.dirTrack)
        var dirSectorNum  = UInt8(format.dirSector)
        var visited    = Set<String>()

        while dirTrackNum != 0 {
            let key = "\(dirTrackNum):\(dirSectorNum)"
            if visited.contains(key) { break }
            visited.insert(key)
            let sectorOff  = offset(track: Int(dirTrackNum), sector: Int(dirSectorNum), format: format)
            let nTrack  = b[sectorOff]
            let nSector = b[sectorOff + 1]
            for entry in 0..<8 { allSlots.append(sectorOff + 2 + entry * 32) }
            dirTrackNum  = nTrack
            dirSectorNum = nSector
        }

        var validSlotIndices: [Int] = []
        for (i, slotBase) in allSlots.enumerated() {
            let entryType = b[slotBase]
            if entryType == 0x00 { continue }
            let nameBytes = b[(slotBase + 3)..<(slotBase + 19)]
            let isGarbage = nameBytes.prefix(while: { $0 != 0xA0 && $0 != 0x00 }).allSatisfy({ $0 == 0x01 })
            if !isGarbage { validSlotIndices.append(i) }
        }

        guard sourceIndex < validSlotIndices.count,
              destinationIndex < validSlotIndices.count,
              sourceIndex != destinationIndex else { return nil }

        func readEntry(_ slotBase: Int) -> [UInt8] {
            var entry = [UInt8](repeating: 0, count: 32)
            for j in 0..<32 {
                let a = slotBase + j
                if a % 256 == 0 || a % 256 == 1 { continue }
                entry[j] = b[a]
            }
            return entry
        }

        func writeEntry(_ entry: [UInt8], to slotBase: Int) {
            for j in 0..<32 {
                let a = slotBase + j
                if a % 256 == 0 || a % 256 == 1 { continue }
                b[a] = entry[j]
            }
        }

        var entries = validSlotIndices.map { readEntry(allSlots[$0]) }
        let src = entries.remove(at: sourceIndex)
        entries.insert(src, at: destinationIndex)
        for (i, slotIdx) in validSlotIndices.enumerated() { writeEntry(entries[i], to: allSlots[slotIdx]) }
        return b
    }

    // MARK: - Directory Index

    static func directoryIndex(in bytes: [UInt8], forFile file: D64File) -> Int? {
        guard let format = DiskFormat.detect(size: bytes.count) else { return nil }
        var dirTrackNum  = UInt8(format.dirTrack)
        var dirSectorNum = UInt8(format.dirSector)
        var visited   = Set<String>()
        var index     = 0

        while dirTrackNum != 0 {
            let key = "\(dirTrackNum):\(dirSectorNum)"
            if visited.contains(key) { break }
            visited.insert(key)
            let sectorOff  = offset(track: Int(dirTrackNum), sector: Int(dirSectorNum), format: format)
            let nTrack  = bytes[sectorOff]
            let nSector = bytes[sectorOff + 1]
            for entry in 0..<8 {
                let base = sectorOff + 2 + (entry * 32)
                if bytes[base] == 0x00 { continue }
                let fTrack  = bytes[base + 1]
                let fSector = bytes[base + 2]
                let name    = petsciiToString(bytes[(base + 3)..<(base + 19)])
                if name == file.filename && fTrack == file.track && fSector == file.sector { return index }
                index += 1
            }
            dirTrackNum  = nTrack
            dirSectorNum = nSector
        }
        return nil
    }

    // MARK: - Delete File

    static func deleteFile(from bytes: [UInt8], file: D64File) -> [UInt8]? {
        guard let format = DiskFormat.detect(size: bytes.count) else { return nil }
        var b = bytes
        var dirTrackNum  = UInt8(format.dirTrack)
        var dirSectorNum = UInt8(format.dirSector)
        var visited   = Set<String>()

        while dirTrackNum != 0 {
            let key = "\(dirTrackNum):\(dirSectorNum)"
            if visited.contains(key) { break }
            visited.insert(key)
            let sectorOff  = offset(track: Int(dirTrackNum), sector: Int(dirSectorNum), format: format)
            let nTrack  = b[sectorOff]
            let nSector = b[sectorOff + 1]
            for entry in 0..<8 {
                let base = sectorOff + 2 + (entry * 32)
                if b[base] == 0x00 { continue }
                let fTrack  = b[base + 1]
                let fSector = b[base + 2]
                let nameMatch: Bool
                if !file.rawFilename.isEmpty {
                    nameMatch = Array(b[(base + 3)..<(base + 3 + file.rawFilename.count)]) == file.rawFilename
                } else {
                    nameMatch = petsciiToString(b[(base + 3)..<(base + 19)]) == file.filename
                }
                if nameMatch && fTrack == file.track && fSector == file.sector {
                    b[base] = 0x00
                    if fTrack != 0 { freeSectorsInBAM(bytes: &b, startTrack: fTrack, startSector: fSector, format: format) }
                    return b
                }
            }
            dirTrackNum  = nTrack
            dirSectorNum = nSector
        }
        return nil
    }

    // MARK: - Delete File At Index

    static func deleteFileAtIndex(from bytes: [UInt8], index: Int) -> [UInt8]? {
        guard let format = DiskFormat.detect(size: bytes.count) else { return nil }
        var b = bytes
        var dirTrackNum  = UInt8(format.dirTrack)
        var dirSectorNum = UInt8(format.dirSector)
        var visited   = Set<String>()
        var current   = 0

        while dirTrackNum != 0 {
            let key = "\(dirTrackNum):\(dirSectorNum)"
            if visited.contains(key) { break }
            visited.insert(key)
            let sectorOff  = offset(track: Int(dirTrackNum), sector: Int(dirSectorNum), format: format)
            let nTrack  = b[sectorOff]
            let nSector = b[sectorOff + 1]
            for entry in 0..<8 {
                let base = sectorOff + 2 + (entry * 32)
                if b[base] == 0x00 { continue }
                let nameBytes = b[(base + 3)..<(base + 19)]
                let isGarbage = nameBytes.prefix(while: { $0 != 0xA0 && $0 != 0x00 }).allSatisfy({ $0 == 0x01 })
                if isGarbage { continue }
                if current == index {
                    let fTrack  = b[base + 1]
                    let fSector = b[base + 2]
                    b[base] = 0x00
                    if fTrack != 0 { freeSectorsInBAM(bytes: &b, startTrack: fTrack, startSector: fSector, format: format) }
                    return b
                }
                current += 1
            }
            dirTrackNum  = nTrack
            dirSectorNum = nSector
        }
        return nil
    }

    // MARK: - Rename File

    static func renameFile(in bytes: [UInt8], file: D64File, newName: String) -> [UInt8]? {
        guard let format = DiskFormat.detect(size: bytes.count) else { return nil }
        var b = bytes
        var dirTrackNum  = UInt8(format.dirTrack)
        var dirSectorNum = UInt8(format.dirSector)
        var visited   = Set<String>()

        while dirTrackNum != 0 {
            let key = "\(dirTrackNum):\(dirSectorNum)"
            if visited.contains(key) { break }
            visited.insert(key)
            let sectorOff  = offset(track: Int(dirTrackNum), sector: Int(dirSectorNum), format: format)
            let nTrack  = b[sectorOff]
            let nSector = b[sectorOff + 1]
            for entry in 0..<8 {
                let base = sectorOff + 2 + (entry * 32)
                if b[base] == 0x00 { continue }
                let fTrack  = b[base + 1]
                let fSector = b[base + 2]
                let name    = petsciiToString(b[(base + 3)..<(base + 19)])
                if name == file.filename && fTrack == file.track && fSector == file.sector {
                    let newBytes = Array(newName.uppercased().utf8)
                    for i in 0..<16 { b[base + 3 + i] = i < newBytes.count ? newBytes[i] : 0xA0 }
                    return b
                }
            }
            dirTrackNum  = nTrack
            dirSectorNum = nSector
        }
        return nil
    }

    // MARK: - Rename Disk

    static func renameDisk(in bytes: [UInt8], name: String, id: String) -> [UInt8]? {
        guard let format = DiskFormat.detect(size: bytes.count) else { return nil }
        var b = bytes
        let nameBytes = Array(name.uppercased().utf8)
        let idBytes   = Array(id.uppercased().utf8)

        switch format {
        case .d64, .d71:
            let bam = offset(track: 18, sector: 0, format: format)
            for i in 0..<16 { b[bam + 0x90 + i] = i < nameBytes.count ? nameBytes[i] : 0xA0 }
            for i in 0..<2  { b[bam + 0xA2 + i] = i < idBytes.count   ? idBytes[i]   : 0x30 }
        case .d81:
            let header = offset(track: 40, sector: 0, format: .d81)
            for i in 0..<16 { b[header + 0x04 + i] = i < nameBytes.count ? nameBytes[i] : 0xA0 }
            for i in 0..<2  { b[header + 0x16 + i] = i < idBytes.count   ? idBytes[i]   : 0x30 }
        }
        return b
    }

    // MARK: - Write File Data Back to Disk Image

    /// Overwrites the data sectors of an existing file on disk with new content.
    /// Walks the file's sector chain and patches each sector with the corresponding
    /// chunk of newFileData. Does NOT change file size, BAM, or directory entry.
    static func writeBytesToFile(in bytes: [UInt8],
                                  startTrack: UInt8, startSector: UInt8,
                                  newFileData: [UInt8],
                                  format: DiskFormat) -> [UInt8]? {
        guard startTrack != 0 else { return nil }
        var b = bytes
        var curTrack  = startTrack
        var curSector = startSector
        var visited   = Set<String>()
        var dataOffset = 0

        while curTrack != 0 {
            let key = "\(curTrack):\(curSector)"
            if visited.contains(key) { break }
            visited.insert(key)
            guard curTrack <= UInt8(format.totalTracks) else { break }
            let s = offset(track: Int(curTrack), sector: Int(curSector), format: format)
            guard s + 256 <= b.count else { break }

            let nTrack  = b[s]
            let nSector = b[s + 1]

            if nTrack == 0 {
                // Last sector — nSector indicates how many bytes are used (including the pointer byte)
                let usableBytes = max(0, Int(nSector) - 1)
                let chunkEnd = min(dataOffset + usableBytes, newFileData.count)
                if dataOffset < chunkEnd {
                    let chunk = Array(newFileData[dataOffset..<chunkEnd])
                    for (j, byte) in chunk.enumerated() {
                        b[s + 2 + j] = byte
                    }
                }
                dataOffset = chunkEnd
            } else {
                // Full sector — 254 data bytes
                let chunkEnd = min(dataOffset + 254, newFileData.count)
                if dataOffset < chunkEnd {
                    let chunk = Array(newFileData[dataOffset..<chunkEnd])
                    for (j, byte) in chunk.enumerated() {
                        b[s + 2 + j] = byte
                    }
                }
                dataOffset = chunkEnd
            }

            curTrack  = nTrack
            curSector = nSector
        }
        return b
    }

} // end D64Parser
