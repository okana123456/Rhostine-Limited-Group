begin;

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

revoke all on function public.rh_review_loan_application(uuid,text,text) from public;
revoke all on function public.rh_disburse_loan_application(uuid,date) from public;
grant execute on function public.rh_review_loan_application(uuid,text,text) to authenticated;
grant execute on function public.rh_disburse_loan_application(uuid,date) to authenticated;

commit;
