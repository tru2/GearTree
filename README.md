# GearTree

A Windower addon that gives you a clickable, expandable tree of every gear set
in your Gearswap user file. Left-click a set to equip it. Right-click to see
what's in it. You can also equip a set from GearTree, change gear in game, then
save the changed slots back into that set.

Sets are shown in the same order they first appear in your Lua file. You can
switch between the raw Lua tree and an organized tree that groups sets into
friendlier folders. The preview pane always shows the original Lua path plus the
source file and line number for each set.

## Install

1. Copy the whole `GearTree` folder into `Windower4/addons/`.
2. In FFXI: `//lua load GearTree`
3. The window opens at position (100, 100). Drag the title bar to move it.

If your gear file isn't auto-detected, point at it explicitly:
```
//gt load D:\Windower4\addons\GearSwap\data\Mogwa\Mogwa_Thf_Gear.lua
```

## Controls

- **Left-click** a row: expand/collapse if it has children, equip if it has gear (does both if both apply).
- **Right-click** a row: open the preview pane to see what the set is for, where it lives in Lua, and what gear it defines or overrides.
- **Mouse wheel** over the window: scroll.
- **Drag the title bar**: move the window. Position is saved.

## Commands

```
//gt show | hide | toggle     show or hide the window
//gt reload                   re-parse the current gear file
//gt save                     save changed equipped slots into highlighted set
//gt undo                     restore the backup from the last GearTree save
//gt last                     jump back to the last saved set
//gt find <text>              jump to a matching set, folder, or gear line
//gt load <path>              parse a specific gear file
//gt auto                     try to auto-detect for your current job
//gt mode [raw|organized|toggle]
                              switch between Raw Lua Tree and Organized Tree
//gt make <folder> [root]     add a virtual display folder
//gt move <set> to <folder>   move a Lua set/folder in the display only
//gt move [set] up|down|top|bottom
                              reorder display items without editing Lua
//gt move here                move the last saved set into highlighted folder
//gt rename <new>             rename highlighted virtual folder
//gt rename <folder> to <new> rename a named virtual folder
//gt remove [folder]          remove virtual folder only
//gt unmove [set]             return a moved set/folder to Lua location
//gt layout reset             return display layout to Lua order
//gt expandall | collapseall  expand or collapse the whole tree
//gt pos [x y]                show position, or set it explicitly
//gt help                     command summary
```

## Saving gear changes

1. Highlight a set in GearTree and equip it from GearTree.
2. Change gear normally in game.
3. Run `//gt save`.

GearTree compares your current gear against the set it equipped, then writes
only the changed slots into the highlighted set. Augmented gear is written as
`{ name="Item", augments={...} }`.

After a save, GearTree prints each changed slot as `old item -> new item` so
you can quickly spot what was written.

Before every successful write, GearTree creates a backup in
`addons/GearTree/data/backups/`. After saving, it reparses the tree and runs
`gs reload`. The saved set is remembered, marked with `*`, and can be revisited
with `//gt last`.

Editable set shapes:

- `sets.foo = { ... }` updates or adds slot fields in that table.
- `sets.foo = set_combine(base, { ... })` updates or adds fields in the
  override table.
- `sets.foo = set_combine(base)` appends a new override table.
- `sets.foo = sets.bar` becomes `sets.foo = set_combine(sets.bar, { ... })`.

Dynamic or unsupported assignments are refused instead of rewritten.

## How it works

GearTree parses your Gearswap user `.lua` file as text — it does **not** execute
it. It extracts every `sets.X.Y.Z = ...` assignment and builds a tree. Clicking
a leaf sends `gs equip <path>` to Gearswap, which does the actual equipping
(including resolving `set_combine()` calls and `gear.*` variables).

This means:
- The addon only modifies your gear file when you explicitly run `//gt save`.
- Saves are backed up first and only changed equipped slots are rewritten.
- It works with any Mote-style or hand-rolled Gearswap file.
- It handles bracket-key paths (`sets.precast.WS["Rudra's Storm"].SA`).
- It does not run your gear file's logic, so dynamic sets defined inside
  `if`-branches won't show up — only top-level `sets.X = ...` assignments are
  extracted.

## Known limitations (v0.2)

- The background panel is rendered as a text object with spaces, so its visible
  width is approximate. You may need to tune `width` in
  `data/settings.xml` for your font choice.
- Preview doesn't recursively resolve `set_combine()` chains; it shows the
  immediate overrides plus the set(s) being combined, and adds a best-effort
  plain-English explanation from standard GearSwap set names.
- Sets defined like `sets.foo = {"item"}` (positional, no slot key) appear in
  the tree but Gearswap treats them as empty. This is a quirk of those files,
  not the addon.

## Files

The editor version also includes `gear_slots.lua`, `snapshot.lua`, `writer.lua`,
`organized_tree.lua`, and `semantics.lua` for slot names, current equipment
snapshots, safe file edits, organized display routing, and plain-English preview
metadata.

```
GearTree/
├── GearTree.xml      - Windower manifest
├── GearTree.lua      - Addon entry point
├── parser.lua        - Lua text parser (extracts sets.* assignments)
├── organized_tree.lua - Optional friendly tree routing
├── semantics.lua     - Plain-English preview metadata for parsed sets
├── tree.lua          - Tree builder, path formatting, flatten for display
├── ui.lua            - Windower text overlay, click/drag/scroll handlers
└── README.md         - This file
```
