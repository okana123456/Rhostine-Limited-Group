begin;

alter table public.rh_member_documents
  add column if not exists loan_application_id uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid='public.rh_member_documents'::regclass
      and conname='rh_member_documents_loan_application_id_fkey'
  ) then
    alter table public.rh_member_documents
      add constraint rh_member_documents_loan_application_id_fkey
      foreign key (loan_application_id)
      references public.rh_loan_applications(id)
      on delete set null;
  end if;
end $$;

alter table public.rh_member_documents
  drop constraint if exists rh_member_documents_category_check;

alter table public.rh_member_documents
  add constraint rh_member_documents_category_check
  check (category in ('profile','business','chattels','loan_form'));

create index if not exists rh_member_documents_application_idx
  on public.rh_member_documents(loan_application_id,category,created_at desc);

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

  if new.category='loan_form' and new.loan_application_id is not null and (
    select count(*) from public.rh_member_documents
    where loan_application_id=new.loan_application_id and category='loan_form'
  ) >= 1 then
    raise exception 'A loan application can have no more than one scanned loan form';
  end if;

  return new;
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
  and (storage.foldername(name))[3] in ('profile','business','chattels','loan_form')
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
  and (storage.foldername(name))[3] in ('profile','business','chattels','loan_form')
);

commit;
