import SwiftUI
import AppKit

// MARK: - Validation Issue

enum IssueSeverity: String {
    case ok      = "OK"
    case info    = "INFO"
    case warning = "WARNING"
    case error   = "ERROR"

    var color: Color {
        switch self {
        case .ok:      return .green
        case .info:    return Color.c64LightBlue
        case .warning: return .orange
        case .error:   return .red
        }
    }

    var symbol: String {
        switch self {
        case .ok:      return "●"
        case .info:    return "●"
        case .warning: return "▲"
        case .error:   return "✖"
        }
    }
}

struct ValidationIssue: Identifiable {
    let id = UUID()
    let severity: IssueSeverity
    let category: String
    let message: String
}

// MARK: - Disk Validator

struct DiskValidator {

    /// Run all validation checks and return a list of issues found.
    static func validate(data: Data) -> [ValidationIssue] {
        guard let format = DiskFormat.detect(size: data.count) else {
            return [ValidationIssue(severity: .error, category: "FORMAT",
                                     message: "Unknown disk format (size: \(data.count) bytes)")]
        }
        let bytes = [UInt8](data)
        var issues: [ValidationIssue] = []

        // Parse directory for file info
        let files = parseDirectory(bytes: bytes, format: format)

        // 1. Build sector usage map from file chains
        var sectorOwner: [String: [String]] = [:]  // "T:S" → [filename, ...]
        var chainLengths: [String: Int] = [:]       // filename → actual chain length

        for file in files {
            var curTrack = file.track
            var curSector = file.sector
            var visited = Set<String>()
            var chainLen = 0

            while curTrack != 0 {
                let key = "\(curTrack):\(curSector)"
                if visited.contains(key) {
                    issues.append(ValidationIssue(
                        severity: .error, category: "CHAIN",
                        message: "\(file.name): circular chain at T\(curTrack)/S\(curSector)"))
                    break
                }
                visited.insert(key)

                // Validate track/sector range
                let maxSectors = D64Parser.trackSectors(track: Int(curTrack), format: format)
                if curTrack < 1 || curTrack > UInt8(format.totalTracks) || Int(curSector) >= maxSectors {
                    issues.append(ValidationIssue(
                        severity: .error, category: "CHAIN",
                        message: "\(file.name): invalid sector T\(curTrack)/S\(curSector)"))
                    break
                }

                sectorOwner[key, default: []].append(file.name)
                chainLen += 1

                let s = D64Parser.offset(track: Int(curTrack), sector: Int(curSector), format: format)
                guard s + 2 <= bytes.count else { break }
                curTrack = bytes[s]
                curSector = bytes[s + 1]
            }
            chainLengths[file.name] = chainLen
        }

        // 2. Check cross-linked sectors
        for (sector, owners) in sectorOwner where owners.count > 1 {
            let names = owners.joined(separator: ", ")
            issues.append(ValidationIssue(
                severity: .error, category: "CROSS-LINK",
                message: "Sector \(sector) shared by: \(names)"))
        }

        // 3. Check chain length vs directory block count
        for file in files {
            if let actual = chainLengths[file.name], actual != file.blocks && file.track != 0 {
                issues.append(ValidationIssue(
                    severity: .warning, category: "BLOCKS",
                    message: "\(file.name): directory says \(file.blocks) blocks, chain has \(actual)"))
            }
        }

        // 4. BAM validation — compare BAM bitmap with actual sector usage
        let dirSectors = getDirectorySectors(bytes: bytes, format: format)
        let systemSectors = getSystemSectors(format: format)
        let allUsedSectors = Set(sectorOwner.keys).union(dirSectors).union(systemSectors)

        var bamFreeCount = 0
        var bamUsedCount = 0
        var orphanedCount = 0
        var bamErrors: [String] = []

        for t in 1...format.totalTracks {
            let numSectors = D64Parser.trackSectors(track: t, format: format)
            // Skip system tracks in free count (they're excluded from display too)
            let isSystemTrack = (format == .d64 && t == 18) ||
                                (format == .d71 && (t == 18 || t == 53)) ||
                                (format == .d81 && t == 40)

            let (fcOff, bmOff) = D64Parser.bamOffsets(track: t, format: format)

            // Count actual free bits in bitmap
            var bitmapFreeCount = 0
            for sec in 0..<numSectors {
                let byteIdx = sec / 8
                let bitIdx = sec % 8
                let isFree = (bytes[bmOff + byteIdx] >> bitIdx) & 1 == 1
                let key = "\(t):\(sec)"
                let isUsedByFile = allUsedSectors.contains(key)

                if isFree {
                    bitmapFreeCount += 1
                    if isUsedByFile {
                        bamErrors.append("T\(t)/S\(sec): marked FREE in BAM but used by file")
                    }
                } else {
                    if !isUsedByFile && !isSystemTrack {
                        orphanedCount += 1
                    }
                }
            }

            // Check free count byte matches bitmap
            let storedFreeCount = Int(bytes[fcOff])
            if storedFreeCount != bitmapFreeCount {
                issues.append(ValidationIssue(
                    severity: .warning, category: "BAM",
                    message: "Track \(t): free count says \(storedFreeCount), bitmap has \(bitmapFreeCount) free"))
            }

            if !isSystemTrack {
                bamFreeCount += bitmapFreeCount
                bamUsedCount += numSectors - bitmapFreeCount
            }
        }

        for err in bamErrors {
            issues.append(ValidationIssue(severity: .error, category: "BAM", message: err))
        }

        if orphanedCount > 0 {
            issues.append(ValidationIssue(
                severity: .warning, category: "BAM",
                message: "\(orphanedCount) sector\(orphanedCount == 1 ? "" : "s") marked used but not in any file chain (lost sectors)"))
        }

        // 5. Directory checks
        var nameCount: [String: Int] = [:]
        for file in files {
            nameCount[file.name, default: 0] += 1
            if file.track == 0 && file.blocks > 0 {
                issues.append(ValidationIssue(
                    severity: .warning, category: "DIR",
                    message: "\(file.name): starts at T0/S0 but has \(file.blocks) blocks"))
            }
        }
        for (name, count) in nameCount where count > 1 {
            issues.append(ValidationIssue(
                severity: .warning, category: "DIR",
                message: "Duplicate filename: \"\(name)\" appears \(count) times"))
        }

        // 6. Summary
        if issues.isEmpty {
            issues.append(ValidationIssue(
                severity: .ok, category: "RESULT",
                message: "Disk is clean — no issues found"))
        }

        // Sort: errors first, then warnings, then info
        issues.sort { a, b in
            let order: [IssueSeverity: Int] = [.error: 0, .warning: 1, .info: 2, .ok: 3]
            return (order[a.severity] ?? 9) < (order[b.severity] ?? 9)
        }

        // Add summary at the end
        let errorCount = issues.filter { $0.severity == .error }.count
        let warnCount = issues.filter { $0.severity == .warning }.count
        issues.append(ValidationIssue(
            severity: errorCount > 0 ? .error : (warnCount > 0 ? .warning : .ok),
            category: "SUMMARY",
            message: "\(files.count) files, \(errorCount) error\(errorCount == 1 ? "" : "s"), \(warnCount) warning\(warnCount == 1 ? "" : "s"), \(bamFreeCount) blocks free"))

        return issues
    }

    // MARK: - Helpers

    private struct FileEntry {
        let name: String
        let track: UInt8
        let sector: UInt8
        let blocks: Int
        let typeCode: UInt8
    }

    private static func parseDirectory(bytes: [UInt8], format: DiskFormat) -> [FileEntry] {
        var files: [FileEntry] = []
        var dirTrack = UInt8(format.dirTrack)
        var dirSector = UInt8(format.dirSector)
        var visited = Set<String>()

        while dirTrack != 0 {
            let key = "\(dirTrack):\(dirSector)"
            if visited.contains(key) { break }
            visited.insert(key)
            let off = D64Parser.offset(track: Int(dirTrack), sector: Int(dirSector), format: format)
            dirTrack = bytes[off]
            dirSector = bytes[off + 1]
            for entry in 0..<8 {
                let base = off + 2 + entry * 32
                let typeByte = bytes[base]
                if typeByte == 0x00 { continue }
                let nameSlice = bytes[(base + 3)..<(base + 19)]
                let rawName = nameSlice.prefix(while: { $0 != 0xA0 && $0 != 0x00 })
                if rawName.allSatisfy({ $0 == 0x01 }) { continue }
                let name = D64Parser.petsciiToString(bytes[(base + 3)..<(base + 19)])
                if name.isEmpty { continue }
                let fTrack = bytes[base + 1]
                let fSector = bytes[base + 2]
                let blocks = Int(bytes[base + 28]) | (Int(bytes[base + 29]) << 8)
                files.append(FileEntry(name: name, track: fTrack, sector: fSector,
                                        blocks: blocks, typeCode: typeByte))
            }
        }
        return files
    }

    private static func getDirectorySectors(bytes: [UInt8], format: DiskFormat) -> Set<String> {
        var sectors = Set<String>()
        var dirTrack = UInt8(format.dirTrack)
        var dirSector = UInt8(format.dirSector)
        var visited = Set<String>()
        while dirTrack != 0 {
            let key = "\(dirTrack):\(dirSector)"
            if visited.contains(key) { break }
            visited.insert(key)
            sectors.insert(key)
            let off = D64Parser.offset(track: Int(dirTrack), sector: Int(dirSector), format: format)
            dirTrack = bytes[off]
            dirSector = bytes[off + 1]
        }
        return sectors
    }

    private static func getSystemSectors(format: DiskFormat) -> Set<String> {
        var sectors = Set<String>()
        switch format {
        case .d64:
            sectors.insert("18:0")  // BAM
        case .d71:
            sectors.insert("18:0")  // BAM side 1
            sectors.insert("53:0")  // BAM side 2
        case .d81:
            sectors.insert("40:0")  // Header
            sectors.insert("40:1")  // BAM1
            sectors.insert("40:2")  // BAM2
        case .t64, .lnx, .g64, .nib: break
        }
        return sectors
    }
}

// MARK: - Validation Results Window

struct ValidationWindow {
    static func open(issues: [ValidationIssue], diskName: String) {
        let view = NSHostingController(rootView: ValidationResultsView(issues: issues, diskName: diskName))
        let window = NSWindow(contentViewController: view)
        window.title = "\(diskName.uppercased()) — Disk Validation"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        // Size to fit: header(40) + divider(1) + issues(~24 each) + padding
        let issueHeight = CGFloat(issues.count) * 24
        let totalHeight = min(max(issueHeight + 60, 120), 500)
        window.setContentSize(NSSize(width: 520, height: totalHeight))
        window.minSize = NSSize(width: 400, height: 250)
        window.center()
        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        objc_setAssociatedObject(window, "controller", controller, .OBJC_ASSOCIATION_RETAIN)
    }
}

struct ValidationResultsView: View {
    let issues: [ValidationIssue]
    let diskName: String
    private let monoFont = "C64 Pro Mono"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("VALIDATE: \(diskName.uppercased())")
                    .font(.custom(monoFont, size: 14))
                    .foregroundColor(Color.c64Blue)
                Spacer()
                let errors = issues.filter { $0.severity == .error }.count
                let warnings = issues.filter { $0.severity == .warning }.count
                if errors == 0 && warnings == 0 {
                    Text("DISK OK")
                        .font(.custom(monoFont, size: 14))
                        .foregroundColor(.green)
                } else {
                    Text("\(errors)E \(warnings)W")
                        .font(.custom(monoFont, size: 14))
                        .foregroundColor(errors > 0 ? .red : .orange)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Issues list
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(issues) { issue in
                        HStack(alignment: .top, spacing: 8) {
                            Text(issue.severity.symbol)
                                .font(.custom(monoFont, size: 12))
                                .foregroundColor(issue.severity.color)
                                .frame(width: 16)

                            Text(issue.category)
                                .font(.custom(monoFont, size: 10))
                                .foregroundColor(Color.c64LightBlue)
                                .frame(width: 80, alignment: .leading)

                            Text(issue.message)
                                .font(.custom(monoFont, size: 11))
                                .foregroundColor(issue.severity == .ok ? .green : Color.c64Blue)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(minWidth: 400, minHeight: 250)
    }
}
