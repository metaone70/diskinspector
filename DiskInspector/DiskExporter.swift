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

        // Summary
        lines.append("--- Disk Inspector Export ---")
        lines.append("Format:     \(disk.format.displayName)")
        lines.append("Files:      \(disk.files.count)")
        lines.append("Used:       \(disk.format.totalBlocks - disk.freeBlocks) blocks")
        lines.append("Free:       \(disk.freeBlocks) blocks")

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

    // MARK: - Helper

    private static func escapeHTML(_ string: String) -> String {
        string.replacingOccurrences(of: "&", with: "&amp;")
              .replacingOccurrences(of: "<", with: "&lt;")
              .replacingOccurrences(of: ">", with: "&gt;")
    }
}
