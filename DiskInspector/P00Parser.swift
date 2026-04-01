import Foundation

// MARK: - P00Parser
// Parses PC64 container files (.P00, .S00, .U00, .R00 and numbered variants).
//
// Header layout (26 bytes total):
//   Bytes  0– 7: magic "C64File\0"
//   Bytes  8–23: C64 filename (16 bytes, null-padded)
//   Byte    24: 0x00
//   Byte    25: REL record size (0 for non-REL files)
//   Bytes 26– N: raw file data

struct P00Parser {

    static func isMagic(_ data: Data) -> Bool {
        guard data.count >= 8 else { return false }
        return data.prefix(8) == Data("C64File\0".utf8)
    }

    /// Returns (c64Filename, fileType, rawData) parsed from a PC64 container.
    /// `ext` is the file extension (e.g. "p00", "s01") used to derive the C64 file type.
    static func parse(_ data: Data, ext: String) -> (filename: String, fileType: String, rawData: Data)? {
        guard isMagic(data), data.count > 26 else { return nil }

        // C64 filename: bytes 8–23, null-terminated, PETSCII $20–$5F
        var name = ""
        for b in data[8..<24] {
            if b == 0x00 { break }
            if b >= 0x20 && b <= 0x5F {
                name.append(Character(UnicodeScalar(b)))
            }
        }
        if name.trimmingCharacters(in: .whitespaces).isEmpty { name = "UNKNOWN" }

        // File type from the first character of the extension
        let fileType: String
        switch ext.prefix(1).lowercased() {
        case "p": fileType = "PRG"
        case "s": fileType = "SEQ"
        case "u": fileType = "USR"
        case "r": fileType = "REL"
        default:  fileType = "PRG"
        }

        let rawData = data.subdata(in: 26..<data.count)
        return (name, fileType, rawData)
    }

    /// Present a P00/S00 file as a read-only D64Disk with one entry,
    /// so it can be opened and viewed like a T64.
    static func parseAsDisk(data: Data) -> D64Disk? {
        guard let (filename, fileType, rawData) = parse(data, ext: "p00") else { return nil }

        let blocks = (rawData.count + 253) / 254
        let file = D64File(
            filename:     filename,
            rawFilename:  Array(filename.utf8.prefix(16)),
            fileType:     fileType,
            fileTypeByte: fileType == "PRG" ? 0x82 : fileType == "SEQ" ? 0x81 : fileType == "USR" ? 0x83 : 0x84,
            blocks:       blocks,
            track:        0,
            sector:       0,
            rawData:      rawData
        )
        return D64Disk(diskName: filename, diskID: "P00",
                       freeBlocks: 0, files: [file], format: .t64)
    }
}
