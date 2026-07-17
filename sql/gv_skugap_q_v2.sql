-- ══════════════════════════════════════════════════════════════════════════════
-- SKU Gap Recommendation — Glovo Platform (per-platform alias tables)
-- Demand alias: vendor_crm_comms_use_case_alias_table_GV
-- Supply alias: vendor_crm_comms_use_case_alias_table_GV_supply
-- Markets: GV_IT,GV_ES,GV_PT,GV_UA,GV_PL,GV_RO,GV_GE,GV_KZ,GV_HR,GV_RS,GV_BG,GV_MA,GV_CI,GV_KE,GV_UG,GV_GH,GV_AM,GV_AZ,GV_BA,GV_ME,GV_MK,GV_XK
-- Period: May 2026
-- ══════════════════════════════════════════════════════════════════════════════

WITH

-- ─── STEP 1a: DEMAND ALIAS (conservative) ───────────────────────────────────
demand_alias AS (
  SELECT global_entity_id, catalog_master_product_id, alias_product_id
  FROM `dh-darkstores-stg.local_shops_analytics.vendor_crm_comms_use_case_alias_table_GV`
),

-- ─── STEP 1b: SUPPLY ALIAS (aggressive) ─────────────────────────────────────
supply_alias AS (
  SELECT global_entity_id, catalog_master_product_id, alias_product_id
  FROM `dh-darkstores-stg.local_shops_analytics.vendor_crm_comms_use_case_alias_table_GV_supply`
),

-- ─── STEP 2: PRODUCT METADATA ───────────────────────────────────────────────
product_metadata AS (
  SELECT DISTINCT
    global_entity_id, alias_product_id, catalog_master_product_name_alias,
    primary_name_local AS product_name_local, primary_name_english AS product_name_english,
    primary_barcode, primary_image_url AS product_image_url
  FROM `dh-darkstores-stg.local_shops_analytics.vendor_crm_comms_use_case_alias_table_GV`
  WHERE catalog_master_product_id = alias_product_id
),

-- ─── STEP 3: BRIDGE demand ↔ supply ─────────────────────────────────────────
demand_to_supply_bridge AS (
  SELECT DISTINCT
    d.global_entity_id,
    d.alias_product_id AS demand_alias_id,
    s.alias_product_id AS supply_alias_id
  FROM demand_alias d
  JOIN supply_alias s
    ON d.global_entity_id = s.global_entity_id
    AND d.catalog_master_product_id = s.catalog_master_product_id
),

-- ─── STEP 4a: MAP platform_product_id → DEMAND alias ────────────────────────
demand_product_to_alias AS (
  SELECT c.global_entity_id, vp.platform_product_id, al.alias_product_id
  FROM `fulfillment-dwh-production.cl_dmart.qc_catalog_products` c
  CROSS JOIN UNNEST(vendor_products) AS vp
  JOIN demand_alias al
    ON c.global_entity_id = al.global_entity_id
    AND c.catalog_master_product_id = al.catalog_master_product_id
  WHERE c.global_entity_id IN ('GV_IT','GV_ES','GV_PT','GV_UA','GV_PL','GV_RO','GV_GE','GV_KZ','GV_HR','GV_RS','GV_BG','GV_MA','GV_CI','GV_KE','GV_UG','GV_GH','GV_AM','GV_AZ','GV_BA','GV_ME','GV_MK','GV_XK')
    AND c.catalog_master_product_id IS NOT NULL
    AND vp.platform_product_id IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY c.global_entity_id, vp.platform_product_id
    ORDER BY c.master_product_created_at_utc DESC NULLS LAST
  ) = 1
),

-- ─── STEP 4b: MAP platform_product_id → SUPPLY alias ────────────────────────
supply_product_to_alias AS (
  SELECT c.global_entity_id, vp.platform_product_id, al.alias_product_id
  FROM `fulfillment-dwh-production.cl_dmart.qc_catalog_products` c
  CROSS JOIN UNNEST(vendor_products) AS vp
  JOIN supply_alias al
    ON c.global_entity_id = al.global_entity_id
    AND c.catalog_master_product_id = al.catalog_master_product_id
  WHERE c.global_entity_id IN ('GV_IT','GV_ES','GV_PT','GV_UA','GV_PL','GV_RO','GV_GE','GV_KZ','GV_HR','GV_RS','GV_BG','GV_MA','GV_CI','GV_KE','GV_UG','GV_GH','GV_AM','GV_AZ','GV_BA','GV_ME','GV_MK','GV_XK')
    AND c.catalog_master_product_id IS NOT NULL
    AND vp.platform_product_id IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY c.global_entity_id, vp.platform_product_id
    ORDER BY c.master_product_created_at_utc DESC NULLS LAST
  ) = 1
),

-- ─── STEP 5: VENDOR DIMENSIONS ──────────────────────────────────────────────
all_vendor_dims AS (
  SELECT DISTINCT
    global_entity_id, platform_vendor_id, vendor_name,
    chain_id, chain_name, vertical_segment, city, is_key_partner,
    menu_sessions, gmv_eur, vps_v11
  FROM `fulfillment-dwh-production.curated_data_shared_dmart.ls_vps_stg_monthly`
  WHERE global_entity_id IN ('GV_IT','GV_ES','GV_PT','GV_UA','GV_PL','GV_RO','GV_GE','GV_KZ','GV_HR','GV_RS','GV_BG','GV_MA','GV_CI','GV_KE','GV_UG','GV_GH','GV_AM','GV_AZ','GV_BA','GV_ME','GV_MK','GV_XK')
    AND report_month = '2026-05-01'
    AND LOWER(vertical) NOT LIKE '%dark%'
    AND is_key_partner IS NOT TRUE
),
vendor_sessions_lookup AS (
  SELECT global_entity_id, platform_vendor_id,
    MAX(COALESCE(menu_sessions, 0)) AS menu_sessions
  FROM all_vendor_dims
  GROUP BY global_entity_id, platform_vendor_id
),
vendor_gmv AS (
  SELECT global_entity_id, platform_vendor_id,
    MAX(COALESCE(gmv_eur, 0)) AS gmv_eur,
    MAX(COALESCE(vps_v11, 0)) AS vps_v11
  FROM all_vendor_dims
  GROUP BY global_entity_id, platform_vendor_id
),

-- ─── STEP 6: ACTIVE SKUs ────────────────────────────────────────────────────
active_skus AS (
  SELECT global_entity_id, platform_vendor_id, platform_product_id
  FROM `fulfillment-dwh-production.cl_dmart.daily_buyable_rate`
  WHERE global_entity_id IN ('GV_IT','GV_ES','GV_PT','GV_UA','GV_PL','GV_RO','GV_GE','GV_KZ','GV_HR','GV_RS','GV_BG','GV_MA','GV_CI','GV_KE','GV_UG','GV_GH','GV_AM','GV_AZ','GV_BA','GV_ME','GV_MK','GV_XK')
    AND date_ref >= '2026-05-01' AND date_ref <= '2026-05-31'
  GROUP BY ALL
  HAVING SUM(daily_buyable_rate_eligible_ref) > 0
),

-- ─── STEP 6b: VENDOR SKU COUNT (active products per vendor) ─────────────────
vendor_sku_count AS (
  SELECT global_entity_id, platform_vendor_id,
    COUNT(DISTINCT platform_product_id) AS vendor_active_skus
  FROM active_skus
  GROUP BY global_entity_id, platform_vendor_id
),

-- ─── STEP 7: VENDOR ACTIVE CATALOG via SUPPLY alias ─────────────────────────
all_vendor_active_products AS (
  SELECT DISTINCT
    a.global_entity_id, a.platform_vendor_id, pta.alias_product_id,
    v.vertical_segment, v.city, v.vendor_name, v.chain_id
  FROM active_skus a
  INNER JOIN all_vendor_dims v
    ON a.global_entity_id = v.global_entity_id AND a.platform_vendor_id = v.platform_vendor_id
  INNER JOIN supply_product_to_alias pta
    ON a.global_entity_id = pta.global_entity_id AND a.platform_product_id = pta.platform_product_id
),

-- ─── STEP 8: VENDOR SALES via DEMAND alias ──────────────────────────────────
all_active_products AS (
  SELECT DISTINCT
    a.global_entity_id, a.platform_vendor_id, a.platform_product_id,
    pta.alias_product_id,
    v.vertical_segment, v.city, v.chain_id
  FROM active_skus a
  INNER JOIN all_vendor_dims v
    ON a.global_entity_id = v.global_entity_id AND a.platform_vendor_id = v.platform_vendor_id
  INNER JOIN demand_product_to_alias pta
    ON a.global_entity_id = pta.global_entity_id AND a.platform_product_id = pta.platform_product_id
),
all_vendor_product_sales AS (
  SELECT
    ap.global_entity_id, ap.platform_vendor_id, ap.chain_id,
    ap.vertical_segment, ap.city, ap.alias_product_id,
    SUM(item.quantity_sold) AS quantity_sold,
    SUM(COALESCE(item.value_euro.total_amt_paid_eur, 0)) AS revenue_eur
  FROM `fulfillment-dwh-production.cl_dmart.qc_orders` o, UNNEST(o.items) AS item
  INNER JOIN all_active_products ap
    ON o.global_entity_id = ap.global_entity_id
    AND o.platform_vendor_id = ap.platform_vendor_id
    AND item.platform_product_id = ap.platform_product_id
  WHERE o.global_entity_id IN ('GV_IT','GV_ES','GV_PT','GV_UA','GV_PL','GV_RO','GV_GE','GV_KZ','GV_HR','GV_RS','GV_BG','GV_MA','GV_CI','GV_KE','GV_UG','GV_GH','GV_AM','GV_AZ','GV_BA','GV_ME','GV_MK','GV_XK')
    AND o.order_created_date_lt >= '2026-05-01' AND o.order_created_date_lt <= '2026-05-31'
    AND o.is_successful IS TRUE
  GROUP BY ALL
),

-- ─── STEP 9: MARKET-LEVEL METRICS + QUALITY GATE ────────────────────────────
product_market_metrics AS (
  SELECT
    s.global_entity_id, s.vertical_segment, s.city, s.alias_product_id,
    SUM(s.quantity_sold) AS total_quantity_sold,
    SUM(s.revenue_eur) AS total_revenue_eur,
    COUNT(DISTINCT s.platform_vendor_id) AS num_vendors_sold,
    SAFE_DIVIDE(SUM(s.revenue_eur), COUNT(DISTINCT s.platform_vendor_id)) AS flat_avg_revenue_eur,
    SAFE_DIVIDE(SUM(s.quantity_sold), COUNT(DISTINCT s.platform_vendor_id)) AS flat_avg_qty,
    SAFE_DIVIDE(SUM(s.revenue_eur), SUM(vs.menu_sessions)) AS rev_per_session
  FROM all_vendor_product_sales s
  LEFT JOIN vendor_sessions_lookup vs
    ON s.global_entity_id = vs.global_entity_id AND s.platform_vendor_id = vs.platform_vendor_id
  GROUP BY s.global_entity_id, s.vertical_segment, s.city, s.alias_product_id
  HAVING
    SAFE_DIVIDE(SUM(s.revenue_eur), COUNT(DISTINCT s.platform_vendor_id)) >= 100
    AND SAFE_DIVIDE(SUM(s.quantity_sold), COUNT(DISTINCT s.platform_vendor_id)) > 1
),

-- ─── STEP 10: PRIVATE LABEL FILTER (≥2 chains) ─────────────────────────────
top_product_candidates AS (
  SELECT
    pmm.global_entity_id, pmm.vertical_segment, pmm.city, pmm.alias_product_id,
    pmm.total_quantity_sold, pmm.flat_avg_revenue_eur, pmm.flat_avg_qty, pmm.rev_per_session,
    COUNT(DISTINCT avap.chain_id) AS num_chains
  FROM product_market_metrics pmm
  JOIN demand_to_supply_bridge bridge
    ON pmm.global_entity_id = bridge.global_entity_id
    AND pmm.alias_product_id = bridge.demand_alias_id
  JOIN all_vendor_active_products avap
    ON bridge.global_entity_id = avap.global_entity_id
    AND bridge.supply_alias_id = avap.alias_product_id
    AND pmm.vertical_segment = avap.vertical_segment
    AND pmm.city = avap.city
  GROUP BY
    pmm.global_entity_id, pmm.vertical_segment, pmm.city, pmm.alias_product_id,
    pmm.total_quantity_sold, pmm.flat_avg_revenue_eur, pmm.flat_avg_qty, pmm.rev_per_session
  HAVING COUNT(DISTINCT avap.chain_id) >= 2
),

-- ─── STEP 11: TOP 10 PRODUCTS PER DIMENSION ─────────────────────────────────
top10_products AS (
  SELECT *,
    RANK() OVER (
      PARTITION BY global_entity_id, vertical_segment, city
      ORDER BY total_quantity_sold DESC
    ) AS sku_rank
  FROM top_product_candidates
  QUALIFY RANK() OVER (
    PARTITION BY global_entity_id, vertical_segment, city
    ORDER BY total_quantity_sold DESC
  ) <= 10
),

-- ─── STEP 12: GAP DETECTION ─────────────────────────────────────────────────
all_vendors_by_dim AS (
  SELECT DISTINCT global_entity_id, platform_vendor_id, vendor_name, vertical_segment, city
  FROM all_vendor_active_products
),
vendor_product_gap AS (
  SELECT
    t.global_entity_id, t.vertical_segment, t.city,
    v.platform_vendor_id, v.vendor_name,
    t.alias_product_id, t.sku_rank,
    t.total_quantity_sold, t.num_chains,
    t.flat_avg_revenue_eur, t.flat_avg_qty, t.rev_per_session,
    COALESCE(vs.menu_sessions, 0) AS vendor_sessions,
    ROUND(t.rev_per_session * COALESCE(vs.menu_sessions, 0), 2) AS weighted_est_revenue_eur,
    COALESCE(vg.gmv_eur, 0) AS vendor_gmv_eur,
    COALESCE(vg.vps_v11, 0) AS vps_v11
  FROM top10_products t
  INNER JOIN all_vendors_by_dim v
    ON t.global_entity_id = v.global_entity_id
    AND t.vertical_segment = v.vertical_segment
    AND t.city = v.city
  LEFT JOIN vendor_sessions_lookup vs
    ON v.global_entity_id = vs.global_entity_id AND v.platform_vendor_id = vs.platform_vendor_id
  LEFT JOIN vendor_gmv vg
    ON v.global_entity_id = vg.global_entity_id AND v.platform_vendor_id = vg.platform_vendor_id
  WHERE NOT EXISTS (
    SELECT 1
    FROM all_vendor_active_products avap
    JOIN demand_to_supply_bridge bridge
      ON avap.global_entity_id = bridge.global_entity_id
      AND avap.alias_product_id = bridge.supply_alias_id
    WHERE bridge.global_entity_id = v.global_entity_id
      AND bridge.demand_alias_id = t.alias_product_id
      AND avap.platform_vendor_id = v.platform_vendor_id
  )
),

-- ─── STEP 13: PER-VENDOR TOP-3 GAPS ─────────────────────────────────────────
top3_gaps AS (
  SELECT *,
    ROW_NUMBER() OVER (
      PARTITION BY global_entity_id, vertical_segment, city, platform_vendor_id
      ORDER BY sku_rank ASC
    ) AS vendor_gap_rank
  FROM vendor_product_gap
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY global_entity_id, vertical_segment, city, platform_vendor_id
    ORDER BY sku_rank ASC
  ) <= 3
),
top3_enriched AS (
  SELECT g.*,
    pm.catalog_master_product_name_alias,
    pm.product_name_local,
    pm.product_name_english,
    pm.primary_barcode,
    pm.product_image_url
  FROM top3_gaps g
  LEFT JOIN product_metadata pm
    ON g.global_entity_id = pm.global_entity_id
    AND g.alias_product_id = pm.alias_product_id
)

-- ─── FINAL OUTPUT ────────────────────────────────────────────────────────────
SELECT
  global_entity_id, vertical_segment, city,
  platform_vendor_id, vendor_name, vendor_sessions,
  MAX(vendor_gmv_eur) AS vendor_gmv_eur,

  MAX(CASE WHEN vendor_gap_rank = 1 THEN alias_product_id END) AS gap1_alias_product_id,
  MAX(CASE WHEN vendor_gap_rank = 1 THEN catalog_master_product_name_alias END) AS gap1_product_name_alias,
  MAX(CASE WHEN vendor_gap_rank = 1 THEN product_name_english END) AS gap1_product_name_en,
  MAX(CASE WHEN vendor_gap_rank = 1 THEN product_name_local END) AS gap1_product_name_local,
  MAX(CASE WHEN vendor_gap_rank = 1 THEN sku_rank END) AS gap1_market_rank,
  MAX(CASE WHEN vendor_gap_rank = 1 THEN total_quantity_sold END) AS gap1_market_qty_sold,
  MAX(CASE WHEN vendor_gap_rank = 1 THEN ROUND(flat_avg_revenue_eur, 2) END) AS gap1_flat_avg_rev_eur,
  MAX(CASE WHEN vendor_gap_rank = 1 THEN weighted_est_revenue_eur END) AS gap1_weighted_est_rev_eur,
  MAX(CASE WHEN vendor_gap_rank = 1 THEN num_chains END) AS gap1_num_chains,
  MAX(CASE WHEN vendor_gap_rank = 1 THEN primary_barcode END) AS gap1_barcode,
  MAX(CASE WHEN vendor_gap_rank = 1 THEN product_image_url END) AS gap1_image_url,

  MAX(CASE WHEN vendor_gap_rank = 2 THEN alias_product_id END) AS gap2_alias_product_id,
  MAX(CASE WHEN vendor_gap_rank = 2 THEN catalog_master_product_name_alias END) AS gap2_product_name_alias,
  MAX(CASE WHEN vendor_gap_rank = 2 THEN product_name_english END) AS gap2_product_name_en,
  MAX(CASE WHEN vendor_gap_rank = 2 THEN product_name_local END) AS gap2_product_name_local,
  MAX(CASE WHEN vendor_gap_rank = 2 THEN sku_rank END) AS gap2_market_rank,
  MAX(CASE WHEN vendor_gap_rank = 2 THEN total_quantity_sold END) AS gap2_market_qty_sold,
  MAX(CASE WHEN vendor_gap_rank = 2 THEN ROUND(flat_avg_revenue_eur, 2) END) AS gap2_flat_avg_rev_eur,
  MAX(CASE WHEN vendor_gap_rank = 2 THEN weighted_est_revenue_eur END) AS gap2_weighted_est_rev_eur,
  MAX(CASE WHEN vendor_gap_rank = 2 THEN num_chains END) AS gap2_num_chains,
  MAX(CASE WHEN vendor_gap_rank = 2 THEN primary_barcode END) AS gap2_barcode,
  MAX(CASE WHEN vendor_gap_rank = 2 THEN product_image_url END) AS gap2_image_url,

  MAX(CASE WHEN vendor_gap_rank = 3 THEN alias_product_id END) AS gap3_alias_product_id,
  MAX(CASE WHEN vendor_gap_rank = 3 THEN catalog_master_product_name_alias END) AS gap3_product_name_alias,
  MAX(CASE WHEN vendor_gap_rank = 3 THEN product_name_english END) AS gap3_product_name_en,
  MAX(CASE WHEN vendor_gap_rank = 3 THEN product_name_local END) AS gap3_product_name_local,
  MAX(CASE WHEN vendor_gap_rank = 3 THEN sku_rank END) AS gap3_market_rank,
  MAX(CASE WHEN vendor_gap_rank = 3 THEN total_quantity_sold END) AS gap3_market_qty_sold,
  MAX(CASE WHEN vendor_gap_rank = 3 THEN ROUND(flat_avg_revenue_eur, 2) END) AS gap3_flat_avg_rev_eur,
  MAX(CASE WHEN vendor_gap_rank = 3 THEN weighted_est_revenue_eur END) AS gap3_weighted_est_rev_eur,
  MAX(CASE WHEN vendor_gap_rank = 3 THEN num_chains END) AS gap3_num_chains,
  MAX(CASE WHEN vendor_gap_rank = 3 THEN primary_barcode END) AS gap3_barcode,
  MAX(CASE WHEN vendor_gap_rank = 3 THEN product_image_url END) AS gap3_image_url,

  ROUND(COALESCE(MAX(CASE WHEN vendor_gap_rank = 1 THEN weighted_est_revenue_eur END), 0)
      + COALESCE(MAX(CASE WHEN vendor_gap_rank = 2 THEN weighted_est_revenue_eur END), 0)
      + COALESCE(MAX(CASE WHEN vendor_gap_rank = 3 THEN weighted_est_revenue_eur END), 0), 2) AS total_weighted_est_rev_eur,

  ROUND(SAFE_DIVIDE(
    COALESCE(MAX(CASE WHEN vendor_gap_rank = 1 THEN weighted_est_revenue_eur END), 0)
  + COALESCE(MAX(CASE WHEN vendor_gap_rank = 2 THEN weighted_est_revenue_eur END), 0)
  + COALESCE(MAX(CASE WHEN vendor_gap_rank = 3 THEN weighted_est_revenue_eur END), 0),
    MAX(vendor_gmv_eur)
  ) * 100, 2) AS pct_of_vendor_gmv,

  MAX(vps_v11) AS vps_v11

FROM top3_enriched
GROUP BY global_entity_id, vertical_segment, city, platform_vendor_id, vendor_name, vendor_sessions
)

-- ─── FINAL: Add SKU count + threshold + dual use-case targeting ─────────────
SELECT f.*,
  COALESCE(vsc.vendor_active_skus, 0) AS vendor_active_skus,
  COALESCE(st.mature_threshold, 0) AS mature_threshold,

  CASE
    WHEN f.vps_v11 >= 50
     AND COALESCE(vsc.vendor_active_skus, 0) >= 0.8 * COALESCE(st.mature_threshold, 999999)
     AND f.pct_of_vendor_gmv >= 1
    THEN TRUE ELSE FALSE
  END AS targeted_usecase1,

  CASE
    WHEN f.vps_v11 >= 50
     AND COALESCE(vsc.vendor_active_skus, 0) < 0.8 * COALESCE(st.mature_threshold, 999999)
    THEN TRUE ELSE FALSE
  END AS targeted_usecase2

FROM final_output f
LEFT JOIN vendor_sku_count vsc
  ON f.global_entity_id = vsc.global_entity_id
  AND f.platform_vendor_id = vsc.platform_vendor_id
LEFT JOIN `dh-darkstores-stg.local_shops_analytics.vendor_crm_comms_sku_threshold` st
  ON f.global_entity_id = st.global_entity_id
  AND f.vertical_segment = st.vertical_segment
ORDER BY f.global_entity_id, f.vertical_segment, f.city, f.platform_vendor_id
