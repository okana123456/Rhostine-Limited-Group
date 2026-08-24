begin;

alter table public.rh_billing_cycles
  add column if not exists merchant_request_id text,
  add column if not exists checkout_request_id text unique,
  add column if not exists result_code integer,
  add column if not exists result_description text,
  add column if not exists amount_paid numeric(14,2),
  add column if not exists raw_callback jsonb;

commit;
