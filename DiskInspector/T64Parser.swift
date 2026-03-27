import Foundation

// MARK: - T64Parser
// Parses C64S tape archive files (.t64) — read-only.
// Format reference: https://vice-emu.sourceforge.io/vice_17.html#SEC387
//
// Header layout (64 bytes):
//   Bytes  0–31: signature ("C64S tape file\r\n" or "C64 tape image file\r\n")
//   Bytes 32–33: tape version (LE)
//   Bytes 34–35: max directory entries (LE) — MAY BE WRONG/ZERO in old files
//   Bytes 36–37: used directory entries (LE) — more reliable
//   Bytes 40–63: tape name (24 bytes PETSCII, 0x20-padded)
//
// Directory entries start at 0x40, 32 bytes each:
//   +00: C64s entry type (1 = normal C64 file)
//   +01: CBM file type byte (0x82=PRG, 0x81=SEQ, etc.)
//   +02–03: start/load address (LE)
//   +04–05: end address (LE)
//   +08–0B: data offset in file (LE 32-bit)
//   +0E–1D: filename (16 bytes PETSCII, 0x20-padded)

struct T64Parser {

    static func isMagic(_ data: Data) -> Bool {
        guard data.count >= 20 else { return false }
        let header = String(bytes: data.prefix(20), encoding: .isoLatin1) ?? ""
        return header.hasPrefix("C64S tape file") || header.hasPrefix("C64 tape image file")
    }

    static func parse(data: Data) -> D64Disk? {
        guard isMagic(data), data.count >= 64 else { return nil }
        let bytes = [UInt8](data)

        // Determine how many directory entries to scan.
        // Old C64S files often set maxEntries=0 but usedEntries is correct.
        let maxEntries  = Int(bytes[0x22]) | (Int(bytes[0x23]) << 8)
        let usedEntries = Int(bytes[0x24]) | (Int(bytes[0x25]) << 8)
        // If both are zero (badly formatted T64), scan all available 32-byte slots
        let availableSlots = (bytes.count - 0x40) / 32
        let entryCount = usedEntries > 0 ? usedEntries
                       : maxEntries  > 0 ? maxEntries
                       : min(availableSlots, 256)

        // Tape name at 0x28 (24 bytes, space-padded)
        let tapeNameSlice = ArraySlice(bytes[0x28..<min(0x40, bytes.count)])
        let tapeName = D64Parser.petsciiToString(tapeNameSlice).trimmingCharacters(in: .whitespaces)

        var files: [D64File] = []

        for i in 0..<entryCount {
            let base = 0x40 + i * 32
            guard base + 32 <= bytes.count else { break }

            let entryType = bytes[base]
            // Type 0 = free slot (stop scanning, many T64s have no trailing free slots)
            // Type 1 = normal C64 file (standard)
            // Some buggy T64s store the CBM file type byte here instead of 1
            guard entryType != 0 else { continue }

            let fileTypeByte = bytes[base + 1]
            let startLo      = bytes[base + 2]
            let startHi      = bytes[base + 3]
            let startAddr    = Int(startLo) | (Int(startHi) << 8)
            let endAddr      = Int(bytes[base + 4]) | (Int(bytes[base + 5]) << 8)
            let dataOffset   = Int(bytes[base + 8])
                             | (Int(bytes[base + 9])  << 8)
                             | (Int(bytes[base + 10]) << 16)
                             | (Int(bytes[base + 11]) << 24)

            let nameSlice    = ArraySlice(bytes[(base + 16)..<(base + 32)])
            let filename     = D64Parser.petsciiToString(nameSlice).trimmingCharacters(in: .whitespaces)
            guard !filename.isEmpty else { continue }
            // T64 pads names with 0x20 (space), not 0xA0 — strip trailing spaces too
            var rawFilenameBytes = Array(nameSlice.prefix(while: { $0 != 0xA0 && $0 != 0x00 }))
            while rawFilenameBytes.last == 0x20 { rawFilenameBytes.removeLast() }
            let rawFilename  = rawFilenameBytes

            var dataLen = endAddr > startAddr ? endAddr - startAddr : 0
            // Workaround for buggy T64 files (e.g. from CONV64) that set endAddr to $C3C6
            if dataOffset + dataLen > bytes.count {
                dataLen = bytes.count - dataOffset
            }
            guard dataOffset > 0, dataLen >= 0 else { continue }

            // Build PRG-style rawData: [lo(load), hi(load)] + payload
            var rawData = Data()
            rawData.append(startLo)
            rawData.append(startHi)
            if dataLen > 0 {
                rawData.append(contentsOf: bytes[dataOffset..<(dataOffset + dataLen)])
            }

            _ = startAddr  // captured in rawData header bytes
            let blocks      = max(1, (rawData.count + 253) / 254)
            let fileTypeStr = cbmFileTypeString(fileTypeByte)

            files.append(D64File(
                filename:     filename,
                rawFilename:  rawFilename,
                fileType:     fileTypeStr,
                fileTypeByte: fileTypeByte,
                blocks:       blocks,
                track:        0,
                sector:       0,
                rawData:      rawData
            ))
        }

        return D64Disk(
            diskName:   tapeName.isEmpty ? "T64 ARCHIVE" : tapeName,
            diskID:     "T64",
            freeBlocks: 0,
            files:      files,
            format:     .t64
        )
    }

    // CBM file type byte: lower 3 bits = type, upper bits = flags (closed, locked)
    private static func cbmFileTypeString(_ byte: UInt8) -> String {
        switch byte & 0x07 {
        case 0x00: return "DEL"
        case 0x01: return "SEQ"
        case 0x02: return "PRG"
        case 0x03: return "USR"
        case 0x04: return "REL"
        default:   return "PRG"
        }
    }
}
