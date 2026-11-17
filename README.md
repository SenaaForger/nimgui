# nimgui

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Version 0.1.0](https://img.shields.io/badge/version-0.1.0-informational.svg)](#status)
[![LuaJIT (Lua 5.1)](https://img.shields.io/badge/LuaJIT-Lua%205.1-2C2D72.svg)](#requirements)
[![Platform: Android / MonetLoader](https://img.shields.io/badge/platform-Android%20%7C%20MonetLoader-3DDC84.svg)](#requirements)
[![mimgui 2.0.1](https://img.shields.io/badge/mimgui-2.0.1-blueviolet.svg)](#requirements)

[English](README.md) | [Bahasa Indonesia](README.id.md)

`nimgui` is a Lua-only UI library for MonetLoader on Android. It wraps `mimgui` and Dear ImGui 1.72 with themes, touch-sized widgets, panel layout, font sizes, state binding, and animated GIF playback.

The library does not modify `mimgui`, Dear ImGui, or native loader code. This repository does not include MonetLoader or `mimgui`; both come from the loader distribution.

## Status

Version `0.1.0`. The headless suite passes with 454 checks and 0 failures (432 `nimgui`, 14 `color`, 8 `motion`).

The interface has **not** been verified on an Android device. DPI, real touch targets, VRAM, and FPS remain untested. This repository has no CI workflow and no release artifacts; run the tests locally.

## Key features

- Five theme directions: `instrument`, `dispatch`, `garage`, `graphite` (dark), and `paper` (light).
- Scale-aware spacing and a `44 * scale` touch target, including extra `FramePadding` for native ImGui controls.
- Fixed or auto-sized panels, centered with `pos` and `pivot`, still draggable through empty areas.
- Widgets: button roles, segmented control, toggle, checkbox, slider, integer/float/text inputs, stat tile, progress bar, empty state, tooltip, modal, and toast.
- State binding for plain Lua tables; internal `cdata` is cached per key.
- Font manager with named sizes and an optional merged icon font, set up once in `OnInitialize`.
- Static images and animated GIFs: one atlas texture per animation, async decode, budget checks, automatic downscale, and idempotent release.
- Headless test suite and a complete demo script.

## Requirements

| Requirement | Version | Notes |
|---|---|---|
| MonetLoader | 3.8.0 | Target runtime; other versions are not tested |
| mimgui | 2.0.1 | Included with MonetLoader; not in this repository |
| Dear ImGui | 1.72 | `IMGUI_VERSION_NUM 17200`; no `BeginTable` or `BeginDisabled` |
| Lua | LuaJIT, Lua 5.1 syntax | Uses the LuaJIT FFI; plain Lua 5.1 is not a target |
| Android | - | Touch-first UI; device behavior is unverified |

There is no build step and no external Lua dependency beyond `mimgui`.

## Installation

1. Copy `dist/lib/nimgui/` into the `lib/` folder used by your MonetLoader scripts, so the result is `lib/nimgui/`.
2. Copy `dist/lib/color.lua` and `dist/lib/motion.lua` into the same `lib/` folder. `nimgui` requires both.
3. Keep `lib/mimgui/` from the MonetLoader distribution. `nimgui` does not ship it.
4. Put your script in the MonetLoader script folder and run it through the loader.

```text
<MonetLoader script folder>/
├── lib/
│   ├── nimgui/
│   │   ├── init.lua
│   │   ├── theme.lua
│   │   ├── state.lua
│   │   ├── layout.lua
│   │   ├── widgets.lua
│   │   ├── fonts.lua
│   │   ├── media.lua
│   │   └── gif.lua
│   ├── color.lua
│   ├── motion.lua
│   └── mimgui/          # from MonetLoader
└── your_script.lua
```

The full demo is in [`example/nimgui_demo.lua`](example/nimgui_demo.lua). Copy `example/nimgui_demo.gif` and `example/nimgui_demo.png` next to the script to see animated and static media; without them the demo shows placeholders.

## Quick start

Call `nimgui.fonts.setup` once in `OnInitialize`, before the first frame. Create the theme once, then draw the panel from `nimgui.render`.

```lua
local imgui = require 'mimgui'
local nimgui = require 'nimgui'

local open = false
local theme
local cfg = { tab = 1, enabled = true }

imgui.OnInitialize(function()
    theme = nimgui.theme('instrument')
    local ok, err = nimgui.fonts.setup({
        base = { path = getWorkingDirectory() .. '/lib/mimgui/trebucbd.ttf', size = 14 },
        sizes = { body = 14, label = 11, display = 20 },
    })
    if not ok then
        print('nimgui fonts: ' .. tostring(err))
    end
end)

nimgui.render(function() return open end, function()
    local screen_w, screen_h = getScreenResolution()
    if screen_w < 320 or screen_h < 240 then
        return -- wait for a usable display size
    end

    local panel_w = math.min(440, screen_w - 32)
    local panel_h = math.min(screen_h - 32, math.floor(250 + 340 * nimgui.scale()))

    local visible = nimgui.begin_panel('##demo', {
        theme = theme,
        pos = { screen_w / 2, screen_h / 2 },
        pivot = { 0.5, 0.5 },
        size = { panel_w, panel_h },
        size_cond = imgui.Cond.Always,
        flags = imgui.WindowFlags.NoTitleBar
            + imgui.WindowFlags.NoResize
            + imgui.WindowFlags.NoSavedSettings,
    })

    if visible then
        nimgui.segmented({ 'General', 'Audio' }, cfg, 'tab')
        if cfg.tab == 1 then
            nimgui.checkbox('Enabled', cfg, 'enabled')
        else
            nimgui.toggle('##enabled', cfg, 'enabled')
        end
        if nimgui.button('primary', 'Save') then
            nimgui.toast('Settings saved')
        end
    end

    nimgui.end_panel()
end)

function main()
    sampRegisterChatCommand('nimgui', function()
        open = not open
    end)
    while true do
        wait(0)
    end
end
```

Type `/nimgui` in chat. A panel up to 440 px wide opens in the center of the screen. Empty areas of the panel drag it; `Save` shows a toast. If the font file cannot be loaded, the panel still opens with the ImGui default font and the error is printed.

## Panel sizing

`pos` uses absolute screen pixels. `pivot` is a ratio of the panel size, so `{ 0.5, 0.5 }` centers the panel on that point. `size` is applied with `FirstUseEver` by default. If the first frame reports a zero or loading-screen resolution, that fallback size is locked in.

The quick start avoids this in two ways:

- It returns before `begin_panel` until `getScreenResolution()` reports at least `320x240`.
- It passes `size_cond = imgui.Cond.Always` so the explicit size stays correct on every frame.

Leave out `imgui.WindowFlags.NoMove` and `anchored = true` when the panel must be draggable. `anchored = true` re-applies the position every frame, which prevents dragging.

## Configuration

Most settings are Lua tables passed to the entry points below. Defaults and edge cases are in the [API reference](docs/reference.md).

| Area | Entry point | Main options |
|---|---|---|
| Theme | `nimgui.theme(spec, opts)` | `scale`, `radius`, `control_h`, `bg_alpha`, `reduce_motion` |
| Panel | `nimgui.begin_panel(id, opts)` | `theme`, `pos`, `pivot`, `size`, `size_cond`, `min`, `max`, `anchored`, `alpha`, `flags` |
| Fonts | `nimgui.fonts.setup(opts)` | `base`, `sizes`, `icons`, `dpi` |
| Media | `nimgui.media.*` | `max_frames`, `max_atlas_pixels`, `max_dimension`, `allow_scale`, `width`, `height` |
| Cleanup | `nimgui.shutdown()` | Releases subscriptions and media handles |

A theme is created once and passed to `begin_panel`. Without it, widgets use the `graphite` fallback at the current screen scale.

```lua
local theme = nimgui.theme('paper', { reduce_motion = true })
```

## Media

Static non-GIF images use `nimgui.media.load_file` and `nimgui.media.image`. The loader decodes through stb_image 2.28: JPEG, PNG, TGA, BMP, PSD, HDR, PIC, and PNM. GIF files are handled by `nimgui`'s own decoder; a static load uses the first frame. WebP, SVG, AVIF, HEIC, and ICO are not supported.

```lua
local image = nimgui.media.load_file(getWorkingDirectory() .. '/photo.png', {
    width = 560,
    height = 315,
})
nimgui.media.image(image, 280, 158)
```

For an animated GIF, load with `anim_async` and call `step_anim` from the `before` callback so the first panel frame is not blocked:

```lua
local anim

imgui.OnInitialize(function()
    local path = getWorkingDirectory() .. '/nimgui_demo.gif'
    if doesFileExist(path) then
        anim = nimgui.media.anim_async(path)
    end
end)

nimgui.render(function() return open end, function()
    if anim ~= nil and anim.loading then
        nimgui.media.step_anim(anim, 8)
    end
end, function()
    nimgui.begin_panel('##media')
    local width = imgui.GetContentRegionAvail().x
    nimgui.media.draw_anim(anim, width, math.floor(width * 9 / 16), nil, { budget = 8 })
    nimgui.end_panel()
end)
```

`step_anim` decodes in slices and uploads one texture when the atlas is ready. `draw_anim` shows a progress placeholder while `handle.loading` is true and advances the animation on the handle. If the atlas exceeds `max_atlas_pixels`, the decoder downscales cells until it fits (`handle.scale < 1`); pass `allow_scale = false` to reject it instead.

Call `nimgui.media.release(handle)` when you replace an image, or `nimgui.shutdown()` when the script is unloaded or reloaded. Release is idempotent.

## Project structure

```text
.
├── dist/lib/
│   ├── nimgui/          # library modules
│   ├── color.lua        # palette helpers used by nimgui
│   └── motion.lua       # motion helpers used by nimgui
├── docs/
│   ├── reference.md
│   └── reference.id.md
├── example/
│   ├── nimgui_demo.lua
│   ├── nimgui_demo.gif
│   └── nimgui_demo.png
├── tests/
├── LICENSE
├── README.md
└── README.id.md
```

## Testing

Run the headless suites from the repository root:

```bash
for f in tests/test_*.lua; do luajit "$f"; done
```

Current result: 454 checks, 0 failures (432 `nimgui`, 14 `color`, 8 `motion`).

Lint, if `luacheck` is installed:

```bash
luacheck --std lua51 dist/lib/nimgui/*.lua tests/fake_nimgui.lua tests/test_nimgui_*.lua tests/test_color.lua tests/test_motion.lua
```

The current result is 0 errors and 83 known warnings, mostly unused `self` arguments in `state.lua` and host globals used by the fake `mimgui` binding in the tests.

The tests use `tests/fake_nimgui.lua`, not a real ImGui renderer. They do not validate device rendering, DPI, touch, VRAM, or FPS.

## Contributing

Run the tests and lint before sending a change. Keep Lua 5.1 syntax and LuaJIT compatibility: no `goto`, `//`, native bitwise operators, `table.unpack`, `string.pack`, `_ENV`, `utf8`, or `table.move`. The runtime includes the LuaJIT FFI.

Do not claim device verification without a device run or screenshot. Keep changes covered by the headless suites and report what was not verified.

## License

MIT. See [`LICENSE`](LICENSE). Copyright (c) 2026, Sena.
