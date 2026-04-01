import Quartz
import Foundation
import UniformTypeIdentifiers

// MARK: - Quick Look Preview Extension
// Self-contained — no dependency on the main app target.

@objc(PreviewProvider)
class PreviewProvider: QLPreviewProvider, QLPreviewingController {

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url  = request.fileURL
        let data = try Data(contentsOf: url)
        let ext  = url.pathExtension.lowercased()

        // Load C64 Pro Mono font from the extension bundle
        let fontBase64: String
        if let fontURL  = Bundle(for: PreviewProvider.self)
                            .url(forResource: "C64_Pro_Mono-STYLE", withExtension: "ttf"),
           let fontData = try? Data(contentsOf: fontURL) {
            fontBase64 = fontData.base64EncodedString()
        } else {
            fontBase64 = ""
        }

        let (html, size) = QLDiskRenderer.render(data: data, ext: ext,
                                                  filename: url.deletingPathExtension().lastPathComponent,
                                                  fontBase64: fontBase64)
        let reply = QLPreviewReply(
            dataOfContentType: .html,
            contentSize: size
        ) { _ in
            return html.data(using: .utf8) ?? Data()
        }
        return reply
    }
}

// MARK: - Renderer

private enum QLDiskRenderer {

    static func render(data: Data, ext: String, filename: String, fontBase64: String) -> (html: String, size: CGSize) {
        let bytes = [UInt8](data)

        switch ext {
        case "t64":
            return renderT64(bytes: bytes, filename: filename, fontBase64: fontBase64)
        case "d64", "d71", "d81":
            return renderD64(bytes: bytes, ext: ext, filename: filename, fontBase64: fontBase64)
        default:
            return errorHTML("Unsupported format: .\(ext)")
        }
    }

    // MARK: D64 / D71 / D81

    private static func renderD64(bytes: [UInt8], ext: String, filename: String, fontBase64: String) -> (html: String, size: CGSize) {
        guard bytes.count > 512 else { return errorHTML("File too small") }

        let isD81 = (ext == "d81")
        let isD71 = (ext == "d71")

        // --- Disk name & ID ---
        let bamOff: Int
        let nameOff: Int
        let idOff: Int
        if isD81 {
            bamOff  = sectorOffset(track: 40, sector: 0, ext: ext)
            nameOff = bamOff + 0x04
            idOff   = bamOff + 0x16
        } else {
            bamOff  = sectorOffset(track: 18, sector: 0, ext: ext)
            nameOff = bamOff + 0x90
            idOff   = bamOff + 0xA2
        }
        guard nameOff + 16 <= bytes.count else { return errorHTML("Disk name offset out of range") }

        let diskName = petscii(bytes: bytes, from: nameOff, len: 16)
        let diskID   = petscii(bytes: bytes, from: idOff,   len: 5)

        // --- Free blocks ---
        var freeBlocks = 0
        if isD81 {
            let bam1 = sectorOffset(track: 40, sector: 1, ext: ext)
            let bam2 = sectorOffset(track: 40, sector: 2, ext: ext)
            for t in 1...40 {
                let e = bam1 + 0x10 + (t - 1) * 6
                if e < bytes.count { freeBlocks += Int(bytes[e]) }
            }
            for t in 41...80 {
                let e = bam2 + 0x10 + (t - 41) * 6
                if e < bytes.count { freeBlocks += Int(bytes[e]) }
            }
        } else if isD71 {
            for t in 1...35 where t != 18 {
                let e = bamOff + 4 + (t - 1) * 4
                if e < bytes.count { freeBlocks += Int(bytes[e]) }
            }
            let bam2 = sectorOffset(track: 18, sector: 0, ext: ext)
            for t in 36...70 {
                let e = bam2 + 0xDC + (t - 36)
                if e < bytes.count { freeBlocks += Int(bytes[e]) }
            }
        } else {
            for t in 1...35 where t != 18 {
                let e = bamOff + 4 + (t - 1) * 4
                if e < bytes.count { freeBlocks += Int(bytes[e]) }
            }
        }

        // --- Directory entries ---
        var entries: [(blocks: Int, name: String, type: String, deleted: Bool)] = []
        var dirTrack  = isD81 ? 40 : 18
        var dirSector = isD81 ? 3  : 1
        var visited   = Set<Int>()

        while dirTrack != 0 {
            let off = sectorOffset(track: dirTrack, sector: dirSector, ext: ext)
            let key = dirTrack &* 256 + dirSector
            guard !visited.contains(key), off + 256 <= bytes.count else { break }
            visited.insert(key)

            let nextTrack  = Int(bytes[off])
            let nextSector = Int(bytes[off + 1])

            for slot in 0..<8 {
                let base = off + 2 + slot * 32
                guard base + 30 <= bytes.count else { break }
                let ft = bytes[base]
                guard ft != 0x00 else { continue }
                let typeCode = ft & 0x07
                let typeName: String
                switch typeCode {
                case 0: typeName = "DEL"
                case 1: typeName = "SEQ"
                case 2: typeName = "PRG"
                case 3: typeName = "USR"
                case 4: typeName = "REL"
                default: typeName = "???"
                }
                let name   = petscii(bytes: bytes, from: base + 3, len: 16)
                guard !name.isEmpty else { continue }
                let blocks = Int(bytes[base + 28]) | (Int(bytes[base + 29]) << 8)
                entries.append((blocks, name, typeName, typeCode == 0))
            }

            dirTrack  = nextTrack
            dirSector = nextSector
        }

        return buildHTML(diskName: diskName, diskID: diskID,
                         freeBlocks: freeBlocks, showFreeBlocks: true,
                         entries: entries, formatLabel: ext.uppercased(),
                         fontBase64: fontBase64)
    }

    // MARK: T64

    private static func renderT64(bytes: [UInt8], filename: String, fontBase64: String) -> (html: String, size: CGSize) {
        guard bytes.count >= 64 else { return errorHTML("File too small") }
        let magic = String(bytes: bytes.prefix(20), encoding: .isoLatin1) ?? ""
        guard magic.hasPrefix("C64S tape file") || magic.hasPrefix("C64 tape image file")
        else { return errorHTML("Not a valid T64 file") }

        let usedEntries = Int(bytes[0x24]) | (Int(bytes[0x25]) << 8)
        let maxEntries  = Int(bytes[0x22]) | (Int(bytes[0x23]) << 8)
        let available   = (bytes.count - 0x40) / 32
        let count       = usedEntries > 0 ? usedEntries
                        : maxEntries  > 0 ? maxEntries
                        : min(available, 256)

        let tapeName = petscii(bytes: bytes, from: 0x28, len: 24)

        var entries: [(blocks: Int, name: String, type: String, deleted: Bool)] = []

        for i in 0..<count {
            let base = 0x40 + i * 32
            guard base + 32 <= bytes.count else { break }
            guard bytes[base] != 0 else { continue }

            let startAddr = Int(bytes[base + 2]) | (Int(bytes[base + 3]) << 8)
            let endAddr   = Int(bytes[base + 4]) | (Int(bytes[base + 5]) << 8)
            let dataLen   = endAddr > startAddr ? endAddr - startAddr : 0
            let blocks    = max(1, (dataLen + 253) / 254)
            let name      = petscii(bytes: bytes, from: base + 16, len: 16)
            guard !name.isEmpty else { continue }
            entries.append((blocks, name, "PRG", false))
        }

        return buildHTML(diskName: tapeName.isEmpty ? filename : tapeName, diskID: "T64",
                         freeBlocks: 0, showFreeBlocks: false,
                         entries: entries, formatLabel: "T64",
                         fontBase64: fontBase64)
    }

    // MARK: HTML builder

    private static func buildHTML(
        diskName: String, diskID: String,
        freeBlocks: Int, showFreeBlocks: Bool,
        entries: [(blocks: Int, name: String, type: String, deleted: Bool)],
        formatLabel: String,
        fontBase64: String
    ) -> (html: String, size: CGSize) {

        let fontFace = fontBase64.isEmpty ? "" : """
            @font-face {
              font-family: 'C64 Pro Mono';
              src: url('data:font/ttf;base64,\(fontBase64)') format('truetype');
            }
            """
        let c64Font = fontBase64.isEmpty ? "'Courier New', monospace" : "'C64 Pro Mono', monospace"

        // Header line: " 0 "DISKNAME        " DISKID"
        let headerName = pad(diskName, to: 16)
        let headerLine = " 0 \"\(htmlEscape(headerName))\" \(htmlEscape(diskID))"

        // Entry lines — each formatted as fixed columns to match in-app layout:
        //   blocks (4 chars) + space + "name (16 chars)" + "   " + type (3 chars)
        var preLines = ""
        for e in entries {
            let blocks  = pad(String(e.blocks), to: 4)
            let name    = pad(e.name, to: 16)
            let line    = "\(htmlEscape(blocks)) \"\(htmlEscape(name))\"   \(e.type)"
            if e.deleted {
                preLines += "<span style=\"opacity:0.45\">\(line)</span>\n"
            } else {
                preLines += "\(line)\n"
            }
        }

        if showFreeBlocks {
            preLines += "\n\(freeBlocks) BLOCKS FREE."
        }

        // Dynamic height: header (16px) + entries + footer lines + body padding
        let entryLines = entries.count + (showFreeBlocks ? 2 : 0)  // +1 blank, +1 footer
        let fontSize:   CGFloat = 14
        let bodyPad:    CGFloat = 40   // 20px top + 20px bottom
        let headerH:    CGFloat = fontSize + 4  // header div
        let height = bodyPad + headerH + CGFloat(entryLines) * fontSize + 8

        let html = """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <style>
          \(fontFace)
          * { box-sizing: border-box; margin: 0; padding: 0; }
          body {
            background: #4337A1;
            color: #ffffff;
            font-family: \(c64Font);
            font-size: \(Int(fontSize))px;
            line-height: 1.0;
            padding: 20px 24px;
          }
          .hd {
            background: #776DD0;
            color: #4337A1;
            font-family: \(c64Font);
            font-size: \(Int(fontSize))px;
            line-height: 1.0;
            white-space: pre;
            padding: 0 2px;
            margin-bottom: 2px;
          }
          pre {
            font-family: \(c64Font);
            font-size: \(Int(fontSize))px;
            line-height: 1.0;
            white-space: pre;
            color: #ffffff;
            margin: 0;
            padding: 0;
          }
        </style>
        </head><body>
        <div class="hd">\(headerLine)</div>
        <pre>\(preLines)</pre>
        </body></html>
        """

        return (html, CGSize(width: 520, height: max(80, height)))
    }

    // MARK: Helpers

    /// Right-pad (or truncate) `s` to exactly `length` characters.
    private static func pad(_ s: String, to length: Int) -> String {
        if s.count >= length { return String(s.prefix(length)) }
        return s + String(repeating: " ", count: length - s.count)
    }

    private static func sectorOffset(track: Int, sector: Int, ext: String) -> Int {
        var total = 0
        for t in 1..<track { total += sectorsPerTrack(t, ext: ext) }
        return (total + sector) * 256
    }

    private static func sectorsPerTrack(_ track: Int, ext: String) -> Int {
        if ext == "d81" { return 40 }
        if ext == "d71" {
            switch track {
            case  1...17: return 21
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
        switch track {
        case  1...17: return 21
        case 18...24: return 19
        case 25...30: return 18
        case 31...35: return 17
        default:      return 0
        }
    }

    /// PETSCII → String using the same PUA mapping as the main app.
    private static func petscii(bytes: [UInt8], from: Int, len: Int) -> String {
        guard from < bytes.count else { return "" }
        let end = min(from + len, bytes.count)
        var result = ""
        for i in from..<end {
            let b = bytes[i]
            if b == 0xA0 || b == 0x00 { break }
            if b >= 0x20 && b <= 0x5F {
                result.append(Character(UnicodeScalar(b)))
            } else if b >= 0x80 && b <= 0x9F {
                result.append("\u{2588}")
            } else if let scalar = Unicode.Scalar(UInt32(b) + 0xE000) {
                result.append(Character(scalar))
            }
        }
        return result
    }

    private static func htmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func errorHTML(_ msg: String) -> (html: String, size: CGSize) {
        let html = """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <style>body{background:#4337A1;color:#fff;font-family:-apple-system,sans-serif;font-size:13px;margin:20px;}</style>
        </head><body><p>⚠ \(htmlEscape(msg))</p></body></html>
        """
        return (html, CGSize(width: 520, height: 80))
    }
}
