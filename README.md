# Confido AE Take-Home

This project builds a standardized invoice line items model from the provided Snowflake source data.

## Model

`invoice_line_items`

Grain: one row per invoice line item.

The model enriches invoice line items with Confido internal product and global customer information where a deterministic mapping is available.

## Key modeling decisions

- External invoice items are mapped to Confido products only when an item maps to exactly one product.
- Ambiguous or unavailable product mappings are left null rather than selecting an arbitrary product.
- Invoice customers are mapped through contacts using the external customer ID. If a contact does not have a global customer directly, the model falls back to the global customer associated with its parent contact.
- Remote IDs are scoped by `company_detail_id` where applicable.
- Distribution center is not included because the provided data does not contain a deterministic invoice-to-distribution-center mapping.
- `TOTAL_AMOUNT` from the source invoice line item is used as the line item dollar amount.