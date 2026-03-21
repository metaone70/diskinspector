import Foundation
import Combine

class D64Clipboard: ObservableObject {
    static let shared = D64Clipboard()
    private init() {}

    @Published private(set) var files: [D64File] = []

    /// Files staged for the current drag operation (separate from Copy/Paste)
    private(set) var draggedFiles: [D64File] = []

    var isEmpty: Bool { files.isEmpty }

    func copy(_ files: [D64File]) {
        self.files = files
    }

    func paste() -> [D64File] {
        return files
    }

    func stageDrag(_ files: [D64File]) {
        draggedFiles = files
    }

    /// Return staged files without clearing — the drop handler may be called
    /// multiple times (outer + per-row) for the same drag operation.
    func peekDrag() -> [D64File] {
        return draggedFiles
    }

    func endDrag() {
        draggedFiles = []
    }
}
