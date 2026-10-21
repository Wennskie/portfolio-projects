/*

Studi Kasus Analitik Marketplace E-Commerce

Tabel yang dipakai: pelanggan, penjual, produk, kategori, pesanan, detail_pesanan, review

Catatan: Nama tabel dan kolom memakai bahasa Indonesia, sesuai dataset yang disediakan.

Kolom yang dipakai di query (dataset-nya tidak disertakan di repositori ini):

  pelanggan       (id, nama, kota, tanggal_daftar)                                 -- tanggal_daftar bertipe TEXT
  penjual         (id, nama, kota, referrer_id)                                    -- referrer_id NULL = penjual root
  produk          (id, nama_produk, penjual_id, kategori_id, harga, stok, is_aktif)
  kategori        (id, nama_kategori, parent_id)                                   -- parent_id NULL = kategori root
  pesanan         (id, pelanggan_id, tanggal_pesanan, status, total)               -- tanggal_pesanan bertipe TEXT, status 'selesai' dipakai sebagai pesanan sukses
  detail_pesanan  (pesanan_id, produk_id, jumlah, harga_satuan)
  review          (id, produk_id, rating)

Skill yang dipakai: Subquery (di WHERE, SELECT, dan FROM), Correlated Subquery, CTE (termasuk beberapa CTE yang saling bergantung), Recursive CTE, EXISTS dan NOT EXISTS, CROSS JOIN, Agregasi Kondisional, Running Total, Fungsi Tanggal (CAST, INTERVAL, STRFTIME), Penanganan NULL (COALESCE)

Tools: SQL

*/


/* ==========================================================
   SKENARIO 1: Analisis Pelanggan dan Penjual
   Brief dari tim CRM, Head of Marketplace, tim Retention, dan tim Partnership
   ========================================================== */

-- 1.1 Segmentasi pelanggan berdasarkan spending (tim CRM)
-- Total belanja tiap pelanggan dari pesanan berstatus selesai, dibandingkan dengan
-- rata-rata total belanja per pelanggan (bukan per pesanan).
-- Dua CTE: yang pertama menghitung total per pelanggan, yang kedua menghitung rata-ratanya.
-- CROSS JOIN menempelkan rata-rata itu ke setiap baris untuk menentukan segmen.

WITH
total_pelanggan AS (
  SELECT
    pes.pelanggan_id,
    SUM(total) AS total_belanja
  FROM pesanan pes
  WHERE status = 'selesai'
  GROUP BY pelanggan_id
),
avg_pelanggan AS (
  SELECT AVG(total_belanja) AS avg_belanja
  FROM total_pelanggan
)
SELECT
  pel.nama,
  tp.total_belanja,
  CASE
    WHEN tp.total_belanja > ap.avg_belanja THEN 'High Spender'
    ELSE 'Regular'
  END AS segmen
FROM pelanggan pel
JOIN total_pelanggan tp ON pel.id = tp.pelanggan_id
CROSS JOIN avg_pelanggan ap
ORDER BY tp.total_belanja DESC;


-- 1.2 Ranking penjual berdasarkan revenue (Head of Marketplace)
-- Revenue tiap penjual dihitung dari detail_pesanan (jumlah x harga_satuan) pada pesanan selesai,
-- lalu dibandingkan dengan total revenue seluruh penjual untuk mendapatkan persentase kontribusi.
-- Polanya sama seperti 1.1: satu CTE per penjual, satu CTE untuk total, lalu CROSS JOIN.

WITH
total_penjual AS (
  SELECT
    pro.penjual_id,
    SUM(det.jumlah * det.harga_satuan) AS total_revenue
  FROM detail_pesanan det
  JOIN produk pro ON pro.id = det.produk_id
  JOIN pesanan pes ON pes.id = det.pesanan_id
  WHERE pes.status = 'selesai'
  GROUP BY pro.penjual_id
),
total_semua AS (
  SELECT SUM(total_revenue) AS all_revenue
  FROM total_penjual
)
SELECT
  pen.nama AS nama_penjual,
  tp.total_revenue,
  ROUND(100.0 * tp.total_revenue / ts.all_revenue, 1) AS persen_kontribusi
FROM penjual pen
JOIN total_penjual tp ON tp.penjual_id = pen.id
CROSS JOIN total_semua ts
ORDER BY tp.total_revenue DESC;


-- 1.3 Pelanggan tidak aktif (tim Retention)
-- Pelanggan yang belum pernah memesan, serta pelanggan yang pesanan terakhirnya lebih dari 60 hari
-- sebelum pesanan terbaru di seluruh marketplace (bukan dari hari ini).
-- tanggal_pesanan bertipe TEXT, jadi di-CAST ke DATE lebih dulu.
-- LEFT JOIN menjaga pelanggan yang tidak punya pesanan tetap muncul.

WITH
max_pelanggan AS (
  SELECT
    pes.pelanggan_id,
    MAX(CAST(pes.tanggal_pesanan AS DATE)) AS last_pesanan
  FROM pesanan pes
  GROUP BY pes.pelanggan_id
),
max_marketplace AS (
  SELECT
    MAX(CAST(pes.tanggal_pesanan AS DATE)) AS max_pesanan
  FROM pesanan pes
)
SELECT
  pel.nama,
  pel.kota,
  CASE
    WHEN mp.last_pesanan IS NULL THEN 'Belum Pernah Pesan'
    WHEN mp.last_pesanan < (mm.max_pesanan - INTERVAL 60 DAY) THEN 'Lama Tidak Pesan'
  END AS status_aktivitas
FROM pelanggan pel
LEFT JOIN max_pelanggan mp ON mp.pelanggan_id = pel.id
CROSS JOIN max_marketplace mm
WHERE mp.last_pesanan IS NULL OR mp.last_pesanan < (mm.max_pesanan - INTERVAL 60 DAY)
ORDER BY status_aktivitas, pel.nama;


-- 1.4 Referral chain penjual (tim Partnership)
-- Rantai referral dari penjual root (yang tidak di-refer siapa pun) beserta level kedalamannya.
-- Recursive CTE: base case adalah penjual root dengan level 0, lalu recursive member
-- menelusuri penjual yang di-refer dan menambah level 1 di setiap langkah.
-- CAST(NULL AS VARCHAR) menyamakan tipe kolom direferensikan_oleh dengan recursive member.

WITH RECURSIVE referral_chain AS (
  SELECT
    id,
    nama AS nama_penjual,
    kota,
    0 AS level_referral,
    CAST(NULL AS VARCHAR) AS direferensikan_oleh
  FROM penjual
  WHERE referrer_id IS NULL

  UNION ALL

  SELECT
    pen.id,
    pen.nama AS nama_penjual,
    pen.kota,
    rc.level_referral + 1,
    rc.nama_penjual AS direferensikan_oleh
  FROM penjual pen
  JOIN referral_chain rc ON rc.id = pen.referrer_id
)
SELECT
  nama_penjual,
  kota,
  level_referral,
  direferensikan_oleh
FROM referral_chain
ORDER BY level_referral, nama_penjual;


/* ==========================================================
   SKENARIO 2: Analisis Produk dan Kategori
   Brief dari Product Manager, CFO, tim Inventory, dan tim Data Science
   ========================================================== */

-- 2.1 Produk terlaris per kategori (Product Manager)
-- Satu produk terlaris di setiap kategori leaf (kategori tanpa sub-kategori), berdasarkan
-- total unit terjual dari pesanan selesai.
-- Kategori leaf difilter dengan subquery NOT IN. NULL pada parent_id dikeluarkan lebih dulu
-- supaya NOT IN tidak menghasilkan kosong. NOT EXISTS (correlated subquery) memastikan tidak ada
-- produk lain di kategori yang sama dengan penjualan lebih tinggi. Jika seri, dipilih yang harganya lebih mahal.

WITH penjualan_produk AS (
  SELECT
    pro.id,
    pro.kategori_id,
    pro.nama_produk,
    pro.harga,
    SUM(det.jumlah) AS total_terjual
  FROM produk pro
  JOIN detail_pesanan det ON det.produk_id = pro.id
  JOIN pesanan pes ON pes.id = det.pesanan_id
  WHERE pes.status = 'selesai'
    AND pro.kategori_id NOT IN (SELECT parent_id FROM kategori WHERE parent_id IS NOT NULL)
  GROUP BY pro.id, pro.kategori_id, pro.nama_produk, pro.harga
)
SELECT
  k.nama_kategori,
  pp.nama_produk,
  pp.total_terjual
FROM kategori k
JOIN penjualan_produk pp ON pp.kategori_id = k.id
WHERE NOT EXISTS (
  SELECT 1
  FROM penjualan_produk pp2
  WHERE pp2.kategori_id = pp.kategori_id
    AND (pp2.total_terjual > pp.total_terjual
         OR (pp2.total_terjual = pp.total_terjual AND pp2.harga > pp.harga))
)
ORDER BY pp.total_terjual DESC, k.nama_kategori;


-- 2.2 Revenue per kategori root (CFO)
-- Recursive CTE menelusuri hierarki kategori dari root sampai leaf sambil membawa nama kategori root-nya.
-- Revenue semua sub-kategori lalu dijumlahkan ke kategori utamanya.
-- Revenue dihitung dari detail_pesanan (jumlah x harga_satuan), bukan dari kolom total di pesanan.

WITH RECURSIVE hierarki_kategori AS (
  SELECT
    id,
    nama_kategori,
    id AS id_utama,
    nama_kategori AS kategori_utama
  FROM kategori
  WHERE parent_id IS NULL

  UNION ALL

  SELECT
    k.id,
    k.nama_kategori,
    hk.id_utama,
    hk.kategori_utama
  FROM kategori k
  JOIN hierarki_kategori hk ON k.parent_id = hk.id
)
SELECT
  hk.kategori_utama,
  SUM(det.jumlah * det.harga_satuan) AS total_revenue
FROM hierarki_kategori hk
JOIN produk pro ON pro.kategori_id = hk.id
JOIN detail_pesanan det ON det.produk_id = pro.id
JOIN pesanan pes ON pes.id = det.pesanan_id
WHERE pes.status = 'selesai'
GROUP BY hk.kategori_utama
ORDER BY total_revenue DESC;


-- 2.3 Produk stok tinggi tapi penjualan rendah (tim Inventory)
-- Produk aktif yang belum pernah terjual, atau penjualannya di bawah rata-rata unit terjual.
-- Rata-rata dihitung di CTE dari produk yang pernah terjual. LEFT JOIN dan COALESCE
-- memunculkan produk tanpa penjualan dengan total 0.

WITH
produk_terjual AS (
  SELECT
    pro.id,
    SUM(det.jumlah) AS total_terjual
  FROM produk pro
  JOIN detail_pesanan det ON det.produk_id = pro.id
  JOIN pesanan pes ON pes.id = det.pesanan_id
  WHERE pes.status = 'selesai'
  GROUP BY pro.id
),
avg_produk AS (
  SELECT AVG(total_terjual) AS avg_terjual
  FROM produk_terjual
)
SELECT
  pro.nama_produk,
  pro.stok,
  COALESCE(pt.total_terjual, 0) AS total_terjual,
  CASE
    WHEN COALESCE(pt.total_terjual, 0) = 0 THEN 'Belum Terjual'
    WHEN pt.total_terjual < ap.avg_terjual THEN 'Di Bawah Rata-Rata'
  END AS status_penjualan
FROM produk pro
LEFT JOIN produk_terjual pt ON pt.id = pro.id
CROSS JOIN avg_produk ap
WHERE (COALESCE(pt.total_terjual, 0) = 0 OR pt.total_terjual < ap.avg_terjual)
  AND pro.is_aktif = TRUE
ORDER BY pro.stok DESC;


-- 2.4 Rating review dan penjualan (tim Data Science)
-- Untuk produk yang punya review dan pernah terjual: rata-rata rating, jumlah review,
-- total unit terjual, dan kategori rating.
-- Penjualan dan review diagregasi di CTE terpisah, jadi barisnya tidak terduplikasi saat digabung.

WITH
penjualan_produk AS (
  SELECT
    pro.id,
    SUM(det.jumlah) AS total_terjual
  FROM produk pro
  JOIN detail_pesanan det ON det.produk_id = pro.id
  JOIN pesanan pes ON pes.id = det.pesanan_id
  WHERE pes.status = 'selesai'
  GROUP BY pro.id
),
review_produk AS (
  SELECT
    pro.id,
    ROUND(AVG(r.rating), 1) AS avg_rating,
    COUNT(r.id) AS jumlah_review
  FROM review r
  JOIN produk pro ON pro.id = r.produk_id
  GROUP BY pro.id
)
SELECT
  pro.nama_produk,
  rp.avg_rating,
  rp.jumlah_review,
  pp.total_terjual,
  CASE
    WHEN rp.avg_rating >= 4 THEN 'Tinggi (4-5)'
    WHEN rp.avg_rating >= 3 THEN 'Sedang (3-3.9)'
    ELSE 'Rendah (1-2.9)'
  END AS kategori_rating
FROM produk pro
JOIN penjualan_produk pp ON pp.id = pro.id
JOIN review_produk rp ON rp.id = pro.id
ORDER BY rp.avg_rating DESC, pp.total_terjual DESC;


/* ==========================================================
   SKENARIO 3: Laporan Manajemen
   Brief dari CFO, VP of Marketplace, Head of Growth, dan CEO
   ========================================================== */

-- 3.1 Trend bulanan dengan running total (CFO)
-- Revenue dan jumlah pesanan selesai per bulan (format YYYY-MM), beserta akumulasi revenue
-- dari bulan pertama. Running total memakai correlated subquery yang menjumlahkan semua bulan
-- sampai bulan berjalan. Format YYYY-MM bisa dibandingkan sebagai teks.

WITH penjualan_bulanan AS (
  SELECT
    strftime(CAST(tanggal_pesanan AS DATE), '%Y-%m') AS bulan,
    SUM(total) AS revenue_bulanan,
    COUNT(id) AS jumlah_pesanan
  FROM pesanan
  WHERE status = 'selesai'
  GROUP BY bulan
)
SELECT
  pb1.bulan,
  pb1.revenue_bulanan,
  pb1.jumlah_pesanan,
  (
    SELECT SUM(pb2.revenue_bulanan)
    FROM penjualan_bulanan pb2
    WHERE pb2.bulan <= pb1.bulan
  ) AS running_total
FROM penjualan_bulanan pb1
ORDER BY pb1.bulan;


-- 3.2 Scorecard penjual (VP of Marketplace)
-- Jumlah produk aktif, total revenue, rata-rata rating, dan pelanggan unik untuk setiap penjual.
-- Tiap aspek diagregasi di CTE sendiri, lalu digabung dengan LEFT JOIN ke penjual agar penjual
-- tanpa penjualan tetap tampil. COALESCE mengganti NULL menjadi 0, sedangkan rating dibiarkan NULL
-- jika belum ada review.

WITH
produk_penjual AS (
  SELECT
    pro.penjual_id,
    COUNT(pro.id) AS jumlah_produk
  FROM produk pro
  WHERE pro.is_aktif = TRUE
  GROUP BY pro.penjual_id
),
penjualan_penjual AS (
  SELECT
    pro.penjual_id,
    SUM(det.jumlah * det.harga_satuan) AS total_revenue,
    COUNT(DISTINCT pes.pelanggan_id) AS jumlah_pelanggan_unik
  FROM produk pro
  JOIN detail_pesanan det ON det.produk_id = pro.id
  JOIN pesanan pes ON pes.id = det.pesanan_id
  WHERE pes.status = 'selesai'
  GROUP BY pro.penjual_id
),
review_penjual AS (
  SELECT
    pro.penjual_id,
    ROUND(AVG(r.rating), 1) AS avg_rating_review
  FROM review r
  JOIN produk pro ON pro.id = r.produk_id
  GROUP BY pro.penjual_id
)
SELECT
  pen.nama AS nama_penjual,
  COALESCE(pp.jumlah_produk, 0) AS jumlah_produk,
  COALESCE(ppe.total_revenue, 0) AS total_revenue,
  rp.avg_rating_review,
  COALESCE(ppe.jumlah_pelanggan_unik, 0) AS jumlah_pelanggan_unik
FROM penjual pen
LEFT JOIN produk_penjual pp ON pp.penjual_id = pen.id
LEFT JOIN penjualan_penjual ppe ON ppe.penjual_id = pen.id
LEFT JOIN review_penjual rp ON rp.penjual_id = pen.id
ORDER BY COALESCE(ppe.total_revenue, 0) DESC;


-- 3.3 Cohort pelanggan berdasarkan bulan registrasi (Head of Growth)
-- Pelanggan dikelompokkan per bulan mereka mendaftar, lalu dihitung jumlah pelanggan,
-- berapa yang pernah membeli (status pesanan apa pun), dan revenue dari pesanan selesai.

WITH
cohort_pelanggan AS (
  SELECT
    strftime(CAST(tanggal_daftar AS DATE), '%Y-%m') AS cohort_bulan,
    COUNT(id) AS jumlah_pelanggan
  FROM pelanggan
  GROUP BY strftime(CAST(tanggal_daftar AS DATE), '%Y-%m')
),
aktivitas_pelanggan AS (
  SELECT
    strftime(CAST(pel.tanggal_daftar AS DATE), '%Y-%m') AS cohort_bulan,
    COUNT(DISTINCT pel.id) AS pelanggan_yang_beli,
    SUM(CASE WHEN pes.status = 'selesai' THEN pes.total ELSE 0 END) AS total_revenue
  FROM pelanggan pel
  JOIN pesanan pes ON pes.pelanggan_id = pel.id
  GROUP BY strftime(CAST(pel.tanggal_daftar AS DATE), '%Y-%m')
)
SELECT
  cp.cohort_bulan,
  cp.jumlah_pelanggan,
  COALESCE(ap.pelanggan_yang_beli, 0) AS pelanggan_yang_beli,
  COALESCE(ap.total_revenue, 0) AS total_revenue
FROM cohort_pelanggan cp
LEFT JOIN aktivitas_pelanggan ap ON ap.cohort_bulan = cp.cohort_bulan
ORDER BY cp.cohort_bulan;


-- 3.4 Ringkasan eksekutif marketplace (CEO)
-- Satu baris berisi metrik utama marketplace. Tiap metrik dihitung di CTE sendiri
-- (masing-masing menghasilkan satu baris), lalu digabung dengan CROSS JOIN.
-- NOT EXISTS dipakai untuk menghitung pelanggan yang belum pernah memesan dan produk yang belum pernah di-review.

WITH
cte_penjual AS (
  SELECT
    COUNT(id) AS total_penjual
  FROM penjual
),
cte_pelanggan AS (
  SELECT
    COUNT(pel.id) AS total_pelanggan,
    COUNT(CASE WHEN NOT EXISTS (SELECT 1 FROM pesanan pes WHERE pes.pelanggan_id = pel.id) THEN pel.id END) AS pelanggan_tanpa_pesanan
  FROM pelanggan pel
),
cte_produk AS (
  SELECT
    COUNT(CASE WHEN pro.is_aktif = TRUE THEN pro.id END) AS total_produk_aktif,
    COUNT(CASE WHEN NOT EXISTS (SELECT 1 FROM review r WHERE r.produk_id = pro.id) THEN pro.id END) AS produk_tanpa_review
  FROM produk pro
),
cte_pesanan AS (
  SELECT
    COUNT(id) AS total_pesanan_selesai,
    SUM(total) AS total_revenue,
    ROUND(AVG(total), 0) AS avg_order_value
  FROM pesanan
  WHERE status = 'selesai'
)
SELECT
  cpen.total_penjual,
  cpel.total_pelanggan,
  cpro.total_produk_aktif,
  cpes.total_pesanan_selesai,
  cpes.total_revenue,
  cpes.avg_order_value,
  cpel.pelanggan_tanpa_pesanan,
  cpro.produk_tanpa_review
FROM cte_penjual cpen
CROSS JOIN cte_pelanggan cpel
CROSS JOIN cte_produk cpro
CROSS JOIN cte_pesanan cpes;
