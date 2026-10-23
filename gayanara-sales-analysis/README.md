# Gayanara: Analisis Penjualan Toko Fashion Online

Project end-to-end untuk toko fashion online fiktif bernama Gayanara: mulai dari data mentah yang berantakan, dibersihkan dan dianalisis dengan SQL, sampai menjadi dashboard satu halaman di Power BI beserta rekomendasi bisnisnya.

![Dashboard Gayanara](dashboard/dashboard.png)

## Pertanyaan Bisnis

1. Bagaimana tren revenue dari tahun ke tahun dan dari bulan ke bulan?
2. Kategori dan brand mana yang paling laku?
3. Apakah promo membuat pelanggan belanja lebih banyak, atau hanya memotong pemasukan?
4. Di mana tingkat cancel dan return paling tinggi: per kurir, metode pembayaran, atau provinsi?

## Data

Dataset simulasi (perusahaan fiktif) dari [Ngulik Data](https://ngulikdata.com). Pemilihan pertanyaan, cleaning, analisis, dashboard, dan rekomendasi dikerjakan sendiri.

| Tabel | Baris | Isi |
| --- | --- | --- |
| `orders` | 3.000 | Pesanan Jan 2022 – Feb 2025: tanggal, status, total, promo, kurir, wilayah |
| `order_items` | 4.986 | Item di setiap pesanan |
| `products` | 300 | Katalog produk: kategori, brand, harga |
| `customers` | 800 | Data pelanggan |
| `reviews` | 1.500 | Rating dan ulasan pembeli |

## Tools

| Tahap | Tools |
| --- | --- |
| Pemeriksaan awal | Excel (filter per kolom, tanpa mengubah file) |
| Database, cleaning, analisis | PostgreSQL (pgAdmin 4) |
| Dashboard | Power BI Desktop |

## Alur Pengerjaan

1. **Load:** membuat 5 tabel di PostgreSQL lengkap dengan primary key dan foreign key, lalu mengimpor CSV.
2. **Audit dan cleaning** ([`sql/01_cleaning.sql`](sql/01_cleaning.sql)): memeriksa setiap tabel, mengonfirmasi temuan dengan query, lalu memperbaikinya di tabel baru (`*_clean`). Tabel mentah tidak diubah.
3. **Analisis** ([`sql/02_analysis.sql`](sql/02_analysis.sql)): menjawab 4 pertanyaan bisnis.
4. **Dashboard** ([`gayanara_dashboard.pbix`](gayanara_dashboard.pbix), [PDF](dashboard/dashboard.pdf)): Power BI terhubung langsung ke tabel `*_clean`. Angka di dashboard dicocokkan dengan hasil SQL.

## Log Cleaning

| Tabel | Temuan | Keputusan |
| --- | --- | --- |
| products | Kategori punya 14 variasi penulisan (huruf besar/kecil, Indonesia/Inggris, istilah berbeda) | Dirapikan jadi 6 kategori |
| products | 9 produk tanpa `material` | Diisi `'Tidak diketahui'` |
| products | 74 nama produk muncul lebih dari sekali dengan ID dan harga berbeda | Tidak digabung (dianggap varian); analisis memakai `product_id` |
| customers | 3 pasang pelanggan berbeda memakai email yang sama | Email yang tidak cocok dengan nama pelanggan dikosongkan; pelanggan tidak dihapus |
| customers | 40 nomor HP kosong | Dibiarkan kosong, tidak diisi data karangan |
| customers | **358 dari 800 pelanggan memiliki pesanan pertama sebelum tanggal registrasinya** (tidak disebut di dokumentasi dataset) | `registration_date` tidak dipakai; tanggal awal pelanggan memakai tanggal pesanan pertama |
| orders | 1.786 pesanan tanpa `promo_code` dan diskon | Diisi `'Tanpa promo'` dan diskon 0 (kosong memang berarti tanpa promo) |
| orders | Total pesanan terkecil Rp1.000 | Dicek: produk Rp49.000 dengan diskon Rp48.000, bukan error |
| orders, order_items | Total pesanan, subtotal, dan harga dicek silang antartabel | Konsisten, tidak ada yang diubah |
| reviews | Teks ulasan tidak sesuai rating (contoh: "kurang puas" rata-rata rating 4,04) | `review_text` tidak dipakai di analisis; `rating` tetap dipakai |

## Temuan

**1. Revenue tumbuh, tanpa pola musiman.**
Revenue naik dari Rp198,8 juta (2022) menjadi Rp427,9 juta (2023, +115%) dan Rp513,2 juta (2024, +20%). Lonjakan terbesar terjadi di Januari 2023 (Rp45,8 juta, lebih dari 2x Desember 2022), dan bulan tertinggi adalah Februari 2025. Periode Harbolnas dan Ramadan tidak lebih tinggi dari bulan lain.

**2. Kategori merata; perbedaan ada di brand.**
Setiap kategori menyumbang 15–17% penjualan kotor. Kaos terendah secara total, tetapi produknya paling sedikit; dihitung per produk, Kaos justru di atas Jaket dan Aksesoris. Di level brand, Riang Apparel teratas (12,4%) dan Ratu Mode terbawah (7,5%). Unit terjual tidak selalu sejalan dengan penjualan: Kanvas Lokal laku banyak tapi harga rata-ratanya paling murah (~Rp183 ribu per unit), sedangkan NusaBrand lebih sedikit terjual tapi harganya tertinggi (~Rp310 ribu).

**3. Promo tidak menaikkan nilai belanja.**
Nilai belanja sebelum diskon hampir sama antara pesanan dengan promo (Rp515.199) dan tanpa promo (Rp513.830). Promo hanya mengurangi pembayaran rata-rata sekitar Rp30.661 per pesanan. Kedelapan kode promo dipakai merata dengan rata-rata diskon 10–13%, dan total diskon yang diberikan sekitar Rp31,4 juta.

**4. Return J&T paling perlu diperhatikan.**
Rata-rata keseluruhan: cancel 10,9% dan return 5,0%. J&T return-nya 6,0% dengan volume terbesar, sehingga jumlah return-nya paling banyak. Pos Indonesia lebih tinggi (6,8%) tetapi volumenya kecil. Perbedaan per metode pembayaran kecil. Beberapa provinsi terlihat tinggi, tetapi jumlah pesanannya terlalu sedikit untuk disimpulkan.

## Rekomendasi

1. **Uji ulang strategi promo.** Jalankan eksperimen sederhana (sebagian pelanggan mendapat promo, sebagian tidak) untuk melihat apakah promo menambah jumlah pembeli. Selama belum terbukti, batasi diskon yang sangat besar.
2. **Evaluasi pengiriman J&T.** Bahas tingkat return dengan pihak kurir dan pantau setiap bulan dengan garis rata-rata 5% sebagai pembanding.
3. **Catat alasan cancel dan return.** Tanpa data alasan, penyebabnya hanya bisa diduga.
4. **Perbaiki pencatatan tanggal registrasi.** Hampir separuh pelanggan punya tanggal registrasi yang tidak masuk akal, sehingga analisis berbasis umur pelanggan belum bisa dipercaya.

## Batasan

- Datanya sintetis, sehingga beberapa pola (misalnya tidak ada efek musiman) bisa jadi karena cara data dibuat.
- Diskon dicatat per pesanan, bukan per item, jadi analisis kategori dan brand memakai penjualan kotor (sebelum diskon).
- Data tidak menunjukkan apa yang terjadi seandainya promo tidak ada, sehingga dampak promo terhadap jumlah pembeli belum bisa diukur.

## Struktur Repository

```
gayanara-sales-analysis/
├── README.md
├── sql/
│   ├── 01_cleaning.sql
│   └── 02_analysis.sql
├── dashboard/
│   ├── dashboard.png
│   └── dashboard.pdf
└── gayanara_dashboard.pbix
```
