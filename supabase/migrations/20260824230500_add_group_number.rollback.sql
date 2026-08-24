begin;

drop index if exists public.rh_groups_business_group_number_uidx;

alter table public.rh_groups
  drop constraint if exists rh_groups_group_number_positive;

alter table public.rh_groups
  drop column if exists group_number;

commit;
