# Changelog

## v1.3

### New Features
- Separator library with 17 built-in PETSCII patterns (frames, lines, decorative)
- Custom separator support with persistent storage
- Separator library accessible via Tools menu (Cmd-Shift-L)
- Drag and drop separators from library into directory
- Insert separators after the currently selected file
- Keyboard shortcut Cmd-R to run selected file in C64 VICE (x64sc)
- Keyboard shortcut Cmd-Shift-R to run selected file in C128 VICE (x128)
- Arrow key navigation in directory listing (Shift+Arrow for multi-select)
- Tighter directory line spacing for authentic C64 screen look

### Bug Fixes
- Disabled auto-save — changes are only written to disk via explicit Save (Cmd-S) or Save As (Cmd-Shift-S)
- Fixed separator library inserting into wrong window when multiple disks are open
- Fixed renaming PETSCII separator files corrupting the first characters (UTF-8 vs PETSCII encoding)
- Fixed renaming always targeting the first match when multiple identical files exist (now uses directory index)
- Fixed rename cursor being invisible on dark blue background (white insertion point and selection highlight)
- Fixed disk rename double-click focusing the ID field instead of the name field

## v1.2

- Fixed D64 files appearing greyed out in the Open dialog on systems where another app (e.g. VICE) had already registered a UTType for .d64/.d71/.d81 extensions

## v1.1

- Fixed file export always using .prg extension — now uses the actual file type (SEQ, USR, REL, etc.)
- Fixed D81 format description from "C128 Disk Image" to "1581 Disk Image" in system type declarations
- Preserved locked and splat file-type flags when copying files between disks
- Unified sectors-per-track logic to use a single canonical function across all code paths
- Fixed hex editor arrow key navigation to stay in sync with the configured row width
- Aligned validation window minimum size with its view constraints
- Removed deprecated UserDefaults.synchronize() calls
- Removed leftover debug print() statements from VICE launcher
- Removed unused D71/D81 clipboard type declarations
- Build script now includes version number in DMG filename

## v1.0

- Initial release
- D64, D71, and D81 disk image support
- File operations: copy, move, rename, delete, import, export
- Hex editor with direct byte editing
- BASIC listing viewer (v2.0 and v7.0 detokenizer)
- Visual BAM map with sector-level view
- Disk integrity validation
- Directory export as text and styled HTML
- VICE emulator integration
- Drag and drop between multiple open disks
