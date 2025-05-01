/*
Northwind Data Exploration

Skills used: Joins, Views, CTE's, Window Functions, Aggregate Functions

*/

-- Important to know that unit price from order_details shows price that it was sold to customer and unit price in products table only shows current value of product
-- This view contains most of the information we will need for all given orders

DROP VIEW IF EXISTS all_order_info


CREATE OR REPLACE VIEW all_order_info AS 
SELECT 
	orderid,
	CONCAT(firstname,' ',lastname) AS employee,
	orderdate AS order_date,
	requireddate AS required_date,
	shippeddate AS shipped_date,
	shipvia AS shipper_id,
	freight,
	companyname AS customer,
	cu.city,
	cu.country,
	productname AS product,
	categoryname AS category,
	p.unitprice AS current_price,
	od.unitprice AS ordered_price,
	quantity,discount,
	ROUND((od.unitprice*quantity*(1-discount))::numeric,2) AS total_sale_price
FROM orders AS o
JOIN order_details AS od USING (orderid)
JOIN products AS p USING (productid)
JOIN categories AS ca USING (categoryid)
JOIN customers AS cu USING (customerid)
JOIN employees AS em USING (employeeid)
ORDER BY orderid;



-- Information on Products Cost Vs Sales and Profit Margins
-- Key assumptions have to be made for this analysis. This database does not contain the amount of money that Northwind trades spends on the products. This information would be useful for determining profit margins which is an important metric for any buisness.
-- For this analysis I use a random number generator to give us the "original price" that we pay to the suppliers

SELECT setseed(0.5);
WITH product_prices AS(
	SELECT 
		productname,
		od.unitprice AS od_price, 
		od.unitprice*(random()*(0.9-0.6)+0.6) AS original_price
	FROM products AS p
	JOIN order_details AS od USING(productid)
	GROUP BY productid,od.unitprice
	ORDER BY productid
)
SELECT 
	orderid,
	all_order_info.product,
	category,
	order_date,
	employee,
	customer,
	ordered_price AS customer_price,
	discount,
	ROUND((ordered_price*(1-discount))::numeric,2) AS purchased_price,
	ROUND(original_price::numeric,2) AS supplier_price,
	ROUND(((ordered_price*(1-discount))-original_price)::numeric,2) AS profit_per_unit,
	ROUND(((((ordered_price*(1-discount))-original_price)/original_price)*100)::numeric,2) AS profit_per_unit_percent,
	quantity,
	ROUND((original_price*quantity)::numeric,2) AS total_supplier_cost,
	total_sale_price,
	ROUND((total_sale_price)-(original_price*quantity)::numeric,2) AS total_profit
FROM all_order_info
JOIN product_prices ON product_prices.productname=all_order_info.product AND product_prices.od_price=all_order_info.ordered_price
ORDER BY orderid;




--Information on Products and inventory

SELECT 
	productname AS product,
	categoryname AS category,
	companyname AS Supplier,
	unitprice AS current_price,
	unitsinstock AS units_in_stock,
	unitsonorder AS units_on_order,
	reorderlevel AS reorder_level,
	discontinued,
	CASE 
		WHEN unitsinstock + unitsonorder< reorderlevel THEN 'Reorder now'
		WHEN unitsinstock + unitsonorder< reorderlevel * 2 THEN 'Reorder next month'
		ELSE 'Do not reorder'
	END AS Inventory_status
FROM products
JOIN suppliers USING (supplierid)
JOIN categories USING (categoryid)
ORDER BY productid;




-- Employee sales data by year (see how much of this can be done directly in tableau with all_order_info table)

SELECT 
	employee,
	extract(YEAR from order_date) AS Year, 
	SUM(Total_Sale_Price) AS Total_Yearly_Sales
FROM all_order_info
GROUP BY 
	employee, 
	Year 
ORDER BY 
	employee,
	Year,
	total_yearly_sales DESC;




-- Customers that employee sold to the most per year
-- Using CTE to find employee yearly sales data per customer and pulling the Max value per employee per year

WITH employee_performance AS(
	SELECT 
		employee, 
		extract(YEAR from order_date) AS Year, 
		SUM(Total_Sale_Price) AS Total_Sales, 
		customer
	FROM all_order_info
	GROUP BY 
		employee, 
		Year,
		customer
	ORDER BY 
		employee, 
		Year,
		Total_Sales DESC
)
SELECT 
	employee_performance.employee,
	employee_performance.year,customer,
	employee_performance.total_sales
FROM employee_performance 
INNER JOIN (
	SELECT 
		employee,
		year,
		MAX(total_sales) AS Max_Sales
	FROM employee_performance
	GROUP BY 
		employee,
		year
) top_customers ON employee_performance.employee = top_customers.employee AND employee_performance.year = top_customers.year AND employee_performance.total_sales = top_customers.max_sales
ORDER BY 
	employee_performance.employee, 
	Year, 
	total_sales DESC;



-- Best selling products per category per year

WITH product_sales_per_year AS(
	SELECT 
		category,
		product,
		extract(YEAR from order_date) AS Year,
		SUM(quantity) AS total_units_sold,
		SUM(Total_Sale_Price) AS total_sales
	FROM all_order_info
	GROUP BY 
		category,
		product,
		year
	ORDER BY 
		category,
		product,
		year
)
SELECT 
	product_sales_per_year.category,
	product_sales_per_year.product,
	product_sales_per_year.year,
	total_units_sold,
	total_sales
FROM product_sales_per_year
Inner JOIN (
	SELECT 
		category,
		year,
		MAX(total_sales) AS max_sales
	FROM product_sales_per_year
	GROUP BY category,year
	ORDER BY category,year
) top_products ON product_sales_per_year.category = top_products.category AND product_sales_per_year.year = top_products.year AND product_sales_per_year.total_sales = top_products.max_sales;




--Compare product prices with average prices per category

SELECT 
	categoryname AS category,
	productname AS product,
	unitprice AS unit_price, 
	AVG(unitprice) OVER (PARTITION BY categoryname) AS Avg_unit_price_per_category
FROM products
JOIN categories USING (categoryid)
ORDER BY 
	categoryname, 
	unitprice DESC;




--Which product category does each company order the most quantity of

WITH company_category_sales AS(
	SELECT 
		customer,
		category,
		SUM(quantity) AS total_units_ordered,
		SUM(total_sale_price) AS Total_Sales
	FROM all_order_info
	GROUP BY 
		customer,
		category
	ORDER BY 
		customer,
		category
)
SELECT 
	company_category_sales.customer,
	company_category_sales.category,
	total_units_ordered,
	Total_Sales
FROM company_category_sales
INNER JOIN (
	SELECT 
		customer,
		MAX(total_units_ordered) AS max_order_amount
	FROM company_category_sales
	GROUP BY customer
	ORDER BY customer
) company_max_category ON company_max_category.customer=company_category_sales.customer AND company_max_category.max_order_amount=company_category_sales.total_units_ordered
ORDER BY customer;