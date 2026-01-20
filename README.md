# PostgreSQL Tuner Pro (Enterprise Edition) 🚀

pg_tuner_pro.sh adalah alat otomatisasi berbasis Bash yang dirancang untuk mengoptimalkan performa database PostgreSQL secara instan. Alat ini menyesuaikan konfigurasi database berdasarkan spesifikasi hardware (RAM, CPU, Disk) dan beban koneksi Anda.

# 🌟 Fitur Utama

Tuning Hardware Otomatis: Menghitung parameter memori optimal (Shared Buffers, Work Mem, dll.) berdasarkan kapasitas RAM dan CPU server.

Optimasi Level Kernel: Menyesuaikan parameter sysctl Linux (seperti vm.swappiness) untuk mencegah hambatan sistem.

Integrasi PgBouncer: Opsi instalasi otomatis untuk pooling koneksi yang efisien.

Monitoring Terintegrasi: Mengaktifkan ekstensi pg_stat_statements untuk pelacakan query tingkat lanjut.

Manajemen User & Role: Membuat user baru dan memberikan hak akses database secara interaktif.

# 📋 Prasyarat

Sebelum menjalankan skrip, pastikan sistem Anda memenuhi kriteria berikut:

OS: Ubuntu (20.04+) atau Debian (11+).

Izin: Akses Root atau sudo.

Database: PostgreSQL harus sudah terinstal di server.

🛠️ Mulai Penggunaan

1. Instalasi

Unduh skrip langsung menggunakan wget:

wget [https://raw.githubusercontent.com/username/repository/main/pg_tuner_pro.sh](https://raw.githubusercontent.com/username/repository/main/pg_tuner_pro.sh)


2. Izin Eksekusi

Berikan izin eksekusi pada skrip:

chmod +x pg_tuner_pro.sh


3. Eksekusi

Jalankan skrip dengan hak akses sudo:

sudo ./pg_tuner_pro.sh


🔍 Input & Logika Tuning

Selama eksekusi, skrip akan meminta informasi berikut:

Input

Deskripsi

PG Version

Versi PostgreSQL yang sedang berjalan.

PG Port

Port database yang diinginkan (Default: 5432).

Server RAM

Total RAM sistem dalam Gigabytes (GB).

CPU Cores

Jumlah core CPU fisik atau virtual.

Storage Type

Pilihan antara SSD/NVMe (Performa) atau HDD (Standar).

Connections

Estimasi jumlah user yang terkoneksi bersamaan.

Detail Logika Tuning:

Shared Buffers: Diatur ke 25% dari total RAM (maksimal 20GB).

Effective Cache Size: Diatur ke 75% dari total RAM.

Work Mem: Dihitung dalam satuan KB per koneksi untuk mencegah Out Of Memory (OOM).

I/O Costs: Dioptimalkan pada 1.1 untuk SSD atau 4.0 untuk HDD.

⚠️ Catatan Penting

[!IMPORTANT]
Restart Layanan: Skrip ini akan merestart layanan PostgreSQL untuk menerapkan perubahan. Hindari menjalankan skrip ini saat jam sibuk trafik.

Backups: File cadangan dibuat secara otomatis dengan stempel waktu (contoh: postgresql.conf.bak_2024-01-01).

Connection Pooling: Jika jumlah koneksi concurrent Anda di atas 500, sangat disarankan untuk mengaktifkan opsi PgBouncer.

📄 Lisensi

Proyek ini dilisensikan di bawah Lisensi MIT.

Dibuat untuk kebutuhan sistem database tingkat Enterprise.
