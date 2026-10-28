# DAX Measures & Business Logic Dictionary
### Project: US Flight Operations & Delay Intelligence System
**Technology Stack:** Power BI, DAX, Tabular Modeling, PostgreSQL  
**Dataset Scope:** Q1 US Domestic Commercial Flights (~1.67M records)

---

## Overview

This repository document serves as the data dictionary and technical documentation for all Data Analysis Expressions (DAX) created in the **US Flight Operations & Delay Intelligence Dashboard**.

In enterprise reporting, keeping business logic clean, standardized, and isolated from UI layers is crucial. All metrics below were authored within a dedicated `_Measures` table, adhering to standard FAA and Bureau of Transportation Statistics (BTS) aviation reporting standards.

---

## 1. Flight Volume & Fleet Reliability

### `[Total Flights]`
* **Formula:**
  ```dax
  Total Flights = COUNTROWS('flights_clean')
  ```
* **Why It Was Made:** Serves as the universal base operational metric representing all scheduled flight operations in the reporting period.
* **Why & Where It Is Used:** Acts as the base denominator for rates (such as Cancellation Rate and Route Concentration) across executive summary cards, scatter plot bubble radii, and volume distribution charts.

---

### `[Cancelled Flights]`
* **Formula:**
  ```dax
  Cancelled Flights = SUM('flights_clean'[cancelled])
  ```
* **Why It Was Made:** Quantifies operations terminated prior to completion (`cancelled = 1`).
* **Why & Where It Is Used:** Used to monitor operational disruptions, populate cancellation root-cause charts, and construct the secondary axis on the daily trend visual to isolate severe shock periods (such as winter storms).

---

### `[Cancellation Rate]`
* **Formula:**
  ```dax
  Cancellation Rate = DIVIDE([Cancelled Flights], [Total Flights], 0)
  ```
* **Why It Was Made:** Provides an operational risk ratio evaluating fleet vulnerability across airlines and airport hubs, irrespective of scheduling scale.
* **Why & Where It Is Used:** Featured on Page 1 Executive KPI cards and the Page 2 Carrier Scorecard table with conditional background highlighting to flag distressed operators (e.g., PSA Airlines and Spirit Airlines at >8% cancellation rates).

---

### `[Diverted Flights]`
* **Formula:**
  ```dax
  Diverted Flights = SUM('flights_clean'[diverted])
  ```
* **Why It Was Made:** Isolates flights dispatched that could not land at their planned destination airport due to weather, fuel, or emergency events.
* **Why & Where It Is Used:** Used in data auditing and operational reconciliation views to ensure diverted flights are properly excluded from standard gate arrival delay benchmarks.

---

### `[Completed Flights]`
* **Formula:**
  ```dax
  Completed Flights = 
  CALCULATE(
      COUNTROWS('flights_clean'),
      'flights_clean'[cancelled] = 0,
      'flights_clean'[diverted] = 0
  )
  ```
* **Why It Was Made:** Calculates true revenue-producing operations that pushed back from the gate, flew the route, and arrived at the designated destination runway.
* **Why & Where It Is Used:** Establishes the clean population of arrivals needed for delay calculations without distorting averages with missing gate telemetry.

---

## 2. On-Time Performance (OTP) & Delay Duration

### `[Delayed Arrivals]`
* **Formula:**
  ```dax
  Delayed Arrivals = 
  CALCULATE(
      COUNTROWS('flights_clean'),
      'flights_clean'[arr_del15] = 1,
      'flights_clean'[cancelled] = 0
  )
  ```
* **Why It Was Made:** Counts operations meeting the federal benchmark definition of a late flight (arriving 15 minutes or more past scheduled gate arrival time: `arr_del15 = 1`).
* **Why & Where It Is Used:** Serves as the numerator for evaluating failure rates, triggering delay cause attribution analyses, and driving the Data Quality match test.

---

### `[On-Time Arrival %]`
* **Formula:**
  ```dax
  On-Time Arrival % = 
  DIVIDE(
      CALCULATE(COUNTROWS('flights_clean'), 'flights_clean'[arr_del15] = 0, 'flights_clean'[cancelled] = 0),
      CALCULATE(COUNTROWS('flights_clean'), 'flights_clean'[cancelled] = 0),
      0
  )
  ```
* **Why It Was Made:** The primary aviation industry KPI (A14/OTP) mandated by the US Department of Transportation. Flights arriving within 14 minutes of schedule are categorized as on-time. Cancelled flights are excluded from the denominator to avoid double-penalizing on-time arrival metrics.
* **Why & Where It Is Used:** Central callout on Page 1 KPI cards, the daily reliability timeline, and as the primary sorting metric on the Carrier Performance Matrix.

---

### `[Avg Arrival Delay (mins)]`
* **Formula:**
  ```dax
  Avg Arrival Delay (mins) = AVERAGE('flights_clean'[arr_delay_new])
  ```
* **Why It Was Made:** Quantifies passenger-experienced gate delay. Using `arr_delay_new` truncates negative values (early arrivals) to zero, preventing flights arriving 20 minutes early from mathematically masking flights arriving 20 minutes late.
* **Why & Where It Is Used:** Primary metric on the Executive Overview card and the vertical axis ($Y$) of the carrier efficiency scatter plot.

---

### `[Avg Departure Delay (mins)]`
* **Formula:**
  ```dax
  Avg Departure Delay (mins) = AVERAGE('flights_clean'[dep_delay_new])
  ```
* **Why It Was Made:** Measures airport terminal and gate pushback friction before en-route flight dynamics come into play.
* **Why & Where It Is Used:** Powers the Day-of-Week vs. Departure-Hour heatmap and forms the horizontal axis ($X$) on the scatter plot.

---

## 3. Delay Cause Attribution (Minutes)

Per Bureau of Transportation Statistics standards, delay minutes are attributed to 5 specific buckets only when a flight arrives 15 or more minutes late.

### `[Total Delay Minutes]`
* **Formula:**
  ```dax
  Total Delay Minutes = 
  COALESCE(SUM('flights_clean'[carrier_delay]), 0) +
  COALESCE(SUM('flights_clean'[weather_delay]), 0) +
  COALESCE(SUM('flights_clean'[nas_delay]), 0) +
  COALESCE(SUM('flights_clean'[security_delay]), 0) +
  COALESCE(SUM('flights_clean'[late_aircraft_delay]), 0)
  ```
* **Why It Was Made:** Aggregates gross delay time across all categorized sources, providing a single metric for financial and operational impact.
* **Why & Where It Is Used:** Primary metric evaluated in the Decomposition Tree on Page 3 and the total magnitude indicator in executive reports (~26.27M minutes).

---

### `[Carrier Delay Minutes]`
* **Formula:**
  ```dax
  Carrier Delay Minutes = SUM('flights_clean'[carrier_delay])
  ```
* **Why It Was Made:** Isolates delay time within airline operational control (e.g., aircraft cleaning, baggage loading, fueling, crew duty timeouts, scheduled maintenance).
* **Why & Where It Is Used:** Displayed on Page 3 Donut Chart and Root-Cause Decomposition Tree; reveals that ~35.9% of system delays stem directly from internal airline operations.

---

### `[Late Aircraft Delay Minutes]`
* **Formula:**
  ```dax
  Late Aircraft Delay Minutes = SUM('flights_clean'[late_aircraft_delay])
  ```
* **Why It Was Made:** Captures compounding, downstream network delays where a flight departs late specifically because its inbound aircraft arrived late on a prior leg.
* **Why & Where It Is Used:** Used in the Page 3 Root Cause breakdown to demonstrate that reactionary delays represent the largest single bucket (37.4%), highlighting fleet turnaround vulnerability.

---

### `[NAS Delay Minutes]`
* **Formula:**
  ```dax
  NAS Delay Minutes = SUM('flights_clean'[nas_delay])
  ```
* **Why It Was Made:** Measures National Aviation System inefficiencies managed by the Federal Aviation Administration (FAA), such as air traffic control (ATC) spacing, airport throughput constraints, and non-extreme weather metering.
* **Why & Where It Is Used:** Used in Page 3 Root Cause attribution to benchmark infrastructure and air-traffic congestion vs. carrier operations.

---

### `[Weather Delay Minutes]`
* **Formula:**
  ```dax
  Weather Delay Minutes = SUM('flights_clean'[weather_delay])
  ```
* **Why It Was Made:** Measures severe, non-routine meteorological conditions (e.g., blizzards, hurricanes, active thunderstorms) that physically halt ground operations or force airborne holdings.
* **Why & Where It Is Used:** Used to contrast delay duration vs. cancellation impact. Demonstrates that while weather accounts for only 7.07% of delay minutes, it is the primary driver of total cancellations (>40K flights).

---

### `[Security Delay Minutes]`
* **Formula:**
  ```dax
  Security Delay Minutes = SUM('flights_clean'[security_delay])
  ```
* **Why It Was Made:** Tracks airport security breaches, terminal evacuations, and TSA screening delays.
* **Why & Where It Is Used:** Included in delay attribution auditing to confirm security represents a minimal portion (<0.2%) of overall operational disruption.

---

## 4. Airline Operations & Efficiency Diagnostics

### `[Delay Difference (Arr - Dep)]`
* **Formula:**
  ```dax
  Delay Difference (Arr - Dep) = 
  [Avg Arrival Delay (mins)] - [Avg Departure Delay (mins)]
  ```
* **Why It Was Made:** Evaluates flight-time buffer efficiency and operational resilience.
  * **Negative values** indicate an airline absorbs pushback delay by making up time en route or via schedule padding.
  * **Positive values** mean delays compound further during cruise or taxi-in.
* **Why & Where It Is Used:** Core metric in the Page 2 Carrier Scorecard. Highlights that carriers like Southwest (-1.99 min) and American Airlines (-0.84 min) absorb delays, whereas regional carriers like Republic Airways (+1.74 min) lose additional time.

---

### `[Flight Share %]`
* **Formula:**
  ```dax
  Flight Share % = 
  DIVIDE([Total Flights], CALCULATE([Total Flights], ALLSELECTED('carriers')), 0)
  ```
* **Why It Was Made:** Calculates relative market and scheduling share while maintaining dynamic responsiveness to external page slicers.
* **Why & Where It Is Used:** Used on the Page 2 Scorecard to provide capacity context (e.g., Southwest managing ~19.6% of flight volume vs. regional carriers managing 2–4%).

---

### `[Flights by Destination]`
* **Formula:**
  ```dax
  Flights by Destination = 
  CALCULATE(
      [Total Flights],
      USERELATIONSHIP('flights_clean'[dest], 'dim_airports'[airport_code])
  )
  ```
* **Why It Was Made:** Power BI allows only one active relationship between `flights_clean` and `dim_airports` (assigned to `origin`). This measure activates the secondary relationship to analyze arrival hubs without circular schema conflicts.
* **Why & Where It Is Used:** Powers destination airport volume rankings and route corridor diagnostics.

---

## 5. Executive Reference Labels & Target Indicators

### `[OTP Goal]`
* **Formula:**
  ```dax
  OTP Goal = 0.80
  ```
* **Why It Was Made:** Stores the industry-standard 80.0% on-time benchmark as a reusable measure for KPI cards and conditional formatting.
* **Why & Where It Is Used:** Serves as the comparison baseline for delta labels and reference lines across charts.

---

### `[OTP Variance]`
* **Formula:**
  ```dax
  OTP Variance = [On-Time Arrival %] - [OTP Goal]
  ```
* **Why It Was Made:** Computes the mathematical deviation from the operational target (e.g., $79.03\% - 80.00\% = -0.97\%$).
* **Why & Where It Is Used:** Used as the conditional formatting driver for color states (red for negative variance, green for positive).

---

### `[OTP Delta Label]`
* **Formula:**
  ```dax
  OTP Delta Label = 
  VAR _diff = [OTP Variance]
  RETURN
      IF(
          _diff >= 0,
          "▲ +" & FORMAT(_diff, "0.00%") & " vs 80.0% Goal",
          "▼ " & FORMAT(_diff, "0.00%") & " vs 80.0% Goal"
      )
  ```
* **Why It Was Made:** Dynamically generates a formatted status string complete with trend arrows and goal context for executive review.
* **Why & Where It Is Used:** Embedded directly into the modern Power BI New Card visual as a **Reference Label (Delta Pill)** on the Page 1 Executive Overview.

---

## 6. Data Quality & Modeling Enhancements

### `[Validation_Match_Rate]`
* **Formula:**
  ```dax
  Validation_Match_Rate = 
  DIVIDE(
      CALCULATE(COUNTROWS('flights_clean'), 'flights_clean'[is_cause_sum_validated] = 1),
      CALCULATE(COUNTROWS('flights_clean'), 'flights_clean'[arr_del15] = 1)
  )
  ```
* **Why It Was Made:** Validates internal dataset integrity. For flights delayed $\ge 15$ minutes, the sum of the 5 delay breakdown fields must reconcile with total `arr_delay`.
* **Why & Where It Is Used:** Displayed on data architecture and audit scorecards, validating that over 99% of delayed records cleanly tie out against federal reporting guidelines.

---

### `Cancellation Reason` *(Calculated Column)*
* **Formula:**
  ```dax
  Cancellation Reason = 
  SWITCH(
      'flights_clean'[cancellation_code],
      "A", "Carrier / Airline",
      "B", "Weather",
      "C", "National Air System (NAS)",
      "D", "Security",
      BLANK()
  )
  ```
* **Why It Was Made:** Converts single-character BTS categorical codes (`A`, `B`, `C`, `D`) into human-readable business terminology.
* **Why & Where It Is Used:** Used as the category axis for the Cancellation Volume Bar Chart on Page 3, ensuring clean presentation without unassigned blanks.