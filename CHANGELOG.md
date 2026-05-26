# Changelog

## 0.3.0 - Release Candidate

### Added

- Organized tree view for friendlier browsing of common GearSwap set patterns.
- Raw Lua tree mode for debugging exact Lua structure.
- Gear preview cards with Summary, Gear, Changes, and Data tabs.
- Source path and source-line visibility for parsed sets.
- `//gt open` support to jump near the selected Lua set in an editor/default app.
- `//gt save` workflow for saving changed equipped slots back into the highlighted set.
- `//gt saveslot <slot>` for force-saving one equipped slot.
- `//gt undo` for restoring the most recent GearTree save backup.
- Personal notes on gear sets, categories, and virtual folders.
- `== Notes ==` section in Summary/category previews.
- Simple augment tags in the Gear tab:
  - `[aug]` when Lua explicitly lists augments.
  - `[aug?]` when Lua does not list augments but GearTree finds an augmented copy.
- Virtual display folders with make, move, rename, remove, unmove, and layout reset commands.
- Find command for jumping to matching sets, folders, or gear lines.
- In-game help updates for notes and newer commands.

### Changed

- Organized tree is now the default display mode.
- Backup retention is limited to the latest 5 backups per Lua file.
- Augment display was intentionally kept simple and reliable; rank/path labels are not shown.
- README updated for public release preparation.

### Safety / Limitations

- GearTree only writes when a save command is explicitly run.
- GearTree creates a backup before each successful write.
- Unsupported or dynamic set shapes are refused instead of guessed.
- If Lua does not specify augments, GearTree cannot know which augmented copy was intended.
- GearTree parses Lua as text and does not execute GearSwap logic.

## 0.2.x

- Development builds leading up to the first public release candidate.
