import SwiftUI
import AppKit

// MARK: - SEQ Viewer Window

struct SEQViewerWindow {

    static func canOpen(file: D64File) -> Bool {
        file.fileType == "SEQ" || file.fileType == "USR"
    }

    /// Try to open as SEQ/USR text; returns false if not that file type
    static func tryOpen(file: D64File) -> Bool {
        guard canOpen(file: file) else { return false }
        open(file: file)
        return true
    }

    static func open(file: D64File) {
        let text = petsciiToText(file.rawData)
        let lineCount = text.components(separatedBy: "\n").count
        let view = NSHostingController(rootView: SEQListingView(file: file, text: text, lineCount: lineCount))
        let window = NSWindow(contentViewController: view)
        window.title = "\(file.filename.uppercased()) — \(file.fileType)"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        let height = min(CGFloat(lineCount) * 18 + 120, 600)
        window.setContentSize(NSSize(width: 520, height: max(height, 250)))
        window.minSize = NSSize(width: 320, height: 200)
        window.center()
        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        objc_setAssociatedObject(window, "controller", controller, .OBJC_ASSOCIATION_RETAIN)
    }

    // MARK: - PETSCII → Text

    /// Convert PETSCII bytes to a displayable Unicode string.
    /// $0D/$8D = RETURN (newline), $C1–$DA = uppercase A–Z, $20–$7E = direct ASCII.
    private static func petsciiToText(_ data: Data) -> String {
        var result = ""
        result.reserveCapacity(data.count)
        for byte in data {
            switch byte {
            case 0x0D, 0x8D:
                result.append("\n")
            case 0x0A:
                result.append("\n")
            case 0x20...0x7E:
                result.append(Character(UnicodeScalar(byte)))
            case 0xC1...0xDA:
                result.append(Character(UnicodeScalar(byte - 0xC1 + 0x41)))
            default:
                result.append("·")
            }
        }
        return result
    }
}

// MARK: - SEQ Listing View

struct SEQListingView: View {
    let file: D64File
    let text: String
    let lineCount: Int
    private let monoFont = "C64 Pro Mono"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 24) {
                headerItem(label: "FILE", value: file.filename.uppercased())
                headerItem(label: "TYPE", value: file.fileType)
                headerItem(label: "LINES", value: "\(lineCount)")
                headerItem(label: "SIZE", value: "\(file.rawData.count) BYTES")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            ScrollView([.vertical, .horizontal], showsIndicators: true) {
                Text(text)
                    .font(.custom(monoFont, size: 13))
                    .foregroundColor(Color.c64Blue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(minWidth: 320, minHeight: 200)
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
}
