-- ui_theme.lua  —  root-level theme stub for GearTree.
--
-- Color overrides live in themes/jeuno/ui_theme.lua, which is loaded by the
-- theme engine when GearTree starts.  This file intentionally returns an empty
-- table so it does not duplicate or conflict with the theme folder's values.
--
-- If the theme engine fails to find themes/jeuno/, the renderer falls back to
-- the color defaults already baked into cfg in ui_facelift.lua.
return {}
