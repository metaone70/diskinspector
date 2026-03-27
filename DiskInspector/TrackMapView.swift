import SwiftUI
import AppKit

// MARK: - Track Map Window

struct TrackMapWindow {
    static func open(disk: D64Disk) {
        guard let tracks = disk.rawTracks else { return }
        let view       = NSHostingController(rootView: TrackMapView(diskName: disk.diskName, format: disk.format, tracks: tracks))
        let window     = NSWindow(contentViewController: view)
        window.title   = "Track Map — \(disk.diskName.uppercased())"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 560, height: 560))
        window.minSize = NSSize(width: 480, height: 380)
        window.center()
        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        objc_setAssociatedObject(window, "controller", controller, .OBJC_ASSOCIATION_RETAIN)
    }
}

// MARK: - Track Map View

struct TrackMapView: View {
    let diskName: String
    let format:   DiskFormat
    let tracks:   [GCRTrackInfo]

    private let monoFont    = "C64 Pro Mono"
    private let headerSize: CGFloat = 12
    private let rowSize:    CGFloat = 10

    // Only full-numbered tracks for the main list
    private var fullTracks: [GCRTrackInfo] {
        tracks.filter { !$0.isHalfTrack }
    }
    private var halfTrackCount: Int {
        tracks.filter { $0.isHalfTrack && $0.hasData }.count
    }

    // Summary counts
    private var cleanCount:     Int { fullTracks.filter { $0.status == .clean }.count }
    private var errorCount:     Int { fullTracks.filter { $0.status == .errors }.count }
    private var missingSectors: Int { fullTracks.filter { $0.status == .noSectors }.count }
    private var totalErrors:    Int { fullTracks.reduce(0) { $0 + $1.headerErrors + $1.dataErrors } }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            columnHeaders
            Divider()
            trackList
            Divider()
            summaryBar
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text("TRACK MAP")
                .font(.custom(monoFont, size: headerSize))
                .foregroundColor(Color.c64Blue)
            Spacer()
            Text(format.displayName)
                .font(.custom(monoFont, size: headerSize))
                .foregroundColor(Color.c64LightBlue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Column headers

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("TRK")
                .frame(width: 40, alignment: .center)
            Text("STATUS")
                .frame(width: 70, alignment: .center)
            Text("SECTORS")
                .frame(width: 70, alignment: .center)
            Text("ERRORS")
                .frame(width: 60, alignment: .center)
            Text("SYNCS")
                .frame(width: 55, alignment: .center)
            Text("GCR BYTES")
                .frame(width: 85, alignment: .trailing)
            Text("NOTES")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
        }
        .font(.custom(monoFont, size: 9))
        .foregroundColor(Color.c64LightBlue)
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(Color.c64Blue.opacity(0.08))
    }

    // MARK: - Track rows

    private var trackList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(fullTracks.enumerated()), id: \.offset) { _, info in
                    trackRow(info)
                    if Int(info.trackNumber) % 5 == 0 {
                        Divider().opacity(0.3)
                    }
                }
            }
        }
    }

    private func trackRow(_ info: GCRTrackInfo) -> some View {
        let isDir    = Int(info.trackNumber) == 18
        let errTotal = info.headerErrors + info.dataErrors

        return HStack(spacing: 0) {
            // Track number
            Text(String(format: "%2d", Int(info.trackNumber)))
                .frame(width: 40, alignment: .center)

            // Status badge
            HStack(spacing: 4) {
                Circle()
                    .fill(info.hasData ? info.status.color : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
                Text(info.hasData ? info.status.label : "   ")
                    .frame(width: 32, alignment: .leading)
            }
            .frame(width: 70, alignment: .center)

            // Sectors found / expected
            Group {
                if info.hasData && info.sectorsExpected > 0 {
                    Text("\(info.sectorsFound)/\(info.sectorsExpected)")
                        .foregroundColor(info.sectorsFound == info.sectorsExpected ? .primary : .orange)
                } else if !info.hasData {
                    Text("—")
                        .foregroundColor(.secondary)
                } else {
                    Text("\(info.sectorsFound)")
                }
            }
            .frame(width: 70, alignment: .center)

            // Errors
            Group {
                if errTotal > 0 {
                    Text("\(errTotal)")
                        .foregroundColor(.yellow)
                } else {
                    Text(info.hasData ? "0" : "—")
                        .foregroundColor(info.hasData ? .secondary : .secondary)
                }
            }
            .frame(width: 60, alignment: .center)

            // Sync count
            Text(info.hasData ? "\(info.syncCount)" : "—")
                .foregroundColor(.secondary)
                .frame(width: 55, alignment: .center)

            // Raw GCR bytes
            Text(info.hasData ? "\(info.rawLength)" : "—")
                .foregroundColor(.secondary)
                .frame(width: 85, alignment: .trailing)

            // Notes
            HStack(spacing: 4) {
                if isDir { noteTag("DIR", color: Color.c64LightBlue) }
                if errTotal > 0 && info.sectorsFound > 0 { noteTag("PROT?", color: .yellow) }
                if info.sectorsFound < info.sectorsExpected && info.hasData && info.sectorsFound > 0 {
                    noteTag("PART", color: .orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 10)
        }
        .font(.custom(monoFont, size: rowSize))
        .foregroundColor(.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
        .background(isDir ? Color.c64Blue.opacity(0.07) : Color.clear)
    }

    private func noteTag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.custom(monoFont, size: 8))
            .foregroundColor(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(color.opacity(0.6), lineWidth: 0.5))
    }

    // MARK: - Summary bar

    private var summaryBar: some View {
        HStack(spacing: 20) {
            summaryItem("TRACKS", "\(fullTracks.count)", color: .primary)
            summaryItem("CLEAN", "\(cleanCount)", color: Color.green.opacity(0.8))
            summaryItem("ERRORS", "\(errorCount)", color: errorCount > 0 ? .yellow : .secondary)
            summaryItem("TOTAL ERR", "\(totalErrors)", color: totalErrors > 0 ? .orange : .secondary)
            if halfTrackCount > 0 {
                summaryItem("HALF-TRACKS", "\(halfTrackCount)", color: Color.c64LightBlue)
            }
            Spacer()
            legendKey()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.c64Blue.opacity(0.06))
    }

    private func summaryItem(_ label: String, _ value: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.custom(monoFont, size: 13))
                .foregroundColor(color)
            Text(label)
                .font(.custom(monoFont, size: 8))
                .foregroundColor(.secondary)
        }
    }

    private func legendKey() -> some View {
        HStack(spacing: 10) {
            ForEach([
                (GCRTrackStatus.clean,     "CLEAN"),
                (.errors,                  "ERR/PROT"),
                (.noSectors,               "EMPTY"),
                (.noData,                  "NO DATA"),
            ], id: \.1) { status, label in
                HStack(spacing: 3) {
                    Circle().fill(status.color).frame(width: 6, height: 6)
                    Text(label)
                        .font(.custom(monoFont, size: 7))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
