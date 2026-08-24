begin;

drop function if exists public.rh_disburse_loan_application(uuid,date);
drop function if exists public.rh_review_loan_application(uuid,text,text);
drop function if exists public.rh_submit_loan_application(uuid,uuid,date,text,text);
drop policy if exists rh_loan_applications_select on public.rh_loan_applications;
drop table if exists public.rh_loan_applications;
grant insert on public.rh_loans to authenticated;
drop function if exists public.rh_current_staff_role();
drop function if exists public.rh_current_staff_id();

commit;
