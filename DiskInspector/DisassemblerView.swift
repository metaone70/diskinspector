import SwiftUI
import AppKit

// MARK: - 6510 Disassembler

struct Disassembler6510 {

    struct Line {
        let address: UInt16
        let bytes: [UInt8]
        let mnemonic: String
        let operand: String
    }

    enum AddrMode {
        case imp   // implied — no operand
        case acc   // accumulator — A
        case imm   // immediate — #$XX
        case zp    // zero page — $XX
        case zpx   // zero page,X — $XX,X
        case zpy   // zero page,Y — $XX,Y
        case abs   // absolute — $XXXX
        case abx   // absolute,X — $XXXX,X
        case aby   // absolute,Y — $XXXX,Y
        case ind   // indirect — ($XXXX)
        case izx   // (indirect,X) — ($XX,X)
        case izy   // (indirect),Y — ($XX),Y
        case rel   // relative branch — $XXXX (computed)
    }

    // Full 6502/6510 opcode table — 256 entries, nil = undocumented/illegal
    static let opcodeTable: [(String, AddrMode)?] = [
        // $00–$0F
        ("BRK",.imp), ("ORA",.izx), nil, nil, nil, ("ORA",.zp), ("ASL",.zp), nil,
        ("PHP",.imp), ("ORA",.imm), ("ASL",.acc), nil, nil, ("ORA",.abs), ("ASL",.abs), nil,
        // $10–$1F
        ("BPL",.rel), ("ORA",.izy), nil, nil, nil, ("ORA",.zpx), ("ASL",.zpx), nil,
        ("CLC",.imp), ("ORA",.aby), nil, nil, nil, ("ORA",.abx), ("ASL",.abx), nil,
        // $20–$2F
        ("JSR",.abs), ("AND",.izx), nil, nil, ("BIT",.zp), ("AND",.zp), ("ROL",.zp), nil,
        ("PLP",.imp), ("AND",.imm), ("ROL",.acc), nil, ("BIT",.abs), ("AND",.abs), ("ROL",.abs), nil,
        // $30–$3F
        ("BMI",.rel), ("AND",.izy), nil, nil, nil, ("AND",.zpx), ("ROL",.zpx), nil,
        ("SEC",.imp), ("AND",.aby), nil, nil, nil, ("AND",.abx), ("ROL",.abx), nil,
        // $40–$4F
        ("RTI",.imp), ("EOR",.izx), nil, nil, nil, ("EOR",.zp), ("LSR",.zp), nil,
        ("PHA",.imp), ("EOR",.imm), ("LSR",.acc), nil, ("JMP",.abs), ("EOR",.abs), ("LSR",.abs), nil,
        // $50–$5F
        ("BVC",.rel), ("EOR",.izy), nil, nil, nil, ("EOR",.zpx), ("LSR",.zpx), nil,
        ("CLI",.imp), ("EOR",.aby), nil, nil, nil, ("EOR",.abx), ("LSR",.abx), nil,
        // $60–$6F
        ("RTS",.imp), ("ADC",.izx), nil, nil, nil, ("ADC",.zp), ("ROR",.zp), nil,
        ("PLA",.imp), ("ADC",.imm), ("ROR",.acc), nil, ("JMP",.ind), ("ADC",.abs), ("ROR",.abs), nil,
        // $70–$7F
        ("BVS",.rel), ("ADC",.izy), nil, nil, nil, ("ADC",.zpx), ("ROR",.zpx), nil,
        ("SEI",.imp), ("ADC",.aby), nil, nil, nil, ("ADC",.abx), ("ROR",.abx), nil,
        // $80–$8F
        nil, ("STA",.izx), nil, nil, ("STY",.zp), ("STA",.zp), ("STX",.zp), nil,
        ("DEY",.imp), nil, ("TXA",.imp), nil, ("STY",.abs), ("STA",.abs), ("STX",.abs), nil,
        // $90–$9F
        ("BCC",.rel), ("STA",.izy), nil, nil, ("STY",.zpx), ("STA",.zpx), ("STX",.zpy), nil,
        ("TYA",.imp), ("STA",.aby), ("TXS",.imp), nil, nil, ("STA",.abx), nil, nil,
        // $A0–$AF
        ("LDY",.imm), ("LDA",.izx), ("LDX",.imm), nil, ("LDY",.zp), ("LDA",.zp), ("LDX",.zp), nil,
        ("TAY",.imp), ("LDA",.imm), ("TAX",.imp), nil, ("LDY",.abs), ("LDA",.abs), ("LDX",.abs), nil,
        // $B0–$BF
        ("BCS",.rel), ("LDA",.izy), nil, nil, ("LDY",.zpx), ("LDA",.zpx), ("LDX",.zpy), nil,
        ("CLV",.imp), ("LDA",.aby), ("TSX",.imp), nil, ("LDY",.abx), ("LDA",.abx), ("LDX",.aby), nil,
        // $C0–$CF
        ("CPY",.imm), ("CMP",.izx), nil, nil, ("CPY",.zp), ("CMP",.zp), ("DEC",.zp), nil,
        ("INY",.imp), ("CMP",.imm), ("DEX",.imp), nil, ("CPY",.abs), ("CMP",.abs), ("DEC",.abs), nil,
        // $D0–$DF
        ("BNE",.rel), ("CMP",.izy), nil, nil, nil, ("CMP",.zpx), ("DEC",.zpx), nil,
        ("CLD",.imp), ("CMP",.aby), nil, nil, nil, ("CMP",.abx), ("DEC",.abx), nil,
        // $E0–$EF
        ("CPX",.imm), ("SBC",.izx), nil, nil, ("CPX",.zp), ("SBC",.zp), ("INC",.zp), nil,
        ("INX",.imp), ("SBC",.imm), ("NOP",.imp), nil, ("CPX",.abs), ("SBC",.abs), ("INC",.abs), nil,
        // $F0–$FF
        ("BEQ",.rel), ("SBC",.izy), nil, nil, nil, ("SBC",.zpx), ("INC",.zpx), nil,
        ("SED",.imp), ("SBC",.aby), nil, nil, nil, ("SBC",.abx), ("INC",.abx), nil,
    ]

    static func operandSize(_ mode: AddrMode) -> Int {
        switch mode {
        case .imp, .acc:                          return 0
        case .imm, .zp, .zpx, .zpy, .izx, .izy, .rel: return 1
        case .abs, .abx, .aby, .ind:              return 2
        }
    }

    /// Disassemble PRG data. First 2 bytes are the load address (little-endian).
    static func disassemble(_ data: Data) -> [Line] {
        guard data.count >= 2 else { return [] }
        let bytes = [UInt8](data)
        let loadAddr = Int(bytes[0]) | (Int(bytes[1]) << 8)
        let code = Array(bytes.dropFirst(2))

        var lines: [Line] = []
        var i = 0

        while i < code.count {
            let pc = UInt16(truncatingIfNeeded: loadAddr + i)
            let opcode = code[i]

            guard let (mnemonic, mode) = opcodeTable[Int(opcode)] else {
                // Unknown/illegal opcode — emit as .BYTE
                lines.append(Line(
                    address: pc,
                    bytes: [opcode],
                    mnemonic: ".BYTE",
                    operand: "$\(String(format: "%02X", opcode))"
                ))
                i += 1
                continue
            }

            let size = operandSize(mode)
            var instrBytes: [UInt8] = [opcode]

            if size > 0 {
                guard i + size < code.count else {
                    // Not enough bytes left — emit opcode only
                    lines.append(Line(address: pc, bytes: instrBytes, mnemonic: mnemonic, operand: ""))
                    i += 1
                    break
                }
                for j in 1...size {
                    instrBytes.append(code[i + j])
                }
            }

            let operand = formatOperand(mode: mode, bytes: instrBytes, pc: pc)
            lines.append(Line(address: pc, bytes: instrBytes, mnemonic: mnemonic, operand: operand))
            i += 1 + size
        }

        return lines
    }

    private static func formatOperand(mode: AddrMode, bytes: [UInt8], pc: UInt16) -> String {
        switch mode {
        case .imp:
            return ""
        case .acc:
            return "A"
        case .imm:
            return "#$\(String(format: "%02X", bytes[1]))"
        case .zp:
            return "$\(String(format: "%02X", bytes[1]))"
        case .zpx:
            return "$\(String(format: "%02X", bytes[1])),X"
        case .zpy:
            return "$\(String(format: "%02X", bytes[1])),Y"
        case .abs:
            let addr = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
            return "$\(String(format: "%04X", addr))"
        case .abx:
            let addr = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
            return "$\(String(format: "%04X", addr)),X"
        case .aby:
            let addr = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
            return "$\(String(format: "%04X", addr)),Y"
        case .ind:
            let addr = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
            return "($\(String(format: "%04X", addr)))"
        case .izx:
            return "($\(String(format: "%02X", bytes[1])),X)"
        case .izy:
            return "($\(String(format: "%02X", bytes[1]))),Y"
        case .rel:
            let offset = Int8(bitPattern: bytes[1])
            let target = UInt16(truncatingIfNeeded: Int(pc) + 2 + Int(offset))
            return "$\(String(format: "%04X", target))"
        }
    }
}

// MARK: - Disassembler Window

struct DisassemblerWindow {

    static func canOpen(file: D64File) -> Bool {
        file.fileType == "PRG"
    }

    static func open(file: D64File) {
        let lines = Disassembler6510.disassemble(file.rawData)
        let loadAddr = file.rawData.count >= 2
            ? Int(file.rawData[0]) | (Int(file.rawData[1]) << 8)
            : 0
        let view = NSHostingController(rootView:
            DisassemblerView(file: file, lines: lines, loadAddr: loadAddr))
        let window = NSWindow(contentViewController: view)
        window.title = "\(file.filename.uppercased()) — 6510 DISASSEMBLY"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        let height = min(CGFloat(lines.count) * 18 + 120, 600)
        window.setContentSize(NSSize(width: 640, height: max(height, 250)))
        window.minSize = NSSize(width: 480, height: 200)
        window.center()
        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        objc_setAssociatedObject(window, "controller", controller, .OBJC_ASSOCIATION_RETAIN)
    }
}

// MARK: - Disassembler View

struct DisassemblerView: View {
    let file: D64File
    let lines: [Disassembler6510.Line]
    let loadAddr: Int
    private let monoFont = "C64 Pro Mono"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 24) {
                headerItem(label: "FILE", value: file.filename.uppercased())
                headerItem(label: "LOAD", value: "$\(String(format: "%04X", loadAddr))")
                headerItem(label: "INSTRUCTIONS", value: "\(lines.count)")
                headerItem(label: "SIZE", value: "\(file.rawData.count) BYTES")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines.indices, id: \.self) { i in
                        disasmLine(lines[i])
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

    func disasmLine(_ line: Disassembler6510.Line) -> some View {
        // Pad hex to always occupy 3-byte width: "XX XX XX" = 8 chars
        let hexRaw = line.bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        let hexPad = hexRaw.padding(toLength: 8, withPad: " ", startingAt: 0)
        // Pad mnemonic to 5 chars (".BYTE" is longest)
        let mnemonicPad = line.mnemonic.padding(toLength: 5, withPad: " ", startingAt: 0)
        let isByte = line.mnemonic == ".BYTE"

        return HStack(spacing: 0) {
            // "$0801  " — address + 2 spaces
            Text(String(format: "$%04X  ", line.address))
                .foregroundColor(Color.c64LightBlue)

            // "XX XX XX  " — padded hex + 2 spaces
            Text(hexPad + "  ")
                .foregroundColor(Color.c64LightBlue.opacity(0.6))

            // ".BYTE  " — padded mnemonic + 2 spaces
            Text(mnemonicPad + "  ")
                .foregroundColor(isByte ? Color.c64LightBlue : Color.c64Blue)

            // operand
            Text(line.operand)
                .foregroundColor(Color.c64Blue)

            Spacer(minLength: 0)
        }
        .font(.custom(monoFont, size: 13))
        .lineLimit(1)
        .frame(minHeight: 18, alignment: .leading)
    }
}
