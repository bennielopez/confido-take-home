{{ config(
    materialized='table'
) }}

with unique_product_item_ids as (
    -- only keep item IDs that map to exactly one confido product (ambiguous item-to-product mappings are intentionally left unresolved)
    select item_id
    from {{ source('confido_demo', 'products') }}
    where item_id is not null
    group by item_id
    having count(*) = 1
),

product_mapping as (
    select
        product.item_id,
        product.id as product_id,
        product.name as product_name
    from {{ source('confido_demo', 'products') }} product
    join unique_product_item_ids on product.item_id = unique_product_item_ids.item_id
),

customer_mapping as (
    -- contacts may map directly to a global customer or inherit the global customer associated with their parent contact
    select
        contact.remote_id as contact_remote_id,
        contact.company_detail_id,
        coalesce(contact.global_customer_id, parent_contact.global_customer_id) as global_customer_id
    from {{ source('confido_demo', 'contacts') }} contact
    left join {{ source('confido_demo', 'contacts') }} parent_contact
        on parent_contact.remote_id = contact.parent_remote_id
        and parent_contact.company_detail_id = contact.company_detail_id
),

invoice_line_items as (
    select
        -- invoice
        invoice.id as invoice_id,
        invoice.created_at as invoice_created_at,
        invoice.currency as invoice_currency,

        -- company detail
        invoice.company_detail_id,
        company_detail.name as company_detail_name,

        -- global customer
        global_customer.id as global_customer_id,
        global_customer.name as global_customer_name,

        -- line item
        invoice_item.id as invoice_line_item_id,
        item.name as invoice_item_name,
        product.product_id,
        product.product_name,
        invoice_item.quantity as invoice_item_quantity,
        invoice_item.total_amount as invoice_line_item_amount

    from {{ source('confido_demo', 'invoice_items') }} invoice_item
    left join {{ source('confido_demo', 'invoices') }} invoice on invoice_item.invoice_id = invoice.id
    left join {{ source('confido_demo', 'items') }} item
        on item.remote_id = invoice_item.item_remote_id
        and item.company_detail_id = invoice.company_detail_id
    left join {{ source('confido_demo', 'company_details') }} company_detail on company_detail.id = invoice.company_detail_id
    left join product_mapping product on product.item_id = item.id
    left join customer_mapping customer
        on customer.contact_remote_id = invoice.customer_remote_id
        and customer.company_detail_id = invoice.company_detail_id
    left join {{ source('confido_demo', 'global_customers') }} global_customer on global_customer.id = customer.global_customer_id
)

select
    invoice_id,
    invoice_created_at,
    invoice_currency,
    company_detail_id,
    company_detail_name,
    global_customer_id,
    global_customer_name,
    invoice_line_item_id,
    invoice_item_name,
    product_id,
    product_name,
    invoice_item_quantity,
    invoice_line_item_amount
from invoice_line_items