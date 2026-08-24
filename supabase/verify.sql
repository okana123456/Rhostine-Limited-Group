select table_name
from information_schema.tables
where table_schema='public' and table_name like 'rh_%'
order by table_name;

select tablename, rowsecurity
from pg_tables
where schemaname='public' and tablename like 'rh_%'
order by tablename;

select tablename, count(*) as policy_count
from pg_policies
where schemaname='public' and tablename like 'rh_%'
group by tablename
order by tablename;

select routine_name
from information_schema.routines
where routine_schema='public' and routine_name in (
  'rh_current_business_id','rh_current_staff_id','rh_current_staff_role',
  'rh_register_business_admin','rh_delete_staff_auth',
  'rh_submit_loan_application','rh_review_loan_application','rh_disburse_loan_application'
)
order by routine_name;

select
  has_table_privilege('authenticated','public.rh_loan_applications','select') as applications_select_allowed,
  has_table_privilege('authenticated','public.rh_loan_applications','insert') as direct_application_insert_allowed,
  has_table_privilege('authenticated','public.rh_loans','insert') as direct_loan_insert_allowed;
