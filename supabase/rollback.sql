-- Guarded rollback for an unpopulated first installation.
-- Restore the pre-deployment backup instead when any live records exist.
do $$
declare
  populated text := '';
  t text;
  has_rows boolean;
begin
  foreach t in array array['rh_groups','rh_members','rh_loans','rh_savings','rh_repayments','rh_reconciliations','rh_expenses'] loop
    if to_regclass('public.'||t) is not null then
      execute format('select exists(select 1 from public.%I)',t) into has_rows;
      if has_rows then populated := concat_ws(', ',nullif(populated,''),t); end if;
    end if;
  end loop;
  if populated <> '' then
    raise exception 'Rollback stopped: live records exist in %. Restore from backup or perform a reviewed migration.', populated;
  end if;
end $$;

drop function if exists public.rh_register_business_admin(uuid,text,text,text,text);
drop function if exists public.rh_delete_staff_auth(uuid);
drop function if exists public.rh_current_business_id();
drop table if exists public.rh_billing_cycles;
drop table if exists public.rh_audit_log;
drop table if exists public.rh_mpesa_transactions;
drop table if exists public.rh_expenses;
drop table if exists public.rh_reconciliations;
drop table if exists public.rh_repayments;
drop table if exists public.rh_savings;
drop table if exists public.rh_meetings;
drop table if exists public.rh_loans;
drop table if exists public.rh_guarantors;
drop table if exists public.rh_members;
drop table if exists public.rh_groups;
drop table if exists public.rh_permissions;
drop table if exists public.rh_settings;
drop table if exists public.rh_staff;
drop table if exists public.rh_businesses;
