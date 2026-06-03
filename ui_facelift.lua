-- GearTree facelift UI
-- Windower text-overlay backend with a wider, multi-pane layout.
--
-- Theme-engine architecture (theme-engine-experiment branch):
--   ui_theme.lua   — pure color/style data, no logic
--   ui_facelift    — layout + hitboxes + renderer; reads cfg.xxx
--   cfg table      — layout keys (pos_x, width, …) + active theme colors
--   apply_theme()  — merges a theme table into cfg; call at startup
--   ui.set_theme() — live theme swap + full redraw
--
-- Rendering code always reads cfg.xxx.  Swapping a theme only requires
-- calling apply_theme() with a new table; no renderer changes needed.

local tree      = require('tree')
local semantics = require('semantics')
local texts     = require('texts')
local images    = require('images')
local gear_slots = require('gear_slots')
local res       = require('resources')
local extdata   = require('extdata')

local ui = {}

local function windower_asset(relative)
    local base = windower and windower.windower_path or ''
    if base ~= '' then
        if base:sub(-1) ~= '/' and base:sub(-1) ~= '\\' then
            base = base .. '/'
        end
        return base .. relative
    end
    return 'C:/Program Files (x86)/Windower/' .. relative
end

local RECT_TEXTURE = windower_asset('addons/invtracker/slot.png')
local TEXT_CHAR_WIDTH = 8

-- ── Layout metrics (calibration tool) ─────────────────────────────────────
-- Single source of truth for the alignment offsets the //gt layout tool edits.
-- Values are deltas/insets (not absolute pixels) so they stay correct if the
-- window moves or width/visible_rows change.  Defaults equal the previously
-- hardcoded values, so normal rendering is byte-identical until the user edits.
-- All metrics are ADDITIVE offsets/adjusts (default 0) layered on the natural
-- computed bounds, except the shared base inset (chrome_inset) and content_top_pad
-- which keep their prior defaults.  Defaults reproduce the current layout exactly,
-- so nothing moves until the user edits.  Per-zone x/w let header, tab, content and
-- footer diverge (the art's footer line can be wider than the header line, etc.).
local LM_DEFAULTS = {
    -- shared base
    chrome_inset    = 6,   -- L/R inset of the zones from the frame edge (image mode)
    content_top_pad = 10,  -- gap below the tab line before the first content row
    -- header / banner box
    header_x_offset = 0,
    header_y_offset = 0,
    header_w_adjust = 0,
    header_h_adjust = 0,
    header_text_x_offset = 0,
    header_text_y_offset = 0,
    -- tab row box
    tab_x_offset    = 0,
    tab_y_offset    = 0,
    tab_w_adjust    = 0,
    tab_h_adjust    = 0,
    tab_right_trim  = 0,   -- legacy: extra right-edge pull-in (kept for back-compat)
    preview_tab_text_x_offset = 0,
    preview_tab_text_y_offset = 0,
    -- tree "Gear Sets" header label
    tree_header_text_x_offset = 0,
    tree_header_text_y_offset = 0,
    -- content / body
    content_x_offset = 0,
    content_w_adjust = 0,
    -- footer / status box
    footer_x_offset = 0,
    footer_y_offset = 2,
    footer_w_adjust = 0,
    footer_h_adjust = 0,
    footer_text_x_offset = 8,
    footer_text_y_offset = 0,
}
local LM_CLAMP = {
    chrome_inset    = { 0, 40 },
    content_top_pad = { 0, 40 },
    header_x_offset = { -60, 60 },
    header_y_offset = { -20, 40 },
    header_w_adjust = { -120, 60 },
    header_h_adjust = { -16, 60 },
    header_text_x_offset = { -80, 200 },
    header_text_y_offset = { -16, 16 },
    tab_x_offset    = { -60, 60 },
    tab_y_offset    = { -20, 40 },
    tab_w_adjust    = { -120, 60 },
    tab_h_adjust    = { -8, 24 },
    tab_right_trim  = { 0, 80 },
    preview_tab_text_x_offset = { -40, 40 },
    preview_tab_text_y_offset = { -16, 16 },
    tree_header_text_x_offset = { -40, 120 },
    tree_header_text_y_offset = { -16, 16 },
    content_x_offset = { -40, 40 },
    content_w_adjust = { -120, 60 },
    footer_x_offset = { -60, 60 },
    footer_y_offset = { -12, 40 },
    footer_w_adjust = { -120, 60 },
    footer_h_adjust = { -12, 40 },
    footer_text_x_offset = { -80, 400 },
    footer_text_y_offset = { -16, 16 },
}
local LM = {}
for k, v in pairs(LM_DEFAULTS) do LM[k] = v end

local function lm_clamp(k, v)
    v = tonumber(v) or LM_DEFAULTS[k]
    local c = LM_CLAMP[k]
    if c then
        if v < c[1] then v = c[1] elseif v > c[2] then v = c[2] end
    end
    return math.floor(v + 0.5)
end

local function apply_layout(t)
    if type(t) ~= 'table' then return end
    for k in pairs(LM_DEFAULTS) do
        if t[k] ~= nil then LM[k] = lm_clamp(k, t[k]) end
    end
end

local cfg = {
    pos_x = 100,
    pos_y = 100,
    width = 205, -- legacy setting now means tree pane width
    visible_rows = 24,
    row_height = 16,
    font = 'Consolas',
    font_size = 10,

    gap = 6,
    header_height = 24,   -- title/header section height; slightly taller than the tab row (~18 px)
    footer_height = 18,
    show_list_pane = false,
    list_width = 300,
    preview_width = 445,
    show_icons = false,
    icon_size = 10,

    bg_color = { 225, 6, 12, 18 },
    panel_bg = { 218, 7, 18, 28 },
    title_bg = { 235, 20, 34, 56 },
    title_fg = { 225, 210, 170 },
    -- Top command/header banner (the "GearTree | End Equip | ..." line).
    -- Translucent navy so it reads as a banner over art OR primitive frame.
    header_bg = { 180, 14, 24, 46 },
    header_fg = { 235, 214, 162 },   -- warm bronze-gold text (no alpha)
    active_title_bg = { 185, 88, 68, 20 },   -- warm amber; less "pasted on" than flat blue
    active_title_fg = { 255, 238, 165 },      -- bright warm gold for selected tab label
    tab_hover_bg    = { 140, 48, 72, 110 },   -- softer blue hover, more translucent
    tab_hover_fg    = { 240, 220, 185 },      -- warm-white: brighter than title_fg, dimmer than active
    -- Image-theme mode tab overlays: translucent so the artwork shows through.
    tab_active_overlay = { 150, 60, 92, 150 },
    tab_hover_overlay  = {  95, 48, 78, 120 },
    frame_bg = { 196, 3, 8, 13 },
    border_light  = { 200, 182, 148, 48 },   -- warm gold — tab row lines and active accent
    border_shadow = { 180, 145, 112, 30 },   -- darker gold for bottom/right frame (primitive mode)
    divider_col   = { 145, 148, 120, 42 },   -- gold-tinted internal separators: divider, footer rule
    scrollbar_track = { 105, 52, 58, 64 },
    scrollbar_thumb = { 150, 128, 128, 126 },
    row_fg_set = { 220, 220, 215 },
    row_fg_cat = { 155, 198, 230 },
    row_fg_dim = { 132, 138, 145 },
    row_fg_gold = { 245, 210, 120 },
    row_fg_green = { 160, 230, 115 },
    row_fg_blue = { 120, 190, 255 },
    row_fg_violet = { 199, 146, 234 },
    row_fg_red = { 255, 105, 105 },
    row_fg_cursor = { 255, 244, 184 },
    row_bg_cursor = { 185, 42, 72, 120 },
    row_bg_hover  = { 145, 42, 72, 120 },  -- same hue as cursor, ~78 % of cursor alpha for clearly visible hover
    row_bg_changed = { 90, 199, 146, 234 },
    -- 'on' (default): left click activates rows/tabs.
    -- 'off': hover only; keyboard navigation is the interaction method.
    mouse_mode = 'on',
    -- Optional visual-only mouse pointer overlay (crosshair) drawn at the last
    -- known mouse position while GearTree is visible.  Does not touch clicks.
    cursor_overlay = false,
    cursor_fg     = { 235, 255, 238, 170 },  -- gold-cream crosshair  {alpha,r,g,b}
    cursor_shadow = { 170,   6,   8,  16 },  -- dark drop-shadow      {alpha,r,g,b}
    ui_scale = 1.0,  -- uniform zoom: 0.75 - 2.0
    ui_opacity = 100, -- global window opacity: 35-100 (100 = fully opaque)
}

-- oa(a): scale an alpha value by the global opacity setting.
-- At 100% opacity this is a no-op.  At 85% opacity, oa(180) = 153.
local function oa(a)
    if cfg.ui_opacity == nil or cfg.ui_opacity >= 100 then return a end
    return math.floor((a or 0) * cfg.ui_opacity / 100 + 0.5)
end

-- ── Theme engine ─────────────────────────────────────────────────────────
-- apply_theme(t): merge a theme table's color/style keys into cfg.
-- Only keys already present in cfg are accepted (layout/behavior keys such
-- as pos_x, width, visible_rows, mouse_mode are never overwritten by themes).
local function apply_theme(t)
    for k, v in pairs(t or {}) do
        if cfg[k] ~= nil then
            cfg[k] = v
        end
    end
end

-- Load the active theme.  Use pcall so a missing/broken theme file is
-- non-fatal; cfg keeps its defaults if the require fails.
do
    local ok, theme_data = pcall(require, 'ui_theme')
    if ok and type(theme_data) == 'table' then
        apply_theme(theme_data)
    end
end

-- sc(v): scale a pixel value by cfg.ui_scale and round to nearest integer.
local function sc(v)
    return math.floor((v or 0) * cfg.ui_scale + 0.5)
end

-- ui.set_theme(t): swap to a new theme at runtime and trigger a full redraw.
-- 't' should be a table with the same color keys as ui_theme.lua.
-- NOTE: apply_theme() is a local defined above, so it is in scope here.
--       'state' and the local render functions are defined LATER in this file,
--       so they are NOT in scope here.  We access the public ui.refresh() via
--       table lookup on 'ui' (defined at module top), which is always in scope.
function ui.set_theme(t)
    apply_theme(t)
    -- Trigger a full re-render through the public refresh path.
    -- ui.refresh is set later in this file; table lookup is fine.
    if type(ui.refresh) == 'function' then ui.refresh() end
end

-- ─────────────────────────────────────────────────────────────────────────

function ui.configure(overrides)
    for k, v in pairs(overrides or {}) do
        if k == 'ui_scale' then
            cfg.ui_scale = math.max(0.75, math.min(tonumber(v) or cfg.ui_scale, 2.0))
        elseif k == 'ui_opacity' then
            cfg.ui_opacity = math.max(35, math.min(100, math.floor(tonumber(v) or 100)))
        elseif k == 'width' then
            cfg.width = math.max(190, math.min(tonumber(v) or cfg.width, 205))
        elseif k == 'mouse_mode' then
            local m = tostring(v or ''):lower()
            -- Backward compat: map old mode names to current 'on'/'off'.
            if m == 'normal' or m == 'left' then m = 'on' end
            if m == 'shift' or m == 'right' then m = 'off' end
            if m == 'on' or m == 'off' then cfg.mouse_mode = m end
        elseif cfg[k] ~= nil then
            cfg[k] = v
        end
    end
end

function ui.set_mouse_mode(mode)
    mode = tostring(mode or ''):lower()
    -- Backward compat: map old mode names to current 'on'/'off'.
    if mode == 'normal' or mode == 'left' then mode = 'on' end
    if mode == 'shift' or mode == 'right' then mode = 'off' end
    if mode ~= 'on' and mode ~= 'off' then return false end
    cfg.mouse_mode = mode
    return true
end

function ui.get_mouse_mode()
    return cfg.mouse_mode or 'on'
end

function ui.set_scale(s)
    cfg.ui_scale = math.max(0.75, math.min(tonumber(s) or 1.0, 2.0))
    -- ui.refresh() is defined later in this file and closes over the local state;
    -- calling it here (via table lookup at call-time) avoids the forward-reference
    -- problem that makes 'state' resolve as a global in functions defined before it.
    if type(ui.refresh) == 'function' then ui.refresh() end
end

function ui.get_scale()
    return cfg.ui_scale or 1.0
end

-- ── 9-slice image panel renderer ─────────────────────────────────────────
-- Manages 9 Windower image objects that tile into an ornamental panel frame.
-- Images are created BEFORE all other overlay objects so they sort behind
-- every rect/text in the Windower overlay stack (creation order = depth).
--
-- Asset directory  : addons/Geartree/themes/jeuno/
-- Expected PNGs    : panel_corner_tl  panel_edge_top    panel_corner_tr
--                    panel_edge_left  panel_fill        panel_edge_right
--                    panel_corner_bl  panel_edge_bottom panel_corner_br
--
-- Corner/edge size : SLICE_CORNER pixels (12 px default).
-- Stretch mode     : each piece uses fit=false so Windower obeys the exact
--                    pixel rectangle set by update_9slice(). This is important
--                    for skinny edge textures like 1x12 top/bottom edges.
--
-- Fallback         : if any PNG is absent the 9-slice is disabled and the
--                    existing primitive frame/border rects are used instead.
--                    One warning is printed to the Windower chat log.
-- ─────────────────────────────────────────────────────────────────────────

local SLICE_CORNER     = 12   -- px; updated per-theme from ui_theme.lua slice_corner key
local pending_accents  = nil  -- accent spec table from most-recent set_theme_dir call

-- Themed cursor image (themes/<name>/cursor.png) if present.  The art's pointer tip is at
-- the top-left, so the image is positioned at (mouse_x - tip_x, mouse_y - tip_y)
-- with tip offsets of 0 — the tip lands exactly on the mouse coordinate.
local CURSOR_IMG_SIZE = 16
local CURSOR_TIP_X    = 0
local CURSOR_TIP_Y    = 0

local THEME_ASSET_DIR = windower_asset('addons/Geartree/themes/jeuno/')
-- Rounded-top tab highlight texture (white mask, tinted + stretched per tab).
local TAB_HL_TEXTURE  = THEME_ASSET_DIR .. 'tab_hl.png'
-- Header logo (transparent PNG; falls back to GearTree text if missing).
local LOGO_TEXTURE    = THEME_ASSET_DIR .. 'logo_geartree.png'
-- Theme base directory (themes/ folder, one level up from each theme folder).
local THEMES_BASE_DIR = windower_asset('addons/Geartree/themes/')

local SLICE_KEYS = {
    'panel_corner_tl', 'panel_edge_top',    'panel_corner_tr',
    'panel_edge_left', 'panel_fill',        'panel_edge_right',
    'panel_corner_bl', 'panel_edge_bottom', 'panel_corner_br',
}

local function slice_file_exists(path)
    local f = io.open(path, 'r')
    if f then f:close(); return true end
    return false
end

-- ── Theme directory / switching functions ─────────────────────────────────
-- These are defined here (after THEME_ASSET_DIR, THEMES_BASE_DIR, and
-- slice_file_exists) so they can close over those locals correctly.

-- Update the theme asset directory and apply the theme's color table.
-- Caller is responsible for calling ui.destroy + ui.create to reload images.
function ui.set_theme_dir(dir)
    THEME_ASSET_DIR = dir
    TAB_HL_TEXTURE  = dir .. 'tab_hl.png'
    LOGO_TEXTURE    = dir .. 'logo_geartree.png'
    -- Load ui_theme.lua from the theme folder if present.
    local theme_lua = dir .. 'ui_theme.lua'
    pending_accents = nil
    SLICE_CORNER    = 12
    if slice_file_exists(theme_lua) then
        local ok, result = pcall(dofile, theme_lua)
        if ok and type(result) == 'table' then
            apply_theme(result)
            if type(result.slice_corner) == 'number' then
                SLICE_CORNER = math.max(8, math.min(64, result.slice_corner))
            end
            if type(result.accents) == 'table' then
                pending_accents = result.accents
            end
        end
    end
end

-- Switch theme by name.  Probes THEMES_BASE_DIR/<name>/panel_fill.png.
-- Returns true on success, false if theme folder/assets not found.
-- Does NOT recreate image objects; caller must destroy + create to reload images.
function ui.set_theme_name(name)
    if type(name) ~= 'string' or name == '' then return false end
    local dir = THEMES_BASE_DIR .. name .. '/'
    if not slice_file_exists(dir .. 'panel_fill.png') then
        return false
    end
    ui.set_theme_dir(dir)
    return true
end

-- Return the current theme name inferred from THEME_ASSET_DIR.
function ui.get_theme_name()
    local dir = THEME_ASSET_DIR
    if dir:sub(1, #THEMES_BASE_DIR) == THEMES_BASE_DIR then
        local rest = dir:sub(#THEMES_BASE_DIR + 1)
        return rest:gsub('[/\\]$', '')
    end
    return 'unknown'
end

-- Return list of theme folder names that have panel_fill.png present.
function ui.list_themes()
    -- Preferred display/cycle order for known built-in themes.
    local preferred = { 'jeuno' }

    -- Collect folders that contain panel_fill.png.
    -- Try lfs directory scan first; fall back to the known list if unavailable.
    local found = {}
    local ok, lfs = pcall(require, 'lfs')
    if ok and lfs and lfs.dir then
        local dir = THEMES_BASE_DIR:gsub('[/\\]$', '')
        local scan_ok, err = pcall(function()
            for name in lfs.dir(dir) do
                if name ~= '.' and name ~= '..' then
                    local mode = lfs.attributes(dir .. '/' .. name, 'mode')
                    if mode == 'directory' then
                        if slice_file_exists(THEMES_BASE_DIR .. name .. '/panel_fill.png') then
                            found[name] = true
                        end
                    end
                end
            end
        end)
        if not scan_ok then found = nil end
    end

    -- Merge: preferred order first, then any extra folders found by scan.
    local out = {}
    local seen = {}
    for _, name in ipairs(preferred) do
        local have = found and found[name] or slice_file_exists(THEMES_BASE_DIR .. name .. '/panel_fill.png')
        if have then
            out[#out + 1] = name
            seen[name] = true
        end
    end
    if found then
        local extras = {}
        for name in pairs(found) do
            if not seen[name] then extras[#extras + 1] = name end
        end
        table.sort(extras)
        for _, name in ipairs(extras) do out[#out + 1] = name end
    end
    return out
end

-- Alias for ui.list_themes().
function ui.available_themes()
    return ui.list_themes()
end

-- ─────────────────────────────────────────────────────────────────────────

-- Returns (true, nil) if all 9 assets exist, or (false, first_missing_name).
local function check_slice_assets()
    for _, key in ipairs(SLICE_KEYS) do
        if not slice_file_exists(THEME_ASSET_DIR .. key .. '.png') then
            return false, key
        end
    end
    return true, nil
end

local function new_slice_image(path)
    local obj = images.new({
        draggable = false,
        visible   = false,
        color     = { alpha = 255, red = 255, green = 255, blue = 255 },
        size      = { width = 1, height = 1 },
        texture   = { fit = false, path = path },
    })
    if obj.path then obj:path(path) end
    if obj.fit  then obj:fit(false) end
    return obj
end

-- Create the 9-slice set.  Must be called FIRST in ui.create() so these
-- images sort behind all subsequently created rects and text objects.
-- Returns { images={…9…}, enabled=bool }.
local function init_9slice()
    local ok, missing = check_slice_assets()
    if not ok then
        if windower and windower.add_to_chat then
            local theme_name = THEME_ASSET_DIR:match('[/\\]([^/\\]+)[/\\]?$') or 'current theme'
            windower.add_to_chat(123,
                '[GearTree] 9-slice theme: "' .. missing ..
                '.png" not found in themes/' .. theme_name .. '/ — primitive fallback active.')
        end
        return { images = {}, enabled = false }
    end

    local imgs = {}
    for _, key in ipairs(SLICE_KEYS) do
        imgs[#imgs + 1] = new_slice_image(THEME_ASSET_DIR .. key .. '.png')
    end
    return { images = imgs, enabled = true }
end

-- Reposition and resize all 9 pieces to cover the rectangle (x,y,w,h).
-- cs = corner pixel size.
local function update_9slice(s9, x, y, w, h, cs)
    if not s9 or not s9.enabled or #s9.images < 9 then return end
    local imgs = s9.images
    local mw   = math.max(1, w - 2 * cs)
    local mh   = math.max(1, h - 2 * cs)
    local function at(i, px, py, pw, ph)
        imgs[i]:pos(math.floor(px), math.floor(py))
        imgs[i]:size(math.max(1, pw), math.max(1, ph))
    end
    --           idx  x              y              w    h
    at(1, x,           y,           cs,  cs)   -- TL corner
    at(2, x + cs,      y,           mw,  cs)   -- top edge
    at(3, x + w - cs,  y,           cs,  cs)   -- TR corner
    at(4, x,           y + cs,      cs,  mh)   -- left edge
    at(5, x + cs,      y + cs,      mw,  mh)   -- fill
    at(6, x + w - cs,  y + cs,      cs,  mh)   -- right edge
    at(7, x,           y + h - cs,  cs,  cs)   -- BL corner
    at(8, x + cs,      y + h - cs,  mw,  cs)   -- bottom edge
    at(9, x + w - cs,  y + h - cs,  cs,  cs)   -- BR corner
end

local function set_9slice_visible(s9, visible)
    if not s9 then return end
    for _, img in ipairs(s9.images) do img:visible(visible) end
end

local function destroy_9slice(s9)
    if not s9 then return end
    for _, img in ipairs(s9.images) do img:destroy() end
    s9.images  = {}
    s9.enabled = false
end

local state = {
    root = nil,
    flat = {},
    scroll = 0,
    cursor = 0,
    visible = false,
    drag = nil,
    hover = nil,  -- {kind='tree_row'|'list_row', flat_idx=N, node=node} or nil
    save_pos_callback = nil,
    equip_callback = nil,
    preview_lines = {},
    preview_cards = { summary = {}, gear = {}, changes = {}, evidence = {} },
    preview_card = 'gear',
    preview_scroll = 0,
    source_cursor = 0,
    source_pan = 0,
    source_left_edge_until = 0,
    focus = 'tree',
    selection_callback = nil,
    last_selection_node = nil,
    live_changes = { path = nil, rows = {}, count = 0 },
    recent_saved = { path = nil, slots = {} },
    current_equipment = { path = nil, slots = {} },
    gear_reference_items = {},
    inventory_locations = { items = {}, items_by_id = {}, bags = {} },
    status_text = '',
    last_saved_path = '',
    objects = {},
    image_objects = {},
    decor_images = {},
    accent_specs = {},
    panel_full_img   = nil,   -- panel_full.png stretched image (replaces 9-slice when present)
    header_band_img  = nil,   -- header_band.png art layer over the header region
    tab_active_img   = nil,   -- tab_active.png art for the active tab cell
    tree_rows = {},
    tree_icons = {},
    list_rows = {},
    list_icons = {},
    preview_rows = {},
    preview_aug_tags = {},
    preview_tab_bg = nil,
    preview_tab_rects = {},
    preview_tab_separators = {},
    preview_gear_title = nil,
    preview_changes_title = nil,
    preview_data_title = nil,
    -- Layout calibration tool
    layout_mode = false,
    layout_drag = nil,           -- { metric, axis, sign, start_v, start_mx, start_my }
    layout_fills = {},           -- guide fill rects
    layout_labels = {},          -- guide label texts
    layout_bounds = {},          -- per-frame guide hit rects { name, edit, x,y,w,h, by }
}

local auto_preview

local function clear_source_left_guard()
    state.source_left_edge_until = 0
end

local function dims()
    local tree_w    = sc(cfg.width)
    local list_w    = cfg.show_list_pane and sc(cfg.list_width) or 0
    local preview_w = sc(cfg.preview_width)
    local preview_x = cfg.pos_x + tree_w + sc(cfg.gap)
    if cfg.show_list_pane then
        preview_x = preview_x + list_w + sc(cfg.gap)
    end
    local total_w = preview_x - cfg.pos_x + preview_w
    local body_y  = cfg.pos_y + sc(cfg.header_height)
    local body_h  = (cfg.visible_rows + 1) * sc(cfg.row_height) + sc(LM.content_top_pad)
    local footer_y = body_y + body_h + 2

    return {
        x = cfg.pos_x,
        y = cfg.pos_y,
        tree_x = cfg.pos_x,
        list_x = cfg.pos_x + tree_w + cfg.gap,
        preview_x = preview_x,
        body_y = body_y,
        footer_y = footer_y,
        tree_w = tree_w,
        list_w = list_w,
        preview_w = preview_w,
        total_w = total_w,
        body_h = body_h,
    }
end

local function cols(width)
    return math.max(12, math.floor(width / sc(TEXT_CHAR_WIDTH)))
end

-- Bounds of the preview tab row.  X spans from the preview pane left edge to the
-- inner gold border on the right (shared with header/footer chrome) so the Data
-- tab never slides under the frame art.  Tab-zone metrics (x/y offset, w/h adjust)
-- are layered on top.  Shared by the renderer AND the tab hitbox so they can't
-- drift apart.  Returns (x, w, y, h).
local function tab_strip_bounds(d)
    local image_frame = state.panel_9slice and state.panel_9slice.enabled
    local right
    if image_frame then
        local frame_pad    = 2
        local chrome_inset = sc(LM.chrome_inset)
        local frame_x = d.x - frame_pad
        local frame_w = d.total_w + frame_pad * 2
        right = (frame_x + chrome_inset) + (frame_w - chrome_inset * 2)  -- == chrome_x + chrome_w
        right = right - sc(LM.tab_right_trim)   -- legacy extra pull-in of the tab row right edge
    else
        right = d.x + d.total_w
    end
    local x = d.preview_x + sc(LM.tab_x_offset)
    local w = math.max(1, (right - x) + sc(LM.tab_w_adjust))
    local y = d.body_y + sc(LM.tab_y_offset)
    local h = math.max(sc(6), sc(cfg.row_height + LM.tab_h_adjust + 2))
    return x, w, y, h
end

local function clamp(value, min_value, max_value)
    if value < min_value then return min_value end
    if value > max_value then return max_value end
    return value
end

local function add_object(obj)
    state.objects[#state.objects + 1] = obj
    return obj
end

local function add_image(obj)
    state.image_objects[#state.image_objects + 1] = obj
    return obj
end

local function add_decor_image(obj)
    state.decor_images[#state.decor_images + 1] = obj
    return obj
end

local function image_obj()
    local obj = images.new({
        draggable = false,
        visible = false,
        color = { alpha = 190, red = 255, green = 255, blue = 255 },
        size = { width = cfg.icon_size, height = cfg.icon_size },
        texture = { fit = true, path = '' },
    })
    return add_image(obj)
end

local function rect_obj(color)
    local obj = images.new({
        draggable = false,
        visible = false,
        color = {
            alpha = color and color[1] or 255,
            red = color and color[2] or 255,
            green = color and color[3] or 255,
            blue = color and color[4] or 255,
        },
        size = { width = 1, height = 1 },
        texture = { fit = false, path = RECT_TEXTURE },
    })
    if obj.path then obj:path(RECT_TEXTURE) end
    if obj.fit then obj:fit(false) end
    return add_decor_image(obj)
end

local function set_rect(obj, x, y, width, height, color)
    if not obj then return end
    obj:pos(math.floor(x), math.floor(y))
    obj:size(math.max(1, math.floor(width)), math.max(1, math.floor(height)))
    if obj.path then obj:path(RECT_TEXTURE) end
    if color then
        if obj.color then obj:color(color[2], color[3], color[4]) end
        if obj.alpha then obj:alpha(oa(color[1])) end
    end
    obj:visible(state.visible)
end

-- Position+tint a tab highlight image (rounded-top tab_hl.png texture stretched
-- to the tab cell), so active/hover highlights match the baked tab shape rather
-- than being a plain rectangle.
local function set_tab_hl(obj, x, y, width, height, color)
    if not obj then return end
    obj:pos(math.floor(x), math.floor(y))
    obj:size(math.max(1, math.floor(width)), math.max(1, math.floor(height)))
    if obj.path then obj:path(TAB_HL_TEXTURE) end
    -- fit=false → texture is stretched to the EXACT size set (same exact-size path
    -- every rect_obj uses).  fit=true was scaling the 256x64 texture by aspect,
    -- making the highlight taller than the 16px tab row and spilling into content.
    if obj.fit  then obj:fit(false) end
    if color then
        if obj.color then obj:color(color[2], color[3], color[4]) end
        if obj.alpha then obj:alpha(oa(color[1])) end
    end
    obj:visible(state.visible)
end

local function text_obj()
    local obj = texts.new({ flags = { draggable = false } })
    obj:font(cfg.font)
    obj:size(sc(cfg.font_size))
    obj:stroke_transparency(255)
    obj:bg_visible(false)
    obj:bg_alpha(0)
    obj:visible(false)
    return add_object(obj)
end

local function panel_obj(width, rows)
    local obj = text_obj()
    obj:bg_visible(true)
    obj:bg_color(cfg.panel_bg[2], cfg.panel_bg[3], cfg.panel_bg[4])
    obj:bg_alpha(cfg.panel_bg[1])
    obj:color(cfg.row_fg_dim[1], cfg.row_fg_dim[2], cfg.row_fg_dim[3])

    local line = string.rep(' ', cols(width))
    local lines = {}
    for _ = 1, rows do
        lines[#lines + 1] = line
    end
    obj:text(table.concat(lines, '\n'))
    return obj
end

local function fill_panel(obj, width, rows)
    local line = string.rep(' ', cols(width))
    local lines = {}
    for _ = 1, rows do
        lines[#lines + 1] = line
    end
    obj:text(table.concat(lines, '\n'))
end

local function rendered_width(obj, fallback)
    if obj and obj.extents then
        local width = obj:extents()
        if type(width) == 'number' and width > 0 then
            return width
        end
    end
    return fallback
end

local function title_obj()
    local obj = text_obj()
    obj:bg_visible(true)
    obj:bg_color(cfg.title_bg[2], cfg.title_bg[3], cfg.title_bg[4])
    obj:bg_alpha(cfg.title_bg[1])
    obj:color(cfg.title_fg[1], cfg.title_fg[2], cfg.title_fg[3])
    return obj
end

local function set_color(obj, color)
    obj:color(color[1], color[2], color[3])
end

local function set_title_active(obj, active)
    local bg = active and cfg.active_title_bg or cfg.title_bg
    local fg = active and cfg.active_title_fg or cfg.title_fg
    obj:bg_color(bg[2], bg[3], bg[4])
    obj:bg_alpha(bg[1])
    obj:color(fg[1], fg[2], fg[3])
end

local function truncate(text, max_cols)
    text = tostring(text or '')
    if #text <= max_cols then return text end
    if max_cols <= 3 then return text:sub(1, max_cols) end
    return text:sub(1, max_cols - 3) .. '...'
end

local function pad(text, max_cols)
    text = truncate(text, max_cols)
    return text .. string.rep(' ', math.max(0, max_cols - #text))
end

local function center_pad(text, max_cols)
    text = truncate(text, max_cols)
    local extra = math.max(0, max_cols - #text)
    local left = math.floor(extra / 2)
    local right = extra - left
    return string.rep(' ', left) .. text .. string.rep(' ', right)
end

local function node_kind(node)
    if not node then return ' ' end
    if node.children and #node.children > 0 then
        return node.expanded and '-' or '+'
    end
    return node.has_gear and '*' or ' '
end

local function asset_path(relative)
    local base = windower and windower.windower_path or ''
    if base ~= '' then
        if base:sub(-1) ~= '/' and base:sub(-1) ~= '\\' then
            base = base .. '/'
        end
        return base .. relative
    end
    return 'C:/Program Files (x86)/Windower/' .. relative
end

local ICONS = {
    current = asset_path('addons/trust/assets/icons/cursor_slot.png'),
    action = asset_path('addons/trust/assets/icons/icon_job_ability_light.png'),
    magic = asset_path('addons/trust/assets/icons/icon_light.png'),
    song = asset_path('addons/trust/assets/icons/icon_singing_light.png'),
    movement = asset_path('addons/trust/assets/icons/icon_wind.png'),
    defense = asset_path('addons/trust/assets/icons/icon_earth.png'),
    dark = asset_path('addons/trust/assets/icons/icon_dark.png'),
    fire = asset_path('addons/trust/assets/icons/icon_fire.png'),
    water = asset_path('addons/trust/assets/icons/icon_water.png'),
    weapon = asset_path('addons/trust/assets/icons/icon_bullet.png'),
    timer = asset_path('addons/trust/assets/icons/icon_timer.png'),
    cursor = asset_path('addons/trust/assets/icons/cursor.png'),
}

local function node_icon(node)
    local key = tostring(node and node.key or ''):lower()
    local path = {}
    if node and node.path then
        for _, part in ipairs(node.path) do
            path[#path + 1] = tostring(part):lower()
        end
    end
    local joined = table.concat(path, ' ')

    if key:find('song', 1, true) or key:find('lullaby', 1, true) or joined:find('song', 1, true) then
        return ICONS.song
    elseif key:find('magic', 1, true) or key == 'precast' or key == 'midcast' or joined:find('magic', 1, true) then
        return ICONS.magic
    elseif key:find('movement', 1, true) or key:find('kiting', 1, true) or key:find('move', 1, true) then
        return ICONS.movement
    elseif key:find('defense', 1, true) or key:find('defensive', 1, true) or key:find('pdt', 1, true) or key:find('mdt', 1, true) then
        return ICONS.defense
    elseif key:find('weapon', 1, true) or key:find('ranged', 1, true) or joined:find('weapon', 1, true) then
        return ICONS.weapon
    elseif key:find('dark', 1, true) then
        return ICONS.dark
    elseif key:find('elemental', 1, true) or key:find('nuk', 1, true) then
        return ICONS.fire
    elseif key:find('cure', 1, true) or key:find('healing', 1, true) then
        return ICONS.water
    elseif key:find('current', 1, true) or key == 'idle' or key == 'engaged' or key == 'resting' then
        return ICONS.current
    elseif key:find('action', 1, true) or key:find('abilit', 1, true) or key:find('waltz', 1, true) then
        return ICONS.action
    elseif node and node.has_gear then
        return ICONS.cursor
    end

    return ICONS.timer
end

local function path_string(node)
    if not node or not node.path then return '' end
    return tree.path_string(node)
end

local function walk_display(node, fn)
    if not node then return nil end
    local result = fn(node)
    if result then return result end
    for _, child in ipairs(node.children or {}) do
        result = walk_display(child, fn)
        if result then return result end
    end
    return nil
end

local function find_node_by_path(path)
    path = tostring(path or '')
    if path == '' then return nil end

    return walk_display(state.root, function(node)
        if node ~= state.root and not node.virtual and path_string(node) == path then
            return node
        end
    end)
end

local function find_virtual_folder(id)
    id = tostring(id or '')
    if id == '' then return nil end

    return walk_display(state.root, function(node)
        if node and node.virtual and tostring(node.virtual_id or '') == id then
            return node
        end
    end)
end

local function selected_entry()
    if state.cursor < 1 or state.cursor > #state.flat then return nil end
    return state.flat[state.cursor]
end

local function selected_node()
    local entry = selected_entry()
    return entry and entry.node or nil
end

local function is_equippable_leaf(node)
    return node and node.has_gear and not (node.children and #node.children > 0)
end

local function notify_selection_changed()
    local node = selected_node()
    if node == state.last_selection_node then return end
    state.last_selection_node = node
    if state.selection_callback then
        state.selection_callback(node)
    end
end

local function flat_index_for_node(node)
    for i, entry in ipairs(state.flat) do
        if entry.node == node then return i end
    end
    return nil
end

local function find_display_parent(target)
    if not state.root or not target then return nil end

    local function walk(parent)
        for _, child in ipairs(parent.children or {}) do
            if child == target then return parent end
            local found = walk(child)
            if found then return found end
        end
        return nil
    end

    return walk(state.root)
end

local function find_parent(node)
    local display_parent = find_display_parent(node)
    if display_parent then return display_parent end

    if not state.root or not node or not node.path or #node.path <= 2 then return nil end
    local parent_path = {}
    for i = 1, #node.path - 1 do
        parent_path[i] = node.path[i]
    end
    return tree.find(state.root, parent_path)
end

local function expand_ancestors(node)
    if not state.root or not node then return end

    local display_path = {}

    local function walk(parent)
        for _, child in ipairs(parent.children or {}) do
            display_path[#display_path + 1] = child
            if child == node then return true end
            if walk(child) then return true end
            display_path[#display_path] = nil
        end
        return false
    end

    if walk(state.root) then
        for i = 1, #display_path - 1 do
            display_path[i].expanded = true
        end
        return
    end

    if not node.path then return end

    local path = { node.path[1] }
    for i = 2, #node.path - 1 do
        path[i] = node.path[i]
        local ancestor = tree.find(state.root, path)
        if ancestor then ancestor.expanded = true end
    end
end

local function ensure_cursor_visible()
    local max_scroll = math.max(0, #state.flat - cfg.visible_rows)
    state.scroll = clamp(state.scroll, 0, max_scroll)

    if state.cursor <= state.scroll then
        state.scroll = math.max(0, state.cursor - 1)
    elseif state.cursor > state.scroll + cfg.visible_rows then
        state.scroll = state.cursor - cfg.visible_rows
    end
end

local function select_node(node)
    if not node then return end
    expand_ancestors(node)
    state.flat = tree.flatten(state.root)
    local idx = flat_index_for_node(node)
    if idx then
        state.cursor = idx
        ensure_cursor_visible()
    end
end

local function active_list_node()
    local node = selected_node()
    if not node then return state.root end
    if node.children and #node.children > 0 then return node end
    return find_parent(node) or node
end

local function active_list_items()
    local node = active_list_node()
    return node and node.children or {}
end

local function wrap_into(out, text, color, width)
    local max_cols = math.max(16, cols(width) - 2)
    local line = tostring(text or '')
    local prefix = line:match('^(%s*)') or ''

    repeat
        if #line <= max_cols then
            out[#out + 1] = { text = line, color = color }
            return
        end

        local cut
        for i = max_cols, #prefix + 2, -1 do
            local ch = line:sub(i, i)
            if ch == ' ' or ch == ',' or ch == '/' then
                cut = i
                break
            end
        end
        cut = cut or max_cols
        out[#out + 1] = { text = line:sub(1, cut):gsub('%s+$', ''), color = color }
        line = prefix .. line:sub(cut + 1):gsub('^%s+', '')
    until line == ''
end

local function add_line(out, text, color)
    out[#out + 1] = { text = tostring(text or ''), color = color or cfg.row_fg_set }
end

-- Display-only formatting for interior section headers.  Strips the old ASCII
-- "== ... ==" wrapper; the gold colour (applied below) is what marks it as a
-- header.  ASCII-only by design — Windower's texts overlay mojibakes multibyte
-- glyphs, so no decorative ◆/— is used here.
local function format_section_header(title)
    return tostring(title or '')
end

local function add_section(out, title)
    add_line(out, '', cfg.row_fg_set)
    add_line(out, format_section_header(title), cfg.row_fg_gold)
end

local function safe(value, fallback)
    if value == nil or tostring(value) == '' then return fallback or 'Unknown' end
    return tostring(value)
end

local function list_count(t)
    return type(t) == 'table' and #t or 0
end

local function source_line(node, info)
    local assignment = node and node.assignment or nil
    local file = info.source_file or info.file or assignment and assignment.source_file or assignment and assignment.file
    local line = info.line or info.start_line or assignment and assignment.line or assignment and assignment.start_line
    local end_line = info.end_line or assignment and assignment.end_line

    if file and line and end_line and tostring(line) ~= tostring(end_line) then
        return string.format('%s:%s-%s', tostring(file), tostring(line), tostring(end_line))
    elseif file and line then
        return string.format('%s:%s', tostring(file), tostring(line))
    elseif line then
        return 'line ' .. tostring(line)
    end
    return safe(info.source, 'Unknown source')
end

local function add_lua_source(out, node, width)
    local assignment = node and node.assignment or nil
    local source = assignment and assignment.source_text or ''
    local start_line = tonumber(assignment and assignment.line) or 1

    add_section(out, 'Lua Source')
    if source == '' then
        wrap_into(out, 'No source text captured for this node.', cfg.row_fg_dim, width)
        return
    end

    local line_no = start_line
    source = source:gsub('\r\n', '\n'):gsub('\r', '\n')
    if source:sub(-1) ~= '\n' then source = source .. '\n' end

    for line in source:gmatch('(.-)\n') do
        out[#out + 1] = {
            text = string.format('%4d | %s', line_no, line),
            color = cfg.row_fg_set,
            source_line = true,
        }
        line_no = line_no + 1
    end
end

local SLOT_LABELS = {
    main = 'Main',
    sub = 'Sub',
    range = 'Range',
    ammo = 'Ammo',
    head = 'Head',
    body = 'Body',
    hands = 'Hands',
    legs = 'Legs',
    feet = 'Feet',
    neck = 'Neck',
    waist = 'Waist',
    back = 'Back',
    ear1 = 'Ear 1',
    ear2 = 'Ear 2',
    left_ear = 'Ear 1',
    right_ear = 'Ear 2',
    lear = 'Ear 1',
    rear = 'Ear 2',
    ring1 = 'Ring 1',
    ring2 = 'Ring 2',
    left_ring = 'Ring 1',
    right_ring = 'Ring 2',
    lring = 'Ring 1',
    rring = 'Ring 2',
}

local function slot_label(slot)
    local key = tostring(slot or ''):lower()
    return SLOT_LABELS[key] or tostring(slot or 'Slot')
end

local function trim(text)
    return tostring(text or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function strip_outer_quotes(text)
    local value = trim(text)
    return value:match('^"(.*)"$') or value:match("^'(.*)'$") or value
end

local function extract_augments(raw)
    local text = tostring(raw or '')
    local aug_key = text:find('augments%s*=%s*{')
    if not aug_key then return nil end

    local function decode_lua_escape(next_ch)
        if next_ch == 'n' then return '\n' end
        if next_ch == 'r' then return '\r' end
        if next_ch == 't' then return '\t' end
        if next_ch == '\\' then return '\\' end
        if next_ch == '"' then return '"' end
        if next_ch == "'" then return "'" end
        return next_ch
    end

    local function parse_quoted(text, pos)
        local quote = text:sub(pos, pos)
        local i = pos + 1
        local out = {}
        while i <= #text do
            local ch = text:sub(i, i)
            if ch == '\\' then
                local next_ch = text:sub(i + 1, i + 1)
                if next_ch == '' then break end
                out[#out + 1] = decode_lua_escape(next_ch)
                i = i + 2
            elseif ch == quote then
                return table.concat(out), i + 1
            else
                out[#out + 1] = ch
                i = i + 1
            end
        end
        return nil, pos
    end

    local function parse_balanced(text, pos, open_char, close_char)
        local depth = 0
        local i = pos
        local start = pos
        local quote = nil
        while i <= #text do
            local ch = text:sub(i, i)
            if quote then
                if ch == '\\' then
                    i = i + 2
                elseif ch == quote then
                    quote = nil
                    i = i + 1
                else
                    i = i + 1
                end
            elseif ch == '"' or ch == "'" then
                quote = ch
                i = i + 1
            elseif ch == open_char then
                depth = depth + 1
                i = i + 1
            elseif ch == close_char then
                depth = depth - 1
                i = i + 1
                if depth == 0 then
                    return text:sub(start, i - 1), i
                end
            else
                i = i + 1
            end
        end
        return nil, pos
    end

    local start = text:find('{', aug_key)
    if not start then return nil end
    local block = parse_balanced(text, start, '{', '}')
    if not block then return nil end

    local inner = block:sub(2, -2)
    local augments = {}
    local pos = 1
    while pos <= #inner do
        local ch = inner:sub(pos, pos)
        if ch == '"' or ch == "'" then
            local augment, next_pos = parse_quoted(inner, pos)
            if augment then
                augments[#augments + 1] = augment
                pos = next_pos
            else
                pos = pos + 1
            end
        else
            pos = pos + 1
        end
    end

    if #augments == 0 then return nil end
    return augments
end

local function gear_reference_key(value)
    local raw = trim(value)
    return raw:match('^(gear%.[%a_][%w_]*)$')
end

local function gear_display(value)
    local raw = tostring(value or '')
    if raw == 'empty' then
        return 'empty', nil, false, false, nil
    end
    local reference = gear_reference_key(raw)
    if reference and state.gear_reference_items[reference] then
        local resolved = state.gear_reference_items[reference]
        if type(resolved) == 'table' then
            return resolved.name or raw, resolved.augments, resolved.augmented == true, false, reference
        end
        return resolved, nil, false, false, reference
    end

    local name = raw:match('name%s*=%s*"([^"]+)"') or raw:match("name%s*=%s*'([^']+)'")
    if name then
        local augments = extract_augments(raw)
        return name, augments, type(augments) == 'table' and #augments > 0, false, reference
    end

    return strip_outer_quotes(raw), nil, false, reference ~= nil, reference
end

local function comparable_gear_value(value)
    local raw = trim(value)
    if raw == '' then return false end
    if raw == 'empty' then return true end
    if gear_reference_key(raw) then
        return true
    end
    return raw:sub(1, 1) == '"' or raw:sub(1, 1) == "'" or raw:find('name%s*=', 1) ~= nil
end

local function equipped_item_for_slot(slot)
    local canonical = gear_slots.canonical(slot)
    if not canonical then return nil end
    return state.current_equipment.slots and state.current_equipment.slots[canonical] or nil
end

-- Pairs of slots that FFXI/GearSwap may swap (e.g. both ears are
-- interchangeable for equip purposes).  Keyed by CANONICAL slot name.
local PAIRED_SLOTS = {
    left_ear   = 'right_ear',
    right_ear  = 'left_ear',
    left_ring  = 'right_ring',
    right_ring = 'left_ring',
}

local function normalize_item_name(name)
    local text = tostring(name or '')
    text = text:gsub("%c", " ")
    text = text:gsub("’", "'"):gsub("‘", "'")
    text = text:gsub("\194\160", " ")
    text = text:lower()
    text = text:gsub('%s+', ' ')
    text = text:gsub('^%s+', ''):gsub('%s+$', '')
    return text
end

local function same_name(left, right)
    return normalize_item_name(left) == normalize_item_name(right)
end

local resource_item_lookup
local resource_item_lookup_by_abbrev
local resource_lookup_language

local function normalize_lookup_token(text)
    text = normalize_item_name(text)
    text = text:gsub('%p+', ' ')
    text = text:gsub('%s+', ' ')
    text = text:gsub('^%s+', ''):gsub('%s+$', '')
    return text
end

local function tokenize_lookup_name(name)
    local tokens = {}
    local text = normalize_lookup_token(name)
    if text == '' then return tokens end
    for token in text:gmatch('[^%s]+') do
        if token ~= '' then
            tokens[#tokens + 1] = token
        end
    end
    return tokens
end

local function token_prefix_score(resource_token, query_token)
    resource_token = normalize_lookup_token(resource_token)
    query_token = normalize_lookup_token(query_token)
    if resource_token == '' or query_token == '' then return false end
    if resource_token == query_token then return true end

    local plain_resource = resource_token:gsub('%W', '')
    local plain_query = query_token:gsub('%W', '')
    if plain_resource == plain_query then return true end

    if #resource_token >= 3 and query_token:sub(1, #resource_token) == resource_token then
        return true
    end

    if #plain_resource >= 3 and plain_query:sub(1, #plain_resource) == plain_resource then
        return true
    end

    return false
end

local function current_resource_language()
    local info = windower and windower.ffxi and windower.ffxi.get_info and windower.ffxi.get_info() or nil
    local lang = (info and info.language) or rawget(_G, 'language') or 'english'
    lang = tostring(lang or 'english'):lower()
    lang = lang:gsub('%s+', '_')
    if lang == 'en' then return 'english' end
    if lang == 'jp' then return 'japanese' end
    return lang ~= '' and lang or 'english'
end

local function reset_resource_lookup_cache_if_needed()
    local lang = current_resource_language()
    if resource_lookup_language ~= lang then
        resource_lookup_language = lang
        resource_item_lookup = nil
        resource_item_lookup_by_abbrev = nil
    end
end

local function resource_name_variants(item)
    local lang = current_resource_language()
    local variants = {}
    local seen = {}

    local function add(field)
        local value = item and item[field]
        if value == nil or value == '' then return end
        local key = field .. '\31' .. tostring(value)
        if seen[key] then return end
        seen[key] = true
        variants[#variants + 1] = {
            field = field,
            name = value,
            normalized = normalize_lookup_token(value),
            tokens = tokenize_lookup_name(value),
        }
    end

    add(lang)
    add(lang .. '_log')
    if lang ~= 'english' then
        add('english')
        add('english_log')
    end
    if lang ~= 'name' then
        add('name')
    end
    if lang ~= 'en' then
        add('en')
    end

    return variants
end

local function resource_lookup_result_for_name(name)
    local raw = tostring(name or '')
    if trim(raw) == 'empty' then
        return nil
    end
    local normalized = normalize_lookup_token(raw)
    if normalized == '' then
        return nil
    end

    reset_resource_lookup_cache_if_needed()

    if not resource_item_lookup then
        resource_item_lookup = {}
        resource_item_lookup_by_abbrev = {}
        for id, item in pairs(res.items or {}) do
            local variants = resource_name_variants(item)
            for _, variant in ipairs(variants) do
                if variant.normalized ~= '' then
                    resource_item_lookup[variant.normalized] = resource_item_lookup[variant.normalized] or {}
                    resource_item_lookup[variant.normalized][#resource_item_lookup[variant.normalized] + 1] = {
                        id = id,
                        field = variant.field,
                        name = variant.name,
                        normalized = variant.normalized,
                    }
                end

                if #variant.tokens > 0 then
                    local abbrev_key = table.concat(variant.tokens, '\31')
                    resource_item_lookup_by_abbrev[abbrev_key] = resource_item_lookup_by_abbrev[abbrev_key] or {}
                    resource_item_lookup_by_abbrev[abbrev_key][#resource_item_lookup_by_abbrev[abbrev_key] + 1] = {
                        id = id,
                        field = variant.field,
                        name = variant.name,
                        normalized = variant.normalized,
                    }
                end
            end
        end
    end

    local result = {
        normalized = normalized,
        exact_id = nil,
        exact_name = nil,
        exact_field = nil,
        exact_candidates = {},
        abbreviation_candidates = {},
        matched_id = nil,
        matched_name = nil,
        matched_field = nil,
        matched_english = nil,
        matched_english_log = nil,
        unresolved = false,
    }

    local exact_matches = {}
    local seen_exact_ids = {}
    for _, candidate in ipairs(resource_item_lookup[normalized] or {}) do
        if not seen_exact_ids[candidate.id] then
            seen_exact_ids[candidate.id] = true
            exact_matches[#exact_matches + 1] = candidate
        end
    end
    if #exact_matches == 1 then
        local match = exact_matches[1]
        local item = res.items and res.items[match.id] or nil
        result.exact_id = match.id
        result.exact_name = match.name
        result.exact_field = match.field
        result.matched_id = match.id
        result.matched_name = match.name
        result.matched_field = match.field
        result.matched_english = item and (item.english or item.en or item.name) or nil
        result.matched_english_log = item and item.english_log or nil
        return result
    elseif #exact_matches > 1 then
        result.exact_candidates = exact_matches
        result.unresolved = true
        return result
    end

    local query_tokens = tokenize_lookup_name(raw)
    if #query_tokens == 0 then
        result.unresolved = true
        return result
    end

    local candidates = {}
    for id, item in pairs(res.items or {}) do
        local variants = resource_name_variants(item)
        local matched_variant = nil
        for _, variant in ipairs(variants) do
            if #variant.tokens == #query_tokens and #variant.tokens > 0 then
                local ok = true
                for i = 1, #query_tokens do
                    if not token_prefix_score(variant.tokens[i], query_tokens[i]) then
                        ok = false
                        break
                    end
                end
                if ok then
                    matched_variant = variant
                    break
                end
            end
        end
        if matched_variant then
            candidates[#candidates + 1] = {
                id = id,
                field = matched_variant.field,
                name = matched_variant.name,
                english = item and item.english or nil,
                english_log = item and item.english_log or nil,
            }
        end
    end

    result.abbreviation_candidates = candidates
    if #candidates == 1 then
        result.matched_id = candidates[1].id
        result.matched_name = candidates[1].name
        result.matched_field = candidates[1].field
        result.matched_english = candidates[1].english
        result.matched_english_log = candidates[1].english_log
    else
        result.unresolved = true
    end

    return result
end

local function resource_id_for_name(name)
    local result = resource_lookup_result_for_name(name)
    return result and result.matched_id or nil
end

local function augment_list(value)
    local out = {}
    if value == nil then return out end

    if type(value) == 'table' then
        for _, augment in ipairs(value) do
            augment = trim(augment)
            if augment ~= '' then
                out[#out + 1] = augment
            end
        end
        return out
    end

    local text = trim(value)
    if text == '' then return out end
    for augment in text:gmatch('[^;]+') do
        augment = trim(augment)
        if augment ~= '' then
            out[#out + 1] = augment
        end
    end
    return out
end

local function normalize_augment_label(text)
    text = tostring(text or '')
    text = text:gsub("%c", " ")
    text = text:gsub("[" .. '"' .. "‘’“”" .. "]", "")
    text = text:gsub("\194\160", " ")
    text = text:lower()
    text = text:gsub('%s+', ' ')
    text = text:gsub('^%s+', ''):gsub('%s+$', '')
    return text
end

local function augment_signature(value)
    local numeric = {}
    local raw = {}

    local function add_raw(text)
        text = normalize_augment_label(text)
        if text ~= '' then
            raw[text] = (raw[text] or 0) + 1
        end
    end

    local function add_numeric(label, amount, is_percent)
        label = normalize_augment_label(label)
        if label == '' then
            add_raw(tostring(amount) .. (is_percent and '%' or ''))
            return
        end
        local key = label .. '|' .. (is_percent and 'pct' or 'num')
        numeric[key] = (numeric[key] or 0) + amount
    end

    local function consume(fragment)
        fragment = trim(fragment)
        if fragment == '' or fragment == 'none' then return end

        local pos = 1
        local found = false
        while pos <= #fragment do
            local s, e, amount_text = fragment:find('([+-]?%d+%%?)', pos)
            if not s then
                local tail = trim(fragment:sub(pos))
                if tail ~= '' then add_raw(tail) end
                break
            end

            local label = trim(fragment:sub(pos, s - 1))
            local amount = tonumber((amount_text or ''):gsub('%%', ''))
            if amount then
                add_numeric(label, amount, amount_text:sub(-1) == '%')
                found = true
            else
                add_raw(fragment:sub(pos, e))
            end
            pos = e + 1
        end

        if not found and next(raw) == nil and next(numeric) == nil then
            add_raw(fragment)
        end
    end

    if type(value) == 'table' then
        for _, augment in ipairs(value) do
            consume(augment)
        end
    else
        for fragment in tostring(value or ''):gmatch('[^;]+') do
            consume(fragment)
        end
    end

    return { numeric = numeric, raw = raw }
end

local function signature_has_data(sig)
    return sig and (next(sig.numeric or {}) ~= nil or next(sig.raw or {}) ~= nil)
end

local function augment_signature_of(value)
    if signature_has_data(value) then
        return value
    end
    return augment_signature(value)
end

local function same_augment_signature(left, right)
    local a = augment_signature_of(left)
    local b = augment_signature_of(right)
    if not signature_has_data(a) and not signature_has_data(b) then
        return true
    end
    if signature_has_data(a) ~= signature_has_data(b) then
        return false
    end

    for key, value in pairs(a.numeric or {}) do
        if (b.numeric or {})[key] ~= value then
            return false
        end
    end
    for key, value in pairs(b.numeric or {}) do
        if (a.numeric or {})[key] ~= value then
            return false
        end
    end

    for key, value in pairs(a.raw or {}) do
        if (b.raw or {})[key] ~= value then
            return false
        end
    end
    for key, value in pairs(b.raw or {}) do
        if (a.raw or {})[key] ~= value then
            return false
        end
    end

    return true
end

local function same_augments(left, right)
    local a = augment_list(left)
    local b = augment_list(right)
    if #a == 0 then return true end
    if #b == 0 then return false end

    local ok, matched = pcall(extdata.compare_augments, a, b)
    if ok then
        return matched == true
    end

    if #a ~= #b then return false end
    local seen = {}
    for _, augment in ipairs(b) do
        local key = normalize_item_name(augment)
        seen[key] = (seen[key] or 0) + 1
    end
    for _, augment in ipairs(a) do
        local key = normalize_item_name(augment)
        if not seen[key] or seen[key] == 0 then
            return false
        end
        seen[key] = seen[key] - 1
    end
    return true
end

-- Returns the item from the OPPOSITE paired slot if it satisfies spec,
-- plus the name of that opposite slot.  Returns nil, nil otherwise.
-- Used ONLY for display; save/write logic is never affected.
-- Rules:
--   * Slot must be in PAIRED_SLOTS.
--   * Opposite slot must have an item equipped.
--   * Item ID (or name when ID is unresolved) must match spec.
--   * If spec requires augments they must match exactly, or extdata
--     must be unavailable (can't verify but item is there).
--   * Augment MISMATCH in the opposite slot → not a valid paired match.
local function paired_slot_match(spec, canonical_slot)
    local opposite = PAIRED_SLOTS[canonical_slot]
    if not opposite then return nil, nil end
    local slots_tbl = state.current_equipment.slots
    local candidate = slots_tbl and slots_tbl[opposite]
    if not candidate or candidate.empty then return nil, nil end

    -- ID / name check (mirrors primary id_match logic).
    local id_ok = spec.item_id ~= nil and candidate.id == spec.item_id
    if not id_ok and spec.display_name then
        if spec.item_id == nil or same_name(candidate.name, spec.display_name) then
            id_ok = same_name(candidate.name, spec.display_name)
        end
    end
    if not id_ok then return nil, nil end

    -- Augment check.
    if spec.has_augments then
        if candidate.augments_available == false then
            -- Cannot verify augments but item is in the slot; accept it.
            return candidate, opposite
        end
        if not same_augments(spec.augments, candidate.augments) then
            -- Augment mismatch in the opposite slot is not a valid match.
            -- (This avoids confusing a wrong-augment copy with the intended item.)
            return nil, nil
        end
    end

    return candidate, opposite
end

local function resolve_gear_spec(value)
    local display_name, augments, augmented, unresolved, reference = gear_display(value)
    local aug_list = augment_list(augments)
    local spec = {
        display_name = display_name,
        item_id = nil,
        resolved_name = nil,
        augments = aug_list,
        expected_augments = aug_list,
        expected_augments_raw = augments,
        has_augments = augmented == true or #aug_list > 0,
        unresolved = unresolved == true,
        lookup = nil,
        unresolved_ref = nil,
        gear_reference = reference,
    }

    if trim(value) == 'empty' then
        spec.expected_empty = true
        spec.display_name = 'empty'
        spec.has_augments = false
        return spec
    end

    if reference and not state.gear_reference_items[reference] then
        spec.unresolved_ref = reference
        spec.unresolved = true
        return spec
    end

    local lookup = display_name and resource_lookup_result_for_name(display_name) or nil
    spec.lookup = lookup
    if lookup then
        spec.item_id = lookup.matched_id
        spec.resolved_name = lookup.matched_name
        spec.lookup_exact_id = lookup.exact_id
        spec.lookup_exact_name = lookup.exact_name
        spec.lookup_exact_field = lookup.exact_field
        spec.lookup_exact_candidates = lookup.exact_candidates
        spec.lookup_candidates = lookup.abbreviation_candidates
        spec.lookup_normalized = lookup.normalized
        spec.lookup_unresolved = lookup.unresolved
        spec.lookup_matched_field = lookup.matched_field
        spec.lookup_matched_english = lookup.matched_english
        spec.lookup_matched_english_log = lookup.matched_english_log
        if lookup.unresolved then
            spec.unresolved = true
        end
    end

    -- If the resource lookup returned multiple exact ID candidates (unresolved),
    -- try to disambiguate using the player's owned/equipped inventory.
    -- Only resolves when exactly one distinct candidate ID is found in inventory;
    -- if two different candidate IDs are owned, leaves spec.item_id nil (still ambiguous).
    if spec.lookup_unresolved and spec.lookup_exact_candidates and not spec.item_id then
        local owned = (state.inventory_locations.items or {})[normalize_item_name(display_name)] or {}
        local found_id = nil
        local conflict = false
        for _, loc in ipairs(owned) do
            local is_candidate = false
            for _, cand in ipairs(spec.lookup_exact_candidates) do
                if cand.id == loc.id then is_candidate = true; break end
            end
            if is_candidate then
                if found_id == nil then
                    found_id = loc.id
                elseif found_id ~= loc.id then
                    conflict = true; break
                end
            end
        end
        if found_id and not conflict then
            spec.item_id = found_id
            spec.disambiguated_by_inventory = true
            spec.unresolved = false
        end
    end

    return spec
end

local function bag_label(id)
    for _, bag in ipairs(state.inventory_locations.bags or {}) do
        if bag.id == id then return bag.label end
    end
    if id == 0 then return 'Inventory' end
    return id and ('Bag ' .. tostring(id)) or 'Unknown'
end

local function item_locations(name)
    return (state.inventory_locations.items or {})[normalize_item_name(name)] or {}
end

local function item_locations_by_id(item_id)
    return (state.inventory_locations.items_by_id or {})[item_id] or {}
end

local function bag_access(id)
    for _, bag in ipairs(state.inventory_locations.bags or {}) do
        if bag.id == id then
            return bag.available == true
        end
    end
    return nil
end

local function best_location_exact(spec)
    if spec and spec.expected_empty then
        return nil, false
    end
    if spec and spec.unresolved_ref then
        return nil, false
    end
    local locations = {}
    if spec and spec.item_id then
        locations = item_locations_by_id(spec.item_id)
    elseif spec and spec.display_name then
        locations = item_locations(spec.display_name)
    end

    local function is_exact_location(location)
        if not location then return false end
        if spec and spec.has_augments then
            return same_augments(spec.augments, location.augments)
        end
        return true
    end

    for _, location in ipairs(locations) do
        if is_exact_location(location) and location.equip_ready and (location.available == true or bag_access(location.bag)) then
            return location, false
        end
    end

    for _, location in ipairs(locations) do
        if is_exact_location(location) then
            return location, location.available == false or not bag_access(location.bag)
        end
    end

    return nil, false
end

local function where_badge_from_label(label)
    local text = tostring(label or ''):lower()

    if text == 'inventory' then
        return 'INV'
    elseif text:find('safe 2', 1, true) then
        return 'SAFE2'
    elseif text:find('safe', 1, true) then
        return 'SAFE1'
    elseif text == 'storage' then
        return 'STOR'
    elseif text:find('locker', 1, true) then
        return 'LOCK'
    elseif text:find('satchel', 1, true) then
        return 'SATCH'
    elseif text:find('sack', 1, true) then
        return 'SACK'
    elseif text:find('case', 1, true) then
        return 'CASE'
    else
        local ward = text:match('wardrobe%s*(%d+)')
        if ward then
            return 'WRD' .. ward
        end
    end

    return 'UNKN'
end

local function gear_row_status(item, set_path)
    local state_out = {
        status = 'MISS',
        badge = 'MISS',
        color = cfg.row_fg_red,
        reason = 'No matching equipped item found.',
        spec = nil,
        equipped = nil,
        expected_augments = {},
        expected_augments_raw = nil,
        equipped_augments = {},
        equipped_augments_available = nil,
        expected_item_id = nil,
        equipped_item_id = nil,
        id_match = false,
        augment_match = false,
    }

    if not item then
        state_out.status = 'UNKN'
        state_out.badge = 'UNKN'
        state_out.color = cfg.row_fg_gold
        state_out.reason = 'No gear row is available.'
        return state_out
    end

    if not comparable_gear_value(item.value) then
        state_out.status = 'UNKN'
        state_out.badge = 'UNKN'
        state_out.color = cfg.row_fg_gold
        state_out.reason = 'Row value is not comparable.'
        return state_out
    end

    local spec = resolve_gear_spec(item.value)
    local equipped = equipped_item_for_slot(item.slot)
    local expected = trim(item.value)

    state_out.spec = spec
    state_out.equipped = equipped
    state_out.expected_augments = spec.expected_augments or spec.augments or {}
    state_out.expected_augments_raw = spec.expected_augments_raw
    state_out.equipped_augments = (equipped and not equipped.empty and equipped.augments) or {}
    state_out.equipped_augments_available = equipped and not equipped.empty and equipped.augments_available
    state_out.expected_item_id = spec.item_id
    state_out.equipped_item_id = (equipped and not equipped.empty) and equipped.id or nil

    if spec.unresolved_ref then
        state_out.status = 'BADREF'
        state_out.badge = 'BADREF'
        state_out.color = cfg.row_fg_gold
        state_out.reason = 'Unresolved gear reference: ' .. tostring(spec.unresolved_ref)
        return state_out
    end

    if spec.expected_empty or expected == 'empty' then
        if equipped and equipped.empty then
            state_out.status = 'EQUIP'
            state_out.badge = 'EMPTY'
            state_out.color = cfg.row_fg_green
            state_out.reason = 'Slot is empty as expected.'
        else
            state_out.status = 'MISS'
            state_out.badge = 'MISS'
            state_out.color = cfg.row_fg_red
            state_out.reason = 'Expected empty but slot is not empty.'
        end
        return state_out
    end

    local has_equipped = equipped and not equipped.empty
    -- id_match: true when equipped item is the same item as the set requires.
    -- Primary check: item ID equality when the spec was resolved to a resource ID.
    -- Fallback: name comparison when spec.item_id could not be resolved (unresolved
    -- resource lookup), or when spec item_id mismatches but names are identical
    -- (protects against resource-lookup returning a wrong variant ID).
    local id_match = has_equipped and spec.item_id ~= nil and equipped.id == spec.item_id
    if not id_match and has_equipped and spec.display_name then
        if spec.item_id == nil or same_name(equipped.name, spec.display_name) then
            id_match = same_name(equipped.name, spec.display_name)
        end
    end
    state_out.id_match = id_match == true

    -- ── Equipped-priority block ──────────────────────────────────────────
    -- When has_equipped AND id_match, the item IS in the slot.
    -- This is always higher priority than any inventory-scan result.
    -- Never fall through to best_location_exact in this case: that scan
    -- includes equipped bags, so it would return FOUND instead of EQUIP.
    if has_equipped and id_match then
        local slot_badge = where_badge_from_label(bag_label(equipped.bag))

        if not spec.has_augments then
            -- No augments required — straight match.
            state_out.status = 'EQUIP'
            state_out.badge  = slot_badge
            state_out.color  = cfg.row_fg_green
            state_out.reason = 'Equipped item ID matches and no augments are required.'
            return state_out
        end

        if equipped.augments_available == false then
            -- extdata decode failed; cannot verify augments but item IS in slot.
            -- Report EQUIP rather than silently falling through to inventory scan.
            state_out.status = 'EQUIP'
            state_out.badge  = slot_badge
            state_out.color  = cfg.row_fg_green
            state_out.reason = 'Equipped item ID matches; augments could not be decoded (extdata unavailable).'
            return state_out
        end

        -- augments_available is true or nil — comparison is meaningful.
        local augment_match = same_augments(spec.augments, equipped.augments)
        state_out.augment_match = augment_match == true
        if augment_match then
            state_out.status = 'EQUIP'
            state_out.badge  = slot_badge
            state_out.color  = cfg.row_fg_green
            state_out.reason = 'Equipped item ID and augments match exactly.'
            return state_out
        end

        -- Item is equipped but augments differ from what the set specifies.
        -- Still EQUIP (it IS in the slot), but amber to signal spec mismatch.
        -- Must NOT fall through to best_location_exact here — the item being
        -- inside a bag makes it appear in inventory locations, which would
        -- incorrectly yield FOUND (gray) and hide the equipped fact.
        state_out.status = 'EQUIP'
        state_out.badge  = slot_badge
        state_out.color  = cfg.row_fg_gold
        state_out.reason = 'Equipped item ID matches but augments differ from the set specification.'
        state_out.augment_mismatch = true
        return state_out
    end
    -- ── End equipped-priority block ──────────────────────────────────────

    -- ── Paired-slot check ────────────────────────────────────────────────
    -- left_ear/right_ear and left_ring/right_ring are interchangeable:
    -- GearSwap may equip the correct pair in swapped positions.
    -- If the exact slot did not produce an id_match, check whether the
    -- expected item is equipped in the opposite paired slot.
    -- This is display-only; save/write always targets the original Lua slot.
    do
        local canonical_slot = gear_slots.canonical(item.slot)
        local pair_item, pair_slot = paired_slot_match(spec, canonical_slot)
        if pair_item then
            local pair_badge = where_badge_from_label(bag_label(pair_item.bag))
            state_out.status        = 'EQUIP'
            state_out.badge         = pair_badge
            state_out.color         = cfg.row_fg_green
            state_out.reason        = 'Equipped in paired slot (' .. pair_slot .. ').'
            state_out.paired_slot   = pair_slot
            state_out.equipped      = pair_item
            state_out.equipped_augments            = pair_item.augments or {}
            state_out.equipped_augments_available  = pair_item.augments_available
            state_out.equipped_item_id             = pair_item.id
            return state_out
        end
    end
    -- ── End paired-slot check ────────────────────────────────────────────

    local location, unavailable = best_location_exact(spec)
    if location then
        state_out.location = location
        local badge = where_badge_from_label(location.label or bag_label(location.bag))
        local bag_name = tostring(location.label or bag_label(location.bag))
        if unavailable then
            state_out.status = 'UNAVAIL'
            state_out.badge = badge
            state_out.color = cfg.row_fg_gold
            state_out.reason = 'Item found in ' .. bag_name .. ' but that storage is not currently accessible.'
        else
            state_out.status = 'FOUND'
            state_out.badge = badge
            state_out.color = cfg.row_fg_dim
            state_out.reason = 'Exact item found in ' .. bag_name .. '.'
        end
        return state_out
    end

    if spec.item_id == nil and spec.unresolved then
        state_out.status = spec.unresolved_ref and 'BADREF' or 'UNRES'
        state_out.badge = spec.unresolved_ref and 'BADREF' or 'UNRES'
        state_out.color = cfg.row_fg_gold
        state_out.reason = 'Could not resolve the Lua value to an item ID.'
        return state_out
    end

    state_out.status = 'MISS'
    state_out.badge = 'MISS'
    state_out.color = cfg.row_fg_red
    state_out.reason = 'No matching equipped item or exact storage copy was found.'
    return state_out
end

local function gear_line_status(item, set_path)
    local state_out = gear_row_status(item, set_path)
    return state_out.badge, state_out.color, state_out
end

local function gear_table_layout(width)
    local total = cols(width) - 1
    local slot_w = 6
    local where_w = 6
    local item_w = math.max(8, total - slot_w - where_w - 2)
    local where_col = math.min(slot_w + 1 + item_w + 1, total - where_w)
    return {
        total = total,
        slot = slot_w,
        item = item_w,
        where = where_w,
        where_col = where_col,
    }
end

local function gear_table_cell(text, width)
    return pad(truncate(text, width), width)
end

local function add_gear_header(out, width)
    local l = gear_table_layout(width)
    add_line(out,
        gear_table_cell('Slot', l.slot) .. ' ' ..
        gear_table_cell('Item Name', l.item) .. ' ' ..
        gear_table_cell('Where', l.where),
        cfg.row_fg_gold)
end

local function changed_slot_lookup(path)
    local slots = {}

    if path and state.recent_saved.path == path then
        for slot in pairs(state.recent_saved.slots or {}) do
            slots[gear_slots.canonical(slot) or slot] = true
        end
    end

    return slots
end

local function maybe_clear_recent_saved(node)
    local current_path = node and path_string(node) or ''
    if current_path == '' then return end
    if state.recent_saved.path and state.recent_saved.path ~= current_path then
        state.recent_saved = { path = nil, slots = {} }
    end
end

-- Returns exactly one augment/path-rank tag to append to an item name in the Gear tab,
-- or nil. Priority tiers (first match wins, no stacking):
--   1. [A/R5] — decoded aug_path from equipped snapshot or exact found location
--   2. [aug]  — confirmed augments decoded from extdata (augments_available=true, non-empty list)
--   3. [aug?] — Lua specifies augments but actual item data is unconfirmed or unavailable
--   4. nil    — no augment tag warranted
local function augment_tag_for_row(row_state)
    local eq   = row_state and row_state.equipped
    local loc  = row_state and row_state.location
    local spec = row_state and row_state.spec

    -- Tier 1: decoded path/rank from equipped snapshot
    if eq and not eq.empty and eq.aug_path then
        local t = '[' .. tostring(eq.aug_path)
        if eq.aug_rank then t = t .. '/R' .. tostring(eq.aug_rank) end
        return t .. ']'
    end

    -- Tier 1: decoded path/rank from exact found location entry
    if loc and loc.aug_path then
        local t = '[' .. tostring(loc.aug_path)
        if loc.aug_rank then t = t .. '/R' .. tostring(loc.aug_rank) end
        return t .. ']'
    end

    -- Tier 2: confirmed augments decoded (augments_available=true, list non-empty, no path/rank)
    local eq_confirmed  = eq  and not eq.empty
                              and eq.augments_available  == true
                              and eq.augments  and #eq.augments  > 0
    local loc_confirmed = loc and loc.augments_available == true
                              and loc.augments and #loc.augments > 0
    if eq_confirmed or loc_confirmed then
        return '[aug]'
    end

    -- Tier 3: Lua expects augments but actual data is unconfirmed or item not found
    if spec and spec.has_augments then
        return '[aug?]'
    end

    -- Tier 4: no tag
    return nil
end

local function add_gear_line(out, item, width, show_augments, color, set_path, changed_slots)
    local name = gear_display(item and item.value or '')
    local l = gear_table_layout(width)
    local badge, badge_color, row_state = gear_line_status(item, set_path)
    local canonical_slot = gear_slots.canonical(item and item.slot) or (item and item.slot)
    local just_changed = changed_slots and canonical_slot and changed_slots[canonical_slot]
    local row_color = row_state and row_state.color or badge_color or cfg.row_fg_set

    local aug_tag = augment_tag_for_row(row_state)
    if aug_tag then
        name = tostring(name or '') .. ' ' .. aug_tag
    end

    add_line(out,
        gear_table_cell(slot_label(item and item.slot), l.slot) .. ' ' ..
        gear_table_cell(name, l.item) .. ' ' ..
        gear_table_cell('', l.where),
        row_color)

    if just_changed then
        out[#out].bg = cfg.row_bg_changed
    end

    out[#out].status = row_state and row_state.status or badge
    out[#out].status_reason = row_state and row_state.reason or nil
    out[#out].expected_augments = row_state and row_state.expected_augments or {}
    out[#out].expected_augments_raw = row_state and row_state.expected_augments_raw or nil
    out[#out].equipped_augments = row_state and row_state.equipped_augments or {}
    out[#out].equipped_augments_available = row_state and row_state.equipped_augments_available or nil
    out[#out].expected_item_id = row_state and row_state.expected_item_id or nil
    out[#out].equipped_item_id = row_state and row_state.equipped_item_id or nil
    out[#out].id_match = row_state and row_state.id_match or false
    out[#out].augment_match = row_state and row_state.augment_match or false

    if badge and badge ~= '' then
        out[#out].aug_tag = truncate(row_state and row_state.badge or badge, l.where)
        out[#out].aug_tag_col = l.where_col
        out[#out].aug_tag_color = row_state and row_state.color or badge_color or cfg.row_fg_gold
    end
end

local PREVIEW_TABS = { 'gear', 'changes', 'summary', 'evidence' }
local SOURCE_LEFT_EDGE_HOLD_SECONDS = 0.35
local SOURCE_LEFT_EDGE_REPEAT_SECONDS = 0.25

local function preview_tab_index()
    for index, name in ipairs(PREVIEW_TABS) do
        if state.preview_card == name then return index end
    end
    return 1
end

local function active_preview_lines()
    if state.preview_cards.summary_only and state.preview_card == nil then
        return state.preview_cards.summary or {}
    end
    if state.preview_card == nil then
        return {}
    end
    return state.preview_cards[state.preview_card] or {}
end

local function cycle_preview_tab(delta)
    if not is_equippable_leaf(selected_node()) then
        state.preview_card = nil
        state.preview_scroll = 0
        state.preview_lines = active_preview_lines()
        if state.visible then ui.refresh() end
        return
    end

    local index = preview_tab_index() + delta
    if index < 1 then
        index = #PREVIEW_TABS
    elseif index > #PREVIEW_TABS then
        index = 1
    end

    state.preview_card = PREVIEW_TABS[index]
    state.focus = 'tree'
    state.preview_scroll = 0
    state.source_cursor = 0
    state.source_pan = 0
    clear_source_left_guard()
    state.preview_lines = active_preview_lines()
    if state.visible then ui.refresh() end
end

local function build_changes_card(node, width)
    local out = {}
    local path = path_string(node)

    add_line(out, node and node.key or 'No selection', cfg.title_fg)
    add_section(out, 'Live Changes')

    if not is_equippable_leaf(node) then
        wrap_into(out, 'Highlight a gear set to track live changes.', cfg.row_fg_dim, width)
        return out
    end

    if state.live_changes.path ~= path then
        wrap_into(out, 'No edit baseline captured for this set yet.', cfg.row_fg_dim, width)
        return out
    end

    if (state.live_changes.count or 0) == 0 then
        wrap_into(out, 'No changed gear slots.', cfg.row_fg_green, width)
        return out
    end

    for _, row in ipairs(state.live_changes.rows or {}) do
        wrap_into(out, string.format('%-8s %s -> %s', row.slot, row.before, row.after), cfg.row_fg_cursor, width)
    end

    return out
end

local function build_preview_cards(node)
    local summary = {}
    local gear_card = {}
    local changes_card = {}
    local evidence = {}
    local info = semantics.build_set_info(node) or {}
    local gear = node and tree.gear_preview(node) or {}
    local inheritance = info.inheritance or {}
    local set_path = path_string(node)
    local changed_slots = changed_slot_lookup(set_path)
    local width = sc(cfg.preview_width)
    local summary_only = info.summary_only or info.node_kind == 'category'
        or (node and not node.has_gear and (node.virtual or (node.children and #node.children > 0)))

    add_line(summary, safe(info.title, node and node.key or 'No selection'), cfg.title_fg)

    -- CATEGORY SUMMARY LAYOUT v3
    -- Category/container nodes get one clean explanation instead of the old
    -- duplicate top paragraph + "Summary" section + empty gear count.
    if summary_only then
        if info.category then
            wrap_into(summary, tostring(info.category), cfg.row_fg_gold, width)
        end

        add_line(summary, '', cfg.row_fg_set)

        local purpose_text = tostring(info.purpose or '')
        local explanation_text = tostring(info.plain_english or '')
        local overview_text = ''

        if purpose_text ~= '' and explanation_text ~= '' then
            if explanation_text:find(purpose_text, 1, true) then
                overview_text = explanation_text
            else
                overview_text = purpose_text .. ' ' .. explanation_text
            end
        elseif explanation_text ~= '' then
            overview_text = explanation_text
        elseif purpose_text ~= '' then
            overview_text = purpose_text
        else
            overview_text = 'Select a set or category to inspect it.'
        end

        wrap_into(summary, overview_text, cfg.row_fg_set, width)

        if info.typical_use and tostring(info.typical_use) ~= '' then
            add_line(summary, '', cfg.row_fg_set)
            wrap_into(summary, 'Common use: ' .. tostring(info.typical_use), cfg.row_fg_set, width)
        end

        if info.conditions and #info.conditions > 0 then
            add_section(summary, 'Conditions')
            for _, condition in ipairs(info.conditions) do
                wrap_into(summary, '- ' .. tostring(condition), cfg.row_fg_set, width)
            end
        end

        return {
            summary = summary,
            gear = summary,
            changes = summary,
            evidence = summary,
            summary_only = true,
        }
    end

    -- Normal gear-set Summary card. Keep this separate from category summaries
    -- so real sets still get the existing Gear / Changes / Summary / Data flow.
    local purpose_text = tostring(info.purpose or '')
    local explanation_text = tostring(info.plain_english or '')
    local overview_text = ''

    if purpose_text ~= '' and explanation_text ~= '' then
        if explanation_text:find(purpose_text, 1, true) then
            overview_text = explanation_text
        else
            overview_text = purpose_text .. ' ' .. explanation_text
        end
    elseif explanation_text ~= '' then
        overview_text = explanation_text
    elseif purpose_text ~= '' then
        overview_text = purpose_text
    else
        overview_text = 'Select a set or category to inspect it.'
    end

    wrap_into(summary, overview_text, cfg.row_fg_set, width)

    if info.category or info.trigger or info.confidence or info.typical_use then
        add_line(summary, '', cfg.row_fg_set)
        if info.category then wrap_into(summary, 'Category: ' .. tostring(info.category), cfg.row_fg_gold, width) end
        if info.trigger then wrap_into(summary, 'Trigger: ' .. tostring(info.trigger), cfg.row_fg_set, width) end
        if info.typical_use and tostring(info.typical_use) ~= '' then
            wrap_into(summary, 'Common use: ' .. tostring(info.typical_use), cfg.row_fg_set, width)
        end
        if info.confidence then wrap_into(summary, 'Confidence: ' .. tostring(info.confidence), cfg.row_fg_green, width) end
    end

    if info.conditions and #info.conditions > 0 then
        add_section(summary, 'Conditions')
        for _, condition in ipairs(info.conditions) do
            wrap_into(summary, '- ' .. tostring(condition), cfg.row_fg_set, width)
        end
    end

    add_line(gear_card, safe(info.title, node and node.key or 'No selection'), cfg.title_fg)
    add_section(gear_card, 'Defined Gear (' .. tostring(#gear) .. ')')
    if #gear == 0 then
        wrap_into(gear_card, 'No direct gear slots detected.', cfg.row_fg_dim, width)
    else
        add_gear_header(gear_card, width)
        for _, item in ipairs(gear) do
            add_gear_line(gear_card, item, width, false, nil, set_path, changed_slots)
        end
    end

    changes_card = build_changes_card(node, width)

    add_line(evidence, safe(info.title, node and node.key or 'No selection'), cfg.title_fg)
    add_lua_source(evidence, node, width)

    add_section(evidence, 'Evidence')
    if info.evidence and #info.evidence > 0 then
        for _, item in ipairs(info.evidence) do
            wrap_into(evidence, '- ' .. tostring(item), cfg.row_fg_dim, width)
        end
    else
        wrap_into(evidence, 'No semantic evidence recorded for this node.', cfg.row_fg_dim, width)
    end

    add_section(evidence, 'Source / Debug')
    wrap_into(evidence, 'Lua Path: ' .. path_string(node), cfg.row_fg_set, width)
    wrap_into(evidence, 'Source: ' .. source_line(node, info), cfg.row_fg_cursor, width)
    wrap_into(evidence, 'Type: ' .. (node and tree.describe(node) or 'none'), cfg.row_fg_dim, width)

    add_section(evidence, 'Inheritance')
    if list_count(inheritance.bases) == 0 and list_count(inheritance.references) == 0 and list_count(inheritance.override_slots) == 0 then
        wrap_into(evidence, 'Direct set definition', cfg.row_fg_dim, width)
    else
        for _, ref in ipairs(inheritance.bases or {}) do
            wrap_into(evidence, 'Base: ' .. tostring(ref), cfg.row_fg_set, width)
        end
        for _, ref in ipairs(inheritance.references or {}) do
            wrap_into(evidence, 'Reference: ' .. tostring(ref), cfg.row_fg_set, width)
        end
        if inheritance.override_slots and #inheritance.override_slots > 0 then
            wrap_into(evidence, 'Overrides: ' .. table.concat(inheritance.override_slots, ', '), cfg.row_fg_set, width)
        end
    end

    return {
        summary = summary,
        gear = gear_card,
        changes = changes_card,
        evidence = evidence,
    }
end

-- Apply global opacity to all background/art image objects.
-- Called at the end of update_positions so alpha stays in sync with cfg.ui_opacity.
-- Rect objects (borders, highlights, fills) are handled individually in set_rect.
-- Text foreground colors are intentionally excluded so text stays fully readable.
local function apply_image_opacity()
    local a = oa(255)
    if state.panel_full_img and state.panel_full_img.alpha then
        state.panel_full_img:alpha(a)
    end
    if state.panel_9slice then
        for _, img in ipairs(state.panel_9slice.images or {}) do
            if img.alpha then img:alpha(a) end
        end
    end
    if state.header_band_img and state.header_band_img.alpha then
        state.header_band_img:alpha(a)
    end
    if state.header_logo and state.header_logo.alpha then
        state.header_logo:alpha(a)
    end
    if state.tab_active_img and state.tab_active_img.alpha then
        state.tab_active_img:alpha(a)
    end
    for _, a_spec in ipairs(state.accent_specs or {}) do
        if a_spec.img and a_spec.img.alpha then
            a_spec.img:alpha(a)
        end
    end
end

local function update_positions()
    local d = dims()
    -- Sync font sizes to current scale (no-op at scale 1.0).
    local _sf = sc(cfg.font_size)
    for _, obj in ipairs(state.objects) do
        if obj.size then obj:size(_sf) end
    end
    local icon_x_offset = sc(6)
    local icon_y_offset = sc(3)
    local text_x_offset = cfg.show_icons and sc(24) or sc(6)

    local frame_pad = sc(2)
    local border_w = sc(2)
    local frame_x = d.x - frame_pad
    -- Extend the frame UPWARD to enclose the command/header banner.  The header
    -- text used to float above the frame at d.y; header_h is the band between the
    -- window top (d.y) and the tab row (d.body_y).  frame_y now starts above the
    -- header band instead of at the tab row.
    local header_h = d.body_y - d.y
    local frame_y = d.y - frame_pad
    local frame_w = d.total_w + (frame_pad * 2)
    local left_pane_w = d.preview_x - d.x

    -- Outer frame: three possible modes in priority order —
    --   full_panel: panel_full.png stretched to frame bounds (single image)
    --   9-slice:    nine tiled/stretched pieces (s9.enabled)
    --   primitive:  Lua rects (fallback when no image assets exist)
    -- image_frame is true for either of the first two so shared logic that
    -- suppresses primitive rects and applies chrome_inset applies to both.
    local s9 = state.panel_9slice
    local has_full_panel = state.panel_full_img ~= nil
    local image_frame = has_full_panel or (s9 and s9.enabled)
    -- art_mode: was true when window_bg.png provided full-window artwork for
    -- header/tab/footer decor.  window_bg.png is no longer loaded; the 9-slice
    -- provides only the outer frame/border, so all internal Lua backgrounds are
    -- always drawn.  art_mode is permanently false.
    local art_mode = false

    -- ── Content table geometry (computed early so frame_h can wrap around it) ──
    -- Tab row: matches tab_strip_bounds y/h at default LM values but is computed
    -- directly here so footer and frame_h do not depend on dims().footer_y.
    local row_top    = d.body_y + sc(LM.tab_y_offset)
    local row_h      = math.max(sc(6), sc(cfg.row_height + LM.tab_h_adjust + 2))
    local row_bottom = row_top + row_h
    -- Content rows start below the tab row.
    local content_y      = row_bottom + sc(LM.content_top_pad)
    local content_h      = cfg.visible_rows * sc(cfg.row_height)
    local content_bottom = content_y + content_h
    -- Bottom padding mirrors content_top_pad: last row gets the same breathing
    -- room above the footer separator as the first row has below the tab line.
    local content_bottom_pad = sc(LM.content_top_pad)
    -- Footer: follows content + bottom padding.
    -- The frame wraps around these; footer position is NOT derived from frame size.
    local footer_rule_y = content_bottom + content_bottom_pad
    local footer_bg_h   = sc(cfg.footer_height) + sc(LM.footer_h_adjust)
    local footer_bg_y   = footer_rule_y + 1
    local footer_bottom = footer_bg_y + footer_bg_h

    -- Frame height: wraps around content+footer.
    -- full_panel: small fixed pad (no corner tiles to clear).
    -- 9-slice:    pad scales with SLICE_CORNER so large corner art clears the footer.
    -- primitive:  standard border_w.
    local bottom_pad
    if has_full_panel then
        bottom_pad = sc(4)
    elseif image_frame then
        bottom_pad = sc(math.max(4, math.floor(SLICE_CORNER / 3)))
    else
        bottom_pad = frame_pad
    end
    local frame_h
    if image_frame then
        frame_h = (footer_bottom - frame_y) + bottom_pad
    else
        frame_h = (footer_bottom - frame_y) + frame_pad
    end

    -- Hide primitive rects whenever any image-based frame is active.
    -- The individual branches below re-show them only in primitive mode.
    if image_frame then
        state.frame_bg_rect:visible(false)
        state.border_top:visible(false)
        state.border_bottom:visible(false)
        state.border_left:visible(false)
        state.border_right:visible(false)
    end

    if has_full_panel then
        -- ── Full-panel mode: single image stretched to the entire frame. ──
        local pf = state.panel_full_img
        pf:pos(math.floor(frame_x), math.floor(frame_y))
        pf:size(math.max(1, frame_w), math.max(1, frame_h))
        -- Accent overlays belong to 9-slice themes; hide them here.
        for _, a in ipairs(state.accent_specs or {}) do a.img:visible(false) end
    elseif image_frame then
        -- ── 9-slice mode: nine tiled/stretched pieces form the frame. ──
        update_9slice(s9, frame_x, frame_y, frame_w, frame_h, sc(SLICE_CORNER))
        -- Position accent overlay images for this theme.
        if state.accent_specs and #state.accent_specs > 0 then
            for _, a in ipairs(state.accent_specs) do
                local aw = type(a.w) == 'number' and a.w or (a.w_mode == 'frame_w' and frame_w or 64)
                local ah = type(a.h) == 'number' and a.h or (a.h_mode == 'frame_h' and frame_h or 64)
                local ax, ay
                local anchor = a.anchor or 'top_left'
                if anchor == 'top_right' then
                    ax = frame_x + frame_w - aw + (a.ox or 0)
                    ay = frame_y              + (a.oy or 0)
                elseif anchor == 'bottom_left' then
                    ax = frame_x              + (a.ox or 0)
                    ay = frame_y + frame_h - ah + (a.oy or 0)
                elseif anchor == 'bottom_right' then
                    ax = frame_x + frame_w - aw + (a.ox or 0)
                    ay = frame_y + frame_h - ah + (a.oy or 0)
                else -- top_left
                    ax = frame_x + (a.ox or 0)
                    ay = frame_y + (a.oy or 0)
                end
                a.img:pos(math.floor(ax), math.floor(ay))
                a.img:size(math.max(1, aw), math.max(1, ah))
            end
        end
    else
        -- ── Primitive fallback (no image assets). ────────────────────────
        set_rect(state.frame_bg_rect, frame_x, frame_y, frame_w, frame_h, cfg.frame_bg)
        set_rect(state.border_top,    frame_x, frame_y, frame_w, border_w, cfg.border_light)
        set_rect(state.border_bottom, frame_x, frame_y + frame_h - border_w, frame_w, border_w, cfg.border_shadow)
        set_rect(state.border_left,   frame_x, frame_y, border_w, frame_h, cfg.border_light)
        set_rect(state.border_right,  frame_x + frame_w - border_w, frame_y, border_w, frame_h, cfg.border_shadow)
        for _, a in ipairs(state.accent_specs or {}) do a.img:visible(false) end
    end

    -- ── Header band art layer. ────────────────────────────────────────────
    -- Drawn over the panel background, under Lua fills and text.
    -- Covers the header region (frame top edge down to the tab row bottom).
    -- When present the Lua header_bg_rect is suppressed so art shows through.
    local header_band_h = row_bottom - frame_y
    if state.header_band_img then
        local hb = state.header_band_img
        hb:pos(math.floor(frame_x), math.floor(frame_y))
        hb:size(math.max(1, frame_w), math.max(1, header_band_h))
    end

    -- Shared inner fill bounds: inside the 2px border on every side.
    -- All internal Lua fills (header, title row) use these so they are guaranteed
    -- to cover the full inner width without gaps or mismatches.
    local inner_x     = frame_x + sc(2)
    local inner_y     = frame_y + sc(2)
    local inner_w     = frame_w - sc(4)
    local inner_right = inner_x + inner_w

    -- tree_title_bg_rect is replaced by the full-width title_row_bg_rect drawn below.
    state.tree_title_bg_rect:visible(false)
    -- Tree/preview divider spans from the tab row top to the footer bottom.
    set_rect(state.tree_divider_rect, d.preview_x - 1, d.body_y, 1, footer_rule_y - d.body_y, cfg.divider_col)

    -- Shared "chrome" horizontal bounds for the header banner AND footer strip so
    -- they always line up left-to-right and cannot drift apart.  Image-frame mode
    -- insets both by chrome_inset from the frame edges (clearing the side gold
    -- borders); primitive mode spans the full content width.  (This is the same
    -- formula the footer already used.)
    local chrome_inset = image_frame and sc(LM.chrome_inset) or 0
    local chrome_x = (image_frame and frame_x or d.x) + chrome_inset
    local chrome_w = (image_frame and frame_w or d.total_w) - (chrome_inset * 2)

    -- Header banner box, independent x/y/w/h via its own metrics (image mode).
    local header_x  = chrome_x + (image_frame and sc(LM.header_x_offset) or 0)
    local header_bw = chrome_w + (image_frame and sc(LM.header_w_adjust) or 0)
    local header_y  = d.y + (image_frame and sc(LM.header_y_offset) or 0)
    local header_bh = header_h + (image_frame and sc(LM.header_h_adjust) or 0)

    -- header_bg_rect is drawn below after tab_strip_bounds using inner_x/inner_w.
    state.header_sep:visible(false)  -- repositioned below after tab_strip_bounds
    -- Old text-backed header panel is unused; keep it hidden.
    state.header_bg:visible(false)
    -- GearTree branding: logo image (preferred) or text fallback, plus commands.
    -- sc(2) nudge lifts both paths ~2–3 px to visually center them within the
    -- decorative header band (header_y = d.y, but the visible band starts at
    -- frame_y = d.y − frame_pad, so without the nudge content sits slightly low).
    local header_text_y = header_y + math.max(0, header_bh - sc(cfg.row_height) - 1) - sc(2) + sc(LM.header_text_y_offset)
    local logo_right  -- right edge of title area; used to floor the commands x
    if state.header_logo then
        -- Logo image path: hide the text title, show and size the image.
        state.header:visible(false)
        local logo_x = inner_x + sc(8) + sc(LM.header_text_x_offset)
        local logo_h = math.min(header_bh - sc(6), sc(30))
        local logo_w = math.floor(logo_h * 4)   -- source logos are roughly 4:1 wide
        local logo_y = header_y + math.floor((header_bh - logo_h) / 2) - sc(2)
        state.header_logo:pos(logo_x, logo_y)
        state.header_logo:size(logo_w, logo_h)
        logo_right = logo_x + logo_w
    else
        -- Text fallback: draw GearTree title in the normal way.
        local title_font_size = sc(cfg.font_size + 2)
        -- header_text_y is the shared Y for the commands text (smaller font).
        -- The title uses a larger font, so its rendered bottom sits lower even
        -- at the same Y.  Shift the title up by half the font-size difference so
        -- both texts share the same visual vertical midpoint.
        local cmd_font_size_pre = math.max(6, sc(cfg.font_size - 2))
        local title_text_y = header_text_y + math.floor((cmd_font_size_pre - title_font_size) / 2)
        state.header:size(title_font_size)
        set_color(state.header, cfg.header_fg)
        state.header:pos(inner_x + sc(8) + sc(LM.header_text_x_offset), title_text_y)
        state.header:text('GearTree')
        logo_right = inner_x + sc(100)
    end
    local cmd_font_size = math.max(6, sc(cfg.font_size - 2))
    state.header_commands:size(cmd_font_size)
    local cmd_str = 'End Equip | Esc Hide | //gt help'
    local cmd_char_w = math.max(1, math.floor(sc(TEXT_CHAR_WIDTH) * cmd_font_size / cfg.font_size))
    local min_cmd_x  = logo_right + sc(24)
    local cmd_x = math.max(min_cmd_x, inner_right - #cmd_str * cmd_char_w - sc(8))
    set_color(state.header_commands, cfg.header_fg)
    state.header_commands:pos(cmd_x, header_text_y)
    state.header_commands:text(cmd_str)

    state.tree_bg:pos(d.x, d.body_y)
    fill_panel(state.tree_bg, d.total_w, cfg.visible_rows + 1)
    state.tree_bg:visible(false)
    state.list_bg:visible(false)
    state.preview_bg:visible(false)

    local tab_row_text_y = row_top + math.max(0, math.floor((row_h - sc(cfg.font_size + 2)) / 2) - 1)
    local tree_title_y = tab_row_text_y + sc(LM.tree_header_text_y_offset)
    state.tree_title:pos(d.tree_x + sc(6) + sc(LM.tree_header_text_x_offset), tree_title_y)
    state.tree_title:bg_visible(false)
    state.list_title:pos(d.list_x, d.body_y)
    state.list_title:bg_visible(false)
    set_color(state.tree_title, cfg.title_fg)

    local tabs = {
        { card = 'gear', label = 'Gear', obj = state.preview_title },
        { card = 'changes', label = 'Changes', obj = state.preview_changes_title },
        { card = 'summary', label = 'Summary', obj = state.preview_gear_title },
        { card = 'evidence', label = 'Data', obj = state.preview_data_title },
    }
    local tab_count = #tabs
    -- tab_strip_bounds provides the x/w for tab placement; y/h come from the
    -- early geometry (row_top/row_h/row_bottom) already computed above.
    local tabs_x = tab_strip_bounds(d)   -- take only x; right edge comes from inner_right
    local tabs_w = inner_right - tabs_x
    local function tab_edge(i)
        return tabs_x + math.floor(((i - 1) * tabs_w) / tab_count)
    end
    local function tab_bounds(i)
        local x1 = tab_edge(i)
        return x1, tab_edge(i + 1) - x1
    end
    local text_char_w = sc(TEXT_CHAR_WIDTH)
    -- row_top / row_h / row_bottom already defined above for frame_h computation.

    -- Header fill: only drawn in primitive mode.  In image-frame mode (9-slice or
    -- full-panel) the 9-slice corner/edge art owns the header zone, and this rect
    -- would cover the gold gradient making the top border look thinner than the
    -- body border.  Suppressing it here is consistent with how every other interior
    -- background rect (title_row_bg_rect, content_bg_rect, footer_bg_rect) is
    -- handled in image-frame mode.  When a header_band_img is provided it also
    -- owns the header interior, so suppress for that case too.
    if image_frame or state.header_band_img then
        state.header_bg_rect:visible(false)
    else
        set_rect(state.header_bg_rect, inner_x, inner_y, inner_w, row_top - inner_y, cfg.header_bg)
    end
    -- Title/tab row background: in image-frame mode the 9-slice base fill owns the
    -- panel color, so the Lua navy band is suppressed.  Primitive mode keeps it so
    -- the no-image UI still has a visible tab row background.
    if image_frame then
        state.title_row_bg_rect:visible(false)
    else
        set_rect(state.title_row_bg_rect, inner_x, row_top, inner_w, row_h, cfg.title_bg)
    end

    if state.preview_tab_bg then state.preview_tab_bg:visible(false) end

    for index, tab in ipairs(tabs) do
        local x, width = tab_bounds(index)
        local active = state.preview_card == tab.card
        local is_tab_hover = not active
                          and state.hover
                          and state.hover.kind == 'tab'
                          and state.hover.card == tab.card
        local fg = active and cfg.active_title_fg or (is_tab_hover and cfg.tab_hover_fg or cfg.title_fg)

        -- Highlights are inset 1px from the row lines so they sit inside the border.
        -- Separators span the full row height so they connect top and bottom lines.
        local hl_y = row_top + sc(1)
        local hl_h = row_h - sc(2)

        if art_mode then
            -- Image-theme: active/hover get an overlay inset inside the row lines.
            local hl = state.tab_hl_ok and state.tab_hl[index] or nil
            local ocol = active and cfg.tab_active_overlay or (is_tab_hover and cfg.tab_hover_overlay or nil)
            if ocol then
                if hl then
                    set_tab_hl(hl, x, hl_y, width, hl_h, ocol)
                    state.preview_tab_rects[index]:visible(false)
                else
                    set_rect(state.preview_tab_rects[index], x, hl_y, width, hl_h, ocol)
                end
            else
                if hl then hl:visible(false) end
                state.preview_tab_rects[index]:visible(false)
            end
            if index < tab_count then
                set_rect(state.preview_tab_separators[index], x + width, row_top, 1, row_h, cfg.divider_col)
            else
                state.preview_tab_separators[index]:visible(false)
            end
        else
            -- Primitive / 9-slice / full-panel: solid tab backgrounds or suppressed fills.
            -- Active tab: defer to tab_active_img if present (handled after the loop).
            local use_tab_art = active and state.tab_active_img ~= nil
            if state.tab_hl[index] then state.tab_hl[index]:visible(false) end
            if use_tab_art then
                -- tab_active_img will cover this cell; hide the fill rect.
                state.preview_tab_rects[index]:visible(false)
            elseif image_frame and not active and not is_tab_hover then
                -- Image frame owns the base fill; inactive non-hover tabs must not draw a Lua bg.
                state.preview_tab_rects[index]:visible(false)
            else
                local bg = active and cfg.active_title_bg or (is_tab_hover and cfg.tab_hover_bg or cfg.title_bg)
                set_rect(state.preview_tab_rects[index], x, hl_y, width, hl_h, bg)
            end
            if index < tab_count then
                set_rect(state.preview_tab_separators[index], x + width, row_top, 1, row_h, cfg.divider_col)
            else
                state.preview_tab_separators[index]:visible(false)
            end
        end

        -- Vertically centre the label within the tab row (shared baseline with tree_title).
        local tab_label_y = tab_row_text_y + sc(LM.preview_tab_text_y_offset)
        tab.obj:pos(x + math.max(sc(4), math.floor((width - (#tab.label * text_char_w)) / 2)) + sc(LM.preview_tab_text_x_offset),
                    tab_label_y)
        tab.obj:bg_visible(false)
        set_color(tab.obj, fg)
        tab.obj:text(tab.label)

    end

    -- Active-tab art image: optional single image stretched to the active tab cell.
    -- Takes priority over tab_hl and the fill rect for the active tab.
    -- Re-positioned each frame; hidden when no tab matches.
    local tab_active_used = false
    if state.tab_active_img then
        for ai, atab in ipairs(tabs) do
            if state.preview_card == atab.card then
                local ax, aw = tab_bounds(ai)
                local ahl_y = row_top + sc(1)
                local ahl_h = row_h   - sc(2)
                state.tab_active_img:pos(math.floor(ax), math.floor(ahl_y))
                state.tab_active_img:size(math.max(1, aw), math.max(1, ahl_h))
                tab_active_used = true
                break
            end
        end
        if not tab_active_used then state.tab_active_img:visible(false) end
    end

    -- Active-tab bottom accent: 2px warm-gold stripe inside the bottom edge of the
    -- active tab rect.  Suppressed when tab_active_img provides art.
    if state.active_tab_accent then
        if tab_active_used then
            state.active_tab_accent:visible(false)
        else
            local accent_placed = false
            for ai, atab in ipairs(tabs) do
                if state.preview_card == atab.card then
                    local ax, aw = tab_bounds(ai)
                    set_rect(state.active_tab_accent,
                        ax,
                        row_top + row_h - 2,
                        aw, 2, cfg.border_light)
                    accent_placed = true
                    break
                end
            end
            if not accent_placed then
                state.active_tab_accent:visible(false)
            end
        end
    end

    -- Tab row top and bottom lines: Lua owns these in all modes.
    -- header_sep = top line (also separates header banner from tab row).
    -- header_rule = bottom line (separates tab row from content).
    set_rect(state.header_sep,  d.x, row_top,    d.total_w, sc(1), cfg.border_light)
    set_rect(state.header_rule, d.x, row_bottom, d.total_w, sc(1), cfg.border_light)

    local row_y = row_bottom + sc(LM.content_top_pad)
    for i, obj in ipairs(state.tree_rows) do
        local y = row_y + (i - 1) * sc(cfg.row_height)
        obj:pos(d.tree_x + text_x_offset, y)
        if state.tree_icons[i] then
            if cfg.show_icons then
                state.tree_icons[i]:pos(d.tree_x + icon_x_offset, y + icon_y_offset)
                state.tree_icons[i]:size(sc(cfg.icon_size), sc(cfg.icon_size))
            else
                state.tree_icons[i]:visible(false)
            end
        end
    end
    for i, obj in ipairs(state.list_rows) do
        local y = row_y + (i - 1) * sc(cfg.row_height)
        obj:pos(d.list_x + text_x_offset, y)
        if state.list_icons[i] then
            if cfg.show_icons then
                state.list_icons[i]:pos(d.list_x + icon_x_offset, y + icon_y_offset)
                state.list_icons[i]:size(sc(cfg.icon_size), sc(cfg.icon_size))
            else
                state.list_icons[i]:visible(false)
            end
        end
    end
    for i, obj in ipairs(state.preview_rows) do
        obj:pos(d.preview_x + sc(8), row_y + (i - 1) * sc(cfg.row_height))
    end

    -- Content background: 9-slice panel_fill.png now owns the base fill for the
    -- entire frame interior, so content_bg_rect is only drawn in primitive mode
    -- (no 9-slice assets) where it is still needed to cover the game world.
    if image_frame then
        state.content_bg_rect:visible(false)
    else
        set_rect(state.content_bg_rect,
            d.x + sc(LM.content_x_offset), d.body_y,
            d.total_w + sc(LM.content_w_adjust), math.max(sc(1), footer_rule_y - d.body_y),
            cfg.panel_bg)
    end

    -- Footer / status box: x/w use chrome bounds; y/h derived from content geometry.
    local footer_bg_x = chrome_x + (image_frame and sc(LM.footer_x_offset) or 0)
    local footer_bg_w = chrome_w + (image_frame and sc(LM.footer_w_adjust) or 0)
    -- Footer separator line: always Lua-drawn in both modes.
    set_rect(state.footer_rule, inner_x, footer_rule_y, inner_w, 1, cfg.divider_col)
    -- Footer background band: suppressed in image-frame mode so the 9-slice base
    -- fill owns the footer area color.  Primitive mode keeps it for readability.
    if image_frame then
        state.footer_bg_rect:visible(false)
    else
        set_rect(state.footer_bg_rect, footer_bg_x, footer_bg_y, footer_bg_w, footer_bg_h, cfg.title_bg)
    end
    -- footer_bg (panel_obj) text-background is always suppressed.
    state.footer_bg:bg_visible(false)
    state.footer:pos(d.tree_x + sc(6) + sc(LM.footer_text_x_offset), footer_bg_y + sc(LM.footer_text_y_offset))
    state.footer:text(truncate(state.status_text or '', cols(footer_bg_w) - 2))

    -- ── Layout calibration guides ─────────────────────────────────────────
    -- Visualised + draggable bounds.  Only shown while layout_mode is on; each
    -- guide records a hit rect + an edit spec consumed by the mouse handlers.
    state.layout_bounds = {}
    if state.layout_mode then
        -- content_y and content_h already computed above from row geometry.
        local content_top  = content_y
        local content_h_lm = content_h
        local first_tab_lbl_x = tabs_x + math.max(sc(4), math.floor((tab_w - (4 * sc(TEXT_CHAR_WIDTH))) / 2)) + sc(LM.preview_tab_text_x_offset)
        local AM = 9   -- anchor marker size
        -- Box guides: edit { move_x, move_y, resize_w, resize_h } (metric names).
        -- Anchor guides: edit { move_x, move_y } only (text offsets), small marker.
        -- { name, x, y, w, h, fill{a,r,g,b}, edit, is_anchor }
        local defs = {
            -- boxes
            { 'header',  header_x, header_y, header_bw, header_bh, { 55, 255, 232, 40 },
                { move_x = 'header_x_offset', move_y = 'header_y_offset', resize_w = 'header_w_adjust', resize_h = 'header_h_adjust' } },
            { 'tabrow',  tabs_x, row_top, tabs_w, row_h, { 55, 90, 230, 120 },
                { move_x = 'tab_x_offset', move_y = 'tab_y_offset', resize_w = 'tab_w_adjust', resize_h = 'tab_h_adjust' } },
            { 'content', d.x + sc(LM.content_x_offset), content_top, d.total_w + sc(LM.content_w_adjust), math.max(sc(8), content_h_lm), { 40, 220, 90, 220 },
                { move_x = 'content_x_offset', move_y = 'content_top_pad', resize_w = 'content_w_adjust' } },
            { 'footer',  footer_bg_x, footer_bg_y, footer_bg_w, footer_bg_h, { 55, 110, 200, 255 },
                { move_x = 'footer_x_offset', move_y = 'footer_y_offset', resize_w = 'footer_w_adjust', resize_h = 'footer_h_adjust' } },
            -- text anchors (small markers; drag moves only the text offsets)
            { 'hdrTxt',  header_text_x - 1, header_text_y + 1, AM, AM, { 230, 255, 244, 150 },
                { move_x = 'header_text_x_offset', move_y = 'header_text_y_offset' }, true },
            { 'treeTxt', d.tree_x + sc(6) + sc(LM.tree_header_text_x_offset) - 1, d.body_y + sc(LM.tree_header_text_y_offset) + 1, AM, AM, { 230, 150, 220, 255 },
                { move_x = 'tree_header_text_x_offset', move_y = 'tree_header_text_y_offset' }, true },
            { 'tabTxt',  first_tab_lbl_x - 1, row_top + sc(LM.preview_tab_text_y_offset) + 1, AM, AM, { 230, 130, 255, 150 },
                { move_x = 'preview_tab_text_x_offset', move_y = 'preview_tab_text_y_offset' }, true },
            { 'ftrTxt',  footer_bg_x + sc(4) + sc(LM.footer_text_x_offset) - 1, footer_bg_y + sc(LM.footer_text_y_offset) + 1, AM, AM, { 230, 255, 230, 150 },
                { move_x = 'footer_text_x_offset', move_y = 'footer_text_y_offset' }, true },
        }
        for i, gdef in ipairs(defs) do
            local name, gx, gy, gw, gh, fill, edit, is_anchor =
                gdef[1], gdef[2], gdef[3], gdef[4], gdef[5], gdef[6], gdef[7], gdef[8]
            set_rect(state.layout_fills[i], gx, gy, gw, gh, fill)
            local lbl = state.layout_labels[i]
            if lbl then
                lbl:pos(gx + (is_anchor and (gw + 2) or 3), gy + 1)
                lbl:text(name)
                set_color(lbl, cfg.row_fg_cursor)
                lbl:bg_visible(false)
                lbl:visible(state.visible)
            end
            state.layout_bounds[i] = { name = name, edit = edit, x = gx, y = gy, w = gw, h = gh, is_anchor = is_anchor }
        end
        -- Hide any unused pool slots.
        for i = #defs + 1, #state.layout_fills do
            if state.layout_fills[i] then state.layout_fills[i]:visible(false) end
            if state.layout_labels[i] then state.layout_labels[i]:visible(false) end
        end
    else
        for i = 1, #state.layout_fills do
            if state.layout_fills[i] then state.layout_fills[i]:visible(false) end
            if state.layout_labels[i] then state.layout_labels[i]:visible(false) end
        end
    end

    -- Apply global opacity to background art images (9-slice, panel_full, header band, etc.).
    apply_image_opacity()
end

function ui.create(root, save_pos_callback)
    state.root = root
    state.save_pos_callback = save_pos_callback
    state.flat = tree.flatten(root)
    state.cursor = #state.flat > 0 and 1 or 0

    -- ── Background layer: panel_full.png (preferred) or 9-slice. ────────────
    -- Created FIRST so they are behind every subsequent Windower image object.
    -- panel_full.png:  single image stretched to the computed frame rectangle.
    --                  Replaces the 9-slice entirely when present; 9-slice is
    --                  never created, saving image-object slots.
    -- 9-slice:         nine tiled/stretched pieces forming the frame border.
    --                  Used when panel_full.png is absent and assets exist.
    -- Primitive rects: fallback when no image assets are available.
    local full_panel_path = THEME_ASSET_DIR .. 'panel_full.png'
    if slice_file_exists(full_panel_path) then
        local pf = new_slice_image(full_panel_path)
        add_decor_image(pf)
        state.panel_full_img = pf
        state.panel_9slice   = { images = {}, enabled = false }
    else
        state.panel_full_img = nil
        state.panel_9slice   = init_9slice()
    end

    -- Header band: optional art layer drawn above the panel background and
    -- below Lua fills.  When present the Lua header_bg_rect is suppressed so
    -- the art is not covered by a solid colour fill.
    local header_band_path = THEME_ASSET_DIR .. 'header_band.png'
    if slice_file_exists(header_band_path) then
        local hb = new_slice_image(header_band_path)
        add_decor_image(hb)
        state.header_band_img = hb
    else
        state.header_band_img = nil
    end

    -- Accent images: decorative non-stretch overlays placed at frame corners/edges.
    -- Created after the panel background so they layer above it but below content.
    -- Each entry: { img = image_obj, anchor, ox, oy, w, h, w_mode, h_mode }
    state.accent_specs = {}
    if pending_accents then
        for slot, spec in pairs(pending_accents) do
            if type(spec) == 'table' and type(spec.file) == 'string' then
                local path = THEME_ASSET_DIR .. spec.file
                if slice_file_exists(path) then
                    local img = images.new({
                        draggable = false,
                        visible   = false,
                        color     = { alpha = 255, red = 255, green = 255, blue = 255 },
                        size      = { width = 1, height = 1 },
                        texture   = { fit = true, path = path },
                    })
                    if img.path then img:path(path) end
                    if img.fit  then img:fit(false) end
                    add_decor_image(img)
                    -- Normalize accent spec: accept x/y as aliases for ox/oy,
                    -- and accept string w/h values ("frame_w","frame_h") as
                    -- w_mode/h_mode so ui_theme.lua does not need two keys.
                    local sw = spec.w
                    local sh = spec.h
                    local wmode = (type(sw) == 'string') and sw or spec.w_mode
                    local hmode = (type(sh) == 'string') and sh or spec.h_mode
                    state.accent_specs[#state.accent_specs + 1] = {
                        img    = img,
                        anchor = spec.anchor or 'top_left',
                        ox     = spec.ox or spec.x or 0,   -- x is alias for ox
                        oy     = spec.oy or spec.y or 0,   -- y is alias for oy
                        w      = type(sw) == 'number' and sw or 64,
                        h      = type(sh) == 'number' and sh or 64,
                        w_mode = wmode,   -- 'frame_w' stretches to full frame width
                        h_mode = hmode,   -- 'frame_h' stretches to full frame height
                    }
                end
            end
        end
    end

    local d = dims()
    state.frame_bg_rect = rect_obj(cfg.frame_bg)
    state.content_bg_rect = rect_obj(cfg.panel_bg)
    state.border_top = rect_obj(cfg.border_light)
    state.border_bottom = rect_obj(cfg.border_shadow)
    state.border_left = rect_obj(cfg.border_light)
    state.border_right = rect_obj(cfg.border_shadow)
    state.header_rule = rect_obj(cfg.divider_col)
    state.tree_title_bg_rect = rect_obj(cfg.title_bg)   -- kept but hidden; replaced by title_row_bg_rect
    state.title_row_bg_rect  = rect_obj(cfg.title_bg)   -- full-width tab/title row background
    state.tree_divider_rect = rect_obj(cfg.divider_col)
    state.tree_scroll_track = rect_obj(cfg.scrollbar_track)
    state.tree_scroll_thumb = rect_obj(cfg.scrollbar_thumb)
    state.footer_rule        = rect_obj(cfg.divider_col)
    state.active_tab_accent  = rect_obj(cfg.border_light)
    state.footer_bg_rect     = rect_obj(cfg.title_bg)
    state.header_bg_rect     = rect_obj(cfg.header_bg)
    state.header_sep         = rect_obj(cfg.border_light)
    state.preview_tab_rects = {}
    state.preview_tab_separators = {}
    for i = 1, 4 do
        state.preview_tab_rects[i] = rect_obj(cfg.title_bg)
        state.preview_tab_separators[i] = rect_obj(cfg.divider_col)
    end

    -- Rounded-top tab highlight images (one per tab) for the active/hover overlay
    -- in image-theme mode.  Created only if tab_hl.png exists; otherwise the
    -- active/hover highlight falls back to the solid rectangle.
    state.tab_hl = {}
    state.tab_hl_ok = slice_file_exists(TAB_HL_TEXTURE)
    if state.tab_hl_ok then
        for i = 1, 4 do
            local o = images.new({
                draggable = false, visible = false,
                color   = { alpha = 255, red = 255, green = 255, blue = 255 },
                size    = { width = 1, height = 1 },
                texture = { fit = false, path = TAB_HL_TEXTURE },
            })
            if o.path then o:path(TAB_HL_TEXTURE) end
            if o.fit  then o:fit(false) end
            state.tab_hl[i] = add_decor_image(o)
        end
    end

    -- Active-tab art image: optional single image repositioned to the active tab
    -- cell on each update.  Created after tab_hl so it layers above tab rects
    -- and tab_hl but below tab-label text objects.
    local tab_active_path = THEME_ASSET_DIR .. 'tab_active.png'
    if slice_file_exists(tab_active_path) then
        local ta = new_slice_image(tab_active_path)
        add_decor_image(ta)
        state.tab_active_img = ta
    else
        state.tab_active_img = nil
    end

    state.header_bg = panel_obj(d.total_w, 1)
    state.header = text_obj()
    state.header:color(cfg.title_fg[1], cfg.title_fg[2], cfg.title_fg[3])
    state.header_commands = text_obj()
    state.header_commands:color(cfg.title_fg[1], cfg.title_fg[2], cfg.title_fg[3])
    state.tree_bg = panel_obj(d.tree_w, cfg.visible_rows + 1)
    state.list_bg = panel_obj(d.list_w, cfg.visible_rows + 1)
    state.preview_bg = panel_obj(d.preview_w, cfg.visible_rows + 1)
    state.tree_title = title_obj()
    state.list_title = title_obj()
    state.preview_tab_bg = title_obj()
    state.preview_title = title_obj()
    state.preview_gear_title = title_obj()
    state.preview_changes_title = title_obj()
    state.preview_data_title = title_obj()
    state.footer_bg = panel_obj(d.total_w, 1)
    state.footer = text_obj()
    state.footer:color(cfg.title_fg[1], cfg.title_fg[2], cfg.title_fg[3])

    -- Layout calibration guide objects (one fill rect + one label per guide).
    -- Hidden in normal mode; positioned/shown only while layout_mode is on.
    state.layout_fills = {}
    state.layout_labels = {}
    for i = 1, 12 do
        state.layout_fills[i] = rect_obj({ 60, 255, 255, 255 })
        state.layout_labels[i] = text_obj()
    end

    for i = 1, cfg.visible_rows do
        state.tree_rows[i] = text_obj()
        state.tree_icons[i] = image_obj()
        state.list_rows[i] = text_obj()
        state.list_icons[i] = image_obj()
        state.preview_rows[i] = text_obj()
        state.preview_aug_tags[i] = text_obj()
        set_color(state.preview_aug_tags[i], cfg.row_fg_blue)
    end

    -- Cursor overlay rects, created LAST so they sort topmost among image objects.
    -- (rect_obj adds them to state.decor_images, so set_visible/destroy cover them.)
    state.cursor_shadow_h = rect_obj(cfg.cursor_shadow)
    state.cursor_shadow_v = rect_obj(cfg.cursor_shadow)
    state.cursor_line_h   = rect_obj(cfg.cursor_fg)
    state.cursor_line_v   = rect_obj(cfg.cursor_fg)
    state.cursor_objs = {
        state.cursor_shadow_h, state.cursor_shadow_v,
        state.cursor_line_h,   state.cursor_line_v,
    }

    -- Optional themed pointer image (themes/mockup/cursor.png).  When present it
    -- replaces the primitive crosshair; otherwise the crosshair is the fallback.
    -- Header logo image (not in decor_images) — destroyed explicitly in ui.destroy.
    do
        if slice_file_exists(LOGO_TEXTURE) then
            local obj = images.new({
                draggable = false,
                visible   = false,
                color     = { alpha = 255, red = 255, green = 255, blue = 255 },
                size      = { width = 1, height = 1 },
                texture   = { fit = true, path = LOGO_TEXTURE },
            })
            if obj.path then obj:path(LOGO_TEXTURE) end
            if obj.fit  then obj:fit(false) end
            state.header_logo = obj
        else
            state.header_logo = nil
        end
    end

    -- Standalone image (not in decor_images) — destroyed explicitly in ui.destroy.
    do
        local cur = THEME_ASSET_DIR .. 'cursor.png'
        if slice_file_exists(cur) then
            local obj = images.new({
                draggable = false,
                visible   = false,
                color     = { alpha = 255, red = 255, green = 255, blue = 255 },
                size      = { width = CURSOR_IMG_SIZE, height = CURSOR_IMG_SIZE },
                texture   = { fit = true, path = cur },
            })
            if obj.path then obj:path(cur) end
            if obj.fit  then obj:fit(false) end
            state.cursor_img = obj
        else
            state.cursor_img = nil
        end
    end

    update_positions()
end

function ui.destroy()
    -- Header logo (not in decor_images, destroy explicitly).
    if state.header_logo then
        state.header_logo:destroy()
        state.header_logo = nil
    end
    -- Themed cursor image (not in decor_images, destroy explicitly).
    if state.cursor_img then
        state.cursor_img:destroy()
        state.cursor_img = nil
    end

    -- 9-slice images are not in state.decor_images, so destroy them separately.
    destroy_9slice(state.panel_9slice)
    state.panel_9slice = nil

    for _, obj in ipairs(state.objects) do
        obj:destroy()
    end
    for _, obj in ipairs(state.decor_images) do
        obj:destroy()
    end
    for _, obj in ipairs(state.image_objects) do
        obj:destroy()
    end
    state.objects = {}
    state.decor_images = {}
    state.image_objects = {}
    state.tree_rows = {}
    state.tree_icons = {}
    state.list_rows = {}
    state.list_icons = {}
    state.preview_rows = {}
    state.preview_aug_tags = {}
end

local function set_visible(visible)
    -- 9-slice images sit behind everything; show/hide them first.
    if state.panel_9slice then
        set_9slice_visible(state.panel_9slice, visible and state.panel_9slice.enabled)
    end
    for _, obj in ipairs(state.decor_images) do
        obj:visible(visible)
    end
    for _, obj in ipairs(state.objects) do
        obj:visible(visible)
    end
    for _, obj in ipairs(state.image_objects) do
        obj:visible(visible and cfg.show_icons)
    end

    if state.preview_bg then state.preview_bg:visible(false) end

    if not cfg.show_list_pane then
        if state.list_bg then state.list_bg:visible(false) end
        if state.list_title then state.list_title:visible(false) end
        for _, obj in ipairs(state.list_rows) do obj:visible(false) end
        for _, obj in ipairs(state.list_icons) do obj:visible(false) end
    end

    -- Cursor overlay (crosshair rects + optional image) must stay hidden until the
    -- next mouse move repositions it — otherwise it'd flash at a stale position on
    -- show.  update_cursor_overlay() re-shows the active variant.
    if state.cursor_objs then
        for _, o in ipairs(state.cursor_objs) do o:visible(false) end
    end
    if state.header_logo then state.header_logo:visible(visible) end
    if state.cursor_img  then state.cursor_img:visible(false)   end

    -- Layout guides: hidden unless layout_mode (update_positions re-shows them).
    if not (visible and state.layout_mode) then
        for _, o in ipairs(state.layout_fills) do o:visible(false) end
        for _, o in ipairs(state.layout_labels) do o:visible(false) end
    end
end

local function update_tree_scrollbar(d)
    if not state.tree_scroll_track or not state.tree_scroll_thumb then return end

    local total = #state.flat
    if total <= cfg.visible_rows then
        state.tree_scroll_track:visible(false)
        state.tree_scroll_thumb:visible(false)
        return
    end

    local track_w = sc(5)
    local track_x = d.preview_x - track_w - sc(4)
    local track_y = d.body_y + sc(cfg.row_height) + sc(2) + sc(LM.content_top_pad)
    local track_h = (cfg.visible_rows * sc(cfg.row_height)) - sc(4)
    local thumb_h = math.max(sc(28), math.floor(track_h * (cfg.visible_rows / total)))
    local max_scroll = math.max(1, total - cfg.visible_rows)
    local thumb_y = track_y + math.floor((track_h - thumb_h) * (state.scroll / max_scroll))

    set_rect(state.tree_scroll_track, track_x, track_y, track_w, track_h, cfg.scrollbar_track)
    set_rect(state.tree_scroll_thumb, track_x, thumb_y, track_w, thumb_h, cfg.scrollbar_thumb)
end

local function render_tree()
    local d = dims()
    state.flat = tree.flatten(state.root)
    if #state.flat > 0 then
        state.cursor = clamp(state.cursor == 0 and 1 or state.cursor, 1, #state.flat)
    else
        state.cursor = 0
    end
    ensure_cursor_visible()
    update_tree_scrollbar(d)

    local label = string.format(' Gear Sets [%d/%d] ', state.cursor, #state.flat)
    state.tree_title:text(truncate(label, cols(d.tree_w) - 1))

    for i = 1, cfg.visible_rows do
        local flat_idx = state.scroll + i
        local entry = state.flat[flat_idx]
        local obj = state.tree_rows[i]
        local icon = state.tree_icons[i]
        obj:bg_visible(false)

        if entry then
            local node = entry.node
            local indent = string.rep('  ', entry.depth)
            local is_last_saved = state.last_saved_path ~= '' and not node.virtual and path_string(node) == state.last_saved_path
            local marker = flat_idx == state.cursor and '>' or (is_last_saved and '*' or ' ')
            -- Display-only: collapse spaces around slash separators ("A / B" -> "A/B").
            -- node.key itself is untouched (paths/keys/classification unaffected).
            local display_key = tostring(node.key or ''):gsub('%s*/%s*', '/')
            local text = string.format('%s %s%s %s', marker, indent, node_kind(node), display_key)
            if icon then
                if cfg.show_icons then
                    icon:path(node_icon(node))
                    icon:visible(state.visible)
                else
                    icon:visible(false)
                end
            end
            local is_hover = state.hover and state.hover.kind == 'tree_row'
                          and state.hover.flat_idx == flat_idx
            if flat_idx == state.cursor then
                obj:bg_visible(true)
                obj:bg_color(cfg.row_bg_cursor[2], cfg.row_bg_cursor[3], cfg.row_bg_cursor[4])
                obj:bg_alpha(oa(cfg.row_bg_cursor[1]))
                set_color(obj, cfg.row_fg_cursor)
            elseif is_hover then
                obj:bg_visible(true)
                obj:bg_color(cfg.row_bg_hover[2], cfg.row_bg_hover[3], cfg.row_bg_hover[4])
                obj:bg_alpha(oa(cfg.row_bg_hover[1]))
                if is_last_saved then
                    set_color(obj, cfg.row_fg_gold)
                elseif node.children and #node.children > 0 then
                    set_color(obj, cfg.row_fg_cat)
                else
                    set_color(obj, cfg.row_fg_set)
                end
            elseif is_last_saved then
                set_color(obj, cfg.row_fg_gold)
            elseif node.children and #node.children > 0 then
                set_color(obj, cfg.row_fg_cat)
            else
                set_color(obj, cfg.row_fg_set)
            end
            -- Pad to full column width so the text-object background spans
            -- the entire tree panel row, not just the text label.
            obj:text(pad(text, cols(d.tree_w)))
        else
            obj:text('')
            if icon then icon:visible(false) end
        end
    end
end

local function render_list()
    if not cfg.show_list_pane then
        if state.list_bg then state.list_bg:visible(false) end
        if state.list_title then state.list_title:visible(false) end
        for _, obj in ipairs(state.list_rows) do
            obj:text('')
            obj:visible(false)
        end
        for _, icon in ipairs(state.list_icons) do
            icon:visible(false)
        end
        return
    end

    local d = dims()
    local list_node = active_list_node()
    local items = active_list_items()
    local title = list_node and list_node.key or 'Sets'
    state.list_title:text(pad(' ' .. title .. '  (' .. tostring(#items) .. ') ', cols(d.list_w)))

    for i = 1, cfg.visible_rows do
        local node = items[i]
        local obj = state.list_rows[i]
        local icon = state.list_icons[i]
        obj:bg_visible(false)

        if node then
            local idx = flat_index_for_node(node)
            local marker = node_kind(node)
            local is_last_saved = state.last_saved_path ~= '' and not node.virtual and path_string(node) == state.last_saved_path
            local saved_marker = is_last_saved and '*' or ' '
            local line = string.format('%s %s %-24s %s', saved_marker, marker, node.key, node.has_gear and tree.describe(node) or '')
            if icon then
                if cfg.show_icons then
                    icon:path(node_icon(node))
                    icon:visible(state.visible)
                else
                    icon:visible(false)
                end
            end
            local is_hover = state.hover and state.hover.kind == 'list_row'
                          and state.hover.node == node
            if idx and idx == state.cursor then
                obj:bg_visible(true)
                obj:bg_color(cfg.row_bg_cursor[2], cfg.row_bg_cursor[3], cfg.row_bg_cursor[4])
                obj:bg_alpha(oa(cfg.row_bg_cursor[1]))
                set_color(obj, cfg.row_fg_cursor)
            elseif is_hover then
                obj:bg_visible(true)
                obj:bg_color(cfg.row_bg_hover[2], cfg.row_bg_hover[3], cfg.row_bg_hover[4])
                obj:bg_alpha(oa(cfg.row_bg_hover[1]))
                if is_last_saved then
                    set_color(obj, cfg.row_fg_gold)
                elseif node.children and #node.children > 0 then
                    set_color(obj, cfg.row_fg_cat)
                else
                    set_color(obj, cfg.row_fg_set)
                end
            elseif is_last_saved then
                set_color(obj, cfg.row_fg_gold)
            elseif node.children and #node.children > 0 then
                set_color(obj, cfg.row_fg_cat)
            else
                set_color(obj, cfg.row_fg_set)
            end
            obj:text(truncate(line, cols(d.list_w) - 4))
        else
            obj:text('')
            if icon then icon:visible(false) end
        end
    end
end

local function first_source_line_index()
    for index, meta in ipairs(state.preview_cards.evidence or {}) do
        if meta.source_line then return index end
    end
    return 1
end

local function source_pan_limit()
    local d = dims()
    local visible_cols = math.max(1, cols(d.preview_w) - 1)
    local max_len = 0
    for _, meta in ipairs(state.preview_cards.evidence or {}) do
        if meta.source_line and meta.text then
            max_len = math.max(max_len, #meta.text)
        end
    end
    return math.max(0, max_len - visible_cols)
end

local function render_preview()
    local d = dims()
    state.preview_lines = active_preview_lines()

    local max_scroll = math.max(0, #state.preview_lines - cfg.visible_rows)
    if state.preview_card == 'evidence' then
        if #state.preview_lines == 0 then
            state.source_cursor = 0
        else
            if state.source_cursor == 0 then
                state.source_cursor = first_source_line_index()
            end
            state.source_cursor = clamp(state.source_cursor, 1, #state.preview_lines)
        end
        state.source_pan = clamp(state.source_pan or 0, 0, source_pan_limit())
    else
        state.source_cursor = 0
        state.source_pan = 0
        clear_source_left_guard()
    end
    state.preview_scroll = clamp(state.preview_scroll, 0, max_scroll)

    for i = 1, cfg.visible_rows do
        local row_index = state.preview_scroll + i
        local meta = state.preview_lines[row_index]
        local obj = state.preview_rows[i]
        local tag = state.preview_aug_tags[i]
        obj:bg_visible(false)
        if tag then
            tag:text('')
            tag:visible(false)
        end
        if meta then
            if meta.bg then
                obj:bg_visible(true)
                obj:bg_color(meta.bg[2], meta.bg[3], meta.bg[4])
                obj:bg_alpha(oa(meta.bg[1]))
            end
            local text = meta.text
            local color = meta.color or cfg.row_fg_set
            if state.preview_card == 'evidence' and row_index == state.source_cursor then
                obj:bg_visible(true)
                obj:bg_color(cfg.row_bg_changed[2], cfg.row_bg_changed[3], cfg.row_bg_changed[4])
                obj:bg_alpha(oa(cfg.row_bg_changed[1]))
                color = cfg.row_fg_cursor
            end
            if meta.source_line and state.preview_card == 'evidence' then
                if state.source_pan > 0 then
                    text = text:sub(state.source_pan + 1)
                end
            end
            obj:text(truncate(text, cols(d.preview_w) - 1))
            set_color(obj, color)
            if tag and meta.aug_tag and meta.aug_tag_col then
                tag:pos(d.preview_x + sc(8) + (meta.aug_tag_col * sc(TEXT_CHAR_WIDTH)), d.body_y + sc(cfg.row_height) + sc(LM.content_top_pad) + (i - 1) * sc(cfg.row_height))
                tag:text(meta.aug_tag)
                set_color(tag, meta.aug_tag_color or cfg.row_fg_blue)
                tag:visible(state.visible)
            end
        else
            obj:text('')
        end
    end
end

function ui.refresh()
    if not state.visible then return end
    update_positions()
    render_tree()
    render_list()
    render_preview()
end

function ui.show()
    state.visible = true
    if state.cursor == 0 and #state.flat > 0 then state.cursor = 1 end
    auto_preview()
    set_visible(true)
    ui.refresh()
end

function ui.hide()
    state.visible = false
    state.hover = nil
    state.focus = 'tree'
    state.preview_card = 'gear'
    set_visible(false)
end

function ui.toggle()
    if state.visible then ui.hide() else ui.show() end
end

function ui.is_visible()
    return state.visible
end

function ui.set_opacity(pct)
    cfg.ui_opacity = math.max(35, math.min(100, math.floor(tonumber(pct) or 100)))
    if state.visible then ui.refresh() end
end

function ui.get_opacity()
    return cfg.ui_opacity or 100
end

function ui.show_preview(node)
    maybe_clear_recent_saved(node)
    state.preview_cards = build_preview_cards(node)
    if state.preview_cards.summary_only then
        state.preview_card = nil
    elseif is_equippable_leaf(node) then
        state.preview_card = 'gear'
    else
        state.preview_card = nil
    end
    state.preview_lines = active_preview_lines()
    state.preview_scroll = 0
    state.source_cursor = 0
    state.source_pan = 0
    clear_source_left_guard()
    if state.visible then render_preview() end
end

function ui.hide_preview()
    state.preview_cards = { summary = {}, gear = {}, changes = {}, evidence = {} }
    state.preview_lines = {}
    state.preview_scroll = 0
    state.source_cursor = 0
    state.source_pan = 0
    clear_source_left_guard()
    if state.visible then render_preview() end
end

local function scroll_preview(delta)
    state.preview_lines = active_preview_lines()
    local max_scroll = math.max(0, #state.preview_lines - cfg.visible_rows)
    state.preview_scroll = clamp(state.preview_scroll + delta, 0, max_scroll)
    if state.visible then render_preview() end
end

local function selected_data_line_is_source()
    local lines = state.preview_cards.evidence or {}
    local meta = lines[state.source_cursor]
    return meta and meta.source_line
end

local function move_source_cursor(delta)
    state.preview_lines = state.preview_cards.evidence or {}
    if #state.preview_lines == 0 then return end

    clear_source_left_guard()
    if state.source_cursor == 0 then
        state.source_cursor = first_source_line_index()
    end
    state.source_cursor = clamp(state.source_cursor + delta, 1, #state.preview_lines)

    if state.source_cursor <= state.preview_scroll then
        state.preview_scroll = math.max(0, state.source_cursor - 1)
    elseif state.source_cursor > state.preview_scroll + cfg.visible_rows then
        state.preview_scroll = state.source_cursor - cfg.visible_rows
    end
    if not selected_data_line_is_source() then
        state.source_pan = 0
    end
    if state.visible then render_preview() end
end

local function pan_source(delta)
    local before = state.source_pan or 0
    state.source_pan = clamp((state.source_pan or 0) + delta, 0, source_pan_limit())
    if delta > 0 then clear_source_left_guard() end
    if state.visible then render_preview() end
    return before, state.source_pan
end

function ui.toggle_preview_focus()
    state.focus = 'tree'
    if state.preview_cards.summary_only then
        state.preview_card = nil
    else
        state.preview_card = 'gear'
    end
    state.preview_scroll = 0
    state.source_cursor = 0
    state.source_pan = 0
    clear_source_left_guard()
    state.preview_lines = active_preview_lines()
    if state.visible then ui.refresh() end
end

function ui.is_preview_focused()
    return false
end

auto_preview = function()
    local node = selected_node()
    if node then
        ui.show_preview(node)
    else
        ui.hide_preview()
    end
    notify_selection_changed()
end

local function activate_node(node)
    if not node then return end

    select_node(node)
    if node.has_gear then
        local cmd = tree.equip_command(node)
        if cmd then
            if state.equip_callback then
                state.equip_callback(node, cmd)
            else
                windower.send_command(cmd)
            end
        end
    elseif node.children and #node.children > 0 then
        tree.toggle(node)
    end

    auto_preview()
    ui.refresh()
end

function ui.cursor_up()
    if not state.visible or #state.flat == 0 then return end
    if is_equippable_leaf(selected_node()) and state.preview_card ~= 'gear' then
        if state.preview_card == 'evidence' then
            move_source_cursor(-1)
        else
            scroll_preview(-1)
        end
        return
    end
    if state.cursor <= 1 then
        state.cursor = #state.flat
        state.scroll = math.max(0, #state.flat - cfg.visible_rows)
    else
        state.cursor = state.cursor - 1
    end
    ensure_cursor_visible()
    auto_preview()
    ui.refresh()
end

function ui.cursor_down()
    if not state.visible or #state.flat == 0 then return end
    if is_equippable_leaf(selected_node()) and state.preview_card ~= 'gear' then
        if state.preview_card == 'evidence' then
            move_source_cursor(1)
        else
            scroll_preview(1)
        end
        return
    end
    if state.cursor >= #state.flat then
        state.cursor = 1
        state.scroll = 0
    else
        state.cursor = state.cursor + 1
    end
    ensure_cursor_visible()
    auto_preview()
    ui.refresh()
end

function ui.cursor_select()
    activate_node(selected_node())
end

function ui.cursor_equip()
    local node = selected_node()
    if not node or not node.has_gear then return end
    local cmd = tree.equip_command(node)
    if not cmd then return end
    if state.equip_callback then
        state.equip_callback(node, cmd)
    else
        windower.send_command(cmd)
    end
end

function ui.cursor_back()
    local entry = selected_entry()
    if not entry then return end
    local node = entry.node

    if node.children and #node.children > 0 and node.expanded then
        tree.toggle(node)
        state.flat = tree.flatten(state.root)
        state.cursor = math.min(state.cursor, #state.flat)
        auto_preview()
        ui.refresh()
        return
    end

    local parent = find_parent(node)
    if parent then
        select_node(parent)
        auto_preview()
        ui.refresh()
    end
end

function ui.cursor_right(is_repeat)
    local node = selected_node()
    if not node then return end
    clear_source_left_guard()

    if is_equippable_leaf(node) and state.preview_card == 'evidence' then
        if selected_data_line_is_source() then
            pan_source(8)
        elseif not is_repeat then
            cycle_preview_tab(1)
        end
        return
    end

    if is_repeat then return end

    if node.children and #node.children > 0 then
        if not node.expanded then
            tree.toggle(node)
            state.flat = tree.flatten(state.root)
            ensure_cursor_visible()
            auto_preview()
            ui.refresh()
        end
        return
    end

    if is_equippable_leaf(node) then
        cycle_preview_tab(1)
    end
end

function ui.cursor_left(is_repeat)
    if is_equippable_leaf(selected_node()) and state.preview_card ~= 'gear' then
        if state.preview_card == 'evidence' and selected_data_line_is_source() then
            if (state.source_pan or 0) > 0 then
                local _, after = pan_source(-8)
                if after == 0 then
                    state.source_left_edge_until = os.clock() + SOURCE_LEFT_EDGE_HOLD_SECONDS
                end
                return
            end

            if (state.source_left_edge_until or 0) > os.clock() then
                state.source_left_edge_until = os.clock() + SOURCE_LEFT_EDGE_REPEAT_SECONDS
                return
            end
        end
        if is_repeat then return end
        clear_source_left_guard()
        cycle_preview_tab(-1)
        return
    end

    if is_repeat then return end
    clear_source_left_guard()
    ui.cursor_back()
end

local function hit_test(mx, my)
    if not state.visible then return nil end
    local d = dims()

    -- Tab bar: full visual tab row (body_y to body_y+row_height) within the preview panel.
    -- Extended 2px upward into the gap below the header bar (body_y - 2 is the gap, NOT the
    -- header bar itself, so header drag is unaffected) and 8px downward for easier clicking.
    -- Only matches mx >= preview_x so the left (tree/header) drag zone is never touched.
    local tabs_x, _, tabs_y, tabs_h = tab_strip_bounds(d)
    local tabs_right = d.x + d.total_w
    if my >= tabs_y - 2 and my < tabs_y + tabs_h + 8
    and mx >= tabs_x and mx < tabs_right then
        local tab_count = #PREVIEW_TABS
        local tab_idx = math.min(math.floor((mx - tabs_x) * tab_count / (tabs_right - tabs_x)) + 1, tab_count)
        return 'tab', PREVIEW_TABS[tab_idx]
    end

    local drag_bottom = d.body_y + sc(cfg.row_height)
    if mx >= d.x and mx <= d.x + d.total_w and my >= d.y and my < drag_bottom then
        return 'header'
    end

    local row_top = d.body_y + sc(cfg.row_height) + sc(LM.content_top_pad)
    local row_bottom = row_top + cfg.visible_rows * sc(cfg.row_height)

    if my >= row_top and my < row_bottom then
        local row = math.floor((my - row_top) / sc(cfg.row_height)) + 1
        -- Extend right by cfg.gap to include the gap pixels between the tree panel
        -- and the divider/next panel. This matches the full usable tree row area.
        -- Works correctly with or without the list pane (list_x = tree_x + tree_w + gap).
        if mx >= d.tree_x and mx < d.tree_x + d.tree_w + sc(cfg.gap) then
            local flat_idx = state.scroll + row
            local entry = state.flat[flat_idx]
            if entry then return 'tree_row', entry.node, flat_idx end
        elseif mx >= d.list_x and mx <= d.list_x + d.list_w then
            local node = active_list_items()[row]
            if node then return 'list_row', node end
        elseif mx >= d.preview_x and mx <= d.preview_x + d.preview_w then
            return 'preview'
        end
    end

    return nil
end

-- Shared activation: performs the full tree-row / list-row / tab / preview action.
-- Called by on_left_click whenever a GearTree control should be activated.
local function activate_hit(kind, node, flat_idx)
    if kind == 'tree_row' then
        state.cursor = flat_idx
        activate_node(node)     -- selects, expands/collapses or equips, then refresh
        return true
    elseif kind == 'list_row' then
        activate_node(node)
        return true
    elseif kind == 'tab' then
        if node then            -- node holds the card name string from hit_test
            state.preview_card = node
            if state.visible then ui.refresh() end
        end
        return true
    elseif kind == 'preview' then
        return true
    end
    return false
end

-- ── Layout calibration: guide hit-test + drag ────────────────────────────
local LAYOUT_EDGE_GRAB = 6   -- px from the bottom edge that triggers resize

local function layout_guide_at(mx, my)
    -- Iterate last→first so later (more specific) guides win on overlap.
    for i = #state.layout_bounds, 1, -1 do
        local g = state.layout_bounds[i]
        if g.edit and mx >= g.x and mx <= g.x + g.w and my >= g.y and my <= g.y + g.h then
            return g
        end
    end
    return nil
end

local function layout_begin_drag(mx, my)
    local g = layout_guide_at(mx, my)
    if not g then return false end
    local edit = g.edit
    -- binds: list of { metric, axis, start_v }.  Edge proximity → resize that
    -- dimension; otherwise move (both axes that have a metric).
    local binds = {}
    if edit.resize_w and mx >= g.x + g.w - LAYOUT_EDGE_GRAB then
        binds[#binds + 1] = { metric = edit.resize_w, axis = 'x' }
    elseif edit.resize_h and my >= g.y + g.h - LAYOUT_EDGE_GRAB then
        binds[#binds + 1] = { metric = edit.resize_h, axis = 'y' }
    else
        if edit.move_x then binds[#binds + 1] = { metric = edit.move_x, axis = 'x' } end
        if edit.move_y then binds[#binds + 1] = { metric = edit.move_y, axis = 'y' } end
    end
    if #binds == 0 then return false end
    for _, b in ipairs(binds) do b.start_v = LM[b.metric] end
    state.layout_drag = { binds = binds, start_mx = mx, start_my = my }
    return true
end

local function layout_update_drag(mx, my)
    local s = state.layout_drag
    if not s then return false end
    for _, b in ipairs(s.binds) do
        local delta = (b.axis == 'x') and (mx - s.start_mx) or (my - s.start_my)
        LM[b.metric] = lm_clamp(b.metric, b.start_v + delta)
    end
    if state.visible then ui.refresh() end
    return true
end

local function layout_end_drag()
    state.layout_drag = nil
end

function ui.set_layout_mode(on)
    state.layout_mode = on and true or false
    state.layout_drag = nil
    if state.visible then ui.refresh() end
    return state.layout_mode
end

function ui.get_layout_mode()
    return state.layout_mode and true or false
end

function ui.get_layout()
    local c = {}
    for k in pairs(LM_DEFAULTS) do c[k] = LM[k] end
    return c
end

function ui.set_layout(t)
    apply_layout(t)
    if state.visible then ui.refresh() end
end

function ui.reset_layout()
    for k, v in pairs(LM_DEFAULTS) do LM[k] = v end
    if state.visible then ui.refresh() end
    return ui.get_layout()
end

-- Copyable Lua-table lines (used by //gt calib print).  Grouped by zone.
function ui.layout_lines()
    local order = {
        'chrome_inset', 'content_top_pad',
        'header_x_offset', 'header_y_offset', 'header_w_adjust', 'header_h_adjust',
        'header_text_x_offset', 'header_text_y_offset',
        'tab_x_offset', 'tab_y_offset', 'tab_w_adjust', 'tab_h_adjust', 'tab_right_trim',
        'preview_tab_text_x_offset', 'preview_tab_text_y_offset',
        'tree_header_text_x_offset', 'tree_header_text_y_offset',
        'content_x_offset', 'content_w_adjust',
        'footer_x_offset', 'footer_y_offset', 'footer_w_adjust', 'footer_h_adjust',
        'footer_text_x_offset', 'footer_text_y_offset',
    }
    local lines = { 'layout = {' }
    for _, k in ipairs(order) do
        lines[#lines + 1] = string.format('    %s = %d,', k, LM[k] or 0)
    end
    lines[#lines + 1] = '}'
    return lines
end

-- Read-only: actual computed frame/background/zone bounds currently in use.
-- Recomputes the exact values update_positions() uses (no side effects, no
-- layout change).  Used by //gt bginfo.
function ui.bounds_lines()
    local d = dims()
    local frame_pad = 2
    local image_frame = state.panel_9slice and state.panel_9slice.enabled
    local art_mode = false  -- window_bg.png removed; 9-slice is outer frame only
    local frame_x = d.x - frame_pad
    local frame_y = d.y - frame_pad
    local frame_w = d.total_w + frame_pad * 2
    local header_h = d.body_y - d.y
    -- Content-derived geometry (mirrors update_positions exactly).
    local bl_row_top    = d.body_y + LM.tab_y_offset
    local bl_row_h      = math.max(6, cfg.row_height + LM.tab_h_adjust + 2)
    local bl_row_bottom = bl_row_top + bl_row_h
    local bl_content_y  = bl_row_bottom + LM.content_top_pad
    local bl_content_h  = cfg.visible_rows * cfg.row_height
    local bl_footer_rule_y = bl_content_y + bl_content_h
    local bl_footer_bg_h   = cfg.footer_height + LM.footer_h_adjust
    local bl_footer_bg_y   = bl_footer_rule_y + 1
    local bl_footer_bottom = bl_footer_bg_y + bl_footer_bg_h
    local bottom_pad = image_frame and math.max(4, math.floor(SLICE_CORNER / 3)) or frame_pad
    local frame_h
    if image_frame then
        frame_h = (bl_footer_bottom - frame_y) + bottom_pad
    else
        frame_h = (bl_footer_bottom - frame_y) + frame_pad
    end

    local tx, tw, ty, th = tab_strip_bounds(d)

    local chrome_inset = image_frame and LM.chrome_inset or 0
    local chrome_x = (image_frame and frame_x or d.x) + chrome_inset
    local chrome_w = (image_frame and frame_w or d.total_w) - (chrome_inset * 2)
    local fx = chrome_x + (image_frame and LM.footer_x_offset or 0)
    local fw = chrome_w + (image_frame and LM.footer_w_adjust or 0)
    local fh = bl_footer_bg_h
    local fy = bl_footer_bg_y

    local tree_w_px = d.preview_x - d.x   -- tree pane spans x .. preview_x

    local function ln(fmt, ...) return string.format(fmt, ...) end
    return {
        ln('-- GearTree bounds  (image_frame=%s  art_mode=%s)', tostring(image_frame and true or false), tostring(art_mode)),
        ln('frame      x=%d y=%d w=%d h=%d', frame_x, frame_y, frame_w, frame_h),
        ln('window     x=%d total_w=%d body_y=%d', d.x, d.total_w, d.body_y),
        ln('tabrow     x=%d y=%d w=%d h=%d', tx, ty, tw, th),
        ln('content    y=%d h=%d bottom=%d', bl_content_y, bl_content_h, bl_footer_rule_y),
        ln('tree       x=%d y=%d w=%d h=%d', d.x, d.body_y, tree_w_px, bl_footer_bottom - d.body_y),
        ln('preview    x=%d y=%d w=%d h=%d', d.preview_x, d.body_y, d.preview_w, bl_footer_bottom - d.body_y),
        ln('footer     x=%d y=%d w=%d h=%d  rule_y=%d', fx, fy, fw, fh, bl_footer_rule_y),
    }
end

function ui.on_left_click(mx, my)
    -- Layout calibration mode: clicks drag guides only; normal row/tab/header
    -- activation is disabled so nothing equips or navigates by accident.
    if state.layout_mode then
        return layout_begin_drag(mx, my)
    end
    local kind, node, flat_idx = hit_test(mx, my)
    -- Header drag is window management, not a GearTree control.
    -- It works regardless of mouse_mode so the window can always be repositioned.
    if kind == 'header' then
        state.drag = { mx = mx, my = my, x = cfg.pos_x, y = cfg.pos_y }
        return true
    end
    -- 'off' mode: hover still works, but left click does not activate controls.
    -- Return false so FFXI receives the click normally.
    if cfg.mouse_mode == 'off' then return false end
    return activate_hit(kind, node, flat_idx)
end

function ui.on_left_up()
    if state.layout_drag then
        layout_end_drag()
        return true
    end
    if state.drag then
        state.drag = nil
        if state.save_pos_callback then
            state.save_pos_callback(cfg.pos_x, cfg.pos_y)
        end
        return true
    end
    return false
end

-- ── Cursor overlay (visual-only) ─────────────────────────────────────────
-- A small gold crosshair drawn at the last mouse position.  Image-layer rects,
-- so it sits above the background/panels (below text, which is fine for a thin
-- crosshair).  Never affects clicks or hitboxes.
local function set_cursor_overlay_visible(vis)
    if state.cursor_objs then
        for _, o in ipairs(state.cursor_objs) do o:visible(vis) end
    end
    if state.cursor_img then state.cursor_img:visible(vis) end
end

local function point_in_panel(mx, my)
    local d = dims()
    local top = d.y
    -- Compute footer bottom from content geometry (mirrors update_positions).
    local row_h_pp      = math.max(sc(6), sc(cfg.row_height + LM.tab_h_adjust + 2))
    local content_y_pp  = d.body_y + row_h_pp + sc(LM.content_top_pad)
    local footer_bg_h_pp = sc(cfg.footer_height) + sc(LM.footer_h_adjust)
    local bottom = content_y_pp + cfg.visible_rows * sc(cfg.row_height) + 1 + footer_bg_h_pp
    return mx >= d.x and mx <= d.x + d.total_w and my >= top and my <= bottom
end

local function update_cursor_overlay(mx, my)
    if not state.cursor_objs then return end
    mx = mx or state.mouse_x
    my = my or state.mouse_y
    -- Show only when: enabled AND GearTree visible AND we have a position AND
    -- the position is inside the panel bounds (inside-only mode).
    if not (cfg.cursor_overlay and state.visible and mx and my and point_in_panel(mx, my)) then
        set_cursor_overlay_visible(false)
        return
    end
    local cx, cy = math.floor(mx), math.floor(my)

    if state.cursor_img then
        -- Themed pointer image: hide the primitive crosshair, show the image with
        -- its tip aligned to the mouse coordinate.
        if state.cursor_objs then
            for _, o in ipairs(state.cursor_objs) do o:visible(false) end
        end
        state.cursor_img:pos(cx - CURSOR_TIP_X, cy - CURSOR_TIP_Y)
        state.cursor_img:size(sc(CURSOR_IMG_SIZE), sc(CURSOR_IMG_SIZE))
        state.cursor_img:visible(true)
        return
    end

    -- Primitive crosshair fallback (no cursor.png present).
    local arm = sc(7)
    -- Shadow first (offset +1,+1), then the gold crosshair on top.
    set_rect(state.cursor_shadow_h, cx - arm + 1, cy + 1,       arm * 2 + 1, 1,           cfg.cursor_shadow)
    set_rect(state.cursor_shadow_v, cx + 1,       cy - arm + 1, 1,           arm * 2 + 1, cfg.cursor_shadow)
    set_rect(state.cursor_line_h,   cx - arm,     cy,           arm * 2 + 1, 1,           cfg.cursor_fg)
    set_rect(state.cursor_line_v,   cx,           cy - arm,     1,           arm * 2 + 1, cfg.cursor_fg)
end

function ui.set_cursor_overlay(on)
    cfg.cursor_overlay = on and true or false
    if cfg.cursor_overlay then
        update_cursor_overlay(state.mouse_x, state.mouse_y)
    else
        set_cursor_overlay_visible(false)
    end
    return cfg.cursor_overlay
end

function ui.get_cursor_overlay()
    return cfg.cursor_overlay and true or false
end

function ui.on_mouse_move(mx, my)
    -- Track the latest mouse position and update the optional cursor overlay
    -- (visual only — happens regardless of drag/hover logic below).
    state.mouse_x, state.mouse_y = mx, my
    update_cursor_overlay(mx, my)

    -- Layout calibration drag takes priority and blocks normal hover/drag.
    if state.layout_drag then
        return layout_update_drag(mx, my)
    end

    if state.drag then
        local dx = mx - state.drag.mx
        local dy = my - state.drag.my
        ui.set_position(state.drag.x + dx, state.drag.y + dy)
        return true
    end

    -- Update hover target. Only re-render when the hovered row actually changes.
    if state.visible and mx and my then
        local kind, node, flat_idx = hit_test(mx, my)
        local new_hover
        if kind == 'tree_row' then
            new_hover = { kind = 'tree_row', flat_idx = flat_idx }
        elseif kind == 'list_row' then
            new_hover = { kind = 'list_row', node = node }
        elseif kind == 'tab' then
            new_hover = { kind = 'tab', card = node }
        end

        local old = state.hover
        local changed = (old == nil) ~= (new_hover == nil)
        if not changed and old and new_hover then
            changed = old.kind    ~= new_hover.kind
                   or old.flat_idx ~= new_hover.flat_idx
                   or old.node    ~= new_hover.node
                   or old.card    ~= new_hover.card
        end

        if changed then
            state.hover = new_hover
            -- Re-render tab bar only when a tab is entering or leaving hover.
            local tab_involved = (old and old.kind == 'tab') or (new_hover and new_hover.kind == 'tab')
            if tab_involved then update_positions() end
            render_tree()
            render_list()
        end
    end

    return false
end

function ui.on_right_click(mx, my)
    -- Right click is not a GearTree control in any mode.
    return false
end

function ui.on_scroll(mx, my, delta)
    if not state.visible then return false end

    local kind = hit_test(mx, my)
    if kind == 'preview' then
        if delta > 0 then
            scroll_preview(3)
        else
            scroll_preview(-3)
        end
        return true
    end

    if delta > 0 then
        ui.cursor_down()
    else
        ui.cursor_up()
    end
    return true
end

function ui.set_position(x, y)
    cfg.pos_x = x
    cfg.pos_y = y
    update_positions()
    if state.visible then ui.refresh() end
end

function ui.get_position()
    return cfg.pos_x, cfg.pos_y
end

function ui.set_equip_callback(callback)
    state.equip_callback = callback
end

function ui.set_selection_callback(callback)
    state.selection_callback = callback
end

function ui.get_selected_node()
    return selected_node()
end

local function augment_signature_text(sig)
    if not sig then return 'none' end
    if type(sig) == 'table' then
        if #sig > 0 then
            return table.concat(sig, ', ')
        end
        local out = {}
        for k, v in pairs(sig) do
            out[#out + 1] = tostring(k) .. '=' .. tostring(v)
        end
        table.sort(out)
        return #out > 0 and table.concat(out, ' | ') or 'none'
    end
    return tostring(sig)
end

local function list_text(list)
    if type(list) ~= 'table' or #list == 0 then
        return 'none'
    end
    return table.concat(list, ', ')
end

local function normalize_debug_slot_input(slot)
    local text = trim(slot):lower()
    if text == '' then return nil end

    text = text:gsub('[_%-]+', ' ')
    text = text:gsub('%s+', ' ')
    text = trim(text)

    local aliases = {
        ['ear 1'] = 'left_ear',
        ['left ear'] = 'left_ear',
        ['ear1'] = 'left_ear',
        ['lear'] = 'left_ear',
        ['ear 2'] = 'right_ear',
        ['right ear'] = 'right_ear',
        ['ear2'] = 'right_ear',
        ['rear'] = 'right_ear',
        ['ring 1'] = 'left_ring',
        ['left ring'] = 'left_ring',
        ['ring1'] = 'left_ring',
        ['lring'] = 'left_ring',
        ['ring 2'] = 'right_ring',
        ['right ring'] = 'right_ring',
        ['ring2'] = 'right_ring',
        ['rring'] = 'right_ring',
        ['ranged'] = 'range',
    }

    if aliases[text] then
        return aliases[text]
    end

    local compact = text:gsub('%s+', '_')
    return gear_slots.canonical(compact) or gear_slots.canonical(text)
end

local function exact_match_state(spec, item)
    if not spec or not item or item.empty then
        if spec and spec.expected_empty and item and item.empty then
            return true, true, true, true
        end
        return false, false, false
    end

    if spec and spec.expected_empty then
        return false, false, false, item.augments_available ~= false
    end

    local id_match = false
    if spec.item_id then
        id_match = item.id == spec.item_id
    end

    local augment_match = true
    local augment_known = item.augments_available ~= false
    if spec.has_augments then
        if augment_known then
            augment_match = same_augments(spec.augments, item.augments)
        else
            augment_match = nil
        end
    end

    return id_match, augment_match, (id_match and augment_match) == true, augment_known
end

local function debug_slot_entry(node, slot_text)
    if not node or not node.has_gear then
        return nil, nil, 'Select a gear set first.'
    end

    local canonical_slot = normalize_debug_slot_input(slot_text)
    if not canonical_slot then
        return nil, nil, 'Usage: //gt debugslot <slot>'
    end

    for _, item in ipairs(tree.gear_preview(node) or {}) do
        if gear_slots.canonical(item.slot) == canonical_slot then
            return item, canonical_slot
        end
    end

    return nil, canonical_slot, 'That set does not define slot: ' .. slot_label(canonical_slot)
end

function ui.debug_selected_gear()
    local node = selected_node()
    if not node or not is_equippable_leaf(node) then
        return nil, 'Select a gear row first.'
    end

    local lines = {}
    lines[#lines + 1] = 'Path: ' .. path_string(node)

    for _, item in ipairs(tree.gear_preview(node) or {}) do
        local spec = resolve_gear_spec(item.value)
        local equipped = equipped_item_for_slot(item.slot)
        lines[#lines + 1] = string.format(
            '%s expected="%s" id=%s expected_aug=%s',
            slot_label(item.slot),
            tostring(spec.display_name or ''),
            tostring(spec.item_id or 'nil'),
            list_text(spec.augments)
        )
        lines[#lines + 1] = string.format(
            '  equipped="%s" id=%s aug_list=%s raw=%s',
            tostring(equipped and equipped.name or 'nil'),
            tostring(equipped and equipped.id or 'nil'),
            list_text(equipped and equipped.augments or nil),
            tostring(equipped and equipped.extdata or 'nil')
        )
    end

    return lines
end

function ui.debug_selected_slot(slot)
    local node = selected_node()
    local preview_item, canonical_slot, err = debug_slot_entry(node, slot)
    if not preview_item then
        return nil, err
    end

    local spec = resolve_gear_spec(preview_item.value)
    local equipped = equipped_item_for_slot(canonical_slot)
    local row_state = gear_row_status(preview_item, path_string(node))
    local path = path_string(node)
    local lines = {}
    local alias_key = gear_reference_key(preview_item.value)
    local alias_resolved = alias_key and state.gear_reference_items[alias_key] ~= nil
    local raw_slot_value = tostring(preview_item.slot or canonical_slot) .. '=' .. tostring(preview_item.value or '')

    lines[#lines + 1] = 'EXPECTED FROM LUA:'
    lines[#lines + 1] = '  selected set path: ' .. path
    lines[#lines + 1] = '  slot: ' .. slot_label(canonical_slot) .. ' (' .. canonical_slot .. ')'
    lines[#lines + 1] = '  raw slot value: ' .. raw_slot_value
    lines[#lines + 1] = '  resolved as gear.* alias: ' .. tostring(alias_key ~= nil)
    lines[#lines + 1] = '  alias resolved from database: ' .. tostring(alias_resolved == true)
    if spec.unresolved_ref then
        lines[#lines + 1] = '  unresolved gear reference: ' .. tostring(spec.unresolved_ref)
        lines[#lines + 1] = '  lookup skipped: true'
    end
    lines[#lines + 1] = '  resolved expected name: ' .. tostring(spec.display_name or 'none')
    lines[#lines + 1] = '  normalized expected name: ' .. tostring(spec.lookup_normalized or 'none')
    lines[#lines + 1] = '  exact lookup result: ' .. tostring(spec.lookup_exact_id or 'none') .. ' / ' .. tostring(spec.lookup_exact_name or 'none') .. ' / ' .. tostring(spec.lookup_exact_field or 'none')
    lines[#lines + 1] = '  matched english name: ' .. tostring(spec.lookup_matched_english or 'none')
    lines[#lines + 1] = '  matched english_log name: ' .. tostring(spec.lookup_matched_english_log or 'none')
    if spec.lookup_candidates and #spec.lookup_candidates > 0 then
        local parts = {}
        for _, candidate in ipairs(spec.lookup_candidates) do
            parts[#parts + 1] = string.format('%s=%s [%s]', tostring(candidate.id), tostring(candidate.name), tostring(candidate.field or ''))
        end
        lines[#lines + 1] = '  abbreviation candidates: ' .. table.concat(parts, ' | ')
    else
        lines[#lines + 1] = '  abbreviation candidates: none'
    end
    if spec.lookup_exact_candidates and #spec.lookup_exact_candidates > 1 then
        local parts = {}
        for _, candidate in ipairs(spec.lookup_exact_candidates) do
            parts[#parts + 1] = string.format('%s=%s [%s]', tostring(candidate.id), tostring(candidate.name), tostring(candidate.field or ''))
        end
        lines[#lines + 1] = '  exact candidates: ' .. table.concat(parts, ' | ')
    end
    lines[#lines + 1] = '  final matched resource: ' .. tostring(spec.resolved_name or 'none') .. ' / ' .. tostring(spec.item_id or 'none') .. ' / ' .. tostring(spec.lookup_matched_field or 'none')
    local id_note = spec.disambiguated_by_inventory and ' (disambiguated by inventory)' or ''
    lines[#lines + 1] = '  resolved expected item ID: ' .. tostring(spec.item_id or 'none') .. id_note
    lines[#lines + 1] = '  expected augments raw: ' .. augment_signature_text(spec.expected_augments_raw)
    lines[#lines + 1] = '  expected augments parsed: ' .. list_text(spec.expected_augments)

    local equipped_name = (equipped and not equipped.empty) and equipped.name or 'empty'
    local equipped_id = (equipped and not equipped.empty) and equipped.id or 'none'
    local equipped_augs = (equipped and not equipped.empty) and equipped.augments or nil
    local id_match, augment_match, exact_match, augment_known = exact_match_state(spec, equipped)

    lines[#lines + 1] = 'CURRENT EQUIPPED SLOT:'
    lines[#lines + 1] = '  equipped item name: ' .. tostring(equipped_name)
    lines[#lines + 1] = '  equipped item ID: ' .. tostring(equipped_id)
    lines[#lines + 1] = '  equipped augments raw: ' .. tostring(equipped and equipped.extdata or 'none')
    lines[#lines + 1] = '  equipped augments parsed: ' .. list_text(equipped_augs)
    local path_rank_text = 'none'
    if equipped and not equipped.empty and equipped.aug_path then
        path_rank_text = 'Path ' .. equipped.aug_path
        if equipped.aug_rank then
            path_rank_text = path_rank_text .. ' Rank ' .. tostring(equipped.aug_rank)
        end
    end
    lines[#lines + 1] = '  equipped path/rank: ' .. path_rank_text
    lines[#lines + 1] = '  ID match: ' .. tostring(id_match)
    lines[#lines + 1] = '  augment match: ' .. tostring(augment_match)
    lines[#lines + 1] = '  augment values available: ' .. tostring(augment_known)

    lines[#lines + 1] = 'INVENTORY / STORAGE SEARCH:'
    if not spec.item_id then
        lines[#lines + 1] = '  no matching item ID found anywhere.'
    else
        local matches = item_locations_by_id(spec.item_id)
        if #matches == 0 then
            lines[#lines + 1] = '  no matching item ID found anywhere.'
        else
            for _, location in ipairs(matches) do
                local _, _, exact = exact_match_state(spec, location)
                local loc_pr = location.aug_path and ('path=' .. location.aug_path .. (location.aug_rank and ' Rank ' .. tostring(location.aug_rank) or '')) or nil
                lines[#lines + 1] = string.format(
                    '  - %s | bag=%s idx=%s avail=%s equip_ready=%s | id=%s | augments=%s%s | exact=%s',
                    tostring(location.label or bag_label(location.bag)),
                    tostring(location.bag or 'none'),
                    tostring(location.index or 'none'),
                    tostring(location.available == true),
                    tostring(location.equip_ready == true),
                    tostring(location.id or 'none'),
                    list_text(location.augments),
                    loc_pr and (' | ' .. loc_pr) or '',
                    tostring(exact)
                )
            end
        end
    end

    lines[#lines + 1] = 'FINAL RESULT:'
    lines[#lines + 1] = '  final gear-tab status: ' .. tostring(row_state.status or 'MISS')
    lines[#lines + 1] = '  augment mismatch flag: ' .. tostring(row_state.augment_mismatch == true)
    lines[#lines + 1] = '  paired slot match: ' .. tostring(row_state.paired_slot or 'none')
    lines[#lines + 1] = '  reason: ' .. tostring(row_state.reason or 'none')

    return lines
end

-- Compact one-line-per-slot status trace for the currently selected set.
-- Output: slot | set_item | equipped_item | id_match | aug_match | status | reason
-- Invoke via //gt debugstatus
function ui.debug_status_trace()
    local node = selected_node()
    if not node then
        return nil, 'No row is selected in the tree.'
    end
    local gear_items = tree.gear_preview(node) or {}
    if #gear_items == 0 then
        return nil, 'Selected node has no gear items to trace (select a set leaf, not a folder).'
    end

    local set_path = path_string(node)
    local lines = {}
    lines[#lines + 1] = 'STATUS TRACE: ' .. set_path

    for _, item in ipairs(gear_items) do
        local canonical = gear_slots.canonical(item.slot) or item.slot
        local spec     = resolve_gear_spec(item.value)
        local equipped = equipped_item_for_slot(item.slot)
        local row      = gear_row_status(item, set_path)

        local set_str = tostring(spec.display_name or item.value or '?')
        if spec.item_id then
            set_str = set_str .. '[id=' .. spec.item_id .. ']'
        end
        if spec.has_augments then
            set_str = set_str .. '{' .. list_text(spec.augments) .. '}'
        end

        local eq_str
        if not equipped or equipped.empty then
            eq_str = 'empty'
        else
            eq_str = tostring(equipped.name or '?')
            if equipped.id then eq_str = eq_str .. '[id=' .. equipped.id .. ']' end
            local augs = equipped.augments or {}
            if #augs > 0 then eq_str = eq_str .. '{' .. list_text(augs) .. '}' end
            if equipped.augments_available == false then eq_str = eq_str .. '[no_extdata]' end
        end

        local id_m   = row.id_match == true and 'Y' or 'N'
        local aug_m  = row.augment_match == true and 'Y' or (row.augment_mismatch and '~' or 'N')
        local pair_m = row.paired_slot and ('pair=' .. row.paired_slot) or ''

        lines[#lines + 1] = string.format(
            '  %-8s | set=%-40s | eq=%-40s | id=%s aug=%s %s| %s | %s',
            canonical,
            set_str,
            eq_str,
            id_m, aug_m,
            pair_m ~= '' and (pair_m .. ' ') or '',
            tostring(row.status or '?'),
            tostring(row.reason or '')
        )
    end

    return lines
end

function ui.select_path(path)
    local node = find_node_by_path(path)
    if not node then return false end

    select_node(node)
    auto_preview()
    if state.visible then ui.refresh() end
    return true
end

function ui.select_virtual_folder(id)
    local node = find_virtual_folder(id)
    if not node then return false end

    select_node(node)
    auto_preview()
    if state.visible then ui.refresh() end
    return true
end

local function query_matches_node(node, query)
    query = tostring(query or ''):lower()
    if query == '' or not node then return false end

    local key = tostring(node.key or ''):lower()
    local path = path_string(node):lower()
    if key:find(query, 1, true) or path:find(query, 1, true) then
        return true
    end

    if node.has_gear then
        local desc = tostring(tree.describe(node) or ''):lower()
        if desc:find(query, 1, true) then return true end

        for _, item in ipairs(tree.gear_preview(node)) do
            local slot = tostring(item.slot or ''):lower()
            local value = tostring(item.value or ''):lower()
            if slot:find(query, 1, true) or value:find(query, 1, true) then
                return true
            end
        end
    end

    return false
end

function ui.find(text)
    local query = tostring(text or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if query == '' or not state.root then return false end

    local nodes = {}
    walk_display(state.root, function(node)
        if node ~= state.root then nodes[#nodes + 1] = node end
        return nil
    end)

    if #nodes == 0 then return false end

    local current = selected_node()
    local start = 0
    for i, node in ipairs(nodes) do
        if node == current then
            start = i
            break
        end
    end

    for offset = 1, #nodes do
        local idx = ((start + offset - 1) % #nodes) + 1
        local node = nodes[idx]
        if query_matches_node(node, query) then
            select_node(node)
            auto_preview()
            if state.visible then ui.refresh() end
            return true
        end
    end

    return false
end

function ui.set_status(text)
    state.status_text = tostring(text or '')
    if state.footer then
        local d = dims()
        state.footer:text(truncate(state.status_text, cols(d.total_w) - 2))
    end
end

function ui.set_last_saved(path)
    state.last_saved_path = tostring(path or '')
    if state.visible then ui.refresh() end
end

local function refresh_preview_cards_preserving_source()
    maybe_clear_recent_saved(selected_node())
    local old_card = state.preview_card
    local old_cursor = state.source_cursor
    local old_pan = state.source_pan
    local old_scroll = state.preview_scroll

    state.preview_cards = build_preview_cards(selected_node())
    if state.preview_cards.summary_only then
        state.preview_card = nil
        state.source_cursor = 0
        state.source_pan = 0
        clear_source_left_guard()
    elseif state.preview_card == nil then
        state.preview_card = 'gear'
    end
    state.preview_lines = active_preview_lines()

    if old_card == 'evidence' and state.preview_card == 'evidence' then
        state.source_cursor = old_cursor
        state.source_pan = old_pan
        state.preview_scroll = old_scroll
    end
end

function ui.set_recent_saved_slots(path, slots)
    local lookup = {}
    for _, slot in ipairs(slots or {}) do
        if slot then lookup[gear_slots.canonical(slot) or slot] = true end
    end

    state.recent_saved = {
        path = path,
        slots = lookup,
    }
    refresh_preview_cards_preserving_source()
    if state.visible then render_preview() end
end

function ui.set_changes(path, rows, count)
    state.live_changes = {
        path = path,
        rows = rows or {},
        count = count or 0,
    }
    refresh_preview_cards_preserving_source()
    if state.visible then render_preview() end
end

function ui.clear_changes()
    state.live_changes = { path = nil, rows = {}, count = 0 }
    refresh_preview_cards_preserving_source()
    if state.visible then render_preview() end
end

function ui.set_current_equipment(path, equipment)
    state.current_equipment = {
        path = path,
        slots = equipment or {},
    }
    refresh_preview_cards_preserving_source()
    if state.visible then render_preview() end
end

function ui.clear_current_equipment()
    state.current_equipment = { path = nil, slots = {} }
    refresh_preview_cards_preserving_source()
    if state.visible then render_preview() end
end

function ui.set_gear_reference_items(references)
    state.gear_reference_items = references or {}
    refresh_preview_cards_preserving_source()
    if state.visible then render_preview() end
end

function ui.set_inventory_locations(locations)
    state.inventory_locations = locations or { items = {}, items_by_id = {}, bags = {} }
    refresh_preview_cards_preserving_source()
    if state.visible then render_preview() end
end

function ui.clear_inventory_locations()
    state.inventory_locations = { items = {}, items_by_id = {}, bags = {} }
    refresh_preview_cards_preserving_source()
    if state.visible then render_preview() end
end

function ui.rebuild(new_root)
    local previous = selected_node()
    local previous_path = previous and not previous.virtual and path_string(previous) or ''

    state.root = new_root
    state.flat = tree.flatten(state.root)
    state.scroll = 0

    local preferred_path = state.last_saved_path ~= '' and state.last_saved_path or previous_path
    if preferred_path ~= '' and ui.select_path(preferred_path) then
        return
    end

    state.cursor = #state.flat > 0 and math.max(1, math.min(state.cursor, #state.flat)) or 0
    auto_preview()
    ui.refresh()
end

return ui
