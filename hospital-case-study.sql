/*

Studi Kasus Analitik Rumah Sakit

Tabel yang dipakai: pasien, dokter, kunjungan, diagnosa

Catatan: Nama tabel dan kolom memakai bahasa Indonesia, sesuai dataset yang disediakan.

Skema (dataset-nya tidak disertakan di repositori ini):

  pasien     (id, nama, umur, jenis_kelamin, kota, no_asuransi)            -- 30 baris, no_asuransi NULL = bayar mandiri
  dokter     (id, nama, spesialisasi, tahun_pengalaman)                    -- 12 baris
  kunjungan  (id, pasien_id, dokter_id, tanggal_kunjungan, tipe_kunjungan,
              biaya, lama_inap_hari, triase_level)                         -- 55 baris, biaya 0 = subsidi, triase_level 1-5 hanya untuk IGD
  diagnosa   (id, kunjungan_id, kode_icd, nama_diagnosa, tingkat_keparahan) -- 45 baris

Skill yang dipakai: Join, Logika Kondisional (CASE WHEN), Fungsi Agregat, Penanganan NULL (COALESCE, NULLIF), Penyaringan Grup (HAVING), Scoring dan Segmentasi

Tools: SQL

*/


/* ==========================================================
   SKENARIO 1: Dashboard Operasional IGD
   Brief dari Manajer Operasional
   ========================================================== */

-- 1.1 Beban kerja dokter
-- Tabel beban kerja per dokter: total kunjungan, jumlah Rawat Inap dan IGD,
-- persentase kasus berat (Rawat Inap + IGD), dan status beban kerja.
-- Dokter tanpa kunjungan tetap harus tampil, jadi saya mulai dari tabel dokter lalu LEFT JOIN ke kunjungan.
-- NULLIF mencegah pembagian dengan nol untuk dokter tanpa kunjungan, dan COALESCE mengubah hasilnya menjadi 0.

SELECT
  d.nama,
  d.spesialisasi,
  COUNT(k.id) AS total,
  COUNT(CASE WHEN k.tipe_kunjungan = 'Rawat Inap' THEN 1 END) AS rawat_inap,
  COUNT(CASE WHEN k.tipe_kunjungan = 'IGD' THEN 1 END) AS igd,
  COALESCE(ROUND(100.0 * COUNT(CASE WHEN k.tipe_kunjungan IN ('Rawat Inap', 'IGD') THEN 1 END) / NULLIF(COUNT(k.id), 0), 1), 0) AS persen_inap_igd,
  CASE
    WHEN COUNT(k.id) >= 8 THEN 'Sangat Sibuk'
    WHEN COUNT(k.id) >= 4 THEN 'Sibuk'
    WHEN COUNT(k.id) >= 1 THEN 'Normal'
    ELSE 'Belum Ada Pasien'
  END AS status_beban
FROM dokter d
LEFT JOIN kunjungan k ON d.id = k.dokter_id
GROUP BY d.id, d.nama, d.spesialisasi
ORDER BY
  total DESC,
  nama ASC


-- 1.2 Sebaran triase IGD per dokter
-- Hanya kunjungan IGD. Per dokter: jumlah kasus kritis (triase 1-2), mendesak (triase 3),
-- dan stabil (triase 4-5), persentase kasus kritis, serta status tim
-- untuk melihat dokter mana yang mungkin perlu dibantu.

SELECT
  d.nama AS nama,
  COUNT(*) AS total_igd,
  COUNT(CASE WHEN k.triase_level <= 2 THEN 1 END) AS kritis,
  COUNT(CASE WHEN k.triase_level = 3 THEN 1 END) AS mendesak,
  COUNT(CASE WHEN k.triase_level >= 4 THEN 1 END) AS stabil,
  ROUND(100.0 * COUNT(CASE WHEN k.triase_level <= 2 THEN 1 END) / COUNT(*), 1) AS persen_kritis,
  CASE
    WHEN COUNT(CASE WHEN k.triase_level <= 2 THEN 1 END) >= 2 AND COUNT(*) >= 4 THEN 'Butuh Tambahan Tim'
    WHEN COUNT(CASE WHEN k.triase_level <= 2 THEN 1 END) >= 2 THEN 'Prioritas Tinggi'
    ELSE 'Standar'
  END AS status_tim
FROM dokter d
JOIN kunjungan k ON d.id = k.dokter_id
WHERE k.tipe_kunjungan = 'IGD'
GROUP BY d.id, d.nama
ORDER BY
  total_igd DESC,
  nama ASC


-- 1.3 Daftar prioritas follow-up IGD
-- Satu baris per kunjungan IGD, lengkap dengan nama pasien. Pasien kritis yang lansia (60+)
-- atau balita (5 tahun ke bawah) harus dihubungi hari ini. Kurung di sekitar syarat umur
-- penting karena AND dan OR bercampur. Pasien tanpa asuransi ditampilkan sebagai
-- 'Bayar Mandiri' agar tim follow-up tahu siapa yang membayar sendiri.

SELECT
  k.id,
  p.nama AS pasien,
  p.umur AS umur,
  CASE
    WHEN k.triase_level <= 2 THEN 'Kritis'
    WHEN k.triase_level = 3 THEN 'Mendesak'
    ELSE 'Stabil'
  END AS kondisi,
  CASE
    WHEN k.triase_level <= 2 AND (p.umur >= 60 OR p.umur <= 5) THEN 'Hari Ini'
    WHEN k.triase_level <= 2 THEN 'Maks 3 Hari'
    WHEN k.triase_level = 3 THEN 'Maks 7 Hari'
    Else 'Kontrol Biasa'
  END AS jadwal_followup,
  COALESCE(p.no_asuransi, 'Bayar Mandiri') AS jaminan
FROM pasien p
JOIN kunjungan k ON k.pasien_id = p.id
WHERE k.tipe_kunjungan = 'IGD'
ORDER BY
  CASE jadwal_followup
    WHEN 'Hari Ini' THEN 1
    WHEN 'Maks 3 Hari' THEN 2
    WHEN 'Maks 7 Hari' THEN 3
    WHEN 'Kontrol Biasa' THEN 4
  END,
  k.id


/* ==========================================================
   SKENARIO 2: Laporan Keuangan Bulanan
   Brief dari Direktur Keuangan
   ========================================================== */

-- 2.1 Revenue dan porsi Rawat Inap per dokter
-- Seberapa besar revenue tiap dokter? Total revenue, rata-rata biaya per kunjungan berbayar
-- (kunjungan gratis dikeluarkan dengan NULLIF), porsi revenue dari Rawat Inap,
-- dan kategori kontribusi. Hanya dokter yang punya kunjungan yang tampil, jadi JOIN biasa sudah cukup.
-- NULLIF melindungi persentase dari pembagian dengan nol jika total revenue dokter adalah 0.

SELECT
  d.nama AS nama,
  d.spesialisasi,
  SUM(k.biaya) AS total_revenue,
  ROUND(AVG(NULLIF(k.biaya, 0)), 0) AS rata_berbayar,
  ROUND(100.0 * SUM(CASE WHEN k.tipe_kunjungan = 'Rawat Inap' THEN k.biaya ELSE 0 END) / NULLIF(SUM(k.biaya), 0), 1) AS persen_dari_inap,
  CASE
    WHEN SUM(k.biaya) >= 20000000 THEN 'Penyumbang Utama'
    WHEN SUM(k.biaya) >= 1000000 THEN 'Penyumbang Menengah'
    ELSE 'Penyumbang Kecil'
  END AS kategori_revenue
FROM dokter d
JOIN kunjungan k ON d.id = k.dokter_id
GROUP BY d.id, d.nama, d.spesialisasi
ORDER BY
  total_revenue DESC,
  nama ASC

-- 2.2 Tren revenue bulanan per tipe kunjungan
-- Revenue bulanan per tipe kunjungan dengan bulan sebagai kolom (pivot manual, Januari sampai April 2025).
-- tanggal_kunjungan bertipe TEXT berformat YYYY-MM-DD, jadi tiap bulan dicocokkan dengan LIKE.
-- Label tren hanya membandingkan Februari dengan Maret, karena data April baru sampai tanggal 8
-- dan belum satu bulan penuh.

SELECT
  k.tipe_kunjungan,
  SUM(CASE WHEN k.tanggal_kunjungan LIKE '2025-01%' THEN k.biaya ELSE 0 END) AS jan,
  SUM(CASE WHEN k.tanggal_kunjungan LIKE '2025-02%' THEN k.biaya ELSE 0 END) AS feb,
  SUM(CASE WHEN k.tanggal_kunjungan LIKE '2025-03%' THEN k.biaya ELSE 0 END) AS mar,
  SUM(CASE WHEN k.tanggal_kunjungan LIKE '2025-04%' THEN k.biaya ELSE 0 END) AS apr,
  SUM(k.biaya) AS total,
  CASE
    WHEN SUM(CASE WHEN k.tanggal_kunjungan LIKE '2025-02%' THEN k.biaya ELSE 0 END) < SUM(CASE WHEN k.tanggal_kunjungan LIKE '2025-03%' THEN k.biaya ELSE 0 END) THEN 'Naik'
    WHEN SUM(CASE WHEN k.tanggal_kunjungan LIKE '2025-02%' THEN k.biaya ELSE 0 END) > SUM(CASE WHEN k.tanggal_kunjungan LIKE '2025-03%' THEN k.biaya ELSE 0 END) THEN 'Turun'
    ELSE 'Stabil'
  END AS tren_feb_ke_mar
FROM kunjungan k
GROUP BY 1
ORDER BY total DESC


-- 2.3 Tingkat biaya dan tagihan pasien mandiri
-- Revenue per tingkat biaya: Gratis (0), Kecil (di bawah 1 juta), Menengah (1 juta sampai di bawah 10 juta),
-- dan Besar (10 juta ke atas). Per tingkat: jumlah kunjungan, total revenue, dan porsi dari
-- pasien bayar mandiri (tanpa nomor asuransi), karena bagian itu paling rawan tunggakan.
-- GROUP BY 1 memakai ulang bucketing CASE sehingga tidak perlu ditulis dua kali.
-- Tingkat dengan total revenue 0 menghasilkan NULL untuk persen_mandiri (NULLIF).

SELECT
  CASE
    WHEN k.biaya = 0 THEN 'Gratis'
    WHEN k.biaya < 1000000 THEN 'Kecil'
    WHEN k.biaya < 10000000 THEN 'Menengah'
    ELSE 'Besar'
  END AS tier,
  COUNT(k.id) AS jml,
  SUM(k.biaya) AS total,
  COUNT(CASE WHEN p.no_asuransi IS NULL THEN 1 END) AS jml_mandiri,
  SUM(CASE WHEN p.no_asuransi IS NULL THEN k.biaya ELSE 0 END) AS revenue_mandiri,
  ROUND(100.0 * SUM(CASE WHEN p.no_asuransi IS NULL THEN k.biaya ELSE 0 END) / NULLIF(SUM(k.biaya), 0), 1) AS persen_mandiri
FROM kunjungan k
JOIN pasien p ON k.pasien_id = p.id
GROUP BY 1
ORDER BY total DESC



/* ==========================================================
   SKENARIO 3: Scoring dan Segmentasi Pasien
   Brief dari Tim Layanan Pasien
   ========================================================== */

-- 3.1 Profil pasien dan program yang cocok
-- Profil setiap pasien yang pernah berkunjung minimal sekali: jenis jaminan, jumlah kunjungan,
-- total biaya, segmen frekuensi, dan program yang paling cocok.
-- Urutan aturan program adalah urutan prioritasnya: pasien yang sering berkunjung dan biayanya
-- besar dicek lebih dulu, lalu pasien berulang, lalu pasien mandiri.

SELECT
  p.nama,
  CASE
    WHEN p.no_asuransi IS NULL THEN 'Mandiri'
    WHEN p.no_asuransi LIKE 'BPJS%' THEN 'BPJS'
    ELSE 'Asuransi Swasta'
  END AS jaminan,
  COUNT(k.id) AS jml_kunjungan,
  SUM(k.biaya) AS total_biaya,
  CASE
    WHEN COUNT(k.id) >= 3 THEN 'Pasien Sering'
    WHEN COUNT(k.id) = 2 THEN 'Pasien Berulang'
    WHEN COUNT(k.id) = 1 THEN 'Pasien Sekali'
  END AS frekuensi,
  CASE
    WHEN COUNT(k.id) >= 2 AND SUM(k.biaya) >= 10000000 THEN 'Program Pasien Kronis'
    WHEN COUNT(k.id) >= 2 THEN 'Program Loyalitas'
    WHEN p.no_asuransi IS NULL THEN 'Edukasi Asuransi'
    ELSE 'Reguler'
  END AS program
FROM pasien p
JOIN kunjungan k ON p.id = k.pasien_id
GROUP BY p.id, p.nama, p.no_asuransi
ORDER BY
  total_biaya DESC,
  nama ASC


-- 3.2 Skor keparahan dan daftar tindak lanjut
-- Skor keparahan per kunjungan. Tiap diagnosa dihitung Ringan = 1, Sedang = 2, Berat = 3,
-- dan satu kunjungan bisa punya beberapa diagnosa, jadi skornya dijumlahkan.
-- Hanya dua jenis kunjungan yang ditampilkan: skor 4 ke atas (perlu case manager)
-- dan kunjungan tanpa diagnosa sama sekali (datanya harus dilengkapi).
-- LEFT JOIN mempertahankan kunjungan tanpa diagnosa, COALESCE mengubah skor NULL mereka jadi 0,
-- dan HAVING menyaring grup setelah skor dihitung.

SELECT
  k.id,
  p.nama AS pasien,
  k.tipe_kunjungan,
  COUNT(d.id) AS jml_diagnosa,
  COALESCE(
    SUM(
      CASE
        WHEN d.tingkat_keparahan = 'Ringan' THEN 1
        WHEN d.tingkat_keparahan = 'Sedang' THEN 2
        WHEN d.tingkat_keparahan = 'Berat' THEN 3
      END
    ), 0) AS skor_keparahan,
  IF(COUNT(d.id) = 0, 'Lengkapi Diagnosa', 'Tunjuk Case Manager') AS tindak_lanjut
FROM kunjungan k
LEFT JOIN diagnosa d ON k.id = d.kunjungan_id
JOIN pasien p ON k.pasien_id = p.id
GROUP BY
  k.id,
  p.nama, 
  k.tipe_kunjungan
HAVING
    SUM(
      CASE
        WHEN d.tingkat_keparahan = 'Ringan' THEN 1
        WHEN d.tingkat_keparahan = 'Sedang' THEN 2
        WHEN d.tingkat_keparahan = 'Berat' THEN 3
      END
    ) >= 4
  OR COUNT(d.id) = 0
ORDER BY
  skor_keparahan DESC,
  k.id


-- 3.3 Ringkasan eksekutif per kelompok umur
-- Ringkasan eksekutif per kelompok umur pasien (Anak, Remaja, Dewasa, Lansia), untuk slide manajemen.
-- Per kelompok: jumlah kunjungan, total revenue, rata-rata biaya per kunjungan berbayar,
-- persentase kasus berat (Rawat Inap + IGD), persentase kunjungan pasien mandiri,
-- dan rekomendasi program.
-- Rekomendasi membandingkan persentase yang belum dibulatkan, sesuai permintaan brief.
-- JOIN biasa dipakai agar hanya kunjungan nyata yang dihitung, pasien tanpa kunjungan tidak ikut.

SELECT
  CASE
    WHEN p.umur <= 12 THEN 'Anak'
    WHEN p.umur <= 17 THEN 'Remaja'
    WHEN p.umur <= 59 THEN 'Dewasa'
    ELSE 'Lansia'
  END AS kelompok_umur,
  COUNT(k.id) AS jml_kunjungan,
  SUM(k.biaya) AS total_revenue,
  ROUND(AVG(NULLIF(k.biaya, 0)), 0) AS rata_biaya_berbayar,
  ROUND(100.0 * COUNT(CASE WHEN k.tipe_kunjungan IN ('Rawat Inap', 'IGD') THEN 1 END) / NULLIF(COUNT(k.id), 0), 1) AS persen_inap_igd,
  ROUND(100.0 * COUNT(CASE WHEN p.no_asuransi IS NULL THEN 1 END) / NULLIF(COUNT(k.id), 0), 1) AS persen_mandiri,
  CASE
    WHEN 100.0 * COUNT(CASE WHEN k.tipe_kunjungan IN ('Rawat Inap', 'IGD') THEN 1 END) / NULLIF(COUNT(k.id), 0) >= 50 THEN 'Program Pencegahan'
    WHEN 100.0 * COUNT(CASE WHEN p.no_asuransi IS NULL THEN 1 END) / NULLIF(COUNT(k.id), 0) >= 25 THEN 'Edukasi Asuransi'
    ELSE 'Pertahankan Layanan'
  END AS rekomendasi
FROM pasien p
JOIN kunjungan k ON p.id = k.pasien_id
GROUP BY 1
ORDER BY total_revenue DESC
