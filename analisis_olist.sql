-- =====================================================================
-- PROYECTO: Análisis de Datos E-commerce (Olist) — SQL + PostgreSQL
-- Dataset público de Olist (+100.000 pedidos, 9 tablas relacionadas)
-- =====================================================================


-- =====================================================================
-- CREACIÓN DE TABLAS
-- =====================================================================

-- Tabla de traducción de categorías (cargarla primero, no depende de nada)
CREATE TABLE product_category_translation (
    product_category_name VARCHAR(100),
    product_category_name_english VARCHAR(100)
);

-- Clientes
CREATE TABLE customers (
    customer_id VARCHAR(50) PRIMARY KEY,
    customer_unique_id VARCHAR(50),
    customer_zip_code_prefix VARCHAR(10),
    customer_city VARCHAR(100),
    customer_state VARCHAR(5)
);

-- Vendedores
CREATE TABLE sellers (
    seller_id VARCHAR(50) PRIMARY KEY,
    seller_zip_code_prefix VARCHAR(10),
    seller_city VARCHAR(100),
    seller_state VARCHAR(5)
);

-- Productos
CREATE TABLE products (
    product_id VARCHAR(50) PRIMARY KEY,
    product_category_name VARCHAR(100),
    product_name_lenght INT,
    product_description_lenght INT,
    product_photos_qty INT,
    product_weight_g INT,
    product_length_cm INT,
    product_height_cm INT,
    product_width_cm INT
);

-- Pedidos (la tabla central)
CREATE TABLE orders (
    order_id VARCHAR(50) PRIMARY KEY,
    customer_id VARCHAR(50) REFERENCES customers(customer_id),
    order_status VARCHAR(20),
    order_purchase_timestamp TIMESTAMP,
    order_approved_at TIMESTAMP,
    order_delivered_carrier_date TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP
);

-- Items de cada pedido (une orders, products y sellers)
CREATE TABLE order_items (
    order_id VARCHAR(50) REFERENCES orders(order_id),
    order_item_id INT,
    product_id VARCHAR(50) REFERENCES products(product_id),
    seller_id VARCHAR(50) REFERENCES sellers(seller_id),
    shipping_limit_date TIMESTAMP,
    price NUMERIC(10,2),
    freight_value NUMERIC(10,2),
    PRIMARY KEY (order_id, order_item_id)
);

-- Pagos
CREATE TABLE order_payments (
    order_id VARCHAR(50) REFERENCES orders(order_id),
    payment_sequential INT,
    payment_type VARCHAR(20),
    payment_installments INT,
    payment_value NUMERIC(10,2)
);

-- Reseñas
CREATE TABLE order_reviews (
    review_id VARCHAR(50),
    order_id VARCHAR(50) REFERENCES orders(order_id),
    review_score INT,
    review_comment_title VARCHAR(200),
    review_comment_message TEXT,
    review_creation_date TIMESTAMP,
    review_answer_timestamp TIMESTAMP
);

-- Geolocalización
CREATE TABLE geolocation (
    geolocation_zip_code_prefix VARCHAR(10),
    geolocation_lat NUMERIC(10,6),
    geolocation_lng NUMERIC(10,6),
    geolocation_city VARCHAR(100),
    geolocation_state VARCHAR(5)
);

-- Verificación de importación
SELECT 'customers' AS tabla, COUNT(*) AS filas FROM customers
UNION ALL
SELECT 'sellers', COUNT(*) FROM sellers
UNION ALL
SELECT 'products', COUNT(*) FROM products
UNION ALL
SELECT 'orders', COUNT(*) FROM orders
UNION ALL
SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL
SELECT 'order_payments', COUNT(*) FROM order_payments
UNION ALL
SELECT 'order_reviews', COUNT(*) FROM order_reviews
UNION ALL
SELECT 'geolocation', COUNT(*) FROM geolocation
UNION ALL
SELECT 'product_category_translation', COUNT(*) FROM product_category_translation;


-- =====================================================================
-- PREGUNTA 1: ¿El tiempo de entrega afecta el review score?
-- Agrupa por puntaje de reseña y calcula el promedio de días de entrega
-- en cada grupo.
-- Resultado: relación inversa clara -> a más días de entrega, peor
-- score promedio (1 estrella: ~20.8 días vs. 5 estrellas: ~10.2 días).
-- =====================================================================
SELECT 
    order_reviews.review_score,
    AVG(EXTRACT(DAY FROM orders.order_delivered_customer_date - orders.order_purchase_timestamp)) AS promedio_dias
FROM orders
JOIN order_reviews ON orders.order_id = order_reviews.order_id
GROUP BY order_reviews.review_score
ORDER BY order_reviews.review_score;


-- =====================================================================
-- PREGUNTA 2: ¿Qué categorías y regiones generan más facturación?
-- Suma el precio de todos los items vendidos, agrupado por categoría
-- de producto y estado del cliente. Ordenado de mayor a menor.
-- Resultado: San Pablo (SP) domina el ranking en casi todas las
-- categorías top, con cama_mesa_banho como líder absoluto en esa región.
-- =====================================================================
SELECT 
    products.product_category_name, 
    customers.customer_state, 
    SUM(order_items.price) AS total_facturado
FROM order_items
JOIN products ON order_items.product_id = products.product_id
JOIN orders ON order_items.order_id = orders.order_id
JOIN customers ON orders.customer_id = customers.customer_id
GROUP BY products.product_category_name, customers.customer_state
ORDER BY total_facturado DESC;


-- =====================================================================
-- PREGUNTA 3: Performance de vendedores
-- Total facturado y cantidad de ventas por vendedor, ordenado de mayor
-- a menor facturación.
-- Insight: vendedores con facturación similar pueden tener volúmenes
-- muy distintos (ticket promedio diferente).
-- =====================================================================
SELECT 
    sellers.seller_id, 
    SUM(order_items.price) AS total, 
    COUNT(order_items.order_id) AS total_ventas
FROM order_items
JOIN sellers ON order_items.seller_id = sellers.seller_id
GROUP BY sellers.seller_id
ORDER BY total DESC, total_ventas DESC;


-- =====================================================================
-- PREGUNTA 4: Segmentación de clientes (RFM)
-- Combina Frequency, Monetary y Recency en una sola tabla por cliente,
-- usando CTEs (WITH ... AS). Nota: se usa customer_unique_id (no
-- customer_id) porque Olist genera un customer_id nuevo por cada compra.
-- Permite segmentar clientes: alta frecuencia + alto gasto + baja
-- recencia = cliente VIP; baja frecuencia + bajo gasto + alta
-- recencia = cliente en riesgo de fuga.
-- =====================================================================
WITH frequency AS (
    SELECT customers.customer_unique_id, COUNT(orders.order_id) AS total_compras
    FROM orders
    JOIN customers ON orders.customer_id = customers.customer_id
    GROUP BY customers.customer_unique_id
),
monetary AS (
    SELECT customers.customer_unique_id, SUM(order_items.price) AS total_gastos
    FROM order_items
    JOIN orders ON order_items.order_id = orders.order_id
    JOIN customers ON orders.customer_id = customers.customer_id
    GROUP BY customers.customer_unique_id
),
recency AS (
    SELECT customers.customer_unique_id, 
        EXTRACT(DAY FROM (SELECT MAX(order_purchase_timestamp) FROM orders) - MAX(orders.order_purchase_timestamp)) AS diferencia_dias
    FROM orders
    JOIN customers ON orders.customer_id = customers.customer_id
    GROUP BY customers.customer_unique_id
)
SELECT 
    frequency.customer_unique_id, 
    frequency.total_compras, 
    monetary.total_gastos, 
    recency.diferencia_dias
FROM frequency
JOIN monetary ON frequency.customer_unique_id = monetary.customer_unique_id
JOIN recency ON frequency.customer_unique_id = recency.customer_unique_id
ORDER BY monetary.total_gastos DESC;
