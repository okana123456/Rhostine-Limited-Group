begin;

create table if not exists public.rh_member_documents (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.rh_businesses(id),
  member_id uuid not null references public.rh_members(id) on delete restrict,
  category text not null check (category in ('profile','business','chattels')),
  storage_path text not null unique,
  original_name text not null,
  mime_type text not null check (mime_type in ('image/jpeg','image/png','image/webp','application/pdf')),
  byte_size integer not null check (byte_size > 0 and byte_size <= 1048576),
  created_by uuid references public.rh_staff(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint rh_member_documents_storage_path_scope
    check (storage_path like business_id::text||'/'||member_id::text||'/'||category||'/%')
);

alter table public.rh_member_documents
  add column if not exists updated_at timestamptz not null default now();

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.rh_member_documents'::regclass
      and conname='rh_member_documents_member_id_fkey' and confdeltype='r'
  ) then
    alter table public.rh_member_documents drop constraint if exists rh_member_documents_member_id_fkey;
    alter table public.rh_member_documents add constraint rh_member_documents_member_id_fkey
      foreign key(member_id) references public.rh_members(id) on delete restrict;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.rh_member_documents'::regclass
      and conname='rh_member_documents_storage_path_scope'
  ) then
    alter table public.rh_member_documents add constraint rh_member_documents_storage_path_scope
      check (storage_path like business_id::text||'/'||member_id::text||'/'||category||'/%');
  end if;
end $$;

create unique index if not exists rh_member_documents_one_profile
  on public.rh_member_documents(member_id)
  where category='profile';

create index if not exists rh_member_documents_member_category_idx
  on public.rh_member_documents(member_id,category,created_at desc);

create or replace function public.rh_enforce_member_document_limit()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.category in ('business','chattels') and (
    select count(*) from public.rh_member_documents
    where member_id=new.member_id and category=new.category
  ) >= 5 then
    raise exception 'A member can have no more than five % documents',new.category;
  end if;
  return new;
end $$;

drop trigger if exists rh_member_document_limit on public.rh_member_documents;
create trigger rh_member_document_limit
before insert on public.rh_member_documents
for each row execute function public.rh_enforce_member_document_limit();

alter table public.rh_member_documents enable row level security;

drop policy if exists rh_member_documents_business_access on public.rh_member_documents;
create policy rh_member_documents_business_access
on public.rh_member_documents
for all
to authenticated
using (business_id=public.rh_current_business_id())
with check (
  business_id=public.rh_current_business_id()
  and exists (
    select 1 from public.rh_members m
    where m.id=member_id and m.business_id=public.rh_current_business_id()
  )
);

grant select,insert,update,delete on public.rh_member_documents to authenticated;
revoke all on public.rh_member_documents from anon;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values (
  'rh-member-documents',
  'rh-member-documents',
  false,
  1048576,
  array['image/jpeg','image/png','image/webp','application/pdf']::text[]
)
on conflict (id) do update set
  public=false,
  file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists rh_member_documents_storage_select on storage.objects;
create policy rh_member_documents_storage_select
on storage.objects
for select
to authenticated
using (
  bucket_id='rh-member-documents'
  and (storage.foldername(name))[1]=public.rh_current_business_id()::text
);

drop policy if exists rh_member_documents_storage_insert on storage.objects;
create policy rh_member_documents_storage_insert
on storage.objects
for insert
to authenticated
with check (
  bucket_id='rh-member-documents'
  and (storage.foldername(name))[1]=public.rh_current_business_id()::text
  and (storage.foldername(name))[2] in (
    select id::text from public.rh_members
    where business_id=public.rh_current_business_id()
  )
  and (storage.foldername(name))[3] in ('profile','business','chattels')
);

drop policy if exists rh_member_documents_storage_update on storage.objects;
create policy rh_member_documents_storage_update
on storage.objects
for update
to authenticated
using (
  bucket_id='rh-member-documents'
  and (storage.foldername(name))[1]=public.rh_current_business_id()::text
)
with check (
  bucket_id='rh-member-documents'
  and (storage.foldername(name))[1]=public.rh_current_business_id()::text
  and (storage.foldername(name))[2] in (
    select id::text from public.rh_members
    where business_id=public.rh_current_business_id()
  )
  and (storage.foldername(name))[3] in ('profile','business','chattels')
);

drop policy if exists rh_member_documents_storage_delete on storage.objects;
create policy rh_member_documents_storage_delete
on storage.objects
for delete
to authenticated
using (
  bucket_id='rh-member-documents'
  and (storage.foldername(name))[1]=public.rh_current_business_id()::text
);

do $$
begin
  if exists (select 1 from pg_publication where pubname='supabase_realtime')
    and not exists (
      select 1 from pg_publication_tables
      where pubname='supabase_realtime' and schemaname='public' and tablename='rh_member_documents'
    ) then
    alter publication supabase_realtime add table public.rh_member_documents;
  end if;
end $$;

commit;
