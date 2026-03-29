import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DiskExporter {

    // MARK: - Text Export

    static func exportAsText(data: Data) -> String? {
        guard let disk = D64Parser.parse(data: data) else { return nil }

        var lines: [String] = []

        // Header line
        lines.append("0 \"\(disk.diskName.uppercased())\" \(disk.diskID.uppercased()) \(disk.format.dosVersion)")
        lines.append("")

        // File entries
        for file in disk.files {
            let blocks = String(file.blocks).padding(toLength: 5, withPad: " ", startingAt: 0)
            let name = "\"\(file.filename.uppercased())\"".padding(toLength: 19, withPad: " ", startingAt: 0)
            lines.append("\(blocks)\(name)\(file.fileType)")
        }

        lines.append("")
        lines.append("\(disk.freeBlocks) BLOCKS FREE.")
        lines.append("")

        let usedBlocks   = disk.format.totalBlocks - disk.freeBlocks
        let usedPercent  = disk.format.totalBlocks > 0
            ? Int(Double(usedBlocks) / Double(disk.format.totalBlocks) * 100) : 0
        lines.append("FORMAT: \(disk.format.displayName)   FILES: \(disk.files.count)   USED: \(usedBlocks)/\(disk.format.totalBlocks) blocks (\(usedPercent)%)")
        lines.append("Exported by Disk Inspector")

        return lines.joined(separator: "\n")
    }

    // MARK: - HTML Export

    static func exportAsHTML(data: Data) -> String? {
        guard let disk = D64Parser.parse(data: data) else { return nil }

        let usedBlocks = disk.format.totalBlocks - disk.freeBlocks
        let usedPercent = disk.format.totalBlocks > 0
            ? Int(Double(usedBlocks) / Double(disk.format.totalBlocks) * 100)
            : 0

        var fileRows = ""
        for file in disk.files {
            let blocks = String(file.blocks).padding(toLength: 5, withPad: " ", startingAt: 0)
            fileRows += """
                <tr>
                    <td class="blocks">\(blocks)</td>
                    <td class="name">&quot;\(escapeHTML(file.filename.uppercased()))&quot;</td>
                    <td class="type">\(file.fileType)</td>
                </tr>\n
            """
        }

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <title>\(escapeHTML(disk.diskName.uppercased())) — Disk Inspector</title>
        <style>
            @font-face {
                font-family: 'C64';
                src: local('C64 Pro Mono');
            }
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body {
                background: #ffffff;
                color: #4338A0;
                font-family: 'C64', 'Courier New', monospace;
                font-size: 14px;
                padding: 24px;
                min-height: 100vh;
            }
            .container {
                max-width: 600px;
                margin: 0 auto;
                border: 2px solid #4338A0;
                border-radius: 8px;
                padding: 20px;
            }
            .header {
                background: #4338A0;
                color: #ffffff;
                padding: 8px 12px;
                margin: -20px -20px 16px -20px;
                border-radius: 6px 6px 0 0;
                font-size: 14px;
            }
            .header .id { color: #B0AADD; }
            table {
                width: 100%;
                border-collapse: collapse;
                margin: 8px 0;
            }
            tr:hover { background: #F0EEFF; }
            td { padding: 2px 0; white-space: pre; color: #4338A0; }
            .blocks { width: 50px; text-align: right; padding-right: 8px; }
            .name { color: #4338A0; }
            .type { color: #7B6DD0; padding-left: 4px; }
            .free-line {
                margin-top: 12px;
                padding-top: 8px;
                border-top: 1px solid #4338A0;
                color: #4338A0;
                font-size: 14px;
            }
            .bar-container {
                margin: 12px 0;
                background: #E8E6F4;
                border-radius: 4px;
                height: 12px;
                overflow: hidden;
            }
            .bar-fill {
                height: 100%;
                background: #4338A0;
                border-radius: 4px;
            }
            .info {
                margin-top: 16px;
                padding-top: 12px;
                border-top: 1px solid #CCCCCC;
                font-size: 11px;
                color: #999999;
            }
            .info span { color: #4338A0; }
            .footer {
                margin-top: 16px;
                font-size: 10px;
                color: #999999;
                text-align: center;
            }
            .footer a { color: #4338A0; text-decoration: none; }
            .footer a:hover { text-decoration: underline; }
        </style>
        </head>
        <body>
        <div class="container">
            <div class="header">
                0 &quot;\(escapeHTML(disk.diskName.uppercased()))&quot;
                <span class="id">\(escapeHTML(disk.diskID.uppercased())) \(disk.format.dosVersion)</span>
            </div>

            <table>
        \(fileRows)
            </table>

            <div class="free-line">\(disk.freeBlocks) BLOCKS FREE.</div>

            <div class="bar-container">
                <div class="bar-fill" style="width: \(usedPercent)%"></div>
            </div>

            <div class="info">
                <span>FORMAT:</span> \(disk.format.displayName) &nbsp;
                <span>FILES:</span> \(disk.files.count) &nbsp;
                <span>USED:</span> \(usedBlocks)/\(disk.format.totalBlocks) blocks (\(usedPercent)%)
            </div>

            <div class="footer">
                Exported by <a href="https://metesev.itch.io">Disk Inspector</a> &mdash; &copy; 2026 metesev
            </div>
        </div>
        </body>
        </html>
        """
    }

    // MARK: - Save Dialogs

    static func saveAsText(data: Data, diskName: String) {
        guard let text = exportAsText(data: data) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = diskName.lowercased() + ".txt"
        panel.allowedContentTypes = [.plainText]
        panel.message = "Export Directory Listing as Text"
        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func saveAsHTML(data: Data, diskName: String) {
        guard let html = exportAsHTML(data: data) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = diskName.lowercased() + ".html"
        panel.allowedContentTypes = [.html]
        panel.message = "Export Directory Listing as HTML"
        if panel.runModal() == .OK, let url = panel.url {
            try? html.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - PNG Export

    @MainActor
    static func saveAsPNG(data: Data, diskName: String) {
        guard let disk = D64Parser.parse(data: data) else { return }
        let view     = DirectoryPNGView(disk: disk)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        guard let image = renderer.nsImage,
              let tiff   = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png    = bitmap.representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = diskName.lowercased()
            .replacingOccurrences(of: " ", with: "_") + ".png"
        panel.allowedContentTypes = [.png]
        panel.message = "Export Directory Listing as PNG"
        if panel.runModal() == .OK, let url = panel.url {
            try? png.write(to: url)
        }
    }

    // MARK: - Helper

    private static func escapeHTML(_ string: String) -> String {
        string.replacingOccurrences(of: "&", with: "&amp;")
              .replacingOccurrences(of: "<", with: "&lt;")
              .replacingOccurrences(of: ">", with: "&gt;")
    }
}

// MARK: - Directory PNG View (private render target)

private struct DirectoryPNGView: View {
    let disk: D64Disk

    // Fixed light-mode C64 colors (not dynamic — PNG is for sharing)
    private let bg        = Color(red: 0.263, green: 0.216, blue: 0.631)
    private let textWhite = Color.white
    private let accent    = Color(red: 0.467, green: 0.427, blue: 0.816)
    private let fontSize: CGFloat  = 14
    // Fixed column widths — matches the app's main directory layout
    private let colBlocks: CGFloat = 56
    private let colName:   CGFloat = 308
    private let colType:   CGFloat = 42
    private let hPad:      CGFloat = 24

    private var contentWidth: CGFloat { colBlocks + colName + colType }

    private var usedBlocks:  Int { disk.format.totalBlocks - disk.freeBlocks }
    private var usedPercent: Int {
        disk.format.totalBlocks > 0
            ? Int(Double(usedBlocks) / Double(disk.format.totalBlocks) * 100) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Disk header — reversed video (light bg, dark text) ──
            HStack(spacing: 0) {
                Text(" 0   ")
                    .foregroundColor(bg)
                Text("\"\(disk.diskName.uppercased())\" \(disk.diskID.uppercased())")
                    .foregroundColor(bg)
                if !disk.format.dosVersion.isEmpty {
                    Text(" \(disk.format.dosVersion)")
                        .foregroundColor(bg)
                }
                Spacer(minLength: 0)
            }
            .font(.custom("C64 Pro Mono", size: fontSize))
            .frame(width: contentWidth)
            .padding(.vertical, 2)
            .background(accent)
            .padding(.bottom, 4)

            // ── File entries — fixed column widths prevent any wrapping ──
            ForEach(disk.files) { file in
                HStack(spacing: 0) {
                    Text(String(file.blocks).padding(toLength: 4, withPad: " ", startingAt: 0))
                        .foregroundColor(accent)
                        .frame(width: colBlocks, alignment: .leading)
                    Text("\"\(file.filename.uppercased())\"")
                        .foregroundColor(textWhite)
                        .frame(width: colName, alignment: .leading)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(file.fileType)
                        .foregroundColor(accent)
                        .frame(width: colType, alignment: .leading)
                }
                .font(.custom("C64 Pro Mono", size: fontSize))
            }

            Spacer().frame(height: 4)

            // ── Blocks free ──
            if !disk.format.isArchive {
                Text("\(disk.freeBlocks) BLOCKS FREE.")
                    .font(.custom("C64 Pro Mono", size: fontSize))
                    .foregroundColor(textWhite)
                    .frame(width: contentWidth, alignment: .leading)
            }

            Spacer().frame(height: 10)

            // ── Info line (matches HTML export) ──
            Text("FORMAT: \(disk.format.displayName)   FILES: \(disk.files.count)   USED: \(usedBlocks)/\(disk.format.totalBlocks) blocks (\(usedPercent)%)")
                .font(.custom("C64 Pro Mono", size: 10))
                .foregroundColor(accent)
                .frame(width: contentWidth, alignment: .leading)
                .lineLimit(1)

            Spacer().frame(height: 4)

            // ── Watermark ──
            Text("Exported by Disk Inspector")
                .font(.custom("C64 Pro Mono", size: 10))
                .foregroundColor(accent.opacity(0.55))
                .frame(width: contentWidth, alignment: .trailing)
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 20)
        .background(bg)
        .frame(width: contentWidth + hPad * 2)
    }
}
