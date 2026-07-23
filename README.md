# VCRM Central Assortment — Top SKU Recommendation

A recommendation engine that identifies the top popular products each vendor doesn't carry and estimates the revenue opportunity from adding them.

## Problem

Vendors are missing popular products that customers in their area are actively buying from competitors. If we identify these gaps and recommend the top products, vendors can add them and capture incremental revenue.

**Example:** In Buenos Aires, the #1 selling product in kiosks is "Paquete de Figuritas Panini Copa Mundial FIFA 2026". A kiosk vendor with 7,000 monthly sessions doesn't carry it — that's an estimated €2,900/month in missed revenue.

**Challenge:** The master product catalog has millions of duplicates (same product, different names). Without deduplication, demand rankings are fragmented and gap detection produces false positives. This is solved by the [Product Alias Table](https://github.com/leanhthunguyen/VCRM_Central_Assortment_Alias_table) — a prerequisite for this pipeline.

## How It Works

A 12-step pipeline that uses **two alias tables** (conservative for sales accuracy, aggressive for catalog matching) to find what's missing from each vendor's assortment.

```
Alias tables ──► Map products ──► Vendor catalog ──► Sales ranking ──► Gap detection ──► Top 3 per vendor
```

| Step | What it does | Alias used |
|---|---|---|
| 1 | Load both alias tables | Conservative + Aggressive |
| 2 | Map each product to its alias group | Both |
| 3 | Get product metadata (name, image, barcode) | Conservative |
| 3b | Bridge conservative ↔ aggressive alias IDs | Both |
| 4 | Get vendor dimensions (name, chain, city, vertical, GMV, VPS) | — |
| 5 | Find active SKUs (buyable rate > 0) | — |
| 6 | Build vendor catalog using aggressive matching | **Aggressive** |
| 7 | Aggregate sales (qty + revenue) per vendor × product | **Conservative** |
| 8 | Calculate market-level demand per (market, vertical, city) | Conservative |
| 9 | Exclude private label products (sold by only 1 chain) | Aggressive |
| 10 | Rank top 10 products per (market, vertical, city) | Conservative |
| 11 | Detect gaps: which top-10 products does each vendor NOT carry? | **Aggressive** |
| 12 | Pick top 3 gaps per vendor | — |

### Why Two Alias Tables

| | Conservative (Demand) | Aggressive (Supply) |
|---|---|---|
| **Purpose** | Sales aggregation — revenue must be accurate | Catalog matching — must catch all name variants |
| **Used for** | Steps 7-8, 10: ranking products by actual demand | Steps 6, 9, 11: checking if vendor carries a product |
| **Risk** | Under-counting: some sales split across unmerged IDs | Over-matching: two different products treated as one |

A **bridge CTE** connects the two: it maps conservative alias IDs to aggressive alias IDs via shared `catalog_master_product_id`, so demand rankings (conservative) can be compared against vendor catalogs (aggressive).

## Filters & Targeting

| Filter | Value | Applied at | Rationale |
|---|---|---|---|
| Dark store exclusion | `vertical NOT LIKE '%dark%'` | Step 4 | Dark stores managed centrally, not by vendor CRM |
| NKP vendors only | `is_key_partner IS FALSE` | Step 4 | Key partners have dedicated account managers |
| Buyable rate | > 0 | Step 5 | Product must have been available at least once |
| Revenue quality gate | avg revenue ≥ €100/vendor | Step 8 | Filter out very low-value items |
| Quantity quality gate | avg qty > 1/vendor | Step 8 | Filter accidental one-time purchases |
| Private label filter | ≥ 2 chains selling it | Step 9 | Exclude products only one chain can source |
| Top N products | Top 10 per (entity, vertical, city) | Step 10 | Focus on highest-demand products |
| Gaps per vendor | Top 3 | Step 12 | Actionable email limit — 3 is the sweet spot |
| VPS targeting | ≥ 50 | Final | Vendor must be active and healthy |
| Revenue uplift | gap_rev / vendor_GMV ≥ 1% | Final | Opportunity must be material |

## Output

One row per vendor with their top 3 gap products:

| Field | Description |
|---|---|
| Product name, image URL, barcode | Display info from conservative alias primary product |
| Market rank | Product's rank in the (market, vertical, city) |
| Total quantity sold | Market-level demand for this product |
| Estimated revenue opportunity | Weighted by vendor's session traffic |
| Vendor GMV, VPS | Context for the opportunity size |
| % uplift from gap products | gap_rev / vendor_GMV |

## Opportunity Sizing

| Platform | Estimated monthly opportunity (NKP vendors) |
|---|---|
| Pandora | €644,398 |
| Glovo | €876,657 |
| Peya | €1,198,416 |
| Talabat | €747,400 |
| **Total** | **€4,984,393** |

Total opportunity represents **3.2% of NKP vendor GMV** and **1.2% of all vendor GMV**.

## Platform Queries

| Query | Platform | Markets |
|---|---|---|
| `sql/py_skugap_q.sql` | Peya | 15 markets (Spanish) |
| `sql/tb_skugap_q.sql` | Talabat | 8 markets (Arabic + English) |
| `sql/hs_skugap_q.sql` | Hungerstation | 1 market (Arabic + English) |
| `sql/gv_skugap_q.sql` | Glovo | 22 markets (17 languages) |
| `sql/pd_skugap_q.sql` | Pandora | 16 markets (English + 6 local) |
| `sql/ef_skugap_q.sql` | Efood | 2 markets (Greek + English) |
| `sql/all_skugap_q.sql` | All platforms | All 64 markets (no entity filter) |

### Supporting Queries

| Query | Purpose |
|---|---|
| `sql/lookup_tables_create.sql` | Pre-materialized lookup tables — run ONCE after refreshing alias tables |
| `sql/gv_skugap_q_v2.sql` | Glovo SKU gap query v2 (uses consolidated alias tables directly) |

## BigQuery Tables

### Input Tables

| Table | Source |
|---|---|
| `vendor_crm_comms_use_case_alias_table_consevative` | Conservative alias — demand aggregation (all platforms incl. Glovo) |
| `vendor_crm_comms_use_case_alias_table_aggressive` | Aggressive alias — catalog matching (all platforms incl. Glovo) |
| `ls_vps_stg_monthly` | Vendor dimensions (GMV, VPS, vertical) |
| `daily_buyable_rate` | Product availability signals |

### Lookup Tables (pre-materialized)

The alias tables work at the `catalog_master_product_id` level, but orders and sales data work at the `platform_product_id` level. These are different IDs — multiple `platform_product_id` values are nested under one `catalog_master_product_id` in the catalog. Connecting them requires unnesting the 1.16 TB catalog table and joining both alias tables — a heavy operation.

The lookup tables do this join **once** and save the result, so recommendation queries just read a flat table instead of repeating the expensive join every run.

| Table | What it stores | Why |
|---|---|---|
| `vendor_crm_comms_product_alias_lookup` | One row per `platform_product_id` → its `demand_alias_id` + `supply_alias_id` | Avoids unnesting 1.16 TB catalog + joining both alias tables on every query run |
| `vendor_crm_comms_demand_supply_bridge` | Every `demand_alias_id` ↔ `supply_alias_id` pair | Avoids a 23M × 23M distinct join every query run |
| `vendor_crm_comms_product_metadata` | One row per alias group: name, image, barcode | Avoids re-reading the full alias table just for display info |

**Note:** `gv_skugap_q_v2.sql` does NOT use these lookup tables — it reads the alias tables directly and builds equivalent CTEs inline. All other v1 queries (`py_skugap_q.sql`, `tb_skugap_q.sql`, etc.) depend on the lookup tables.

## Refresh Process

1. Refresh alias tables (monthly, after catalog data updates)
2. Run `sql/lookup_tables_create.sql` to rebuild lookup/bridge/metadata tables (required for v1 queries, not needed for v2)
3. Run platform-specific SKU gap queries for the new month

## Known Limitations

| Limitation | Impact | Mitigation |
|---|---|---|
| ~1-2% under-merge (dual alias) | Some gap recommendations for products the vendor already sells under a different name | Email copy: "may go by a different name on your menu" |
| Efood has no buyable rate data | Cannot determine active SKUs → no recommendations for Efood | Need alternative active product signal |
| Glovo catalog size | 9M+ products — largest platform section | Consolidated with all platforms; runs in ~5-10 min per alias INSERT |

## Repository Structure

```
├── README.md
├── sql/
│   ├── py_skugap_q.sql              — Peya SKU gap query (15 markets)
│   ├── tb_skugap_q.sql              — Talabat SKU gap query (8 markets)
│   ├── hs_skugap_q.sql              — Hungerstation SKU gap query (1 market)
│   ├── gv_skugap_q.sql              — Glovo SKU gap query (22 markets)
│   ├── pd_skugap_q.sql              — Pandora SKU gap query (16 markets)
│   ├── ef_skugap_q.sql              — Efood SKU gap query (2 markets)
│   ├── all_skugap_q.sql             — All-platform SKU gap query (no entity filter)
│   ├── lookup_tables_create.sql     — Pre-materialized lookup tables (run after alias refresh)
│   └── gv_skugap_q_v2.sql          — Glovo SKU gap v2 (uses consolidated alias tables)
└── docs/
    ├── pipeline-logic.md            — 12-step pipeline walkthrough with filter rationale
    ├── email-template.md            — Vendor email copy and format
    ├── opportunity-sizing.md        — Revenue opportunity by market
    └── use-case-2-minimum-sku.md    — Minimum SKU compliance (Use Case 2)
```

> **Dependency:** This pipeline requires the [Product Alias Table](https://github.com/leanhthunguyen/VCRM_Central_Assortment_Alias_table) to be refreshed first.
