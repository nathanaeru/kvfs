#!/usr/bin/env bash

BASE_URL="http://localhost:8080"
OWNER="alice"

echo "=================================================="
echo "  Seeding KVFS Sample Data for Owner: ${OWNER}"
echo "=================================================="

# Helper function untuk POST request JSON
send_post() {
    local endpoint="$1"
    local json_data="$2"
    curl -s -X POST "${BASE_URL}${endpoint}" \
         -H "Content-Type: application/json" \
         -d "${json_data}"
    echo ""
}

# 1. Membuat Struktur Folder
echo "--> [1/4] Membuat struktur folder..."
send_post "/api/file/${OWNER}/documents" '{"type": "directory"}'
send_post "/api/file/${OWNER}/photos" '{"type": "directory"}'
send_post "/api/file/${OWNER}/documents/work" '{"type": "directory"}'
send_post "/api/file/${OWNER}/projects" '{"type": "directory"}'
send_post "/api/file/${OWNER}/projects/erlang" '{"type": "directory"}'
send_post "/api/file/${OWNER}/archive" '{"type": "directory"}'

# 2. Membuat Berkas Sampel dengan Tag Metadata
echo "--> [2/4] Membuat berkas sampel..."
send_post "/api/file/${OWNER}/documents/work/report_q4.txt" \
    '{"type": "file", "content": "Laporan Keuangan Q4 - Confidential", "tags": ["urgent", "finance"], "mime_type": "text/plain"}'

send_post "/api/file/${OWNER}/documents/notes.txt" \
    '{"type": "file", "content": "Catatan diskusi Flipped Classroom Erlang dan Khepri", "tags": ["fp", "notes"], "mime_type": "text/plain"}'

send_post "/api/file/${OWNER}/projects/erlang/kvfs_vfs.erl" \
    '{"type": "file", "content": "-module(kvfs_vfs).\n-export([read_path/2]).", "tags": ["erlang", "fp", "khepri"], "mime_type": "text/x-erlang"}'

send_post "/api/file/${OWNER}/readme.md" \
    '{"type": "file", "content": "# Welcome to KVFS", "tags": ["docs"], "mime_type": "text/markdown"}'

send_post "/api/file/${OWNER}/photos/vacation.jpg" \
    '{"type": "file", "content": "BASE64_ENCODED_IMAGE_DATA", "tags": ["vacation", "photo"], "mime_type": "image/jpeg"}'

# 3. Menguji Operasi Copy & Move Atomic
echo "--> [3/4] Menjalankan operasi Copy dan Move..."
# Menyalin notes.txt ke folder archive (notes_backup.txt)
send_post "/api/copy" \
    "{\"owner\": \"${OWNER}\", \"src\": [\"documents\", \"notes.txt\"], \"dst\": [\"archive\", \"notes_backup.txt\"]}"

# 4. Verifikasi Status ETS Quota dan Tag Search
echo "--> [4/4] Verifikasi hasil proyeksi ETS..."
echo -n "ETS Quota Status: "
curl -s "${BASE_URL}/api/quota/${OWNER}"
echo ""

echo -n "Pencarian Tag 'fp' via ETS: "
curl -s "${BASE_URL}/api/search/tag?tag=fp"
echo ""

echo "=================================================="
echo "  Seeding Selesai! Silakan cek Web GUI."
echo "=================================================="