-- Restore the previous default. This does not alter existing settings or loan rows.
alter table public.rh_settings
  alter column max_loan_weeks set default 52;
