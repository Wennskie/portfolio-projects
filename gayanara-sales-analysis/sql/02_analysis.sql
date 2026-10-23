-- 02_analysis.sql
-- Analisis data Gayanara
-- Revenue = total_amount_idr dari pesanan yang tidak cancelled/returned

-- =======================================
-- 1. Tren revenue
-- =======================================

-- 1a. Revenue per tahun

WITH revenue_tahunan AS (
	SELECT
		TO_CHAR(order_date, 'YYYY') AS tahun,
		COUNT(*) AS jumlah_pesanan,
		SUM(total_amount_idr) AS revenue
	FROM orders_clean
	WHERE order_status NOT IN ('cancelled', 'returned')
	GROUP BY TO_CHAR(order_date, 'YYYY')
)
SELECT
	tahun,
	jumlah_pesanan,
	revenue,
	CASE
		WHEN tahun = '2025' THEN NULL
		ELSE ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY tahun))
		           / LAG(revenue) OVER (ORDER BY tahun), 0)
	END AS revenue_growth_persen
FROM revenue_tahunan
ORDER BY tahun;

-- Revenue naik setiap tahun: 2022 Rp198,8 jt --> 2023 Rp427,9 jt (+115%) --> 2024 Rp513,2 jt (+20%)
-- 2025 baru 2 bulan (Jan-Feb), jadi tidak bisa dibandingkan langsung dengan tahun penuh

-- 1b. Revenue per bulan

WITH revenue_bulanan AS (
	SELECT
		TO_CHAR(order_date, 'YYYY-MM') AS bulan,
		COUNT(*) AS jumlah_pesanan,
		SUM(total_amount_idr) AS revenue
	FROM orders_clean
	WHERE order_status NOT IN ('cancelled', 'returned')
	GROUP BY TO_CHAR(order_date, 'YYYY-MM')
)
SELECT
	bulan,
	jumlah_pesanan,
	revenue,
	ROUND(AVG(revenue) OVER (ORDER BY bulan ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 0) AS avg_revenue_3bulan
FROM revenue_bulanan
ORDER BY bulan;

-- Lonjakan besar terjadi di Januari 2023: Rp45,8 jt, lebih dari 2x lipat Desember 2022 (Rp19,3 jt)
-- Bulan tertinggi di seluruh data: Februari 2025
-- Tidak terlihat pola musiman: Nov-Des dan bulan Ramadan (perkiraan Apr 2022, Mar-Apr 2023,
-- Mar-Apr 2024) tidak lebih tinggi dari bulan lain

-- =======================================
-- 2. Kategori dan brand terlaris
-- =======================================

-- Memakai penjualan kotor (subtotal_idr, sebelum diskon), karena diskon dicatat
-- per pesanan sehingga tidak bisa dibagi ke masing-masing item.

-- 2a. Penjualan per kategori

SELECT
	pc.category,
	SUM(oi.quantity) AS unit_terjual,
	SUM(oi.subtotal_idr) AS penjualan_kotor,
	ROUND(100.0 * SUM(oi.subtotal_idr) / SUM(SUM(oi.subtotal_idr)) OVER (), 1) AS persen_penjualan,
	COUNT(DISTINCT oi.product_id) AS jumlah_produk,
	ROUND(1.0 * SUM(oi.subtotal_idr) / COUNT(DISTINCT oi.product_id), 0) AS penjualan_per_produk
FROM order_items oi
JOIN orders_clean oc ON oc.order_id = oi.order_id
JOIN products_clean pc ON pc.product_id = oi.product_id
WHERE oc.order_status NOT IN ('cancelled', 'returned')
GROUP BY pc.category
ORDER BY penjualan_kotor DESC;

-- penjualan per kategori merata (15-17%), tidak ada kategori yang dominan.
-- Kaos terendah secara total (15,1%), tapi produknya paling sedikit (44).
-- Dihitung per produk, Kaos justru di atas Jaket dan Aksesoris --> bukan kategori yang lemah.

-- 2b. Penjualan per brand

SELECT
	pc.brand,
	SUM(oi.quantity) AS unit_terjual,
	SUM(oi.subtotal_idr) AS penjualan_kotor,
	ROUND(100.0 * SUM(oi.subtotal_idr) / SUM(SUM(oi.subtotal_idr)) OVER (), 1) AS persen_penjualan,
	ROUND(1.0 * SUM(oi.subtotal_idr) / SUM(oi.quantity), 0) AS harga_rata2_per_unit
FROM order_items oi
JOIN orders_clean oc ON oc.order_id = oi.order_id
JOIN products_clean pc ON pc.product_id = oi.product_id
WHERE oc.order_status NOT IN ('cancelled', 'returned')
GROUP BY pc.brand
ORDER BY penjualan_kotor DESC;

-- Riang Apparel tertinggi (12,4%), Ratu Mode terendah (7,5%).
-- Unit terjual tidak sejalan dengan penjualan:
-- Kanvas Lokal unit terjualnya peringkat 3 (585), tapi harga rata-rata per unit paling murah
-- (~Rp183 rb) --> penjualannya hanya peringkat 9.
-- NusaBrand unitnya lebih sedikit (508), tapi harga rata-rata tertinggi (~Rp310 rb) --> peringkat 2.

-- =======================================
-- 3. Efektivitas promo
-- =======================================

-- 3a. Pesanan dengan promo vs tanpa promo
-- Nilai belanja sebelum diskon = total_amount_idr + discount_amount_idr

SELECT
	CASE WHEN promo_code = 'Tanpa promo' THEN 'Tanpa promo' ELSE 'Pakai promo' END AS kelompok,
	COUNT(*) AS jumlah_pesanan,
	ROUND(AVG(total_amount_idr + discount_amount_idr), 0) AS rata2_belanja_sebelum_diskon,
	ROUND(AVG(discount_amount_idr), 0) AS rata2_diskon,
	ROUND(AVG(total_amount_idr), 0) AS rata2_dibayar
FROM orders_clean
WHERE order_status NOT IN ('cancelled', 'returned')
GROUP BY CASE WHEN promo_code = 'Tanpa promo' THEN 'Tanpa promo' ELSE 'Pakai promo' END;

-- nilai belanja sebelum diskon hampir sama (Rp515.199 vs Rp513.830)
-- --> promo tidak membuat pelanggan belanja lebih banyak per pesanan,
-- hanya mengurangi pembayaran rata-rata ~Rp30.661 per pesanan.
-- Batasan: data tidak bisa menunjukkan apakah promo menarik pembeli baru
-- yang tidak akan belanja tanpa promo.

-- 3b. Rincian per kode promo

SELECT
	promo_code,
	COUNT(*) AS jumlah_pesanan,
	SUM(discount_amount_idr) AS total_diskon,
	ROUND(AVG(100.0 * discount_amount_idr / (total_amount_idr + discount_amount_idr)), 1) AS rata2_persen_diskon,
	SUM(total_amount_idr) AS revenue
FROM orders_clean
WHERE order_status NOT IN ('cancelled', 'returned')
	AND promo_code <> 'Tanpa promo'
GROUP BY promo_code
ORDER BY jumlah_pesanan DESC;

-- pemakaian tiap kode merata (111-141 pesanan), rata-rata diskon 10-13%
-- untuk semua kode --> tidak ada kode yang jauh lebih efektif.
-- Total diskon yang diberikan sekitar Rp31,4 juta.

-- =======================================
-- 4. Cancel dan return
-- =======================================

-- 4a. Keseluruhan

SELECT
	COUNT(*) AS jumlah_pesanan,
	ROUND(100.0 * SUM(CASE WHEN order_status = 'cancelled' THEN 1 ELSE 0 END) / COUNT(*), 1) AS persen_cancel,
	ROUND(100.0 * SUM(CASE WHEN order_status = 'returned' THEN 1 ELSE 0 END) / COUNT(*), 1) AS persen_return
FROM orders_clean;

-- Rata-rata keseluruhan: cancel 10,9%, return 5,0% --> dipakai sebagai pembanding di 4b-4d

-- 4b. Per kurir

SELECT
	courier,
	COUNT(*) AS jumlah_pesanan,
	SUM(CASE WHEN order_status = 'cancelled' THEN 1 ELSE 0 END) AS jumlah_cancel,
	SUM(CASE WHEN order_status = 'returned' THEN 1 ELSE 0 END) AS jumlah_return,
	ROUND(100.0 * SUM(CASE WHEN order_status = 'cancelled' THEN 1 ELSE 0 END) / COUNT(*), 1) AS persen_cancel,
	ROUND(100.0 * SUM(CASE WHEN order_status = 'returned' THEN 1 ELSE 0 END) / COUNT(*), 1) AS persen_return
FROM orders_clean
GROUP BY courier
ORDER BY persen_return DESC;

-- return J&T 6,0% (di atas rata-rata 5,0%) dengan volume terbesar --> jumlah return terbanyak.
-- Pos Indonesia 6,8% tapi pesanannya sedikit. Cancel tinggi Anteraja (14,3%) kemungkinan
-- bukan karena kurir, karena cancel terjadi sebelum pengiriman.

-- 4c. Per Metode Pembayaran

SELECT
	payment_method,
	COUNT(*) AS jumlah_pesanan,
	SUM(CASE WHEN order_status = 'cancelled' THEN 1 ELSE 0 END) AS jumlah_cancel,
	SUM(CASE WHEN order_status = 'returned' THEN 1 ELSE 0 END) AS jumlah_return,
	ROUND(100.0 * SUM(CASE WHEN order_status = 'cancelled' THEN 1 ELSE 0 END) / COUNT(*), 1) AS persen_cancel,
	ROUND(100.0 * SUM(CASE WHEN order_status = 'returned' THEN 1 ELSE 0 END) / COUNT(*), 1) AS persen_return
FROM orders_clean
GROUP BY payment_method
ORDER BY persen_return DESC;

-- perbedaan antar metode pembayaran kecil, tidak ada yang menonjol.

-- 4d. Per Provinsi Tujuan

SELECT
	shipping_province,
	COUNT(*) AS jumlah_pesanan,
	SUM(CASE WHEN order_status = 'cancelled' THEN 1 ELSE 0 END) AS jumlah_cancel,
	SUM(CASE WHEN order_status = 'returned' THEN 1 ELSE 0 END) AS jumlah_return,
	ROUND(100.0 * SUM(CASE WHEN order_status = 'cancelled' THEN 1 ELSE 0 END) / COUNT(*), 1) AS persen_cancel,
	ROUND(100.0 * SUM(CASE WHEN order_status = 'returned' THEN 1 ELSE 0 END) / COUNT(*), 1) AS persen_return
FROM orders_clean
GROUP BY shipping_province
ORDER BY persen_return DESC;

-- return tertinggi DKI Jakarta dan Sulawesi Utara, cancel tertinggi Kalimantan Selatan,
-- tapi jumlah pesanan per provinsi kecil --> perlu dipantau, belum bisa disimpulkan.
-- Batasan: data tidak mencatat alasan cancel/return.