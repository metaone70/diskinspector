# Disk Inspector v1.6

**A Commodore 64/128 disk image editor for macOS**

By metesev — (https://metesev.itch.io)

---

## Installation

Drag **Disk Inspector.app** to your **Applications** folder.

## Supported Formats

| Format | Type | Access |
|--------|------|--------|
| D64 | 1541 single-sided (170 KB, 35 tracks) | Read / Write |
| D71 | 1571 double-sided (340 KB, 70 tracks) | Read / Write |
| D81 | 1581 (800 KB, 80 tracks) | Read / Write |
| T64 | C64S tape archive | Read only |
| LNX | Lynx archive | Read only |
| G64 | Raw GCR disk image (VICE format) | Read only |
| NIB | Raw GCR disk image (NibTools/MNIB format) | Read only |
| P00/S00 | PC64 container (PRG/SEQ/USR/REL) | Read only |

## Features

- View and edit Commodore disk images with authentic C64 styling
- Copy, move, rename, and delete files between disk images
- Drag and drop files between multiple open disk windows
- **Import files from Mac** — drag from Finder or use right-click → Import from Mac…
- **Batch export** — export all files to a Mac folder at once (right-click → Export All to Mac…)
- **6510 disassembler** — view full machine code listing with addresses and mnemonics (right-click → View Disassembly on PRG files)
- **SEQ/USR viewer** — view sequential text files with PETSCII decoding (double-click or right-click → View SEQ)
- **BASIC viewer** — BASIC v2.0 and v7.0 detokenizer (double-click a BASIC PRG)
- **Hex editor** — direct byte editing, saves back to disk; addresses shown in C64 memory map for PRG files
- Visual BAM map with sector-level view (including G64/NIB)
- Disk integrity validation (including G64/NIB)
- Separator library with 17 built-in PETSCII patterns, drag-and-drop, and custom separator support
- **File type change** — right-click any file → Change Type to switch between PRG / SEQ / USR / REL
- **Lock / Splat flags** — right-click → Lock/Unlock (protected bit, shown as `<`) and Mark/Clear Splat (closed bit, shown as `*` prefix)
- **Fix Block Count** — right-click → Fix Block Count recalculates block count by walking the actual sector chain
- **Sort directory** — ↕ SORT toolbar button sorts by Name, Type, or Blocks (ascending or descending)
- **Export directory listing** as plain text, styled HTML, or PNG image (C64-styled, 2× retina, suitable for itch.io/social sharing)
- **Sector Chain Viewer** — right-click any file → View Sector Chain… to inspect the full T/S link chain with byte counts per sector
- **Recover deleted files** — ♻ RECOVER toolbar button finds scratched files whose data is still on disk and restores them with one click
- **Quick Look preview** — press Space on any .d64, .d71, .d81, or .t64 file in Finder for an instant directory listing (no need to open the app)
- **Clone Disk** — File menu → Clone Disk… saves an independent copy without closing or modifying the original
- **Import from Folder** — Tools menu → Import from Folder… imports all .prg/.seq/.usr/.rel and P00/S00 files from a Mac folder at once
- **P00/S00 support** — PC64 container files (.P00, .S00, .U00, .R00) imported correctly using the embedded C64 filename
- Launch disks and files directly in VICE emulator
- Track Map archivist view for G64/NIB: per-track GCR analysis, error counts, copy-protection indicators

## VICE Integration

To use the VICE emulator integration:
1. Go to **Disk Inspector → VICE Settings**
2. Browse to your x64sc and x128 binaries
3. Right-click any file → **Run File in VICE** or **Open Disk in VICE**
4. Or use **Cmd-R** / **Cmd-Shift-R** to launch the selected file directly

> G64 files are passed to VICE directly. MNIB/NIB files are automatically converted to D64 before launching.

## Separator Library

Insert decorative PETSCII separator lines into your disk directory:
1. Go to **Tools → Separators** (or press **Cmd-Shift-L**)
2. Browse built-in patterns (lines, borders, blocks, decorative)
3. Double-click or press **Insert** to add to the disk
4. Create your own custom separators with the **New…** button

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| Cmd-C | Copy selected files |
| Cmd-V | Paste files |
| Cmd-A | Select all files |
| Cmd-Z | Undo |
| Cmd-Shift-Z | Redo |
| Cmd-S | Save |
| Cmd-Shift-S | Save As |
| Cmd-R | Run selected file in C64 VICE |
| Cmd-Shift-R | Run selected file in C128 VICE |
| Cmd-Shift-L | Open Separator Library |
| Up/Down Arrow | Navigate directory listing |
| Shift+Arrow | Extend selection up/down |
| Cmd+Up / Cmd+Down | Move selected file up/down in directory |
| Delete | Delete selected files |
| Double-click | View file (BASIC → SEQ → Hex, in order) |

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon or Intel Mac

## Credits

© 2026 metesev
https://metesev.itch.io
