begin;

do $$
begin
  if exists (
    select 1 from public.rh_member_documents
    where category='loan_form'
       or loan_application_id is not null
  ) then
    raise exception 'Rollback stopped: loan form document records exist. Preserve them or migrate them before reverting this change.';
  end if;
end $$;

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

drop index if exists public.rh_member_documents_application_idx;

alter table public.rh_member_documents
  drop constraint if exists rh_member_documents_loan_application_id_fkey;

alter table public.rh_member_documents
  drop column if exists loan_application_id;

alter table public.rh_member_documents
  drop constraint if exists rh_member_documents_category_check;

alter table public.rh_member_documents
  add constraint rh_member_documents_category_check
  check (category in ('profile','business','chattels'));

commit;
