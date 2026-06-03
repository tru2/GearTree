# Changelog

## 0.4.1

### Added

- Click Lock support to prevent mouse clicks from passing through to FFXI while interacting with GearTree.

### Changed

- Click Lock now defaults on for new installs.
- Shift Mode now defaults on for new installs so normal arrow keys remain available to FFXI unless Shift is held.

### Notes

- Existing users may need to manually enable the new defaults with `//gt clicklock on` and `//gt shift on` because existing settings files preserve previous values.

---

## 0.4.0

### Added

- Mouse navigation and interaction support.
- Visual cursor overlay for easier mouse navigation.
- Personal notes for gear sets and folders.
- Virtual folders and custom display organization.
- Source-file navigation for jumping to the selected set in the Lua file.
- UI opacity controls.
- Whole-addon UI scaling controls.
- Shift+Arrow navigation mode for users who want to reserve normal arrow keys for FFXI.
- Expanded help system with separate player and developer help.

### Improved

- Major UI refresh with updated theme visuals and cleaner panel layout.
- Organized Tree view improved with clearer gameplay-focused categories.
- Improved gear comparison and status display.
- Improved inventory and wardrobe location detection.
- Improved save workflow for writing equipped gear back into GearSwap sets.
- Improved preview panels and information presentation.
- Improved keyboard navigation throughout the addon.
- Improved command organization and help documentation.
- Improved theme asset handling and UI consistency.
- Improved layout persistence and customization options.

### Saving & Safety

- Automatic backup creation before every successful write.
- Undo support for restoring the most recent GearTree save.
- Improved write validation and safety checks.
- Improved handling of unsupported set structures.

### Notes & Organization

- Added note support for both gear sets and folders.
- Added custom folder creation and management.
- Added item movement, reordering, renaming, and layout management tools.
- Added layout reset functionality.

### GearSwap Integration

- Improved GearSwap file parsing.
- Improved support for common GearSwap assignment patterns.
- Improved set detection and navigation.
- Improved reload and refresh workflows after saves.

### Fixes

- Numerous UI alignment and navigation fixes.
- Multiple tree navigation fixes.
- Multiple save and reload workflow fixes.
- Various parser, writer, and display fixes.
- General stability and usability improvements throughout the addon.

## 0.3.0 - Release Candidate

- First public release candidate.

## 0.2.x

- Development builds leading up to the first public release candidate.
