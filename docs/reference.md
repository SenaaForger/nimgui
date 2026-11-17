# nimgui API reference

[English](reference.md) | [Bahasa Indonesia](reference.id.md)

This page documents the public contract of `nimgui` version `0.1.0`. Load the facade with `require 'nimgui'`. Modules under `nimgui.*` are implementation details unless this page names them. For installation and a first script, see the [README](../README.md).

## Lifecycle

### `nimgui.render(cond, draw)` and `nimgui.render(cond, before, draw)`

Registers a panel with `mimgui.OnFrame`.

- `cond` is a function that returns `true` while the panel should be drawn.
- `before` is an optional function that runs before the frame starts.
- `draw` is the function that draws the panel contents.
- If `draw` raises an error, `nimgui` resets the layout and theme stacks, then re-raises the error.
- An active toast is drawn automatically after `draw`.

Returns the `mimgui` subscription object.

```lua
nimgui.render(function() return open end, function()
    nimgui.begin_panel('##panel')
    -- panel contents
    nimgui.end_panel()
end)
```

### `nimgui.shutdown()`

Releases every `render` subscription, runs the shutdown handlers, resets layout and widget state, releases every live media handle, and clears the theme stack. It is safe to call more than once.

Returns `true`, or `false, err` if a release or unsubscribe failed.

```lua
nimgui.add_shutdown_handler(function()
    nimgui.media.release(avatar)
end)
```

### `nimgui.add_shutdown_handler(fn)`

Adds a function that `shutdown()` calls. Handlers run in reverse registration order. An error in one handler does not stop the others; `shutdown()` returns the first error.

### `nimgui.capabilities()`

Returns a copy of the boolean feature probe for `mimgui` and host globals. The result is cached after the first call.

| Group | Keys |
|---|---|
| Drawing and layout | `draw_list`, `add_image`, `invisible_button`, `get_cursor_screen_pos`, `same_line`, `imvec2`, `imvec4`, `style`, `style_colors` |
| Value wrappers | `new_int`, `new_bool`, `new_float` |
| Fonts | `font_atlas`, `font_rebuild`, `push_font` |
| Textures | `texture_file`, `texture_memory`, `release_texture` |
| Widgets | `time`, `input_text`, `slider_float`, `combo`, `selectable`, `popup_modal`, `tooltip` |
| Host globals | `dpi_scale`, `working_directory`, `file_exists`, `screen_resolution`, `event_handler` |

A key is `true` only when the binding or global exists. For example, `texture_memory` is `true` when `mimgui.CreateTextureFromFileInMemory` is available.

## Theme and scale

### `nimgui.theme(spec, opts)`

Creates a theme object. `spec` is a built-in direction name or a table with custom direction fields.

| Direction | Mode |
|---|---|
| `instrument` | dark |
| `dispatch` | dark |
| `garage` | dark |
| `graphite` | dark |
| `paper` | light |

A custom direction table uses `hue`, `tint`, `accentHue`, `accentSat`, and `accentLight`. Add `mode = 'light'` for a light palette.

`opts`:

| Option | Default | Description |
|---|---|---|
| `scale` | `nimgui.scale()` | Multiplier for sizes, radii, and spacing |
| `radius` | `4 * scale` | Corner radius |
| `control_h` | `44 * scale` | Touch target height |
| `bg_alpha` | `248` | Panel background alpha (`0..255`) |
| `reduce_motion` | `false` | Disables decorative animation |

`radius` and `control_h` are multiplied by `scale` after they are read from `opts`.

The resulting theme object exposes:

| Field | Description |
|---|---|
| `mode` | `'dark'` or `'light'` |
| `scale` | Scale multiplier |
| `radius` | Corner radius in pixels |
| `control_h` | Control height in pixels |
| `reduce_motion` | Boolean |
| `raw` | Palette as `0xRRGGBB` integers |
| `color` | Palette packed as `IM_COL32` values |
| `sp(name)` | Spacing token in pixels |

Spacing tokens are multiplied by `scale`: `xs` 4, `sm` 8, `md` 12, `lg` 16, `xl` 24, `xxl` 32.

```lua
local theme = nimgui.theme('instrument', { reduce_motion = true })
local gap = theme.sp('md')
```

Pass the theme to `begin_panel` with `opts.theme`. Without an active theme, widgets use the `graphite` fallback at the current screen scale.

### `nimgui.scale()`

Returns `MONET_DPI_SCALE` when it is a positive number. Otherwise it derives a scale from the screen height (`height / 720`) and clamps it to `1.0..2.0`. If neither source is available, it returns `1.0`.

## Layout

### `nimgui.begin_panel(id, opts)`

Opens a panel and pushes its theme. Returns the `visible` value from `imgui.Begin`. Always call `nimgui.end_panel()`, including when `visible` is `false`.

| Option | Type | Default | Description |
|---|---|---|---|
| `theme` | table | active theme | Theme pushed for this panel |
| `pos` | `{x,y}` or `ImVec2` | `nil` | Window position in screen pixels, not a `0..1` ratio |
| `pivot` | `{x,y}` or `ImVec2` | `{0,0}` | Pivot of `pos` as a ratio of the window size (`0..1`) |
| `size` | `{x,y}` or `ImVec2` | `nil` | Window size |
| `size_cond` | number | `Always` when `anchored`, else `FirstUseEver` | Condition for applying `size` |
| `min`, `max` | `{x,y}` or `ImVec2` | `nil` | Size constraints |
| `anchored` | boolean | `false` | Applies `pos` every frame, which prevents dragging |
| `alpha` | number | `nil` | Panel alpha; pushed only when the value is below `1` |
| `open` | boolean | `nil` | Open/close state passed to `imgui.Begin` |
| `flags` | number | `0` | `ImGuiWindowFlags` |

If `opts.theme` is absent and no theme is active, the panel pushes the fallback theme. Nested panels keep the active theme.

To center a panel:

```lua
local screen_w, screen_h = getScreenResolution()
nimgui.begin_panel('##panel', {
    pos = { screen_w / 2, screen_h / 2 },
    pivot = { 0.5, 0.5 },
    flags = imgui.WindowFlags.NoTitleBar,
})
```

`pos` uses screen pixels. `pivot` uses a ratio of the window size. Leave out `imgui.WindowFlags.NoMove` and `anchored = true` when the panel should be draggable. Without `NoMove`, empty areas of the panel can drag it.

`size` with `FirstUseEver` is applied only once. If `getScreenResolution()` returns `0` or a loading-screen size on the first frame, the panel can lock to that fallback. Wait for a valid resolution before calling `begin_panel`, and use `size_cond = imgui.Cond.Always` for a fixed-size panel.

### `nimgui.end_panel()`

Closes the panel and restores the theme and alpha pushed by `begin_panel`. Returns `true`, or `false, err` when there is no matching panel.

### `nimgui.begin_child(id, size, border)` and `nimgui.end_child()`

Opens and closes a child window. `size` may be `nil` (which uses `0,0`); `border` is a boolean. Always pair the calls, including when the child is not visible. `end_child()` returns `true`, or `false, err` when there is no matching child.

### `nimgui.spacer(size)`

Adds vertical space. The default is `theme.active().sp('md')`. `size` must be a number.

### `nimgui.same_line(offset)`

Calls `imgui.SameLine`. `offset` defaults to `0`.

### `nimgui.separator()`

Calls `imgui.Separator`.

### `nimgui.grid_columns(avail_x, cell_w, gap)`

Returns how many columns fit in `avail_x`. `gap` defaults to `8`. The result is at least `1`.

```lua
local columns = nimgui.grid_columns(avail_width, 96, 8)
```

The formula is `floor((avail_x + gap) / (cell_w + gap))`. `avail_x` and `cell_w` must be positive numbers.

### `nimgui.truncate(text, max_width)`

Cuts `text` and appends `...` so it fits in `max_width`. It does not split a UTF-8 character. If `max_width` is not a positive number, the original text is returned. If even `...` does not fit, it returns `...`.

### `nimgui.footer_height()`

Returns `control_h + sp('md')`, useful for reserving space for a bottom button row.

## Widgets

Widgets that accept `state` take a plain table or a binder from `nimgui.state`. They refresh the binder from `state[key]` before drawing, so an external write is visible on the next frame. `cdata` is cached per table and key.

### `nimgui.button(role, label, opts)`

Draws a button. `role` is `primary`, `secondary`, `danger`, or `ghost`. Returns `true` when pressed.

| Option | Default | Description |
|---|---|---|
| `width` | content width | Button width; a negative value also means content width |
| `height` | `control_h` | Button height |
| `theme` | active theme | Theme override |
| `disabled` | `false` | Draws at `0.45` alpha and returns `false` |
| `disabled_hint` | `nil` | Tooltip text shown only while hovered |

`disabled_hint` is hover-only. On a touch screen, put required information in normal text instead.

### `nimgui.segmented(items, state, key, dt)`

Draws a row of choice buttons. `items` contains strings or tables with a `label` field. `state[key]` is a 1-based index; an invalid value falls back to `1`. The function writes the selected index to `state[key]` and returns it.

`dt` is optional. With `reduce_motion`, the selection changes without animation.

### `nimgui.toggle(id, state, key, dt)`

Draws a touch toggle. `id` must be stable and unique. Returns a boolean.

If the required draw-list bindings are unavailable, it falls back to `imgui.Checkbox`. Because the normal path uses `InvisibleButton`, it has no visible keyboard focus highlight. Use `nimgui.checkbox` when keyboard navigation matters.

### `nimgui.checkbox(label, state, key)`

Draws an ImGui checkbox with extra vertical padding to reach `control_h` (`44 * scale`). Returns a boolean.

### `nimgui.slider(label, state, key, min, max)`

Draws a float slider with the label above the control. `min` and `max` must be numbers. The value format is `%.2f`. Returns the current value.

The visible label is separate from the ImGui ID, which is derived from `key`. Two sliders with different labels but the same key share an ID.

### `nimgui.input_int(label, state, key, step, step_fast)`

Draws an integer input with the label above the control. `step` defaults to `1`; `step_fast` defaults to `100`. Returns the current value.

### `nimgui.input_float(label, state, key, step, step_fast)`

Draws a float input with the label above the control. `step` defaults to `0.1`; `step_fast` defaults to `1.0`. The format is `%.3f`. Returns the current value.

### `nimgui.input_text(label, state, key, max_len)`

Draws a text input with the label above the control. `max_len` defaults to `64`. The internal buffer is reused and grows when `max_len` increases. Returns the current string.

### `nimgui.stat_tile(label, value, opts)`

Draws a statistics tile with a small label and a large value. It returns nothing.

| Option | Default | Description |
|---|---|---|
| `width` | content width | Tile width |
| `height` | `64 * scale` | Tile height |
| `id` | `label` | Child window ID |
| `border` | `true` | Draws a border |
| `theme` | active theme | Theme override |

### `nimgui.progress(value, opts)`

Draws a progress bar. `value` is clamped to `0..1`. Returns the fraction that was actually drawn.

| Option | Default | Description |
|---|---|---|
| `width` | `-1` | Bar width; `-1` fills the content area |
| `height` | `6 * scale` | Bar height |
| `overlay` | `''` | Text drawn over the bar |
| `color` | accent | Bar color as `IM_COL32` |
| `theme` | active theme | Theme override |
| `smooth` | `false` | Animates the bar toward `value` |
| `id` | `##nimgui_progress` | Tracker ID used by `smooth` |
| `dt` | frame delta | Animation step used by `smooth` |

### `nimgui.empty(title, hint, opts)`

Draws an empty state: a title, an optional hint, and an optional action button. Returns `true` when the action button is pressed; otherwise returns `false`.

| Option | Default | Description |
|---|---|---|
| `action` | `nil` | Action button label |
| `action_role` | `secondary` | Button role |
| `action_width` | content width | Button width |
| `theme` | active theme | Theme override |

### `nimgui.tooltip(text)`

Shows a static tooltip. It does nothing when `text` is `nil` or an empty string.

### `nimgui.modal(id, title, draw_fn, opts)`

Draws an ImGui modal. `draw_fn` must be a function. Returns `is_open`.

| Option | Default | Description |
|---|---|---|
| `open` | `false` | Opens the popup on a `false` to `true` transition |
| `close_label` | `nil` | Label of a button that closes the popup |
| `close_width` | content width | Width of the close button |
| `flags` | `0` | `ImGuiWindowFlags` |
| `theme` | active theme | Theme override |

`open = false` does not close a popup that is already open.

```lua
nimgui.modal('reset', 'Reset settings?', function()
    imgui.TextUnformatted('All values return to their defaults.')
end, { open = reset_open, close_label = 'Cancel' })
```

### `nimgui.toast(text)`

Stores the active toast. Only one toast is alive at a time; a new text replaces the old one. `nimgui.render` draws the toast in the top-right corner after the panel callback. `reduce_motion` removes the fade and shortens the lifetime.

## Fonts

### `nimgui.fonts.setup(opts)`

Loads a base font for each named size and optionally merges one icon font. Call it in `OnInitialize`, before the first frame, and before the first `NewFrame`. It returns `true`, or `nil, err`.

| Option | Description |
|---|---|
| `base.path` | TTF path; required and must exist |
| `base.size` | Base size; defaults to `14` |
| `sizes` | Table of `name = size`; defaults to `{ body = base.size }` |
| `icons.path` | Icon TTF path; use this or `icons.data_base85` |
| `icons.data_base85` | Compressed Base85 icon font data |
| `icons.size` | Icon size; defaults to the primary size |
| `icons.codepoints` | Non-empty array of codepoints `1..0xFFFF` or UTF-8 strings |
| `dpi` | Size multiplier; defaults to `MONET_DPI_SCALE`, else `1.0` |

`body` becomes the primary size. If `body` is absent, the first name after sorting is primary. The icon font is merged only into the primary size, with `MergeMode`. The base range uses Cyrillic glyphs from the atlas when available, plus common punctuation. If the atlas is already built and `InvalidateFontsTexture` exists, `setup` calls it.

`setup` loads once. Later calls return `true` without reloading.

### `nimgui.fonts.ready()`

Returns `true` after `setup` has succeeded.

### `nimgui.fonts.push(name)` and `nimgui.fonts.pop()`

Pushes or pops a named font. `push` returns `true`, or `nil, err` when `setup` has not run or the name is unknown. `pop` returns `true`, or `nil, err` when `setup` has not run. Always pair `push` with `pop`.

```lua
if nimgui.fonts.push('display') then
    imgui.TextUnformatted('Title')
    nimgui.fonts.pop()
end
```

## Media

### Options

`load_file`, `load_bytes`, `anim`, `anim_bytes`, `anim_async`, and `anim_bytes_async` accept the same options table.

| Option | Default | Description |
|---|---|---|
| `width`, `height` | `nil` | Size used for statistics of non-GIF images |
| `max_frames` | `120` | Maximum GIF frame count |
| `max_atlas_pixels` | `2000000` | Maximum total atlas pixels |
| `max_dimension` | `4096` | Maximum atlas side length |
| `allow_scale` | `true` | `false` rejects an animation that exceeds the budget instead of downscaling it |

The GIF decoder also enforces a `4,000,000` pixel budget for the logical screen and each frame. This version does not forward a per-call override for that canvas budget through `nimgui.media`.

### `nimgui.media.load_file(path, opts)` and `nimgui.media.load_bytes(data, size, opts)`

Loads a static image. For a GIF, it uses the first frame. Returns a handle, or `nil, err`.

`load_bytes` requires `data` to be a string. `size` defaults to `#data` and must be in `1..#data`.

### Supported image formats

Non-GIF data goes to `mimgui.CreateTextureFromFileInMemory`, which uses stb_image 2.28 in the loader:

- JPEG baseline and progressive.
- PNG 1/2/4/8/16-bit per channel.
- TGA, BMP (non-1bpp, non-RLE), and PSD (composited view).
- HDR, PIC, and PNM (binary PPM/PGM).

GIF files are handled by `nimgui`'s own decoder; `load_file`/`load_bytes` use the first frame. All decoded images are converted to RGBA8888.

The format is detected from the data, not the file extension. WebP, SVG, AVIF, HEIC, and ICO are not supported. Animated GIFs go through `anim`, `anim_bytes`, `anim_async`, or `anim_bytes_async`.

### `nimgui.media.anim(path, opts)` and `nimgui.media.anim_bytes(data, size, opts)`

Loads a GIF as an animation. Returns a handle, or `nil, err`.

If decoding the animation or uploading the atlas fails, and the first frame fits the budget, the result is a static first-frame handle with `handle.animated == false` and the error in `handle.fallback`. If the first frame itself exceeds the budget, or the data is not a GIF, the function returns `nil, err`.

If the full atlas exceeds `max_atlas_pixels`, the decoder reduces the cell resolution until it fits. The handle keeps the logical `width`/`height` for layout, with `scale < 1` and smaller `cell_width`/`cell_height`. Set `allow_scale = false` for strict behavior: an animation that does not fit becomes a static fallback or `nil, err`.

A one-frame GIF is static (`animated == false`). A NETSCAPE loop value of `N` means `N` repeats after the first pass; `0` means unlimited.

### `nimgui.media.anim_async(path, opts)` and `nimgui.media.anim_bytes_async(data, size, opts)`

Opens and validates a GIF without decoding the whole animation. Returns a handle with `loading == true` and `tex == nil`, or `nil, err` when the header, data type, or initial budget is invalid. Options and downscale rules match `anim`/`anim_bytes`.

Call `nimgui.media.step_anim(handle, budget_ms)` until `handle.loading == false`. Decode is incremental, and the texture is uploaded once when the atlas is ready. Put the call in the `before` callback of `nimgui.render` so it runs before `renderer:NewFrame`:

```lua
nimgui.render(function() return open end, function()
    if anim ~= nil and anim.loading then
        nimgui.media.step_anim(anim, 8)
    end
end, draw_panel)
```

`draw_anim` also calls `step_anim` as a fallback while the handle is loading, but the `before` callback is preferred. `release` is safe while a handle is loading; the decoder is dropped without an upload.

### `nimgui.media.step_anim(handle, budget_ms)`

Continues an async decode. `budget_ms` defaults to `8` and is measured with `os.clock()`; values below `1` are raised to `1`.

Returns:

- `true` when the handle is loaded or already complete.
- `nil` while decoding is still in progress.
- `false, err` when decoding fails or the handle was released.

While decoding, `handle.progress` moves from `0` to `1`. On failure, `handle.failed == true` and `handle.error` contains the cause.

### `nimgui.media.image(handle, width, height, opts)`

Draws a static handle. `width` and `height` must be positive. `opts.tint` and `opts.border` are `ImVec4` values; the default tint is white and the default border is transparent. A released or broken handle is replaced by a placeholder. Returns nothing.

### `nimgui.media.draw_anim(handle, width, height, dt, opts)`

Draws an animation and advances its frame. `width` and `height` must be positive.

- `dt` is optional. The default is the frame `DeltaTime`, clamped to `0.1` seconds.
- `opts.budget` defaults to `8` and is passed to `step_anim` while the handle is loading. A progress placeholder is drawn during that time.
- Returns the frame index, or `nil` when a placeholder was used.
- A static handle is drawn through `image` and returns `1`.
- With `theme.active().reduce_motion`, the frame is locked to `1`.

Call it from a draw callback. It does not upload a texture unless the `step_anim` fallback runs.

### `nimgui.media.placeholder(width, height, opts)`

Draws a placeholder box with a label. `width` and `height` must be positive. `opts.label` defaults to `Gambar tidak tersedia`; `opts.theme` is optional. Returns nothing.

### `nimgui.media.release(handle)`

Releases the texture and removes the handle from statistics. It is idempotent: a second call returns `true`. It calls `ffi.gc(tex, nil)` before `ReleaseTexture` so the finalizer cannot destroy the texture twice. Returns `true`, or `false, err`.

### `nimgui.media.release_all()`

Releases every live handle. Returns the number released and the first error, or `nil` when there is no error.

### `nimgui.media.stats()`

Returns `textures`, `atlas_pixels`, `frames`, and `estimated_bytes` (`atlas_pixels * 4`). It counts uploaded handles; a handle that is still loading is not included until its texture is uploaded. A non-GIF image without `width`/`height` contributes `0` pixels.

### Handle fields

GIF handles expose `tex`, `width`, `height`, `atlas_width`, `atlas_height`, `atlas_pixels`, `cell_width`, `cell_height`, `scale`, `frame_count`, `frame_index`, `loop_count`, `frames`, `uv0`, `uv1`, `animated`, `fallback`, `loading`, `failed`, `error`, `progress`, and `released`.

Raw image handles expose `tex`, `width`, `height` (from the options), `atlas_width`, `atlas_height`, `atlas_pixels`, `frame_count`, `frame_index`, `loop_count`, `frames`, `uv0`, `uv1`, `animated`, `fallback`, `loading`, `failed`, `progress`, and `released`. `error` appears only after a failure.

Each entry in `frames` contains `delay` in seconds, plus `uv0` and `uv1`. For a raw image, `width`/`height` are `nil` when omitted from the options, and `atlas_pixels` is `0` without them.

## State binder

### `nimgui.state(table)`

Creates a binder for a state table. Most scripts can pass the plain table directly to widgets; the binder is useful when the `cdata` must be passed to an ImGui API.

The binder exposes:

| Method | Description |
|---|---|
| `int(key, default)` | Returns an integer proxy |
| `bool(key, default)` | Returns a boolean proxy |
| `float(key, default)` | Returns a float proxy |
| `get(key)` | Reads `state[key]` |
| `set(key, value)` | Writes `state[key]` |

`key` must be a string. A key is cached on first use; later calls return the same proxy.

Each proxy exposes:

| Method | Description |
|---|---|
| `get()` | Reads `state[key]` |
| `set(value)` | Writes `state[key]` |
| `commit()` | Writes the current `cdata` value to `state[key]` |
| `refresh()` | Reads `state[key]` into the `cdata` |
| `value()` | Returns the current `cdata` value |
| `cdata()` | Returns the underlying `cdata` |

```lua
local binder = nimgui.state(cfg)
local volume = binder:float('volume', 0.5)
imgui.SliderFloat('##volume', volume:cdata(), 0, 1)
cfg.volume = volume:value()
```

## Known limits

- `toggle` uses `InvisibleButton` and has no visible keyboard focus highlight. Use `checkbox` for keyboard navigation.
- `disabled_hint` on a button appears only on hover. On a touch device, show the reason as normal text.
- Dear ImGui 1.72 has no `BeginTable` or `BeginDisabled`; `nimgui` uses `Columns`, `BeginChild`, `Selectable`, and style pushes.
- Do not do IO, texture loading, font atlas rebuilds, or state allocation in a draw callback. Do it in `OnInitialize` or when state changes.
- The host `imgui.Text` and `SetTooltip` are variadic and have crashed on Android. `nimgui` uses `TextUnformatted` and `BeginTooltip`/`EndTooltip`.
- Only one toast can be active.
- The GIF canvas budget is fixed at `4,000,000` pixels in this version.
- Raw non-GIF images have no size query in `mimgui`; pass `width`/`height` when accurate `media.stats()` matters.

## Verification

The headless suites run with `luajit` and the fake `mimgui` binding:

| Suite | Checks |
|---|---|
| capability | 38 |
| fonts | 56 |
| gif | 51 |
| layout | 48 |
| media | 88 |
| polish | 13 |
| render | 15 |
| state | 18 |
| theme | 33 |
| widgets | 72 |
| **Total** | **432 checks, 0 failures** |

`tests/test_color.lua` adds 14 checks and `tests/test_motion.lua` adds 8, for 454 checks and 0 failures.

`luacheck --std lua51 dist/lib/nimgui/*.lua tests/fake_nimgui.lua tests/test_nimgui_*.lua tests/test_color.lua tests/test_motion.lua` reports 0 errors and 83 known warnings, mostly unused `self` arguments in `state.lua` and host globals used by the fake binding in the tests.

Not verified: Android rendering and interaction, DPI `1 / 1.5 / 2`, real touch targets, small screens, raster/VRAM limits, FPS with GIF playback, and reload/pause/terminate. Those remain `static review only` or `not verified`.
