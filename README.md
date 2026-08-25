# Rhostine Limited Groups

Professional group-lending operations system for cash loans, savings, repayments, meetings, remittances, expenses, staff controls and reporting.

Member registration supports a private profile photo plus categorized business and household-chattel evidence. PNG and JPG images are resized and compressed in the browser before upload; PDFs must be no more than 1 MB. Files are stored in a private, business-isolated Supabase bucket and opened only through short-lived signed links. The member profile includes visual image/PDF previews and confirmed controls to view, replace or delete each file.

The client subscription schedule begins on 1 October 2026. Admins receive a payment reminder on the 1st and 2nd of each month, with the unpaid-account restriction beginning on the 3rd.

## Loan model

- Officers submit loan applications for registered group members during meetings.
- Administrators approve or reject applications, then separately confirm cash disbursement.
- Only confirmed disbursement creates an active loan and repayment balance.
- Cycle 1 and Cycle 2 use fixed product bands reconstructed from the supplied schedules.
- Required savings, insurance, principal plus interest, weekly instalment and term are stored on each loan.
- Reconciled rows are explicitly marked provisional until management provides the signed product schedule.
- Inventory, supplier, purchase, order and asset-deposit workflows are excluded.

## Deployment order

1. Run `supabase/preflight-audit.sql` and retain the result.
2. Take a Supabase dashboard backup or a `pg_dump` before any live change.
3. Review and run `supabase/schema.sql`.
4. Apply files in `supabase/migrations/` in timestamp order.
5. Run `supabase/verify.sql` and confirm all checks pass.
6. Configure a valid project URL and anon key in `index.html`.
7. Deploy the static `index.html` and `assets/` directory.

For an existing installation, apply `supabase/migrations/20260825090000_member_documents.sql` after retaining the pre-migration backup. Its paired rollback refuses to run once any member document exists, preventing accidental file loss.

`supabase/rollback.sql` removes only an empty installation. It intentionally stops if any Rhostine operational table contains records.

## Local preview

Serve this directory with any static web server. The app has no build step.
