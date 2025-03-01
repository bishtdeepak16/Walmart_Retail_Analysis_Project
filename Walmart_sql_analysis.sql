-- SQL Walmart Retail Analysis
CREATE DATABASE walmart_analysis;


CREATE TABLE walmart ("transaction_id" INTEGER, 
					  "customer_id" INTEGER, 
					  "product_id" INTEGER, 
					  "product_name" VARCHAR, 
					  "category" VARCHAR, 
					  "quantity_sold" INTEGER, 
					  "unit_price" FLOAT, 
					  "transaction_date" VARCHAR, 
					  "store_id" INTEGER, 
					  "store_location" VARCHAR, 
					  "customer_age" INTEGER, 
					  "customer_gender" VARCHAR, 
					  "customer_income" FLOAT, 
					  "customer_loyalty_level" VARCHAR, 
					  "payment_method" VARCHAR, 
					  "promotion_applied" BOOLEAN, 
					  "promotion_type" VARCHAR, 
					  "holiday_indicator" BOOLEAN, 
					  "weekday" VARCHAR);

-- Data Cleaning

SELECT * FROM Walmart
WHERE 
    "transaction_id" IS NULL
    OR
    "customer_id" IS NULL
    OR
    "product_id" IS NULL
    OR
    "product_name" IS NULL
    OR
    "category" IS NULL
    OR
    "quantity_sold" IS NULL
    OR
    "unit_price" IS NULL
    OR
    "transaction_date" IS NULL
    OR
    "store_id" IS NULL
    OR
    "store_location" IS NULL
    OR
    "customer_age" IS NULL
    OR
    "customer_gender" IS NULL
    OR
    "customer_income" IS NULL
    OR
    "customer_loyalty_level" IS NULL
    OR
    "payment_method" IS NULL
    OR
    "promotion_applied" IS NULL
    OR
    "promotion_type" IS NULL
    OR
    "holiday_indicator" IS NULL
    OR
    "weekday" IS NULL;
	
-- There are no null values but there are other problems in data. In product_name column some rows are mistakenly assigned in both product categories.
-- So we need to fix this by assigining those rows of product_name to their correct product category.
	
Update walmart
set category = 
case when product_name in ('Camera','Headphones','Laptop','Smartphone','Tablet','TV') THEN 'Electronics'
	when product_name in ('Fridge','Washing Machine') then 'Appliances'
	else category
	end;

-- In table, there is transaction_date column which has datatype of timestamp timezone. For convinience I extracted date and hour in seperate new column.
	
ALTER TABLE walmart
ADD COLUMN transaction_date_only DATE,
ADD COLUMN transaction_hour INT;

UPDATE walmart
SET transaction_date_only = TO_DATE(SPLIT_PART(transaction_date, ' ', 1), 'MM/DD/YYYY'),
    transaction_hour = EXTRACT(HOUR FROM TO_TIMESTAMP(transaction_date, 'MM/DD/YYYY HH24:MI'));
	
-- In table, holiday_indicator is a column which indicates wether the day is holiday or not. In some rows of weekday where weekday is sunday the holiday indicator is false.
-- Doesn't make sense as sunday is offical week holiday so fixed those rows by True where weekday is Sunday.

Select transaction_date,weekday,holiday_indicator
from walmart
where weekday = 'Sunday' and holiday_indicator = False;

Update walmart
set holiday_indicator = True
where weekday = 'Sunday';


-- Now here comes an intresting problem. There are two columns in table one is 'promotion_applied' which indicates boolean value True and False and the second column is promotion_type which has types of promotions and discounts applied by customer.
-- The two problems are there are some rows in which promotion_applied is False and still promotion_type is assigned AND rows in which promotion_applied is True but promotion_type is assigned 'None'.
-- It shows that there is some data inconsistency.  

SELECT COUNT(*) 
FROM walmart 
WHERE promotion_applied = False AND promotion_type != 'None';

SELECT COUNT(*) 
FROM walmart 
WHERE promotion_applied = True AND promotion_type = 'None';

-- As this is sample data many multiple approaches can be applied. Since where promotion_applied is FALSE, Its very likely that promotion_type is mistakenly assigned because False means no promotion should be recorded.
-- So I fixed this by replacing those promotion_type values by 'None' where promotion_applied is FALSE.
UPDATE walmart
SET promotion_type = 'None'
WHERE promotion_applied = False AND promotion_type != 'None';

-- Now the first problem is solved there is still need to fill the remaining promotion_type None values where promotion_applied is True.
-- The only possible best way to replace those none values is by using the most frequently applied promotion in that store and category across a larger period (e.g., the last 30 days).

WITH PromoMapping AS (
    -- Find most frequent promotion for each store, date, and category
    SELECT store_id, transaction_date_only, category, 
           promotion_type,
           COUNT(*) AS freq
    FROM walmart
    WHERE promotion_type IS NOT NULL AND promotion_type <> 'None'
    GROUP BY store_id, transaction_date_only, category, promotion_type
),
RankedPromo AS (
    -- Rank promotions based on frequency per store, date, and category
    SELECT store_id, transaction_date_only, category, promotion_type,
           RANK() OVER (PARTITION BY store_id, transaction_date_only, category ORDER BY freq DESC) AS rnk
    FROM PromoMapping
),
FinalMapping AS (
    -- Fill missing promotions with the most frequent promotion in the last 30 days for that store & category
    SELECT w.store_id, w.transaction_date_only, w.category, 
           COALESCE(rp.promotion_type, 
                (SELECT promotion_type 
                 FROM walmart 
                 WHERE store_id = w.store_id 
                   AND category = w.category 
                   AND promotion_type IS NOT NULL AND promotion_type <> 'None'
                   AND transaction_date_only BETWEEN w.transaction_date_only - INTERVAL '30 days' 
                                                 AND w.transaction_date_only
                 GROUP BY promotion_type
                 ORDER BY COUNT(*) DESC 
                 LIMIT 1)) AS new_promo
    FROM walmart w
    LEFT JOIN RankedPromo rp 
        ON w.store_id = rp.store_id 
        AND w.transaction_date_only = rp.transaction_date_only
        AND w.category = rp.category
    WHERE w.promotion_applied = TRUE 
          AND (w.promotion_type IS NULL OR w.promotion_type = 'None')
)
UPDATE walmart AS t
SET promotion_type = f.new_promo
FROM FinalMapping f
WHERE t.store_id = f.store_id 
AND t.transaction_date_only = f.transaction_date_only
AND t.category = f.category
AND t.promotion_applied = TRUE
AND (t.promotion_type IS NULL OR t.promotion_type = 'None');


-- This finds the most frequently applied promotion per store, category, and date.
-- Ranks them to select the highest occurrence.
-- If still None, it backfill with the most used promotion in the last 30 days for that store and category.
-- This Ensures no None values are left when promotion_applied = TRUE as it uses real past data instead of guessing, making the dataset more accurate.



-- DATA ANALYSIS & BUSINESS KEY PROBLEMS AND ANSWERS

-- My Analysis & Findings

-- Q1. What are the total sales revenue.
SELECT sum(unit_price * quantity_sold) as totsl_revenue
from walmart

--Q2 How many unique customers have made purchases?
Select count(distinct customer_id) as unique_customers
FROM walmart

-- Q3. Which store has the highest number of transactions?
SELECT store_id,
Count(transaction_id) as total_transactions
from walmart
group by 1
order by 2 desc
limit 1

-- Q4. What are the top 3 best-selling products by quantity sold and revenue?
Select product_name,
sum(quantity_sold) as total_quantity
from walmart
group by 1
order by 2 desc
limit 3;

Select product_name,
round(sum(quantity_sold*unit_price)::numeric,2) as total_quantity
from walmart
group by 1
order by 2 desc
limit 3;

-- Q5. What is the average unit price of products sold?
SELECT round(avg(unit_price::numeric),2) as avg_unit_price
from walmart

-- Q6 What is the most commonly used payment method?
SELECT payment_method,
count(*) as commonly_used_payment_method
from walmart
group by 1
order by 2 desc
limit 1

-- Q7. How does sales revenue vary between weekdays and weekends?
Select 
round(sum(case when weekday in ('Sunday','Saturday') then (quantity_sold * unit_price) else null end::numeric),2) as weekend_sales,
round(sum(case when weekday not in ('Sunday','Saturday')then (quantity_sold * unit_price)  else null end::numeric),2) as weekday_sales
from walmart

-- Q8. Which store location generates the most revenue?
SELECT store_location,
sum(unit_price * quantity_sold) as total_revenue
from walmart
group by 1 
order by 2 desc
limit 1

-- Q9. What is the total number of transactions that involved promotions?
select count(transaction_id) as transaction_count
from walmart
where promotion_applied = 'true'


-- Q10. What is the highest and lowest revenue generated in a single day?
SELECT max(quantity_sold*unit_price) as highest_revenue_generated,
min(quantity_sold * unit_price) as lowest_revenue_generated
from walmart


-- Q11. What is the revenue contribution by each store as a percentage of total revenue?
SELECT 
store_id,
round(sum(quantity_sold* unit_price)::numeric,2) as total_revenue,
round(100 *sum(quantity_sold* unit_price)::numeric/
	  (select sum(quantity_sold*unit_price)::numeric from walmart),2) as revenue_percentage
from walmart
group by 1
order by 1


-- Q12. What are the monthly trends for sales revenue?
SELECT to_char(transaction_date_only,'MM-YYYY') as month,
sum(quantity_sold * unit_price) as total_revenue
from walmart
group by 1
order by 1


 -- Q13. Which customer age group contributes the most to total revenue?
 alter table walmart
add column customer_age_group varchar;
 
 Update walmart
set customer_age_group =
case when customer_age between 18 and 26 then 'Young Adults(18-26)'
when customer_age between 27 and 39 then 'Adults(26-39)'
when customer_age between 40 and 54 then 'Middle-Age(40-54)'
when customer_age between 55 and 65 then 'Senior Citizen(55-65)'
else 'Elderly(65+)'
end;

 SELECT customer_age_group,
 round(sum(quantity_sold * unit_price::numeric),2) as total_revenue
 from walmart
 group by 1
 order by 2 desc
 limit 1;
 
 
 -- Q14. How does customer income level affect spending habits?
ALTER TABLE walmart
ADD COLUMN customer_income_category TEXT;

Update walmart
set customer_income_category = 
case when customer_income < 50000 then 'Low Income'
when customer_income between 50000 and 100000 then 'Middle Income'
else 'High Income'
end;
-- Total revenue by income group
Select customer_income_category,
round(sum(quantity_sold * unit_price::numeric),2) as avg_transaction_value
from walmart
group by 1
order by 2 desc;

-- avg_spending per order by income group
Select customer_income_category,
round(avg(quantity_sold * unit_price::numeric),2) as avg_transaction_value
from walmart
group by 1
order by 2 desc;


-- Q15. How do sales compare on holidays vs. non-holidays?
select 
round(sum(case when holiday_indicator = 'true' then (quantity_sold* unit_price)::numeric end),2) as Holiday,
round(sum(case when holiday_indicator = 'false' then (quantity_sold* unit_price)::numeric end),2) as Non_Holiday
from walmart


 -- Q16. What is the percentage of total revenue generated from promotional sales vs. non-promotional sales?
with promotional_sales as (
select 
round(sum(case when promotion_applied is True then (quantity_sold * unit_price) end::numeric),2) as promotional_sales,
round(sum(case when promotion_applied is False then (quantity_sold * unit_price)end::numeric),2) as non_promotional_sales
from walmart)

select 
round(100* promotional_sales/(promotional_sales+non_promotional_sales),2) as promotional_sales_revenue_pct,
round(100* non_promotional_sales/(promotional_sales+non_promotional_sales),2) as non_promotional_sales_revenue_pct
from promotional_sales

-- Q17. Which TOP- 2 products are most popular among high-income customers?
SELECT product_name,
sum(quantity_sold * unit_price) as revenue
from walmart
where customer_income_category = 'High Income'
group by 1 
order by 2 desc
limit 2;


-- Q18. What is the impact of promotions on the quantity of products sold?
SELECT promotion_applied,
    ROUND(AVG(quantity_sold),2) AS avg_quantity_sold,
    SUM(quantity_sold) AS total_quantity_sold,
    COUNT(*) AS total_transactions
FROM walmart
GROUP BY promotion_applied;


-- Q19. Find the peak transaction hours by extracting hour from transaction_date.
select transaction_hour,
round(sum(quantity_sold* unit_price)::numeric,2) as revenue
from walmart
group by 1
order by 1


-- Q20. Analyze the average spending per transaction for each customer loyalty level.
select customer_loyalty_level,
ROUND(AVG(quantity_sold * unit_price)::numeric,2) AS avg_spending_per_transaction
from walmart
group by 1
order by 2 desc

-- Q21. Identify the top performing product in each category.
with top_product as (
SELECT product_name,
category,
round(sum(quantity_sold * unit_price)::numeric,2) as revenue,
rank()over(partition by category order by sum(quantity_sold * unit_price)desc) as rnk
from walmart
group by 1,2
)

SELECT category,
product_name,
revenue 
from top_product
where rnk = 1


-- Q22. Rank Top customers within each income group based on their total spending.
with income_group as (
select customer_id,
customer_income_category,
round(sum(unit_price * quantity_sold)::numeric,2) as total_spending,
rank()over(partition by customer_income_category order by sum(unit_price*quantity_sold)desc) as rnk
from walmart
group by 1,2)

select customer_income_category,
customer_id,
total_spending
from income_group
where rnk = 1


-- Q22. Calculate the cumulative sales growth month by month
select extract(month from transaction_date_only) as mth,
round(sum(quantity_sold * unit_price)::numeric,2) as total_revenue,
round(sum(sum(quantity_sold * unit_price))
	  over(order by extract(month from transaction_date_only))::numeric,2) as cum_sum
from walmart
group by 1


-- Q23. Find the avg revenue growth percentage by promotions.
WITH SalesBeforeAfter AS (
    SELECT 
        promotion_type,
        DATE_TRUNC('month', transaction_date_only) AS month,
        SUM(unit_price * quantity_sold)::numeric AS revenue,
        LAG(SUM(unit_price * quantity_sold)::numeric) OVER (PARTITION BY promotion_type ORDER BY DATE_TRUNC('month', transaction_date_only)) AS prev_month_revenue
    FROM walmart
    WHERE promotion_type IS NOT NULL
    GROUP BY 1, 2
),
GrowthAnalysis AS (
    SELECT 
        promotion_type,
        month,
        revenue,
        prev_month_revenue,
        ROUND(((revenue - prev_month_revenue) / NULLIF(prev_month_revenue, 0)) * 100, 2) AS growth_percentage
    FROM SalesBeforeAfter
)
SELECT 
    promotion_type,
    AVG(growth_percentage) AS avg_growth_percentage
FROM GrowthAnalysis
WHERE growth_percentage IS NOT NULL
GROUP BY promotion_type
ORDER BY avg_growth_percentage DESC;


-- 	Q23. Breakdown monthwise revenue growth trends for each promotion.
WITH SalesBeforeAfter AS (
    SELECT 
        promotion_type,
        DATE_TRUNC('month', transaction_date_only) AS month,
        SUM(unit_price * quantity_sold)::numeric AS revenue,
        LAG(SUM(unit_price * quantity_sold)::numeric) OVER (PARTITION BY promotion_type ORDER BY DATE_TRUNC('month', transaction_date_only)) AS prev_month_revenue
    FROM walmart
    WHERE promotion_type IS NOT NULL
    GROUP BY 1, 2
),
GrowthAnalysis AS (
    SELECT 
        promotion_type,
        month,
        revenue,
        prev_month_revenue,
        ROUND(((revenue - prev_month_revenue) / NULLIF(prev_month_revenue, 0)) * 100, 2) AS growth_percentage
    FROM SalesBeforeAfter
)
SELECT 
    promotion_type,
    month,
    revenue,
    prev_month_revenue,
    growth_percentage,
    AVG(growth_percentage) OVER (PARTITION BY promotion_type) AS avg_growth_percentage
FROM GrowthAnalysis
WHERE growth_percentage IS NOT NULL
ORDER BY promotion_type, month;




--- End Of Project













--Q23. Find the avg revenue growth percentage by promotions.

with salesbeforeafter as (
select promotion_type,
DATE_TRUNC('month',transaction_date_only) as month,
sum(unit_price * quantity_sold)::numeric as revenue,
sum(quantity_sold) as items_sold,
lag(sum(unit_price*quantity_sold)::numeric) over(partition by promotion_type order by date_trunc('month',transaction_date_only)) as prev_month_revenue,
lag(sum(quantity_sold)::numeric) over(partition by promotion_type order by date_trunc('month',transaction_date_only)) as prev_month_item_sold
from walmart
where promotion_type != 'None'
group by 1,2
),

growth_analysis as (
select promotion_type,
	month,
	items_sold,
	prev_month_item_sold,
	round(((items_sold - prev_month_item_sold)/nullif(prev_month_item_sold,0))* 100, 2) as item_growth_perc,
	revenue,
	prev_month_revenue,
	round(((revenue - prev_month_revenue)/nullif(prev_month_revenue,0))* 100, 2) as revenue_growth_perc
	from salesbeforeafter
)

select promotion_type,
month,
items_sold,
prev_month_item_sold,
item_growth_perc,
avg(item_growth_perc) over(partition by promotion_type) avg_item_growth,
revenue,
prev_month_revenue,
revenue_growth_perc,
avg(revenue_growth_perc)over(partition by promotion_type) as avg_growth_perc
from growth_analysis
where item_growth_perc is not null and revenue_growth_perc is not null
order by 1,2








