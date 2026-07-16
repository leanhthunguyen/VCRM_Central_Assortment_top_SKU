CREATE OR REPLACE TABLE `dh-darkstores-stg.local_shops_analytics.vendor_crm_comms_use_case_alias_table_GV_supply` AS

-- ══════════════════════════════════════════════════════════════════════════════
-- Product Alias Mapping — Glovo Platform SUPPLY (aggressive merge)
-- Markets: GV_IT, GV_ES, GV_PT, GV_UA, GV_PL, GV_RO, GV_GE, GV_KZ, GV_HR,
--          GV_RS, GV_BG, GV_MA, GV_CI, GV_KE, GV_UG, GV_GH, GV_AM, GV_AZ,
--          GV_BA, GV_ME, GV_MK, GV_XK
-- Language: Mixed — dual (local+EN) or English-only depending on market
-- Priority: Local language first (where available)
-- Purpose: Supply-side matching — adds packaging words (bottle, can, etc.)
--          + quality/temp/size descriptors to reduce false gaps
-- ══════════════════════════════════════════════════════════════════════════════

WITH

-- ── CONFIG: Market → script type mapping ─────────────────────────────────────
market_config AS (
  SELECT * FROM UNNEST([
    STRUCT('GV_IT'  AS geid, 'latin'    AS local_script, TRUE AS has_local),
    STRUCT('GV_ES', 'latin',    TRUE),
    STRUCT('GV_PT', 'latin',    TRUE),
    STRUCT('GV_UA', 'cyrillic', TRUE),
    STRUCT('GV_PL', 'latin',    TRUE),
    STRUCT('GV_RO', 'latin',    TRUE),
    STRUCT('GV_GE', 'georgian', TRUE),
    STRUCT('GV_KZ', 'cyrillic', TRUE),
    STRUCT('GV_HR', 'latin',    TRUE),
    STRUCT('GV_RS', 'cyrillic', TRUE),
    STRUCT('GV_BG', 'cyrillic', TRUE),
    STRUCT('GV_MA', 'latin',    TRUE),
    STRUCT('GV_CI', 'latin',    TRUE),
    STRUCT('GV_KE', 'none',     FALSE),
    STRUCT('GV_UG', 'none',     FALSE),
    STRUCT('GV_GH', 'none',     FALSE),
    STRUCT('GV_AM', 'armenian', TRUE),
    STRUCT('GV_AZ', 'none',     FALSE),
    STRUCT('GV_BA', 'latin',    TRUE),
    STRUCT('GV_ME', 'latin',    TRUE),
    STRUCT('GV_MK', 'cyrillic', TRUE),
    STRUCT('GV_XK', 'none',     FALSE)
  ])
),

-- ── CONFIG: Noise words per market (local language) — SUPPLY (aggressive) ───
noise_words_local AS (
  SELECT * FROM UNNEST([
    -- Italian: demand + packaging (bottiglia/bottiglie/lattina) + quality/temp/size
    STRUCT('GV_IT' AS geid, r'(confezione|busta|barattolo|vasetto|cartone|bibita|bevanda|gassata|birra|bottiglia|bottiglie|lattina|lattine|pet|vetro|plastica|naturale|classico|classica|originale|freddo|fredda|ghiacciato|grande|piccolo|piccola|medio|media)' AS noise_regex),
    -- Spanish: demand + packaging (botella/lata/sixpack/doypack) + quality/temp/size
    STRUCT('GV_ES', r'(gaseosa|bebida|refresco|cerveza|cervezas|bandeja|bolsa|sobre|descartable|retornable|botella|botellas|lata|latas|sixpack|doypack|pet|vidrio|plastico|natural|clasico|clasica|original|frio|fria|helado|helada|grande|chico|chica|mediano|mediana)'),
    -- Portuguese: demand + packaging (garrafa/lata) + quality/temp/size
    STRUCT('GV_PT', r'(pacote|saco|frasco|caixa|embalagem|pack|refrigerante|bebida|cerveja|garrafa|garrafas|lata|latas|pet|vidro|plastico|natural|clássico|clássica|original|frio|fria|gelado|gelada|grande|pequeno|pequena|médio|média)'),
    -- Ukrainian: demand + packaging (пляшка/банка) + quality/temp/size
    STRUCT('GV_UA', r'(пакет|пакування|коробка|лоток|картон|напій|газований|пляшка|банка|пластик|скло|натуральний|класичний|оригінальний|холодний|великий|малий|середній)'),
    -- Polish: demand + packaging (butelka/puszka) + quality/temp/size
    STRUCT('GV_PL', r'(opakowanie|torba|słoik|karton|napój|gazowany|piwo|butelka|puszka|pet|szkło|plastik|naturalny|klasyczny|oryginalny|zimny|schłodzony|duży|mały|średni)'),
    -- Romanian: demand + packaging (sticlă/doză) + quality/temp/size
    STRUCT('GV_RO', r'(pachet|pungă|borcan|cutie|carton|băutură|răcoritoare|bere|sticlă|doză|pet|sticlă|plastic|natural|clasic|original|rece|mare|mic|mediu)'),
    -- Georgian: demand + packaging (ბოთლი/ქილა) + quality/temp/size
    STRUCT('GV_GE', r'(პაკეტი|ყუთი|კოლოფი|სასმელი|გაზიანი|ბოთლი|ქილა|პლასტმასი|მინა|ნატურალური|კლასიკური|ორიგინალი|ცივი|დიდი|პატარა|საშუალო)'),
    -- Russian (Kazakhstan): demand + packaging (бутылка/банка) + quality/temp/size
    STRUCT('GV_KZ', r'(пакет|упаковка|коробка|лоток|картон|напиток|газированный|бутылка|банка|пластик|стекло|натуральный|классический|оригинальный|холодный|большой|маленький|средний)'),
    -- Croatian: demand + packaging (boca/limenka) + quality/temp/size
    STRUCT('GV_HR', r'(pakiranje|vrećica|staklenka|kutija|piće|gazirani|pivo|boca|limenka|pet|staklo|plastika|prirodni|klasični|originalni|hladan|hladna|velik|mali|srednji)'),
    -- Serbian: demand + packaging (flaša/limenka) + quality/temp/size
    STRUCT('GV_RS', r'(pakovanje|kesa|tegla|kutija|piće|gazirani|pivo|flaša|limenka|pet|staklo|plastika|prirodni|klasični|originalni|hladan|veliki|mali|srednji)'),
    -- Bulgarian: demand + packaging (бутилка/кутия) + quality/temp/size
    STRUCT('GV_BG', r'(пакет|буркан|напитка|газирана|бутилка|кутия|пластмаса|стъкло|натурален|класически|оригинален|студен|голям|малък|среден)'),
    -- French (Morocco, Ivory Coast): demand + packaging (bouteille/canette) + quality/temp/size
    STRUCT('GV_MA', r'(paquet|sachet|bocal|barquette|carton|flacon|pack|boisson|bouteille|canette|pet|verre|plastique|naturel|classique|original|froid|fraîche|grand|petit|moyen)'),
    STRUCT('GV_CI', r'(paquet|sachet|bocal|barquette|carton|flacon|pack|boisson|bouteille|canette|pet|verre|plastique|naturel|classique|original|froid|fraîche|grand|petit|moyen)'),
    -- Armenian: demand + packaging (շիշ/տուփ) + quality/temp/size
    STRUCT('GV_AM', r'(փաթեթ|տոպրակ|բաժակ|հատ|ըմպելիք|գազավորված|շիշ|տուփ|պլաստիկ|բնական|դասական|բնօրինալ|սառն|մեծ|փոքր|միին)'),
    -- Bosnian: demand + packaging (boca/limenka) + quality/temp/size
    STRUCT('GV_BA', r'(pakovanje|kesa|kutija|piće|gazirani|boca|limenka|pet|staklo|plastika|prirodni|klasični|originalni|hladan|velik|mali|srednji)'),
    -- Montenegrin: demand + packaging (flaša/limenka) + quality/temp/size
    STRUCT('GV_ME', r'(pakovanje|kesa|kutija|piće|gazirani|flaša|limenka|pet|staklo|plastika|prirodni|klasični|originalni|hladan|velik|mali|srednji)'),
    -- Macedonian: demand + packaging + quality/temp/size
    STRUCT('GV_MK', r'(шише|кутија|пакет|тегла|пиће|газиран|пластика|стакло|природен|класичен|оригинален|ладен|голем|мал|среден)')
  ])
),

-- ── STEP 1: ONE ROW PER (global_entity_id, catalog_master_product_id) ────────
raw_products AS (
  SELECT
    global_entity_id,
    catalog_master_product_id,
    NULLIF(TRIM(product_name_english), '') AS product_name_english,
    NULLIF(TRIM(product_name_local), '')   AS product_name_local,
    product_image_url,
    barcodes,
    master_product_created_at_utc,
    (SELECT COUNT(DISTINCT vp.platform_product_id)
     FROM UNNEST(vendor_products) AS vp
     WHERE vp.platform_product_id IS NOT NULL) AS platform_product_count
  FROM `fulfillment-dwh-production.cl_dmart.qc_catalog_products`
  WHERE global_entity_id IN (
    'GV_IT','GV_ES','GV_PT','GV_UA','GV_PL','GV_RO','GV_GE','GV_KZ',
    'GV_HR','GV_RS','GV_BG','GV_MA','GV_CI','GV_KE','GV_UG','GV_GH',
    'GV_AM','GV_AZ','GV_BA','GV_ME','GV_MK','GV_XK'
  )
  AND catalog_master_product_id IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY global_entity_id, catalog_master_product_id
    ORDER BY master_product_created_at_utc DESC NULLS LAST
  ) = 1
),

-- ── STEP 2: UNIT NORMALIZATION ───────────────────────────────────────────────
unit_normalized AS (
  SELECT
    rp.*,
    mc.local_script,
    mc.has_local,
    -- English unit normalization
    CASE WHEN rp.product_name_english IS NOT NULL THEN
      REGEXP_REPLACE(
      REGEXP_REPLACE(
      REGEXP_REPLACE(
      REGEXP_REPLACE(
      REGEXP_REPLACE(
      REGEXP_REPLACE(
      REGEXP_REPLACE(
      REGEXP_REPLACE(
      REGEXP_REPLACE(
      REGEXP_REPLACE(
      REGEXP_REPLACE(
      REGEXP_REPLACE(
        LOWER(TRIM(rp.product_name_english)),
        r'(\d+),(\d+)', r'\1.\2'),
        r'(\d+\.\d*[1-9])0+', r'\1'),
        r'(\d+)\.0+\b', r'\1'),
        r'(\d+\.?\d*)\s*(mililitros?|milliliters?|millilitres?|mls|ml)\b', r'\1ml'),
        r'(\d+\.?\d*)\s*(kilogramos?|kilograms?|kilos?|kgs|kg)\b', r'\1kg'),
        r'(\d+\.?\d*)\s*(gramos?|grams?|grs|gr|gs|g)\b', r'\1g'),
        r'(\d+\.?\d*)\s*(litros?|litres?|liters?|ltrs|ltr|lts|lt|l)\b', r'\1l'),
        r'(\d+\.?\d*)\s*(cm3|cc)\b', r'\1ml'),
        r'(\d+\.?\d*)\s*(onzas?|ounces?|ozs|oz)\b', r'\1oz'),
        r'(\d+\.?\d*)\s*(unidades|unidad|unid|und|units?|un)\b', r'\1un'),
        r'(\d+\.?\d*)\s*(piezas?|pzas|pzs|pz|pieces?|pcs|pc)\b', r'\1pz'),
        r'x\s*(\d+)\s*(un|pz)\b', r'x\1')
    END AS eng_unit_normalized,
    -- Local: lowercase + basic numeric normalization
    CASE WHEN rp.product_name_local IS NOT NULL AND mc.has_local THEN
      REGEXP_REPLACE(
      REGEXP_REPLACE(
      REGEXP_REPLACE(
      REGEXP_REPLACE(
        LOWER(TRIM(rp.product_name_local)),
        r'(\d+),(\d+)', r'\1.\2'),
        r'(\d+\.\d*[1-9])0+', r'\1'),
        r'(\d+)\.0+\b', r'\1'),
        r'(\d+\.?\d*)\s*(ml|kg|g|l|oz)\b', r'\1\2')
    END AS local_normalized
  FROM raw_products rp
  JOIN market_config mc ON rp.global_entity_id = mc.geid
),

-- ── STEP 2b: CONVERT cl → ml ─────────────────────────────────────────────────
cl_converted AS (
  SELECT * REPLACE (
    CASE
      WHEN eng_unit_normalized IS NOT NULL AND REGEXP_CONTAINS(eng_unit_normalized, r'\d+\.?\d*cl')
      THEN REGEXP_REPLACE(
        eng_unit_normalized,
        r'(\d+\.?\d*)cl',
        CONCAT(CAST(CAST(SAFE_CAST(REGEXP_EXTRACT(eng_unit_normalized, r'(\d+\.?\d*)cl') AS FLOAT64) * 10 AS INT64) AS STRING), 'ml')
      )
      ELSE eng_unit_normalized
    END AS eng_unit_normalized,
    CASE
      WHEN local_normalized IS NOT NULL AND REGEXP_CONTAINS(local_normalized, r'\d+\.?\d*cl')
      THEN REGEXP_REPLACE(
        local_normalized,
        r'(\d+\.?\d*)cl',
        CONCAT(CAST(CAST(SAFE_CAST(REGEXP_EXTRACT(local_normalized, r'(\d+\.?\d*)cl') AS FLOAT64) * 10 AS INT64) AS STRING), 'ml')
      )
      ELSE local_normalized
    END AS local_normalized
  )
  FROM unit_normalized
),

-- ── STEP 3: AGGRESSIVE NOISE REMOVAL (supply) ───────────────────────────────
noise_removed AS (
  SELECT u.*,
    -- English: demand words + packaging (bottle/can) + quality/temp/size
    CASE WHEN u.eng_unit_normalized IS NOT NULL THEN
      REGEXP_REPLACE(
        u.eng_unit_normalized,
        r'\b(pack|packs|box|boxes|bag|bags|jar|jars|pouch|pouches|tin|tins|tray|trays|packet|packets|carton|cartons|sachet|sachets|tube|tubes|bottle|bottles|can|cans|beer|pet|glass|tetra|plastic|natural|classic|original|regular|cold|chilled|frozen|fresh|large|small|medium|slim|mini)\b',
        ''
      )
    END AS eng_clean,
    -- Local noise removal (market-specific regex from config — supply aggressive)
    CASE WHEN u.local_normalized IS NOT NULL AND nw.noise_regex IS NOT NULL THEN
      CASE
        -- Latin-script markets: use \b word boundaries
        WHEN u.local_script = 'latin' THEN
          REGEXP_REPLACE(u.local_normalized, CONCAT(r'\b', nw.noise_regex, r'\b'), '')
        -- Non-Latin (Cyrillic, Georgian, Armenian): no \b
        ELSE
          REGEXP_REPLACE(u.local_normalized, nw.noise_regex, '')
      END
    ELSE u.local_normalized
    END AS local_clean
  FROM cl_converted u
  LEFT JOIN noise_words_local nw ON u.global_entity_id = nw.geid
),

-- ── STEP 4: BUILD MERGE KEYS ─────────────────────────────────────────────────
normalized AS (
  SELECT *,
    -- English merge key (always Latin)
    CASE WHEN eng_clean IS NOT NULL
         AND LENGTH(TRIM(eng_clean)) > 4 THEN
      LOWER(TRIM(REGEXP_REPLACE(eng_clean, r'[^a-z0-9]', '')))
    END AS eng_merge_key,
    -- Local merge key (script-aware)
    CASE WHEN local_clean IS NOT NULL
         AND LENGTH(TRIM(local_clean)) > 4 THEN
      CASE
        WHEN local_script IN ('cyrillic','georgian','armenian') THEN
          LOWER(TRIM(REGEXP_REPLACE(local_clean, r'[^\p{L}\p{N}]', '')))
        ELSE
          LOWER(TRIM(REGEXP_REPLACE(local_clean, r'[^a-z0-9À-ɏ]', '')))
      END
    END AS local_merge_key,
    COALESCE(product_name_english, product_name_local) AS product_name,
    REGEXP_EXTRACT(
      COALESCE(eng_clean, local_clean),
      r'(\d+\.?\d*\s*(?:ml|l|g|kg|un|pz|oz|x\d+))\s*$'
    ) AS extracted_size
  FROM noise_removed
),

-- ── STEP 5: BUILD ALIAS GROUPS (EITHER language matches = merged) ────────────
-- Build local and English groups independently, then union all merge edges
local_groups AS (
  SELECT
    global_entity_id,
    local_merge_key AS merge_key,
    'local' AS merge_language,
    ARRAY_AGG(catalog_master_product_id ORDER BY platform_product_count DESC, catalog_master_product_id LIMIT 1)[OFFSET(0)] AS alias_product_id,
    COUNT(DISTINCT catalog_master_product_id) AS num_variants,
    APPROX_TOP_COUNT(product_name, 1)[OFFSET(0)].value AS catalog_master_product_name_alias
  FROM normalized
  WHERE local_merge_key IS NOT NULL AND LENGTH(local_merge_key) > 4
  GROUP BY global_entity_id, local_merge_key
  HAVING COUNT(DISTINCT catalog_master_product_id) >= 2
),

-- English groups built independently (NO exclusion of local-merged products)
eng_groups AS (
  SELECT
    n.global_entity_id,
    n.eng_merge_key AS merge_key,
    'english' AS merge_language,
    ARRAY_AGG(n.catalog_master_product_id ORDER BY n.platform_product_count DESC, n.catalog_master_product_id LIMIT 1)[OFFSET(0)] AS alias_product_id,
    COUNT(DISTINCT n.catalog_master_product_id) AS num_variants,
    APPROX_TOP_COUNT(n.product_name, 1)[OFFSET(0)].value AS catalog_master_product_name_alias
  FROM normalized n
  WHERE n.eng_merge_key IS NOT NULL AND LENGTH(n.eng_merge_key) > 4
  GROUP BY n.global_entity_id, n.eng_merge_key
  HAVING COUNT(DISTINCT n.catalog_master_product_id) >= 2
),

-- Union all merge edges: product → alias from EITHER language
-- A product that matches in both languages gets the alias with the most variants
all_merge_edges AS (
  SELECT n.global_entity_id, n.catalog_master_product_id,
    lg.alias_product_id, lg.catalog_master_product_name_alias, lg.num_variants, 'merged_local' AS match_method
  FROM normalized n
  JOIN local_groups lg ON n.global_entity_id = lg.global_entity_id AND n.local_merge_key = lg.merge_key
  WHERE n.local_merge_key IS NOT NULL

  UNION ALL

  SELECT n.global_entity_id, n.catalog_master_product_id,
    eg.alias_product_id, eg.catalog_master_product_name_alias, eg.num_variants, 'merged_english' AS match_method
  FROM normalized n
  JOIN eng_groups eg ON n.global_entity_id = eg.global_entity_id AND n.eng_merge_key = eg.merge_key
  WHERE n.eng_merge_key IS NOT NULL
),

-- Pick the best merge for each product (prefer the group with more variants)
best_merge AS (
  SELECT * FROM all_merge_edges
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY global_entity_id, catalog_master_product_id
    ORDER BY num_variants DESC, match_method ASC
  ) = 1
),

-- ── STEP 6: MAP EVERY PRODUCT TO ITS ALIAS GROUP OR SINGLETON ────────────────
master_to_alias AS (
  SELECT
    n.global_entity_id,
    n.catalog_master_product_id,
    COALESCE(bm.alias_product_id, n.catalog_master_product_id) AS alias_product_id,
    COALESCE(bm.catalog_master_product_name_alias, n.product_name) AS catalog_master_product_name_alias,
    COALESCE(bm.num_variants, 1) AS num_variants,
    COALESCE(bm.match_method, 'singleton') AS match_method,
    COALESCE(n.local_merge_key, n.eng_merge_key) AS merge_key,
    n.extracted_size,
    n.product_name,
    n.product_name_english,
    n.product_name_local,
    n.product_image_url,
    n.barcodes,
    n.master_product_created_at_utc,
    n.platform_product_count
  FROM normalized n
  LEFT JOIN best_merge bm
    ON n.global_entity_id = bm.global_entity_id
    AND n.catalog_master_product_id = bm.catalog_master_product_id
),

-- ── STEP 7: LATEST METADATA PER ALIAS GROUP ─────────────────────────────────
primary_metadata AS (
  SELECT
    global_entity_id,
    alias_product_id,
    product_name_local   AS primary_name_local,
    product_name_english AS primary_name_english,
    product_image_url    AS primary_image_url,
    (SELECT MIN(b.barcode) FROM UNNEST(barcodes) AS b
     WHERE b.barcode IS NOT NULL AND b.barcode != '') AS primary_barcode,
    master_product_created_at_utc AS primary_created_at
  FROM master_to_alias
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY global_entity_id, alias_product_id
    ORDER BY platform_product_count DESC, master_product_created_at_utc DESC NULLS LAST
  ) = 1
),

-- ── STEP 7b: BEST IMAGE URL FALLBACK ────────────────────────────────────────
best_image AS (
  SELECT
    global_entity_id,
    alias_product_id,
    product_image_url AS fallback_image_url
  FROM master_to_alias
  WHERE product_image_url IS NOT NULL AND TRIM(product_image_url) != ''
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY global_entity_id, alias_product_id
    ORDER BY platform_product_count DESC, master_product_created_at_utc DESC NULLS LAST
  ) = 1
)

-- ── FINAL OUTPUT ─────────────────────────────────────────────────────────────
SELECT
  m.global_entity_id,
  m.catalog_master_product_id,
  m.product_name_english  AS master_product_name_english,
  m.product_name_local    AS master_product_name_local,
  m.alias_product_id,
  m.catalog_master_product_name_alias,
  m.num_variants,
  m.match_method,
  m.merge_key,
  m.extracted_size,
  lm.primary_name_local,
  lm.primary_name_english,
  lm.primary_barcode,
  COALESCE(lm.primary_image_url, bi.fallback_image_url) AS primary_image_url,
  lm.primary_created_at
FROM master_to_alias m
LEFT JOIN primary_metadata lm
  ON m.global_entity_id = lm.global_entity_id
  AND m.alias_product_id = lm.alias_product_id
LEFT JOIN best_image bi
  ON m.global_entity_id = bi.global_entity_id
  AND m.alias_product_id = bi.alias_product_id
ORDER BY
  m.global_entity_id,
  CASE
    WHEN m.match_method = 'merged_local' THEN 1
    WHEN m.match_method = 'merged_english' THEN 2
    ELSE 3
  END,
  m.num_variants DESC, m.alias_product_id, m.catalog_master_product_id
