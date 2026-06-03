# GearTree

GearTree is a Windower addon that transforms GearSwap Lua files into an interactive gear management system inside Final Fantasy XI.

Instead of digging through hundreds or thousands of lines of Lua, GearTree lets you browse, organize, inspect, and update gear sets directly from the game.

![GearTree Main View](Images/Geartab.png)

---

## Why GearTree?

Large GearSwap files become difficult to navigate, maintain, and update over time.

GearTree provides:

* Organized set browsing
* Raw GearSwap navigation
* Gear inspection
* Personal notes
* Virtual folders
* Save-back support
* Automatic backups
* Undo functionality
* Mouse and keyboard navigation
* UI scaling and customization

Whether you maintain a simple job file or a highly customized endgame setup, GearTree makes managing gear significantly easier.

---

## Features

### Organized Tree View

Browse gear sets through gameplay-focused categories instead of hunting through Lua files.

Examples include:

* Weapon Skills
* Idle Sets
* Engaged Sets
* Defensive Sets
* Utility Sets
* Reactive Sets
* Magic Sets

Perfect for large GearSwap files with dozens or hundreds of sets.

### Save Directly Back To GearSwap

Update gear in-game and write changes directly back into your GearSwap Lua.

No manual editing required.

### Automatic Backups & Undo

Every save creates a backup automatically.

Restore the previous save with:

`//gt undo`

### Notes and Organization

Attach notes to sets and folders for:

* Upgrade planning
* Farming goals
* Build explanations
* Future gear upgrades
* Personal reminders

![Summary View](Images/Summarytab.png)

### Gear Inspection

Inspect equipment, inventory location, missing items, and additional set information.

![Data View](Images/Datatab.png)

### Mouse and Keyboard Navigation

Navigate using:

* Keyboard controls
* Mouse controls
* Visual cursor overlay
* Shift+Arrow navigation mode

### UI Customization

Scale the interface:

`//gt scale 1.25`

Adjust opacity:

`//gt opacity 75`

Toggle cursor overlay:

`//gt cursor on`

### Organized and Raw Views

Switch between:

* Organized View (gameplay-focused categories)
* Raw View (original GearSwap structure)

depending on how you prefer to manage your sets.

---

## Help

Player commands:

`//gt help`

Advanced and developer commands:

`//gt devhelp`

---

## Requirements

* Windower
* GearSwap

---

## Current Version

**GearTree 0.4.0**
