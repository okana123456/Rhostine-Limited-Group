begin;

do $$
begin
  if exists (select 1 from public.rh_member_documents limit 1)
    or exists (select 1 from storage.objects where bucket_id='rh-member-documents' limit 1) then
    raise exception 'Rollback stopped: member documents exist. Preserve the files and restore the pre-migration backup or perform a reviewed migration.';
  end if;
end $$;

drop policy if exists rh_member_documents_storage_delete on storage.objects;
drop policy if exists rh_member_documents_storage_update on storage.objects;
drop policy if exists rh_member_documents_storage_insert on storage.objects;
drop policy if exists rh_member_documents_storage_select on storage.objects;

delete from storage.buckets
where id='rh-member-documents'
  and not exists (select 1 from storage.objects where bucket_id='rh-member-documents');

drop table if exists public.rh_member_documents;
drop function if exists public.rh_enforce_member_document_limit();

commit;
