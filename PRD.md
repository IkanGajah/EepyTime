# PRODUCT REQUIREMENTS DOCUMENT (PRD)

**Nama Proyek:** Timer Tidur Otomatis (Sleep & Mute Timer Utility)  

**Platform Target:** Android (API Level 26 / Android 8.0 ke atas)  

**Arsitektur:** Offline-First Mobile Utility dengan Integrasi Native OS Policy  



---



## 1. Ringkasan Eksekutif (Product Overview)

**Timer Tidur Otomatis** adalah aplikasi utilitas sistem berbasis Android yang dirancang untuk mengotomatisasi peredaman suara media (*audio suppression*) dan penguncian layar perangkat (*force screen-lock / sleep*) ketika batas waktu hitung mundur habis. Berbeda dari *sleep timer* internal bawaan aplikasi musik yang hanya menghentikan pemutaran lokal, aplikasi ini bekerja langsung pada layer kebijakan sistem operasi (*OS Policy Layer*) menggunakan `AudioManager` dan `DevicePolicyManager`. Pendekatan ini memastikan seluruh suara media mati ke titik nol dan layar terkunci sepenuhnya meskipun terdapat aplikasi video yang menahan status layar (*Wake-Lock*).



---



## 2. Profil Pengguna & Pernyataan Masalah (Problem Statement)



### 2.1 Target Persona

* **Profil Subjek:** Pengguna perangkat seluler aktif yang rutin mengonsumsi konten audio/video menjelang tidur (*bedtime media listener*), seperti podcast, video YouTube, ASMR, atau musik relaksasi.



### 2.2 Kegagalan Solusi Saat Ini (Current Workarounds & Gaps)

1. **Pemutus Internal Aplikasi (In-App Timers):**

  * *Aksi:* Memakai sleep timer bawaan Spotify atau platform tertentu.

  * *Celah:* Tidak universal. Tidak bisa mengunci layar (*force lock*) dan tidak berlaku jika berpindah ke video lokal, browser, atau YouTube.

2. **Kebijakan Auto-Lock Sistem Operasi:**

  * *Aksi:* Menunggu layar mati sendiri mengikuti durasi *display timeout* sistem.

  * *Celah:* Gagal total akibat mekanisme `WAKELOCK` Android dari pemutar video yang mengabaikan *system timeout*.

3. **Tindakan Manual (Bangun Tengah Malam):**

  * *Aksi:* Mengorbankan kualitas tidur untuk mematikan perangkat secara sadar di tengah malam.

  * *Celah:* Mengganggu ritme sirkadian dan memicu fragmentasi tidur.

4. **Pembiaran Pasif:**

  * *Aksi:* Tidak melakukan apa pun dan membiarkan perangkat menyala hingga pagi.

  * *Celah:* Penurunan kesehatan baterai (*battery degradation*), pemborosan listrik/kuota karena *autoplay*, risiko *screen burn-in*, dan potensi bahaya *overheating* di kasur.



---



## 3. Sasaran Produk, First-Time UX & Strategi Retensi



* **Onboarding Kritis (First-Time User Experience):** Saat pengguna membuka aplikasi untuk pertama kali, satu hal utama yang wajib langsung selesai sebelum mereka menutup atau menjalankan fungsi aplikasi adalah **pemberian izin kunci layar (Device Administrator Permission)**.

* **Fitur Inti Wajib (Core MVP):** Hitung mundur (*Countdown*), Matikan suara (*Audio Mute*), Kunci layar (*Screen Lock*), dan Riwayat pemakaian (*Usage History*).

* **Keunggulan Utama (Core Value Proposition):** Menghemat baterai secara signifikan dan menjaga kesehatan perangkat tanpa menuntut pengguna bangun di tengah malam.

* **Pendorong Retensi (Habit Loop):** Membentuk kebiasaan rutin setiap malam (*nightly habit*) melalui kemudahan memilih preset durasi yang tersimpan dan pemantauan ringkasan kebiasaan tidur/pemakaian.



---



## 4. Spesifikasi Teknis & Arsitektur (Tech Stack)



> **CATATAN ARSITEKTUR PENTING UNTUK AI CODING AGENT:**  

> Aplikasi ini **100% berjalan secara lokal (Offline-First)** di perangkat Android. **DILARANG** membuat server eksternal (seperti Java Spring Boot / REST API). Seluruh logika sistem belakang layar (*Backend Logic*) dieksekusi di layer Native Android (Kotlin/Java) menggunakan jembatan komunikasi `MethodChannel`.



* **Frontend & UI Layer:** Flutter SDK (Dart) — Menggunakan skema warna Material Design 3 Dark Mode (ramah mata di kondisi gelap).

* **Local Backend / Native Bridge:** Flutter `MethodChannel` (`sleep_timer/native_control`) yang terhubung langsung ke kode Native Android (`MainActivity.kt`).

* **OS Hardware APIs (Android Native):**

 * `android.app.admin.DevicePolicyManager` & `DeviceAdminReceiver` (untuk eksekusi `lockNow()`).

 * `android.media.AudioManager` (untuk memanipulasi `STREAM_MUSIC` ke indeks `0` dan memulihkan volume).

* **Database Lokal:** SQLite melalui paket `sqflite` dan `path` (tanpa ORM berat).

* **Deployment Target:** Perangkat fisik Android (APK/AAB lokal via USB Debugging / Release Build).



---



## 5. Rincian Modul & Spesifikasi Fitur



### Modul 1: Hitung Mundur (Core Timer Engine)

1. **Pilih Durasi:** Input durasi manual (jam, menit, detik) atau pemilihan langsung dari daftar preset.

2. **Mulai & Jeda (Start & Pause):** Menjalankan siklus hitung mundur per detik dengan akurasi tinggi dan menjeda waktu kapan saja tanpa kehilangan sisa detik.

3. **Atur Ulang (Reset):** Mengembalikan angka hitung mundur ke nilai durasi awal yang dipilih.

4. **Indikator Visual Progres:** Tampilan angka waktu proporsional (`HH:MM:SS`) dengan indikator status aktif (*Idle*, *Running*, *Paused*).



### Modul 2: Izin Kunci Layar (OS Policy & Permission Management)

1. **Deteksi Status Izin:** Memeriksa secara otomatis saat inisialisasi aplikasi (`initState` & `AppLifecycleState.resumed`) apakah izin `DeviceAdmin` sudah aktif.

2. **Banner Peringatan:** Menampilkan peringatan yang jelas di bagian atas layar utama apabila izin kunci layar belum diberikan oleh pengguna.

3. **Buka Pengaturan Izin:** Tombol aksi langsung yang memicu *Android Intent* (`ACTION_ADD_DEVICE_ADMIN`) menuju halaman otorisasi sistem.

4. **Panduan Pencabutan Izin:** Informasi singkat di dalam aplikasi mengenai cara menonaktifkan izin admin jika pengguna ingin mencopot pemasangan (*uninstall*) aplikasi.



### Modul 3: Peredam Suara (Audio Suppression Control)

1. **Redam Saat Habis:** Secara otomatis mengubah volume kanal media (`STREAM_MUSIC`) menjadi `0` tepat ketika hitung mundur mencapai `00:00:00`.

2. **Redam Sekali Ketuk (One-Tap Mute):** Tombol aksi cepat di UI untuk membisukan volume media seketika tanpa harus menunggu timer habis.

3. **Pulihkan Suara (Restore Audio):** Menyimpan nilai volume media sebelum diredam (`lastVolumeLevel`) di memori native, lalu mengembalikannya ke nilai semula saat pengguna menekan tombol *Pulihkan Suara*.

4. **Indikator Status Audio:** Menampilkan status apakah kanal media saat ini sedang dalam kondisi teredam (*Muted*) atau normal.



### Modul 4: Kunci Layar (Screen Lock Execution)

1. **Kunci Saat Habis:** Memicu instruksi `DevicePolicyManager.lockNow()` tepat saat timer menyentuh `00:00:00` (setelah peredaman suara selesai dieksekusi).

2. **Kunci Sekali Ketuk (One-Tap Lock):** Tombol aksi instan untuk mengunci layar perangkat saat itu juga (berguna untuk pengujian langsung oleh pengguna).

3. **Status Kunci Berhasil:** Mencatat keberhasilan eksekusi penguncian layar ke dalam log sesi di database SQLite (apakah terkunci penuh atau hanya berhasil meredam suara karena izin admin belum aktif).



### Modul 5: Preset Durasi (SQLite Preset CRUD)

1. **Daftar Preset:** Menampilkan pilihan durasi cepat yang diambil dari tabel `presets` di SQLite (dilengkapi data awal bawaan: *10 Detik [Uji Coba]*, *15 Menit*, *30 Menit*, *60 Menit*).

2. **Tambah Preset:** Form dialog untuk menyimpan kombinasi label nama dan durasi baru ke dalam SQLite.

3. **Hapus Preset:** Aksi menghapus item preset dari database lokal.

4. **Eksekusi Cepat Preset:** Mengetuk kartu preset langsung memasang durasi tersebut ke mesin hitung mundur utama.



### Modul 6: Riwayat Pemakaian (Usage History & Habit Analytics)

1. **Daftar Riwayat:** Menampilkan daftar log sesi timer yang telah selesai dieksekusi dari tabel `history` SQLite secara kronologis terbalik (*terbaru di atas*).

2. **Detail Satu Sesi:** Menampilkan rincian per sesi: tanggal & waktu eksekusi, durasi timer yang dijalankan, serta status keberhasilan (*Terkunci & Teredam* vs *Hanya Teredam*).

3. **Ringkasan Kebiasaan:** Kartu metrik ringkas di bagian atas tab Riwayat yang menghitung **Total Sesi Berhasil**, **Total Waktu Penggunaan**, dan **Rata-rata Durasi Tidur/Timer** menggunakan agregasi query SQLite.

4. **Bersihkan Riwayat:** Opsi menghapus seluruh log riwayat pemakaian.



### Modul 7: Pengaturan (App Settings)

1. **Tema Tampilan:** Pengaturan mode gelap (*Dark Mode* default) atau kontras gelap pekat (*AMOLED Pitch Black*) untuk menghemat baterai di layar OLED.

2. **Suara & Pemberitahuan:** Opsi mengaktifkan/menonaktifkan umpan balik getar (*haptic feedback*) atau notifikasi toast ketika timer dimulai/selesai.

3. **Tentang Aplikasi:** Informasi versi aplikasi, status izin sistem, dan tombol pintas untuk mencabut izin *Device Admin* dengan aman.



---



## 6. Skema Database Lokal (SQLite Schema)

Nama File Database: `sleep_timer_utility.db` (Versi 1)

### 6.1 Tabel `presets`
```sql
CREATE TABLE presets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  label TEXT NOT NULL,
  duration_seconds INTEGER NOT NULL,
  created_at TEXT NOT NULL
);
```
### 6.2 Tabel `history`
```sql
CREATE TABLE history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  preset_label TEXT NOT NULL,
  duration_seconds INTEGER NOT NULL,
  executed_at TEXT NOT NULL,
  is_screen_locked INTEGER NOT NULL DEFAULT 1, -- 1 = Berhasil Kunci & Mute, 0 = Hanya Mute
  is_audio_muted INTEGER NOT NULL DEFAULT 1
);
```

### 6.3 Tabel `settings`
```sql
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
-- Default rows:
-- ('pitch_black_mode', 'false')
-- ('haptic_feedback', 'true')
```

---

## 7. Kontrak Komunikasi Native (`MethodChannel`)

* **Nama Channel:** `sleep_timer/native_control`

| Nama Method | Argumen | Return Type (Dart) | Deskripsi Tugas di Native Android (`MainActivity.kt`) |
|---|---|---|---|
| `checkAdmin` | `null` | `bool` | Memeriksa `DevicePolicyManager.isAdminActive(compName)`. |
| `requestAdmin` | `null` | `bool` | Membuka Intent `ACTION_ADD_DEVICE_ADMIN` jika belum aktif. |
| `revokeAdmin` | `null` | `bool` | Mencabut hak admin via `removeActiveAdmin(compName)` untuk memudahkan uninstall. |
| `muteAudio` | `null` | `int` | Menyimpan volume `STREAM_MUSIC` saat ini ke variabel memori, lalu mengubah volume menjadi `0`. Mengembalikan nilai volume sebelumnya. |
| `restoreAudio` | `null` | `int` | Mengembalikan volume `STREAM_MUSIC` ke nilai sebelum diredam. |
| `lockScreen` | `null` | `bool` | Memanggil `dpm.lockNow()` jika admin aktif. Mengembalikan `false` jika gagal. |
| `executeSleepAndMute` | `null` | `Map<String, bool>` | Menjalankan `muteAudio` dan `lockScreen` sekaligus saat timer habis. Mengembalikan `{'muted': true, 'locked': true/false}`. |

---

## 8. Peta Jalan Implementasi Bertahap (Phased Implementation Roadmap)
Urutan pengerjaan telah dioptimalkan berdasarkan ketergantungan sistem (system dependencies) agar setiap fase dapat dikompilasi dan diuji tanpa error:

FASE 1: Pondasi Proyek, Izin Sistem & Jembatan Native (Foundation & OS Policy)

Konfigurasi pubspec.yaml (sqflite, path).

Pembuatan res/xml/device_admin.xml dan pendaftaran <receiver> di AndroidManifest.xml.

Implementasi lengkap MainActivity.kt untuk seluruh kontrak MethodChannel (Izin Admin, Peredam Suara, Pulihkan Suara, dan Kunci Layar).

FASE 2: Layer Database SQLite & Mesin Hitung Mundur (Data & Core Timer Layer)

Pembuatan kelas DatabaseHelper beserta query CRUD untuk presets, history (termasuk query agregasi ringkasan kebiasaan), dan settings.

Implementasi state mesin hitung mundur (Pilih Durasi, Mulai, Jeda, Atur Ulang) dan pengait otomatis ke MethodChannel saat waktu habis.

FASE 3: Antarmuka Utama, Kontrol Cepat & Manajemen Preset (Primary UI & Presets)

Implementasi Banner Peringatan Izin Kunci Layar (prioritas tampilan pertama).

Komponen UI Timer Utama, tombol aksi sekali ketuk (Redam Sekali Ketuk, Pulihkan Suara, Kunci Sekali Ketuk), serta daftar dan dialog tambah/hapus Preset Durasi.

FASE 4: Riwayat Pemakaian, Analitik Kebiasaan & Pengaturan (History & Settings)

Implementasi Tab Riwayat Pemakaian, kartu Ringkasan Kebiasaan, modal Detail Satu Sesi, serta halaman Pengaturan (Tema AMOLED Pitch Black, Haptic, & tombol pencabut izin admin).


