import SwiftUI
import AppKit
import Combine

// MARK: - BAM Map Data

struct SectorInfo {
    let track: Int
    let sector: Int
    var status: SectorStatus
    var owner: String?       // filename that uses this sector
    var chainIndex: Int?     // position in the file's chain (1-based)
}

enum SectorStatus {
    case free
    case fileUsed
    case system       // BAM, directory
    case orphaned     // marked used in BAM but not in any chain

    var color: Color {
        switch self {
        case .free:     return Color.green.opacity(0.6)
        case .fileUsed: return Color.c64Blue
        case .system:   return Color.gray
        case .orphaned: return Color.red.opacity(0.7)
        }
    }
}

// MARK: - BAM Analyzer

struct BAMAnalyzer {

    struct FileChain {
        let name: String
        let sectors: [(track: Int, sector: Int)]
    }

    struct Result {
        let format: DiskFormat
        let sectorMap: [String: SectorInfo]   // "T:S" → info
        let fileChains: [FileChain]
        let totalTracks: Int
        let maxSectors: Int                    // max sectors in any track
    }

    static func analyze(data: Data) -> Result? {
        guard let format = DiskFormat.detect(size: data.count) else { return nil }
        let bytes = [UInt8](data)

        var sectorMap: [String: SectorInfo] = [:]
        var fileChains: [FileChain] = []
        var maxSec = 0

        // Initialize all sectors as free or used based on BAM
        for t in 1...format.totalTracks {
            let numSectors = D64Parser.trackSectors(track: t, format: format)
            if numSectors > maxSec { maxSec = numSectors }
            let (_, bmOff) = D64Parser.bamOffsets(track: t, format: format)
            for s in 0..<numSectors {
                let byteIdx = s / 8
                let bitIdx = s % 8
                let isFree = (bytes[bmOff + byteIdx] >> bitIdx) & 1 == 1
                let key = "\(t):\(s)"
                sectorMap[key] = SectorInfo(
                    track: t, sector: s,
                    status: isFree ? .free : .orphaned,  // assume orphaned until claimed
                    owner: nil, chainIndex: nil
                )
            }
        }

        // Mark system sectors
        let systemKeys = getSystemSectors(format: format)
        for key in systemKeys {
            sectorMap[key]?.status = .system
            sectorMap[key]?.owner = "SYSTEM"
        }

        // Mark directory sectors
        let dirKeys = getDirectorySectors(bytes: bytes, format: format)
        for key in dirKeys {
            sectorMap[key]?.status = .system
            sectorMap[key]?.owner = "DIRECTORY"
        }

        // Walk file chains and mark sectors
        let files = parseDirectory(bytes: bytes, format: format)
        for file in files {
            var chain: [(track: Int, sector: Int)] = []
            var curTrack = file.track
            var curSector = file.sector
            var visited = Set<String>()
            var chainIdx = 1

            while curTrack != 0 {
                let key = "\(curTrack):\(curSector)"
                if visited.contains(key) { break }
                visited.insert(key)
                guard curTrack <= UInt8(format.totalTracks) else { break }
                let maxS = D64Parser.trackSectors(track: Int(curTrack), format: format)
                guard Int(curSector) < maxS else { break }

                chain.append((track: Int(curTrack), sector: Int(curSector)))
                sectorMap[key]?.status = .fileUsed
                sectorMap[key]?.owner = file.name
                sectorMap[key]?.chainIndex = chainIdx
                chainIdx += 1

                let s = D64Parser.offset(track: Int(curTrack), sector: Int(curSector), format: format)
                guard s + 2 <= bytes.count else { break }
                curTrack = bytes[s]
                curSector = bytes[s + 1]
            }
            fileChains.append(FileChain(name: file.name, sectors: chain))
        }

        return Result(format: format, sectorMap: sectorMap, fileChains: fileChains,
                      totalTracks: format.totalTracks, maxSectors: maxSec)
    }

    // MARK: - Helpers

    private struct FileEntry {
        let name: String
        let track: UInt8
        let sector: UInt8
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
                if bytes[base] == 0x00 { continue }
                let nameSlice = bytes[(base + 3)..<(base + 19)]
                let rawName = nameSlice.prefix(while: { $0 != 0xA0 && $0 != 0x00 })
                if rawName.allSatisfy({ $0 == 0x01 }) { continue }
                let name = D64Parser.petsciiToString(bytes[(base + 3)..<(base + 19)])
                if name.isEmpty { continue }
                files.append(FileEntry(name: name, track: bytes[base + 1], sector: bytes[base + 2]))
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
        case .d64: sectors.insert("18:0")
        case .d71: sectors.insert("18:0"); sectors.insert("53:0")
        case .d81: sectors.insert("40:0"); sectors.insert("40:1"); sectors.insert("40:2")
        }
        return sectors
    }
}

// MARK: - BAM Window

struct BAMViewWindow {
    static func open(document: D64Document) {
        guard let result = BAMAnalyzer.analyze(data: document.data) else { return }
        let disk = D64Parser.parse(data: document.data)
        let diskName = disk?.diskName ?? "DISK"

        let bamState = BAMViewState(result: result)
        let view = NSHostingController(rootView: BAMMapView(state: bamState, document: document))
        let window = NSWindow(contentViewController: view)
        window.title = "\(diskName.uppercased()) — BAM Map"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]

        // Size based on format — ensure enough width for labels and legend
        let cellSize: CGFloat = 14
        let gridWidth = CGFloat(result.maxSectors) * (cellSize + 1) + 50
        let width = max(gridWidth + 60, 500)
        let height = min(CGFloat(result.totalTracks) * (cellSize + 1) + 180, 700)
        window.setContentSize(NSSize(width: width, height: max(height, 350)))
        window.minSize = NSSize(width: 500, height: 300)
        window.center()

        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        objc_setAssociatedObject(window, "controller", controller, .OBJC_ASSOCIATION_RETAIN)
    }
}

// MARK: - BAM View State

class BAMViewState: ObservableObject {
    let result: BAMAnalyzer.Result
    @Published var selectedFile: String? = nil
    @Published var hoveredSector: String? = nil

    init(result: BAMAnalyzer.Result) {
        self.result = result
    }

    func sectorsForFile(_ name: String) -> Set<String> {
        guard let chain = result.fileChains.first(where: { $0.name == name }) else { return [] }
        return Set(chain.sectors.map { "\($0.track):\($0.sector)" })
    }
}

// MARK: - BAM Map View

struct BAMMapView: View {
    @ObservedObject var state: BAMViewState
    let document: D64Document
    private let monoFont = "C64 Pro Mono"
    private let cellSize: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // File selector
            fileSelector
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            // Hover info
            hoverInfo
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

            Divider()

            // BAM grid
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                VStack(alignment: .leading, spacing: 1) {
                    // Column headers (sector numbers)
                    HStack(spacing: 1) {
                        Text("T\\S")
                            .font(.custom(monoFont, size: 8))
                            .foregroundColor(Color.c64LightBlue)
                            .frame(width: 28, height: cellSize, alignment: .center)
                        ForEach(0..<state.result.maxSectors, id: \.self) { s in
                            Text("\(s)")
                                .font(.custom(monoFont, size: 7))
                                .foregroundColor(Color.c64LightBlue)
                                .frame(width: cellSize, height: cellSize, alignment: .center)
                        }
                    }

                    // Track rows
                    ForEach(1...state.result.totalTracks, id: \.self) { track in
                        trackRow(track: track)
                    }
                }
                .padding(8)
            }

            Divider()

            // Legend
            legend
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // ── File selector ──

    var fileSelector: some View {
        HStack(spacing: 8) {
            Text("FILE:")
                .font(.custom(monoFont, size: 11))
                .foregroundColor(Color.c64LightBlue)
                .fixedSize()

            Picker("", selection: $state.selectedFile) {
                Text("(none)").tag(String?.none)
                ForEach(state.result.fileChains, id: \.name) { chain in
                    Text("\(chain.name.uppercased()) (\(chain.sectors.count) sec)")
                        .tag(Optional(chain.name))
                }
            }
            .frame(minWidth: 200, maxWidth: 300)

            Spacer()

            if let name = state.selectedFile,
               let chain = state.result.fileChains.first(where: { $0.name == name }) {
                Text("\(chain.sectors.count) SECTORS")
                    .font(.custom(monoFont, size: 11))
                    .foregroundColor(Color.c64Blue)
                    .fixedSize()
            }
        }
        .lineLimit(1)
    }

    // ── Hover info ──

    var hoverInfo: some View {
        HStack {
            if let key = state.hoveredSector, let info = state.result.sectorMap[key] {
                Text(String(format: "T%d/S%d", info.track, info.sector))
                    .font(.custom(monoFont, size: 11))
                    .foregroundColor(Color.c64Blue)
                Text("—")
                    .font(.custom(monoFont, size: 11))
                    .foregroundColor(Color.c64LightBlue)
                Text(sectorDescription(info))
                    .font(.custom(monoFont, size: 11))
                    .foregroundColor(info.status.color)
            } else {
                Text("HOVER OVER A SECTOR FOR DETAILS")
                    .font(.custom(monoFont, size: 10))
                    .foregroundColor(Color.c64LightBlue.opacity(0.5))
            }
            Spacer()
        }
        .frame(height: 18)
    }

    func sectorDescription(_ info: SectorInfo) -> String {
        switch info.status {
        case .free: return "FREE"
        case .system: return info.owner ?? "SYSTEM"
        case .fileUsed:
            if let name = info.owner, let idx = info.chainIndex {
                return "\(name.uppercased()) [#\(idx)]"
            }
            return info.owner?.uppercased() ?? "USED"
        case .orphaned: return "ORPHANED (lost sector)"
        }
    }

    // ── Track row ──

    func trackRow(track: Int) -> some View {
        let numSectors = D64Parser.trackSectors(track: track, format: state.result.format)
        let selectedSectors = state.selectedFile.map { state.sectorsForFile($0) } ?? []

        return HStack(spacing: 1) {
            // Track number
            Text("\(track)")
                .font(.custom(monoFont, size: 8))
                .foregroundColor(Color.c64LightBlue)
                .frame(width: 28, height: cellSize, alignment: .trailing)

            // Sector cells
            ForEach(0..<state.result.maxSectors, id: \.self) { sector in
                if sector < numSectors {
                    let key = "\(track):\(sector)"
                    let info = state.result.sectorMap[key]
                    let isHighlighted = selectedSectors.contains(key)

                    sectorCell(key: key, info: info, isHighlighted: isHighlighted)
                } else {
                    // No sector here (track has fewer sectors)
                    Color.clear
                        .frame(width: cellSize, height: cellSize)
                }
            }
        }
    }

    // ── Single sector cell ──

    func sectorCell(key: String, info: SectorInfo?, isHighlighted: Bool) -> some View {
        let bgColor: Color
        if isHighlighted {
            bgColor = Color.orange
        } else {
            bgColor = info?.status.color ?? Color.gray.opacity(0.3)
        }

        let label: String
        if isHighlighted, let idx = info?.chainIndex {
            label = idx < 100 ? "\(idx)" : "·"
        } else {
            label = ""
        }

        return Text(label)
            .font(.system(size: 6, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .frame(width: cellSize, height: cellSize)
            .background(bgColor)
            .cornerRadius(2)
            .onHover { hovering in
                state.hoveredSector = hovering ? key : nil
            }
            .onTapGesture {
                // Open sector in hex editor
                openSectorHex(key: key)
            }
    }

    // ── Legend ──

    var legend: some View {
        HStack(spacing: 10) {
            legendItem(color: SectorStatus.free.color, label: "FREE")
            legendItem(color: SectorStatus.fileUsed.color, label: "FILE")
            legendItem(color: SectorStatus.system.color, label: "SYS")
            legendItem(color: SectorStatus.orphaned.color, label: "ORPHAN")
            legendItem(color: .orange, label: "SEL")
            Spacer()
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.custom(monoFont, size: 8))
                .foregroundColor(Color.c64LightBlue)
                .fixedSize()
        }
    }

    // ── Open sector hex editor ──

    func openSectorHex(key: String) {
        let parts = key.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return }
        let track = parts[0], sector = parts[1]
        guard let format = DiskFormat.detect(size: document.data.count) else { return }
        let offset = D64Parser.offset(track: track, sector: sector, format: format)
        guard offset + 256 <= document.data.count else { return }

        let sectorData = Data(document.data[offset..<offset + 256])
        let sectorFile = D64File(
            filename: String(format: "T%d/S%d", track, sector),
            fileType: "RAW",
            blocks: 1,
            track: UInt8(track),
            sector: UInt8(sector),
            rawData: sectorData
        )
        HexViewerWindow.open(file: sectorFile, document: document)
    }
}
