# Email Template — Vendor SKU Gap Recommendation

## Subject Line

> Your customers are searching for these products — are they on your menu?

## Email Body

> Hi {{vendor_name}},
>
> We noticed some popular products in your area that other shops are selling well but may be missing from your listing, or they may go by a different name. Shops with similar traffic in {{city}} are generating up to ~€{{sum_weighted_est_rev_eur}}/month from these items alone.
>
> **Here's what customers near you are buying:**
>
> | # | Product | Barcode | Image |
> |---|---|---|---|
> | 1 | {{product_1_name}} | {{product_1_barcode}} | [Link] |
> | 2 | {{product_2_name}} | {{product_2_barcode}} | [Link] |
> | 3 | {{product_3_name}} | {{product_3_barcode}} | [Link] |
>
> Revenue estimates are based on similar shops in your city with comparable traffic.
>
> **Don't have them yet?** Adding top-selling products is one of the fastest ways to grow your basket size.
>
> **How to add:**
> - Open your vendor portal
> - Search by barcode (listed above) or product name
> - Set your price and availability
>
> It only takes a few minutes — and your customers are already looking for these items.
>
> **Already have these?** Great — they're among the top sellers in your area. If any look unfamiliar but you carry a similar product under a different name, no worries — our recommendations are based on name matching, so slight variations can cause a mismatch.
>
> Questions? Reply to this email or reach out to your account manager.
>
> Happy selling,

## Template Variables

| Variable | Source | Description |
|---|---|---|
| `{{vendor_name}}` | `vendor_name` from Step 4 | Vendor display name |
| `{{city}}` | `city` from Step 4 | Vendor's city for local context |
| `{{sum_weighted_est_rev_eur}}` | Sum of `weighted_est_rev_eur` for top 3 gaps | Total estimated monthly revenue opportunity |
| `{{product_N_name}}` | `primary_name_local` or `primary_name_english` | Product display name from conservative alias metadata |
| `{{product_N_barcode}}` | `primary_barcode` | Barcode for easy vendor portal lookup |
| `{{product_N_image}}` | `primary_image_url` | Product image URL |

## Key Design Decisions

- **"may go by a different name"** — handles the ~1-2% under-merge case where the vendor already sells the product under a different name
- **Revenue framed as "shops with similar traffic"** — makes the estimate relatable and credible
- **Barcode included** — makes it easy for vendors to find the product in their portal without typing the full name
- **3 products max** — more than 3 overwhelms, fewer than 3 feels thin
- **"Already have these?" section** — preemptively addresses false positives without undermining credibility
