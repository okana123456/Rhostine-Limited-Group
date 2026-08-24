-- Confirmed Rhostine products use 25, 36, or at most 50 weekly instalments.
alter table public.rh_settings
  alter column max_loan_weeks set default 50;
