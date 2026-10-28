# US Commercial Flight Operations & Delay Intelligence System

An end-to-end data engineering and business intelligence reporting pipeline analyzing **1.67M+ commercial flights** across major US carriers (Q1 2026). The project transforms raw Bureau of Transportation Statistics (BTS) telemetry into an optimized **Star Schema** in **PostgreSQL**, driving a multi-page executive dashboard suite in **Power BI** to uncover delay propagation, flight-time recovery efficiency, and cancellation root causes.

---

## 📌 Executive Summary & Key Findings

* **Network Volume & Reliability:** Analyzed **1,671,348 flights** with a system-wide **On-Time Performance (OTP) of 79.03%** (falling -1.21% below the FAA standard 80.00% benchmark) and an average arrival delay of **17.25 minutes**.
* **73.3% Reactionary Delay Snowball:** Direct carrier operations (**35.93%**) and downstream late aircraft turnaround propagation (**37.40%**) generated **over 19.2M of the total 26.27M system delay minutes**.
* **Weather Divergence (Delays vs. Cancellations):** Severe winter storms generated only **7.07% of operational delay minutes**, but accounted for **over 40,000 cancellations** (>75% of all cancellations), demonstrating that winter weather drives proactive ground cancellations rather than extended holding delays.
* **In-Flight Recovery Efficiency:** **Southwest Airlines (-1.99 mins)** and **American Airlines (-0.84 mins)** demonstrated active airborne buffer recovery, whereas regional carriers such as **Republic Airways (+1.74 mins)** and **Envoy Air (+1.11 mins)** consistently lost additional time en route.
* **Primary System Bottleneck:** **Chicago, IL (ORD/MDW)** concentrated over **2.13M delay minutes**, with regional feeder airlines (led by **SkyWest Airlines** with ~593K delay minutes) acting as the main delay transmitters into the national airspace.

---

## 🏗️ Architecture & Technology Stack

```
   Raw BTS CSVs (Q1)
  [JAN, FEB, MAR Telemetry]
              │
              ▼
   PostgreSQL Staging Layer
  [flights_raw] (Staging)
              │
              ▼  SQL Transformations (Type casting, date normalization,
              │                       cancellation nullification, FAA rules)
   PostgreSQL Relational Core
  [Star Schema: Fact Table + Dimensions + B-Tree Indexes]
              │
              ▼  Direct Import / Tabular VertiPaq Engine
   Power BI Semantic Layer
  [DAX Business Logic, Inactive Relationship Modeling, Reference Labels]
              │
              ▼
   Executive Dashboard Suite (3 Pages)
  1. Executive Overview & Fleet Reliability
  2. Airline & Operational Scorecard (Air Recovery & Heatmap)
  3. Root Cause Attribution & Cancellation Breakdown
```

* **Database / ETL:** PostgreSQL 15+
* **Data Modeling:** Star Schema (Kimball Methodology)
* **Analytics Engine:** Power BI Desktop (DAX, VertiPaq)
* **Dataset Source:** US Bureau of Transportation Statistics (BTS) TranStats On-Time Performance Reporting

---

## 📂 Repository Structure

```
├── data/
│   ├── raw/                           # Raw BTS monthly CSV files (Jan, Feb, Mar)
│   └── dim_carriers.csv               # Carrier metadata and classification lookup
├── sql/
│   ├── 01_staging_ddl.sql             # flights_raw table schema and COPY execution
│   ├── 02_transform_fact.sql          # flights_clean fact derivation with data cleaning
│   ├── 03_dimensions_and_indexing.sql # dim_airports, dim_date DDL and B-tree indexes
│   └── 04_analytical_queries.sql      # Benchmark SQL validation scripts
├── power_bi/
│   ├── flight_intelligence.pbix       # Power BI report file
│   └── dax_measures.dax               # Production DAX business logic repository
├── docs/
│   └── screenshots/                   # Dashboard mockups and layout previews
└── README.md
```

---

## 🛠️ Database Setup & SQL Pipeline

### 1. Ingestion Layer (`flights_raw`)
Raw CSV files contain string-formatted numbers, empty string dates, and mixed cancellation flags. Staging uses unconstrained text columns to prevent truncation during bulk load.

```sql
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

COPY flights_raw FROM 'C:/.../T_ONTIME_REPORTING JAN.csv' WITH (FORMAT CSV, HEADER TRUE);
COPY flights_raw FROM 'C:/.../T_ONTIME_REPORTING FEB.csv' WITH (FORMAT CSV, HEADER TRUE);
COPY flights_raw FROM 'C:/.../T_ONTIME_REPORTING MAR.csv' WITH (FORMAT CSV, HEADER TRUE);
```

### 2. Transformation Layer (`flights_clean`)
Data cleaning logic enforces:
1. **Date Normalization:** Extracts pure date tokens and standardizes to `MM/DD/YYYY`.
2. **Scheduled Time Formatting:** Derives departure hour (`(crs_dep_time / 100) % 24`) handling `24:00` rollover.
3. **Cancellation & Diverted Logic:** Enforces `NULL` on delay minutes for cancelled or diverted flights.
4. **FAA 15-Minute Threshold Rule:** Enforces `NULL` on granular cause buckets unless arrival delay flag `arr_del15 = 1`.

```sql
CREATE TABLE flights_clean AS
SELECT
    TO_DATE(SPLIT_PART(NULLIF(fl_date, ''), ' ', 1), 'MM/DD/YYYY') AS fl_date,
    day_of_week::NUMERIC::INT AS day_of_week,
    op_unique_carrier AS carrier,
    origin,
    origin_city_name,
    origin_state_abr,
    dest,
    dest_city_name,
    dest_state_abr,
    crs_dep_time::NUMERIC::INT AS crs_dep_time,
    (crs_dep_time::NUMERIC::INT / 100) % 24 AS crs_dep_hour,
    dep_time::NUMERIC::INT AS dep_time,
    CASE WHEN cancelled::NUMERIC::INT = 1 OR diverted::NUMERIC::INT = 1 THEN NULL ELSE dep_delay::NUMERIC END AS dep_delay,
    CASE WHEN cancelled::NUMERIC::INT = 1 OR diverted::NUMERIC::INT = 1 THEN NULL ELSE dep_delay_new::NUMERIC END AS dep_delay_new,
    dep_del15::NUMERIC::INT AS dep_del15,
    crs_arr_time::NUMERIC::INT AS crs_arr_time,
    arr_time::NUMERIC::INT AS arr_time,
    CASE WHEN cancelled::NUMERIC::INT = 1 OR diverted::NUMERIC::INT = 1 THEN NULL ELSE arr_delay::NUMERIC END AS arr_delay,
    CASE WHEN cancelled::NUMERIC::INT = 1 OR diverted::NUMERIC::INT = 1 THEN NULL ELSE arr_delay_new::NUMERIC END AS arr_delay_new,
    arr_del15::NUMERIC::INT AS arr_del15,
    cancelled::NUMERIC::INT AS cancelled,
    NULLIF(TRIM(cancellation_code), '') AS cancellation_code,
    diverted::NUMERIC::INT AS diverted,
    flights::NUMERIC::INT AS flights,
    distance::NUMERIC AS distance,
    CASE WHEN arr_del15::NUMERIC::INT = 1 THEN carrier_delay::NUMERIC ELSE NULL END AS carrier_delay,
    CASE WHEN arr_del15::NUMERIC::INT = 1 THEN weather_delay::NUMERIC ELSE NULL END AS weather_delay,
    CASE WHEN arr_del15::NUMERIC::INT = 1 THEN nas_delay::NUMERIC ELSE NULL END AS nas_delay,
    CASE WHEN arr_del15::NUMERIC::INT = 1 THEN security_delay::NUMERIC ELSE NULL END AS security_delay,
    CASE WHEN arr_del15::NUMERIC::INT = 1 THEN late_aircraft_delay::NUMERIC ELSE NULL END AS late_aircraft_delay
FROM flights_raw;
```

### 3. Dimensional Modeling & Optimization
* Extracted distinct origin and destination coordinates into a unified `dim_airports` table.
* Generated automated daily dates and calendar flags via `generate_series` in `dim_date`.
* Created lookup definitions for 20 carriers classified into **Mainline**, **Low-cost**, and **Regional**.
* Built B-Tree indexes across join keys to ensure instant execution during Power BI refreshes:

```sql
CREATE INDEX idx_flights_date ON flights_clean(fl_date);
CREATE INDEX idx_flights_carrier ON flights_clean(carrier);
CREATE INDEX idx_flights_origin ON flights_clean(origin);
CREATE INDEX idx_flights_dest ON flights_clean(dest);
```

---

## 📊 Data Model & Relationships

```
        dim_carriers [1] ──── (1:M, Active) ────< [M] flights_clean
                                                        │
        dim_date     [1] ──── (1:M, Active) ────< [M] flights_clean
                                                        │
        dim_airports [1] ──── (1:M, Active) ────< [M] flights_clean (origin)
        dim_airports [1] ─ ─ ─ (1:M, Inactive) ─< [M] flights_clean (dest)
```

> **Inactive Airport Relationship Note:** Destination airport aggregations use Power BI DAX `USERELATIONSHIP('flights_clean'[dest], 'dim_airports'[airport_code])`.

---

## 🧮 Core DAX Measures

### 1. Volume & Operational Reliability
```dax
Total Flights = COUNTROWS('flights_clean')

Cancelled Flights = SUM('flights_clean'[cancelled])

Cancellation Rate = DIVIDE([Cancelled Flights], [Total Flights], 0)

On-Time Arrival % = 
DIVIDE(
    CALCULATE(COUNTROWS('flights_clean'), 'flights_clean'[arr_del15] = 0, 'flights_clean'[cancelled] = 0),
    CALCULATE(COUNTROWS('flights_clean'), 'flights_clean'[cancelled] = 0),
    0
)
```

### 2. Variance & Target Benchmarking (Pill Badge DAX)
```dax
OTP Goal = 0.80

OTP Variance = [On-Time Arrival %] - [OTP Goal]

OTP Variance Label = 
VAR _diff = [OTP Variance]
RETURN
    IF(
        _diff >= 0,
        "▲ +" & FORMAT(_diff, "0.00%") & " vs 80.0% Goal",
        "▼ " & FORMAT(_diff, "0.00%") & " vs 80.0% Goal"
    )
```

### 3. In-Flight Recovery Efficiency
```dax
Delay Difference (Arr - Dep) = 
[Avg Arrival Delay (mins)] - [Avg Departure Delay (mins)]
```
*(Negative values indicate the carrier made up time in the air; positive values indicate delay accumulation in flight).*

### 4. Delay Category Totals
```dax
Total Delay Minutes = 
COALESCE(SUM('flights_clean'[carrier_delay]), 0) +
COALESCE(SUM('flights_clean'[weather_delay]), 0) +
COALESCE(SUM('flights_clean'[nas_delay]), 0) +
COALESCE(SUM('flights_clean'[security_delay]), 0) +
COALESCE(SUM('flights_clean'[late_aircraft_delay]), 0)
```

---

## 🖥️ Dashboard Architecture & Views

### Page 1: Executive Overview & Network Reliability
* **KPI Header Cards:** Total Flights (1.67M), On-Time Arrival % (79.03% with custom dynamic variance pill `▼ -1.21% vs 80.0% Goal`), Average Arrival Delay (17.25 mins), and Cancellation Rate (3.29%).
* **Timeline Analysis:** Dual-axis chart contrasting daily On-Time Arrival % against daily flight cancellations, capturing the late-January severe storm shock where cancellations surged toward 10,000 flights/day.
* **Carrier Rankings:** Horizontal bar chart comparing OTP across all airlines against the 80% standard benchmark.
* **Hourly Congestion Profile:** Column chart demonstrating delay compounding from morning baseline (10.5 mins at 06:00) to evening peak (24.3 mins between 18:00 and 21:00).

### Page 2: Airline & Operational Performance
* **Delay Recovery Scatter Plot:** Evaluates average departure delay vs. average arrival delay. Points below the $y = x$ line represent airlines that consistently recover time in the air.
* **Carrier Operational Scorecard:** High-density matrix displaying total volume, market flight share %, OTP with in-cell data bars, departure delays, recovery deltas, and conditional cancellation gradients.
* **Rush-Hour Heatmap:** Matrix plotting Day of Week (Monday–Sunday) vs. Scheduled Departure Hour (00:00 to 23:00) with 3-color conditional formatting, exposing high-risk red-eye delay spikes (e.g., Sunday 03:00 at 42.9 mins).

### Page 3: Root Cause & Cancellation Breakdown
* **Delay Attribution Donut Chart:** Categorizes system delay minutes across Late Aircraft (37.40%), Carrier (35.93%), NAS/Air Traffic Control (19.42%), Weather (7.07%), and Security (0.18%).
* **Cancellation Reason Bar Chart:** Ranks causes using decoded descriptions (Weather, Carrier/Airline, NAS, Security), isolating severe winter weather as the dominant cause of ground stops (>40K flights).
* **Decomposition Tree:** Interactive root-cause hierarchy exploring total delay minutes:
  `Carrier Type` $\rightarrow$ `Carrier Name` $\rightarrow$ `City / Delay Attribution`.

---

## 📈 Carrier Performance Benchmark Summary

| Carrier | Category | Flight Share % | On-Time Arrival % | Avg Dep Delay (min) | In-Flight Recovery (min) | Cancellation Rate |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **United Airlines** | Mainline | 11.63% | **81.69%** | 13.85 | +0.46 | 1.82% |
| **Delta Air Lines** | Mainline | 14.38% | **81.11%** | 14.12 | +0.12 | 3.23% |
| **Envoy Air** | Regional | 4.40% | **81.09%** | 12.81 | +1.11 | 2.95% |
| **Southwest Airlines** | Mainline | 19.57% | 79.97% | 13.59 | **-1.99** | 1.73% |
| **Alaska Airlines** | Mainline | 4.68% | 79.94% | 12.50 | **-0.23** | 1.71% |
| **SkyWest Airlines** | Regional | 12.07% | 77.72% | 22.20 | +0.55 | 2.75% |
| **Republic Airways** | Regional | 5.31% | 77.33% | 14.66 | +1.74 | 6.94% |
| **American Airlines** | Mainline | 14.01% | 76.51% | 22.25 | **-0.84** | 4.33% |
| **Allegiant Air** | Low-Cost | 1.83% | 75.16% | 22.58 | +1.06 | 1.57% |
| **PSA Airlines** | Regional | 3.48% | 73.34% | 27.29 | -0.01 | **8.04%** |
| **Frontier Airlines** | Low-Cost | 3.03% | 73.29% | 23.19 | +0.29 | 2.78% |
| **JetBlue Airways** | Mainline | 3.43% | 68.88% | 23.28 | +1.01 | 5.25% |
| **Spirit Airlines** | Low-Cost | 2.18% | **64.63%** | 27.65 | -0.17 | **8.58%** |

---

## 🚀 How to Replicate This Project

### Prerequisites
* PostgreSQL 14+ installed locally or via cloud instance.
* Power BI Desktop (November 2023 release or newer for `Card (new)` reference label features).
* BTS Q1 flight CSV dataset placed in your data directory.

### Step 1: Clone and Configure Database
```bash
git clone https://github.com/your-username/us-flight-delay-intelligence.git
cd us-flight-delay-intelligence
```
Execute SQL pipeline scripts sequentially in PostgreSQL / pgAdmin:
```bash
psql -U postgres -d flight_db -f sql/01_staging_ddl.sql
psql -U postgres -d flight_db -f sql/02_transform_fact.sql
psql -U postgres -d flight_db -f sql/03_dimensions_and_indexing.sql
```

### Step 2: Connect Power BI to PostgreSQL
1. Open `Power BI Desktop` $\rightarrow$ **Get Data** $\rightarrow$ **PostgreSQL database**.
2. Specify your server (`localhost:5432`) and database (`flight_db`).
3. Select **Import** mode.
4. Select tables:
   * `flights_clean`
   * `dim_date`
   * `dim_airports`
   * `carriers`
5. Verify model relationships align with the architecture diagram above.
6. Open the **DAX Formula Bar** or paste `sql/dax_measures.dax` into your `_Measures` table.

---

## 📜 License
Distributed under the MIT License. See `LICENSE` for more information.