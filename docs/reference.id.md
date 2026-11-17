# Referensi API nimgui

[English](reference.md) | [Bahasa Indonesia](reference.id.md)

Halaman ini mendokumentasikan kontrak publik `nimgui` versi `0.1.0`. Muat facade dengan `require 'nimgui'`. Modul di bawah `nimgui.*` adalah detail implementasi kecuali halaman ini menyebutnya. Untuk instalasi dan script pertama, lihat [README](../README.id.md).

## Siklus hidup

### `nimgui.render(cond, draw)` dan `nimgui.render(cond, before, draw)`

Mendaftarkan panel ke `mimgui.OnFrame`.

- `cond` adalah fungsi yang mengembalikan `true` selama panel harus digambar.
- `before` adalah fungsi opsional yang berjalan sebelum frame dimulai.
- `draw` adalah fungsi yang menggambar isi panel.
- Kalau `draw` melempar error, `nimgui` mereset stack layout dan tema, lalu melempar ulang error itu.
- Toast aktif digambar otomatis setelah `draw`.

Mengembalikan objek subscription `mimgui`.

```lua
nimgui.render(function() return open end, function()
    nimgui.begin_panel('##panel')
    -- isi panel
    nimgui.end_panel()
end)
```

### `nimgui.shutdown()`

Melepas semua subscription `render`, menjalankan shutdown handler, mereset state layout dan widget, melepas semua handle media yang masih hidup, dan mengosongkan stack tema. Aman dipanggil lebih dari sekali.

Mengembalikan `true`, atau `false, err` kalau ada pelepasan atau unsubscribe yang gagal.

```lua
nimgui.add_shutdown_handler(function()
    nimgui.media.release(avatar)
end)
```

### `nimgui.add_shutdown_handler(fn)`

Menambahkan fungsi yang dipanggil oleh `shutdown()`. Handler berjalan dengan urutan kebalikan dari pendaftaran. Error di satu handler tidak menghentikan handler lain; `shutdown()` mengembalikan error pertama.

### `nimgui.capabilities()`

Mengembalikan salinan probe boolean untuk fitur `mimgui` dan global host. Hasilnya di-cache setelah panggilan pertama.

| Grup | Key |
|---|---|
| Drawing dan layout | `draw_list`, `add_image`, `invisible_button`, `get_cursor_screen_pos`, `same_line`, `imvec2`, `imvec4`, `style`, `style_colors` |
| Wrapper nilai | `new_int`, `new_bool`, `new_float` |
| Font | `font_atlas`, `font_rebuild`, `push_font` |
| Tekstur | `texture_file`, `texture_memory`, `release_texture` |
| Widget | `time`, `input_text`, `slider_float`, `combo`, `selectable`, `popup_modal`, `tooltip` |
| Global host | `dpi_scale`, `working_directory`, `file_exists`, `screen_resolution`, `event_handler` |

Sebuah key bernilai `true` hanya kalau binding atau global-nya ada. Contoh: `texture_memory` bernilai `true` kalau `mimgui.CreateTextureFromFileInMemory` tersedia.

## Tema dan skala

### `nimgui.theme(spec, opts)`

Membuat objek tema. `spec` adalah nama arah bawaan atau tabel dengan field arah kustom.

| Arah | Mode |
|---|---|
| `instrument` | gelap |
| `dispatch` | gelap |
| `garage` | gelap |
| `graphite` | gelap |
| `paper` | terang |

Tabel arah kustom memakai `hue`, `tint`, `accentHue`, `accentSat`, dan `accentLight`. Tambahkan `mode = 'light'` untuk palet terang.

`opts`:

| Opsi | Default | Keterangan |
|---|---|---|
| `scale` | `nimgui.scale()` | Pengali ukuran, radius, dan spacing |
| `radius` | `4 * scale` | Radius sudut |
| `control_h` | `44 * scale` | Tinggi target sentuh |
| `bg_alpha` | `248` | Alpha latar panel (`0..255`) |
| `reduce_motion` | `false` | Mematikan animasi dekoratif |

`radius` dan `control_h` dikali `scale` setelah dibaca dari `opts`.

Objek tema yang dihasilkan punya field:

| Field | Keterangan |
|---|---|
| `mode` | `'dark'` atau `'light'` |
| `scale` | Pengali skala |
| `radius` | Radius sudut dalam piksel |
| `control_h` | Tinggi kontrol dalam piksel |
| `reduce_motion` | Boolean |
| `raw` | Palet sebagai integer `0xRRGGBB` |
| `color` | Palet sebagai nilai `IM_COL32` |
| `sp(name)` | Token spacing dalam piksel |

Token spacing dikali `scale`: `xs` 4, `sm` 8, `md` 12, `lg` 16, `xl` 24, `xxl` 32.

```lua
local theme = nimgui.theme('instrument', { reduce_motion = true })
local gap = theme.sp('md')
```

Kirim tema ke `begin_panel` lewat `opts.theme`. Tanpa tema aktif, widget memakai fallback `graphite` pada skala layar saat ini.

### `nimgui.scale()`

Mengembalikan `MONET_DPI_SCALE` kalau nilainya angka positif. Kalau tidak, skala diturunkan dari tinggi layar (`height / 720`) dan dijepit ke `1.0..2.0`. Kalau tidak ada sumber yang tersedia, hasilnya `1.0`.

## Layout

### `nimgui.begin_panel(id, opts)`

Membuka panel dan mendorong temanya. Mengembalikan nilai `visible` dari `imgui.Begin`. Selalu panggil `nimgui.end_panel()`, termasuk saat `visible` bernilai `false`.

| Opsi | Tipe | Default | Keterangan |
|---|---|---|---|
| `theme` | tabel | tema aktif | Tema yang didorong untuk panel ini |
| `pos` | `{x,y}` atau `ImVec2` | `nil` | Posisi jendela dalam piksel layar, bukan rasio `0..1` |
| `pivot` | `{x,y}` atau `ImVec2` | `{0,0}` | Pivot `pos` sebagai rasio ukuran jendela (`0..1`) |
| `size` | `{x,y}` atau `ImVec2` | `nil` | Ukuran jendela |
| `size_cond` | angka | `Always` saat `anchored`, selain itu `FirstUseEver` | Kondisi penerapan `size` |
| `min`, `max` | `{x,y}` atau `ImVec2` | `nil` | Batas ukuran |
| `anchored` | boolean | `false` | Menerapkan `pos` setiap frame, sehingga panel tidak bisa digeser |
| `alpha` | angka | `nil` | Alpha panel; didorong hanya kalau nilainya di bawah `1` |
| `open` | boolean | `nil` | Status buka/tutup yang diteruskan ke `imgui.Begin` |
| `flags` | angka | `0` | `ImGuiWindowFlags` |

Kalau `opts.theme` tidak ada dan belum ada tema aktif, panel mendorong tema fallback. Panel bersarang mempertahankan tema yang sedang aktif.

Untuk memusatkan panel:

```lua
local screen_w, screen_h = getScreenResolution()
nimgui.begin_panel('##panel', {
    pos = { screen_w / 2, screen_h / 2 },
    pivot = { 0.5, 0.5 },
    flags = imgui.WindowFlags.NoTitleBar,
})
```

`pos` memakai piksel layar. `pivot` memakai rasio ukuran jendela. Jangan sertakan `imgui.WindowFlags.NoMove` dan `anchored = true` kalau panel harus bisa digeser. Tanpa `NoMove`, area kosong panel bisa dipakai untuk menggeser.

`size` dengan `FirstUseEver` hanya diterapkan sekali. Kalau `getScreenResolution()` mengembalikan `0` atau ukuran layar loading pada frame pertama, panel bisa terkunci pada fallback itu. Tunggu resolusi yang valid sebelum memanggil `begin_panel`, dan pakai `size_cond = imgui.Cond.Always` untuk panel berukuran tetap.

### `nimgui.end_panel()`

Menutup panel dan mengembalikan tema serta alpha yang didorong oleh `begin_panel`. Mengembalikan `true`, atau `false, err` kalau tidak ada panel yang cocok.

### `nimgui.begin_child(id, size, border)` dan `nimgui.end_child()`

Membuka dan menutup child window. `size` boleh `nil` (memakai `0,0`); `border` boolean. Selalu pasangkan panggilannya, termasuk saat child tidak terlihat. `end_child()` mengembalikan `true`, atau `false, err` kalau tidak ada child yang cocok.

### `nimgui.spacer(size)`

Menambah ruang vertikal. Default-nya `theme.active().sp('md')`. `size` harus angka.

### `nimgui.same_line(offset)`

Memanggil `imgui.SameLine`. `offset` default `0`.

### `nimgui.separator()`

Memanggil `imgui.Separator`.

### `nimgui.grid_columns(avail_x, cell_w, gap)`

Mengembalikan jumlah kolom yang muat dalam `avail_x`. `gap` default `8`. Hasilnya minimal `1`.

```lua
local columns = nimgui.grid_columns(avail_width, 96, 8)
```

Rumusnya `floor((avail_x + gap) / (cell_w + gap))`. `avail_x` dan `cell_w` harus angka positif.

### `nimgui.truncate(text, max_width)`

Memotong `text` dan menambahkan `...` agar muat dalam `max_width`. Fungsi ini tidak memotong karakter UTF-8. Kalau `max_width` bukan angka positif, teks asli dikembalikan. Kalau `...` saja tidak muat, hasilnya `...`.

### `nimgui.footer_height()`

Mengembalikan `control_h + sp('md')`, berguna untuk menyisakan ruang bagi baris tombol di bawah.

## Widget

Widget yang menerima `state` boleh memakai tabel biasa atau binder dari `nimgui.state`. Widget memuat ulang binder dari `state[key]` sebelum menggambar, jadi perubahan dari kode luar terlihat pada frame berikutnya. `cdata` di-cache per tabel dan key.

### `nimgui.button(role, label, opts)`

Menggambar tombol. `role` adalah `primary`, `secondary`, `danger`, atau `ghost`. Mengembalikan `true` saat ditekan.

| Opsi | Default | Keterangan |
|---|---|---|
| `width` | lebar konten | Lebar tombol; nilai negatif juga berarti lebar konten |
| `height` | `control_h` | Tinggi tombol |
| `theme` | tema aktif | Override tema |
| `disabled` | `false` | Digambar dengan alpha `0.45` dan mengembalikan `false` |
| `disabled_hint` | `nil` | Teks tooltip yang hanya muncul saat hover |

`disabled_hint` hanya muncul saat hover. Di layar sentuh, taruh informasi penting di teks biasa.

### `nimgui.segmented(items, state, key, dt)`

Menggambar deretan tombol pilihan. `items` berisi string atau tabel dengan field `label`. `state[key]` adalah indeks 1-based; nilai tidak valid jatuh ke `1`. Fungsi menulis indeks terpilih ke `state[key]` dan mengembalikannya.

`dt` opsional. Dengan `reduce_motion`, pilihan berubah tanpa animasi.

### `nimgui.toggle(id, state, key, dt)`

Menggambar toggle sentuh. `id` harus stabil dan unik. Mengembalikan boolean.

Kalau binding draw-list yang dibutuhkan tidak tersedia, widget jatuh ke `imgui.Checkbox`. Karena jalur normal memakai `InvisibleButton`, toggle tidak punya highlight fokus keyboard yang terlihat. Pakai `nimgui.checkbox` kalau navigasi keyboard penting.

### `nimgui.checkbox(label, state, key)`

Menggambar checkbox ImGui dengan padding vertikal tambahan agar mencapai `control_h` (`44 * scale`). Mengembalikan boolean.

### `nimgui.slider(label, state, key, min, max)`

Menggambar slider float dengan label di atas kontrol. `min` dan `max` harus angka. Format nilainya `%.2f`. Mengembalikan nilai saat ini.

Label yang terlihat terpisah dari ID ImGui, yang diturunkan dari `key`. Dua slider dengan label berbeda tetapi key sama akan berbagi ID.

### `nimgui.input_int(label, state, key, step, step_fast)`

Menggambar input integer dengan label di atas kontrol. `step` default `1`; `step_fast` default `100`. Mengembalikan nilai saat ini.

### `nimgui.input_float(label, state, key, step, step_fast)`

Menggambar input float dengan label di atas kontrol. `step` default `0.1`; `step_fast` default `1.0`. Formatnya `%.3f`. Mengembalikan nilai saat ini.

### `nimgui.input_text(label, state, key, max_len)`

Menggambar input teks dengan label di atas kontrol. `max_len` default `64`. Buffer internal dipakai ulang dan diperbesar saat `max_len` naik. Mengembalikan string saat ini.

### `nimgui.stat_tile(label, value, opts)`

Menggambar kotak statistik dengan label kecil dan nilai besar. Tidak mengembalikan nilai.

| Opsi | Default | Keterangan |
|---|---|---|
| `width` | lebar konten | Lebar kotak |
| `height` | `64 * scale` | Tinggi kotak |
| `id` | `label` | ID child window |
| `border` | `true` | Menggambar border |
| `theme` | tema aktif | Override tema |

### `nimgui.progress(value, opts)`

Menggambar progress bar. `value` dijepit ke `0..1`. Mengembalikan fraksi yang benar-benar digambar.

| Opsi | Default | Keterangan |
|---|---|---|
| `width` | `-1` | Lebar bar; `-1` mengisi area konten |
| `height` | `6 * scale` | Tinggi bar |
| `overlay` | `''` | Teks yang digambar di atas bar |
| `color` | accent | Warna bar sebagai `IM_COL32` |
| `theme` | tema aktif | Override tema |
| `smooth` | `false` | Menganimasikan bar menuju `value` |
| `id` | `##nimgui_progress` | ID tracker yang dipakai `smooth` |
| `dt` | delta frame | Langkah animasi yang dipakai `smooth` |

### `nimgui.empty(title, hint, opts)`

Menggambar empty state: judul, hint opsional, dan tombol aksi opsional. Mengembalikan `true` saat tombol aksi ditekan; selain itu `false`.

| Opsi | Default | Keterangan |
|---|---|---|
| `action` | `nil` | Label tombol aksi |
| `action_role` | `secondary` | Role tombol |
| `action_width` | lebar konten | Lebar tombol |
| `theme` | tema aktif | Override tema |

### `nimgui.tooltip(text)`

Menampilkan tooltip statis. Tidak melakukan apa pun kalau `text` bernilai `nil` atau string kosong.

### `nimgui.modal(id, title, draw_fn, opts)`

Menggambar modal ImGui. `draw_fn` harus fungsi. Mengembalikan `is_open`.

| Opsi | Default | Keterangan |
|---|---|---|
| `open` | `false` | Membuka popup saat transisi `false` ke `true` |
| `close_label` | `nil` | Label tombol yang menutup popup |
| `close_width` | lebar konten | Lebar tombol tutup |
| `flags` | `0` | `ImGuiWindowFlags` |
| `theme` | tema aktif | Override tema |

`open = false` tidak menutup popup yang sedang terbuka.

```lua
nimgui.modal('reset', 'Reset pengaturan?', function()
    imgui.TextUnformatted('Semua nilai kembali ke default.')
end, { open = reset_open, close_label = 'Batal' })
```

### `nimgui.toast(text)`

Menyimpan toast aktif. Hanya satu toast yang hidup; teks baru menggantikan teks lama. `nimgui.render` menggambar toast di pojok kanan atas setelah callback panel. `reduce_motion` menghapus fade dan memperpendek masa hidupnya.

## Font

### `nimgui.fonts.setup(opts)`

Memuat font dasar untuk setiap ukuran bernama dan opsional menggabungkan satu font ikon. Panggil di `OnInitialize`, sebelum frame pertama, dan sebelum `NewFrame` pertama. Mengembalikan `true`, atau `nil, err`.

| Opsi | Keterangan |
|---|---|
| `base.path` | Path TTF; wajib dan harus ada |
| `base.size` | Ukuran dasar; default `14` |
| `sizes` | Tabel `name = size`; default `{ body = base.size }` |
| `icons.path` | Path TTF ikon; pakai ini atau `icons.data_base85` |
| `icons.data_base85` | Data font ikon Base85 terkompresi |
| `icons.size` | Ukuran ikon; default ukuran primary |
| `icons.codepoints` | Array non-kosong berisi codepoint `1..0xFFFF` atau string UTF-8 |
| `dpi` | Pengali ukuran; default `MONET_DPI_SCALE`, selain itu `1.0` |

`body` menjadi ukuran primary. Kalau `body` tidak ada, nama pertama setelah diurutkan menjadi primary. Font ikon digabung hanya ke ukuran primary dengan `MergeMode`. Rentang dasar memakai glyph Cyrillic dari atlas kalau tersedia, ditambah tanda baca umum. Kalau atlas sudah dibangun dan `InvalidateFontsTexture` tersedia, `setup` memanggilnya.

`setup` hanya memuat sekali. Panggilan berikutnya mengembalikan `true` tanpa memuat ulang.

### `nimgui.fonts.ready()`

Mengembalikan `true` setelah `setup` berhasil.

### `nimgui.fonts.push(name)` dan `nimgui.fonts.pop()`

Mendorong atau mengeluarkan font bernama. `push` mengembalikan `true`, atau `nil, err` kalau `setup` belum berjalan atau nama tidak dikenal. `pop` mengembalikan `true`, atau `nil, err` kalau `setup` belum berjalan. Selalu pasangkan `push` dengan `pop`.

```lua
if nimgui.fonts.push('display') then
    imgui.TextUnformatted('Judul')
    nimgui.fonts.pop()
end
```

## Media

### Opsi

`load_file`, `load_bytes`, `anim`, `anim_bytes`, `anim_async`, dan `anim_bytes_async` menerima tabel opsi yang sama.

| Opsi | Default | Keterangan |
|---|---|---|
| `width`, `height` | `nil` | Ukuran untuk statistik gambar non-GIF |
| `max_frames` | `120` | Jumlah frame GIF maksimum |
| `max_atlas_pixels` | `2000000` | Total piksel atlas maksimum |
| `max_dimension` | `4096` | Panjang sisi atlas maksimum |
| `allow_scale` | `true` | `false` menolak animasi yang melewati budget, bukan memperkecilnya |

Decoder GIF juga menerapkan budget `4.000.000` piksel untuk layar logis dan setiap frame. Versi ini tidak meneruskan override budget canvas per panggilan lewat `nimgui.media`.

### `nimgui.media.load_file(path, opts)` dan `nimgui.media.load_bytes(data, size, opts)`

Memuat gambar statis. Untuk GIF, frame pertama yang dipakai. Mengembalikan handle, atau `nil, err`.

`load_bytes` membutuhkan `data` berupa string. `size` default `#data` dan harus berada di `1..#data`.

### Format gambar yang didukung

Data non-GIF diteruskan ke `mimgui.CreateTextureFromFileInMemory`, yang memakai stb_image 2.28 di loader:

- JPEG baseline dan progressive.
- PNG 1/2/4/8/16-bit per channel.
- TGA, BMP (non-1bpp, non-RLE), dan PSD (composited view).
- HDR, PIC, dan PNM (PPM/PGM biner).

File GIF ditangani decoder `nimgui` sendiri; `load_file`/`load_bytes` memakai frame pertama. Semua gambar hasil decode dikonversi ke RGBA8888.

Format dideteksi dari isi data, bukan ekstensi file. WebP, SVG, AVIF, HEIC, dan ICO tidak didukung. GIF animasi lewat `anim`, `anim_bytes`, `anim_async`, atau `anim_bytes_async`.

### `nimgui.media.anim(path, opts)` dan `nimgui.media.anim_bytes(data, size, opts)`

Memuat GIF sebagai animasi. Mengembalikan handle, atau `nil, err`.

Kalau decode animasi atau upload atlas gagal, dan frame pertama masih muat di budget, hasilnya handle statis frame pertama dengan `handle.animated == false` dan error di `handle.fallback`. Kalau frame pertama sendiri melewati budget, atau data bukan GIF, fungsi mengembalikan `nil, err`.

Kalau atlas penuh melewati `max_atlas_pixels`, decoder memperkecil resolusi sel sampai muat. Handle tetap memakai `width`/`height` logis untuk layout, dengan `scale < 1` dan `cell_width`/`cell_height` yang lebih kecil. Set `allow_scale = false` untuk perilaku ketat: animasi yang tidak muat menjadi fallback statis atau `nil, err`.

GIF satu frame bersifat statis (`animated == false`). Nilai loop NETSCAPE `N` berarti `N` pengulangan setelah putaran pertama; `0` berarti tanpa batas.

### `nimgui.media.anim_async(path, opts)` dan `nimgui.media.anim_bytes_async(data, size, opts)`

Membuka dan memvalidasi GIF tanpa men-decode seluruh animasi. Mengembalikan handle dengan `loading == true` dan `tex == nil`, atau `nil, err` kalau header, tipe data, atau budget awal tidak valid. Opsi dan aturan downscale sama dengan `anim`/`anim_bytes`.

Panggil `nimgui.media.step_anim(handle, budget_ms)` sampai `handle.loading == false`. Decode berjalan bertahap, dan tekstur diunggah sekali saat atlas siap. Letakkan panggilan di callback `before` milik `nimgui.render` supaya berjalan sebelum `renderer:NewFrame`:

```lua
nimgui.render(function() return open end, function()
    if anim ~= nil and anim.loading then
        nimgui.media.step_anim(anim, 8)
    end
end, draw_panel)
```

`draw_anim` juga memanggil `step_anim` sebagai fallback selama handle masih dimuat, tetapi callback `before` lebih disarankan. `release` aman dipanggil saat handle masih dimuat; decoder dibuang tanpa upload.

### `nimgui.media.step_anim(handle, budget_ms)`

Melanjutkan decode async. `budget_ms` default `8` dan dihitung dengan `os.clock()`; nilai di bawah `1` dinaikkan ke `1`.

Mengembalikan:

- `true` saat handle selesai dimuat atau sudah selesai.
- `nil` selama decode masih berjalan.
- `false, err` saat decode gagal atau handle sudah dilepas.

Selama decode, `handle.progress` bergerak dari `0` ke `1`. Kalau gagal, `handle.failed == true` dan `handle.error` berisi penyebabnya.

### `nimgui.media.image(handle, width, height, opts)`

Menggambar handle statis. `width` dan `height` harus positif. `opts.tint` dan `opts.border` adalah `ImVec4`; tint default putih dan border default transparan. Handle yang sudah dilepas atau rusak diganti placeholder. Tidak mengembalikan nilai.

### `nimgui.media.draw_anim(handle, width, height, dt, opts)`

Menggambar animasi dan memajukan frame. `width` dan `height` harus positif.

- `dt` opsional. Default-nya `DeltaTime` frame, dijepit ke `0.1` detik.
- `opts.budget` default `8` dan diteruskan ke `step_anim` selama handle masih dimuat. Placeholder progres digambar selama itu.
- Mengembalikan indeks frame, atau `nil` kalau placeholder dipakai.
- Handle statis digambar lewat `image` dan mengembalikan `1`.
- Saat `theme.active().reduce_motion` aktif, frame dikunci ke `1`.

Panggil dari callback draw. Fungsi ini tidak mengunggah tekstur kecuali fallback `step_anim` berjalan.

### `nimgui.media.placeholder(width, height, opts)`

Menggambar kotak placeholder dengan label. `width` dan `height` harus positif. `opts.label` default `Gambar tidak tersedia`; `opts.theme` opsional. Tidak mengembalikan nilai.

### `nimgui.media.release(handle)`

Melepas tekstur dan menghapus handle dari statistik. Idempoten: panggilan kedua mengembalikan `true`. Fungsi memanggil `ffi.gc(tex, nil)` sebelum `ReleaseTexture` agar finalizer tidak menghancurkan tekstur dua kali. Mengembalikan `true`, atau `false, err`.

### `nimgui.media.release_all()`

Melepas semua handle yang masih hidup. Mengembalikan jumlah yang dilepas dan error pertama, atau `nil` kalau tidak ada error.

### `nimgui.media.stats()`

Mengembalikan `textures`, `atlas_pixels`, `frames`, dan `estimated_bytes` (`atlas_pixels * 4`). Fungsi menghitung handle yang sudah diunggah; handle yang masih dimuat belum dihitung sampai teksturnya diunggah. Gambar non-GIF tanpa `width`/`height` menyumbang `0` piksel.

### Field handle

Handle GIF punya `tex`, `width`, `height`, `atlas_width`, `atlas_height`, `atlas_pixels`, `cell_width`, `cell_height`, `scale`, `frame_count`, `frame_index`, `loop_count`, `frames`, `uv0`, `uv1`, `animated`, `fallback`, `loading`, `failed`, `error`, `progress`, dan `released`.

Handle gambar mentah punya `tex`, `width`, `height` (dari opsi), `atlas_width`, `atlas_height`, `atlas_pixels`, `frame_count`, `frame_index`, `loop_count`, `frames`, `uv0`, `uv1`, `animated`, `fallback`, `loading`, `failed`, `progress`, dan `released`. `error` hanya muncul setelah kegagalan.

Setiap entri di `frames` berisi `delay` dalam detik, plus `uv0` dan `uv1`. Untuk gambar mentah, `width`/`height` bernilai `nil` kalau tidak dikirim di opsi, dan `atlas_pixels` bernilai `0` tanpa keduanya.

## State binder

### `nimgui.state(table)`

Membuat binder untuk tabel state. Kebanyakan script bisa mengirim tabel biasa langsung ke widget; binder berguna saat `cdata` perlu diteruskan ke API ImGui.

Binder menyediakan:

| Method | Keterangan |
|---|---|
| `int(key, default)` | Mengembalikan proxy integer |
| `bool(key, default)` | Mengembalikan proxy boolean |
| `float(key, default)` | Mengembalikan proxy float |
| `get(key)` | Membaca `state[key]` |
| `set(key, value)` | Menulis `state[key]` |

`key` harus string. Key di-cache saat pertama dipakai; panggilan berikutnya mengembalikan proxy yang sama.

Setiap proxy menyediakan:

| Method | Keterangan |
|---|---|
| `get()` | Membaca `state[key]` |
| `set(value)` | Menulis `state[key]` |
| `commit()` | Menulis nilai `cdata` saat ini ke `state[key]` |
| `refresh()` | Membaca `state[key]` ke `cdata` |
| `value()` | Mengembalikan nilai `cdata` saat ini |
| `cdata()` | Mengembalikan `cdata` dasarnya |

```lua
local binder = nimgui.state(cfg)
local volume = binder:float('volume', 0.5)
imgui.SliderFloat('##volume', volume:cdata(), 0, 1)
cfg.volume = volume:value()
```

## Batasan yang diketahui

- `toggle` memakai `InvisibleButton` dan tidak punya highlight fokus keyboard yang terlihat. Pakai `checkbox` untuk navigasi keyboard.
- `disabled_hint` pada tombol hanya muncul saat hover. Di perangkat sentuh, tampilkan alasannya sebagai teks biasa.
- Dear ImGui 1.72 tidak punya `BeginTable` atau `BeginDisabled`; `nimgui` memakai `Columns`, `BeginChild`, `Selectable`, dan push style.
- Jangan melakukan IO, load tekstur, rebuild font atlas, atau alokasi state di callback draw. Lakukan di `OnInitialize` atau saat state berubah.
- `imgui.Text` dan `SetTooltip` milik host bersifat variadic dan pernah crash di Android. `nimgui` memakai `TextUnformatted` dan `BeginTooltip`/`EndTooltip`.
- Hanya satu toast yang bisa aktif.
- Budget canvas GIF tetap `4.000.000` piksel di versi ini.
- Gambar non-GIF mentah tidak punya query ukuran di `mimgui`; kirim `width`/`height` kalau `media.stats()` perlu akurat.

## Verifikasi

Suite headless dijalankan dengan `luajit` dan binding `mimgui` palsu:

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

`tests/test_color.lua` menambah 14 checks dan `tests/test_motion.lua` menambah 8, sehingga totalnya 454 checks dan 0 failures.

`luacheck --std lua51 dist/lib/nimgui/*.lua tests/fake_nimgui.lua tests/test_nimgui_*.lua tests/test_color.lua tests/test_motion.lua` melaporkan 0 error dan 83 warning yang sudah diketahui, sebagian besar berupa argumen `self` yang tidak dipakai di `state.lua` dan global host yang dipakai binding palsu di test.

Belum diverifikasi: rendering dan interaksi Android, DPI `1 / 1.5 / 2`, target sentuh nyata, layar kecil, batas raster/VRAM, FPS dengan playback GIF, serta reload/pause/terminate. Semuanya tetap `static review only` atau `not verified`.
