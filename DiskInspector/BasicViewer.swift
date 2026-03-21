import SwiftUI
import AppKit
import Combine

// MARK: - BASIC Detokenizer

struct BasicDetokenizer {

    struct BasicLine {
        let lineNumber: Int
        let text: String
    }

    /// Detect if file data looks like a BASIC program
    static func isBasicProgram(_ data: Data) -> Bool {
        guard data.count >= 5 else { return false }
        let bytes = [UInt8](data)
        let loadAddr = Int(bytes[0]) | (Int(bytes[1]) << 8)
        if loadAddr != 0x0801 && loadAddr != 0x1C01 { return false }
        let nextLine = Int(bytes[2]) | (Int(bytes[3]) << 8)
        return nextLine > loadAddr && nextLine < loadAddr + data.count
    }

    /// Detokenize a BASIC program
    static func detokenize(_ data: Data) -> [BasicLine]? {
        guard data.count >= 5 else { return nil }
        let bytes = [UInt8](data)
        let loadAddr = Int(bytes[0]) | (Int(bytes[1]) << 8)
        let isC128 = (loadAddr == 0x1C01)

        var lines: [BasicLine] = []
        var pos = 2

        while pos + 3 < bytes.count {
            let nextPtr = Int(bytes[pos]) | (Int(bytes[pos + 1]) << 8)
            if nextPtr == 0 { break }

            let lineNum = Int(bytes[pos + 2]) | (Int(bytes[pos + 3]) << 8)
            pos += 4

            var text = ""
            var inQuote = false

            while pos < bytes.count && bytes[pos] != 0x00 {
                let b = bytes[pos]

                if b == 0x22 {
                    inQuote.toggle()
                    text.append("\"")
                    pos += 1
                    continue
                }

                if inQuote {
                    text.append(petsciiChar(b))
                    pos += 1
                    continue
                }

                // BASIC 7.0 two-byte tokens
                if isC128 && b == 0xFE && pos + 1 < bytes.count {
                    let token2 = bytes[pos + 1]
                    text.append(basic7ExtTokens[token2] ?? "{\(String(format: "FE%02X", token2))}")
                    pos += 2
                    continue
                }

                // BASIC 7.0 extra tokens
                if isC128 && b >= 0xCC && b <= 0xFD {
                    text.append(basic7Tokens[b] ?? "{\(String(format: "%02X", b))}")
                    pos += 1
                    continue
                }

                // BASIC 2.0 tokens
                if b >= 0x80 && b <= 0xCB {
                    text.append(basic2Tokens[b] ?? "{\(String(format: "%02X", b))}")
                    pos += 1
                    continue
                }

                text.append(petsciiChar(b))
                pos += 1
            }

            if pos < bytes.count && bytes[pos] == 0x00 { pos += 1 }
            lines.append(BasicLine(lineNumber: lineNum, text: text))
            if lines.count > 10000 { break }
        }

        return lines.isEmpty ? nil : lines
    }

    private static func petsciiChar(_ b: UInt8) -> Character {
        if b >= 0x20 && b <= 0x7E { return Character(UnicodeScalar(b)) }
        if b >= 0xC1 && b <= 0xDA { return Character(UnicodeScalar(b - 0xC1 + 0x41)) }
        return "·"
    }

    // MARK: - Token Tables

    static let basic2Tokens: [UInt8: String] = [
        0x80: "END",     0x81: "FOR",     0x82: "NEXT",    0x83: "DATA",
        0x84: "INPUT#",  0x85: "INPUT",   0x86: "DIM",     0x87: "READ",
        0x88: "LET",     0x89: "GOTO",    0x8A: "RUN",     0x8B: "IF",
        0x8C: "RESTORE", 0x8D: "GOSUB",   0x8E: "RETURN",  0x8F: "REM",
        0x90: "STOP",    0x91: "ON",      0x92: "WAIT",    0x93: "LOAD",
        0x94: "SAVE",    0x95: "VERIFY",  0x96: "DEF",     0x97: "POKE",
        0x98: "PRINT#",  0x99: "PRINT",   0x9A: "CONT",    0x9B: "LIST",
        0x9C: "CLR",     0x9D: "CMD",     0x9E: "SYS",     0x9F: "OPEN",
        0xA0: "CLOSE",   0xA1: "GET",     0xA2: "NEW",     0xA3: "TAB(",
        0xA4: "TO",      0xA5: "FN",      0xA6: "SPC(",    0xA7: "THEN",
        0xA8: "NOT",     0xA9: "STEP",    0xAA: "+",       0xAB: "-",
        0xAC: "*",       0xAD: "/",       0xAE: "^",       0xAF: "AND",
        0xB0: "OR",      0xB1: ">",       0xB2: "=",       0xB3: "<",
        0xB4: "SGN",     0xB5: "INT",     0xB6: "ABS",     0xB7: "USR",
        0xB8: "FRE",     0xB9: "POS",     0xBA: "SQR",     0xBB: "RND",
        0xBC: "LOG",     0xBD: "EXP",     0xBE: "COS",     0xBF: "SIN",
        0xC0: "TAN",     0xC1: "ATN",     0xC2: "PEEK",    0xC3: "LEN",
        0xC4: "STR$",    0xC5: "VAL",     0xC6: "ASC",     0xC7: "CHR$",
        0xC8: "LEFT$",   0xC9: "RIGHT$",  0xCA: "MID$",    0xCB: "GO",
    ]

    static let basic7Tokens: [UInt8: String] = [
        0xCC: "RGR",     0xCD: "RCLR",    0xCE: "RLUM",    0xCF: "JOY",
        0xD0: "RDOT",    0xD1: "DEC",     0xD2: "HEX$",    0xD3: "ERR$",
        0xD4: "INSTR",   0xD5: "ELSE",    0xD6: "RESUME",  0xD7: "TRAP",
        0xD8: "TRON",    0xD9: "TROFF",   0xDA: "SOUND",   0xDB: "VOL",
        0xDC: "AUTO",    0xDD: "PUDEF",   0xDE: "GRAPHIC", 0xDF: "PAINT",
        0xE0: "CHAR",    0xE1: "BOX",     0xE2: "CIRCLE",  0xE3: "GSHAPE",
        0xE4: "SSHAPE",  0xE5: "DRAW",    0xE6: "LOCATE",  0xE7: "COLOR",
        0xE8: "SCNCLR",  0xE9: "SCALE",   0xEA: "HELP",    0xEB: "DO",
        0xEC: "LOOP",    0xED: "EXIT",    0xEE: "DIRECTORY",0xEF: "DSAVE",
        0xF0: "DLOAD",   0xF1: "HEADER",  0xF2: "SCRATCH",  0xF3: "COLLECT",
        0xF4: "COPY",    0xF5: "RENAME",  0xF6: "BACKUP",   0xF7: "DELETE",
        0xF8: "RENUMBER",0xF9: "KEY",     0xFA: "MONITOR",  0xFB: "USING",
        0xFC: "UNTIL",   0xFD: "WHILE",
    ]

    static let basic7ExtTokens: [UInt8: String] = [
        0x02: "POT",     0x03: "BUMP",    0x04: "PEN",     0x05: "RSPPOS",
        0x06: "RSPRITE", 0x07: "RSPCOLOR",0x08: "XOR",     0x09: "RWINDOW",
        0x0A: "POINTER", 0x0B: "BANK",    0x0C: "SWAP",    0x0D: "FETCH",
        0x0E: "STASH",   0x0F: "LPEN",    0x10: "OFF",     0x11: "FAST",
        0x12: "SLOW",    0x13: "TYPE",    0x14: "BLOAD",   0x15: "BSAVE",
        0x16: "RECORD",  0x17: "CONCAT",  0x18: "DOPEN",   0x19: "DCLOSE",
        0x1A: "DCLEAR",  0x1B: "DVERIFY", 0x1C: "WIDTH",   0x1D: "BEGIN",
        0x1E: "SPRDEF",  0x1F: "RREG",    0x20: "CATALOG", 0x21: "DVERIFY",
        0x22: "DIRECTORY",0x23: "DMA",    0x24: "PLAY",    0x25: "TEMPO",
        0x26: "MOVSPR",  0x27: "SPRITE",  0x28: "SPRCOLOR",0x29: "SPRSAV",
        0x2A: "COLLISION",0x2B: "SYSRESET",
    ]
}

// MARK: - BASIC Viewer Window

struct BasicViewerWindow {
    static func open(file: D64File) {
        guard let lines = BasicDetokenizer.detokenize(file.rawData) else { return }
        let loadAddr = file.rawData.count >= 2
            ? Int(file.rawData[0]) | (Int(file.rawData[1]) << 8)
            : 0
        let basicType = loadAddr == 0x1C01 ? "BASIC 7.0" : "BASIC 2.0"

        let view = NSHostingController(rootView:
            BasicListingView(file: file, lines: lines, basicType: basicType))
        let window = NSWindow(contentViewController: view)
        window.title = "\(file.filename.uppercased()) — \(basicType)"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        let height = min(CGFloat(lines.count) * 18 + 120, 600)
        window.setContentSize(NSSize(width: 520, height: max(height, 250)))
        window.minSize = NSSize(width: 400, height: 200)
        window.center()
        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        objc_setAssociatedObject(window, "controller", controller, .OBJC_ASSOCIATION_RETAIN)
    }

    /// Try to open as BASIC; returns false if not a BASIC program
    static func tryOpen(file: D64File) -> Bool {
        if BasicDetokenizer.isBasicProgram(file.rawData) {
            open(file: file)
            return true
        }
        return false
    }
}

// MARK: - BASIC Listing View

struct BasicListingView: View {
    let file: D64File
    let lines: [BasicDetokenizer.BasicLine]
    let basicType: String
    private let monoFont = "C64 Pro Mono"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 24) {
                headerItem(label: "FILE", value: file.filename.uppercased())
                headerItem(label: "TYPE", value: basicType)
                headerItem(label: "LINES", value: "\(lines.count)")
                headerItem(label: "SIZE", value: "\(file.rawData.count) BYTES")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Listing
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines.indices, id: \.self) { i in
                        basicLine(lines[i])
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(minWidth: 400, minHeight: 200)
    }

    func headerItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.custom(monoFont, size: 9))
                .foregroundColor(Color.c64LightBlue)
            Text(value)
                .font(.custom(monoFont, size: 12))
                .foregroundColor(Color.c64Blue)
        }
    }

    func basicLine(_ line: BasicDetokenizer.BasicLine) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("\(line.lineNumber) ")
                .font(.custom(monoFont, size: 13))
                .foregroundColor(Color.c64LightBlue)
                .frame(minWidth: 50, alignment: .trailing)

            Text(line.text)
                .font(.custom(monoFont, size: 13))
                .foregroundColor(Color.c64Blue)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 18, alignment: .topLeading)
    }
}
