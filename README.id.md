# nimgui

[![Lisensi: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Versi 0.1.0](https://img.shields.io/badge/version-0.1.0-informational.svg)](#status)
[![LuaJIT (Lua 5.1)](https://img.shields.io/badge/LuaJIT-Lua%205.1-2C2D72.svg)](#kebutuhan)
[![Platform: Android / MonetLoader](https://img.shields.io/badge/platform-Android%20%7C%20MonetLoader-3DDC84.svg)](#kebutuhan)
[![mimgui 2.0.1](https://img.shields.io/badge/mimgui-2.0.1-blueviolet.svg)](#kebutuhan)

[English](README.md) | [Bahasa Indonesia](README.id.md)

`nimgui` adalah library UI Lua untuk MonetLoader di Android. Library ini membungkus `mimgui` dan Dear ImGui 1.72 dengan tema, widget berukuran sentuh, layout panel, ukuran font, binding state, dan pemutar GIF animasi.

Library ini tidak mengubah `mimgui`, Dear ImGui, atau kode native loader. Repository ini tidak menyertakan MonetLoader atau `mimgui`; keduanya berasal dari distribusi loader.

## Status

Versi `0.1.0`. Suite headless lulus dengan 454 checks dan 0 failures (432 `nimgui`, 14 `color`, 8 `motion`).

Tampilan **belum** diverifikasi di perangkat Android. DPI, target sentuh nyata, VRAM, dan FPS belum diuji. Repository ini tidak punya workflow CI dan belum punya artefak rilis; jalankan test secara lokal.

## Fitur utama

- Lima arah tema: `instrument`, `dispatch`, `garage`, `graphite` (gelap), dan `paper` (terang).
- Spacing yang mengikuti skala dan target sentuh `44 * scale`, termasuk `FramePadding` tambahan untuk kontrol native ImGui.
- Panel berukuran tetap atau otomatis, diposisikan di tengah dengan `pos` dan `pivot`, tetap bisa digeser lewat area kosong.
- Widget: role tombol, segmented control, toggle, checkbox, slider, input integer/float/teks, stat tile, progress bar, empty state, tooltip, modal, dan toast.
- Binding state untuk tabel Lua biasa; `cdata` internal di-cache per key.
- Manajer font dengan ukuran bernama dan font ikon opsional yang digabung sekali, disiapkan di `OnInitialize`.
- Gambar statis dan GIF animasi: satu tekstur atlas per animasi, decode async, cek budget, downscale otomatis, dan release idempoten.
- Suite test headless dan script demo lengkap.

## Kebutuhan

| Kebutuhan | Versi | Catatan |
|---|---|---|
| MonetLoader | 3.8.0 | Target runtime; versi lain belum diuji |
| mimgui | 2.0.1 | Disertakan MonetLoader; tidak ada di repository ini |
| Dear ImGui | 1.72 | `IMGUI_VERSION_NUM 17200`; tidak ada `BeginTable` atau `BeginDisabled` |
| Lua | LuaJIT, sintaks Lua 5.1 | Memakai FFI LuaJIT; Lua 5.1 biasa bukan target |
| Android | - | UI untuk sentuh; perilaku device belum diverifikasi |

Tidak ada build step dan tidak ada dependensi Lua eksternal selain `mimgui`.

## Instalasi

1. Salin `dist/lib/nimgui/` ke folder `lib/` yang dipakai script MonetLoader, sehingga menjadi `lib/nimgui/`.
2. Salin `dist/lib/color.lua` dan `dist/lib/motion.lua` ke folder `lib/` yang sama. `nimgui` membutuhkan keduanya.
3. Pertahankan `lib/mimgui/` dari distribusi MonetLoader. `nimgui` tidak menyertakannya.
4. Letakkan script di folder script MonetLoader, lalu jalankan lewat loader.

```text
<folder script MonetLoader>/
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
│   └── mimgui/          # dari MonetLoader
└── script_kamu.lua
```

Demo lengkap ada di [`example/nimgui_demo.lua`](example/nimgui_demo.lua). Salin `example/nimgui_demo.gif` dan `example/nimgui_demo.png` ke samping script untuk melihat media animasi dan statis; tanpa file itu demo menampilkan placeholder.

## Mulai cepat

Panggil `nimgui.fonts.setup` sekali di `OnInitialize`, sebelum frame pertama. Buat tema sekali, lalu gambar panel dari `nimgui.render`.

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
        return -- tunggu ukuran layar yang valid
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
        nimgui.segmented({ 'Umum', 'Audio' }, cfg, 'tab')
        if cfg.tab == 1 then
            nimgui.checkbox('Aktif', cfg, 'enabled')
        else
            nimgui.toggle('##enabled', cfg, 'enabled')
        end
        if nimgui.button('primary', 'Simpan') then
            nimgui.toast('Pengaturan disimpan')
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

Ketik `/nimgui` di chat. Panel dengan lebar maksimal 440 px terbuka di tengah layar. Area kosong panel bisa dipakai untuk menggeser; tombol `Simpan` menampilkan toast. Kalau file font gagal dimuat, panel tetap terbuka dengan font default ImGui dan error-nya dicetak.

## Ukuran panel

`pos` memakai piksel layar absolut. `pivot` adalah rasio ukuran panel, jadi `{ 0.5, 0.5 }` memusatkan panel pada titik itu. `size` diterapkan dengan `FirstUseEver` secara default. Kalau frame pertama membaca resolusi nol atau resolusi saat layar masih loading, ukuran fallback itu terkunci.

Contoh mulai cepat menghindari masalah ini dengan dua cara:

- Berhenti sebelum `begin_panel` sampai `getScreenResolution()` melaporkan minimal `320x240`.
- Mengirim `size_cond = imgui.Cond.Always` agar ukuran eksplisit tetap benar di setiap frame.

Jangan sertakan `imgui.WindowFlags.NoMove` dan `anchored = true` kalau panel harus bisa digeser. `anchored = true` menerapkan posisi setiap frame, sehingga panel tidak bisa digeser.

## Konfigurasi

Sebagian besar pengaturan berupa tabel Lua yang dikirim ke entry point berikut. Default dan kasus khusus ada di [referensi API](docs/reference.id.md).

| Area | Entry point | Opsi utama |
|---|---|---|
| Tema | `nimgui.theme(spec, opts)` | `scale`, `radius`, `control_h`, `bg_alpha`, `reduce_motion` |
| Panel | `nimgui.begin_panel(id, opts)` | `theme`, `pos`, `pivot`, `size`, `size_cond`, `min`, `max`, `anchored`, `alpha`, `flags` |
| Font | `nimgui.fonts.setup(opts)` | `base`, `sizes`, `icons`, `dpi` |
| Media | `nimgui.media.*` | `max_frames`, `max_atlas_pixels`, `max_dimension`, `allow_scale`, `width`, `height` |
| Cleanup | `nimgui.shutdown()` | Melepas subscription dan handle media |

Tema dibuat sekali dan dikirim ke `begin_panel`. Tanpa tema, widget memakai fallback `graphite` pada skala layar saat ini.

```lua
local theme = nimgui.theme('paper', { reduce_motion = true })
```

## Media

Gambar statis non-GIF memakai `nimgui.media.load_file` dan `nimgui.media.image`. Loader men-decode lewat stb_image 2.28: JPEG, PNG, TGA, BMP, PSD, HDR, PIC, dan PNM. File GIF ditangani decoder `nimgui` sendiri; load statis memakai frame pertama. WebP, SVG, AVIF, HEIC, dan ICO tidak didukung.

```lua
local image = nimgui.media.load_file(getWorkingDirectory() .. '/foto.png', {
    width = 560,
    height = 315,
})
nimgui.media.image(image, 280, 158)
```

Untuk GIF animasi, muat dengan `anim_async` dan panggil `step_anim` dari callback `before` supaya frame panel pertama tidak tertahan:

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

`step_anim` men-decode per potongan dan mengunggah satu tekstur saat atlas siap. `draw_anim` menampilkan placeholder progres selama `handle.loading` bernilai true dan memajukan animasi pada handle. Kalau atlas melewati `max_atlas_pixels`, decoder memperkecil sel sampai muat (`handle.scale < 1`); kirim `allow_scale = false` untuk menolaknya.

Panggil `nimgui.media.release(handle)` saat mengganti gambar, atau `nimgui.shutdown()` saat script di-unload atau di-reload. Release bersifat idempoten.

## Struktur proyek

```text
.
├── dist/lib/
│   ├── nimgui/          # modul library
│   ├── color.lua        # helper palet yang dipakai nimgui
│   └── motion.lua       # helper motion yang dipakai nimgui
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

## Pengujian

Jalankan suite headless dari root repository:

```bash
for f in tests/test_*.lua; do luajit "$f"; done
```

Hasil saat ini: 454 checks, 0 failures (432 `nimgui`, 14 `color`, 8 `motion`).

Lint, kalau `luacheck` terpasang:

```bash
luacheck --std lua51 dist/lib/nimgui/*.lua tests/fake_nimgui.lua tests/test_nimgui_*.lua tests/test_color.lua tests/test_motion.lua
```

Hasil saat ini 0 error dan 83 warning yang sudah diketahui, sebagian besar berupa argumen `self` yang tidak dipakai di `state.lua` dan global host yang dipakai binding `mimgui` palsu di test.

Test memakai `tests/fake_nimgui.lua`, bukan renderer ImGui sungguhan. Test tidak memvalidasi rendering device, DPI, sentuh, VRAM, atau FPS.

## Kontribusi

Jalankan test dan lint sebelum mengirim perubahan. Jaga sintaks Lua 5.1 dan kompatibilitas LuaJIT: tanpa `goto`, `//`, operator bitwise native, `table.unpack`, `string.pack`, `_ENV`, `utf8`, atau `table.move`. Runtime-nya menyertakan FFI LuaJIT.

Jangan mengklaim verifikasi device tanpa menjalankan di device atau punya screenshot. Jaga perubahan tetap tercakup suite headless dan laporkan apa yang belum diverifikasi.

## Lisensi

MIT. Lihat [`LICENSE`](LICENSE). Copyright (c) 2026, Sena.
