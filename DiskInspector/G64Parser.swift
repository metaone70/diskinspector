import Foundation

// MARK: - G64Parser
// Parses VICE G64 raw GCR disk images — read-only.
//
// Header layout:
//   Bytes  0–7:  "GCR-1541" signature
//   Byte   8:    Version (0x00)
//   Byte   9:    Number of half-track entries (84 for a full 35-track disk with half-tracks)
//   Bytes 10–11: Maximum track data size in bytes (LE 16-bit)
//   Bytes 12…:   Track offset table: 4 bytes per entry (LE 32-bit, 0 = no data)
//                followed by speed/density table (also 4 bytes per entry, not used here)
//
// Each non-zero track entry in the file:
//   [offset+0..1]: track data size (LE 16-bit)
//   [offset+2…]:   raw GCR bytes (size bytes)

struct G64Parser {

    static let magicBytes = Array("GCR-1541".utf8)

    static func isMagic(_ data: Data) -> Bool {
        guard data.count >= 8 else { return false }
        return data.prefix(8).elementsEqual(magicBytes)
    }

    /// Decode all full tracks to a 174848-byte virtual D64 image.
    /// Used by Validate, BAM, and VICE launch for G64 files.
    static func buildVirtualD64(from data: Data) -> Data? {
        guard isMagic(data), data.count >= 12 else { return nil }
        let bytes = [UInt8](data)
        let numEntries = Int(bytes[9])
        var allSectors = [GCRDecoder.DecodedSector]()
        for ti in 0..<numEntries {
            let offsetBase = 12 + ti * 4
            guard offsetBase + 4 <= bytes.count else { break }
            let trackOffset = Int(bytes[offsetBase])
                | (Int(bytes[offsetBase + 1]) << 8)
                | (Int(bytes[offsetBase + 2]) << 16)
                | (Int(bytes[offsetBase + 3]) << 24)
            guard trackOffset != 0 else { continue }
            guard trackOffset + 2 <= bytes.count else { continue }
            let trackSize = Int(bytes[trackOffset]) | (Int(bytes[trackOffset + 1]) << 8)
            guard trackSize > 0, trackOffset + 2 + trackSize <= bytes.count else { continue }
            let isHalfTrack = (ti % 2) == 1
            if !isHalfTrack {
                let trackData = Array(bytes[(trackOffset + 2)..<(trackOffset + 2 + trackSize)])
                allSectors.append(contentsOf: GCRDecoder.decodeTrack(trackData).sectors)
            }
        }
        return GCRDecoder.buildVirtualD64(sectors: allSectors)
    }

    static func parse(data: Data) -> D64Disk? {
        guard isMagic(data), data.count >= 12 else { return nil }
        let bytes = [UInt8](data)

        let numEntries   = Int(bytes[9])              // half-track slots
        // Bytes 10-11: max track size (informational — we read actual track sizes below)

        var allSectors   = [GCRDecoder.DecodedSector]()
        var trackInfos   = [GCRTrackInfo]()

        for ti in 0..<numEntries {
            let offsetBase = 12 + ti * 4
            guard offsetBase + 4 <= bytes.count else { break }

            let trackOffset = Int(bytes[offsetBase])
                | (Int(bytes[offsetBase + 1]) << 8)
                | (Int(bytes[offsetBase + 2]) << 16)
                | (Int(bytes[offsetBase + 3]) << 24)

            // G64 stores full tracks at even indices (0, 2, 4…) and half-tracks at odd indices.
            let isHalfTrack  = (ti % 2) == 1
            let trackNumber  = Double(ti / 2) + 1.0 + (isHalfTrack ? 0.5 : 0.0)
            let fullTrackNum = ti / 2 + 1
            let expected     = (!isHalfTrack && fullTrackNum >= 1 && fullTrackNum <= 35)
                               ? D64Parser.trackSectors(track: fullTrackNum, format: .d64) : 0

            if trackOffset == 0 {
                // Null track — no data written
                trackInfos.append(GCRTrackInfo(
                    trackNumber:     trackNumber,
                    rawLength:       0,
                    sectorsFound:    0,
                    sectorsExpected: expected,
                    headerErrors:    0,
                    dataErrors:      0,
                    syncCount:       0,
                    hasData:         false
                ))
                continue
            }

            guard trackOffset + 2 <= bytes.count else { continue }
            let trackSize = Int(bytes[trackOffset]) | (Int(bytes[trackOffset + 1]) << 8)
            guard trackSize > 0, trackOffset + 2 + trackSize <= bytes.count else { continue }

            let trackData = Array(bytes[(trackOffset + 2)..<(trackOffset + 2 + trackSize)])
            let result    = GCRDecoder.decodeTrack(trackData)

            // Only use full tracks for the virtual D64 reconstruction
            if !isHalfTrack {
                allSectors.append(contentsOf: result.sectors)
            }

            trackInfos.append(GCRTrackInfo(
                trackNumber:     trackNumber,
                rawLength:       trackSize,
                sectorsFound:    result.sectors.count,
                sectorsExpected: expected,
                headerErrors:    result.headerErrors,
                dataErrors:      result.dataErrors,
                syncCount:       result.syncCount,
                hasData:         true
            ))
        }

        // Build a virtual D64 from decoded sectors and parse the directory from it
        let virtualD64 = GCRDecoder.buildVirtualD64(sectors: allSectors)
        guard let baseDisk = D64Parser.parse(data: virtualD64, formatHint: .d64) else { return nil }

        return D64Disk(
            diskName:   baseDisk.diskName.isEmpty ? "G64 DISK" : baseDisk.diskName,
            diskID:     baseDisk.diskID,
            freeBlocks: baseDisk.freeBlocks,
            files:      baseDisk.files,
            format:     .g64,
            rawTracks:  trackInfos
        )
    }
}
