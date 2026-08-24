begin;

create extension if not exists pgcrypto;

create table if not exists public.rh_businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  group_number integer,
  status text not null default 'active' check (status in ('active','inactive')),
  created_at timestamptz not null default now()
);

create table if not exists public.rh_staff (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.rh_businesses(id),
  auth_user_id uuid unique,
  full_name text not null,
  email text,
  phone text,
  role text not null default 'officer' check (role in ('admin','officer')),
  status text not null default 'active' check (status in ('active','inactive')),
  pin_hash text,
  created_at timestamptz not null default now()
);

create table if not exists public.rh_permissions (
  staff_id uuid primary key references public.rh_staff(id) on delete cascade,
  business_id uuid not null references public.rh_businesses(id),
  can_manage_groups boolean not null default false,
  can_manage_members boolean not null default false,
  can_record_savings boolean not null default true,
  can_record_repayments boolean not null default true,
  can_issue_loans boolean not null default false,
  can_view_reports boolean not null default false,
  can_manage_staff boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists public.rh_settings (
  id text primary key,
  business_id uuid unique references public.rh_businesses(id),
  business_name text not null default 'Rhostine Limited Groups',
  receipt_footer text default 'Together We Rise',
  registration_fee numeric(14,2) not null default 200,
  savings_threshold numeric(14,2) not null default 1600,
  max_loan_weeks integer not null default 50,
  paybill_number text,
  paybill_account text,
  mpesa_environment text default 'sandbox',
  mpesa_consumer_key text,
  mpesa_consumer_secret text,
  mpesa_shortcode text,
  mpesa_passkey text,
  collections_callback_url text,
  updated_at timestamptz not null default now()
);

create table if not exists public.rh_groups (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.rh_businesses(id),
  name text not null,
  group_number integer not null check (group_number > 0),
  group_code text,
  location text,
  chairman_name text,
  chairman_phone text,
  treasurer_name text,
  treasurer_phone text,
  meeting_day text,
  meeting_time time,
  officer_id uuid references public.rh_staff(id),
  status text not null default 'active' check (status in ('active','inactive')),
  created_at timestamptz not null default now(),
  unique (business_id, name),
  unique (business_id, group_number),
  unique (business_id, group_code)
);

create table if not exists public.rh_members (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.rh_businesses(id),
  group_id uuid not null references public.rh_groups(id),
  full_name text not null,
  national_id text,
  phone text,
  alternate_phone text,
  email text,
  gender text,
  date_of_birth date,
  address text,
  nearest_town text,
  occupation text,
  employer text,
  income_estimate numeric(14,2),
  officer_id uuid references public.rh_staff(id),
  registration_fee numeric(14,2),
  registered_on date not null default current_date,
  status text not null default 'active' check (status in ('active','inactive')),
  created_at timestamptz not null default now(),
  unique (business_id, national_id)
);

create table if not exists public.rh_guarantors (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.rh_businesses(id),
  member_id uuid not null references public.rh_members(id) on delete cascade,
  full_name text not null,
  national_id text,
  phone text,
  location text,
  relationship text,
  position integer,
  created_at timestamptz not null default now()
);

create table if not exists public.rh_loans (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.rh_businesses(id),
  member_id uuid not null references public.rh_members(id),
  group_id uuid not null references public.rh_groups(id),
  officer_id uuid references public.rh_staff(id),
  product_name text not null,
  asset_name text,
  loan_cycle integer not null check (loan_cycle in (1,2)),
  loan_value numeric(14,2) not null check (loan_value > 0),
  required_savings numeric(14,2) not null default 0,
  insurance_amount numeric(14,2) not null default 0,
  interest_amount numeric(14,2) not null default 0,
  interest_rate numeric(9,4) not null default 0,
  weekly_installment numeric(14,2) not null check (weekly_installment > 0),
  total_payable numeric(14,2) not null check (total_payable >= loan_value),
  net_disbursement numeric(14,2) not null,
  term_weeks integer not null check (term_weeks between 1 and 52),
  start_date date not null,
  expected_end_date date not null,
  status text not null default 'active' check (status in ('active','completed','defaulted','transferred')),
  terms_source text not null default 'sheet' check (terms_source in ('sheet','reconciled','confirmed')),
  transferred_to uuid references public.rh_members(id),
  transferred_at timestamptz,
  created_at timestamptz not null default now()
);

create unique index if not exists rh_one_active_loan_per_member
  on public.rh_loans(member_id) where status='active';

create table if not exists public.rh_meetings (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.rh_businesses(id),
  group_id uuid not null references public.rh_groups(id),
  meeting_date date not null,
  recorded_by uuid references public.rh_staff(id),
  notes text,
  created_at timestamptz not null default now(),
  unique (group_id, meeting_date)
);

create table if not exists public.rh_loan_applications (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.rh_businesses(id),
  member_id uuid not null references public.rh_members(id),
  group_id uuid not null references public.rh_groups(id),
  meeting_id uuid references public.rh_meetings(id),
  officer_id uuid not null references public.rh_staff(id),
  product_id text not null,
  product_name text not null,
  loan_cycle integer not null check (loan_cycle in (1,2)),
  loan_value numeric(14,2) not null check (loan_value > 0),
  term_months integer not null check (term_months in (6,9,12)),
  term_weeks integer not null check (term_weeks in (25,36,50)),
  interest_rate numeric(9,4) not null,
  interest_amount numeric(14,2) not null,
  total_payable numeric(14,2) not null,
  weekly_installment numeric(14,2) not null,
  required_savings numeric(14,2) not null,
  savings_at_application numeric(14,2) not null default 0,
  completed_loans_at_application integer not null default 0,
  insurance_fee numeric(14,2) not null,
  other_fee numeric(14,2) not null,
  upfront_deductions numeric(14,2) not null,
  net_disbursement numeric(14,2) not null,
  application_date date not null,
  notes text,
  status text not null default 'pending' check (status in ('pending','approved','rejected','disbursed')),
  reviewed_by uuid references public.rh_staff(id),
  reviewed_at timestamptz,
  rejection_reason text,
  disbursement_date date,
  disbursed_by uuid references public.rh_staff(id),
  disbursed_at timestamptz,
  loan_id uuid unique references public.rh_loans(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists rh_one_open_loan_application_per_member
  on public.rh_loan_applications(member_id) where status in ('pending','approved');

do $$
begin
  if exists (select 1 from pg_publication where pubname='supabase_realtime')
    and not exists (
      select 1 from pg_publication_tables
      where pubname='supabase_realtime' and schemaname='public' and tablename='rh_loan_applications'
    ) then
    alter publication supabase_realtime add table public.rh_loan_applications;
  end if;
end $$;

create table if not exists public.rh_savings (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.rh_businesses(id),
  member_id uuid not null references public.rh_members(id),
  group_id uuid not null references public.rh_groups(id),
  meeting_id uuid references public.rh_meetings(id),
  meeting_date date not null,
  amount numeric(14,2) not null check (amount > 0),
  type text not null default 'savings' check (type in ('savings','registration')),
  status text not null default 'approved' check (status in ('pending','approved','rejected')),
  recorded_by uuid references public.rh_staff(id),
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.rh_repayments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.rh_businesses(id),
  loan_id uuid not null references public.rh_loans(id),
  member_id uuid not null references public.rh_members(id),
  group_id uuid not null references public.rh_groups(id),
  meeting_id uuid references public.rh_meetings(id),
  meeting_date date not null,
  amount numeric(14,2) not null check (amount > 0),
  principal numeric(14,2) not null default 0,
  interest numeric(14,2) not null default 0,
  status text not null default 'approved' check (status in ('pending','approved','rejected')),
  recorded_by uuid references public.rh_staff(id),
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.rh_reconciliations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.rh_businesses(id),
  group_id uuid not null references public.rh_groups(id),
  meeting_id uuid references public.rh_meetings(id),
  meeting_date date not null,
  total_savings numeric(14,2) not null default 0,
  total_repayments numeric(14,2) not null default 0,
  registration_total numeric(14,2) not null default 0,
  grand_total numeric(14,2) not null default 0,
  amount_remitted numeric(14,2) not null default 0,
  variance numeric(14,2) not null default 0,
  amount_matched text,
  actual_sms_amount numeric(14,2),
  actual_amount_received numeric(14,2),
  mpesa_transaction_id uuid,
  mpesa_reference text,
  status text not null default 'pending' check (status in ('pending','confirmed','rejected')),
  recorded_by uuid references public.rh_staff(id),
  logged_by uuid references public.rh_staff(id),
  confirmed_by uuid references public.rh_staff(id),
  confirmed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.rh_expenses (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.rh_businesses(id),
  date date not null default current_date,
  category text not null,
  description text,
  amount numeric(14,2) not null check (amount > 0),
  payment_method text,
  reference text,
  recorded_by uuid references public.rh_staff(id),
  created_at timestamptz not null default now()
);

create table if not exists public.rh_mpesa_transactions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references public.rh_businesses(id),
  group_id uuid references public.rh_groups(id),
  member_id uuid references public.rh_members(id),
  transaction_id text unique,
  trans_id text unique,
  transaction_time timestamptz,
  amount numeric(14,2) not null default 0,
  msisdn text,
  account_reference text,
  transaction_type text,
  allocation_status text default 'unallocated',
  allocated_table text,
  allocated_id uuid,
  raw_payload jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.rh_audit_log (
  id bigint generated always as identity primary key,
  business_id uuid references public.rh_businesses(id),
  staff_id uuid references public.rh_staff(id),
  action text not null,
  staff_name text,
  entity text,
  entity_id text,
  old_value jsonb,
  new_value jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.rh_billing_cycles (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.rh_businesses(id),
  billing_month date not null,
  status text not null default 'pending',
  paid_at timestamptz,
  paid_until date,
  receipt_number text,
  phone text,
  created_at timestamptz not null default now(),
  unique (business_id, billing_month)
);

create or replace function public.rh_current_business_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select business_id from public.rh_staff
  where auth_user_id = auth.uid() and status='active'
  limit 1
$$;

revoke all on function public.rh_current_business_id() from public;
grant execute on function public.rh_current_business_id() to authenticated;

create or replace function public.rh_current_staff_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from public.rh_staff
  where auth_user_id=auth.uid() and status='active'
  limit 1
$$;

create or replace function public.rh_current_staff_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role from public.rh_staff
  where auth_user_id=auth.uid() and status='active'
  limit 1
$$;

revoke all on function public.rh_current_staff_id() from public;
revoke all on function public.rh_current_staff_role() from public;
grant execute on function public.rh_current_staff_id() to authenticated;
grant execute on function public.rh_current_staff_role() to authenticated;

create or replace function public.rh_register_business_admin(
  p_auth_user_id uuid,
  p_business_name text,
  p_admin_name text,
  p_admin_email text,
  p_registration_key text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business_id uuid;
  v_staff_id uuid;
begin
  if auth.uid() is distinct from p_auth_user_id then
    raise exception 'Authenticated user mismatch';
  end if;
  if p_registration_key <> 'RHOSTINE2026' then
    raise exception 'Invalid registration key';
  end if;
  select business_id into v_business_id from public.rh_staff where auth_user_id=p_auth_user_id;
  if v_business_id is not null then return; end if;
  insert into public.rh_businesses(name) values(trim(p_business_name)) returning id into v_business_id;
  insert into public.rh_staff(business_id,auth_user_id,full_name,email,role)
  values(v_business_id,p_auth_user_id,trim(p_admin_name),lower(trim(p_admin_email)),'admin') returning id into v_staff_id;
  insert into public.rh_permissions(staff_id,business_id,can_manage_groups,can_manage_members,can_issue_loans,can_view_reports,can_manage_staff)
  values(v_staff_id,v_business_id,true,true,true,true,true);
  insert into public.rh_settings(id,business_id,business_name)
  values('biz_'||v_business_id::text,v_business_id,trim(p_business_name));
end $$;

revoke all on function public.rh_register_business_admin(uuid,text,text,text,text) from public;
grant execute on function public.rh_register_business_admin(uuid,text,text,text,text) to authenticated;

create or replace function public.rh_delete_staff_auth(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_target public.rh_staff%rowtype;
  v_caller public.rh_staff%rowtype;
begin
  select * into v_caller from public.rh_staff where auth_user_id=auth.uid() and status='active';
  if v_caller.id is null or v_caller.role<>'admin' then raise exception 'Administrator access required'; end if;
  if target_user_id=auth.uid() then raise exception 'You cannot remove your own administrator account'; end if;
  select * into v_target from public.rh_staff where auth_user_id=target_user_id and business_id=v_caller.business_id;
  if v_target.id is null then raise exception 'Staff account not found'; end if;
  update public.rh_staff set status='inactive',auth_user_id=null where id=v_target.id;
  delete from auth.users where id=target_user_id;
end $$;

revoke all on function public.rh_delete_staff_auth(uuid) from public;
grant execute on function public.rh_delete_staff_auth(uuid) to authenticated;

do $$
declare t text;
begin
  foreach t in array array[
    'rh_businesses','rh_staff','rh_permissions','rh_settings','rh_groups','rh_members','rh_guarantors',
    'rh_loans','rh_meetings','rh_loan_applications','rh_savings','rh_repayments','rh_reconciliations','rh_expenses',
    'rh_mpesa_transactions','rh_audit_log','rh_billing_cycles'
  ] loop
    execute format('alter table public.%I enable row level security',t);
  end loop;
end $$;

drop policy if exists rh_loan_applications_select on public.rh_loan_applications;
create policy rh_loan_applications_select on public.rh_loan_applications
for select to authenticated
using (
  business_id=public.rh_current_business_id()
  and (public.rh_current_staff_role()='admin' or officer_id=public.rh_current_staff_id())
);

revoke insert, update, delete on public.rh_loan_applications from anon, authenticated;
grant select on public.rh_loan_applications to authenticated;
revoke insert on public.rh_loans from anon, authenticated;

drop policy if exists rh_staff_business_access on public.rh_staff;
create policy rh_staff_business_access on public.rh_staff for all to authenticated
using (business_id=public.rh_current_business_id())
with check (business_id=public.rh_current_business_id());

drop policy if exists rh_businesses_access on public.rh_businesses;
create policy rh_businesses_access on public.rh_businesses for select to authenticated
using (id=public.rh_current_business_id());

do $$
declare t text;
begin
  foreach t in array array[
    'rh_permissions','rh_settings','rh_groups','rh_members','rh_guarantors','rh_loans','rh_meetings',
    'rh_savings','rh_repayments','rh_reconciliations','rh_expenses','rh_mpesa_transactions','rh_audit_log','rh_billing_cycles'
  ] loop
    execute format('drop policy if exists rh_business_access on public.%I',t);
    execute format('create policy rh_business_access on public.%I for all to authenticated using (business_id=public.rh_current_business_id()) with check (business_id=public.rh_current_business_id())',t);
  end loop;
end $$;

create index if not exists rh_members_group_idx on public.rh_members(group_id);
create index if not exists rh_loans_member_idx on public.rh_loans(member_id,status);
create index if not exists rh_loans_group_idx on public.rh_loans(group_id,status);
create index if not exists rh_loan_applications_business_status_idx on public.rh_loan_applications(business_id,status,application_date desc);
create index if not exists rh_loan_applications_officer_idx on public.rh_loan_applications(officer_id,application_date desc);
create index if not exists rh_savings_member_date_idx on public.rh_savings(member_id,meeting_date desc);
create index if not exists rh_repayments_loan_date_idx on public.rh_repayments(loan_id,meeting_date desc);
create index if not exists rh_reconciliations_group_date_idx on public.rh_reconciliations(group_id,meeting_date desc);

commit;
