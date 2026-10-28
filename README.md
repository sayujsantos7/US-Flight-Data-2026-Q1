# US Flight Operations & Delay Intelligence Dashboard (Q1 2026)

An end-to-end analytics project covering **1.67M+ US commercial flights** (January to March 2026). Raw Bureau of Transportation Statistics (BTS) flight records are cleaned and modelled as a **star schema in PostgreSQL**, then analysed in a **3-page Power BI report** to study delay propagation, in-flight time recovery and cancellation causes.

**Tools:** PostgreSQL, SQL, Power BI, DAX, Data Modelling
**Data source:** US Bureau of Transportation Statistics (BTS), TranStats "Reporting Carrier On-Time Performance" (Jan, Feb, Mar 2026)

---

## Dashboard Preview

![Page 1: Executive overview](docs/screenshots/page1_overview.png)
![Page 2: Airline performance](docs/screenshots/page2_performance.png)
![Page 3: Root cause analysis](docs/screenshots/page3_root_cause.png)

---

## Key Findings

* **Network reliability:** Across **1,671,348 flights**, on-time arrival was **79.03%**, which is **1.21 points below an 80% reference target**. The average arrival delay was **17.25 minutes**.
* **Delays compound:** Carrier-caused delays (**35.93%**) and late-arriving aircraft (**37.40%**) together made up **73.3%** of all delay minutes (over 19.2M of 26.27M). Late-aircraft delay is itself a knock-on effect of earlier delays, so most delay minutes trace back to how operations run on the day, not to external factors.
* **Weather causes cancellations more than delays:** Weather accounted for only **7.07%** of delay minutes but for most cancellations (over 40,000 flights). This suggests that during severe winter storms, airlines tend to cancel flights outright instead of holding them.
* **In-flight recovery varies by carrier:** On average, **Southwest (-1.99 min)** and **American (-0.84 min)** arrived with less delay than they departed with, while **Republic (+1.74 min)** and **Envoy (+1.11 min)** lost additional time en route.
* **Largest delay concentration:** **Chicago (ORD/MDW)** accounted for over **2.13M delay minutes**. Regional feeder carriers, led by **SkyWest (~593K delay minutes)**, were among the largest sources of delay in the root-cause decomposition.

---

## Approach

```
Raw BTS CSV files (Jan, Feb, Mar 2026)
        │
        ▼
PostgreSQL staging table: flights_raw (all text columns)
        │
        ▼  SQL: type casting, date standardisation, null handling
PostgreSQL star schema: flights_clean (fact) + dim_date + dim_airports + carriers
        │
        ▼  Import into Power BI
Power BI model: relationships + DAX measures
        │
        ▼
3-page report: Overview | Airline Performance | Root Cause
```

* **Database:** PostgreSQL
* **Modelling:** Star schema (fact table plus date, airport and carrier dimensions)
* **Reporting:** Power BI Desktop (DAX)

---

## Repository Structure

```
├── sql/
│   └── us_flight_data.sql        # Staging, cleaning, dimensions and indexes
├── power_bi/
│   └── dax_measures.dax          # DAX measures used in the report
├── docs/
│   └── screenshots/              # Report page previews
└── README.md
```

The raw BTS files are not included because of their size. Download them from the BTS TranStats site (see Data source above).

---

## SQL Pipeline

### 1. Staging (`flights_raw`)
The raw CSV files contain numbers stored as text, empty date strings and mixed cancellation flags. The staging table uses text columns so the bulk load does not truncate or reject values.

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

### 2. Cleaning (`flights_clean`)
The cleaning step does four things:
1. **Dates:** extracts the date and converts it to a proper `DATE` type.
2. **Scheduled departure hour:** derives the hour with `(crs_dep_time / 100) % 24`, which handles the `24:00` rollover.
3. **Cancelled and diverted flights:** sets delay minutes to `NULL`, since no meaningful delay exists for them.
4. **Delay causes:** keeps cause minutes (carrier, weather, NAS, security, late aircraft) only for flights with `arr_del15 = 1`, following the BTS reporting rule that causes are recorded for arrivals delayed 15 minutes or more.

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

### 3. Dimensions and indexes
* `dim_airports`: distinct origin and destination airports in one table.
* `dim_date`: a daily calendar generated with `generate_series`, with calendar flags.
* `carriers`: a lookup for 20 carriers, classified as **Mainline**, **Low-cost** or **Regional**.
* B-tree indexes on the date, carrier, origin and destination columns to support joins and filtering in the SQL scripts:

```sql
CREATE INDEX idx_flights_date ON flights_clean(fl_date);
CREATE INDEX idx_flights_carrier ON flights_clean(carrier);
CREATE INDEX idx_flights_origin ON flights_clean(origin);
CREATE INDEX idx_flights_dest ON flights_clean(dest);
```

---

## Data Model

```
carriers     [1] ──── (1:M, active)   ────< [M] flights_clean
dim_date     [1] ──── (1:M, active)   ────< [M] flights_clean
dim_airports [1] ──── (1:M, active)   ────< [M] flights_clean (origin)
dim_airports [1] ─ ─ ─ (1:M, inactive) ─< [M] flights_clean (dest)
```

> **Destination airports** use an inactive relationship, activated in DAX with `USERELATIONSHIP('flights_clean'[dest], 'dim_airports'[airport_code])`.

---

## Metric Definitions

* **On-Time Arrival %:** flights arriving less than 15 minutes late (`arr_del15 = 0`) as a share of non-cancelled flights. The 15-minute threshold follows the US DOT and BTS definition of an on-time arrival.
* **80% target:** a reference level used for comparison in this report. It is not an official standard.
* **Delay Difference (Arr - Dep):** average arrival delay minus average departure delay. Negative values mean the carrier made up time in the air.
* **Total Delay Minutes:** the sum of carrier, weather, NAS, security and late-aircraft delay minutes.

---

## Core DAX Measures

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

OTP Goal = 0.80

OTP Variance = [On-Time Arrival %] - [OTP Goal]

OTP Variance Label =
VAR _diff = [OTP Variance]
RETURN
    IF(
        _diff >= 0,
        "▲ +" & FORMAT(_diff, "0.00%") & " vs 80.0% target",
        "▼ " & FORMAT(_diff, "0.00%") & " vs 80.0% target"
    )

Delay Difference (Arr - Dep) =
[Avg Arrival Delay (mins)] - [Avg Departure Delay (mins)]

Total Delay Minutes =
COALESCE(SUM('flights_clean'[carrier_delay]), 0) +
COALESCE(SUM('flights_clean'[weather_delay]), 0) +
COALESCE(SUM('flights_clean'[nas_delay]), 0) +
COALESCE(SUM('flights_clean'[security_delay]), 0) +
COALESCE(SUM('flights_clean'[late_aircraft_delay]), 0)
```

The full set of measures is in `power_bi/dax_measures.dax`.

---

## Report Pages

### Page 1: Executive Overview
* **KPI cards:** Total Flights (1.67M), On-Time Arrival % (79.03%, with a variance label against the 80% target), Average Arrival Delay (17.25 min) and Cancellation Rate (3.29%).
* **Daily timeline:** on-time arrival % against daily cancellations, showing the late-January winter storm, when cancellations rose toward 10,000 flights a day.
* **Carrier ranking:** on-time arrival % by airline against the 80% target.
* **Hourly profile:** average delay rises from 10.5 minutes at 06:00 to a peak of 24.3 minutes between 18:00 and 21:00.

### Page 2: Airline Performance
* **Recovery scatter plot:** average departure delay against average arrival delay. Points below the diagonal are carriers that make up time in the air.
* **Carrier scorecard:** volume, flight share, on-time %, departure delay, recovery and cancellation rate.
* **Heatmap:** day of week against scheduled departure hour, highlighting high-delay slots such as Sunday at 03:00 (42.9 minutes on average).

### Page 3: Root Cause Analysis
* **Delay attribution:** Late Aircraft (37.40%), Carrier (35.93%), NAS / air traffic control (19.42%), Weather (7.07%) and Security (0.18%).
* **Cancellation reasons:** ranked by cause, with severe winter weather the largest.
* **Decomposition tree:** total delay minutes broken down by carrier type, carrier name and city.

---

## Carrier Benchmark (selected carriers)

| Carrier | Category | Flight Share % | On-Time Arrival % | Avg Dep Delay (min) | In-Flight Recovery (min) | Cancellation Rate |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| United Airlines | Mainline | 11.63% | 81.69% | 13.85 | +0.46 | 1.82% |
| Delta Air Lines | Mainline | 14.38% | 81.11% | 14.12 | +0.12 | 3.23% |
| Envoy Air | Regional | 4.40% | 81.09% | 12.81 | +1.11 | 2.95% |
| Southwest Airlines | Mainline | 19.57% | 79.97% | 13.59 | -1.99 | 1.73% |
| Alaska Airlines | Mainline | 4.68% | 79.94% | 12.50 | -0.23 | 1.71% |
| SkyWest Airlines | Regional | 12.07% | 77.72% | 22.20 | +0.55 | 2.75% |
| Republic Airways | Regional | 5.31% | 77.33% | 14.66 | +1.74 | 6.94% |
| American Airlines | Mainline | 14.01% | 76.51% | 22.25 | -0.84 | 4.33% |
| Allegiant Air | Low-cost | 1.83% | 75.16% | 22.58 | +1.06 | 1.57% |
| PSA Airlines | Regional | 3.48% | 73.34% | 27.29 | -0.01 | 8.04% |
| Frontier Airlines | Low-cost | 3.03% | 73.29% | 23.19 | +0.29 | 2.78% |
| JetBlue Airways | Mainline | 3.43% | 68.88% | 23.28 | +1.01 | 5.25% |
| Spirit Airlines | Low-cost | 2.18% | 64.63% | 27.65 | -0.17 | 8.58% |

---

## How to Reproduce

**Requirements:** PostgreSQL 14 or newer, Power BI Desktop (November 2023 release or newer), and the BTS Q1 2026 CSV files.

1. **Get the data.** Download the Jan, Feb and Mar 2026 files from BTS TranStats (Reporting Carrier On-Time Performance) with the columns used in `flights_raw`.
2. **Create the database and run the SQL.** Update the file paths in the `COPY` commands to match where you saved the CSV files, then run:
   ```bash
   git clone https://github.com/sayujsantos7/US-Flight-Data-2026-Q1.git
   cd US-Flight-Data-2026-Q1
   psql -U postgres -d flight_db -f sql/us_flight_data.sql
   ```
3. **Connect Power BI.** Open Power BI Desktop, choose **Get Data > PostgreSQL database**, enter your server (for example `localhost:5432`) and database (`flight_db`), and select **Import** mode.
4. **Load the tables:** `flights_clean`, `dim_date`, `dim_airports` and `carriers`.
5. **Check the relationships** against the data model above, then add the measures from `power_bi/dax_measures.dax` to a measures table.
