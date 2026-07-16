# Pipeline Logic — 12-Step SKU Gap Recommendation

## Overview

| | |
|---|---|
| **Goal** | For each vendor, identify the top 3 popular products they don't carry and estimate the revenue opportunity |
| **Scope** | 64 markets across 6 platforms, all NKP (non-key-partner) vendors |
| **Frequency** | Monthly — after alias tables are refreshed and previous month's order data is available |
| **Output** | One row per vendor with top 3 gap products, revenue estimates, and product metadata |

## Dual Alias Strategy

The pipeline uses **two** alias tables simultaneously for different purposes:

| Table | Version | Used for | Why this version |
|---|---|---|---|
| `alias_table_consevative` | Conservative | Sales aggregation, revenue ranking, product metadata | Revenue numbers must be accurate — over-merging inflates metrics |
| `alias_table_aggressive` | Aggressive | Vendor catalog matching, gap detection, private label filter | Must catch all name variants — missing a match = false gap recommendation |

A **bridge CTE** connects the two via shared `catalog_master_product_id` values, so demand rankings (conservative) can be checked against vendor catalogs (aggressive).

## Step-by-Step Pipeline

### Step 1a–1b: Load Alias Tables

Read both conservative and aggressive alias tables from BigQuery.

- Non-Glovo platforms: `vendor_crm_comms_use_case_alias_table_consevative` / `_aggressive`
- Glovo: `vendor_crm_comms_use_case_alias_table_GV` / `_GV_supply` (dedicated tables for performance)

### Step 2a–2b: Map Products to Aliases

Link each `platform_product_id` to its alias group in both tables.

Uses pre-built lookup table `vendor_crm_comms_product_alias_lookup` to avoid scanning the full catalog at runtime.

**Dedup logic:** `ROW_NUMBER() OVER (PARTITION BY platform_product_id ORDER BY created_at DESC)` — if a product maps to multiple alias groups, take the most recent.

### Step 3: Product Metadata

Get display information (name, image URL, barcode) for each alias group's **primary product** — the canonical representative.

**Filter:** `WHERE catalog_master_product_id = alias_product_id` — only the primary product in each group.

Uses pre-built `vendor_crm_comms_product_metadata` table.

### Step 3b: Bridge CTE

Map conservative alias IDs to aggressive alias IDs via shared `catalog_master_product_id` values.

Uses pre-built `vendor_crm_comms_demand_supply_bridge` table.

This is critical: demand rankings come from conservative aliases, but vendor catalog checks use aggressive aliases. The bridge lets us compare them.

### Step 4: Vendor Dimensions

Get vendor info from `ls_vps_stg_monthly`:

| Field | Description |
|---|---|
| `platform_vendor_id` | Vendor identifier |
| `vendor_name` | Display name |
| `chain_name` | Chain affiliation |
| `city` | City for geographic targeting |
| `vertical_segment` | Business vertical (kiosk, grocery, etc.) |
| `sessions` | Monthly session traffic |
| `gmv_eur` | Monthly gross merchandise value |
| `vps` | Vendor performance score |

**Filters applied:**
- `report_month = current month`
- `vertical NOT LIKE '%dark%'` — exclude dark stores (managed centrally)
- `is_key_partner IS FALSE` — exclude key partners (have dedicated account managers)

### Step 5: Active SKUs

Find products that were actually available for purchase during the month.

**Filter:** `SUM(daily_buyable_rate_eligible_ref) > 0`

A product must have been buyable at least once (active for ≥ 1 second) during the month to be included.

### Step 6: Vendor Active Catalog

Build each vendor's current product list using the **aggressive** alias table.

This is where aggressive matching matters most: if a vendor sells "Coca Cola 500ml Lata" and the top product is "Coca Cola 500ml", aggressive matching merges them — so we don't falsely recommend a product the vendor already carries.

### Step 7: Vendor Sales

Aggregate `quantity_sold` and `revenue_eur` per vendor × alias product using the **conservative** alias table.

**Filter:** `is_successful = TRUE` — only completed orders.

Conservative alias keeps revenue figures accurate for the vendor email.

### Step 8: Market-Level Metrics

Calculate total demand per product per (market, vertical, city).

**Quality gates:**
- `flat_avg_revenue >= €100/vendor` — filter out very low-value items not worth recommending
- `flat_avg_qty > 1/vendor` — filter out accidental one-time purchases

### Step 9: Private Label Filter

Exclude products sold by only 1 chain.

**Filter:** `num_chains >= 2`

**Rationale:** If only one chain sells a product, it's likely a private label or exclusive distribution item. The vendor can't source it, so recommending it would be unhelpful.

Uses aggressive alias via bridge to count chains correctly.

### Step 10: Top 10 Ranking

Rank products by `total_quantity_sold` per (entity, vertical, city).

**Filter:** `RANK() <= 10`

Top 10 most-demanded products in each market/vertical/city combination.

### Step 11: Gap Detection

For each vendor: which top-10 products do they NOT carry?

**Logic:** `NOT EXISTS` — check if the vendor's active catalog (aggressive alias) contains each top-10 product.

Uses aggressive matching via bridge to minimize false gaps.

### Step 12: Top 3 Per Vendor

Pick the 3 highest-ranked gaps per vendor.

**Filter:** `ROW_NUMBER() <= 3`

**Why 3:** Actionable email limit. Recommending 10+ products overwhelms the vendor. 3 is the sweet spot for conversion.

### Final: Targeting

Only target vendors who meet BOTH conditions:

| Condition | Threshold | Rationale |
|---|---|---|
| VPS ≥ 50 | Vendor must be active and healthy | Low-VPS vendors are inactive or churning — recommendations won't convert |
| gap_rev / vendor_GMV ≥ 1% | Opportunity must be material | If the gap is 0.01% of their GMV, it's not worth an email |

## Under-Merge Risk

| Scenario | Rate | Impact | Mitigation |
|---|---|---|---|
| Conservative alias only | ~2-5% | False gap recommendations | Email copy: "may go by a different name" |
| Dual alias (conservative + aggressive) | ~1-2% | Aggressive catches packaging/format variants | +160,790 additional products merged |
| Irreducible under-merge | <1% | Semantic synonyms with zero character overlap | Accepted trade-off — NLP introduces worse over-merge risk |

Over-merge risk (recommending the WRONG product) remains <0.5% because regex requires exact merge key match.
