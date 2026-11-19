# KVFS - Khepri Virtual File System

KVFS (Khepri Virtual File System) adalah aplikasi sistem berkas virtual berbasis struktur pohon (tree structure) yang dibangun di atas Erlang/OTP dan basis data Khepri. Aplikasi ini mengimplementasikan konsep Pemrograman Fungsional (FP), transaksi terdistribusi berstandar ACID (via Raft state machine), dan mekanisme proyeksi real-time ke Erlang Term Storage (ETS) yang diakses melalui antarmuka Web GUI interaktif.

## Fitur Utama

- Hierarchical Tree Storage: Berkas dan direktori disimpan secara hirarkis menggunakan struktur Khepri Path (`[kvfs, Owner, PathComponents...]`).
- Atomic Transactions: Operasi pemindahan (`move`) dan penyalinan (`copy`) berkas atau direktori dilakukan secara atomik menggunakan `khepri_tx`.
- Real-time ETS Projections: Metadata berkas diproyeksikan secara otomatis ke tabel ETS (`kvfs_tag_index` dan `kvfs_user_quota`) untuk mendukung pencarian tag dan kalkulasi kuota dengan kompleksitas O(1).
- REST API and WebSocket Gateway: Diintegrasikan menggunakan web server Cowboy untuk melayani operasi CRUD berkas dan penyiaran (broadcasting) perubahan status secara real-time ke klien.
- Web-based File Manager: GUI berbasis web dengan antarmuka bertema file manager untuk navigasi folder, manajemen berkas, pencarian tag, dan pemantauan tabel ETS.

## Arsitektur Modul

```text
src/
|-- kvfs.app.src        - Metadata aplikasi Erlang
|-- kvfs_app.erl        - Modul inisialisasi aplikasi, Khepri, Proyeksi, dan Listener Cowboy
|-- kvfs_sup.erl        - Top-level supervisor
|-- kvfs_vfs.erl        - Logika inti VFS (CRUD berkas/direktori, move, copy, khepri_tx)
|-- kvfs_projection.erl - Pendaftaran Khepri Projection ke tabel ETS (Tag Indexer & User Quota)
|-- kvfs_router.erl     - Pengaturan rute URL Cowboy (HTTP API, WebSocket, dan File Statis)
|-- kvfs_http_handler.erl - Handler HTTP REST API untuk operasi berkas dan pencarian
`-- kvfs_ws_handler.erl   - Handler WebSocket untuk penyiaran event pembaruan pohon secara real-time

priv/static/
|-- index.html          - Antarmuka utama File Manager Web GUI
`-- app.js              - Logika interaksi frontend dan klien WebSocket
```

## Persyaratan Sistem dan Dependensi

### Lingkungan Eksekusi

- Erlang/OTP 25.0 atau versi yang lebih baru
- rebar3 3.20.0 atau versi yang lebih baru

### Dependensi Aplikasi (rebar.config)

- khepri (0.14.0): Basis data terdistribusi berbasis Raft state machine
- cowboy (2.10.0): HTTP web server dan WebSocket handler
- jsx (3.1.0): Encoding dan decoding format JSON

## Panduan Instalasi dan Setup

### 1. Kloning Repositori

```bash
git clone [https://github.com/nathanaeru/kvfs.git](https://github.com/nathanaeru/kvfs.git)
cd kvfs
```

### 2. Mengunduh Dependensi dan Kompilasi

Gunakan rebar3 untuk mengunduh seluruh dependensi dan memproses kompilasi berkas Erlang:

```bash
rebar3 get-deps
rebar3 compile
```

## Cara Menjalankan Aplikasi

### 1. Menjalankan Server via rebar3 Shell

Jalankan perintah berikut pada terminal proyek:

```bash
rebar3 shell
```

Saat aplikasi berhasil berjalan, Anda akan melihat pesan log berikut di terminal:

```plaintext
==================================================
KVFS Server running on http://localhost:8080
==================================================
```

### 2. Mengakses Web GUI

Buka peramban web dan akses URL berikut:

```plaintext
http://localhost:8080
```

Melalui antarmuka web, Anda dapat:

- Membuat folder baru dan membuat berkas teks beserta tag metadata.
- Mengunggah/membaca isi berkas.
- Melakukan pencarian berkas berdasarkan tag di indeks ETS secara instan.
- Mengamati pembaruan kuota penyimpanan dan tabel ETS secara live di panel bawah.

## Dokumentasi REST API

Semua respons API dikembalikan dalam format JSON.

| Method | Endpoint | Deskripsi |
| --- | --- | --- |
| GET | `/api/list/:owner/*path` | Menampilkan daftar isi direktori |
| GET | `/api/file/:owner/*path` | Membaca metadata dan isi dari suatu berkas |
| POST | `/api/file/:owner/*path` | Membuat berkas atau direktori baru |
| DELETE | `/api/file/:owner/*path` | Menghapus berkas atau direktori |
| POST | `/api/move` | Memindahkan / mengganti nama berkas (Atomic Move) |
| POST | `/api/copy` | Menyalin berkas atau direktori (Atomic Copy) |
| GET | `/api/search/tag?tag=KEY` | Mencari lokasi berkas dari tabel ETS berdasarkan tag |
| GET | `/api/quota/:owner` | Mengambil data kuota penggunaan memori dari tabel ETS |
| WS | `/ws` | WebSocket endpoint untuk menerima penyiaran event real-time |

### Contoh Request API via curl

Membuat file baru:

```bash
curl -X POST http://localhost:8080/api/file/alice/documents/notes.txt \
-H "Content-Type: application/json" \
-d '{"type": "file", "content": "Sample content", "tags": ["fp", "demo"]}'
```

Mencari file berdasarkan tag dari ETS:

```bash
curl http://localhost:8080/api/search/tag?tag=fp
```

## Lisensi

Proyek ini dilisensikan di bawah Apache License 2.0 / MPL 2.0.