import SwiftUI
import AppKit

// MARK: - Sector Chain Entry

struct SectorChainEntry: Identifiable {
    let id = UUID()
    let index: Int
    let track: UInt8
    let sector: UInt8
    let nextTrack: UInt8
    let nextSector: UInt8
    var isEnd: Bool { nextTrack == 0 }
    var bytesUsed: Int { isEnd ? max(0, Int(nextSector) - 1) : 254 }
}

// MARK: - Sector Chain View

struct SectorChainView: View {
    let file: D64File
    let data: Data
    let format: DiskFormat

    private let monoFont = "C64 Pro Mono"

    var chain: [SectorChainEntry] {
        var entries: [SectorChainEntry] = []
        var curTrack  = file.track
        var curSector = file.sector
        var visited   = Set<String>()
        let bytes     = [UInt8](data)

        while curTrack != 0 {
            let key = "\(curTrack):\(curSector)"
            if visited.contains(key) { break }
            visited.insert(key)

            let off = D64Parser.offset(track: Int(curTrack), sector: Int(curSector), format: format)
            guard off + 2 <= bytes.count else { break }
            let nt = bytes[off]
            let ns = bytes[off + 1]

            entries.append(SectorChainEntry(
                index: entries.count,
                track: curTrack, sector: curSector,
                nextTrack: nt, nextSector: ns
            ))
            curTrack  = nt
            curSector = ns
        }
        return entries
    }

    var totalBytes: Int { chain.reduce(0) { $0 + $1.bytesUsed } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("CHAIN: \"\(file.filename.uppercased())\" \(file.fileType)")
                    .font(.custom(monoFont, size: 14))
                    .foregroundColor(Color.c64Blue)
                Spacer()
                Text("\(chain.count) SECTOR\(chain.count == 1 ? "" : "S"), \(totalBytes) BYTES")
                    .font(.custom(monoFont, size: 11))
                    .foregroundColor(Color.c64LightBlue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Column headers
            HStack(spacing: 0) {
                Text("#").frame(width: 44, alignment: .leading)
                Text("SECTOR").frame(width: 100, alignment: .leading)
                Text("→ NEXT").frame(width: 100, alignment: .leading)
                Text("BYTES").frame(width: 64, alignment: .leading)
                Spacer()
            }
            .font(.custom(monoFont, size: 10))
            .foregroundColor(Color.c64LightBlue)
            .padding(.horizontal, 16)
            .padding(.vertical, 5)

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if chain.isEmpty {
                        Text("No sector chain (file starts at T0/S0)")
                            .font(.custom(monoFont, size: 12))
                            .foregroundColor(Color.c64LightBlue)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(chain) { entry in
                            HStack(spacing: 0) {
                                Text("\(entry.index)")
                                    .frame(width: 44, alignment: .leading)
                                    .lineLimit(1)
                                Text("T\(entry.track)/S\(entry.sector)")
                                    .frame(width: 100, alignment: .leading)
                                    .lineLimit(1)
                                if entry.isEnd {
                                    Text("EOF")
                                        .frame(width: 100, alignment: .leading)
                                        .foregroundColor(Color.c64LightBlue)
                                        .lineLimit(1)
                                } else {
                                    Text("T\(entry.nextTrack)/S\(entry.nextSector)")
                                        .frame(width: 100, alignment: .leading)
                                        .lineLimit(1)
                                }
                                Text("\(entry.bytesUsed)")
                                    .frame(width: 64, alignment: .leading)
                                    .lineLimit(1)
                                if entry.isEnd {
                                    Text("← last sector")
                                        .foregroundColor(Color.c64LightBlue)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .lineLimit(1)
                                } else {
                                    Spacer()
                                }
                            }
                            .font(.custom(monoFont, size: 12))
                            .foregroundColor(Color.c64Blue)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 3)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(minWidth: 420, minHeight: 200)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Window

struct SectorChainWindow {
    static func open(file: D64File, data: Data, format: DiskFormat) {
        let view       = SectorChainView(file: file, data: data, format: format)
        let hosting    = NSHostingController(rootView: view)
        let window     = NSWindow(contentViewController: hosting)
        window.title   = "Sector Chain: \"\(file.filename.uppercased())\""
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 520, height: 380))
        window.minSize = NSSize(width: 460, height: 200)
        window.center()
        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        objc_setAssociatedObject(window, "sectorChainController", controller, .OBJC_ASSOCIATION_RETAIN)
    }
}
