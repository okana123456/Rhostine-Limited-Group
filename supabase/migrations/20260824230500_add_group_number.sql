begin;

alter table public.rh_groups
  add column if not exists group_number integer;

with numbered as (
  select
    id,
    row_number() over (
      partition by business_id
      order by created_at, id
    )::integer as generated_group_number
  from public.rh_groups
  where group_number is null
)
update public.rh_groups as groups
set group_number = numbered.generated_group_number
from numbered
where groups.id = numbered.id;

alter table public.rh_groups
  alter column group_number set not null;

alter table public.rh_groups
  drop constraint if exists rh_groups_group_number_positive;

alter table public.rh_groups
  add constraint rh_groups_group_number_positive
  check (group_number > 0);

create unique index if not exists rh_groups_business_group_number_uidx
  on public.rh_groups (business_id, group_number);

commit;
