# GearTree AI Handoff

This file is for another AI assistant picking up Tru's GearTree work.

## Project

GearTree is a Windower addon in:

`C:\Program Files (x86)\Windower\addons\GearTree`

Safe working copy used by Codex:

`C:\Users\Mark-PC\Documents\GearTree_editor_work`

The user wants a practical in-game GearSwap set browser/editor. Keep real Lua
file edits safe and backed up. Do not rewrite or reorganize the user's actual
job Lua unless explicitly asked.

## Current Core Behavior

- GearTree parses the current GearSwap job Lua as text.
- The tree follows the order sets first appear in the Lua.
- Preview panel shows semantic set info from `semantics.lua`, Lua path, source
  file/line, inheritance or references, confidence, evidence, and the gear list.
- Tree mode is persisted in settings as `tree_mode`, with `raw` as default.
  `//gt mode organized` builds an organized display tree from
  `organized_tree.lua`; leaves keep the original Lua set path/assignment for
  equip, preview, and save.
- Clicking/equipping a set captures a baseline equipment snapshot.
- `//gt save` compares current equipment to the baseline and patches only
  changed slots in the selected set.
- Saves create backups under `addons/GearTree/data/backups/`, then reparse and
  run `gs reload`.
- Augmented gear is written as `{ name="Item", augments={...} }`.

## Current Patch State

The current working copy includes:

- Better text UI: cleaner header, footer/status line, stronger selected row,
  and last-save footer.
- `//gt help` listing the current commands.
- `//gt find <text>`.
- Remembering the last saved set after reload and highlighting it with `*`.
- `//gt last`.
- `//gt undo` with no confirmation, restoring the most recent save backup.
- Virtual UI layout folders that do not change the Lua:
  - `//gt make Attack`
  - `//gt make Attack root`
  - `//gt move TP to Attack`
  - `//gt move here`
  - `//gt move up/down/top/bottom`
  - `//gt move TP up/down/top/bottom`
  - `//gt rename Accuracy`
  - `//gt rename Attack to Accuracy`
  - `//gt remove [folder]`
  - `//gt unmove [set]`
  - `//gt layout reset`

Still future work:

- Future smart preview usage/condition notes could scan actual Lua resolver
  logic, such as `buffactive['Sneak Attack']`. Current preview metadata is
  best-effort naming inference in `semantics.lua`.

Rules for virtual layouts:

- Lua sets can move/reorder in the UI but cannot be removed.
- `remove` only removes virtual folders.
- Removing a virtual folder returns moved Lua children to their original Lua
  order/location.
- `layout reset` returns everything to Lua order.
- `//gt save` always targets the original Lua set path, even if displayed inside
  a virtual folder.

## Later Visual Pass

After this patch, the user wants a more legit graphical skin using Windower
`images`, similar to XivParty:

- Add `assets/` PNGs for panel backgrounds, title/footer bars, selected row,
  folder/set icons, preview frame, and small status indicators.
- Keep text as labels over image primitives.

## Safety Notes

- Work in the Documents working copy first.
- Use `apply_patch` for edits.
- Installing to `C:\Program Files (x86)\Windower\addons\GearTree` requires
  elevated copy approval in Codex.
- Make a backup folder in Documents before copying installed files.
- Do not use destructive git/file commands.
