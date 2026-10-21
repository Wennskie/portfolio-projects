/*

Studi Kasus Analitik Platform E-Learning

Tabel yang dipakai: mahasiswa, kursus, instruktur, kategori_kursus, pendaftaran, review

Catatan: Nama tabel dan kolom memakai bahasa Indonesia, sesuai dataset yang disediakan.

Skema (dataset-nya tidak disertakan di repositori ini):

  mahasiswa        (id, nama, kota, email, tanggal_daftar)                          -- 10 baris, tanggal_daftar bertipe TEXT
  instruktur       (id, nama, spesialisasi, tahun_bergabung)                        -- 5 baris
  kategori_kursus  (id, nama_kategori, deskripsi)                                   -- 4 baris: Data, Programming, Bisnis, Desain
  kursus           (id, judul, instruktur_id, kategori_id, harga, level, is_aktif)  -- 8 baris, level: pemula, menengah, lanjutan
  pendaftaran      (id, mahasiswa_id, kursus_id, tanggal_daftar, status, nilai)     -- 17 baris, status: aktif, selesai, batal; nilai NULL jika belum selesai atau batal
  review           (id, mahasiswa_id, kursus_id, rating, komentar, tanggal)         -- 13 baris, rating 1-5

Skill yang dipakai: Join (INNER dan LEFT), Anti-Join, Agregasi Kondisional (CASE WHEN), Penyaringan Grup (HAVING), Derived Table dan CROSS JOIN, CTE, Fungsi Tanggal (CAST, DATEDIFF), Penanganan NULL (COALESCE)

Tools: SQL

*/


/* ==========================================================
   SKENARIO 1: Laporan Semester
   Brief dari Kepala Akademik
   ========================================================== */

-- 1.1 Ringkasan pendaftaran per kursus
-- Total pendaftaran per kursus beserta rincian status aktif, selesai, dan batal.
-- Agregasi kondisional (COUNT + CASE WHEN) memecah status menjadi kolom,
-- jadi tidak perlu beberapa query terpisah.

SELECT
  k.judul,
  COUNT(p.id) AS total_pendaftaran,
  COUNT(CASE WHEN p.status = 'aktif' THEN 1 END) AS aktif,
  COUNT(CASE WHEN p.status = 'selesai' THEN 1 END) AS selesai,
  COUNT(CASE WHEN p.status = 'batal' THEN 1 END) AS batal
FROM pendaftaran p
JOIN kursus k ON p.kursus_id = k.id
GROUP BY k.id, 1
ORDER BY 2 DESC;


-- 1.2 Pendaftaran per kategori
-- Total pendaftaran valid (tanpa yang batal) per kategori, beserta jumlah kursus unik
-- dan rata-rata pendaftaran per kursus, untuk melihat kategori yang paling diminati.
-- Rata-rata dikali 1.0 supaya hasilnya desimal, bukan pembagian bilangan bulat.

SELECT
  kk.nama_kategori,
  COUNT(DISTINCT k.id) AS jumlah_kursus,
  COUNT(p.id) AS total_pendaftaran,
  ROUND(COUNT(p.id) * 1.0 / COUNT(DISTINCT k.id), 1) AS rata_rata_per_kursus
FROM pendaftaran p
JOIN kursus k ON p.kursus_id = k.id
JOIN kategori_kursus kk ON k.kategori_id = kk.id
WHERE p.status != 'batal'
GROUP BY kk.id, 1
ORDER BY 3 DESC;


-- 1.3 Kursus sepi pendaftaran
-- Semua kursus, termasuk yang belum punya pendaftaran sama sekali, jadi memakai LEFT JOIN
-- ke pendaftaran. HAVING menyaring kursus dengan pendaftaran kurang dari 2,
-- yaitu kandidat untuk ditutup atau diperbaiki.

SELECT
  k.judul,
  i.nama AS pengajar,
  k.is_aktif,
  COUNT(p.id) AS jumlah_pendaftaran
FROM kursus k
JOIN instruktur i ON k.instruktur_id = i.id
LEFT JOIN pendaftaran p ON p.kursus_id = k.id
GROUP BY k.id, 1, 2, 3
HAVING COUNT(p.id) < 2
ORDER BY 4, 1;


-- 1.4 Mahasiswa tanpa aktivitas
-- Mahasiswa yang belum pernah mendaftar kursus apa pun (anti-join): LEFT JOIN ke pendaftaran,
-- lalu WHERE p.id IS NULL untuk menyisakan yang tidak punya pasangan.
-- tanggal_daftar disimpan sebagai TEXT, jadi di-CAST ke DATE dulu sebelum dihitung
-- selisih harinya sampai tanggal acuan 2025-04-15 dengan DATEDIFF.

SELECT
  m.nama,
  m.email,
  m.kota,
  DATEDIFF('day', CAST(m.tanggal_daftar AS DATE), '2025-04-15') AS hari_sejak_daftar
FROM mahasiswa m
LEFT JOIN pendaftaran p ON m.id = p.mahasiswa_id
WHERE p.id IS NULL
ORDER BY 4 DESC;


/* ==========================================================
   SKENARIO 2: Evaluasi Instruktur
   Brief dari Head of People
   ========================================================== */

-- 2.1 Scorecard instruktur
-- Scorecard tiap instruktur: jumlah kursus, total mahasiswa, dan rata-rata rating.
-- Semua instruktur harus tampil, termasuk yang belum punya kursus, jadi memakai LEFT JOIN berantai.
-- Karena beberapa tabel digabung, jumlah kursus dan mahasiswa dihitung dengan COUNT(DISTINCT)
-- agar tidak ganda. Syarat pendaftaran bukan batal ditaruh di ON (bukan di WHERE)
-- supaya instruktur tanpa pendaftaran tetap muncul.

SELECT
  i.nama,
  COUNT(DISTINCT k.id) AS jumlah_kursus,
  COUNT(DISTINCT p.id) AS total_mahasiswa,
  ROUND(AVG(r.rating), 1) AS rata_rata_rating
FROM instruktur i
LEFT JOIN kursus k ON k.instruktur_id = i.id
LEFT JOIN pendaftaran p ON k.id = p.kursus_id AND p.status != 'batal'
LEFT JOIN review r ON r.kursus_id = k.id
GROUP BY i.id, 1
ORDER BY 3 DESC;


-- 2.2 Completion rate per instruktur
-- Persentase pendaftaran yang selesai dari total pendaftaran valid (tanpa batal) per instruktur.
-- 100.0 membuat hasilnya desimal, dan HAVING memastikan hanya instruktur dengan
-- pendaftaran valid yang dihitung, sehingga tidak ada pembagian dengan nol.

SELECT
  i.nama,
  COUNT(CASE WHEN p.status != 'batal' THEN 1 END) AS total_valid,
  COUNT(CASE WHEN p.status = 'selesai' THEN 1 END) AS total_selesai,
  ROUND(100.0 * COUNT(CASE WHEN p.status = 'selesai' THEN p.id END) / COUNT(CASE WHEN p.status != 'batal' THEN p.id END), 1) AS completion_rate
FROM instruktur i
JOIN kursus k ON k.instruktur_id = i.id
JOIN pendaftaran p ON k.id = p.kursus_id
GROUP BY i.id, 1
HAVING COUNT(CASE WHEN p.status != 'batal' THEN 1 END) > 0
ORDER BY 4 DESC;


-- 2.3 Perbandingan instruktur: mahasiswa per kursus
-- Rata-rata jumlah pendaftaran valid per kursus untuk tiap instruktur, untuk melihat
-- instruktur mana yang kursusnya paling diminati. LEFT JOIN ke pendaftaran supaya
-- kursus tanpa pendaftaran tetap terhitung di jumlah kursus.

SELECT
  i.nama,
  COUNT(DISTINCT k.id) AS jumlah_kursus,
  COUNT(CASE WHEN p.status != 'batal' THEN 1 END) AS total_pendaftaran_valid,
  ROUND(COUNT(CASE WHEN p.status != 'batal' THEN 1 END) / COUNT(DISTINCT k.id), 1) AS rata_rata_mahasiswa_per_kursus
FROM instruktur i
JOIN kursus k ON k.instruktur_id = i.id
LEFT JOIN pendaftaran p ON p.kursus_id = k.id
GROUP BY i.id, 1
ORDER BY 4 DESC;


-- 2.4 Instruktur dengan rating di atas rata-rata
-- Rata-rata rating tiap instruktur dibandingkan dengan rata-rata seluruh review di platform.
-- Rata-rata platform dihitung di derived table, lalu di-CROSS JOIN supaya angkanya
-- menempel di setiap baris. HAVING menyisakan instruktur yang ratingnya lebih tinggi.

SELECT
  i.nama,
  ROUND(AVG(r.rating), 1) AS rata_rata_rating,
  ROUND(plat.avg_rating, 1) AS rata_rata_platform
FROM instruktur i
JOIN kursus k ON k.instruktur_id = i.id
JOIN review r ON r.kursus_id = k.id
CROSS JOIN (SELECT AVG(rating) AS avg_rating FROM review) plat
GROUP BY i.id, 1, plat.avg_rating
HAVING AVG(r.rating) > plat.avg_rating
ORDER BY 2 DESC;


/* ==========================================================
   SKENARIO 3: Laporan Eksekutif
   Brief dari CEO
   ========================================================== */

-- 3.1 Revenue per kategori dan level
-- Total revenue (harga kursus x pendaftaran valid) untuk setiap kombinasi kategori dan level kursus.
-- CASE WHEN di dalam SUM dan COUNT mengeluarkan pendaftaran yang batal.

SELECT
  kk.nama_kategori,
  k.level,
  COUNT(DISTINCT k.id) AS jumlah_kursus,
  SUM(CASE WHEN p.status != 'batal' THEN k.harga ELSE 0 END) AS total_revenue,
  COUNT(CASE WHEN p.status != 'batal' THEN 1 END) AS jumlah_pendaftaran
FROM pendaftaran p
JOIN kursus k ON p.kursus_id = k.id
JOIN kategori_kursus kk ON k.kategori_id = kk.id
GROUP BY kk.id, 1, 2
ORDER BY 4 DESC;


-- 3.2 Top 3 mahasiswa paling aktif
-- Tiga mahasiswa dengan pendaftaran valid terbanyak (tanpa yang batal),
-- lengkap dengan rincian yang selesai dan yang masih aktif. LIMIT 3 mengambil tiga teratas.

SELECT
  m.nama,
  m.kota,
  COUNT(CASE WHEN p.status != 'batal' THEN 1 END) AS total_pendaftaran,
  COUNT(CASE WHEN p.status = 'selesai' THEN 1 END) AS total_selesai,
  COUNT(CASE WHEN p.status = 'aktif' THEN 1 END) AS total_aktif
FROM mahasiswa m
JOIN pendaftaran p ON m.id = p.mahasiswa_id
GROUP BY m.id, 1, 2
ORDER BY 3 DESC
LIMIT 3;


-- 3.3 Kursus yang perlu perhatian
-- Kursus yang bermasalah: rata-rata rating di bawah 4.0 ATAU tingkat pembatalan di atas 20%.
-- LEFT JOIN ke review karena tidak semua kursus punya review. HAVING menyaring
-- dua kondisi tersebut dengan OR.

SELECT
  k.judul,
  ROUND(AVG(r.rating), 1) AS rata_rata_rating,
  COUNT(DISTINCT p.id) AS total_pendaftaran,
  ROUND(100.0 * COUNT(DISTINCT CASE WHEN p.status = 'batal' THEN p.id END) / COUNT(DISTINCT p.id), 1) AS persen_batal
FROM kursus k
JOIN pendaftaran p ON k.id = p.kursus_id
LEFT JOIN review r ON k.id = r.kursus_id
GROUP BY k.id, 1
HAVING AVG(r.rating) < 4.0 OR 100.0 * COUNT(DISTINCT CASE WHEN p.status = 'batal' THEN p.id END) / COUNT(DISTINCT p.id) > 20
ORDER BY 1;


-- 3.4 Executive summary per kategori
-- Satu tabel ringkasan untuk setiap kategori: jumlah kursus, pendaftaran valid, revenue,
-- rata-rata rating, dan jumlah mahasiswa unik.
-- Pendaftaran dan review sama-sama one-to-many ke kursus. Kalau digabung langsung,
-- barisnya terduplikasi (fanout) dan revenue membengkak. Karena itu tiap tabel
-- diagregasi dulu di CTE masing-masing, lalu digabung ke kategori_kursus dengan LEFT JOIN
-- supaya kategori yang belum punya kursus tetap tampil.

WITH
kursus_agg AS (
  SELECT
    kategori_id,
    COUNT(id) AS jumlah_kursus
  FROM kursus
  GROUP BY kategori_id
),
pendaftaran_agg AS (
  SELECT
    k.kategori_id,
    COUNT(p.id) AS total_pendaftaran,
    SUM(k.harga) AS total_revenue,
    COUNT(DISTINCT p.mahasiswa_id) AS mahasiswa_unik
  FROM pendaftaran p
  JOIN kursus k ON k.id = p.kursus_id
  WHERE p.status != 'batal'
  GROUP BY k.kategori_id
),
review_agg AS (
  SELECT
    k.kategori_id,
    AVG(r.rating) AS rata_rata_rating
  FROM review r
  JOIN kursus k ON k.id = r.kursus_id
  GROUP BY k.kategori_id
)
SELECT
  kk.nama_kategori,
  COALESCE(jumlah_kursus, 0) AS jumlah_kursus,
  COALESCE(total_pendaftaran, 0) AS total_pendaftaran,
  COALESCE(total_revenue, 0) AS total_revenue,
  ROUND(rata_rata_rating, 1) AS rata_rata_rating,
  COALESCE(mahasiswa_unik, 0) AS mahasiswa_unik
FROM kategori_kursus kk
LEFT JOIN kursus_agg ka ON kk.id = ka.kategori_id
LEFT JOIN pendaftaran_agg pa ON kk.id = pa.kategori_id
LEFT JOIN review_agg ra ON kk.id = ra.kategori_id
ORDER BY 4 DESC;
