import Foundation

// MARK: - GCR Decoder
//
// Decodes raw GCR (Group Code Recording) byte streams from G64/NIB disk images
// back into standard CBM sector data.
//
// CBM GCR encodes 4 data bytes into 5 GCR bytes (40 bits → 8 x 5-bit symbols).
// Sync marks are 5 or more consecutive 0xFF bytes (guaranteed not to appear in
// valid encoded data — no valid GCR symbol is 0x1F = 11111b).
//
// Track layout per sector:
//   [≥5 sync bytes] [10 GCR bytes = header block] [gap] [≥5 sync bytes] [325 GCR bytes = data block]
//
// Header block (8 decoded bytes):
//   [0] 0x08 (block ID)   [1] checksum (XOR of [2..5])
//   [2] sector#           [3] track#
//   [4] disk ID lo        [5] disk ID hi
//   [6] 0x0F              [7] 0x0F
//
// Data block (260 decoded bytes):
//   [0] 0x07 (block ID)   [1..256] 256 bytes of sector data
//   [257] checksum (XOR of [1..256])   [258..259] 0x00 0x00

struct GCRDecoder {

    // MARK: - Decode table: 5-bit GCR symbol → 4-bit nibble (0xFF = invalid)
    private static let decodeTable: [UInt8] = {
        var t = [UInt8](repeating: 0xFF, count: 32)
        t[0x09] = 0x8;  t[0x0A] = 0x0;  t[0x0B] = 0x1
        t[0x0D] = 0xC;  t[0x0E] = 0x4;  t[0x0F] = 0x5
        t[0x12] = 0x2;  t[0x13] = 0x3;  t[0x15] = 0xF
        t[0x16] = 0x6;  t[0x17] = 0x7;  t[0x19] = 0x9
        t[0x1A] = 0xA;  t[0x1B] = 0xB;  t[0x1D] = 0xD
        t[0x1E] = 0xE
        return t
    }()

    // MARK: - Decoded sector

    struct DecodedSector {
        let track:    UInt8
        let sector:   UInt8
        let data:     [UInt8]   // exactly 256 bytes
        let headerOK: Bool
        let dataOK:   Bool
    }

    // MARK: - Track decode result

    struct TrackResult {
        let sectors:      [DecodedSector]
        let syncCount:    Int
        let headerErrors: Int
        let dataErrors:   Int
    }

    // MARK: - Core: decode 5 GCR bytes → 4 decoded bytes

    /// Returns (4 decoded bytes, allSymbolsValid).
    private static func decodeGroup(_ bytes: [UInt8], at pos: Int) -> ([UInt8], Bool) {
        guard pos + 5 <= bytes.count else { return ([0,0,0,0], false) }
        // Pack 5 bytes into 40 bits, MSB first
        var bits: UInt64 = 0
        for i in 0..<5 { bits = (bits << 8) | UInt64(bytes[pos + i]) }

        var nibbles = [UInt8](repeating: 0, count: 8)
        var valid = true
        for i in 0..<8 {
            let sym = Int((bits >> UInt64(35 - i * 5)) & 0x1F)
            let nib = decodeTable[sym]
            if nib == 0xFF { valid = false }
            nibbles[i] = nib & 0x0F
        }
        return ([
            (nibbles[0] << 4) | nibbles[1],
            (nibbles[2] << 4) | nibbles[3],
            (nibbles[4] << 4) | nibbles[5],
            (nibbles[6] << 4) | nibbles[7]
        ], valid)
    }

    /// Decode `groupCount` consecutive 5-byte GCR groups starting at `pos`.
    private static func decodeGroups(_ bytes: [UInt8], at pos: Int, count groupCount: Int) -> ([UInt8], Bool) {
        var result = [UInt8]()
        result.reserveCapacity(groupCount * 4)
        var valid = true
        for g in 0..<groupCount {
            let (d, ok) = decodeGroup(bytes, at: pos + g * 5)
            result.append(contentsOf: d)
            if !ok { valid = false }
        }
        return (result, valid)
    }

    // MARK: - Track decode

    /// Scan raw GCR track bytes and return all decodeable sectors.
    static func decodeTrack(_ trackBytes: [UInt8]) -> TrackResult {
        var sectors      = [DecodedSector]()
        var syncCount    = 0
        var headerErrors = 0
        var dataErrors   = 0
        var i            = 0
        let n            = trackBytes.count

        while i < n {
            // ── Find sync mark: ≥2 consecutive 0xFF bytes ──
            // Threshold is 2 (not 5) to handle partial wrap-around syncs at the start
            // of a circular track buffer, where the leading bytes of a ≥5-byte sync
            // are stored at the end of the buffer and only the tail is visible here.
            var syncLen = 0
            while i < n && trackBytes[i] == 0xFF { syncLen += 1; i += 1 }
            if syncLen < 2 {
                if syncLen == 0 { i += 1 }   // no 0xFF here — advance
                continue
            }
            syncCount += 1

            // ── Try to read header block: 10 GCR bytes → 8 decoded bytes ──
            guard i + 10 <= n else { break }
            let (hdr, hdrGCROK) = decodeGroups(trackBytes, at: i, count: 2)

            guard hdr[0] == 0x08 else {
                // Not a header marker — keep scanning from here
                continue
            }

            let expectedCheck = hdr[2] ^ hdr[3] ^ hdr[4] ^ hdr[5]
            let headerOK      = hdrGCROK && (hdr[1] == expectedCheck)
            if !headerOK { headerErrors += 1 }

            let sectorNum = hdr[2]
            let trackNum  = hdr[3]
            i += 10

            // ── Skip gap, find data block sync ──
            while i < n && trackBytes[i] != 0xFF { i += 1 }
            var sync2Len = 0
            while i < n && trackBytes[i] == 0xFF { sync2Len += 1; i += 1 }
            if sync2Len >= 5 { syncCount += 1 }

            // ── Read data block: 325 GCR bytes → 260 decoded bytes ──
            guard i + 325 <= n else { break }
            let (dat, datGCROK) = decodeGroups(trackBytes, at: i, count: 65)
            i += 325

            guard dat[0] == 0x07 else {
                dataErrors += 1
                continue
            }

            let sectorData    = Array(dat[1..<257])
            let calcDataCheck = sectorData.reduce(0 as UInt8, ^)
            let dataOK        = datGCROK && (dat[257] == calcDataCheck)
            if !dataOK { dataErrors += 1 }

            sectors.append(DecodedSector(
                track:    trackNum,
                sector:   sectorNum,
                data:     sectorData,
                headerOK: headerOK,
                dataOK:   dataOK
            ))
        }

        return TrackResult(
            sectors:      sectors,
            syncCount:    syncCount,
            headerErrors: headerErrors,
            dataErrors:   dataErrors
        )
    }

    // MARK: - Virtual D64 construction

    /// Fill a 174848-byte D64 image buffer with decoded sector data.
    /// Sectors outside the standard 1-35 track range are silently dropped.
    static func buildVirtualD64(sectors: [DecodedSector]) -> Data {
        var bytes = [UInt8](repeating: 0x00, count: 174848)
        for s in sectors {
            let t   = Int(s.track)
            let sec = Int(s.sector)
            guard t >= 1, t <= 35 else { continue }
            let maxSec = D64Parser.trackSectors(track: t, format: .d64)
            guard sec < maxSec else { continue }
            let off = D64Parser.offset(track: t, sector: sec, format: .d64)
            guard off + 256 <= bytes.count else { continue }
            bytes.replaceSubrange(off..<(off + 256), with: s.data)
        }
        return Data(bytes)
    }
}
