# GearTree

GearTree is a Windower addon for FFXI that turns your currently loaded GearSwap Lua file into a clickable gear-set browser.

It lets you:

- Browse GearSwap sets in a readable tree.
- Use an organized view that groups common GearSwap patterns into friendly folders.
- Equip sets directly from the UI.
- Preview what a set does, where it comes from, and what gear it defines.
- Compare the selected set against your currently equipped gear.
- Save changed equipped slots back into the highlighted Lua set.
- Add personal notes to sets and folders without editing your GearSwap Lua.

GearTree is meant to help players understand, test, clean up, and maintain big GearSwap files without digging through hundreds or thousands of Lua lines every time.

---

## Install

1. Copy the whole `GearTree` folder into:

   ```text
   Windower4/addons/GearTree/
   ```

2. In game, load the addon:

   ```lua
   //lua load GearTree
   ```

3. GearTree will try to auto-detect the current GearSwap file for your character/job.

If your gear file is not auto-detected, load it manually:

```lua
//gt load D:\Windower4\addons\GearSwap\data\Character\Character_Job_Gear.lua
```

---

## Basic use

- **Left-click** a row to expand/collapse it. If the row is a gear set, it also equips that set.
- **Right-click** a row to preview set info, source/path details, and gear.
- **Mouse wheel** over the window to scroll.
- **Drag the title bar** to move the window. Position is saved.
- **Esc** hides the window.
- **End** equips the highlighted set.

When GearTree is visible:

```text
Up / Down   Move through the tree or scroll the active preview tab
Right       Expand folder / move preview tab right
Left        Collapse/back / move preview tab left
End         Equip highlighted set
Esc         Hide GearTree
```

---

## Commands

```lua
//gt show | hide | toggle
//gt reload
//gt save
//gt saveslot <slot>
//gt undo
//gt last
//gt open
//gt note <text>
//gt note
//gt note clear
//gt find <text>
//gt status
//gt edit [on|off|toggle]
//gt load <path>
//gt auto
//gt mode [raw|organized|toggle]
//gt make <folder> [root]
//gt move <set> to <folder>
//gt move [set] up|down|top|bottom
//gt move here
//gt rename <new name>
//gt rename <folder> to <new name>
//gt remove [folder]
//gt unmove [set]
//gt layout reset
//gt expandall | collapseall
//gt pos [x y]
//gt augdebug
//gt debugslot <slot>
//gt help
```

### Useful commands

```lua
//gt save
```

Saves changed equipped slots back into the highlighted set. GearTree only writes slots that changed from the baseline it captured when the set was equipped.

```lua
//gt saveslot head
```

Force-saves the currently equipped item in one slot into the highlighted set.

```lua
//gt undo
```

Restores the backup from the most recent GearTree save.

```lua
//gt note Temporary set while I work toward better head/back pieces.
```

Adds a personal note to the highlighted set or folder. Notes are stored in GearTree data files, not in your GearSwap Lua.

```lua
//gt note
```

Shows the note for the highlighted set or folder in chat.

```lua
//gt note clear
```

Clears the note for the highlighted set or folder.

```lua
//gt open
```

Opens the highlighted Lua set near its source line, when possible.

```lua
//gt mode raw
//gt mode organized
```

Switches between the raw Lua tree and the organized tree.

---

## Organized tree vs raw tree

GearTree has two display modes:

### Organized Tree

The default view. GearTree groups common GearSwap patterns into friendly categories like:

- Current State
- Actions
- Magic
- Overlays / Modifiers
- Reactive
- Weapons
- Other

This does **not** change your Lua file. It is only a display layer.

### Raw Lua Tree

Shows sets closer to the actual Lua structure, useful for debugging or finding the exact path.

Use:

```lua
//gt mode raw
//gt mode organized
//gt mode toggle
```

---

## Saving gear changes

Typical save workflow:

1. Highlight a set in GearTree.
2. Equip it from GearTree.
3. Change gear normally in game.
4. Run:

   ```lua
   //gt save
   ```

GearTree compares your current equipment against the baseline from when it equipped the set. It writes only changed slots.

Before every successful write, GearTree creates a backup in:

```text
Windower4/addons/GearTree/data/backups/
```

GearTree keeps the latest **5 backups per Lua file**. The most recent save can be restored with:

```lua
//gt undo
```

After saving, GearTree reparses the file and queues a GearSwap reload.

---

## Notes

GearTree supports personal notes on both gear sets and category/folder cards.

Notes appear under:

```text
== Notes ==
```

in the Summary tab.

Examples:

```lua
//gt note Temporary idle set while I work toward better DT pieces.
```

```lua
//gt note Dynamis proc/NM utility sets. Keep low damage options here.
```

Notes are stored separately from your GearSwap Lua, so they do not clutter or rewrite your source file comments.

---

## Augment tags

GearTree uses simple augment tags in the Gear tab:

```text
[aug]
```

The Lua set explicitly lists augments for that item.

```text
[aug?]
```

The Lua set does **not** list augments, but GearTree found an augmented copy equipped or in inventory/storage.

Important limitation: if your Lua only says:

```lua
right_ring="Gelatinous Ring +1"
```

then GearTree cannot know which augmented copy you intended. It can only say that an augmented copy was found. If you need exact-copy matching, put the augments in your Lua:

```lua
right_ring={ name="Gelatinous Ring +1", augments={'Path: A'} }
```

GearTree currently does **not** display augment rank/path details like `A/R15`, because Windower/extdata does not consistently expose that data in the parsed augment list.

---

## What GearTree will edit

GearTree edits common GearSwap assignment shapes such as:

```lua
sets.foo = { ... }
sets.foo = set_combine(base, { ... })
sets.foo = set_combine(base)
sets.foo = sets.bar
```

Dynamic or unsupported assignments are refused instead of rewritten.

GearTree parses your Lua file as text. It does **not** execute your GearSwap file. That keeps the parser safer, but it also means sets built only through runtime logic may not appear.

---

## Known limitations

- Dynamic sets built only inside runtime logic may not be detected.
- GearTree does not fully resolve every nested `set_combine()` chain in the preview.
- If Lua does not specify augments, GearTree cannot know which augmented copy you intended.
- Augment rank/path display is intentionally not shown because the parsed data is inconsistent.
- Some unusual positional tables like `sets.foo = {"item"}` may appear empty because GearSwap itself expects slot keys like `head=`, `body=`, etc.
- The UI is rendered with Windower text objects, so exact spacing can vary by font/settings.

---

## Release safety

GearTree is designed to be conservative:

- It only writes when you explicitly run a save command.
- It creates a backup before each successful write.
- It keeps the latest 5 backups per Lua file.
- `//gt undo` restores the most recent GearTree save.
- Unsupported set shapes are refused instead of guessed.

Still, use normal caution: test on one job file first, and keep your GearSwap files backed up.

---

## Files

```text
GearTree/
├── GearTree.xml        - Windower manifest
├── GearTree.lua        - Addon entry point and command handling
├── parser.lua          - Lua text parser for sets.* assignments
├── tree.lua            - Raw tree builder and path/equip helpers
├── organized_tree.lua  - Friendly organized tree routing
├── semantics.lua       - Summary/category explanations
├── ui_adapter.lua      - UI adapter layer
├── ui_facelift.lua     - Main text UI
├── notes.lua           - GearTree note storage
├── gear_slots.lua      - Slot names and canonicalization
├── snapshot.lua        - Current equipment/inventory snapshots
├── writer.lua          - Safe Lua file patching and backups
├── layout.lua          - Virtual folder/reorder layout storage
└── README.md
```
