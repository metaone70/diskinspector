# Changelog

## v1.4

### New Features
- Support for opening T64 tape archive and LNX Lynx archive files (read-only)
- Support for opening G64 raw GCR disk images (VICE format) — read-only, directory listing + Track Map view
- Support for opening NIB raw GCR disk images (NibTools/MNIB format) — read-only, directory listing + Track Map view
- Track Map archivist view for G64/NIB: per-track sector count, checksum errors, sync count, raw GCR length, and copy-protection indicators (▤ TRACKS button)
- BAM map and disk validation available for G64/NIB images (operates on the decoded virtual D64)
- Free blocks count shown for G64/NIB images
- G64/NIB disks can be launched in VICE directly from the context menu; MNIB files are automatically converted to D64 for VICE compatibility


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
