-- Read-only preflight. Run and save the output before applying schema.sql.
select now() as audited_at, current_database() as database_name, current_user as database_user;

select table_schema, table_name
from information_schema.tables
where table_schema = 'public'
order by table_name;

select schemaname, tablename, policyname, cmd
from pg_policies
where schemaname = 'public'
order by tablename, policyname;

select relname as table_name, n_live_tup as estimated_rows
from pg_stat_user_tables
order by relname;

select routine_name, routine_type
from information_schema.routines
where routine_schema = 'public'
order by routine_name;

