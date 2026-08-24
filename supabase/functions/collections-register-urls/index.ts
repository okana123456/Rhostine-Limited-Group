import { handleOptions, json } from "../_shared/http.ts";
import { requireBusinessAdmin } from "../_shared/supabase.ts";
import { accessToken, mpesaBaseUrl } from "../_shared/mpesa.ts";

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;
  if (req.method !== "POST") return json({ ok: false, error: "Method not allowed" }, 405);
  try {
    const { admin, staff } = await requireBusinessAdmin(req);
    const environment = Deno.env.get("COLLECTIONS_MPESA_ENVIRONMENT") || "sandbox";
    const consumerKey = Deno.env.get("COLLECTIONS_MPESA_CONSUMER_KEY");
    const consumerSecret = Deno.env.get("COLLECTIONS_MPESA_CONSUMER_SECRET");
    const shortcode = Deno.env.get("COLLECTIONS_MPESA_SHORTCODE");
    if (!consumerKey || !consumerSecret || !shortcode) return json({ ok: false, error: "Collections credentials are not configured yet." }, 503);

    const callbackUrl = `${Deno.env.get("SUPABASE_URL")}/functions/v1/collections-callback/${staff.business_id}`;
    const token = await accessToken(environment, consumerKey, consumerSecret);
    const response = await fetch(`${mpesaBaseUrl(environment)}/mpesa/c2b/v2/registerurl`, {
      method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ ShortCode: shortcode, ResponseType: "Completed", ConfirmationURL: callbackUrl, ValidationURL: callbackUrl }),
    });
    const result = await response.json();
    if (!response.ok) throw new Error(result.errorMessage || "Callback registration failed");
    await admin.from("rh_settings").update({ mpesa_environment: environment, mpesa_shortcode: shortcode, collections_callback_url: callbackUrl }).eq("business_id", staff.business_id);
    return json({ ok: true, message: "M-Pesa callback URLs registered.", callbackUrl });
  } catch (error) {
    return json({ ok: false, error: error.message || "Callback registration failed" }, 400);
  }
});
