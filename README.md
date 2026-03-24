# Disk Inspector v1.3

**A Commodore 64/128 disk image editor for macOS**

By metesev — (https://metesev.itch.io)

---

## Installation

Drag **Disk Inspector.app** to your **Applications** folder.

## Supported Formats

- **D64** — 1541 single-sided (170 KB, 35 tracks)
- **D71** — 1571 double-sided (340 KB, 70 tracks)
- **D81** — 1581 (800 KB, 80 tracks)

## Features

- View and edit Commodore disk images with authentic C64 styling
- Tighter directory line spacing for authentic C64 screen look
- Copy, move, rename, and delete files between disk images
- Drag and drop files between multiple open disks
- Hex editor with direct byte editing and save to disk
- BASIC listing viewer (v2.0 and v7.0 detokenizer)
- Visual BAM map with sector-level view
- Separator library with 17 built-in PETSCII patterns, drag-and-drop, and custom separator support
- Disk integrity validation
- Export directory as text or styled HTML
- Launch disks and files directly in VICE emulator with keyboard shortcuts
- Import/export files to and from Mac filesystem

## VICE Integration

To use the VICE emulator integration:
1. Go to **Disk Inspector → VICE Settings**
2. Browse to your x64sc and x128 binaries
3. Right-click any file → **Run File in VICE** or **Open Disk in VICE**
4. Or use **Cmd-R** / **Cmd-Shift-R** to launch the selected file directly

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
| Delete | Delete selected files |
| Double-click | View file (BASIC or Hex) |

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon or Intel Mac

## Credits

© 2026 metesev
https://metesev.itch.io
