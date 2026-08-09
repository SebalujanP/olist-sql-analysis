
-- Tabla de traducción de categorías (cargarla primero, no depende de nada)
CREATE TABLE product_category_translation (
    product_category_name VARCHAR(100),
    product_category_name_english VARCHAR(100)
);

-- Clientes
-- Nota: esta tabla tiene DOS identificadores distintos.
-- customer_id genera uno nuevo por CADA COMPRA (aunque sea el mismo cliente).
-- customer_unique_id sí identifica a la misma persona a través de sus distintas compras.
-- Esto importa más adelante en la sección RFM.
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

-- Geolocalización (opcional, la más pesada, podés dejarla para después)
CREATE TABLE geolocation (
    geolocation_zip_code_prefix VARCHAR(10),
    geolocation_lat NUMERIC(10,6),
    geolocation_lng NUMERIC(10,6),
    geolocation_city VARCHAR(100),
    geolocation_state VARCHAR(5)
);

--Verificacion de importacion
-- UNION ALL apila el resultado de varios SELECT (mismo número de columnas)
-- en una sola salida, para chequear de un vistazo que ninguna tabla haya
-- quedado vacía o a medio cargar.
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

-- Consultas

--1):
-- PREGUNTA DE NEGOCIO: ¿el tiempo de entrega afecta la satisfacción del cliente (review_score)?
-- Fecha de COMPRA, FECHA QUE LLEGO,REVIEW SCORE
-- JOIN entre orders y order_reviews por order_id, la columna que ambas comparten.
SELECT orders.order_purchase_timestamp,orders.order_delivered_customer_date,order_reviews.review_score
from orders
join order_reviews on orders.order_id=order_reviews.order_id

--Dias que tardo en entregarse 
-- La resta entre dos TIMESTAMP en PostgreSQL devuelve un INTERVAL (formato "X days HH:MM:SS"),
-- no un número. EXTRACT(DAY FROM ...) saca solo la cantidad de días como entero,
-- para poder promediarlo después con AVG().
SELECT EXTRACT(DAY FROM orders.order_delivered_customer_date - orders.order_purchase_timestamp) AS dias_entrega, orders.order_delivered_customer_date, orders.order_purchase_timestamp,order_reviews.review_score
FROM orders
JOIN order_reviews on orders.order_id=order_reviews.order_id

--Sacar el promedio de dias_entrega para cada review score (1 al 5)
-- AVG() agrupado por review_score: da el promedio de dias_entrega dentro de cada puntaje.
-- Resultado: relación inversa clara -> a más días de entrega, peor score promedio
-- (1 estrella: ~20.8 días vs. 5 estrellas: ~10.2 días).
SELECT order_reviews.review_score,AVG(EXTRACT(DAY FROM orders.order_delivered_customer_date - orders.order_purchase_timestamp)) AS promedio_dias
FROM orders
JOIN order_reviews ON orders.order_id=order_reviews.order_id
GROUP BY order_reviews.review_score;

--2) RENTABILIDAD POR CATEGORIA Y REGION
-- El precio vive en order_items, la categoría en products, y la región del cliente
-- en customers -- pero customers no tiene conexión directa con order_items, hay que
-- pasar por orders en el medio: order_items -> products, order_items -> orders -> customers.
-- SUM(price) agrupado por 2 columnas a la vez da el total facturado en cada combinación
-- categoría + estado. Resultado: SP domina el ranking, con cama_mesa_banho como líder.
SELECT PRODUCTS.PRODUCT_CATEGORY_NAME,CUSTOMERS.CUSTOMER_STATE,SUM(ORDER_ITEMS.PRICE) AS total_facturado
from order_items
join products on order_items.product_id=products.product_id
join orders on order_items.order_id=orders.order_id
join customers on orders.customer_id=customers.customer_id
group by products.product_category_name,customers.customer_state
order by total_facturado DESC;

--3 PERFOMANCE DE VENDEDORES
-- SUM(price) = facturación total por vendedor; COUNT(order_id) = cantidad de ventas.
-- El ORDER BY ordena primero por "total" (criterio principal); "total_ventas" solo
-- desempata filas con el mismo total exacto, por eso no se ve "ordenado" por sí solo.
-- Insight: vendedores con facturación similar pueden tener volúmenes muy distintos
-- (mismo total, con pocas ventas caras o muchas ventas baratas).
Select sellers.seller_id,SUM(order_items.price) as total ,COUNT(order_items.order_id) as total_ventas
FROM order_items
join sellers on order_items.seller_id=sellers.seller_id
GROUP BY sellers.seller_id
order by total desc,total_ventas desc;

--4 RFM (Recencencia(¿hace cuánto fue su última compra? (menos días = mejor, cliente más "activo"))
--Frequency (Frecuencia): ¿cuántas veces compró en total? (más compras = cliente más fiel)
--Monetary (Monetario): ¿cuánto gastó en total? (más plata = cliente más valioso)

--Frecuencia (cuantas veces compro cada cliente)
-- Se agrupa por customer_unique_id (no customer_id) porque Olist genera un customer_id
-- nuevo en cada compra. Si se agrupara por customer_id, cada compra quedaría "aislada"
-- y el COUNT siempre daría 1, sin importar cuántas veces compró la misma persona.
SELECT customers.customer_unique_id,COUNT(orders.order_id) AS TOTAL_COMPRAS
from orders
join customers on orders.customer_id=customers.customer_id
GROUP BY customers.customer_unique_id
order by total_compras desc;

--Monetary (cuanto gasto en total cada cliente)
SELECT customers.customer_unique_id,SUM(order_items.price) as total_gastos
From order_items
join orders on order_items.order_id=orders.order_id
join customers on orders.customer_id=customers.customer_id
group by customers.customer_id,order_items.price
order by total_gastos desc;

-- Recency — hace cuántos días fue la última compra de cada cliente.
-- Paso 1: por ahora solo se saca la fecha máxima de compra de cada cliente (MAX),
-- sin calcular todavía la diferencia en días contra el "hoy" del dataset.
SELECT MAX(orders.order_purchase_timestamp) as Fecha_ultima_compra,customers.customer_unique_id
from orders
join customers on orders.customer_id=customers.customer_id
group by customers.customer_unique_id
order by Fecha_ultima_compra desc;


-- Paso 2: Diferencias del ultimo dia con la ultima compra de cada cliente
-- La subquery (SELECT MAX(order_purchase_timestamp) FROM orders) calcula la fecha
-- más reciente de TODO el dataset (sin agrupar), y se usa como el "hoy" de referencia,
-- ya que el dataset es histórico y no tiene sentido comparar contra la fecha real actual.
-- Se le resta la fecha máxima de compra DE CADA CLIENTE (MAX agrupado por GROUP BY).
SELECT customers.customer_unique_id,EXTRACT(DAY FROM (SELECT MAX(order_purchase_timestamp) FROM orders) - MAX(ORDERS.ORDER_PURCHASE_TIMESTAMP)) AS DIFERENCIA_DIAS
from orders
join customers on orders.customer_id=customers.customer_id
group by customers.customer_unique_id
order by diferencia_dias asc;

-- Craer 3 CTES
-- WITH nombre AS (...) crea una tabla temporal con nombre, válida solo durante esta
-- consulta. Se necesita porque cada una de las 3 queries de abajo ya trae su propio
-- GROUP BY (son resultados "resueltos", no tablas simples), y SQL no permite hacer
-- JOIN directo entre consultas ya agrupadas sin antes darles un nombre así.
WITH FREQUENCY AS (
SELECT customers.customer_unique_id,COUNT(orders.order_id) AS TOTAL_COMPRAS
from orders
join customers on orders.customer_id=customers.customer_id
GROUP BY customers.customer_unique_id
),

MONETARY AS(
SELECT customers.customer_unique_id,SUM(order_items.price) as total_gastos
From order_items
join orders on order_items.order_id=orders.order_id
join customers on orders.customer_id=customers.customer_id
group by customers.customer_unique_id
),

RECENCY AS(
SELECT customers.customer_unique_id,EXTRACT(DAY FROM (SELECT MAX(order_purchase_timestamp) FROM orders) - MAX(ORDERS.ORDER_PURCHASE_TIMESTAMP)) AS DIFERENCIA_DIAS
from orders
join customers on orders.customer_id=customers.customer_id
group by customers.customer_unique_id
)

-- El SELECT final une los 3 CTEs con JOIN por customer_unique_id, igual que se
-- unirían tablas normales, para tener las 3 métricas (frecuencia, gasto, recencia)
-- juntas en una sola fila por cliente.
-- Permite segmentar clientes: alta frecuencia + alto gasto + baja recencia = cliente VIP;
-- baja frecuencia + bajo gasto + alta recencia = cliente en riesgo de fuga.
SELECT FREQUENCY.CUSTOMER_UNIQUE_ID,FREQUENCY.TOTAL_COMPRAS,MONETARY.TOTAL_GASTOS,RECENCY.DIFERENCIA_DIAS
FROM FREQUENCY
JOIN MONETARY ON FREQUENCY.CUSTOMER_UNIQUE_ID=MONETARY.CUSTOMER_UNIQUE_ID
JOIN RECENCY ON FREQUENCY.CUSTOMER_UNIQUE_ID=RECENCY.CUSTOMER_UNIQUE_ID
order by diferencia_dias desc;
