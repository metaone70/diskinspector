import Foundation

// MARK: - LNXParser
// Parses Lynx archive files (.lnx) — read-only.
//
// The Lynx archive format is a sequence of 254-byte blocks.
// The first block (Block 0) contains a BASIC stub as well as the
// start of a PETSCII text directory. The directory continues across
// multiple blocks if necessary, delimited by 0x0D (CR).
// Each file then occupies its respective number of 254-byte blocks.

struct LNXParser {

    static func parse(data: Data) -> D64Disk? {
        guard data.count >= 254 else { return nil }
        let bytes = [UInt8](data)

        // Read the directory (in PETSCII text) which starts within the first blocks.
        // We scan until we parse the number of expected directory entries.
        var dirTextBytes: [UInt8] = []
        var blockIdx = 0
        var foundSignature = false
        var numEntries = 0
        var expectedDirBlocks = 1

        // Extract tokens separated by 0x0D from the first few blocks
        var tokens: [String] = []
        var currentToken: [UInt8] = []

        func extractTokens(from blockSize: Int) {
            let limit = min(bytes.count, blockSize)
            for i in 0..<limit {
                if bytes[i] == 0x0D {
                    let petscii = D64Parser.petsciiToString(ArraySlice(currentToken))
                    tokens.append(petscii)
                    currentToken.removeAll()
                } else {
                    // Skip BASIC stub padding (spaces and 0x00) before the signature
                    if !foundSignature && currentToken.isEmpty && (bytes[i] == 0x20 || bytes[i] == 0x00) {
                        continue
                    }
                    currentToken.append(bytes[i])
                }
            }
        }

        // We initially extract tokens from the first block
        var scanLimit = 254
        var extractedLen = 0
        
        // Loop until we extract all the directory tokens
        while extractedLen < bytes.count {
            let petscii = D64Parser.petsciiToString(ArraySlice([bytes[extractedLen]]))
            if petscii == "\r" {
                // If we match 0x0D directly in loop, we can just split tokens
                break
            }
            extractedLen += 1
        }
        
        // Since LNX directory is somewhat tricky to parse block-by-block,
        // we can just extract ALL 0x0D-separated tokens from the file up to a reasonable limit,
        // then parse the directory structure, and calculate the data offset.

        var allTokens: [String] = []
        var allTokenBytes: [[UInt8]] = []  // raw PETSCII bytes for each token (preserves original encoding)
        var cur: [UInt8] = []
        for i in 0..<min(bytes.count, 65536) {
            if bytes[i] == 0x0D {
                allTokens.append(D64Parser.petsciiToString(ArraySlice(cur)))
                allTokenBytes.append(cur)
                cur = []
            } else {
                cur.append(bytes[i])
            }
        }
        
        // Parse the tokens. The first token usually contains the BASIC stub (ignored) ending with the number of blocks,
        // OR the BASIC stub is skipped and the first "real" token ends with the signature.
        // E.g., "... 1  *LYNX XV  BY WILL CORLEY" -> token 1
        // " 4 " -> token 2 (number of entries)
        var entryStartIdx = -1
        for (i, token) in allTokens.enumerated() {
            if token.contains("*LYNX") || token.contains("LYNX") {
                // The next token should be the number of entries
                if i + 1 < allTokens.count {
                    if let n = Int(allTokens[i + 1].trimmingCharacters(in: .whitespaces)) {
                        numEntries = n
                        entryStartIdx = i + 2
                        
                        // Try to extract directory blocks from this token
                        let numStr = token.components(separatedBy: " ").first(where: { !$0.isEmpty }) ?? "1"
                        expectedDirBlocks = Int(numStr) ?? 1
                    }
                }
                break
            }
        }

        guard entryStartIdx != -1, numEntries > 0 else { return nil }

        var files: [D64File] = []
        let dataStartOffset = expectedDirBlocks * 254
        var currentDataOffset = dataStartOffset

        var tIdx = entryStartIdx
        for _ in 0..<numEntries {
            guard tIdx + 3 < allTokens.count else { break }
            let filename = allTokens[tIdx].trimmingCharacters(in: .whitespaces)
            let blocksStr = allTokens[tIdx + 1].trimmingCharacters(in: .whitespaces)
            let typeStr = allTokens[tIdx + 2].trimmingCharacters(in: .whitespaces)
            let lastByteStr = allTokens[tIdx + 3].trimmingCharacters(in: .whitespaces)
            tIdx += 4

            let blocks = Int(blocksStr) ?? 0
            let typeCode = parseLNXType(typeStr)

            let dataLen = blocks * 254
            var rawData = Data()
            if currentDataOffset + dataLen <= bytes.count {
                rawData.append(contentsOf: bytes[currentDataOffset..<(currentDataOffset + dataLen)])
            } else if currentDataOffset < bytes.count {
                rawData.append(contentsOf: bytes[currentDataOffset..<bytes.count])
            }
            
            // To make it a valid PRG, we normally prepend a load address if it's a PRG,
            // but LNX doesn't explicitly store it in the directory; the files in LNX *are* standard files,
            // so PRG files already have their 2-byte load address inside their data block!
            // We just extract the raw data as-is.

            // Use the original raw PETSCII bytes for rawFilename so that special PETSCII
            // characters (like graphics symbols) survive the copy-to-disk operation intact.
            // Converting to String and back via .utf8 would turn single PETSCII bytes into
            // multi-byte UTF-8 sequences, corrupting the filename when written to D64.
            var rawFn = allTokenBytes[tIdx - 4]
            while rawFn.first == 0x20 { rawFn.removeFirst() }
            while rawFn.last == 0x20 || rawFn.last == 0x00 { rawFn.removeLast() }

            files.append(D64File(
                filename: filename,
                rawFilename: rawFn,
                fileType: typeCode.str,
                fileTypeByte: typeCode.byte,
                blocks: blocks,
                track: 0,
                sector: 0,
                rawData: rawData
            ))

            currentDataOffset += dataLen
        }

        return D64Disk(
            diskName: "LNX ARCHIVE",
            diskID: "LNX",
            freeBlocks: 0,
            files: files,
            format: .lnx
        )
    }

    private static func parseLNXType(_ typeStr: String) -> (str: String, byte: UInt8) {
        let t = typeStr.uppercased()
        if t.hasPrefix("P") { return ("PRG", 0x82) }
        if t.hasPrefix("S") { return ("SEQ", 0x81) }
        if t.hasPrefix("R") { return ("REL", 0x84) }
        if t.hasPrefix("U") { return ("USR", 0x83) }
        if t.hasPrefix("D") { return ("DEL", 0x80) }
        return ("PRG", 0x82)
    }
}
