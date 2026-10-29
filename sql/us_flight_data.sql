CREATE TABLE flights_raw (
  day_of_week TEXT, fl_date TEXT, op_unique_carrier TEXT,
  origin TEXT, origin_city_name TEXT, origin_state_abr TEXT,
  dest TEXT, dest_city_name TEXT, dest_state_abr TEXT,
  crs_dep_time TEXT, dep_time TEXT, dep_delay TEXT, dep_delay_new TEXT, dep_del15 TEXT,
  crs_arr_time TEXT, arr_time TEXT, arr_delay TEXT, arr_delay_new TEXT, arr_del15 TEXT,
  cancelled TEXT, cancellation_code TEXT, diverted TEXT, flights TEXT, distance TEXT,
  carrier_delay TEXT, weather_delay TEXT, nas_delay TEXT,
  security_delay TEXT, late_aircraft_delay TEXT
);

COPY flights_raw FROM 'C:/Users/Public/Documents/US Flight Project/T_ONTIME_REPORTING/T_ONTIME_REPORTING JAN.csv' WITH (FORMAT CSV, HEADER TRUE)

COPY flights_raw FROM 'C:/Users/Public/Documents/US Flight Project/T_ONTIME_REPORTING/T_ONTIME_REPORTING FEB.csv' WITH (FORMAT CSV, HEADER TRUE)

COPY flights_raw FROM 'C:/Users/Public/Documents/US Flight Project/T_ONTIME_REPORTING/T_ONTIME_REPORTING MAR.csv' WITH (FORMAT CSV, HEADER TRUE)

CREATE TABLE flights_clean AS
SELECT
  -- Robust date conversion: strips time portion, enforces US date order (MM/DD/YYYY)
  TO_DATE(SPLIT_PART(NULLIF(fl_date, ''), ' ', 1), 'MM/DD/YYYY') AS fl_date,
  
  day_of_week::NUMERIC::INT                                     AS day_of_week,
  op_unique_carrier                                             AS carrier,
  origin, 
  origin_city_name, 
  origin_state_abr,
  dest, 
  dest_city_name, 
  dest_state_abr,
  
  crs_dep_time::NUMERIC::INT                                   AS crs_dep_time,
  -- Rule 1: Midnight / Hour derivation (handles 2400 gracefully)
  (crs_dep_time::NUMERIC::INT / 100) % 24                      AS crs_dep_hour,
  dep_time::NUMERIC::INT                                       AS dep_time,
  
  -- Rule 3: Nullify delay numbers for cancelled or diverted flights
  CASE 
    WHEN cancelled::NUMERIC::INT = 1 OR diverted::NUMERIC::INT = 1 THEN NULL 
    ELSE dep_delay::NUMERIC 
  END                                                          AS dep_delay,
  
  CASE 
    WHEN cancelled::NUMERIC::INT = 1 OR diverted::NUMERIC::INT = 1 THEN NULL 
    ELSE dep_delay_new::NUMERIC 
  END                                                          AS dep_delay_new,
  
  dep_del15::NUMERIC::INT                                      AS dep_del15,
  crs_arr_time::NUMERIC::INT                                   AS crs_arr_time,
  arr_time::NUMERIC::INT                                       AS arr_time,
  
  CASE 
    WHEN cancelled::NUMERIC::INT = 1 OR diverted::NUMERIC::INT = 1 THEN NULL 
    ELSE arr_delay::NUMERIC 
  END                                                          AS arr_delay,
  
  CASE 
    WHEN cancelled::NUMERIC::INT = 1 OR diverted::NUMERIC::INT = 1 THEN NULL 
    ELSE arr_delay_new::NUMERIC 
  END                                                          AS arr_delay_new,
  
  arr_del15::NUMERIC::INT                                      AS arr_del15,
  cancelled::NUMERIC::INT                                      AS cancelled,
  NULLIF(TRIM(cancellation_code), '')                         AS cancellation_code,
  diverted::NUMERIC::INT                                       AS diverted,
  flights::NUMERIC::INT                                        AS flights,
  distance::NUMERIC                                            AS distance,
  
  -- Rule 2: Keep delay causes NULL unless ARR_DEL15 = 1
  CASE WHEN arr_del15::NUMERIC::INT = 1 THEN carrier_delay::NUMERIC ELSE NULL END       AS carrier_delay,
  CASE WHEN arr_del15::NUMERIC::INT = 1 THEN weather_delay::NUMERIC ELSE NULL END       AS weather_delay,
  CASE WHEN arr_del15::NUMERIC::INT = 1 THEN nas_delay::NUMERIC ELSE NULL END           AS nas_delay,
  CASE WHEN arr_del15::NUMERIC::INT = 1 THEN security_delay::NUMERIC ELSE NULL END      AS security_delay,
  CASE WHEN arr_del15::NUMERIC::INT = 1 THEN late_aircraft_delay::NUMERIC ELSE NULL END AS late_aircraft_delay

FROM flights_raw;

-- 1. total rows (510,000 + 544,000 + 612,100 is about 1,666,100)
SELECT COUNT(*) FROM flights_clean;

-- 2. dates parsed correctly, no month leakage
SELECT DATE_TRUNC('month', fl_date) AS MONTH, COUNT(*), MIN(fl_date), MAX(fl_date) 
FROM flights_clean GROUP BY 1 ORDER BY 1;

-- 3. nothing silently turned NULL
SELECT COUNT(*) FROM flights_clean WHERE fl_date IS NULL OR carrier IS NULL OR origin IS NULL;

-- 4. the cause-sum validation test
SELECT COUNT(*) AS delayed_flights,
       SUM(CASE WHEN ABS(arr_delay - (carrier_delay + weather_delay + nas_delay
            + security_delay + late_aircraft_delay)) < 1 THEN 1 ELSE 0 END) AS matching
FROM flights_clean
WHERE arr_del15 = 1 AND cancelled = 0 AND diverted = 0 AND carrier_delay IS NOT NULL;

-- 5. any delayed flight that lacks cause data? should equal 350737
SELECT COUNT(*) FROM flights_clean
WHERE arr_del15 = 1 AND cancelled = 0 AND diverted = 0;

-- 6. flag consistency: arr_del15 should agree with arr_delay >= 15
SELECT COUNT(*) FROM flights_clean
WHERE cancelled = 0 AND diverted = 0
  AND (arr_del15 = 1) <> (arr_delay >= 15);

-- 7. hour range should be 0-23, cancellation codes only A/B/C/D
SELECT MIN(crs_dep_hour), MAX(crs_dep_hour) FROM flights_clean;
SELECT cancellation_code, COUNT(*) FROM flights_clean GROUP BY 1 ORDER BY 1;

-- 8. headline numbers
SELECT COUNT(*) AS flights,
       SUM(cancelled) AS cancelled,
       SUM(diverted) AS diverted,
       ROUND(100.0 * SUM(arr_del15) / NULLIF(SUM(CASE WHEN cancelled = 0 AND diverted = 0 THEN 1 END), 0), 1) AS pct_arr_delayed
FROM flights_clean;

---9. The empty result rules that story out: all 350,757 delayed flights have cause data, but 20 of them don’t reconcile with their arrival delay. That is a 99.994% match rate
SELECT fl_date, carrier, origin, dest, arr_delay,
       carrier_delay, weather_delay, nas_delay, security_delay, late_aircraft_delay,
       carrier_delay + weather_delay + nas_delay + security_delay + late_aircraft_delay AS cause_sum,
       arr_delay - (carrier_delay + weather_delay + nas_delay + security_delay + late_aircraft_delay) AS diff
FROM flights_clean
WHERE arr_del15 = 1 AND cancelled = 0 AND diverted = 0
  AND (carrier_delay + weather_delay + nas_delay + security_delay + late_aircraft_delay IS NULL
       OR ABS(arr_delay - (carrier_delay + weather_delay + nas_delay + security_delay + late_aircraft_delay)) >= 1)
ORDER BY ABS(arr_delay - (carrier_delay + weather_delay + nas_delay + security_delay + late_aircraft_delay)) DESC NULLS FIRST;

---10. The cause columns in those 20 rows are 0, not NULL and not rounding errors
ALTER TABLE flights_clean ADD COLUMN unattributed_delay NUMERIC;

UPDATE flights_clean
SET unattributed_delay = arr_delay - (carrier_delay + weather_delay + nas_delay
                                      + security_delay + late_aircraft_delay)
WHERE arr_del15 = 1 AND cancelled = 0 AND diverted = 0;

---11. Verify with check, which also shows how small the gap is:
SELECT SUM(unattributed_delay) AS unattributed_min,
       SUM(arr_delay) AS total_delay_min,
       ROUND(100.0 * SUM(unattributed_delay) / SUM(arr_delay), 3) AS pct
FROM flights_clean
WHERE arr_del15 = 1 AND cancelled = 0 AND diverted = 0;

---12. airport ranking query (top 20 origins by flight count)
CREATE INDEX ON flights_clean (origin);
CREATE INDEX ON flights_clean (fl_date);

SELECT origin, origin_city_name, COUNT(*) AS flights
FROM flights_clean
GROUP BY origin, origin_city_name
ORDER BY flights DESC
LIMIT 20;

WITH top20 AS (
  SELECT origin FROM flights_clean GROUP BY origin ORDER BY COUNT(*) DESC LIMIT 20
)
SELECT f.origin,
  ROUND(100.0*SUM(carrier_delay)/SUM(arr_delay),1)       AS carrier_pct,
  ROUND(100.0*SUM(weather_delay)/SUM(arr_delay),1)       AS weather_pct,
  ROUND(100.0*SUM(nas_delay)/SUM(arr_delay),1)           AS nas_pct,
  ROUND(100.0*SUM(late_aircraft_delay)/SUM(arr_delay),1) AS late_aircraft_pct
FROM flights_clean f JOIN top20 t ON t.origin = f.origin
WHERE arr_del15 = 1 AND cancelled = 0 AND diverted = 0
GROUP BY f.origin
ORDER BY nas_pct DESC;

CREATE TABLE carriers (carrier TEXT PRIMARY KEY, carrier_name TEXT, carrier_type TEXT);
INSERT INTO carriers VALUES
('AA','American Airlines','Mainline'),('DL','Delta Air Lines','Mainline'),
('UA','United Airlines','Mainline'),('WN','Southwest Airlines','Mainline'),
('AS','Alaska Airlines','Mainline'),('B6','JetBlue Airways','Mainline'),
('HA','Hawaiian Airlines','Mainline'),
('NK','Spirit Airlines','Low-cost'),('F9','Frontier Airlines','Low-cost'),
('G4','Allegiant Air','Low-cost'),
('OO','SkyWest Airlines','Regional'),('MQ','Envoy Air','Regional'),
('OH','PSA Airlines','Regional'),('YX','Republic Airways','Regional'),
('9E','Endeavor Air','Regional'),('YV','Mesa Airlines','Regional'),
('QX','Horizon Air','Regional'),('ZW','Air Wisconsin','Regional'),
('C5','CommuteAir','Regional'),('G7','GoJet Airlines','Regional');

SELECT * FROM carriers;

-- codes in your data that the lookup doesn't cover
SELECT DISTINCT f.carrier FROM flights_clean f
LEFT JOIN carriers c ON c.carrier = f.carrier WHERE c.carrier IS NULL;

---Add indexes to your cleaned fact table (flights_clean) on columns commonly used for joins, filtering, and time-series aggregation:
CREATE INDEX idx_flights_date ON flights_clean(fl_date);
CREATE INDEX idx_flights_carrier ON flights_clean(carrier);
CREATE INDEX idx_flights_origin ON flights_clean(origin);
CREATE INDEX idx_flights_dest ON flights_clean(dest);


--- Create a dimension table for airports
CREATE TABLE dim_airports (
    airport_code VARCHAR(10) PRIMARY KEY,
    city_name TEXT,
    state_abr VARCHAR(10)
);

-- Extract all unique airports from both origin and destination
INSERT INTO dim_airports (airport_code, city_name, state_abr)
SELECT DISTINCT
    origin AS airport_code,
    origin_city_name AS city_name,
    origin_state_abr AS state_abr
FROM flights_clean
WHERE origin IS NOT NULL
UNION
SELECT DISTINCT
    dest AS airport_code,
    dest_city_name AS city_name,
    dest_state_abr AS state_abr
FROM flights_clean
WHERE dest IS NOT NULL
ON CONFLICT (airport_code) DO NOTHING;

---create a dimension table for dates

CREATE TABLE dim_date (
    date_id DATE PRIMARY KEY,
    YEAR INT,
    quarter INT,
    quarter_name VARCHAR(10),
    month_num INT,
    month_name VARCHAR(20),
    month_year VARCHAR(20),
    week_of_year INT,
    day_of_month INT,
    day_of_week INT,
    day_name VARCHAR(20),
    is_weekend BOOLEAN
);

-- Populate dates dynamically based on your flights_clean date range
INSERT INTO dim_date (
    date_id,
    YEAR,
    quarter,
    quarter_name,
    month_num,
    month_name,
    month_year,
    week_of_year,
    day_of_month,
    day_of_week,
    day_name,
    is_weekend
)
SELECT
    d::DATE AS date_id,
    EXTRACT(YEAR FROM d)::INT AS YEAR,
    EXTRACT(QUARTER FROM d)::INT AS quarter,
    'Q' || EXTRACT(QUARTER FROM d)::TEXT AS quarter_name,
    EXTRACT(MONTH FROM d)::INT AS month_num,
    TO_CHAR(d, 'Month') AS month_name,
    TO_CHAR(d, 'Mon-YYYY') AS month_year,
    EXTRACT(WEEK FROM d)::INT AS week_of_year,
    EXTRACT(DAY FROM d)::INT AS day_of_month,
    EXTRACT(ISODOW FROM d)::INT AS day_of_week,  -- 1 = Monday, 7 = Sunday
    TO_CHAR(d, 'Day') AS day_name,
    CASE WHEN EXTRACT(ISODOW FROM d) IN (6, 7) THEN TRUE ELSE FALSE END AS is_weekend
FROM (
    SELECT generate_series(
        (SELECT MIN(fl_date) FROM flights_clean),
        (SELECT MAX(fl_date) FROM flights_clean),
        INTERVAL '1 day'
    ) AS d
) sub;

-- Check airport count and sample
SELECT COUNT(*) FROM dim_airports;
SELECT * FROM dim_airports LIMIT 5;

-- Check date coverage
SELECT MIN(date_id), MAX(date_id), COUNT(*) FROM dim_date;



