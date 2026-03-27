import Foundation

// MARK: - NIBParser
// Parses NibTools raw GCR disk images — read-only.
//
// Two variants:
//
// Plain NIB:  No header.  35 tracks × 8192 bytes = 286720 bytes total.
//             Track N (0-indexed) starts at N * 8192.
//
// MNIB:       256-byte header starting with "MNIB-1541-RAW".
//             After the header: N tracks × 8192 bytes (N derived from file size).
//             286976 bytes = 256 + 35 × 8192  (plain copy, 35 full tracks)
//             336128 bytes = 256 + 41 × 8192  (extended, tracks 1–41)
//             In the 41-track variant only the first 35 integer tracks are used.
//
// Unused space at the end of each 8192-byte track block is padded with 0xFF.

struct NIBParser {

    private static let mnibMagic = Array("MNIB-1541-RAW".utf8)

    // MARK: - Magic check (called from D64Document to detect MNIB files)
    static func isMNIBMagic(_ data: Data) -> Bool {
        guard data.count >= mnibMagic.count else { return false }
        return data.prefix(mnibMagic.count).elementsEqual(mnibMagic)
    }

    // MARK: - Virtual D64

    /// Decode all tracks to a 174848-byte virtual D64 image.
    /// Used by Validate, BAM, and VICE launch for NIB/MNIB files.
    static func buildVirtualD64(from data: Data) -> Data? {
        let bytes = [UInt8](data)
        let headerSize: Int
        let trackCount: Int
        if isMNIBMagic(data) {
            headerSize = 256
            let trackBytes = data.count - headerSize
            guard trackBytes > 0, trackBytes % 8192 == 0 else { return nil }
            trackCount = trackBytes / 8192
        } else if data.count == 286720 {
            headerSize = 0
            trackCount = 35
        } else { return nil }
        var allSectors = [GCRDecoder.DecodedSector]()
        for ti in 0..<min(trackCount, 35) {
            let offset = headerSize + ti * 8192
            guard offset + 8192 <= bytes.count else { break }
            let trackData = Array(bytes[offset..<(offset + 8192)])
            allSectors.append(contentsOf: GCRDecoder.decodeTrack(trackData).sectors)
        }
        return GCRDecoder.buildVirtualD64(sectors: allSectors)
    }

    // MARK: - Parse

    static func parse(data: Data) -> D64Disk? {
        let bytes = [UInt8](data)

        // Determine header size and track count
        let headerSize: Int
        let trackCount: Int

        if isMNIBMagic(data) {
            // MNIB: 256-byte header + N × 8192 track blocks
            headerSize = 256
            let trackBytes = data.count - headerSize
            guard trackBytes > 0, trackBytes % 8192 == 0 else { return nil }
            trackCount = trackBytes / 8192
        } else if data.count == 286720 {
            // Plain NIB: no header, exactly 35 tracks
            headerSize = 0
            trackCount = 35
        } else {
            return nil
        }

        var allSectors = [GCRDecoder.DecodedSector]()
        var trackInfos = [GCRTrackInfo]()

        // Process up to 35 full tracks (ignore extra copy-protection tracks beyond 35)
        let maxTracks = min(trackCount, 35)

        for ti in 0..<maxTracks {
            let trackNum = ti + 1
            let offset   = headerSize + ti * 8192
            guard offset + 8192 <= bytes.count else { break }
            let trackData = Array(bytes[offset..<(offset + 8192)])
            let result    = GCRDecoder.decodeTrack(trackData)

            allSectors.append(contentsOf: result.sectors)

            let expected = D64Parser.trackSectors(track: trackNum, format: .d64)
            trackInfos.append(GCRTrackInfo(
                trackNumber:     Double(trackNum),
                rawLength:       8192,
                sectorsFound:    result.sectors.count,
                sectorsExpected: expected,
                headerErrors:    result.headerErrors,
                dataErrors:      result.dataErrors,
                syncCount:       result.syncCount,
                hasData:         true
            ))
        }

        let virtualD64 = GCRDecoder.buildVirtualD64(sectors: allSectors)
        guard let baseDisk = D64Parser.parse(data: virtualD64, formatHint: .d64) else { return nil }

        return D64Disk(
            diskName:   baseDisk.diskName.isEmpty ? "NIB DISK" : baseDisk.diskName,
            diskID:     baseDisk.diskID,
            freeBlocks: baseDisk.freeBlocks,
            files:      baseDisk.files,
            format:     .nib,
            rawTracks:  trackInfos
        )
    }
}
