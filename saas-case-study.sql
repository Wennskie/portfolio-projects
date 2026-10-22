/*

Studi Kasus Analitik Bisnis SaaS

Tabel yang dipakai: pengguna, langganan, pembayaran, aktivitas, tiket_support

Catatan: Nama tabel dan kolom memakai bahasa Indonesia, sesuai dataset yang disediakan.

Skema (dataset-nya tidak disertakan di repositori ini):

  pengguna       (id, nama, kota, email, tanggal_daftar)                                                  -- 15 baris
  langganan      (id, pengguna_id, plan, harga_bulanan, tanggal_mulai, tanggal_selesai, status)           -- 21 baris, plan: free, starter, pro, enterprise; status: aktif, expired, cancelled; tanggal_selesai NULL jika masih aktif
  pembayaran     (id, pengguna_id, langganan_id, jumlah, metode, tanggal_bayar)                           -- 35 baris, metode: transfer, kartu_kredit, ewallet
  aktivitas      (id, pengguna_id, tipe_aktivitas, tanggal_aktivitas)                                     -- 60 baris, tipe: login, buat_proyek, undang_anggota, selesai_tugas, export_laporan
  tiket_support  (id, pengguna_id, kategori, prioritas, status, tanggal_dibuat, tanggal_selesai)          -- 20 baris, tanggal_selesai NULL jika belum selesai

Semua kolom tanggal bertipe TEXT.

Skill yang dipakai: Window Function (LAG, RANK, DENSE_RANK, ROW_NUMBER, FIRST_VALUE, LAST_VALUE), Running Total dan Running MAX, Moving Average dengan Frame Clause (ROWS BETWEEN), PARTITION BY, CTE, Join, Fungsi Tanggal (SUBSTR, DATEDIFF)

Tools: SQL

*/


/* ==========================================================
   SKENARIO 1: Analisis Revenue dan Churn
   Brief dari CFO, CEO, dan tim Retention
   ========================================================== */

-- 1.1 MoM growth dengan trend (CFO)
-- Laporan revenue bulanan: revenue bulan ini, revenue bulan lalu, pertumbuhan MoM dalam persen,
-- dan moving average 3 bulan. Revenue per bulan dihitung dulu di CTE (SUBSTR mengambil 'YYYY-MM'
-- dari tanggal bertipe TEXT). LAG mengambil revenue bulan sebelumnya, dan frame
-- ROWS BETWEEN 2 PRECEDING AND CURRENT ROW membuat moving average dari bulan itu dan dua bulan
-- sebelumnya. Pada dua bulan pertama jendelanya belum penuh, jadi rata-ratanya dihitung dari data yang ada.

WITH revenue_bulanan AS (
  SELECT
    SUBSTR(tanggal_bayar, 1, 7) AS bulan,
    SUM(jumlah) AS revenue
  FROM pembayaran
  GROUP BY SUBSTR(tanggal_bayar, 1, 7)
)
SELECT
  bulan,
  revenue,
  LAG(revenue) OVER (ORDER BY bulan) AS revenue_lalu,
  ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY bulan)) / LAG(revenue) OVER (ORDER BY bulan), 2) AS growth_persen,
  ROUND(AVG(revenue) OVER (ORDER BY bulan ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 0) AS moving_avg_3bln
FROM revenue_bulanan
ORDER BY bulan;


-- 1.2 Ranking kontribusi revenue per pengguna (CEO)
-- Ranking pengguna berdasarkan total pembayaran, lengkap dengan nama, kota, dan persentase
-- kontribusi ke grand total. RANK() memberi peringkat (nilai yang sama mendapat peringkat sama),
-- dan SUM(...) OVER () tanpa PARTITION menghitung grand total di setiap baris tanpa perlu CROSS JOIN.

WITH pembayaran_pengguna AS (
  SELECT
    pem.pengguna_id,
    pen.nama,
    pen.kota,
    SUM(pem.jumlah) AS total_bayar
  FROM pembayaran pem
  JOIN pengguna pen ON pen.id = pem.pengguna_id
  GROUP BY pem.pengguna_id, pen.nama, pen.kota
)
SELECT
  pengguna_id,
  nama,
  kota,
  total_bayar,
  RANK() OVER (ORDER BY total_bayar DESC) AS ranking,
  ROUND(100.0 * total_bayar / SUM(total_bayar) OVER (), 2) AS persen_dari_total
FROM pembayaran_pengguna
ORDER BY ranking;


-- 1.3 Gap antar pembayaran sebagai indikator churn risk (tim Retention)
-- Selisih hari antara pembayaran sekarang dan pembayaran sebelumnya untuk setiap pengguna.
-- Gap lebih dari 60 hari patut dicurigai sebagai churn risk. LAG dengan PARTITION BY pengguna_id
-- mengambil tanggal pembayaran sebelumnya milik pengguna yang sama. Pembayaran pertama tiap pengguna
-- dikeluarkan karena belum punya pembayaran sebelumnya, dan hasilnya diurutkan dari gap terbesar.

WITH prev_payment AS (
  SELECT
    pem.pengguna_id,
    pen.nama,
    pen.kota,
    pem.tanggal_bayar,
    LAG(pem.tanggal_bayar) OVER (PARTITION BY pem.pengguna_id ORDER BY pem.tanggal_bayar) AS tanggal_bayar_lalu
  FROM pembayaran pem
  JOIN pengguna pen ON pen.id = pem.pengguna_id
),
with_gap AS (
  SELECT
    pengguna_id,
    nama,
    kota,
    tanggal_bayar,
    tanggal_bayar_lalu,
    DATEDIFF('day', tanggal_bayar_lalu::DATE, tanggal_bayar::DATE) AS gap_hari
  FROM prev_payment
  WHERE tanggal_bayar_lalu IS NOT NULL
)
SELECT
  pengguna_id,
  nama,
  kota,
  tanggal_bayar,
  tanggal_bayar_lalu,
  gap_hari
FROM with_gap
ORDER BY gap_hari DESC;


-- 1.4 Revenue kumulatif dan target (CFO)
-- Revenue bulanan, revenue kumulatif (running total), dan penanda apakah target kumulatif
-- Rp10.000.000 sudah tercapai. SUM(...) OVER (ORDER BY bulan) menjumlahkan semua bulan
-- dari awal sampai bulan berjalan.

WITH
pembayaran_bulanan AS (
  SELECT
    SUBSTR(tanggal_bayar, 1, 7) AS bulan,
    SUM(jumlah) AS revenue_bulan
  FROM pembayaran
  GROUP BY SUBSTR(tanggal_bayar, 1, 7)
),
with_kumulatif AS (
  SELECT
    bulan,
    revenue_bulan,
    SUM(revenue_bulan) OVER (ORDER BY bulan) AS revenue_kumulatif
  FROM pembayaran_bulanan
)
SELECT
  bulan,
  revenue_bulan,
  revenue_kumulatif,
  CASE
    WHEN revenue_kumulatif >= 10000000 THEN 'Ya'
    ELSE 'Belum'
  END AS target_tercapai
FROM with_kumulatif
ORDER BY bulan;


/* ==========================================================
   SKENARIO 2: Analisis Aktivitas dan Retensi
   Brief dari Product Manager, Growth team, Product team, dan VP Product
   ========================================================== */

-- 2.1 Aktivitas bulanan per pengguna dengan ranking (Product Manager)
-- Jumlah aktivitas tiap pengguna per bulan beserta rankingnya di bulan itu.
-- DENSE_RANK dengan PARTITION BY bulan membuat peringkat dimulai ulang setiap bulan,
-- dan peringkat berikutnya tidak melompat jika ada nilai yang sama.

WITH aktivitas_pengguna_bulanan AS (
  SELECT
    SUBSTR(tanggal_aktivitas, 1, 7) AS bulan,
    pengguna_id,
    COUNT(*) AS jumlah_aktivitas
  FROM aktivitas
  GROUP BY SUBSTR(tanggal_aktivitas, 1, 7), pengguna_id
)
SELECT
  bulan,
  pengguna_id,
  jumlah_aktivitas,
  DENSE_RANK() OVER (PARTITION BY bulan ORDER BY jumlah_aktivitas DESC) AS rank_di_bulan
FROM aktivitas_pengguna_bulanan
ORDER BY bulan, rank_di_bulan;


-- 2.2 Trend aktivitas bulanan (Growth team)
-- Total aktivitas per bulan, perbandingannya dengan bulan lalu (LAG),
-- dan moving average 3 bulan untuk melihat trend yang lebih halus.

WITH aktivitas_bulanan AS (
  SELECT
    SUBSTR(tanggal_aktivitas, 1, 7) AS bulan,
    COUNT(*) AS total_aktivitas
  FROM aktivitas
  GROUP BY SUBSTR(tanggal_aktivitas, 1, 7)
)
SELECT
  bulan,
  total_aktivitas,
  LAG(total_aktivitas) OVER (ORDER BY bulan) AS aktivitas_bulan_lalu,
  ROUND(AVG(total_aktivitas) OVER (ORDER BY bulan ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 0) AS moving_avg_3bln
FROM aktivitas_bulanan
ORDER BY bulan;


-- 2.3 Lifecycle span pengguna (Product team)
-- Rentang waktu (lifecycle span) antara aktivitas pertama dan terakhir tiap pengguna.
-- FIRST_VALUE dan LAST_VALUE dipakai sebagai latihan window function. LAST_VALUE butuh frame
-- ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING, karena frame bawaan hanya sampai
-- baris saat ini dan akan mengembalikan nilai yang salah. SELECT DISTINCT menyisakan satu baris
-- per pengguna. (Hasil yang sama juga bisa didapat dengan MIN dan MAX plus GROUP BY.)

WITH aktivitas_pengguna AS (
  SELECT
    pengguna_id,
    FIRST_VALUE(tanggal_aktivitas) OVER (PARTITION BY pengguna_id ORDER BY tanggal_aktivitas) AS aktivitas_pertama,
    LAST_VALUE(tanggal_aktivitas) OVER (PARTITION BY pengguna_id ORDER BY tanggal_aktivitas ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS aktivitas_terakhir
  FROM aktivitas
)
SELECT DISTINCT
  pengguna_id,
  aktivitas_pertama,
  aktivitas_terakhir,
  DATEDIFF('day', aktivitas_pertama::DATE, aktivitas_terakhir::DATE) AS span_hari
FROM aktivitas_pengguna
ORDER BY span_hari DESC, aktivitas_pertama ASC;


-- 2.4 Top 3 pengguna paling aktif per bulan (VP Product)
-- Tiga pengguna paling aktif di setiap bulan untuk program reward, lengkap dengan nama.
-- ROW_NUMBER dengan PARTITION BY bulan memberi nomor urut per bulan, lalu rank_bulan <= 3 difilter.
-- Filter ini dilakukan di luar CTE yang menghitung ROW_NUMBER, karena window function
-- tidak bisa dipakai langsung di WHERE.

WITH
aktivitas_pengguna_bulanan AS (
  SELECT
    SUBSTR(a.tanggal_aktivitas, 1, 7) AS bulan,
    a.pengguna_id,
    pen.nama,
    COUNT(*) AS jumlah_aktivitas
  FROM aktivitas a
  JOIN pengguna pen ON pen.id = a.pengguna_id
  GROUP BY SUBSTR(a.tanggal_aktivitas, 1, 7), a.pengguna_id, pen.nama
),
ranked AS (
  SELECT
    bulan,
    nama,
    jumlah_aktivitas,
    ROW_NUMBER() OVER (PARTITION BY bulan ORDER BY jumlah_aktivitas DESC) AS rank_bulan
  FROM aktivitas_pengguna_bulanan
)
SELECT
  bulan,
  nama,
  jumlah_aktivitas,
  rank_bulan
FROM ranked
WHERE rank_bulan <= 3
ORDER BY bulan, rank_bulan;


/* ==========================================================
   SKENARIO 3: Laporan Manajemen
   Brief dari CEO, VP Sales, dan VP Engineering
   ========================================================== */

-- 3.1 Dashboard revenue executive (CEO)
-- Dashboard revenue bulanan dengan beberapa metrik sekaligus: revenue, revenue kumulatif,
-- revenue bulan lalu, pertumbuhan MoM, dan rekor revenue tertinggi sejauh ini (running MAX).
-- Revenue per bulan dihitung di CTE pertama, semua window function di CTE kedua,
-- dan persentase pertumbuhan dihitung di query akhir.

WITH
revenue_bulanan AS (
  SELECT
    SUBSTR(tanggal_bayar, 1, 7) AS bulan,
    SUM(jumlah) AS revenue
  FROM pembayaran
  GROUP BY SUBSTR(tanggal_bayar, 1, 7)
),
metrics_calc AS (
  SELECT
    bulan,
    revenue,
    SUM(revenue) OVER (ORDER BY bulan) AS revenue_kumulatif,
    LAG(revenue) OVER (ORDER BY bulan) AS revenue_lalu,
    MAX(revenue) OVER (ORDER BY bulan) AS rekor_tertinggi
  FROM revenue_bulanan
)
SELECT
  bulan,
  revenue,
  revenue_kumulatif,
  revenue_lalu,
  ROUND(100.0 * (revenue - revenue_lalu) / revenue_lalu, 2) AS growth_persen,
  rekor_tertinggi
FROM metrics_calc
ORDER BY bulan;


-- 3.2 Segmentasi plan dengan revenue share (VP Sales)
-- Revenue per paket langganan: total, peringkat, dan persentase kontribusi ke total revenue,
-- untuk mengevaluasi strategi harga. Revenue per plan dihitung di CTE (JOIN pembayaran dengan
-- langganan), lalu RANK dan SUM(...) OVER () menghitung peringkat dan porsinya.

WITH
plan_revenue AS (
  SELECT
    lan.plan,
    SUM(pem.jumlah) AS total_revenue
  FROM pembayaran pem
  JOIN langganan lan ON lan.id = pem.langganan_id
  GROUP BY lan.plan
),
ranked AS (
  SELECT
    plan,
    total_revenue,
    RANK() OVER (ORDER BY total_revenue DESC) AS ranking,
    ROUND(100.0 * total_revenue / SUM(total_revenue) OVER (), 2) AS persen_revenue
  FROM plan_revenue
)
SELECT
  plan,
  total_revenue,
  ranking,
  persen_revenue
FROM ranked
ORDER BY ranking;


-- 3.3 Tiket support: trend dan moving average (VP Engineering)
-- Laporan tiket support bulanan untuk perencanaan resource: jumlah tiket, jumlah bulan lalu,
-- moving average 3 bulan, dan jumlah kumulatif. Pembulatan moving average dilakukan di query akhir,
-- setelah window function selesai dihitung.

WITH
tiket_bulanan AS (
  SELECT
    SUBSTR(tanggal_dibuat, 1, 7) AS bulan,
    COUNT(*) AS jumlah_tiket
  FROM tiket_support
  GROUP BY SUBSTR(tanggal_dibuat, 1, 7)
),
tiket_metrics AS (
  SELECT
    bulan,
    jumlah_tiket,
    LAG(jumlah_tiket) OVER (ORDER BY bulan) AS tiket_bulan_lalu,
    AVG(jumlah_tiket) OVER (ORDER BY bulan ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS moving_avg_3bln,
    SUM(jumlah_tiket) OVER (ORDER BY bulan) AS tiket_kumulatif
  FROM tiket_bulanan
)
SELECT
  bulan,
  jumlah_tiket,
  tiket_bulan_lalu,
  ROUND(moving_avg_3bln, 0) AS moving_avg_3bln,
  tiket_kumulatif
FROM tiket_metrics
ORDER BY bulan;


-- 3.4 Pengguna teratas per kota (CEO)
-- Pengguna dengan total pembayaran tertinggi di setiap kota ("best customer per kota"),
-- beserta total pembayaran kota dan persentase kontribusinya.
-- SUM(...) OVER (PARTITION BY kota) menghitung total kota, dan ROW_NUMBER (PARTITION BY kota)
-- dipakai untuk memilih peringkat 1 di tiap kota.

WITH
pembayaran_pengguna AS (
  SELECT
    pem.pengguna_id,
    pen.kota,
    pen.nama,
    SUM(pem.jumlah) AS total_bayar
  FROM pembayaran pem
  JOIN pengguna pen ON pen.id = pem.pengguna_id
  GROUP BY pem.pengguna_id, pen.kota, pen.nama
),
per_kota AS (
  SELECT
    kota,
    nama,
    total_bayar,
    SUM(total_bayar) OVER (PARTITION BY kota) AS total_kota,
    ROW_NUMBER() OVER (PARTITION BY kota ORDER BY total_bayar DESC) AS ranking
  FROM pembayaran_pengguna
)
SELECT
  kota,
  nama,
  total_bayar,
  total_kota,
  ROUND(100.0 * total_bayar / total_kota, 2) AS persen_dari_kota
FROM per_kota
WHERE ranking <= 1
ORDER BY total_bayar DESC;
