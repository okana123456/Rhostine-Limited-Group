begin;

do $$
begin
  if exists(select 1 from public.rh_billing_cycles) then
    raise exception 'Rollback stopped: billing records exist.';
  end if;
end $$;

alter table public.rh_billing_cycles
  drop column if exists raw_callback,
  drop column if exists amount_paid,
  drop column if exists result_description,
  drop column if exists result_code,
  drop column if exists checkout_request_id,
  drop column if exists merchant_request_id;

commit;
