-- ══════════════════════════════════════════════════════════════════════════════
-- PRE-MATERIALIZED LOOKUP TABLES
-- Run ONCE after refreshing alias tables. Recommendation queries read these instead.
-- ══════════════════════════════════════════════════════════════════════════════

-- TABLE 1: platform_product_id → demand_alias_id + supply_alias_id
-- Replaces: qc_catalog_products CROSS JOIN UNNEST + both alias table JOINs
CREATE OR REPLACE TABLE `dh-darkstores-stg.local_shops_analytics.vendor_crm_comms_product_alias_lookup` AS
WITH
catalog_product_map AS (
  SELECT
    c.global_entity_id,
    c.catalog_master_product_id,
    vp.platform_product_id
  FROM `fulfillment-dwh-production.cl_dmart.qc_catalog_products` c
  CROSS JOIN UNNEST(vendor_products) AS vp
  WHERE c.catalog_master_product_id IS NOT NULL
    AND vp.platform_product_id IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY c.global_entity_id, vp.platform_product_id
    ORDER BY c.master_product_created_at_utc DESC NULLS LAST
  ) = 1
)
SELECT
  cpm.global_entity_id,
  cpm.platform_product_id,
  d.alias_product_id AS demand_alias_id,
  s.alias_product_id AS supply_alias_id
FROM catalog_product_map cpm
LEFT JOIN `dh-darkstores-stg.local_shops_analytics.vendor_crm_comms_use_case_alias_table_consevative` d
  ON cpm.global_entity_id = d.global_entity_id
  AND cpm.catalog_master_product_id = d.catalog_master_product_id
LEFT JOIN `dh-darkstores-stg.local_shops_analytics.vendor_crm_comms_use_case_alias_table_aggressive` s
  ON cpm.global_entity_id = s.global_entity_id
  AND cpm.catalog_master_product_id = s.catalog_master_product_id
;

-- TABLE 2: demand_alias_id → supply_alias_id bridge
-- Replaces: 22M × 22M DISTINCT JOIN computed on every query run
CREATE OR REPLACE TABLE `dh-darkstores-stg.local_shops_analytics.vendor_crm_comms_demand_supply_bridge` AS
SELECT DISTINCT
  d.global_entity_id,
  d.alias_product_id AS demand_alias_id,
  s.alias_product_id AS supply_alias_id
FROM `dh-darkstores-stg.local_shops_analytics.vendor_crm_comms_use_case_alias_table_consevative` d
JOIN `dh-darkstores-stg.local_shops_analytics.vendor_crm_comms_use_case_alias_table_aggressive` s
  ON d.global_entity_id = s.global_entity_id
  AND d.catalog_master_product_id = s.catalog_master_product_id
;

-- TABLE 3: product metadata (one row per alias group primary product)
-- Replaces: reading the full conservative alias table again for display info
CREATE OR REPLACE TABLE `dh-darkstores-stg.local_shops_analytics.vendor_crm_comms_product_metadata` AS
SELECT DISTINCT
  global_entity_id,
  alias_product_id,
  catalog_master_product_name_alias,
  primary_name_local    AS product_name_local,
  primary_name_english  AS product_name_english,
  primary_barcode,
  primary_image_url     AS product_image_url
FROM `dh-darkstores-stg.local_shops_analytics.vendor_crm_comms_use_case_alias_table_consevative`
WHERE catalog_master_product_id = alias_product_id
;
