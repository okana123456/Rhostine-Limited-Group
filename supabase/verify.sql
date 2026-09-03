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

select id,name,public,file_size_limit,allowed_mime_types
from storage.buckets
where id='rh-member-documents';

select policyname,cmd
from pg_policies
where schemaname='storage' and tablename='objects'
  and policyname like 'rh_member_documents_storage_%'
order by policyname;

select
  (select count(*) from public.rh_member_documents) as member_document_rows,
  (select count(*) from storage.objects where bucket_id='rh-member-documents') as stored_member_files;

select column_name,data_type,is_nullable
from information_schema.columns
where table_schema='public'
  and table_name='rh_member_documents'
  and column_name in ('loan_application_id','category','storage_path','byte_size')
order by column_name;

select conname, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid='public.rh_member_documents'::regclass
  and conname in ('rh_member_documents_category_check','rh_member_documents_loan_application_id_fkey');

select category,count(*) as rows
from public.rh_member_documents
group by category
order by category;

select routine_name
from information_schema.routines
where routine_schema='public' and routine_name in (
  'rh_current_business_id','rh_current_staff_id','rh_current_staff_role',
  'rh_register_business_admin','rh_delete_staff_auth',
  'rh_submit_loan_application','rh_review_loan_application','rh_disburse_loan_application'
)
order by routine_name;

select
  'review_allows_admin_second_cycle_migration' as check_name,
  position('A second-cycle loan requires one completed first-cycle loan' in pg_get_functiondef('public.rh_review_loan_application(uuid,text,text)'::regprocedure)) = 0 as passed
union all
select
  'disburse_allows_admin_second_cycle_migration',
  position('A second-cycle loan requires one completed first-cycle loan' in pg_get_functiondef('public.rh_disburse_loan_application(uuid,date)'::regprocedure)) = 0;

select
  has_table_privilege('authenticated','public.rh_loan_applications','select') as applications_select_allowed,
  has_table_privilege('authenticated','public.rh_loan_applications','insert') as direct_application_insert_allowed,
  has_table_privilege('authenticated','public.rh_loans','insert') as direct_loan_insert_allowed;
