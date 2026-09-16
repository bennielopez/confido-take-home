# Model Walkthrough

## Overview

The goal was to build a clean invoice line-item model that connects external accounting-system data to Confido's internal entities where possible.

### Source Landscape

| Core Invoice Data | External → Internal Bridges | Internal Confido Entities |
| --- | --- | --- |
| `invoices` | `items` | `products` |
| `invoice_items` | `contacts` | `global_customers` |
|  |  | `distribution_centers` |

Additional tables explored:
`product_prices`, `product_relationships`, `product_shipping_configs`

### Target Grain

**One row per invoice item**

`invoice_items.id` → `invoice_line_item_id`

The goal throughout the modeling process was to enrich each invoice line without changing this grain.

### Mapping Approach

> Map internal entities where the data supports a clear relationship.  
> Leave ambiguous mappings unresolved rather than force a potentially incorrect mapping.

---

## Product Mapping

### Mapping Path

```text
invoice_items.item_remote_id
            │
            ▼
      items.remote_id
            │
         items.id
            │
            ▼
     products.item_id
```

The item-to-product relationship is not always one-to-one.

Example:

```text
                     ┌── Product A
                     ├── Product B
Yogurt ──────────────├── Product C
                     ├── Product D
                     └── Product E
```

The provided data does not reliably identify which of these products belongs to a particular invoice line.

**Approach:** map an item to a product only when it is associated with exactly one Confido product.

Ambiguous product mappings remain `NULL`.

Prevents a 1:M product relationship turning a single invoice line into multiple rows.

---

## Global Customer Mapping

### Direct Mapping

```text
invoice.customer_remote_id
            │
            ▼
    contacts.remote_id
            │
            ▼
 contacts.global_customer_id
            │
            ▼
    global_customers.id
```

Some contacts do not have their own `global_customer_id`, but their parent contact does.

### Parent Fallback

```text
Invoice
   │
   ▼
Contact
   │
   │ parent_remote_id
   ▼
Parent Contact
   │
   ▼
Global Customer
```

Example:

**KeHE distribution-center contact → KeHE parent contact → KeHE global customer**

The mapping prioritizes:

```text
contact.global_customer_id
          │
          │ if NULL
          ▼
parent_contact.global_customer_id
```

Customer-name matching isn't used as an additional fallback - names aren't necessarily unique / standardized.

---

## Distribution Center

The most direct potential mapping was:

```text
Invoice
   │
   ▼
Contact
   │
   │ distribution_center_id
   ▼
Distribution Center
```

But `contacts.distribution_center_id` wasn't populated in the data.

Using global customer alone also doesn't identify a specific distribution center:

```text
                         ┌── Distribution Center A
Global Customer ─────────├── Distribution Center B
                         └── Distribution Center C
```

A global customer can have multiple distribution centers, so this relationship could both assign an unsupported distribution center + duplicate invoice lines.

**Approach:** leave distribution center unresolved rather than force a mapping that the provided data cannot support.

---

## Final Invoice Line-Item Model

The final model starts from `invoice_items` and enriches each line with invoice context and the internal mappings above.

### Product Path

```text
┌──────────────────┐
│  invoice_items   │
│                  │
│    BASE GRAIN    │
└────────┬─────────┘
         │
         │ item_remote_id
         ▼
┌──────────────────┐
│      items       │
└────────┬─────────┘
         │
         │ item_id
         ▼
┌──────────────────┐
│ product_mapping  │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│     products     │
└──────────────────┘
```

### Customer Path

```text
┌──────────────────┐
│     invoices     │
└────────┬─────────┘
         │
         │ customer_remote_id
         ▼
┌──────────────────┐
│     contacts     │
└────────┬─────────┘
         │
    ┌────┴─────────────┐
    │                  │
    ▼                  ▼
Direct Customer    Parent Contact
    │                  │
    └────────┬─────────┘
             ▼
┌──────────────────┐
│ global_customers │
└──────────────────┘
```

### Final Grain

```text
invoice_items
      │
      ├──── invoice context
      │
      ├──── item / product enrichment
      │
      └──── customer enrichment
      │
      ▼
┌────────────────────────┐
│   invoice_line_items   │
│                        │
│  1 row / invoice item  │
└────────────────────────┘
```

### Join Pattern

External remote IDs are scoped by `company_detail_id` where applicable:

```text
remote_id + company_detail_id
```

This avoids assuming that an external remote ID is globally unique across every company in Confido.

Enrichment relationships use **LEFT JOINs** so an unresolved product or customer mapping doesn't remove an otherwise valid invoice line.

### Measures & Context

The model preserves:

- source `total_amount` as `invoice_line_item_amount`
- original invoice-item `quantity`
- invoice currency and created date
- source item name
- internal product ID and name where resolved
- internal global customer ID and name where resolved

---

## Validation

| Validation | Result |
| --- | ---: |
| Source invoice items | **2,527** |
| Final model rows | **2,527** |
| Unique invoice line-item IDs | **2,527** |
| Product mappings | **1,651** |
| Global customer mappings | **911** |
| Source rows with null quantity | **7** |

The final row count and unique line-item count confirm that the enrichment logic preserves the intended grain.

Reviewed mapping coverage was to distinguish expected unresolved mappings from broken joins.

The 7 null quantities already existed in the source and are preserved rather than imputed.

---

## Maintainability

Implementation is intentionally kept relatively simple:

- descriptive naming
- product and customer mapping logic separated into named CTEs
- comments around non-obvious modeling decisions
- dbt documentation and tests

For the scope of this model, the mapping logic remains together in a single model. If the mappings became more complex or were reused elsewhere, they could be extracted into reusable staging or intermediate models.

---

## Potential Extensions

### Distribution Center

Look for a source-system **ship-to, location, or warehouse identifier** that can map directly to an internal Confido distribution center.

### Product

Look for a more specific external **SKU or variant identifier** that can resolve one-to-many item-to-product relationships.

### dbt Architecture

If the entity-mapping logic becomes shared across downstream models, extract it into reusable dbt models.

---

> **Guiding principle:** preserve the invoice-line-item grain and only enrich where the data supports the mapping.
