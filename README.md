# Rhostine Limited Groups

Professional group-lending operations system for cash loans, savings, repayments, meetings, remittances, expenses, staff controls and reporting.

The client subscription schedule begins on 1 October 2026. Admins receive a payment reminder on the 1st and 2nd of each month, with the unpaid-account restriction beginning on the 3rd.

## Loan model

- Loans are issued as cash to registered group members.
- Cycle 1 and Cycle 2 use fixed product bands reconstructed from the supplied schedules.
- Required savings, insurance, principal plus interest, weekly instalment and term are stored on each loan.
- Reconciled rows are explicitly marked provisional until management provides the signed product schedule.
- Inventory, supplier, purchase, order and asset-deposit workflows are excluded.

## Deployment order

1. Run `supabase/preflight-audit.sql` and retain the result.
2. Take a Supabase dashboard backup or a `pg_dump` before any live change.
3. Review and run `supabase/schema.sql`.
4. Run `supabase/verify.sql` and confirm all checks pass.
5. Configure a valid project URL and anon key in `index.html`.
6. Deploy the static `index.html` and `assets/` directory.

`supabase/rollback.sql` removes only an empty installation. It intentionally stops if any Rhostine operational table contains records.

## Local preview

Serve this directory with any static web server. The app has no build step.
