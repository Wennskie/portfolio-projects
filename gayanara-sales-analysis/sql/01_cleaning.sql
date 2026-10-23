-- 01_cleaning.sql
-- Pembersihan data Gayanara

-- =======================================
-- TABLE products
-- =======================================

-- 1. Temuan awal products (scan filter di Excel), dikonfirmasi dengan query di bawah

SELECT
	COUNT(*) AS total_baris,
	COUNT(DISTINCT product_id) AS id_unik,
	COUNT(DISTINCT name) AS nama_unik,
	COUNT(DISTINCT category) AS variasi_kategori,
	COUNT(*) - COUNT(material) AS material_kosong,
	MIN(price_idr) AS harga_min,
	MAX(price_idr) AS harga_max,
	MIN(stock) AS stok_min,
	MAX(stock) AS stok_max,
	MIN(avg_rating) AS rating_min,
	MAX(avg_rating) AS rating_max
FROM products;

-- nama unik < total baris (berarti ada nama yang duplikat)
-- variasi kategori terlalu banyak (ada 14)
-- ada 9 material kosong [NULL]
-- sub_category, brand, material: dicek di Excel, penulisannya sudah konsisten
-- sisanya masih dalam batas wajar

-- 2. Cek variasi kategori produk

SELECT
	category,
	sub_category,
	COUNT(*) AS jumlah
FROM products
GROUP BY category, sub_category
ORDER BY category;

-- Merapikan kategori produk (Data mentah masih mixed indo-inggris, huruf kapital tidak konsisten, dan ada
-- kategori yang menggunakan lebih dari 1 istilah untuk produk yang sama)

CREATE TABLE products_clean AS
SELECT
	product_id,
	name,
	CASE
		WHEN LOWER(TRIM(category)) IN ('accessories', 'aksesoris') THEN 'Aksesoris'
		WHEN LOWER(TRIM(category)) IN ('celana', 'pants') THEN 'Celana'
		WHEN LOWER(TRIM(category)) = 'dress' THEN 'Dress'
		WHEN LOWER(TRIM(category)) IN ('jacket', 'jaket') THEN 'Jaket'
		WHEN LOWER(TRIM(category)) IN ('kaos', 't-shirt') THEN 'Kaos'
		WHEN LOWER(TRIM(category)) IN ('kemeja', 'shirt') THEN 'Kemeja'
	END AS category,
	sub_category,
	price_idr,
	stock,
	brand,
	material,
	avg_rating
FROM products;

-- Cek hasil, harusnya sisa 6 kategori dengan total 300 baris + tidak ada kategori NULL

SELECT
	category,
	COUNT(*) AS jumlah
FROM products_clean
GROUP BY category
ORDER BY category;

-- 3. Cek variasi material produk

SELECT
	material,
	COUNT(*) AS jumlah
FROM products_clean
GROUP BY material
ORDER BY material;

-- Ada 9 baris produk yang tidak memiliki value [NULL] --> update menjadi 'Tidak diketahui'

UPDATE products_clean
SET material = 'Tidak diketahui'
WHERE material IS NULL;

-- Cek lagi, sudah tidak ada NULL (semua baris NULL sudah diganti menjadi 'Tidak diketahui')

SELECT
	material,
	COUNT(*) AS jumlah
FROM products_clean
GROUP BY material
ORDER BY material;

-- 4. Cek nama produk yang dobel

SELECT
	name,
	COUNT(*) AS jumlah,
	MIN(price_idr) AS harga_min,
	MAX(price_idr) AS harga_max
FROM products_clean
GROUP BY name
HAVING COUNT(*) > 1
ORDER BY jumlah DESC, name;

-- ternyata ada 74 nama produk yang muncul > 1, namun product_id dan harganya berbeda --> bisa
-- dianggap sebagai varian berbeda jadi tidak perlu digabung (Analisis per produk juga tetap
-- menggunakan product_id bukan name)


-- =======================================
-- TABLE customers
-- =======================================


-- 1. Temuan awal customers (scan filter di Excel), dikonfirmasi dengan query di bawah

SELECT
	COUNT(*) AS total_baris,
	COUNT(DISTINCT customer_id) AS id_unik,
	COUNT(DISTINCT email) AS email_unik,
	COUNT(*) - COUNT(phone) AS phone_kosong,
	MIN(registration_date) AS registrasi_pertama,
	MAX(registration_date) AS registrasi_terakhir
FROM customers;

-- email_unik 797 dari 800 --> berarti ada email yang dipake oleh lebih dari 1 customer
-- ada 40 baris phone kosong
-- rentang tanggal registrasi masih masuk akal

-- 2. Detail email yang dipake oleh lebih dari 1 customer

SELECT *
FROM customers
WHERE email IN (SELECT email FROM customers GROUP BY email HAVING COUNT(*) > 1)
ORDER BY email;

-- Ada 3 pasang email dipake oleh 2 orang yang berbeda (1 sesuai + 1 tidak sesuai)
-- karena bisa saja customer yang salah input itu memiliki pesanan, maka
-- email yang tidak sesuai dibuat [NULL] 

CREATE TABLE customers_clean AS
SELECT * FROM customers;

UPDATE customers_clean
SET email = NULL
WHERE customer_id IN ('CUST0321', 'CUST0755', 'CUST0567');

-- cek kembali setelah dibersihkan

SELECT
	COUNT(*) AS total_baris,
	COUNT(*) - COUNT(email) AS email_kosong,
	COUNT(email) - COUNT(DISTINCT email) AS email_double
FROM customers_clean;

-- untuk phone memang ada 40 baris yang kosong, 
-- tapi lebih baik dibiarin NULL daripada diisi oleh data fiktif

-- 3. Cek apakah ada tanggal yang bermasalah (tanggal pesan sebelum tanggal registrasi)

WITH customers_first AS(
	SELECT
		customer_id,
		MIN(order_date) AS pesanan_pertama
	FROM orders
	GROUP BY customer_id
)
SELECT COUNT(*) AS customer_bermasalah
FROM customers_clean cc
JOIN customers_first cf ON cf.customer_id = cc.customer_id
WHERE cf.pesanan_pertama < cc.registration_date;

-- 358 dari 800 customer pesanan pertamanya sebelum tanggal registrasi
-- sehingga kolom registration_date tidak bisa dipercaya.
-- tanggal awal customers sebaiknya memakai tanggal pesanan pertama dari tabel orders


-- =======================================
-- TABLE orders
-- =======================================


-- 1. Temuan awal orders (scan filter di Excel), dikonfirmasi dengan query di bawah

SELECT
	COUNT(*) AS total_baris,
	COUNT(DISTINCT order_id) AS id_unik,
	COUNT(*) - COUNT(promo_code) AS promo_kosong,
	COUNT(*) - COUNT(discount_amount_idr) AS diskon_kosong,
	SUM(CASE WHEN promo_code IS NULL AND discount_amount_idr IS NOT NULL THEN 1 ELSE 0 END)
	+ SUM(CASE WHEN promo_code IS NOT NULL AND discount_amount_idr IS NULL THEN 1 ELSE 0 END) AS promo_diskon_tidak_sinkron,
	MIN(order_date) AS pesanan_pertama,
	MAX(order_date) AS pesanan_terakhir,
	MIN(total_amount_idr) AS total_min,
	MAX(total_amount_idr) AS total_max
FROM orders;

-- promo_code kosong 1786 dan discount_amount_idr kosong 1786, selalu kosong bersamaan
-- total_min Rp1.000: dicek, berasal dari produk Rp49.000 dengan diskon Rp48.000
-- --> total jadi Rp1.000 karena diskonnya sangat besar, bukan error data.
-- Rentang tanggal pesanan masuk akal

-- 2. Isi promo dan diskon yang kosong
-- Kosong artinya tanpa promo, jadi diskon = 0 (bukan data karangan).
-- Diskon diisi 0 supaya AVG/SUM diskon nanti tidak hanya menghitung pesanan berpromo.

CREATE TABLE orders_clean AS
SELECT * FROM orders;

UPDATE orders_clean
SET promo_code = 'Tanpa promo',
	discount_amount_idr = 0
WHERE promo_code IS NULL;

-- cek kembali setelah dibersihkan

SELECT
	COUNT(*) AS total_baris,
	COUNT(*) - COUNT(promo_code) AS promo_kosong,
	COUNT(*) - COUNT(discount_amount_idr) AS diskon_kosong,
	SUM(CASE WHEN promo_code IS NULL AND discount_amount_idr IS NOT NULL THEN 1 ELSE 0 END)
	+ SUM(CASE WHEN promo_code IS NOT NULL AND discount_amount_idr IS NULL THEN 1 ELSE 0 END) AS promo_diskon_tidak_sinkron
FROM orders_clean;

-- Hasil: promo_kosong 0, diskon_kosong 0

-- 3. Cek logika antartabel: total pesanan = jumlah subtotal item - diskon

WITH total_item AS (
	SELECT
		order_id,
		SUM(subtotal_idr) AS jumlah_subtotal
	FROM order_items
	GROUP BY order_id
)
SELECT
	COUNT(*) AS pesanan_dicek,
	SUM(CASE WHEN oc.total_amount_idr != ti.jumlah_subtotal - oc.discount_amount_idr
	         THEN 1 ELSE 0 END) AS total_tidak_cocok
FROM orders_clean oc
LEFT JOIN total_item ti ON ti.order_id = oc.order_id;

-- Hasil: 3000 pesanan dicek, total_tidak_cocok 0 --> total pesanan konsisten dengan item-itemnya

-- =======================================
-- TABLE order_items
-- =======================================

-- 1. Temuan awal order_items (scan filter di Excel), dikonfirmasi dengan query di bawah

SELECT
	COUNT(*) AS total_baris,
	COUNT(DISTINCT item_id) AS id_unik,
	MIN(quantity) AS qty_min,
	MAX(quantity) AS qty_max,
	SUM(CASE WHEN subtotal_idr != quantity * unit_price_idr THEN 1 ELSE 0 END) AS subtotal_tidak_cocok
FROM order_items;

-- 2. Cek logika antartabel: harga di pesanan = harga produk

SELECT COUNT(*) AS harga_tidak_cocok
FROM order_items oi
JOIN products_clean pc ON pc.product_id = oi.product_id
WHERE oi.unit_price_idr != pc.price_idr;

-- Hasil: tidak ada masalah. Subtotal dan harga konsisten.
-- Tidak ada yang perlu dibersihkan --> tabel order_items bisa langsung dipakai di analisis.


-- =======================================
-- TABLE reviews
-- =======================================


-- 1. Temuan awal reviews (scan filter di Excel), dikonfirmasi dengan query di bawah

SELECT
	COUNT(*) AS total_baris,
	COUNT(DISTINCT review_id) AS id_unik,
	COUNT(*) - COUNT(review_text) AS teks_kosong,
	MIN(rating) AS rating_min,
	MAX(rating) AS rating_max,
	MIN(helpful_count) AS helpful_min,
	MAX(helpful_count) AS helpful_max
FROM reviews;

-- tidak ada masalah. review_text kosong 120 --> dibiarkan NULL (rating tanpa teks itu masih wajar)

-- 2. Cek logika antartabel: review hanya untuk pesanan delivered,
-- dan tanggal review setelah tanggal pesanan

SELECT
	oc.order_status,
	COUNT(*) AS jumlah_review,
	MIN(r.review_date - oc.order_date) AS selisih_hari_min,
	MAX(r.review_date - oc.order_date) AS selisih_hari_max
FROM reviews r
JOIN orders_clean oc ON oc.order_id = r.order_id
GROUP BY oc.order_status;

-- semua review dari pesanan berstatus delivered,
-- tanggal review 1-10 hari setelah pesanan (masih relevan)

-- 3. Cek apakah isi teks review nyambung dengan rating-nya

SELECT
	review_text,
	COUNT(*) AS jumlah,
	ROUND(AVG(rating), 2) AS rata_rata_rating
FROM reviews
WHERE review_text IS NOT NULL
GROUP BY review_text
ORDER BY rata_rata_rating;

-- teks review tidak sesuai rating. Contoh: "Tidak sesuai ekspektasi, kurang puas"
-- rata-rata rating 4,04, lebih tinggi dari "Bahannya enak banget... Recommended!" (3,78).
-- review_text better tidak dipakai di analisis, tetapi kolom rating tetap dipakai.
-- Tidak ada yang diubah --> tabel reviews dipakai langsung.