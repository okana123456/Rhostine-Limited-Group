import { json } from "../_shared/http.ts";
import { adminClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ ResultCode: 0, ResultDesc: "Accepted" });
  try {
    const payload = await req.json();
    const callback = payload?.Body?.stkCallback;
    if (!callback?.CheckoutRequestID) return json({ ResultCode: 0, ResultDesc: "Accepted" });
    const items = Object.fromEntries((callback.CallbackMetadata?.Item || []).map((item) => [item.Name, item.Value]));
    const paid = Number(callback.ResultCode) === 0;
    const update = {
      status: paid ? "paid" : "failed",
      result_code: Number(callback.ResultCode), result_description: callback.ResultDesc || null,
      raw_callback: payload,
    };
    if (paid) {
      update.paid_at = new Date().toISOString();
      update.paid_until = new Date(new Date().getFullYear(), new Date().getMonth() + 1, 0).toISOString().slice(0, 10);
      update.receipt_number = items.MpesaReceiptNumber || null;
      update.phone = items.PhoneNumber ? String(items.PhoneNumber) : null;
      update.amount_paid = Number(items.Amount || 0);
    }
    await adminClient().from("rh_billing_cycles").update(update).eq("checkout_request_id", callback.CheckoutRequestID);
  } catch (error) {
    console.error("Billing callback error", error);
  }
  return json({ ResultCode: 0, ResultDesc: "Accepted" });
});
