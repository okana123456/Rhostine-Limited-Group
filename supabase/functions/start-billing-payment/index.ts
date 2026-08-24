import { handleOptions, json } from "../_shared/http.ts";
import { requireBusinessAdmin } from "../_shared/supabase.ts";
import { accessToken, mpesaBaseUrl, normalizePhone, timestamp } from "../_shared/mpesa.ts";

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;
  if (req.method !== "POST") return json({ ok: false, error: "Method not allowed" }, 405);

  try {
    const { admin, staff } = await requireBusinessAdmin(req);
    const { phone } = await req.json();
    const environment = Deno.env.get("BILLING_MPESA_ENVIRONMENT") || "sandbox";
    const consumerKey = Deno.env.get("BILLING_MPESA_CONSUMER_KEY");
    const consumerSecret = Deno.env.get("BILLING_MPESA_CONSUMER_SECRET");
    const shortcode = Deno.env.get("BILLING_MPESA_SHORTCODE");
    const passkey = Deno.env.get("BILLING_MPESA_PASSKEY");
    const amount = Number(Deno.env.get("BILLING_AMOUNT") || "3000");
    if (!consumerKey || !consumerSecret || !shortcode || !passkey) {
      return json({ ok: false, error: "Subscription payment service is not configured yet." }, 503);
    }

    const normalizedPhone = normalizePhone(phone);
    const stamp = timestamp();
    const password = btoa(`${shortcode}${passkey}${stamp}`);
    const token = await accessToken(environment, consumerKey, consumerSecret);
    const callbackUrl = `${Deno.env.get("SUPABASE_URL")}/functions/v1/billing-callback`;
    const response = await fetch(`${mpesaBaseUrl(environment)}/mpesa/stkpush/v1/processrequest`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        BusinessShortCode: shortcode, Password: password, Timestamp: stamp,
        TransactionType: "CustomerPayBillOnline", Amount: amount,
        PartyA: normalizedPhone, PartyB: shortcode, PhoneNumber: normalizedPhone,
        CallBackURL: callbackUrl, AccountReference: "RUDDERDATA",
        TransactionDesc: "Rhostine subscription",
      }),
    });
    const result = await response.json();
    if (!response.ok || result.ResponseCode !== "0") throw new Error(result.errorMessage || result.ResponseDescription || "Payment prompt failed");

    const now = new Date();
    const cycleMonth = `${now.toLocaleString("en-CA", { timeZone: "Africa/Nairobi", year: "numeric" })}-${now.toLocaleString("en-CA", { timeZone: "Africa/Nairobi", month: "2-digit" })}-01`;
    const { error } = await admin.from("rh_billing_cycles").upsert({
      business_id: staff.business_id, billing_month: cycleMonth, status: "pending", phone: normalizedPhone,
      merchant_request_id: result.MerchantRequestID, checkout_request_id: result.CheckoutRequestID,
    }, { onConflict: "business_id,billing_month" });
    if (error) throw error;

    return json({ ok: true, message: "Payment prompt sent. Complete it on the phone." });
  } catch (error) {
    return json({ ok: false, error: error.message || "Payment prompt failed" }, 400);
  }
});
