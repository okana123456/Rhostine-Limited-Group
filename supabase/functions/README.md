# Rhostine Edge Functions

Supabase supplies `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` to hosted Edge Functions automatically. Never commit or expose the service-role key in the frontend.

## Collections secrets

- `COLLECTIONS_MPESA_ENVIRONMENT`: `sandbox` or `production`
- `COLLECTIONS_MPESA_CONSUMER_KEY`
- `COLLECTIONS_MPESA_CONSUMER_SECRET`
- `COLLECTIONS_MPESA_SHORTCODE`

## Subscription billing secrets

- `BILLING_MPESA_ENVIRONMENT`: `sandbox` or `production`
- `BILLING_MPESA_CONSUMER_KEY`
- `BILLING_MPESA_CONSUMER_SECRET`
- `BILLING_MPESA_SHORTCODE`
- `BILLING_MPESA_PASSKEY`
- `BILLING_AMOUNT`: defaults to `3000`

Set production values in Supabase Edge Function Secrets. Do not place them in `.env.example`, `index.html`, database settings, or GitHub.

## Functions

- `start-billing-payment`: authenticated admin endpoint that initiates the subscription STK prompt.
- `billing-callback`: public Safaricom callback that confirms the subscription result.
- `collections-callback`: public Safaricom C2B callback that records incoming Paybill transactions.
- `collections-register-urls`: authenticated admin endpoint that registers the collections callback URLs with Daraja.
