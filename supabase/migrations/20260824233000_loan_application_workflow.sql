begin;

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
  on public.rh_loan_applications(member_id)
  where status in ('pending','approved');

create index if not exists rh_loan_applications_business_status_idx
  on public.rh_loan_applications(business_id,status,application_date desc);

create index if not exists rh_loan_applications_officer_idx
  on public.rh_loan_applications(officer_id,application_date desc);

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

alter table public.rh_loan_applications enable row level security;

drop policy if exists rh_loan_applications_select on public.rh_loan_applications;
create policy rh_loan_applications_select
on public.rh_loan_applications
for select
to authenticated
using (
  business_id=public.rh_current_business_id()
  and (
    public.rh_current_staff_role()='admin'
    or officer_id=public.rh_current_staff_id()
  )
);

revoke insert, update, delete on public.rh_loan_applications from anon, authenticated;
grant select on public.rh_loan_applications to authenticated;
revoke insert on public.rh_loans from anon, authenticated;

create or replace function public.rh_submit_loan_application(
  p_member_id uuid,
  p_group_id uuid,
  p_application_date date,
  p_product_id text,
  p_notes text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller public.rh_staff%rowtype;
  v_member public.rh_members%rowtype;
  v_group public.rh_groups%rowtype;
  v_meeting_id uuid;
  v_application_id uuid;
  v_principal numeric(14,2);
  v_months integer;
  v_weeks integer;
  v_rate numeric(9,4);
  v_cycle integer;
  v_interest numeric(14,2);
  v_total numeric(14,2);
  v_weekly numeric(14,2);
  v_required_savings numeric(14,2);
  v_current_savings numeric(14,2);
  v_completed_loans integer;
  v_insurance numeric(14,2);
  v_other_fee numeric(14,2);
  v_upfront numeric(14,2);
  v_net numeric(14,2);
begin
  select * into v_caller
  from public.rh_staff
  where auth_user_id=auth.uid() and status='active';

  if v_caller.id is null or v_caller.role not in ('admin','officer') then
    raise exception 'Active staff access is required';
  end if;
  if v_caller.role='officer' and not coalesce((
    select can_issue_loans from public.rh_permissions where staff_id=v_caller.id
  ),false) then
    raise exception 'Loan application permission is required';
  end if;

  if p_application_date is null then
    raise exception 'Application date is required';
  end if;
  if p_application_date > (now() at time zone 'Africa/Nairobi')::date then
    raise exception 'Loan applications cannot be recorded in the future';
  end if;

  select * into v_group
  from public.rh_groups
  where id=p_group_id and business_id=v_caller.business_id and status='active';
  if v_group.id is null then raise exception 'Active group not found'; end if;
  if v_caller.role='officer' and v_group.officer_id is distinct from v_caller.id then
    raise exception 'This group is not assigned to the current officer';
  end if;

  select * into v_member
  from public.rh_members
  where id=p_member_id and business_id=v_caller.business_id and group_id=p_group_id
    and coalesce(status,'active')='active';
  if v_member.id is null then raise exception 'Active member not found in this group'; end if;

  if exists (select 1 from public.rh_loans where member_id=p_member_id and status='active') then
    raise exception 'This member already has an active loan';
  end if;
  if exists (select 1 from public.rh_loan_applications where member_id=p_member_id and status in ('pending','approved')) then
    raise exception 'This member already has an open loan application';
  end if;

  begin
    v_principal := split_part(p_product_id,'-',1)::numeric;
    v_months := split_part(p_product_id,'-',2)::integer;
  exception when others then
    raise exception 'Invalid loan product';
  end;

  if v_principal < 5000 or v_principal > 100000 or mod(v_principal,5000) <> 0 then
    raise exception 'Invalid loan amount';
  end if;
  if (v_principal <= 30000 and v_months <> 6)
    or (v_principal = 35000 and v_months <> 9)
    or (v_principal >= 40000 and v_months not in (6,9,12)) then
    raise exception 'Invalid loan term for this amount';
  end if;

  v_cycle := case when v_principal <= 30000 then 1 else 2 end;
  v_weeks := case v_months when 6 then 25 when 9 then 36 else 50 end;
  v_rate := case v_months when 6 then 18 when 9 then 20 else 24 end;
  v_interest := round(v_principal * v_rate / 100, 2);
  v_total := round(v_principal + v_interest, 2);
  v_weekly := round(v_total / v_weeks, 2);
  v_required_savings := case v_principal::integer
    when 5000 then 800 when 10000 then 1600 when 15000 then 2550
    when 20000 then 3500 when 25000 then 5000 when 30000 then 6600
    when 35000 then 9000 when 40000 then 10000 when 45000 then 11250
    when 50000 then 12500 when 55000 then 14000 when 60000 then 15000
    when 65000 then 16250
    else round(v_principal * 0.33, 2)
  end;
  v_insurance := round(v_total * 0.035, 2);
  v_other_fee := case when v_principal <= 35000 then 500 else round(v_principal * 0.015, 2) end;
  v_upfront := round(v_insurance + v_other_fee, 2);
  v_net := round(v_principal - v_upfront, 2);

  select coalesce(sum(amount),0) into v_current_savings
  from public.rh_savings
  where member_id=p_member_id and status='approved' and coalesce(type,'savings')='savings';

  select count(*) into v_completed_loans
  from public.rh_loans
  where member_id=p_member_id and status='completed';

  select id into v_meeting_id
  from public.rh_meetings
  where group_id=p_group_id and meeting_date=p_application_date;
  if v_meeting_id is null then
    insert into public.rh_meetings(business_id,group_id,meeting_date,recorded_by)
    values(v_caller.business_id,p_group_id,p_application_date,v_caller.id)
    on conflict (group_id,meeting_date) do nothing
    returning id into v_meeting_id;
    if v_meeting_id is null then
      select id into v_meeting_id from public.rh_meetings
      where group_id=p_group_id and meeting_date=p_application_date;
    end if;
  end if;

  insert into public.rh_loan_applications(
    business_id,member_id,group_id,meeting_id,officer_id,product_id,product_name,
    loan_cycle,loan_value,term_months,term_weeks,interest_rate,interest_amount,
    total_payable,weekly_installment,required_savings,savings_at_application,
    completed_loans_at_application,insurance_fee,other_fee,upfront_deductions,
    net_disbursement,application_date,notes
  ) values (
    v_caller.business_id,p_member_id,p_group_id,v_meeting_id,v_caller.id,p_product_id,
    'Cycle '||v_cycle||' Cash Loan - '||v_months||' Months',v_cycle,v_principal,
    v_months,v_weeks,v_rate,v_interest,v_total,v_weekly,v_required_savings,
    v_current_savings,v_completed_loans,v_insurance,v_other_fee,v_upfront,v_net,
    p_application_date,nullif(trim(p_notes),'')
  ) returning id into v_application_id;

  insert into public.rh_audit_log(business_id,staff_id,staff_name,action,entity,entity_id,new_value)
  values(v_caller.business_id,v_caller.id,v_caller.full_name,'submit_loan_application',
    'rh_loan_applications',v_application_id::text,
    jsonb_build_object('member_id',p_member_id,'product_id',p_product_id,'application_date',p_application_date));

  return v_application_id;
end $$;

create or replace function public.rh_review_loan_application(
  p_application_id uuid,
  p_action text,
  p_reason text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller public.rh_staff%rowtype;
  v_application public.rh_loan_applications%rowtype;
  v_savings numeric(14,2);
  v_completed integer;
begin
  select * into v_caller from public.rh_staff
  where auth_user_id=auth.uid() and status='active';
  if v_caller.id is null or v_caller.role<>'admin' then
    raise exception 'Administrator access is required';
  end if;

  select * into v_application from public.rh_loan_applications
  where id=p_application_id and business_id=v_caller.business_id
  for update;
  if v_application.id is null then raise exception 'Loan application not found'; end if;

  if lower(p_action)='approve' then
    if v_application.status<>'pending' then raise exception 'Only pending applications can be approved'; end if;
    if exists (select 1 from public.rh_loans where member_id=v_application.member_id and status='active') then
      raise exception 'This member already has an active loan';
    end if;
    select coalesce(sum(amount),0) into v_savings from public.rh_savings
    where member_id=v_application.member_id and status='approved' and coalesce(type,'savings')='savings';
    if v_savings < v_application.required_savings then
      raise exception 'Approved savings are below the required amount';
    end if;
    select count(*) into v_completed from public.rh_loans
    where member_id=v_application.member_id and status='completed';
    if v_application.loan_cycle=2 and v_completed<1 then
      raise exception 'A second-cycle loan requires one completed first-cycle loan';
    end if;

    update public.rh_loan_applications
    set status='approved',reviewed_by=v_caller.id,reviewed_at=now(),
      rejection_reason=null,updated_at=now()
    where id=v_application.id;
  elsif lower(p_action)='reject' then
    if v_application.status not in ('pending','approved') then
      raise exception 'Only pending or approved applications can be rejected';
    end if;
    if nullif(trim(p_reason),'') is null then raise exception 'A rejection reason is required'; end if;
    update public.rh_loan_applications
    set status='rejected',reviewed_by=v_caller.id,reviewed_at=now(),
      rejection_reason=trim(p_reason),updated_at=now()
    where id=v_application.id;
  else
    raise exception 'Review action must be approve or reject';
  end if;

  insert into public.rh_audit_log(business_id,staff_id,staff_name,action,entity,entity_id,old_value,new_value)
  values(v_caller.business_id,v_caller.id,v_caller.full_name,
    case when lower(p_action)='approve' then 'approve_loan_application' else 'reject_loan_application' end,
    'rh_loan_applications',v_application.id::text,
    jsonb_build_object('status',v_application.status),
    jsonb_build_object('status',case when lower(p_action)='approve' then 'approved' else 'rejected' end,'reason',p_reason));

  return v_application.id;
end $$;

create or replace function public.rh_disburse_loan_application(
  p_application_id uuid,
  p_disbursement_date date
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller public.rh_staff%rowtype;
  v_application public.rh_loan_applications%rowtype;
  v_loan_id uuid;
  v_savings numeric(14,2);
  v_completed integer;
begin
  select * into v_caller from public.rh_staff
  where auth_user_id=auth.uid() and status='active';
  if v_caller.id is null or v_caller.role<>'admin' then
    raise exception 'Administrator access is required';
  end if;

  select * into v_application from public.rh_loan_applications
  where id=p_application_id and business_id=v_caller.business_id
  for update;
  if v_application.id is null then raise exception 'Loan application not found'; end if;
  if v_application.status<>'approved' then raise exception 'The application must be approved before disbursement'; end if;
  if p_disbursement_date is null then raise exception 'Disbursement date is required'; end if;
  if p_disbursement_date < v_application.application_date then
    raise exception 'Disbursement date cannot be before the application date';
  end if;
  if p_disbursement_date > (now() at time zone 'Africa/Nairobi')::date then
    raise exception 'Disbursement date cannot be in the future';
  end if;
  if exists (select 1 from public.rh_loans where member_id=v_application.member_id and status='active') then
    raise exception 'This member already has an active loan';
  end if;

  select coalesce(sum(amount),0) into v_savings from public.rh_savings
  where member_id=v_application.member_id and status='approved' and coalesce(type,'savings')='savings';
  if v_savings < v_application.required_savings then
    raise exception 'Approved savings are below the required amount';
  end if;
  select count(*) into v_completed from public.rh_loans
  where member_id=v_application.member_id and status='completed';
  if v_application.loan_cycle=2 and v_completed<1 then
    raise exception 'A second-cycle loan requires one completed first-cycle loan';
  end if;

  insert into public.rh_loans(
    business_id,member_id,group_id,officer_id,product_name,asset_name,loan_cycle,
    loan_value,required_savings,insurance_amount,interest_amount,interest_rate,
    weekly_installment,total_payable,net_disbursement,term_weeks,start_date,
    expected_end_date,status,terms_source
  ) values (
    v_application.business_id,v_application.member_id,v_application.group_id,
    v_application.officer_id,v_application.product_name,null,v_application.loan_cycle,
    v_application.loan_value,v_application.required_savings,v_application.upfront_deductions,
    v_application.interest_amount,v_application.interest_rate,v_application.weekly_installment,
    v_application.total_payable,v_application.net_disbursement,v_application.term_weeks,
    p_disbursement_date,p_disbursement_date+(v_application.term_weeks*7),
    'active','confirmed'
  ) returning id into v_loan_id;

  update public.rh_loan_applications
  set status='disbursed',disbursement_date=p_disbursement_date,
    disbursed_by=v_caller.id,disbursed_at=now(),loan_id=v_loan_id,updated_at=now()
  where id=v_application.id;

  insert into public.rh_audit_log(business_id,staff_id,staff_name,action,entity,entity_id,new_value)
  values(v_caller.business_id,v_caller.id,v_caller.full_name,'disburse_loan_application',
    'rh_loans',v_loan_id::text,
    jsonb_build_object('application_id',v_application.id,'member_id',v_application.member_id,
      'loan_value',v_application.loan_value,'net_disbursement',v_application.net_disbursement,
      'disbursement_date',p_disbursement_date));

  return v_loan_id;
end $$;

revoke all on function public.rh_submit_loan_application(uuid,uuid,date,text,text) from public;
revoke all on function public.rh_review_loan_application(uuid,text,text) from public;
revoke all on function public.rh_disburse_loan_application(uuid,date) from public;
grant execute on function public.rh_submit_loan_application(uuid,uuid,date,text,text) to authenticated;
grant execute on function public.rh_review_loan_application(uuid,text,text) to authenticated;
grant execute on function public.rh_disburse_loan_application(uuid,date) to authenticated;

commit;
